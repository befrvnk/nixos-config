{ pkgs }:

let
  # Import shared theme configuration (used by both Stylix and Zen Browser)
  themes = import ../themes.nix { inherit pkgs; };

  # Convert YAML color schemes to JSON and import
  # We use yq-go to convert YAML to JSON, then parse with builtins.fromJSON
  yamlToScheme =
    yamlPath:
    builtins.fromJSON (
      builtins.readFile (
        pkgs.runCommand "scheme.json" { } ''
          ${pkgs.yq-go}/bin/yq -o json ${yamlPath} > $out
        ''
      )
    );

  # Load base16 color schemes from shared themes config
  darkScheme = yamlToScheme themes.dark.base16Scheme;
  lightScheme = yamlToScheme themes.light.base16Scheme;

  # Helper function to generate Zen Browser theme CSS from base16 colors
  # Uses the scheme's color palette to set all Zen-specific CSS variables
  generateZenTheme =
    scheme: with scheme.palette; ''
      :root {
        --zen-colors-primary: ${base02} !important;
        --zen-primary-color: ${base0D} !important;
        --zen-colors-secondary: ${base02} !important;
        --zen-colors-tertiary: ${base01} !important;
        --zen-colors-border: ${base0D} !important;
        --toolbarbutton-icon-fill: ${base0D} !important;
        --lwt-text-color: ${base05} !important;
        --toolbar-field-color: ${base05} !important;
        --tab-selected-textcolor: ${base05} !important;
        --toolbar-field-focus-color: ${base05} !important;
        --toolbar-color: ${base05} !important;
        --newtab-text-primary-color: ${base05} !important;
        --arrowpanel-color: ${base05} !important;
        --arrowpanel-background: ${base00} !important;
        --sidebar-text-color: ${base05} !important;
        --lwt-sidebar-text-color: ${base05} !important;
        --lwt-sidebar-background-color: ${base00} !important;
        --toolbar-bgcolor: ${base02} !important;
        --newtab-background-color: ${base00} !important;
        --zen-themed-toolbar-bg: ${base00} !important;
        --zen-main-browser-background: ${base00} !important;
        --toolbox-bgcolor-inactive: ${base01} !important;
      }

      #permissions-granted-icon {
        color: ${base05} !important;
      }

      .sidebar-placesTree {
        background-color: ${base00} !important;
      }

      #zen-workspaces-button {
        background-color: ${base00} !important;
      }

      #TabsToolbar {
        background-color: ${base00} !important;
      }

      .urlbar-background {
        background-color: ${base02} !important;
      }

      .content-shortcuts {
        background-color: ${base00} !important;
        border-color: ${base0D} !important;
      }

      .urlbarView-url {
        color: ${base0D} !important;
      }

      #urlbar-input::selection {
        background-color: ${base0D} !important;
        color: ${base00} !important;
      }

      #zenEditBookmarkPanelFaviconContainer {
        background: ${base00} !important;
      }

      #zen-media-controls-toolbar {
        & #zen-media-progress-bar {
          &::-moz-range-track {
            background: ${base02} !important;
          }
        }
      }

      toolbar .toolbarbutton-1 {
        &:not([disabled]) {
          &:is([open], [checked])
            > :is(
              .toolbarbutton-icon,
              .toolbarbutton-text,
              .toolbarbutton-badge-stack
            ) {
            fill: ${base0D};
          }
        }
      }

      .identity-color-blue {
        --identity-tab-color: ${base0D} !important;
        --identity-icon-color: ${base0D} !important;
      }

      .identity-color-turquoise {
        --identity-tab-color: ${base0C} !important;
        --identity-icon-color: ${base0C} !important;
      }

      .identity-color-green {
        --identity-tab-color: ${base0B} !important;
        --identity-icon-color: ${base0B} !important;
      }

      .identity-color-yellow {
        --identity-tab-color: ${base0A} !important;
        --identity-icon-color: ${base0A} !important;
      }

      .identity-color-orange {
        --identity-tab-color: ${base09} !important;
        --identity-icon-color: ${base09} !important;
      }

      .identity-color-red {
        --identity-tab-color: ${base08} !important;
        --identity-icon-color: ${base08} !important;
      }

      .identity-color-pink {
        --identity-tab-color: ${base0E} !important;
        --identity-icon-color: ${base0E} !important;
      }

      .identity-color-purple {
        --identity-tab-color: ${base0F} !important;
        --identity-icon-color: ${base0F} !important;
      }

      hbox#titlebar {
        background-color: ${base00} !important;
      }

      #zen-appcontent-navbar-container {
        background-color: ${base00} !important;
      }

      /* Menu text colors only (Zen Browser handles backgrounds) */
      #contentAreaContextMenu menu,
      menuitem,
      menupopup {
        color: ${base05} !important;
      }
    '';

  # Glance uses inverted light-dark() function, override with correct colors
  generateGlanceTheme =
    scheme: with scheme.palette; ''
      /* Glance sidebar - override inverted light-dark() with correct theme colors */
      .zen-glance-sidebar-container toolbarbutton {
        background: ${base02} !important;
      }

      .zen-glance-sidebar-container toolbarbutton:hover {
        background: ${base03} !important;
      }

      .zen-glance-sidebar-close,
      .zen-glance-sidebar-open,
      .zen-glance-sidebar-split {
        -moz-context-properties: fill, fill-opacity !important;
        fill: ${base05} !important;
        color: ${base05} !important;
      }

      .zen-glance-sidebar-close .toolbarbutton-icon,
      .zen-glance-sidebar-open .toolbarbutton-icon,
      .zen-glance-sidebar-split .toolbarbutton-icon {
        -moz-context-properties: fill, fill-opacity !important;
        fill: ${base05} !important;
      }
    '';
in
# Generate combined userChrome.css with both themes using media queries
pkgs.writeText "userChrome.css" ''
  /* Generated userChrome.css for Zen Browser with light and dark themes */
  /* Colors automatically sourced from Stylix base16 color schemes */

  /* ========================================== */
  /* DARK THEME - ${darkScheme.name} */
  /* ========================================== */
  @media (prefers-color-scheme: dark) {
    ${generateZenTheme darkScheme}
    /* Glance - override inverted light-dark() with correct dark colors */
    ${generateGlanceTheme darkScheme}
  }

  /* ========================================== */
  /* LIGHT THEME - ${lightScheme.name} */
  /* ========================================== */
  @media (prefers-color-scheme: light) {
    ${generateZenTheme lightScheme}
    /* Glance - override inverted light-dark() with correct light colors */
    ${generateGlanceTheme lightScheme}
  }
''
