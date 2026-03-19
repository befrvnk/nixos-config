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
    # opencode from flake (patch bun version check + fix stale node_modules hash)
    (final: prev: {
      opencode = inputs.opencode.packages.${prev.system}.default.overrideAttrs (old: {
        node_modules = old.node_modules.overrideAttrs {
          outputHash = "sha256-kZGUAE0fxFkFYrarWLQ6e40r5ZAF+GkRF2oZM8/erOM=";
        };
        postPatch = (old.postPatch or "") + ''
          substituteInPlace packages/script/src/index.ts \
            --replace-fail "if (!semver.satisfies(process.versions.bun, expectedBunVersionRange))" "if (false)"
          mkdir -p .github
          touch .github/TEAM_MEMBERS
        '';
      });
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
