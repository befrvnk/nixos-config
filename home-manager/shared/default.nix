{
  # This flake tracks nixpkgs-unstable. During the post-release cycle,
  # nixpkgs reports the next release number before Home Manager updates its
  # own release metadata, so the release check warns even though both inputs
  # are intentionally tracking their default branches.
  home.enableNixpkgsReleaseCheck = false;

  imports = [
    ./atuin.nix
    ./btop.nix
    ./claude-code
    ./direnv.nix
    ./gh.nix
    ./git.nix
    ./jujutsu.nix
    ./lazygit.nix
    ./navi
    ./nil.nix
    ./nix-index.nix
    ./nushell.nix
    ./opencode.nix
    ./packages.nix
    ./pi
    ./ssh.nix
    ./starship.nix
    ./worktrunk.nix
    ./zed.nix
    ./zoxide.nix
  ];
}
