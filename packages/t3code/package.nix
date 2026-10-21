{
  lib,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpm_11,
  rustPlatform,
  t3code,
}:

let
  version = "0.1.1";

  src = fetchFromGitHub {
    owner = "pingdotgg";
    repo = "t3code";
    tag = "v${version}";
    hash = "sha256-kIGiC/uCDgRlqt+8/zZ9K48NBuCGJ1TgqW+rpdZgZUQ=";
  };

  patches = [
    ./patches/0001-feat-server-agents-start-with-the-project-s-direnv-e.patch
    ./patches/0002-fix-clients-hide-Allow-.envrc-from-clients-without-t.patch
  ];

  unwrapped = t3code.unwrapped.overrideAttrs (
    finalAttrs: _: {
      inherit version src patches;

      pnpmDeps = fetchPnpmDeps {
        pnpm = pnpm_11;
        inherit (finalAttrs)
          pname
          version
          src
          patches
          pnpmWorkspaces
          ;
        fetcherVersion = 4;
        hash = "sha256-witoens1UicKE+SIQCrRk9YtbAVIW5x+2MqDrFh4F0s=";
      };
    }
  );

  resourceMonitor = t3code.resourceMonitor.overrideAttrs {
    inherit version src;
    cargoDeps = rustPlatform.fetchCargoVendor {
      inherit src;
      sourceRoot = "${src.name}/native/resource-monitor";
      hash = "sha256-5cmG2daM1bVOA23gjjoalbx0fEL1hmqV6WZov0sUZp8=";
    };
  };
in
t3code.override {
  t3code-unwrapped = unwrapped;
  t3code-resource-monitor = resourceMonitor;
}
