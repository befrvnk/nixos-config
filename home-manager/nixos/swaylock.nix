_: {
  # Rollback-only fallback pending the remaining recovery/output security review.
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

  services.swayidle.enable = false;
}
