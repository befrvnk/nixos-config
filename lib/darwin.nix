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
    # Pi coding agent pinned ahead of nixpkgs
    (import ../overlays/pi-coding-agent.nix)
    # opencode from flake (patch bun version check - upstream requires ^1.3.11 but nixpkgs has 1.3.10)
    (final: prev: {
      opencode = inputs.opencode.packages.${prev.system}.default.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.nodejs ];
        postConfigure = (old.postConfigure or "") + ''
          sed -i 's/"packageManager": "bun@[^"]*"/"packageManager": "bun@${prev.bun.version}"/' package.json
          chmod -R u+w node_modules packages
          patchShebangs node_modules packages/*/node_modules
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
    # direnv: fix cgo required for -linkmode=external on Darwin
    (final: prev: {
      direnv = prev.direnv.overrideAttrs (old: {
        env = (old.env or { }) // {
          CGO_ENABLED = "1";
        };
      });
    })
    # OpenChamber: desktop GUI for OpenCode AI agent
    (import ../overlays/openchamber.nix)
  ];
in
{
  mkDarwinHost =
    {
      hostname,
      system ? "aarch64-darwin",
      primaryUser ? "frank",
      homeDirectory ? "/Users/${primaryUser}",
    }:
    inputs.nix-darwin.lib.darwinSystem {
      inherit system;
      specialArgs = {
        inherit inputs;
        hostConfig = {
          inherit
            hostname
            system
            primaryUser
            homeDirectory
            ;
        };
      };
      modules = [
        # Apply darwin-compatible overlays
        { nixpkgs.overlays = darwinOverlays; }
        inputs.home-manager.darwinModules.home-manager
        ../hosts/${hostname}
      ];
    };
}
