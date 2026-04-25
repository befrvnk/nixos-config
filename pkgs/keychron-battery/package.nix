{
  lib,
  stdenv,
  fetchFromGitHub,
  kernel,
  kernelModuleMakeFlags,
}:

stdenv.mkDerivation rec {
  pname = "keychron-battery";
  version = "0.1.1";

  src = fetchFromGitHub {
    owner = "csutcliff";
    repo = "keychron-battery-dkms";
    rev = "v${version}";
    hash = "sha256-wIdZaVIqDZmVQn5ag8aO8AzOj4C/K/Eb4gcX7RNsgGc=";
  };

  nativeBuildInputs = kernel.moduleBuildDependencies;

  hardeningDisable = [
    "pic"
    "format"
  ];

  postPatch = ''
    substituteInPlace keychron_battery.c \
      --replace-fail 'val->strval = "Keychron M5";' 'val->strval = "Keychron Mouse";'
  '';

  makeFlags = kernelModuleMakeFlags ++ [
    "KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    "INSTALL_MOD_PATH=$(out)"
  ];

  installPhase = ''
    runHook preInstall

    make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build M=$(pwd) modules_install $makeFlags

    runHook postInstall
  '';

  meta = {
    description = "Out-of-tree kernel module for Keychron mouse battery reporting via UPower";
    homepage = "https://github.com/csutcliff/keychron-battery-dkms";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
  };
}
