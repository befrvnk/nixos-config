{
  config,
  inputs,
  pkgs,
  ...
}:
{
  stylix.targets.fzf.enable = false;
  # Keep the fzf module/integrations disabled as before. The existing shared
  # package list consumes this package option; Darwin keeps its default package.
  programs.fzf.package = pkgs.callPackage ./fzf-package.nix {
    configHome = config.xdg.configHome;
  };

  # Reuse the upstream Bash snippet, sourced only inside each fzf child wrapper.
  # No Fish universal variable, Nu eval/conversion, or parent-shell env mutation.
  programs.noctalia.settings.theme.templates.user.fzf = {
    input_path = "${inputs.noctalia-community-templates}/fzf/fzf.sh";
    output_path = "$XDG_CONFIG_HOME/fzf/themes/noctalia.sh";
  };

  noctalia.prepareOutputs = [
    {
      theme = "${config.xdg.configHome}/fzf/themes/noctalia.sh";
      backup = "${config.xdg.stateHome}/noctalia/fzf.pre-template.sh";
      placeholder = "# Awaiting Noctalia fzf colors.";
    }
  ];
}
