{niri}: final: prev: {
  niri = niri.packages.${prev.system}.niri.overrideAttrs {
    doCheck = false;
  };
}
