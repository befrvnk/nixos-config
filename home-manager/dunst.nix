{ pkgs, ... }:

{
  services.dunst = {
    enable = true;

    settings = {
      global = {
        # Display
        monitor = 0;
        follow = "mouse";

        # Geometry
        width = 300;
        height = 300;
        origin = "top-right";
        offset = "10x10";

        # Progress bar
        progress_bar = true;
        progress_bar_height = 10;
        progress_bar_frame_width = 1;
        progress_bar_min_width = 150;
        progress_bar_max_width = 300;

        # Appearance
        # Colors, transparency, and frame styling managed by Stylix
        separator_height = 2;
        padding = 8;
        horizontal_padding = 16;
        text_icon_padding = 16;
        sort = true;

        # Text
        # Font managed by Stylix
        line_height = 0;
        markup = "full";
        format = "<b>%s</b>\\n%b";
        alignment = "left";
        vertical_alignment = "center";
        show_age_threshold = 60;
        word_wrap = true;
        ellipsize = "middle";
        ignore_newline = false;
        stack_duplicates = true;
        hide_duplicate_count = false;
        show_indicators = true;

        # Icons
        icon_position = "left";
        min_icon_size = 32;
        max_icon_size = 64;
        enable_recursive_icon_lookup = true;
        icon_theme = "Papirus";
        icon_path = "/home/frank/.nix-profile/share/icons/:/run/current-system/sw/share/icons/hicolor/:/run/current-system/sw/share/pixmaps/";

        # History
        sticky_history = true;
        history_length = 20;

        # Misc
        dmenu = "${pkgs.rofi}/bin/rofi -dmenu -p dunst";
        browser = "${pkgs.xdg-utils}/bin/xdg-open";
        always_run_script = true;
        title = "Dunst";
        class = "Dunst";
        corner_radius = 16;
        ignore_dbusclose = false;

        # Mouse actions
        mouse_left_click = "close_current";
        mouse_middle_click = "do_action, close_current";
        mouse_right_click = "close_all";
      };

      # Urgency levels - colors will be overridden by Stylix
      urgency_low = {
        timeout = 5;
      };

      urgency_normal = {
        timeout = 10;
      };

      urgency_critical = {
        timeout = 0;
      };
    };
  };
}
