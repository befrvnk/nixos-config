{ inputs, pkgs, ... }:
{
  cache-trust =
    let
      shared = import ../shared/caches.nix;
      declared = (import ../flake.nix).nixConfig;
      runtime =
        if pkgs.stdenv.hostPlatform.isLinux then
          inputs.self.nixosConfigurations.framework.config.nix.settings
        else
          { };
      safe =
        value: !(pkgs.lib.hasInfix "attic.xuyh0120.win" value) && !(pkgs.lib.hasPrefix "lantian:" value);
      values =
        shared.substituters
        ++ shared.publicKeys
        ++ (runtime.substituters or [ ])
        ++ (runtime.trusted-public-keys or [ ])
        ++ (runtime.extra-substituters or [ ])
        ++ (runtime.extra-trusted-public-keys or [ ]);
    in
    assert pkgs.lib.assertMsg (
      declared.extra-substituters == shared.substituters
      && declared.extra-trusted-public-keys == shared.publicKeys
    ) "Flake cache literals must match shared cache policy";
    assert pkgs.lib.assertMsg (builtins.all safe values)
      "The compromised Lantian endpoint and signing key must not be trusted";
    pkgs.runCommand "cache-trust-check" { } ''
      touch $out
    '';

}
