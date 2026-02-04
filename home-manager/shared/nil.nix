{ pkgs, ... }:

{
  # Install nil LSP
  home.packages = with pkgs; [ nil ];

  # Configure nil via its configuration file
  xdg.configFile."nil/nil.toml".text = ''
    [nil]
    # Automatically run 'nix flake archive' when flake inputs are missing
    auto-archive = true

    [nil.formatting]
    # Use nixfmt for formatting (matches project convention)
    command = ["${pkgs.nixfmt}/bin/nixfmt"]
  '';
}
