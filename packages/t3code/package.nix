{
  lib,
  cloudflared,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpm_12,
  rustPlatform,
  t3code,
}:

let
  version = "0.1.6";

  src = fetchFromGitHub {
    owner = "pingdotgg";
    repo = "t3code";
    tag = "v${version}";
    hash = "sha256-GWO+/gJWLu9GUwZCbmrBYIVn9Y7N8PwXrjQYFLOtmWk=";
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
    ./patches/0012-fix-web-keyboard-conversation-scrolling.patch
  ];

  unwrapped = t3code.unwrapped.overrideAttrs (
    finalAttrs: oldAttrs: {
      inherit version src patches;

      # Connect is disabled unless the public production identifiers are embedded at build time.
      preBuild = ''
        cp .env.example .env
      ''
      + (oldAttrs.preBuild or "");

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
        hash = "sha256-XqdfHBKTB1QnlqLBAdm2lqzVSGpSW99V0aedDNl24eQ=";
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
(t3code.override {
  t3code-unwrapped = unwrapped;
  t3code-resource-monitor = resourceMonitor;
}).overrideAttrs
  (oldAttrs: {
    # Shared Electron must register the packaged launcher so sign-in callbacks reopen T3 Code.
    buildCommand = oldAttrs.buildCommand + ''
      # Use Nix's relay client instead of downloading a managed copy at runtime.
      wrapProgram "$out/bin/t3" \
        --set-default T3CODE_CLOUDFLARED_PATH "${lib.getExe cloudflared}"
      wrapProgram "$out/bin/t3code-desktop" \
        --set T3CODE_DESKTOP_LAUNCHER_PATH "$out/bin/t3code-desktop" \
        --set-default T3CODE_CLOUDFLARED_PATH "${lib.getExe cloudflared}"
    '';
  })
