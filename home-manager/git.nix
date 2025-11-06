{ ... }:

{
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
}
