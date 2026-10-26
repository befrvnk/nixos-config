{ inputs, pkgs, ... }:
{
  umbriel-trial =
    let
      # A `flake = false` input only exposes its source path, so read the pin from the lock.
      umbrielRev = (builtins.fromJSON (builtins.readFile ../flake.lock)).nodes.umbriel.locked.rev;
    in
    assert pkgs.lib.assertMsg (
      umbrielRev == (pkgs.umbriel.src.drvAttrs.rev or "")
    ) "umbriel flake input must match the umbriel source pinned by nixpkgs";
    import ../modules/desktop/umbriel-check.nix {
      configuration = inputs.self.nixosConfigurations.framework;
      inherit pkgs;
    };

}
