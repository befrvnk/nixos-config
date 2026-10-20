# NixOS-specific runtime reader and aliases; shared integrations remain unchanged.
{ lib, ... }:
{
  programs.nushell = {
    extraConfig = builtins.readFile ./noctalia/nushell-theme.nu;
    shellAliases = {
      firewall-log = "journalctl -k | grep 'refused'";
      firewall-log-live = "sudo dmesg --follow | grep 'refused'";
    };
  };

  stylix.targets.nushell.enable = lib.mkForce false;
}
