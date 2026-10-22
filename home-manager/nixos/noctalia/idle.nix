_: {
  programs.noctalia.settings.idle = {
    behavior_order = [
      "lock"
      "screen-off"
      "suspend"
    ];
    pre_action_fade_seconds = 0;
    behavior = {
      lock = {
        action = "lock";
        enabled = true;
        locked_timeout = 0;
        timeout = 300;
      };
      screen-off = {
        action = "screen_off";
        enabled = true;
        locked_timeout = 0;
        timeout = 305;
      };
      suspend = {
        action = "lock_and_suspend";
        enabled = true;
        locked_timeout = 0;
        timeout = 310;
      };
    };
  };
}
