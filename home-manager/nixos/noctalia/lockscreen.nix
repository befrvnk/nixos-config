_: {
  # Stage two is a manual trial. Existing swayidle idle/pre-sleep lock remains
  # swaylock until native password/fingerprint/surface tests are accepted.
  programs.noctalia.settings.lockscreen = {
    enabled = true;
    lock_before_suspend = false;
    grace_period_seconds = 0;
    allow_empty_password = false;
    fingerprint = true;
    blurred_desktop = false;
    transition = [ ];
    wallpaper = "";
    monitors = [ ];
  };
}
