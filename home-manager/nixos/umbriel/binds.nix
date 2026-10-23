{
  config,
  lib,
  pkgs,
}:
let
  original = (import ../niri/binds.nix { inherit config pkgs; }).binds;
  actions = {
    center-column = "column-center";
    center-visible-columns = "column-center";
    close-window = "window-close";
    consume-or-expel-window-left = "window-consume-or-expel-left";
    consume-or-expel-window-right = "window-consume-or-expel-right";
    consume-window-into-column = "window-consume-from-right";
    expand-column-to-available-width = "window-toggle-maximize-to-edges";
    expel-window-from-column = "window-consume-or-expel-right";
    focus-column-first = "column-focus-first";
    focus-column-last = "column-focus-last";
    focus-column-left = "window-focus-left";
    focus-column-right = "window-focus-right";
    focus-monitor-down = "output-focus-down";
    focus-monitor-left = "output-focus-left";
    focus-monitor-right = "output-focus-right";
    focus-monitor-up = "output-focus-up";
    focus-window-down = "window-focus-down";
    focus-window-up = "window-focus-up";
    focus-workspace-down = "workspace-next";
    focus-workspace-previous = "workspace-focus-last";
    focus-workspace-up = "workspace-previous";
    fullscreen-window = "window-toggle-fullscreen";
    maximize-column = "window-toggle-maximize";
    move-column-left = "column-move-left";
    move-column-right = "column-move-right";
    move-column-to-first = "column-move-to-first";
    move-column-to-last = "column-move-to-last";
    move-column-to-monitor-down = "column-move-to-output-down";
    move-column-to-monitor-left = "column-move-to-output-left";
    move-column-to-monitor-right = "column-move-to-output-right";
    move-column-to-monitor-up = "column-move-to-output-up";
    move-column-to-workspace-down = "column-move-to-workspace-next";
    move-column-to-workspace-up = "column-move-to-workspace-previous";
    move-window-down = "window-move-down";
    move-window-up = "window-move-up";
    move-workspace-down = "workspace-move-down";
    move-workspace-up = "workspace-move-up";
    power-off-monitors = "dpms-off";
    reset-window-height = "window-set-secondary-extent:0.5";
    show-hotkey-overlay = "cheatsheet-toggle";
    switch-focus-between-floating-and-tiling = "window-focus-switch-floating";
    switch-preset-column-width = "window-cycle-primary-extent";
    switch-preset-window-height = "window-cycle-secondary-extent";
    toggle-column-tabbed-display = "column-toggle-tabbed";
    toggle-overview = "overview-toggle";
    toggle-window-floating = "window-toggle-floating";
  };
  noctalia = lib.getExe config.programs.noctalia.package;
  convert =
    bind:
    let
      name = builtins.head (builtins.attrNames bind.action);
      argument = bind.action.${name};
      action =
        if name == "spawn" then
          "spawn:${lib.escapeShellArgs argument}"
        else if name == "focus-workspace" then
          "workspace-switch:${toString argument}"
        else if name == "move-column-to-workspace" then
          "column-move-to-workspace:${toString argument}"
        else if name == "set-column-width" then
          "window-modify-primary-extent:${if lib.hasPrefix "-" argument then "-0.1" else "0.1"}"
        else if name == "set-window-height" then
          "window-modify-secondary-extent:${if lib.hasPrefix "-" argument then "-0.1" else "0.1"}"
        else if name == "quit" then
          "session-quit${if argument.skip-confirmation or false then ":skip-confirmation" else ""}"
        else if name == "screenshot" then
          "spawn:${noctalia} msg screenshot-region"
        else if name == "screenshot-screen" then
          "spawn:${noctalia} msg screenshot-fullscreen"
        else if name == "screenshot-window" then
          "spawn:${noctalia} msg screenshot-region"
        else
          actions.${name} or (throw "Unmapped Umbriel trial binding: ${name}");
    in
    {
      inherit action;
      repeat = bind.repeat or true;
    };
  keyName =
    name:
    lib.replaceStrings
      [ "WheelScrollDown" "WheelScrollLeft" "WheelScrollRight" "WheelScrollUp" ]
      [ "WheelDown" "WheelLeft" "WheelRight" "WheelUp" ]
      name;
in
builtins.listToAttrs (
  lib.mapAttrsToList (name: bind: {
    name = keyName name;
    value = convert bind;
  }) original
)
// {
  "Alt+Tab" = {
    action = "spawn:${noctalia} msg window-switcher hold";
    repeat = false;
  };
  "Mod+Shift+D" = {
    action = "output-toggle:eDP-1";
    repeat = false;
  };
}
