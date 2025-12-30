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
      # Video players set Wayland idle inhibitors, so this only triggers for audio-only playback
      # The inhibit-suspend-while-playing service blocks suspend when music is playing
      {
        timeout = 300;
        command = "${pkgs.swaylock}/bin/swaylock -f";
      }
      # Suspend 5 seconds after lock (unless audio is playing)
      {
        timeout = 305;
        command = "${pkgs.systemd}/bin/systemctl suspend";
      }
      # Turn off displays if suspend was inhibited (audio still playing)
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
