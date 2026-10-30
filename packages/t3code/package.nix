{
  lib,
  fetchFromGitHub,
  fetchPnpmDeps,
  nodejs_26,
  pnpm_12,
  rustPlatform,
  t3code,
}:

let
  version = "0.1.5";

  src = fetchFromGitHub {
    owner = "pingdotgg";
    repo = "t3code";
    tag = "v${version}";
    hash = "sha256-MUIf+6/gk2jG3eziHFjtvOfooDeQbbcJxMBECFZh6KQ=";
  };

  patches = [
    ./patches/0001-feat-server-agents-start-with-the-project-s-direnv-e.patch
    ./patches/0002-fix-clients-hide-Allow-.envrc-from-clients-without-t.patch
    ./patches/0003-fix-server-setup-script-terminals-can-unset-variable.patch
    ./patches/0004-fix-acp-registry-agents-resolve-their-binary-on-the-.patch
    ./patches/0005-feat-server-Codex-runs-one-shared-process-per-projec.patch
    ./patches/0006-feat-approve-a-project-s-.envrc-once-and-load-it-aut.patch
    ./patches/0007-feat-server-worktree-setup-scripts-start-with-the-di.patch
    ./patches/0008-feat-web-ask-to-approve-a-project-s-.envrc-and-show-.patch
    ./patches/0009-feat-mobile-ask-to-approve-a-project-s-.envrc-and-ad.patch
    ./patches/0010-docs-explain-how-project-.envrc-approval-works.patch
    ./patches/0011-feat-muse-Muse-agents-start-with-the-project-s-diren.patch
  ];

  unwrapped =
    (t3code.unwrapped.override {
      nodejs = nodejs_26;
      pnpm_11 = pnpm_12;
    }).overrideAttrs
      (
        finalAttrs: _: {
          inherit version src patches;

          pnpmDeps = fetchPnpmDeps {
            pnpm = pnpm_12;
            inherit (finalAttrs)
              pname
              version
              src
              patches
              pnpmWorkspaces
              ;
            fetcherVersion = 4;
            hash = "sha256-IO9xIHzN5Qk/a8GTctI5UbBmxL4pYBCmm6Nrio4eFZM=";
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
