{
  config,
  pkgs,
  inputs,
  ...
}:

let
  wallpapers = import ../wallpapers;
in
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

      # After restart, wait for awww-daemon to be ready and apply initial wallpaper
      # This ensures wallpaper is set on boot and after home-manager switches
      if [ -z "$DRY_RUN_CMD" ]; then
        for i in {1..10}; do
          if ${inputs.awww.packages.${pkgs.system}.awww}/bin/awww query &>/dev/null; then
            MODE=$(${pkgs.darkman}/bin/darkman get) || MODE="dark"
            ~/.local/share/darkman-switch-mode.sh "$MODE" &>/dev/null || true
            break
          fi
          sleep 0.5
        done &
      fi
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
      gnugrep = "${pkgs.gnugrep}";
      gnused = "${pkgs.gnused}";
      awww = "${inputs.awww.packages.${pkgs.system}.awww}";
      wallpaper_light = "${wallpapers.light}";
      wallpaper_dark = "${wallpapers.dark}";
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
