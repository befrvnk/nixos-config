_: {
  programs.antigravity-cli = {
    enable = true;
    settings = {
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
