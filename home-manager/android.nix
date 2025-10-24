{ pkgs, pkgs-unstable, ... }:

let
  update-vmoptions-script = pkgs.writeScript "update-android-studio-vmoptions.sh" (builtins.readFile ./android/update-vmoptions.sh);
in
{
  home.packages = with pkgs; [
    pkgs-unstable.androidStudioPackages.canary
  ];

  systemd.user.services.update-android-studio-vmoptions = {
    Unit = {
      Description = "Update Android Studio vmoptions";
    };
    Service = {
      ExecStart = "${update-vmoptions-script}";
    };
    Install = {
      WantedBy = [ "multi-user.target" ];
    };
  };
}
