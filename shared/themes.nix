{ pkgs }:

let
  # Helper to parse base16 scheme and extract variant (polarity)
  parseScheme =
    schemeFile:
    let
      jsonFile = pkgs.runCommand "base16-to-json" { } ''
        ${pkgs.yq-go}/bin/yq -o json ${schemeFile} > $out
      '';
      scheme = builtins.fromJSON (builtins.readFile jsonFile);
    in
    {
      base16Scheme = schemeFile;
      polarity = scheme.variant; # "dark" or "light" from the YAML
    };
in
{
  # Define dark and light base16 color schemes
  # Polarity is automatically derived from the scheme's "variant" field
  dark = parseScheme "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";
  light = parseScheme "${pkgs.base16-schemes}/share/themes/catppuccin-latte.yaml";
}
