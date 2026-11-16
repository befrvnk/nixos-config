_: {
  services.swayosd.enable = false;
  programs.noctalia.settings = {
    audio.enable_overdrive = false;
    osd = {
      enabled = true;
      position = "top_center";
      position_vertical = "top_center";
      # Topbar thickness (34) + 16.
      offset_y = 34 + 16;
      kinds = {
        volume = true;
        volume_output = true;
        volume_input = false;
        brightness = true;
      };
    };
  };
}
