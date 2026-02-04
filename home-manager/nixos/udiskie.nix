{
  services.udiskie = {
    enable = true;
    automount = true;
    notify = true;
    tray = "never"; # rely on notifications instead
  };
}
