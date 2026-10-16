{
  programs.noctalia.settings = {
    plugin_settings."aristides/udiskie" = {
      # The existing udiskie daemon owns automount and event notifications.
      enable_notifications = false;
      auto_open_filemanager = false;
      file_manager_cmd = "xdg-open";
    };
    widget.storage = {
      type = "aristides/udiskie:status";
      hide_when_empty = true;
      show_count = true;
      color = "on_surface";
    };
  };
}
