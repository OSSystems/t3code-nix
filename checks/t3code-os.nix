{ self }:
{ pkgs, lib, ... }:

let
  domain = "t3.test";

  certs = pkgs.runCommand "t3code-os-test-certs" { nativeBuildInputs = [ pkgs.openssl ]; } ''
    mkdir $out
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 3650 \
      -subj "/CN=t3code-os test CA" -keyout ca.key -out $out/ca.crt
    openssl req -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
      -subj "/CN=*.${domain}" -keyout $out/server.key -out server.csr
    printf 'subjectAltName=DNS:*.${domain}\n' > ext
    openssl x509 -req -in server.csr -CA $out/ca.crt -CAkey ca.key -CAcreateserial \
      -days 3650 -extfile ext -out $out/server.crt
  '';

  users = {
    alice = 40001;
    bob = 40002;
  };
in
{
  name = "t3code-os";

  nodes = {
    server = {
      imports = [ self.nixosModules.t3code-os ];

      virtualisation.memorySize = 3072;
      networking.firewall.allowedTCPPorts = [ 443 ];

      services.t3code-os = {
        enable = true;
        inherit domain;
        virtualHost = {
          forceSSL = true;
          sslCertificate = "${certs}/server.crt";
          sslCertificateKey = "${certs}/server.key";
        };
        users = lib.mapAttrs (name: port: {
          inherit port;
          environment.T3OS_TEST_USER = name;
        }) users;
      };
    };

    client =
      { nodes, ... }:
      {
        security.pki.certificateFiles = [ "${certs}/ca.crt" ];
        networking.hosts.${nodes.server.networking.primaryIPAddress} = map (name: "${name}.${domain}") (
          lib.attrNames users
        );
        environment.systemPackages = [
          pkgs.curl
          pkgs.jq
        ];
      };
  };

  testScript = ''
    import json

    start_all()

    for user, port in ${builtins.toJSON users}.items():
        server.wait_for_unit(f"t3code-{user}.service")
        server.wait_for_open_port(port)
    server.wait_for_unit("nginx.service")
    client.wait_for_unit("multi-user.target")

    with subtest("homes are private to their owner"):
        server.succeed("runuser -u alice -- touch /home/alice/.t3/probe")
        server.fail("runuser -u bob -- ls /home/alice")
        server.fail("runuser -u bob -- cat /home/alice/.t3/userdata/statev2.sqlite")

    with subtest("each server runs as its own user with its own environment"):
        for user in ${builtins.toJSON (lib.attrNames users)}:
            pid = server.succeed(f"systemctl show -P MainPID t3code-{user}.service").strip()
            assert server.succeed(f"stat -c %U /proc/{pid}").strip() == user
            server.succeed(f"tr '\\0' '\\n' < /proc/{pid}/environ | grep -qx T3OS_TEST_USER={user}")

    def url(user):
        return f"https://{user}.${domain}"

    def session_state(user, cookie=None):
        header = f"-H 'Cookie: {cookie}'" if cookie else ""
        return json.loads(client.succeed(
            f"curl -sf -H 'Origin: {url(user)}' {header} {url(user)}/api/auth/session"
        ))

    cookies = {}
    for user in ${builtins.toJSON (lib.attrNames users)}:
        with subtest(f"{user} pairs over HTTPS"):
            client.wait_until_succeeds(f"curl -sf {url(user)}/.well-known/t3/environment", timeout=120)
            assert not session_state(user)["authenticated"]
            grant = json.loads(server.succeed(f"t3os-pair {user} --json"))
            assert grant["pairUrl"] == f"{url(user)}/pair#token={grant['credential']}"
            client.succeed(
                f"curl -sf -c /tmp/{user}.jar -H 'Origin: {url(user)}' "
                f"-H 'Content-Type: application/json' "
                f"-d '{json.dumps({'credential': grant['credential']})}' "
                f"{url(user)}/api/auth/browser-session"
            )
            name = session_state(user)["auth"]["sessionCookieName"]
            value = client.succeed(f"awk '$6 == \"{name}\" {{ print $7 }}' /tmp/{user}.jar").strip()
            assert value, f"no {name} cookie for {user}"
            cookies[user] = value
            assert session_state(user, f"{name}={value}")["authenticated"]

    with subtest("a session does not open another user's server"):
        for owner, other in (("alice", "bob"), ("bob", "alice")):
            name = session_state(other)["auth"]["sessionCookieName"]
            assert not session_state(other, f"{name}={cookies[owner]}")["authenticated"]
  '';
}
