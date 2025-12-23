{
  services.udiskie = {
    enable = true;
    automount = true;
    notify = true;
    tray = "auto"; # show tray icon when devices are mounted
  };
}
