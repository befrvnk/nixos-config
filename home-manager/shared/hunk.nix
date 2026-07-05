{ inputs, ... }:

{
  imports = [ inputs.hunk.homeManagerModules.default ];

  programs.hunk = {
    enable = true;
    settings = {
      line_numbers = true;
      mode = "auto";
      theme = "auto";
    };
  };
}
