_final: prev: {
  # Disable niri tests - they fail in the Nix sandbox with panic/SIGABRT
  niri-stable = prev.niri-stable.overrideAttrs (_old: {
    doCheck = false;
  });
  niri-unstable = prev.niri-unstable.overrideAttrs (_old: {
    doCheck = false;
  });
}
