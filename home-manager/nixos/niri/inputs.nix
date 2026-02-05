_: {
  input = {
    keyboard = {
      xkb = {
        # Use the custom us-umlauts layout defined in modules/system/xkb-custom.nix
        layout = "us-umlauts";
        # Use left and right alt for special characters (level 3 shift)
        options = "lv3:ralt_switch";
      };
    };
    touchpad = {
      tap = true;
      natural-scroll = true;
      dwt = true;
      click-method = "clickfinger";
    };
    mouse = {
      natural-scroll = true;
    };
    warp-mouse-to-focus.enable = true;
    workspace-auto-back-and-forth = true;
  };
}
