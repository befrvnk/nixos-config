{ pkgs }:

pkgs.ticktick.overrideAttrs (oldAttrs: {
  nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
  postFixup = (oldAttrs.postFixup or "") + ''
    wrapProgram $out/bin/ticktick \
      --add-flags "--ozone-platform=wayland --enable-features=UseOzonePlatform"
  '';
})
