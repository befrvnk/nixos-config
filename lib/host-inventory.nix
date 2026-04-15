{
  nixos = {
    framework = {
      hostname = "framework";
      primaryUser = "frank";
      homeDirectory = "/home/frank";
      cpuVendor = "amd";
      hasFingerprint = true;
      hasTouchscreen = false;
      enableAndroid = true;
      enableLogitech = true;
      enableNuphy = true;
      wifiInterface = "wlp192s0";
      abmPath = "/sys/class/drm/card1-eDP-1/amdgpu/panel_power_savings";
    };
  };

  darwin = {
    macbook = {
      hostname = "macbook-darwin";
      primaryUser = "frank";
      homeDirectory = "/Users/frank";
    };
  };
}
