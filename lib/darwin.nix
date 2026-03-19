{ inputs }:
let
  inherit (inputs.nixpkgs) lib;

  # Darwin-compatible overlays
  darwinOverlays = [
    # Claude Code from flake
    inputs.claude-code.overlays.default
    # gh-enhance: GitHub Actions TUI (companion to gh-dash)
    (import ../overlays/gh-enhance.nix)
    # Kotlin LSP from JetBrains CDN
    (import ../overlays/kotlin-lsp.nix)
    # opencode from flake (pinned to last working version, see upstream regression in d178d82+)
    (final: prev: {
      opencode = inputs.opencode.packages.${prev.system}.default;
    })
    # devenv from flake (latest version, ahead of nixpkgs, skip tests during build)
    (final: prev: {
      devenv = inputs.devenv.packages.${prev.system}.devenv.overrideAttrs { doCheck = false; };
    })
    # worktrunk from flake
    (final: prev: {
      worktrunk = inputs.worktrunk.packages.${prev.system}.default;
    })
    # agent-of-empires from flake
    (final: prev: {
      agent-of-empires = inputs.agent-of-empires.packages.${prev.system}.default;
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
