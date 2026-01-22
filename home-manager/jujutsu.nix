# Jujutsu (jj) - Git-compatible distributed version control system
#
# Shell completions are provided by Carapace (configured in nushell.nix).
# No additional Nushell integration is needed.

{ ... }:

{
  programs.jujutsu = {
    enable = true;

    settings = {
      user = {
        name = "Frank Hermann";
        email = "hermann.frank@gmail.com";
      };

      # Use colocated repos by default for Git interoperability
      # This places .jj alongside .git, allowing both jj and git commands
      git.colocate = true;
    };
  };
}
