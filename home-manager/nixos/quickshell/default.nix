{
  pkgs,
  config,
  lib,
  inputs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;

  # Quickshell built with the Niri QML plugin for niri (from the qml-niri flake).
  quickshell = inputs.qml-niri.packages.${system}.quickshell;

  # Standalone qml-niri plugin package; exposes the Qt QML import path for `import Niri`.
  # NOTE: nixpkgs Qt 6 uses the dash form `lib/qt-6/qml` (not `lib/qt6/qml`).
  qmlNiriPlugin = inputs.qml-niri.packages.${system}.default;
  qmlImportPath = "${qmlNiriPlugin}/lib/qt-6/qml";

  shellDir = ./config/shell;

  # Wrap an existing ironbar module script with an explicit store PATH.
  # Kept self-contained in the quickshell module (independent of the ironbar
  # lifecycle) so Phase 4 / the Go rewrite can swap these cleanly.
  wrapScript =
    name: path:
    pkgs.writeShellScript name ''
      export PATH="${
        lib.makeBinPath [
          pkgs.curl
          pkgs.jq
          pkgs.gawk
          pkgs.gnugrep
          pkgs.coreutils
          pkgs.procps
          pkgs.dunst
          pkgs.systemd
        ]
      }"
      ${builtins.readFile path}
    '';

  # openrouter: the scripts call a sibling account.sh via $DIR, so they live in
  # one directory together. Caller wrappers export PATH, inherited by siblings.
  openrouter-scripts = pkgs.runCommand "qs-openrouter" { } ''
    mkdir -p $out
    cat > $out/account.sh <<'EOF'
    ${builtins.readFile ../ironbar/modules/openrouter/account.sh}
    EOF
    cat > $out/openrouter-status.sh <<'EOF'
    export PATH="${
      lib.makeBinPath [
        pkgs.curl
        pkgs.jq
        pkgs.gawk
        pkgs.coreutils
      ]
    }"
    ${builtins.readFile ../ironbar/modules/openrouter/openrouter-status.sh}
    EOF
    cat > $out/openrouter-details.sh <<'EOF'
    export PATH="${
      lib.makeBinPath [
        pkgs.curl
        pkgs.jq
        pkgs.gawk
        pkgs.coreutils
      ]
    }"
    ${builtins.readFile ../ironbar/modules/openrouter/openrouter-details.sh}
    EOF
    chmod +x $out/*.sh
  '';

  scripts = rec {
    openrouter-status = "${openrouter-scripts}/openrouter-status.sh";
    openrouter-details = "${openrouter-scripts}/openrouter-details.sh";

    firewall-status = wrapScript "qs-firewall-status" ../ironbar/modules/firewall/firewall-status.sh;
    firewall-details = wrapScript "qs-firewall-details" ../ironbar/modules/firewall/firewall-details.sh;
    firewall-has-refused = wrapScript "qs-firewall-has-refused" ../ironbar/modules/firewall/has-refused.sh;

    aurora-status = wrapScript "qs-aurora-status" ../ironbar/modules/aurora/aurora-status.sh;
    aurora-details = wrapScript "qs-aurora-details" ../ironbar/modules/aurora/aurora-details.sh;
    aurora-has-activity = wrapScript "qs-aurora-has-activity" ../ironbar/modules/aurora/has-aurora-activity.sh;

    weather-status = wrapScript "qs-weather-status" ../ironbar/modules/weather/weather-status.sh;
    weather-forecast = wrapScript "qs-weather-forecast" ../ironbar/modules/weather/weather-forecast.sh;
    weather-has-data = wrapScript "qs-weather-has-data" ../ironbar/modules/weather/has-weather-data.sh;

    notif-count = wrapScript "qs-notif-count" ../ironbar/modules/notifications/notification-count.sh;
    notif-history = wrapScript "qs-notif-history" ../ironbar/modules/notifications/notification-history.sh;
    notif-clear = pkgs.writeShellScript "qs-notif-clear" ''
      export PATH="${lib.makeBinPath [ pkgs.dunst ]}"
      exec ${pkgs.dunst}/bin/dunstctl history-clear
    '';

    peripheral-status = wrapScript "qs-peripheral-status" ../ironbar/modules/peripheral-battery/peripheral-battery-status.sh;
    peripheral-has = wrapScript "qs-peripheral-has" ../ironbar/modules/peripheral-battery/has-peripherals-connected.sh;

    sysinfo-status = pkgs.writeShellScript "qs-sysinfo-status" ''
      export PATH="${
        lib.makeBinPath [
          pkgs.procps
          pkgs.coreutils
          pkgs.gawk
        ]
      }"
      ${builtins.readFile ./sysinfo-status.sh}
    '';

    # --- Storage (Phase 2) ---
    storage-status = pkgs.writeShellScript "qs-storage-status" ''
      export PATH="${
        lib.makeBinPath [
          pkgs.util-linux
          pkgs.coreutils
        ]
      }"
      ${builtins.readFile ../ironbar/modules/storage/storage-status.sh}
    '';
    storage-has = pkgs.writeShellScript "qs-storage-has" ''
      export PATH="${
        lib.makeBinPath [
          pkgs.util-linux
          pkgs.coreutils
        ]
      }"
      ${builtins.readFile ../ironbar/modules/storage/has-mounted-devices.sh}
    '';
    storage-list = pkgs.writeShellScript "qs-storage-list" ''
      export PATH="${
        lib.makeBinPath [
          pkgs.util-linux
          pkgs.coreutils
          pkgs.gawk
        ]
      }"
      ${builtins.readFile ./storage-list.sh}
    '';
    storage-open = pkgs.writeShellScript "qs-storage-open" ''
      export PATH="${
        lib.makeBinPath [
          pkgs.util-linux
          pkgs.coreutils
          pkgs.nautilus
        ]
      }"
      ${builtins.readFile ./storage-open.sh}
    '';
    storage-eject = pkgs.writeShellScript "qs-storage-eject" ''
      export PATH="${
        lib.makeBinPath [
          pkgs.util-linux
          pkgs.coreutils
          pkgs.udisks
        ]
      }"
      ${builtins.readFile ./storage-eject.sh}
    '';

    # --- Battery (Phase 2) ---
    battery-status = pkgs.writeShellScript "qs-battery-status" ''
      export PATH="${
        lib.makeBinPath [
          pkgs.upower
          pkgs.gawk
          pkgs.gnugrep
          pkgs.coreutils
        ]
      }"
      ${builtins.readFile ../ironbar/modules/battery/battery-status.sh}
    '';
    battery-details = pkgs.writeShellScript "qs-battery-details" ''
      export PATH="${
        lib.makeBinPath [
          pkgs.upower
          pkgs.gawk
          pkgs.gnugrep
          pkgs.coreutils
        ]
      }"
      ${builtins.readFile ../ironbar/modules/battery/battery-details.sh}
    '';
    battery-get-profile = pkgs.writeShellScript "qs-battery-get-profile" ''
      export PATH="${lib.makeBinPath [ pkgs.coreutils ]}"
      cat /sys/firmware/acpi/platform_profile
    '';
    battery-set-profile = pkgs.writeShellScript "qs-battery-set-profile" ''
      export PATH="${
        lib.makeBinPath [
          pkgs.tuned
          pkgs.coreutils
        ]
      }"
      case "$1" in
        low-power)   exec ${pkgs.tuned}/bin/tuned-adm profile framework-battery ;;
        balanced)    exec ${pkgs.tuned}/bin/tuned-adm profile framework-ac ;;
        performance) exec ${pkgs.tuned}/bin/tuned-adm profile throughput-performance ;;
        *) echo "unknown profile: $1" >&2; exit 1 ;;
      esac
    '';

    # --- WiFi (Phase 3, flagship interactive) ---
    # wifi-status needs nmcli (networkmanager); the generic wrapScript PATH lacks it.
    wifi-status = pkgs.writeShellScript "qs-wifi-status" ''
      export PATH="${
        lib.makeBinPath [
          pkgs.networkmanager
          pkgs.coreutils
          pkgs.gnugrep
        ]
      }"
      ${builtins.readFile ../ironbar/modules/wifi/wifi-status.sh}
    '';
    wifi-list = pkgs.writeShellScript "qs-wifi-list" ''
      export PATH="${
        lib.makeBinPath [
          pkgs.networkmanager
          pkgs.coreutils
        ]
      }"
      ${builtins.readFile ./wifi-list.sh}
    '';
    wifi-toggle = pkgs.writeShellScript "qs-wifi-toggle" ''
      export PATH="${
        lib.makeBinPath [
          pkgs.networkmanager
          pkgs.coreutils
        ]
      }"
      ${builtins.readFile ./wifi-toggle.sh}
    '';
    wifi-connect = pkgs.writeShellScript "qs-wifi-connect" ''
      export PATH="${
        lib.makeBinPath [
          pkgs.networkmanager
          pkgs.coreutils
        ]
      }"
      ${builtins.readFile ./wifi-connect.sh}
    '';
    wifi-disconnect = pkgs.writeShellScript "qs-wifi-disconnect" ''
      export PATH="${
        lib.makeBinPath [
          pkgs.networkmanager
          pkgs.coreutils
        ]
      }"
      ${builtins.readFile ./wifi-disconnect.sh}
    '';

    # --- Bluetooth (Phase 3, interactive) ---
    bluetooth-status = pkgs.writeShellScript "qs-bluetooth-status" ''
      export PATH="${
        lib.makeBinPath [
          pkgs.bluez
          pkgs.coreutils
          pkgs.gnugrep
        ]
      }"
      ${builtins.readFile ./bluetooth-status.sh}
    '';
    bluetooth-list = pkgs.writeShellScript "qs-bluetooth-list" ''
      export PATH="${
        lib.makeBinPath [
          pkgs.bluez
          pkgs.coreutils
        ]
      }"
      ${builtins.readFile ./bluetooth-list.sh}
    '';
    bluetooth-connect = pkgs.writeShellScript "qs-bluetooth-connect" ''
      export PATH="${
        lib.makeBinPath [
          pkgs.bluez
          pkgs.coreutils
        ]
      }"
      ${builtins.readFile ./bluetooth-connect.sh}
    '';

    # --- Volume (Phase 3, interactive slider) ---
    volume-status = wrapScript "volume-status" ../ironbar/modules/volume/volume-status.sh;
    volume-set = pkgs.writeShellScript "qs-volume-set" ''
      export PATH="${
        lib.makeBinPath [
          pkgs.wireplumber
          pkgs.swayosd
          pkgs.coreutils
        ]
      }"
      ${builtins.readFile ./volume-set.sh}
    '';

    # --- Brightness / display (Phase 3) ---
    display-status = wrapScript "qs-display-status" ../ironbar/modules/display/display-status.sh;
    display-details = wrapScript "qs-display-details" ../ironbar/modules/display/display-details.sh;
    display-abm-btn = wrapScript "qs-display-abm" ../ironbar/modules/display/get-auto-status.sh;
    display-abm-toggle = wrapScript "qs-display-abm-toggle" ../ironbar/modules/display/toggle-auto.sh;
    display-stay-btn = wrapScript "qs-display-stay-btn" ../ironbar/modules/display/get-stay-on-status.sh;
    display-stay-toggle = wrapScript "qs-display-stay-toggle" ../ironbar/modules/display/toggle-stay-on.sh;
    display-redlight-btn = wrapScript "qs-display-redlight-btn" ../ironbar/modules/display/get-redlight-status.sh;
    display-redlight-toggle = wrapScript "qs-display-redlight-toggle" ../ironbar/modules/display/toggle-redlight.sh;
    brightness-set = pkgs.writeShellScript "qs-brightness-set" ''
      export PATH="${
        lib.makeBinPath [
          pkgs.brightnessctl
          pkgs.swayosd
          pkgs.coreutils
        ]
      }"
      ${builtins.readFile ./brightness-set.sh}
    '';
  };

  # Generate a QML singleton that exposes the Stylix palette + resolved script
  # paths. Regenerated on every rebuild so it tracks script store paths.
  configQml = pkgs.runCommand "quickshell-config" { } ''
    mkdir -p $out/modules/common
    cat > $out/modules/common/Config.qml <<'QML'
    pragma Singleton
    import QtQuick
    import Quickshell

    Singleton {
      readonly property string base00: "#${config.lib.stylix.colors.base00}"
      readonly property string base01: "#${config.lib.stylix.colors.base01}"
      readonly property string base02: "#${config.lib.stylix.colors.base02}"
      readonly property string base03: "#${config.lib.stylix.colors.base03}"
      readonly property string base04: "#${config.lib.stylix.colors.base04}"
      readonly property string base05: "#${config.lib.stylix.colors.base05}"
      readonly property string base06: "#${config.lib.stylix.colors.base06}"
      readonly property string base07: "#${config.lib.stylix.colors.base07}"
      readonly property string base08: "#${config.lib.stylix.colors.base08}"
      readonly property string base09: "#${config.lib.stylix.colors.base09}"
      readonly property string base0A: "#${config.lib.stylix.colors.base0A}"
      readonly property string base0B: "#${config.lib.stylix.colors.base0B}"
      readonly property string base0C: "#${config.lib.stylix.colors.base0C}"
      readonly property string base0D: "#${config.lib.stylix.colors.base0D}"
      readonly property string base0E: "#${config.lib.stylix.colors.base0E}"
      readonly property string base0F: "#${config.lib.stylix.colors.base0F}"

      // Bar font (matches ironbar; gives Nerd Font glyphs real advance width).
      readonly property string fontName: "JetBrainsMono Nerd Font"

      readonly property string openrouterStatus: "${scripts.openrouter-status}"
      readonly property string openrouterDetails: "${scripts.openrouter-details}"
      readonly property string firewallStatus: "${scripts.firewall-status}"
      readonly property string firewallDetails: "${scripts.firewall-details}"
      readonly property string firewallHasRefused: "${scripts.firewall-has-refused}"
      readonly property string auroraStatus: "${scripts.aurora-status}"
      readonly property string auroraDetails: "${scripts.aurora-details}"
      readonly property string auroraHasActivity: "${scripts.aurora-has-activity}"
      readonly property string weatherStatus: "${scripts.weather-status}"
      readonly property string weatherForecast: "${scripts.weather-forecast}"
      readonly property string weatherHasData: "${scripts.weather-has-data}"
      readonly property string notifCount: "${scripts.notif-count}"
      readonly property string notifHistory: "${scripts.notif-history}"
      readonly property string notifClear: "${scripts.notif-clear}"
      readonly property string peripheralStatus: "${scripts.peripheral-status}"
      readonly property string peripheralHas: "${scripts.peripheral-has}"
      readonly property string sysinfoStatus: "${scripts.sysinfo-status}"
      readonly property string storageStatus: "${scripts.storage-status}"
      readonly property string storageHas: "${scripts.storage-has}"
      readonly property string storageList: "${scripts.storage-list}"
      readonly property string storageOpen: "${scripts.storage-open}"
      readonly property string storageEject: "${scripts.storage-eject}"
      readonly property string batteryStatus: "${scripts.battery-status}"
      readonly property string batteryDetails: "${scripts.battery-details}"
      readonly property string batteryGetProfile: "${scripts.battery-get-profile}"
      readonly property string batterySetProfile: "${scripts.battery-set-profile}"
      readonly property string wifiStatus: "${scripts.wifi-status}"
      readonly property string wifiList: "${scripts.wifi-list}"
      readonly property string wifiToggle: "${scripts.wifi-toggle}"
      readonly property string wifiConnect: "${scripts.wifi-connect}"
      readonly property string wifiDisconnect: "${scripts.wifi-disconnect}"
      readonly property string bluetoothStatus: "${scripts.bluetooth-status}"
      readonly property string bluetoothList: "${scripts.bluetooth-list}"
      readonly property string bluetoothConnect: "${scripts.bluetooth-connect}"
      readonly property string volumeStatus: "${scripts.volume-status}"
      readonly property string volumeSet: "${scripts.volume-set}"
      readonly property string displayStatus: "${scripts.display-status}"
      readonly property string displayDetails: "${scripts.display-details}"
      readonly property string displayAbmBtn: "${scripts.display-abm-btn}"
      readonly property string displayAbmToggle: "${scripts.display-abm-toggle}"
      readonly property string displayStayBtn: "${scripts.display-stay-btn}"
      readonly property string displayStayToggle: "${scripts.display-stay-toggle}"
      readonly property string displayRedlightBtn: "${scripts.display-redlight-btn}"
      readonly property string displayRedlightToggle: "${scripts.display-redlight-toggle}"
      readonly property string brightnessSet: "${scripts.brightness-set}"
    }
    QML
  '';

  # Merge the hand-tracked shell config with the generated Config.qml so the
  # installed config is complete under ~/.config/quickshell/shell.
  # buildEnv merges nested directories recursively (symlinkJoin would not).
  shellContents = pkgs.buildEnv {
    name = "quickshell-shell-contents";
    paths = [
      shellDir
      configQml
    ];
  };
in
{
  home.packages = [ quickshell ];

  xdg.configFile."quickshell/shell".source = shellContents;

  systemd.user.services.quickshell = {
    Unit = {
      Description = "Quickshell bar (overview-only, niri)";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };

    Service = {
      Type = "simple";
      ExecStartPre = "-${pkgs.procps}/bin/pkill -f quickshell";
      ExecStart = pkgs.writeShellScript "quickshell-run" ''
        export QT_QPA_PLATFORM=wayland
        export QML_IMPORT_PATH="${qmlImportPath}"
        export QML2_IMPORT_PATH="${qmlImportPath}"
        export QT_LOGGING_RULES="niri.debug=false"
        exec ${quickshell}/bin/quickshell --config shell
      '';
      Restart = "on-failure";
      RestartSec = "5s";
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
