{
  config,
  ...
}:
{
  stylix.targets.btop.enable = false;
  programs.btop.settings.color_theme = "noctalia";
  programs.noctalia.settings.theme.templates.builtin_ids = [ "btop" ];

  # The native apply hook sees the fixed selector and skips main-config writes.
  # Only the separate theme output is writable; btop reloads it on SIGUSR2.
  noctalia.prepareOutputs = [
    {
      theme = "${config.xdg.configHome}/btop/themes/noctalia.theme";
      backup = "${config.xdg.stateHome}/noctalia/btop.pre-template.theme";
      placeholder = "# Awaiting Noctalia btop colors.";
    }
  ];
}
