{ config, pkgs, ... }:

{
  # Darkman configuration
  home.file.".config/darkman/config.yaml".text = ''
    lat: 48.13743
    lng: 11.57549
  '';

  # Restart darkman after home-manager activation to re-evaluate current theme
  # Only restart if we're not already being run by darkman (avoid infinite loop)
  home.activation.restartDarkman = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    # Check if DARKMAN_RUNNING environment variable is set
    # Use parameter expansion with default to avoid "unbound variable" error
    if [ -z "''${DARKMAN_RUNNING:-}" ]; then
      $DRY_RUN_CMD ${pkgs.systemd}/bin/systemctl --user restart darkman.service || true
    fi
  '';

  # Darkman scripts for theme switching
  # Note: darkman looks for scripts in XDG_DATA_HOME/light-mode.d and XDG_DATA_HOME/dark-mode.d
  # NOT in a darkman subdirectory!

  # Unified theme switching script
  home.file.".local/share/darkman-switch-mode.sh" = {
    source = pkgs.replaceVars ./darkman-switch-mode.sh {
      dconf = "${pkgs.dconf}";
      systemd = "${pkgs.systemd}";
      jq = "${pkgs.jq}";
      niri = "${pkgs.niri}";
      coreutils = "${pkgs.coreutils}";
    };
    executable = true;
  };

  # Light mode wrapper
  home.file.".local/share/light-mode.d/stylix.sh" = {
    text = ''
      #!/run/current-system/sw/bin/bash
      exec ~/.local/share/darkman-switch-mode.sh light
    '';
    executable = true;
  };

  # Dark mode wrapper
  home.file.".local/share/dark-mode.d/stylix.sh" = {
    text = ''
      #!/run/current-system/sw/bin/bash
      exec ~/.local/share/darkman-switch-mode.sh dark
    '';
    executable = true;
  };
}
