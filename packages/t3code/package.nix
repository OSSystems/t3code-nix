{
  lib,
  autoPatchelfHook,
  callPackage,
  chromium,
  desktop-file-utils,
  electron_44,
  fetchFromGitHub,
  fetchPnpmDeps,
  makeDesktopItem,
  pnpm_12,
  rustPlatform,
  stdenv,
  t3code,
  vulkan-loader,
  xdg-utils,
}:

let
  version = "0.1.11";

  browser = chromium;
  browserProfileName = "t3-nix-${baseNameOf (toString browser.browser)}";

  src = fetchFromGitHub {
    owner = "pingdotgg";
    repo = "t3code";
    tag = "v${version}";
    hash = "sha256-oI8gyTWFgtTmVK+0cVQaEcfO8EzxUUOW5s8JFG/z/U8=";
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
    ./patches/0012-feat-server-Git-hooks-start-with-the-project-s-diren.patch
    ./patches/0013-feat-choose-the-flake-dev-shell-a-project-s-direnv-e.patch
  ];

  captureHelpers = lib.genAttrs [ "kde" "hyprland" ] (
    backend: callPackage ./capture-helper.nix { inherit backend src version; }
  );

  unwrapped = t3code.unwrapped.overrideAttrs (
    finalAttrs: oldAttrs: {
      inherit version src patches;

      # Backport of https://github.com/NixOS/nixpkgs/pull/582335: the downloaded browser cannot run on
      # NixOS. Keying the AppArmor profile by store path makes setup rerun after browser updates.
      postPatch = (oldAttrs.postPatch or "") + ''
        substituteInPlace apps/server/src/preview/PreviewBrowser.ts \
          --replace-fail 'const executable = path.join(installRoot, release.version, executableName);' \
                         'const executable = "${lib.getExe browser}";'

        substituteInPlace apps/server/src/preview/PreviewBrowserHost.ts \
          --replace-fail 't3-chrome-headless-shell' '${browserProfileName}' \
          --replace-fail '/**/tools/chrome-headless-shell/*/*/chrome-headless-shell' \
                         '${browser.browser}/libexec/chromium/chromium'

        substituteInPlace apps/server/src/cli/browser.ts \
          --replace-fail 'const browser = yield* installedBrowser(baseDirPath);' \
                         'const browser = Option.some("${lib.getExe browser}");'

        # Backport of https://github.com/NixOS/nixpkgs/pull/575673: shared Electron runs the app
        # unpackaged, so the backend would otherwise start in the read-only store.
        substituteInPlace apps/desktop/src/app/DesktopEnvironment.ts \
          --replace-fail 'backendCwd: input.isPackaged ? homeDirectory : appRoot,' \
                         'backendCwd: homeDirectory,'
      '';

      # Connect is disabled unless the public production identifiers are embedded at build time.
      preBuild = ''
        cp .env.example .env
      ''
      + (oldAttrs.preBuild or "");

      # Backport of https://github.com/NixOS/nixpkgs/pull/589125: voice input loads speech
      # libraries that need libstdc++ and Vulkan, and window capture needs the GNOME extension
      # and the KDE and Hyprland helpers.
      nativeBuildInputs = oldAttrs.nativeBuildInputs ++ [ autoPatchelfHook ];
      buildInputs = oldAttrs.buildInputs ++ [
        stdenv.cc.cc.lib
        vulkan-loader
      ];
      # The pnpm tree includes static, musl and foreign-platform binaries; patch only host modules.
      dontAutoPatchelf = true;
      # Speech backends load sibling libraries relative to their own directory.
      autoPatchelfFlags = [ "--preserve-origin" ];

      postInstall = (oldAttrs.postInstall or "") + ''
        # Shared Electron uses the unpackaged resource paths in DesktopSnapShot.
        while IFS= read -r file; do
          install -Dm444 "apps/desktop/gnome-extension/$file" \
            "$out/libexec/t3code/apps/desktop/gnome-extension/$file"
        done < <(jq -r '.files[]' apps/desktop/gnome-extension/bundle.json)

        # The setup code rejects symlinks, including for bundled helpers.
        install -Dm755 ${lib.getExe captureHelpers.kde} \
          "$out/libexec/t3code/native/kde-snap-shot/target/release/t3-kde-snap-shot"
        install -Dm755 ${lib.getExe captureHelpers.hyprland} \
          "$out/libexec/t3code/native/hyprland-snap-shot/target/release/t3-hyprland-snap-shot"
        cp -r ${captureHelpers.hyprland}/share/t3code/hyprland-capture/protocols \
          "$out/libexec/t3code/native/hyprland-snap-shot/"
      '';

      postFixup = ''
        autoPatchelf \
          "$out"/libexec/t3code/node_modules/.pnpm/node-pty@*/node_modules/node-pty/prebuilds/linux-${stdenv.hostPlatform.node.arch} \
          "$out"/libexec/t3code/node_modules/.pnpm/@koromix+koffi-linux-${stdenv.hostPlatform.node.arch}@*/node_modules/@koromix/koffi-linux-${stdenv.hostPlatform.node.arch}/linux_${stdenv.hostPlatform.node.arch} \
          "$out"/libexec/t3code/node_modules/.pnpm/@transcribe-cpp+linux-${stdenv.hostPlatform.node.arch}-cpu-vulkan@*/node_modules/@transcribe-cpp/linux-${stdenv.hostPlatform.node.arch}-cpu-vulkan
      '';

      doInstallCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
      installCheckPhase = ''
        runHook preInstallCheck

        # The standalone Node CLI can mask missing C++ runtime dependencies; exercise local
        # dictation with the same runtime as the desktop worker.
        ELECTRON_RUN_AS_NODE=1 ${lib.getExe electron_44} --input-type=module -e '
          const speech = await import(process.argv[1]);
          if (!speech.getAvailableBackends().some(backend => backend.kind === "cpu")) {
            throw new Error("Native speech CPU backend is unavailable");
          }
        ' "$out/libexec/t3code/apps/server/node_modules/transcribe-cpp/dist/index.js"

        runHook postInstallCheck
      '';

      desktopItems = [
        (makeDesktopItem {
          name = "t3code";
          desktopName = "T3 Code (Beta)";
          comment = "Minimal web GUI for coding agents";
          exec = "t3code-desktop %U";
          terminal = false;
          icon = "t3code";
          startupWMClass = "com.t3tools.T3Code";
          categories = [ "Development" ];
          mimeTypes = [ "x-scheme-handler/t3code" ];
        })
      ];

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
        hash = "sha256-u34YhuSMQj178JiRf/bf+VQYZfBUUH9UtCcJODPzBFQ=";
      };

      passthru = (oldAttrs.passthru or { }) // {
        inherit browser captureHelpers;
        tests = (oldAttrs.passthru.tests or { }) // {
          browser = callPackage ./browser-test.nix {
            inherit browser;
            t3code = finalAttrs.finalPackage;
          };
        };
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
      # The app registers itself for t3code:// sign-in links with these tools (NixOS/nixpkgs#555921).
      wrapProgram "$out/bin/t3code-desktop" \
        --set T3CODE_DESKTOP_LAUNCHER_PATH "$out/bin/t3code-desktop" \
        --prefix PATH : "${
          lib.makeBinPath [
            desktop-file-utils
            xdg-utils
          ]
        }"
    '';
  })
