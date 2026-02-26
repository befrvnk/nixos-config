{ inputs }:
let
  inherit (inputs.nixpkgs) lib;

  # Darwin-compatible overlays
  darwinOverlays = [
    # Claude Code from flake
    inputs.claude-code.overlays.default
    # Kotlin LSP from JetBrains CDN
    (import ../overlays/kotlin-lsp.nix)
    # opencode from flake (patch bun version check - upstream nixpkgs has bun 1.3.9, opencode requires ^1.3.10)
    (final: prev: {
      opencode = (inputs.opencode.packages.${prev.system}.default).overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace packages/script/src/index.ts \
            --replace-fail "if (!semver.satisfies(process.versions.bun, expectedBunVersionRange))" "if (false)"
        '';
      });
    })
    # worktrunk from flake
    (final: prev: {
      worktrunk = inputs.worktrunk.packages.${prev.system}.default;
    })
  ];
in
{
  mkDarwinHost =
    {
      hostname,
      system ? "aarch64-darwin",
    }:
    inputs.nix-darwin.lib.darwinSystem {
      inherit system;
      specialArgs = {
        inherit inputs;
      };
      modules = [
        # Apply darwin-compatible overlays
        { nixpkgs.overlays = darwinOverlays; }
        inputs.home-manager.darwinModules.home-manager
        ../hosts/${hostname}
      ];
    };
}
