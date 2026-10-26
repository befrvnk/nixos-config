{ pkgs, ... }:
{
  falcon-observer = pkgs.callPackage ../pkgs/falcon-observer/package.nix { };

  inherit (pkgs)
    google-antigravity
    openchamber
    supacode
    ;
}
