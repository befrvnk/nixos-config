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
      indicator-thickness = 7;
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
      # Optional: Lock screen after 10 minutes of inactivity
      # Uncomment the following lines if you want automatic locking on idle:
      # {
      #   timeout = 600;
      #   command = "${pkgs.swaylock}/bin/swaylock -f";
      # }
      # Turn off displays after 5 minutes (keeping existing behavior)
      {
        timeout = 300;
        command = "${pkgs.niri}/bin/niri msg action power-off-monitors";
      }
    ];
  };

  # Ensure swayidle is available (swaylock already included in niri packages)
  home.packages = with pkgs; [
    swayidle
  ];
}
