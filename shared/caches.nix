# Single source of truth for binary caches.
#
# Used by both flake.nix (nixConfig, for non-NixOS/CI consumers and the
# sudo-level trusted caches) and modules/system/core.nix (nix.settings, which
# is what actually applies at runtime on NixOS). Keep these lists updated here
# only, so the two don't drift.
{
  # EU mirror/proxy of cache.nixos.org (Hetzner, Germany). It serves narinfos
  # signed by cache.nixos.org's own key, so no extra public key is required.
  # Its nix-cache-info Priority (39) is lower than the official cache (40), so
  # nix prefers this mirror automatically and falls back to cache.nixos.org
  # for any paths the mirror is missing.
  substituters = [
    "https://nixos.snix.store"
    "https://claude-code.cachix.org"
    "https://devenv.cachix.org"
    "https://niri.cachix.org"
    "https://nix-community.cachix.org"
    "https://nixos-raspberrypi.cachix.org"
    "https://vicinae.cachix.org"
    "https://attic.xuyh0120.win/lantian"
  ];

  publicKeys = [
    "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
    "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
    "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    "vicinae.cachix.org-1:1kDrfienkGHPYbkpNj1mWTr7Fm1+zcenzgTizIcI3oc="
    "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
  ];
}
