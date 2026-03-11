{ pkgs, config, ... }:

let
  # 1Password SSH signing program path
  sshSignProgram =
    if pkgs.stdenv.isDarwin then
      "/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
    else
      "/run/current-system/sw/bin/op-ssh-sign";
in
{
  programs.git = {
    enable = true;
    includes =
      let
        homeDir = config.home.homeDirectory;
        workEmail = {
          contents.user.email = "frank.hermann@egym.com";
        };
      in
      builtins.concatMap
        (dir: [
          (workEmail // { condition = "gitdir:${homeDir}/projects/${dir}/"; })
          (workEmail // { condition = "gitdir:${homeDir}/projects/${dir}.*/"; })
        ])
        [
          "egym-docs"
          "galaxy-android-app"
          "galaxy-backend"
          "mobile-api"
          "mwa-bma-features"
        ];
    settings = {
      user = {
        name = "Frank Hermann";
        email = "hermann.frank@gmail.com";
        signingkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ+3hhn8MHxIuaTPFR6z+OPSL9YX5sBN80bct7GVspuz";
      };
      gpg.format = "ssh";
      gpg.ssh.program = sshSignProgram;
      commit.gpgsign = true;
      init.defaultBranch = "main";
      pull = {
        rebase = true;
      };

      # Delta diff viewer configuration with light/dark features
      # Activated via DELTA_FEATURES env var (set by ghd wrapper)
      # NOTE: no options in [delta] directly - that disables features
      delta.features = "dark";
      "delta \"dark\"" = {
        syntax-theme = "TwoDark";
        dark = true;
        navigate = true;
        tabs = 2;
        minus-style = "syntax #45221c";
        minus-emph-style = "syntax #6d2019";
        plus-style = "syntax #0e250e";
        plus-emph-style = "syntax #103610";
        hunk-header-style = "syntax #1e1e2e";
        line-numbers-minus-style = "#f38ba8";
        line-numbers-plus-style = "#a6e3a1";
        line-numbers-zero-style = "#585b70";
      };
      "delta \"light\"" = {
        syntax-theme = "GitHub";
        light = true;
        navigate = true;
        tabs = 2;
        minus-style = "syntax #f5c0c0";
        minus-emph-style = "syntax #e8a0a0";
        plus-style = "syntax #c0f5c0";
        plus-emph-style = "syntax #a0e8a0";
        hunk-header-style = "syntax #eff1f5";
        line-numbers-minus-style = "#d20f39";
        line-numbers-plus-style = "#40a02b";
        line-numbers-zero-style = "#acb0be";
      };
    };
  };
}
