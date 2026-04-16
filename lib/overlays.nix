{ inputs }:
let
  sharedOverlays = [
    inputs.claude-code.overlays.default
    (import ../overlays/gh-enhance.nix)
    (import ../overlays/kotlin-lsp.nix)
    (import ../overlays/pi-coding-agent.nix)
    (import ../overlays/user-scanner.nix)

    # opencode from flake
    # Keep build-time Bun aligned with this repo's nixpkgs Bun so temporary pins
    # to older upstream revisions do not fail the packageManager version check.
    (final: prev: {
      opencode = inputs.opencode.packages.${prev.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
        nativeBuildInputs = [ prev.bun ] ++ (old.nativeBuildInputs or [ ]) ++ [ prev.nodejs ];
        postConfigure = (old.postConfigure or "") + ''
          sed -i 's/"packageManager": "bun@[^"]*"/"packageManager": "bun@${prev.bun.version}"/' package.json
          chmod -R u+w node_modules packages
          patchShebangs node_modules packages/*/node_modules
        '';
      });
    })

    # Extra packages from flakes
    (final: prev: {
      devenvLatest = inputs.devenv.packages.${prev.stdenv.hostPlatform.system}.devenv.overrideAttrs {
        doCheck = false;
      };
      worktrunk = inputs.worktrunk.packages.${prev.stdenv.hostPlatform.system}.default;
      agent-of-empires = inputs.agent-of-empires.packages.${prev.stdenv.hostPlatform.system}.default;
    })
  ];

  nixosOverlays = sharedOverlays ++ [
    inputs.android-nixpkgs.overlays.default
    (import ../overlays/android-studio-canary.nix)
    (import ../overlays/claude-code.nix)
    (import ../overlays/domain-check.nix)
    (import ../overlays/idea-community.nix)
    inputs.niri.overlays.niri
    (import ../overlays/niri.nix)
    inputs.nix-cachyos-kernel.overlays.pinned
    (import ../overlays/profile-sync-daemon.nix)
  ];

  darwinOverlays = sharedOverlays ++ [
    # direnv: fix cgo required for -linkmode=external on Darwin
    (final: prev: {
      direnv = prev.direnv.overrideAttrs (old: {
        env = (old.env or { }) // {
          CGO_ENABLED = "1";
        };
      });
    })
    # Nushell 0.112.1 currently fails Darwin sandboxed SHLVL tests with
    # "Operation not permitted"; keep the package buildable until upstream/nixpkgs catches up.
    (final: prev: {
      nushell = prev.nushell.overrideAttrs {
        doCheck = false;
      };
    })
    # OpenChamber: desktop GUI for OpenCode AI agent
    (import ../overlays/openchamber.nix)
    (import ../overlays/supacode.nix)
  ];
in
{
  inherit darwinOverlays nixosOverlays;
}
