{ inputs }:
let
  inherit (inputs.nixpkgs) lib;

  # Common overlays applied to all hosts
  commonOverlays = [
    inputs.android-nixpkgs.overlays.default
    (import ../overlays/android-studio-canary.nix)
    (import ../overlays/claude-code.nix)
    (import ../overlays/domain-check.nix)
    (import ../overlays/gh-enhance.nix)
    inputs.claude-code.overlays.default

    (import ../overlays/idea-community.nix)
    (import ../overlays/kotlin-lsp.nix)
    inputs.niri.overlays.niri
    (import ../overlays/niri.nix)
    inputs.nix-cachyos-kernel.overlays.pinned
    (import ../overlays/profile-sync-daemon.nix)
    (import ../overlays/user-scanner.nix)
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
  ];
in
{
  mkHost =
    {
      hostname,
      system ? "x86_64-linux",
      # Host capability flags
      cpuVendor ? "intel", # "amd" or "intel"
      hasFingerprint ? false,
      hasTouchscreen ? false,
    }:
    lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit inputs;
        hostConfig = {
          inherit
            hostname
            cpuVendor
            hasFingerprint
            hasTouchscreen
            ;
        };
      };
      modules = [
        # Apply common overlays
        { nixpkgs.overlays = commonOverlays; }
        # Host-specific configuration (imports nixos-hardware, lanzaboote, etc.)
        ../hosts/${hostname}
        ../hosts/${hostname}/home.nix
        # Common modules
        inputs.home-manager.nixosModules.home-manager
        inputs.stylix.nixosModules.stylix
      ];
    };
}
