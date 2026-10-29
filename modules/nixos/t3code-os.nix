{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    mkPackageOption
    types
    ;

  cfg = config.services.t3code-os;

  hostFor = name: "${name}.${cfg.domain}";

  pair = pkgs.writeShellApplication {
    name = "t3os-pair";
    runtimeInputs = [ pkgs.util-linux ];
    text = ''
      if [ "$#" -lt 1 ]; then
        echo "usage: t3os-pair <user> [t3 auth pairing create flags...]" >&2
        exit 64
      fi
      user=$1
      shift
      case "$user" in
      ${lib.concatMapStringsSep "\n" (
        name:
        "${lib.escapeShellArg name}) url=${lib.escapeShellArg "${cfg.publicScheme}://${hostFor name}"} ;;"
      ) (lib.attrNames cfg.users)}
        *)
          echo "t3os-pair: unknown T3 Code OS user: $user" >&2
          exit 65
          ;;
      esac
      exec runuser -u "$user" -- ${lib.getExe' cfg.package "t3"} auth pairing create \
        --base-url "$url" --label "t3os-pair" "$@"
    '';
  };

  userModule =
    { name, ... }:
    {
      options = {
        port = mkOption {
          type = types.port;
          description = "Loopback port this user's T3 Code server listens on.";
        };

        home = mkOption {
          type = types.path;
          default = "/home/${name}";
          description = "Home directory; T3 Code keeps its state in `.t3` under it.";
        };

        createUser = mkOption {
          type = types.bool;
          default = true;
          description = "Declare the Unix account. Disable when accounts come from elsewhere, such as LDAP.";
        };

        environment = mkOption {
          type = types.attrsOf types.str;
          default = { };
          example = {
            ANTHROPIC_BASE_URL = "https://llm-proxy.example.com";
          };
          description = "Non-secret environment for the server and the agents it starts.";
        };

        environmentFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "File of `KEY=value` lines, such as an API key, read by systemd at start and kept out of the Nix store.";
        };

        extraPackages = mkOption {
          type = types.listOf types.package;
          default = [ ];
          description = "Packages on the PATH of this user's agents and terminals.";
        };
      };
    };
in
{
  options.services.t3code-os = {
    enable = mkEnableOption "one T3 Code server per user, each behind its own HTTPS subdomain";

    package = mkPackageOption pkgs "t3code" { };

    domain = mkOption {
      type = types.str;
      example = "t3.example.com";
      description = "Each user is served at `<user>.<domain>`.";
    };

    publicScheme = mkOption {
      type = types.enum [
        "https"
        "http"
      ];
      default = "https";
      description = "Scheme of the URLs printed by `t3os-pair`.";
    };

    extraPackages = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Packages on the PATH of every user's agents and terminals.";
    };

    virtualHost = mkOption {
      type = types.attrsOf types.anything;
      default = {
        forceSSL = true;
        enableACME = true;
      };
      example = {
        forceSSL = true;
        useACMEHost = "example.com";
      };
      description = "nginx virtual host settings, such as TLS, applied to every user's subdomain.";
    };

    users = mkOption {
      type = types.attrsOf (types.submodule userModule);
      default = { };
      description = "Users that get a T3 Code server, keyed by Unix user name.";
    };
  };

  config = mkIf cfg.enable {
    assertions =
      let
        ports = lib.mapAttrsToList (_: u: u.port) cfg.users;
      in
      [
        {
          assertion = lib.length ports == lib.length (lib.unique ports);
          message = "services.t3code-os.users: every user needs a distinct port.";
        }
      ];

    environment.systemPackages = [
      cfg.package
      pair
    ];

    users.users = lib.mapAttrs (
      name: u:
      mkIf u.createUser {
        isNormalUser = true;
        inherit (u) home;
        homeMode = "700";
      }
    ) cfg.users;

    systemd.services = lib.mapAttrs' (
      name: u:
      lib.nameValuePair "t3code-${name}" {
        description = "T3 Code server for ${name}";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        path = [
          cfg.package
          config.nix.package
          pkgs.bashInteractive
          pkgs.coreutils
          pkgs.git
        ]
        ++ cfg.extraPackages
        ++ u.extraPackages;
        environment = {
          HOME = u.home;
          T3CODE_HOME = "${u.home}/.t3";
        }
        // u.environment;
        serviceConfig = {
          User = name;
          WorkingDirectory = u.home;
          ExecStart = "${lib.getExe' cfg.package "t3"} serve --host 127.0.0.1 --port ${toString u.port}";
          EnvironmentFile = lib.optional (u.environmentFile != null) u.environmentFile;
          Restart = "on-failure";
          RestartSec = 5;
          KillMode = "mixed";
        };
      }
    ) cfg.users;

    services.nginx = {
      enable = true;
      recommendedProxySettings = true;
      virtualHosts = lib.mapAttrs' (
        name: u:
        lib.nameValuePair (hostFor name) (
          cfg.virtualHost
          // {
            locations."/" = {
              proxyPass = "http://127.0.0.1:${toString u.port}";
              proxyWebsockets = true;
              extraConfig = ''
                proxy_read_timeout 1d;
                proxy_send_timeout 1d;
                client_max_body_size 64m;
              '';
            };
          }
        )
      ) cfg.users;
    };
  };
}
