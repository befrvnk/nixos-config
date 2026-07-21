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

        # nixpkgs' desktop package targets a newer upstream layout where the
        # Electron app lives in packages/desktop. Our pinned flake revision uses
        # packages/desktop-electron, so retarget the package and bundle the CLI
        # sidecar from the matching pinned opencode build.
        opencode-desktop = prev.opencode-desktop.overrideAttrs (old: {
          postPatch =
            builtins.replaceStrings
              [ "packages/desktop/src/main/constants.ts" ]
              [ "packages/desktop-electron/src/main/constants.ts" ]
              old.postPatch;

          buildPhase =
            builtins.replaceStrings
              [
                "bun --bun ./script/build-node.ts --skip-install"
                "cd packages/desktop"
                "cp -R icons/prod resources/icons"
              ]
              [
                ":"
                "cd packages/desktop-electron"
                ''
                  cp -R icons/prod resources/icons
                  install -Dm755 ${final.opencode}/bin/opencode resources/opencode-cli
                ''
              ]
              old.buildPhase;

          installPhase =
            builtins.replaceStrings
              [ "packages/desktop/" "packages/desktop" ]
              [ "packages/desktop-electron/" "packages/desktop-electron" ]
              old.installPhase;
        });
      }
    )

    # Extra packages from flakes
    (_final: prev: {
      worktrunk = inputs.worktrunk.packages.${prev.stdenv.hostPlatform.system}.default;
    })
  ];

  nixosOverlays = sharedOverlays ++ [
    inputs.android-nixpkgs.overlays.default
    (import ../overlays/android-studio-canary.nix { nixpkgsSrc = inputs.nixpkgs; })
    (import ../overlays/claude-code.nix)
    (import ../overlays/domain-check.nix)
    (import ../overlays/idea-community.nix)
    inputs.niri.overlays.niri
    (import ../overlays/niri.nix)
    inputs.nix-cachyos-kernel.overlays.pinned
    (import ../overlays/profile-sync-daemon.nix)
  ];

  darwinOverlays = sharedOverlays ++ [
    # nix-darwin's current manual builder still passes removed *-toc-depth
    # flags, but nixos-render-docs in nixpkgs unstable now requires --sidebar-depth.
    # Keep the generated Darwin manual buildable until nix-darwin updates.
    (_final: prev: {
      nixos-render-docs = prev.writeShellScriptBin "nixos-render-docs" ''
        set -euo pipefail

        args=()
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --toc-depth | --chunk-toc-depth | --section-toc-depth)
              args+=(--sidebar-depth)
              shift
              if [ "$#" -gt 0 ] && [ "''${1#-}" = "$1" ]; then
                args+=("$1")
                shift
              else
                args+=(1)
              fi
              ;;
            --toc-depth=* | --chunk-toc-depth=* | --section-toc-depth=*)
              args+=("--sidebar-depth=''${1#*=}")
              shift
              ;;
            *)
              args+=("$1")
              shift
              ;;
          esac
        done

        exec ${prev.lib.getExe prev.nixos-render-docs} "''${args[@]}"
      '';
    })
    # direnv: fix Darwin build issues until nixpkgs catches up
    # - CGO is required for -linkmode=external on Darwin
    # - checkPhase currently hangs/fails in shell integration tests on Darwin
    (final: prev: {
      direnv = prev.direnv.overrideAttrs (old: {
        env = (old.env or { }) // {
          CGO_ENABLED = "1";
        };
        doCheck = false;
      });
    })
    # Nushell 0.112.1 currently fails Darwin sandboxed SHLVL tests with
    # "Operation not permitted"; keep the package buildable until upstream/nixpkgs catches up.
    (final: prev: {
      nushell = prev.nushell.overrideAttrs {
        doCheck = false;
      };
    })
    # Desktop AI agent apps
    (import ../overlays/google-antigravity.nix)
    (import ../overlays/openchamber.nix)
    (import ../overlays/supacode.nix)
  ];
in
{
  inherit darwinOverlays nixosOverlays;
}
