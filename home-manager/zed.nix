{ pkgs, ... }:

{
  home.packages = with pkgs; [
    nil
    nixd
  ];

  programs.zed-editor = {
    enable = true;
    package = pkgs.zed-editor;
    extensions = [ "nix" ];
    userSettings = {
      tab_bar = {
        show = false;
        show_nav_history_buttons = false;
        show_tab_bar_buttons = false;
      };
    };
  };
}
