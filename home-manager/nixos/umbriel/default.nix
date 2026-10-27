{
  config,
  inputs,
  lib,
  osConfig,
  pkgs,
  umbrielHomeModule,
  ...
}:
let
  enabled = osConfig.programs.umbriel.enable;
  audioInit = pkgs.writeShellScript "umbriel-framework-audio-init" ''
    ${pkgs.coreutils}/bin/timeout 0.5 ${pkgs.pipewire}/bin/pw-loopback --capture-props='media.class=Audio/Sink' --playback-props='node.target=@DEFAULT_AUDIO_SINK@' || true
  '';
  output = "${config.xdg.configHome}/umbriel/noctalia.toml";
in
{
  imports = [ umbrielHomeModule ];

  config = lib.mkIf enabled {
    programs.umbriel = {
      enable = true;
      package = osConfig.programs.umbriel.package;
      settings = {
        include.optional.files = [ output ];
        general = {
          autostart = [ "${audioInit}" ];
          mod_key = "Super";
          show_cheatsheet = false;
          xwayland = true;
        };
        environment = {
          NIRI_SOCKET = "";
          XKB_CONFIG_ROOT = osConfig.services.xserver.xkb.dir;
        };
        appearance = {
          border_width = 4;
          corner_radius = 16;
          prefer_no_csd = true;
          blur.enabled = false;
          shadow.enabled = false;
        };
        colors.overview = {
          background_tint = "#00000000";
          workspace_background = "#00000000";
        };
        input = {
          keyboard = {
            inherit (osConfig.services.xserver.xkb)
              layout
              model
              options
              variant
              ;
          };
          cursor = {
            theme = "default";
            size = 24;
            follows_focus = true;
            hide_when_typing = true;
          };
          mouse.natural_scroll = true;
          touchpad = {
            tap = true;
            natural_scroll = true;
            disable_while_typing = true;
            click_method = "clickfinger";
          };
        };
        keybinds = import ./binds.nix { inherit config lib pkgs; };
        layout = {
          mode = "scrolling";
          gap = 12;
          extent_presets = [
            0.75
            0.5
            0.25
          ];
          scrolling.default_extent_fraction = 0.5;
          struts = {
            left = 0;
            right = 0;
            top = 0;
            bottom = 0;
          };
        };
        overview = {
          zoom = 0.5;
          background_blur = false;
          workspace_wallpaper = false;
        };
        output = {
          "eDP-1" = {
            scale = 1.4;
            min_workspaces = 9;
            vrr = "always";
            workspace_axis = "vertical";
          };
          "DP-3" = {
            scale = 1.25;
            min_workspaces = 9;
            vrr = "always";
            mode = "3840x2160@120";
            workspace_axis = "vertical";
          };
        };
        workspaces.back_and_forth = true;
        window_rule = [
          {
            match.app_id = "^(signal|elecwhat)$";
            default_floating = true;
            default_floating_size_px = {
              width = 1000;
              height = 600;
            };
          }
          {
            match.app_id = "^(1password|com[.]ezratweaver[.]AdwBluetooth)$";
            default_floating = true;
          }
          {
            match.app_id = "^zen-beta$";
            default_scrolling_extent = 0.75;
          }
          {
            match = {
              app_id = "^zen-beta$";
              title = "Picture-in-Picture";
            };
            default_floating = true;
          }
          {
            match.app_id = "^org[.]gnome[.]NautilusPreviewer$";
            default_floating = true;
          }
          {
            match.app_id = "^dev[.]noctalia[.]Noctalia$";
            default_floating = true;
            default_floating_size_px = {
              width = 1080;
              height = 920;
            };
          }
          {
            match.app_id = "^dev[.]noctalia[.]UmbrielSharePicker$";
            default_floating = true;
          }
        ];
      };
    };

    # Reuse the maintained native template, not its config-rewriting apply hook.
    programs.noctalia.settings = {
      shell.umbriel_overview_type_to_launch_enabled = false;
      theme.templates.user.umbriel = {
        input_path = "${inputs.noctalia}/assets/templates/umbriel/umbriel.toml";
        output_path = output;
      };
    };
    home.activation.prepareUmbrielNoctaliaTheme =
      lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ]
        ''
          $DRY_RUN_CMD ${pkgs.python3}/bin/python3 ${../noctalia/prepare_theme_output.py} \
            ${lib.escapeShellArg output} \
            ${lib.escapeShellArg "${config.xdg.stateHome}/noctalia/umbriel.pre-template.toml"} \
            --placeholder '# Awaiting Noctalia native colors.'
        '';

    xdg.portal.config.umbriel = {
      default = [ "gtk" ];
      "org.freedesktop.impl.portal.InputCapture" = [ "umbriel" ];
      "org.freedesktop.impl.portal.ScreenCast" = [ "umbriel" ];
      "org.freedesktop.impl.portal.Screenshot" = [ "umbriel" ];
      "org.freedesktop.impl.portal.Settings" = [ "gtk" ];
    };
  };
}
