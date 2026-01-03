{ pkgs, ... }:

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
  # Note: audio-idle-inhibit service prevents idle during actual audio playback
  services.swayidle = {
    enable = true;
    events = {
      # Lock the screen before suspend/sleep
      before-sleep = "${pkgs.swaylock}/bin/swaylock -f";
      # Lock the screen when lid is closed (if not already suspending)
      lock = "${pkgs.swaylock}/bin/swaylock -f";
    };
    timeouts = [
      # Lock screen after 5 minutes of inactivity
      # audio-idle-inhibit prevents this during actual audio playback
      {
        timeout = 300;
        command = "${pkgs.swaylock}/bin/swaylock -f";
      }
      # Suspend 5 seconds after lock
      {
        timeout = 305;
        command = "${pkgs.systemd}/bin/systemctl suspend";
      }
    ];
  };

  # Ensure swayidle is available (swaylock already included in niri packages)
  home.packages = with pkgs; [
    swayidle
  ];
}
