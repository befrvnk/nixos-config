{ inputs, pkgs, ... }:
{
  umbriel-trial =
    # The overlay is the only wiring point; assert it still resolves to the
    # pinned flake source and did not silently fall back to nixpkgs' package.
    assert pkgs.lib.assertMsg (
      toString pkgs.umbriel.src == toString inputs.umbriel.outPath
    ) "umbriel must be overlaid from the pinned flake input";
    import ../modules/desktop/umbriel-check.nix {
      configuration = inputs.self.nixosConfigurations.framework;
      inherit pkgs;
    };
}
