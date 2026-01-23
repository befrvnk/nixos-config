{ pkgs, inputs, ... }:

let
  stasisPkg = inputs.stasis.packages.${pkgs.system}.default;

  stasisConfig = ''
    @author "frank"
    @description "Framework laptop idle management with stasis"

    default:
      monitor_media true
      debounce_seconds 2

      inhibit_apps [
        "spotify"
        "mpv"
        "vlc"
        "firefox"
        "zen-beta"
      ]

      pre_suspend_command "${pkgs.swaylock}/bin/swaylock -f"

      lock_screen:
        timeout 300
        command "${pkgs.swaylock}/bin/swaylock -f"
      end

      suspend:
        timeout 305
        command "${pkgs.systemd}/bin/systemctl suspend"
      end
    end
  '';
in
{
  # Enable swaylock for the lock screen (Stylix will manage colors)
  programs.swaylock = {
    enable = true;
    settings = {
      font-size = 24;
      indicator-idle-visible = false;
      indicator-radius = 100;
      indicator-thickness = 12;
      show-failed-attempts = true;
    };
  };

  # Add stasis package to PATH
  home.packages = [ stasisPkg ];

  # Write stasis config manually (not using services.stasis to avoid systemd service)
  xdg.configFile."stasis/stasis.rune".text = stasisConfig;
}
