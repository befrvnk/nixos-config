{ config, osConfig, pkgs, pkgs-unstable, zen-browser, android-nixpkgs, nix-colors, ... }:

{
  imports = [
    zen-browser.homeModules.beta
    (import ./zed.nix { inherit pkgs pkgs-unstable; })
    (import ./android.nix { inherit pkgs pkgs-unstable android-nixpkgs; })
    ./stylix.nix
    (import ./niri/default.nix { inherit osConfig pkgs nix-colors; lib = pkgs.lib; })
    ./hyprlock.nix
    ./vicinae.nix
  ];

  home.username = "frank";
  home.homeDirectory = "/home/frank";
  home.stateVersion = "25.05";


  home.file.".config/zsh/rebuild.zsh".source = ./zsh/rebuild.zsh;


  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "Frank Hermann";
        email = "hermann.frank@gmail.com";
      };
      init.defaultBranch = "main";
    };
  };
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks."*" = {
      identityAgent = "~/.1password/agent.sock";
    };
  };
  programs.zsh = {
    enable = true;
    initContent = "source ${config.home.homeDirectory}/.config/zsh/rebuild.zsh";
  };
  programs.starship = {
    enable = true;
  };
  programs.zen-browser.enable = true;
  home.packages = with pkgs; [
    pkgs-unstable._1password-cli
    pkgs-unstable._1password-gui
    pkgs-unstable.anytype
    pkgs-unstable.claude-code
    pkgs-unstable.discord
    pkgs-unstable.gemini-cli
    pkgs-unstable.ghostty
    pkgs-unstable.helix
    pkgs-unstable.jetbrains.idea-community-bin
    pkgs-unstable.signal-desktop
    pkgs-unstable.slack
    pkgs-unstable.spotify
    pkgs-unstable.ticktick
    pkgs-unstable.zapzap
    bat
    eza
    fd
    fzf
    gh
    htop
    lf
    neofetch
    starship
    tree
  ];

  dconf.settings = {
    "org/gnome/desktop/input-sources" = {
      sources = [ ["xkb" "us-umlauts"] ];
    };
  };
}
