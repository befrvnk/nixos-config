{ inputs }:
let
  sharedOverlays = [
    inputs.claude-code.overlays.default
    (import ../overlays/gh-enhance.nix)
    (import ../overlays/kotlin-lsp.nix)
    (import ../overlays/pi-coding-agent.nix)
    (import ../overlays/user-scanner.nix)

    # opencode from flake
    # Keep build-time Bun aligned with this repo's nixpkgs Bun and pin the
    # mutable ghostty-web Git dependency to the commit already recorded in the
    # upstream lockfile so bun --frozen-lockfile stays reproducible.
    (
      final: prev:
      let
        opencodeRev =
          inputs.opencode.shortRev
            or (if inputs.opencode ? rev then builtins.substring 0 7 inputs.opencode.rev else "dirty");

        opencodeSrc = prev.runCommand "opencode-source-${opencodeRev}" { } ''
          cp -R ${inputs.opencode.outPath}/. $out
          chmod -R u+w $out
          sed -i 's#"packageManager": "bun@[^"]*"#"packageManager": "bun@${prev.bun.version}"#' $out/package.json
          sed -i 's|"ghostty-web": "github:anomalyco/ghostty-web#main"|"ghostty-web": "github:anomalyco/ghostty-web#4af877d"|' $out/packages/app/package.json
        '';

        node_modules =
          (prev.callPackage "${inputs.opencode.outPath}/nix/node_modules.nix" {
            inherit (prev) bun;
            rev = opencodeRev;
          }).overrideAttrs
            {
              src = opencodeSrc;
            };
      in
      {
        opencode =
          (prev.callPackage "${inputs.opencode.outPath}/nix/opencode.nix" {
            inherit (prev) bun;
            inherit node_modules;
          }).overrideAttrs
            (old: {
              nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.nodejs ];
              postConfigure = (old.postConfigure or "") + ''
                chmod -R u+w node_modules packages
                patchShebangs node_modules packages/*/node_modules
              '';
            });
      }
    )

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
    (import ../overlays/orca-ai.nix)
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
