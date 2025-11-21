{ ... }:
{
  programs.gemini-cli = {
    enable = true;
    settings = {
      context.fileName = [ "AGENTS.md" ];
      security.auth.selectedType = "oauth-personal";
      ui.theme = "Google Code";
      general = {
        preferredEditor = "vim";
        disableAutoUpdate = true;
        previewFeatures = false;
      };
    };
  };
}
