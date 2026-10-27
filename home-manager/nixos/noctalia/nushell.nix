{
  config,
  ...
}:
{
  # No Nushell entry exists in either pinned catalog. This data-only template
  # uses Noctalia's native renderer, not a second generator/controller/service.
  programs.noctalia.settings.theme.templates.user.nushell = {
    input_path = "${./nushell.nuon}";
    output_path = "$XDG_STATE_HOME/nushell/theme.nuon";
  };

  noctalia.prepareOutputs = [
    {
      theme = "${config.xdg.stateHome}/nushell/theme.nuon";
      backup = "${config.xdg.stateHome}/noctalia/nushell.pre-template.nuon";
      placeholder = "{}";
    }
  ];
}
