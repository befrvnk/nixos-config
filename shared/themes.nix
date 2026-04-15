{ pkgs }:

let
  inherit (pkgs) lib;

  # Parse the small subset of Base16 YAML we use without import-from-derivation,
  # so `nix flake check` can evaluate cross-platform configs on any host.
  parseScheme =
    schemeFile:
    let
      lines = lib.splitString "\n" (builtins.readFile schemeFile);

      parseVariant =
        line:
        let
          match = builtins.match ''variant:[[:space:]]*"([^"]+)".*'' line;
        in
        if match == null then null else builtins.elemAt match 0;

      parsePaletteEntry =
        line:
        let
          match = builtins.match ''[[:space:]]*(base[0-9A-F]{2}):[[:space:]]*"([^"]+)".*'' line;
        in
        if match == null then
          null
        else
          {
            name = builtins.elemAt match 0;
            value = builtins.elemAt match 1;
          };

      variantMatches = builtins.filter (value: value != null) (map parseVariant lines);
      paletteEntries = builtins.filter (value: value != null) (map parsePaletteEntry lines);
    in
    {
      base16Scheme = schemeFile;
      polarity = builtins.head variantMatches;
      palette = builtins.listToAttrs paletteEntries;
    };
in
{
  dark = parseScheme "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";
  light = parseScheme "${pkgs.base16-schemes}/share/themes/catppuccin-latte.yaml";
}
