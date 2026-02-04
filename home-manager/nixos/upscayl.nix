{ pkgs }:

# Upscayl with Wayland support
pkgs.symlinkJoin {
  name = "upscayl-wayland";
  paths = [ pkgs.upscayl ];
  buildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/upscayl \
      --add-flags "--enable-features=UseOzonePlatform" \
      --add-flags "--ozone-platform=wayland"
  '';
}
