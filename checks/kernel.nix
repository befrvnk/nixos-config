{
  inputs,
  pkgs,
  system,
  ...
}:
{
  kernel-provider-compat =
    let
      framework = inputs.self.nixosConfigurations.framework;
      provider = inputs.chaotic.inputs.nixpkgs.legacyPackages.${system};
      standard = framework.extendModules {
        modules = [
          ({ lib, pkgs, ... }: { boot.kernelPackages = lib.mkForce pkgs.linuxPackages; })
        ];
      };
      aggregator = packages: (packages.aggregateModules [ ]).drvPath;
    in
    assert pkgs.lib.assertMsg (
      aggregator framework.pkgs == aggregator provider
    ) "CachyOS modules must use their provider's matching aggregation format";
    assert pkgs.lib.assertMsg (
      aggregator standard.pkgs == aggregator pkgs
    ) "Standard kernels must retain main nixpkgs' certificate-aware aggregation";
    pkgs.runCommand "kernel-provider-compat-check" { } ''
      touch $out
    '';

}
