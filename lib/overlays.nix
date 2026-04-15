{ inputs }:
let
  sharedOverlays = [
    inputs.claude-code.overlays.default
    (import ../overlays/gh-enhance.nix)
    (import ../overlays/kotlin-lsp.nix)
    (import ../overlays/pi-coding-agent.nix)

    # opencode from flake (patch bun version check - upstream requires ^1.3.11 but nixpkgs has 1.3.10)
    (final: prev: {
      opencode = inputs.opencode.packages.${prev.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.nodejs ];
        postConfigure = (old.postConfigure or "") + ''
          sed -i 's/"packageManager": "bun@[^"]*"/"packageManager": "bun@${prev.bun.version}"/' package.json
          chmod -R u+w node_modules packages
          patchShebangs node_modules packages/*/node_modules
        '';
      });
    })

    # devenv/worktrunk/agent-of-empires from flakes
    (final: prev: {
      devenv = inputs.devenv.packages.${prev.stdenv.hostPlatform.system}.devenv.overrideAttrs {
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
    (import ../overlays/user-scanner.nix)
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
    # OpenChamber: desktop GUI for OpenCode AI agent
    (import ../overlays/openchamber.nix)
  ];
in
{
  inherit darwinOverlays nixosOverlays;
}
