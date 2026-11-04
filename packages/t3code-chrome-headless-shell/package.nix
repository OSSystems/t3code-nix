{
  lib,
  alsa-lib,
  at-spi2-atk,
  autoPatchelfHook,
  dbus,
  expat,
  fetchurl,
  glib,
  libgbm,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  nspr,
  nss,
  stdenv,
  systemdLibs,
  unzip,
}:

let
  # Must match VERSION and ARCHIVES in apps/server/src/preview/PreviewBrowser.ts;
  # update it with each t3code bump.
  archives = {
    x86_64-linux = {
      platform = "linux64";
      sha256 = "547dcd374e02961bf998f6046a267644f8502225c36bb78ca307dab32a0b3eb4";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      sha256 = "5bb6a00a4285c13303d3f72c5afdb70f144ea7a93eed462365a52b69631c9607";
    };
  };
  archive =
    archives.${stdenv.hostPlatform.system}
      or (throw "chrome-headless-shell: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "chrome-headless-shell";
  version = "156.0.8078.80";

  src = fetchurl {
    url = "https://storage.googleapis.com/chrome-for-testing-public/${finalAttrs.version}/${archive.platform}/chrome-headless-shell-${archive.platform}.zip";
    inherit (archive) sha256;
  };

  nativeBuildInputs = [
    unzip
    autoPatchelfHook
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    dbus
    expat
    glib
    libgbm
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxrandr
    nspr
    nss
    systemdLibs
  ];

  installPhase = ''
    runHook preInstall
    cp -R . $out
    runHook postInstall
  '';

  passthru = {
    inherit (archive) platform;
    inherit archives;
  };

  meta = {
    description = "Chrome for Testing headless shell pinned by T3 Code";
    homepage = "https://googlechromelabs.github.io/chrome-for-testing/";
    license = lib.licenses.bsd3;
    platforms = lib.attrNames archives;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
