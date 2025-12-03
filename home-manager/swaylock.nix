{ pkgs, ... }:

let
  # Smart lock script that checks if media is playing before locking
  # Prevents interrupting videos/music with the lock screen
  smartLock = pkgs.writeShellScript "smart-lock" ''
    # Check if any media player is currently playing
    status=$(${pkgs.playerctl}/bin/playerctl status 2>/dev/null || echo "Stopped")

    if [ "$status" = "Playing" ]; then
      # Media is playing - don't lock, just turn off the screen
      ${pkgs.niri}/bin/niri msg action power-off-monitors
    else
      # No media playing - lock normally
      ${pkgs.swaylock}/bin/swaylock -f
    fi
  '';
in
{
  # Enable swaylock with Stylix theming
  # Stylix will automatically manage colors based on the current theme
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

  # Use swayidle to automatically lock the screen before suspend/sleep
  # This ensures the lock screen is properly shown when opening the lid
  services.swayidle = {
    enable = true;
    events = [
      # Lock the screen before suspend/sleep
      {
        event = "before-sleep";
        command = "${pkgs.swaylock}/bin/swaylock -f";
      }
      # Lock the screen when lid is closed (if not already suspending)
      {
        event = "lock";
        command = "${pkgs.swaylock}/bin/swaylock -f";
      }
    ];
    timeouts = [
      # Smart lock after 5 minutes of inactivity
      # If media is playing: only turns off screen (no lock)
      # If no media: locks normally
      {
        timeout = 300;
        command = "${smartLock}";
      }
      # Suspend 5 seconds after timeout (unless media is playing)
      # The inhibit-suspend-while-playing service will prevent this if audio is active
      {
        timeout = 305;
        command = "${pkgs.systemd}/bin/systemctl suspend";
      }
      # Turn off displays if suspend was inhibited (media still playing)
      # This is a fallback in case the screen wasn't turned off by smartLock
      {
        timeout = 310;
        command = "${pkgs.niri}/bin/niri msg action power-off-monitors";
      }
    ];
  };

  # Ensure swayidle is available (swaylock already included in niri packages)
  home.packages = with pkgs; [
    swayidle
  ];
}
