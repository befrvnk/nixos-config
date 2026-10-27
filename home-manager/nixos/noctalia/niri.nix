{
  config,
  inputs,
  options,
  ...
}:
{
  programs.noctalia.settings.theme.templates.builtin_ids = [ "niri" ];

  # Preserve niri-flake's settings renderer and append only the native include.
  # Optional allows its build-time validator to run without user-home files;
  # activation prepares the output before linking and tests validate it present.
  programs.niri.config = options.programs.niri.config.default ++ [
    (inputs.niri.lib.kdl.leaf "include" [
      "${config.xdg.configHome}/niri/noctalia.kdl"
      { optional = true; }
    ])
  ];

  noctalia.prepareOutputs = [
    {
      theme = "${config.xdg.configHome}/niri/noctalia.kdl";
      backup = "${config.xdg.stateHome}/noctalia/niri.pre-template.kdl";
      placeholder = "// Awaiting Noctalia native colors.";
    }
  ];
}
