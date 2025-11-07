{ pkgs, ... }:

{
  # Enable DankMaterialShell
  programs.dankMaterialShell = {
    enable = true;
    enableSystemd = true;
    enableClipboard = true;
    enableBrightnessControl = true;

    # DankMaterialShell settings
    default.settings = {
      # Theme settings
      currentThemeName = "cat-blue";
      customThemeFile = "";
      matugenScheme = "scheme-tonal-spot";
      runUserMatugenTemplates = true;
      matugenTargetMonitor = "";

      # Transparency settings
      dankBarTransparency = 1;
      dankBarWidgetTransparency = 1;
      popupTransparency = 1;
      dockTransparency = 1;

      # Visual settings
      widgetBackgroundColor = "sch";
      surfaceBase = "s";
      cornerRadius = 12;

      # Time and date settings
      use24HourClock = true;
      showSeconds = false;
      useFahrenheit = false;
      clockCompactMode = false;
      clockDateFormat = "";
      lockDateFormat = "";

      # Animations
      nightModeEnabled = false;
      animationSpeed = 1;
      customAnimationDuration = 500;

      # Wallpaper
      wallpaperFillMode = "Fill";
      blurredWallpaperLayer = false;
      blurWallpaperOnOverview = false;

      # DankBar widget visibility
      showLauncherButton = true;
      showWorkspaceSwitcher = true;
      showFocusedWindow = true;
      showWeather = true;
      showMusic = true;
      showClipboard = true;
      showCpuUsage = true;
      showMemUsage = true;
      showCpuTemp = true;
      showGpuTemp = true;
      selectedGpuIndex = 0;
      enabledGpuPciIds = [ ];
      showSystemTray = true;
      showClock = true;
      showNotificationButton = true;
      showBattery = true;
      showControlCenterButton = true;

      # Control center
      controlCenterShowNetworkIcon = true;
      controlCenterShowBluetoothIcon = true;
      controlCenterShowAudioIcon = true;
      controlCenterWidgets = [
        {
          id = "volumeSlider";
          enabled = true;
          width = 50;
        }
        {
          id = "brightnessSlider";
          enabled = true;
          width = 50;
        }
        {
          id = "wifi";
          enabled = true;
          width = 50;
        }
        {
          id = "bluetooth";
          enabled = true;
          width = 50;
        }
        {
          id = "audioOutput";
          enabled = true;
          width = 50;
        }
        {
          id = "audioInput";
          enabled = true;
          width = 50;
        }
        {
          id = "nightMode";
          enabled = true;
          width = 50;
        }
        {
          id = "darkMode";
          enabled = true;
          width = 50;
        }
      ];

      # Workspace settings
      showWorkspaceIndex = false;
      showWorkspacePadding = false;
      workspaceScrolling = false;
      showWorkspaceApps = true;
      maxWorkspaceIcons = 3;
      workspacesPerMonitor = false;
      dwlShowAllTags = false;
      workspaceNameIcons = { };

      # Widget compact modes
      waveProgressEnabled = true;
      focusedWindowCompactMode = false;
      runningAppsCompactMode = true;
      keyboardLayoutNameCompactMode = false;
      runningAppsCurrentWorkspace = true;
      runningAppsGroupByApp = false;

      # Media settings
      mediaSize = 1;

      # DankBar widget layout
      dankBarLeftWidgets = [
        "workspaceSwitcher"
        "focusedWindow"
      ];
      dankBarCenterWidgets = [
        "music"
        "clock"
        "weather"
      ];
      dankBarRightWidgets = [
        "systemTray"
        "clipboard"
        "cpuUsage"
        "memUsage"
        "notificationButton"
        "battery"
        "controlCenterButton"
      ];
      dankBarWidgetOrder = [ ];

      # Launcher settings
      appLauncherViewMode = "list";
      spotlightModalViewMode = "list";
      sortAppsAlphabetically = false;
      launcherLogoMode = "os";
      launcherLogoCustomPath = "";
      launcherLogoColorOverride = "";
      launcherLogoColorInvertOnMode = false;
      launcherLogoBrightness = 0.5;
      launcherLogoContrast = 1;
      launcherLogoSizeOffset = 0;

      # Weather settings
      weatherLocation = "New York, NY";
      weatherCoordinates = "40.7128,-74.0060";
      useAutoLocation = false;
      weatherEnabled = true;

      # Network settings
      networkPreference = "auto";
      vpnLastConnected = "";

      # Theme settings
      iconTheme = "System Default";
      gtkThemingEnabled = false;
      qtThemingEnabled = false;
      syncModeWithPortal = true;

      # Font settings
      fontFamily = "Inter Variable";
      monoFontFamily = "Fira Code";
      fontWeight = 400;
      fontScale = 1;
      dankBarFontScale = 1;

      # Notepad settings
      notepadUseMonospace = true;
      notepadFontFamily = "";
      notepadFontSize = 14;
      notepadShowLineNumbers = false;
      notepadTransparencyOverride = -1;
      notepadLastCustomTransparency = 0.7;

      # Sound settings
      soundsEnabled = true;
      useSystemSoundTheme = false;
      soundNewNotification = true;
      soundVolumeChanged = true;
      soundPluggedIn = true;

      # Power management
      acMonitorTimeout = 0;
      acLockTimeout = 0;
      acSuspendTimeout = 0;
      acSuspendBehavior = 0;
      batteryMonitorTimeout = 0;
      batteryLockTimeout = 0;
      batterySuspendTimeout = 0;
      batterySuspendBehavior = 0;
      lockBeforeSuspend = true;
      loginctlLockIntegration = true;

      # Misc settings
      launchPrefix = "";
      brightnessDevicePins = { };

      # Dock settings
      showDock = false;
      dockAutoHide = false;
      dockGroupByApp = false;
      dockOpenOnOverview = false;
      dockPosition = 1;
      dockSpacing = 4;
      dockBottomGap = 0;
      dockIconSize = 40;
      dockIndicatorStyle = "circle";

      # Notification settings
      notificationOverlayEnabled = false;
      notificationTimeoutLow = 5000;
      notificationTimeoutNormal = 5000;
      notificationTimeoutCritical = 0;
      notificationPopupPosition = 0;

      # DankBar behavior (CRITICAL: Only show in Niri overview mode)
      dankBarAutoHide = false;
      dankBarOpenOnOverview = true;
      dankBarVisible = false;

      # DankBar appearance
      dankBarSpacing = 0;
      dankBarBottomGap = 0;
      dankBarInnerPadding = 16;
      dankBarPosition = 0;
      dankBarSquareCorners = true;
      dankBarNoBackground = false;
      dankBarGothCornersEnabled = false;
      dankBarBorderEnabled = false;
      dankBarBorderColor = "surfaceText";
      dankBarBorderOpacity = 1;
      dankBarBorderThickness = 1;

      # Popup settings
      popupGapsAuto = true;
      popupGapsManual = 13;
      modalDarkenBackground = true;

      # Lock screen
      lockScreenShowPowerActions = true;
      enableFprint = false;
      maxFprintTries = 3;

      # Other UI settings
      hideBrightnessSlider = false;
      osdAlwaysShowValue = true;
      powerActionConfirm = true;

      # Custom power actions
      customPowerActionLock = "";
      customPowerActionLogout = "";
      customPowerActionSuspend = "";
      customPowerActionHibernate = "";
      customPowerActionReboot = "";
      customPowerActionPowerOff = "";

      # Updater settings
      updaterUseCustomCommand = false;
      updaterCustomCommand = "";
      updaterTerminalAdditionalParams = "";

      # Display preferences
      screenPreferences = { };
      showOnLastDisplay = { };

      # Config version
      configVersion = 1;
    };

    # DankMaterialShell session data (wallpaper, etc.)
    default.session = {
      wallpaperPath = "${./wallpapers/mountain.jpg}";
      perMonitorWallpaper = false;
      monitorWallpapers = { };
      perModeWallpaper = false;
      wallpaperPathLight = "";
      wallpaperPathDark = "";
      monitorWallpapersLight = { };
      monitorWallpapersDark = { };
      wallpaperCyclingEnabled = false;
      wallpaperCyclingMode = "interval";
      wallpaperCyclingInterval = 300;
      wallpaperCyclingTime = "06:00";
      wallpaperTransition = "fade";
    };
  };

  # DankMaterialShell dependencies
  home.packages = with pkgs; [
    brightnessctl # Brightness control
    mako # Notification daemon for Wayland
    libnotify # Notification library
  ];
}
