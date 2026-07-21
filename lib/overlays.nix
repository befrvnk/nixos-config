{ inputs }:
let
  sharedOverlays = [
    inputs.claude-code.overlays.default
    (import ../overlays/gh-enhance.nix)
    (import ../overlays/kotlin-lsp.nix)
    (import ../overlays/pi-coding-agent.nix)
    (import ../overlays/user-scanner.nix)

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
    (import ../overlays/supacode.nix)
  ];
in
{
  inherit darwinOverlays nixosOverlays;
}
