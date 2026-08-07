# Single source of truth for binary caches.
#
# Used by both flake.nix (nixConfig, for non-NixOS/CI consumers and the
# sudo-level trusted caches) and modules/system/core.nix (nix.settings, which
# is what actually applies at runtime on NixOS). Keep these lists updated here
# only, so the two don't drift.
{
  substituters = [
    "https://claude-code.cachix.org"
    "https://devenv.cachix.org"
    "https://niri.cachix.org"
    "https://nix-community.cachix.org"
    "https://vicinae.cachix.org"
    "https://attic.xuyh0120.win/lantian"
  ];

  publicKeys = [
    "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
    "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
    "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "vicinae.cachix.org-1:1kDrfienkGHPYbkpNj1mWTr7Fm1+zcenzgTizIcI3oc="
    "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
  ];
}
