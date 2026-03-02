# Ghostree - Ghostty terminal with native git worktrees
# https://github.com/sidequery/ghostree
#
# To update: change version, set hash = "", run `nh darwin switch .`,
# then fill in the hash from the error message.
{
  lib,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation rec {
  pname = "ghostree";
  version = "0.3.18";

  src = fetchurl {
    url = "https://github.com/sidequery/ghostree/releases/download/v${version}/Ghostree.dmg";
    hash = "sha256-Z1m4ZMAP00X4RiwYZVzFOUXb69arqnQCHr+ZElCM4SE=";
  };

  # undmg only supports HFS; use hdiutil for the APFS-format DMG
  unpackPhase = ''
    runHook preUnpack
    mnt=$(mktemp -d)
    /usr/bin/hdiutil attach -nobrowse -mountpoint "$mnt" "$src"
    /usr/bin/ditto "$mnt/Ghostree.app" ./Ghostree.app
    /usr/bin/hdiutil detach "$mnt"
    runHook postUnpack
  '';

  # Prevent Nix from rewriting shebangs in bundled scripts, which would change
  # file contents and break the app's code signature.
  dontPatchShebangs = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications"
    /usr/bin/ditto Ghostree.app "$out/Applications/Ghostree.app"
    runHook postInstall
  '';

  meta = {
    description = "Ghostty terminal with native git worktrees";
    homepage = "https://github.com/sidequery/ghostree";
    platforms = [ "aarch64-darwin" ];
  };
}
