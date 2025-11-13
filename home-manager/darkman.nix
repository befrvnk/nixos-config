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
  home.file.".local/share/light-mode.d/stylix.sh" = {
    text = ''
      #!/run/current-system/sw/bin/bash
      # Set environment variable to prevent infinite restart loop
      export DARKMAN_RUNNING=1
      export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(${pkgs.coreutils}/bin/id -u)/bus"

      # Find the home-manager generation with specialisations from the current system
      HM_GEN=$(/run/current-system/sw/bin/nix-store -qR /run/current-system | /run/current-system/sw/bin/grep home-manager-generation | while read gen; do
        if [ -d "$gen/specialisation" ]; then
          echo "$gen"
          break
        fi
      done)

      if [ -z "$HM_GEN" ]; then
        echo "Error: Could not find home-manager generation with specialisations" >&2
        exit 1
      fi

      "$HM_GEN/specialisation/light/activate"

      # Set freedesktop portal color scheme preference AFTER specialization activation
      # This ensures Stylix doesn't override it
      ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/color-scheme "'prefer-light'"

      # Restart Ironbar to pick up new theme CSS
      ${pkgs.systemd}/bin/systemctl --user restart ironbar.service || true

      # Trigger Niri screen transition effect
      NIRI_SOCKET=$(/run/current-system/sw/bin/find /run/user/* -maxdepth 1 -name 'niri*.sock' 2>/dev/null | /run/current-system/sw/bin/head -n1)
      if [ -n "$NIRI_SOCKET" ]; then
        NIRI_SOCKET="$NIRI_SOCKET" ${pkgs.niri}/bin/niri msg action do-screen-transition
      fi
    '';
    executable = true;
  };

  home.file.".local/share/dark-mode.d/stylix.sh" = {
    text = ''
      #!/run/current-system/sw/bin/bash
      # Set environment variable to prevent infinite restart loop
      export DARKMAN_RUNNING=1
      export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(${pkgs.coreutils}/bin/id -u)/bus"

      # Find the home-manager generation with specialisations from the current system
      HM_GEN=$(/run/current-system/sw/bin/nix-store -qR /run/current-system | /run/current-system/sw/bin/grep home-manager-generation | while read gen; do
        if [ -d "$gen/specialisation" ]; then
          echo "$gen"
          break
        fi
      done)

      if [ -z "$HM_GEN" ]; then
        echo "Error: Could not find home-manager generation with specialisations" >&2
        exit 1
      fi

      "$HM_GEN/specialisation/dark/activate"

      # Set freedesktop portal color scheme preference AFTER specialization activation
      # This ensures Stylix doesn't override it
      ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"

      # Restart Ironbar to pick up new theme CSS
      ${pkgs.systemd}/bin/systemctl --user restart ironbar.service || true

      # Trigger Niri screen transition effect
      NIRI_SOCKET=$(/run/current-system/sw/bin/find /run/user/* -maxdepth 1 -name 'niri*.sock' 2>/dev/null | /run/current-system/sw/bin/head -n1)
      if [ -n "$NIRI_SOCKET" ]; then
        NIRI_SOCKET="$NIRI_SOCKET" ${pkgs.niri}/bin/niri msg action do-screen-transition
      fi
    '';
    executable = true;
  };
}
