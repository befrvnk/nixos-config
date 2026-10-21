_: {
  services.swayosd.enable = false;
  programs.noctalia.settings = {
    audio.enable_overdrive = false;
    osd = {
      enabled = true;
      position = "bottom_center";
      position_vertical = "bottom_center";
      kinds = {
        volume = true;
        volume_output = true;
        volume_input = false;
        brightness = true;
      };
    };
  };
}
