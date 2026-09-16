{
  lib,
  fetchurl,
  appimageTools,
  stdenv,
  autoPatchelfHook,
  symlinkJoin,
}:
let
  pname = "asyar";
  version = "0.1.1-47";

  appimage = appimageTools.wrapType2 {
    inherit pname version;
    src = fetchurl {
      url = "https://github.com/Xoshbin/asyar/releases/download/v${version}/asyar_${version}_amd64.AppImage";
      hash = "sha256-CM90n2vAqhJu1UqOpOiGGVrfj+b8KeorSnES0h2RZ0k=";
    };
    extraPkgs =
      pkgs: with pkgs; [
        webkitgtk_4_1
        gtk3
      ];
  };

  summon = stdenv.mkDerivation {
    pname = "asyar-summon";
    inherit version;
    src = fetchurl {
      url = "https://github.com/Xoshbin/asyar/releases/download/v${version}/asyar-summon_amd64";
      hash = "sha256-AES4HSPgp00KxyRpdswzVMbMtQ0C+8jlZOtxuEWxYNs=";
    };
    nativeBuildInputs = [ autoPatchelfHook ];
    dontUnpack = true;
    installPhase = ''
      install -Dm755 $src $out/bin/asyar-summon
    '';
  };
in
symlinkJoin {
  name = "asyar-${version}";
  paths = [
    appimage
    summon
  ];
  meta = with lib; {
    description = "A fast, open-source launcher for macOS, Windows, and Linux";
    homepage = "https://github.com/Xoshbin/asyar";
    license = licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "asyar";
  };
}
