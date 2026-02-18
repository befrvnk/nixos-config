{ inputs }:
let
  inherit (inputs.nixpkgs) lib;

  # Darwin-compatible overlays
  darwinOverlays = [
    # Claude Code from flake
    inputs.claude-code.overlays.default
    # Kotlin LSP from JetBrains CDN
    (import ../overlays/kotlin-lsp.nix)
    # opencode from flake
    inputs.opencode.overlays.default
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
