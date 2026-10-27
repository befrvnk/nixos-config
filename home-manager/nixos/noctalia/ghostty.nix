{
  config,
  ...
}:
{
  programs.noctalia.settings.theme.templates = {
    enable_builtin_templates = true;
    builtin_ids = [ "ghostty" ];
  };

  # Prepare before either the managed Ghostty config or the enabled Noctalia
  # template is linked. Do not register this runtime output as home.file.
  noctalia.prepareOutputs = [
    {
      theme = "${config.xdg.configHome}/ghostty/themes/noctalia";
      backup = "${config.xdg.stateHome}/noctalia/ghostty-theme.pre-template";
    }
  ];
}
