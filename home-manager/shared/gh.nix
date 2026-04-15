{ pkgs, ... }:

let
  # gh-dash config shared across light/dark (everything except theme, keybindings, pager)
  ghDashBaseConfig = ''
    prSections:
        - title: My Pull Requests
          filters: is:open author:@me
        - title: Needs My Review
          filters: is:open review-requested:@me
        - title: Involved
          filters: is:open involves:@me -author:@me
    issuesSections:
        - title: My Issues
          filters: is:open author:@me
        - title: Assigned
          filters: is:open assignee:@me
        - title: Involved
          filters: is:open involves:@me -author:@me
    notificationsSections:
        - title: All
          filters: ""
        - title: Created
          filters: reason:author
        - title: Participating
          filters: reason:participating
        - title: Mentioned
          filters: reason:mention
        - title: Review Requested
          filters: reason:review-requested
        - title: Assigned
          filters: reason:assign
        - title: Subscribed
          filters: reason:subscribed
        - title: Team Mentioned
          filters: reason:team-mention
    repo:
        branchesRefetchIntervalSeconds: 30
        prsRefetchIntervalSeconds: 60
    defaults:
        preview:
            open: true
            width: 0.45
        prsLimit: 20
        prApproveComment: LGTM
        issuesLimit: 20
        notificationsLimit: 20
        view: prs
        layout:
            prs:
                updatedAt:
                    width: 5
                createdAt:
                    width: 5
                repo:
                    width: 20
                author:
                    width: 15
                authorIcon:
                    hidden: false
                assignees:
                    width: 20
                    hidden: true
                base:
                    width: 15
                    hidden: true
                lines:
                    width: 15
            issues:
                updatedAt:
                    width: 5
                createdAt:
                    width: 5
                repo:
                    width: 15
                creator:
                    width: 10
                creatorIcon:
                    hidden: false
                assignees:
                    width: 20
                    hidden: true
        refetchIntervalMinutes: 30
    repoPaths: {}
  '';

  # Diffnav wrapper scripts (gh-dash runs pager commands via $SHELL -c,
  # and nushell doesn't support VAR=value command syntax)
  diffnavDark = pkgs.writeShellScript "diffnav-dark" ''
    export DELTA_FEATURES=dark
    exec ${pkgs.diffnav}/bin/diffnav "$@"
  '';

  diffnavLight = pkgs.writeShellScript "diffnav-light" ''
    export DELTA_FEATURES=light
    exec ${pkgs.diffnav}/bin/diffnav "$@"
  '';

  # Keybindings (shared across light/dark - enhance lacks proper light theme support)
  keybindingsConfig = ''
    keybindings:
        prs:
            - key: T
              command: gh enhance -R {{.RepoName}} {{.PrNumber}}
  '';

  # Catppuccin Mocha (dark) theme colors for gh-dash
  darkTheme = ''
    theme:
        ui:
            sectionsShowCount: true
            table:
                showSeparator: true
                compact: false
        colors:
            text:
                primary: "#cdd6f4"
                secondary: "#a6adc8"
                inverted: "#1e1e2e"
                faint: "#585b70"
                warning: "#f38ba8"
                success: "#a6e3a1"
            background:
                selected: "#313244"
            border:
                primary: "#45475a"
                secondary: "#313244"
                faint: "#181825"
  '';

  # Catppuccin Latte (light) theme colors for gh-dash
  lightTheme = ''
    theme:
        ui:
            sectionsShowCount: true
            table:
                showSeparator: true
                compact: false
        colors:
            text:
                primary: "#4c4f69"
                secondary: "#6c6f85"
                inverted: "#eff1f5"
                faint: "#acb0be"
                warning: "#d20f39"
                success: "#40a02b"
            background:
                selected: "#ccd0da"
            border:
                primary: "#bcc0cc"
                secondary: "#ccd0da"
                faint: "#e6e9ef"
  '';

  darkSuffix = ''
    pager:
        diff: ${diffnavDark}
    confirmQuit: false
    showAuthorIcons: true
    smartFilteringAtLaunch: true
    includeReadNotifications: true
  '';

  lightSuffix = ''
    pager:
        diff: ${diffnavLight}
    confirmQuit: false
    showAuthorIcons: true
    smartFilteringAtLaunch: true
    includeReadNotifications: true
  '';

  # Wrapper script that detects system appearance and launches gh-dash
  ghDashWrapper = pkgs.writeShellScript "gh-dash-wrapper" ''
    export PATH="${pkgs.gh}/bin:$PATH"
    ${builtins.readFile ./gh-dash-wrapper.sh}
  '';
in
{
  programs.gh = {
    enable = true;
    extensions = [
      pkgs.gh-dash
      pkgs.gh-enhance
    ];
    settings = {
      git_protocol = "ssh";
      prompt = "enabled";
      aliases = {
        co = "pr checkout";
      };
    };
  };

  # Generate light and dark gh-dash configs
  xdg.configFile = {
    "gh/config.yml".force = true;
    "gh-dash/config-dark.yml" = {
      text = ghDashBaseConfig + keybindingsConfig + darkTheme + darkSuffix;
      force = true;
    };
    "gh-dash/config-light.yml" = {
      text = ghDashBaseConfig + keybindingsConfig + lightTheme + lightSuffix;
      force = true;
    };
  };

  # diffnav: git diff pager with file tree (used by gh-dash and standalone)
  # github-copilot-cli: terminal agent used by the `ai` / `?` nushell helpers
  home.packages = [
    pkgs.diffnav
    pkgs.github-copilot-cli
  ];

  # Add ghd alias that auto-detects appearance
  home.shellAliases.ghd = toString ghDashWrapper;
}
