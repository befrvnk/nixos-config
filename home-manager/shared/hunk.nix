{ inputs, ... }:

{
  # Use the module without its flake package override. The override evaluates
  # bun2nix for x86_64-darwin, which nixpkgs 26.11 no longer supports.
  imports = [ inputs.hunk.homeManagerModules.hunk ];

  programs.hunk = {
    enable = true;
    settings = {
      line_numbers = true;
      mode = "auto";
      theme = "auto";
    };
  };
}
