{ pkgs, ... }:
let
  showChangelogs = import ./scripts/show-changelogs.nix { inherit pkgs; };
in
{
  # Note: Agents are defined in .claude/agents/*.md files
  # Claude Code loads these automatically without needing devenv configuration
  # Enable Claude Code integration
  claude.code.enable = true;

  # Packages available in the development environment
  packages = with pkgs; [
    git
    nixfmt-rfc-style
    statix # Nix linter
    deadnix # Find dead Nix code
    nh # NixOS helper
    nvd # Nix version diff (for changelog lookup)
  ];

  # Git hooks configuration - runs automatically after Claude edits files
  git-hooks.hooks = {
    nixfmt = {
      enable = true;
      package = pkgs.nixfmt-rfc-style;
    };
    # Optional: enable these for additional code quality checks
    # statix.enable = true;    # Nix linter
    # deadnix.enable = true;   # Find dead code
  };

  # Custom slash commands for NixOS workflows
  claude.code.commands = {
    rebuild = ''
      Rebuild NixOS configuration and switch to it using nh

      ```bash
      nh os switch --accept-flake-config .
      ```
    '';

    boot = ''
      Rebuild NixOS configuration and activate on next boot

      ```bash
      nh os boot --accept-flake-config .
      ```
    '';

    test = ''
      Test NixOS configuration without persisting

      ```bash
      nh os test --accept-flake-config .
      ```
    '';

    update = ''
      Update all flake inputs

      ```bash
      nix flake update --accept-flake-config
      ```
    '';

    check = ''
      Check flake for errors

      ```bash
      nix flake check --accept-flake-config
      ```
    '';

    format = ''
      Format all Nix files with nixfmt

      ```bash
      nixfmt **/*.nix
      ```
    '';

    lint = ''
      Run statix linter on Nix files

      ```bash
      statix check .
      ```
    '';

    clean = ''
      Clean up old NixOS generations (keeps last 5 by default)

      ```bash
      nh clean all --keep 5
      ```
    '';
  };

  # Custom workflow hooks for automation
  claude.code.hooks = {
    # Protect sensitive files from being edited
    protect-secrets = {
      enable = true;
      name = "Protect sensitive files";
      hookType = "PreToolUse";
      matcher = "^(Edit|MultiEdit|Write)$";
      command = ''
        json=$(cat)
        file_path=$(echo "$json" | ${pkgs.jq}/bin/jq -r '.file_path // empty')

        # Block editing of sensitive files
        if [[ "$file_path" =~ \.(env|secret|key|pem)$ ]]; then
          echo "❌ Error: Cannot edit sensitive files (.env, .secret, .key, .pem)"
          exit 1
        fi

        # Allow the operation
        echo "$json"
      '';
    };

    # Inform user after editing Nix files
    nix-file-edited = {
      enable = true;
      name = "Nix file change notification";
      hookType = "PostToolUse";
      matcher = "^(Edit|MultiEdit|Write)$";
      command = ''
        json=$(cat)
        file_path=$(echo "$json" | ${pkgs.jq}/bin/jq -r '.file_path // empty')

        if [[ "$file_path" =~ \.nix$ ]]; then
          echo "ℹ️  Nix file edited. Run /rebuild to apply changes or /check to validate."
        fi
      '';
    };
  };

  # MCP Servers - Model Context Protocol for extended capabilities
  claude.code.mcpServers = {
    # Context7: Documentation and code examples for libraries
    context7 = {
      type = "http";
      url = "https://mcp.context7.com/mcp";
    };

    # Devenv MCP: Provides devenv-specific context and capabilities
    devenv = {
      type = "stdio";
      command = "${pkgs.devenv}/bin/devenv";
      args = [ "mcp" ];
    };
  };

  # Environment variables
  env = {
    # Ensure nixfmt uses RFC style
    NIXFMT_STYLE = "rfc";
  };

  # Shell initialization
  enterShell = ''
    echo "🚀 NixOS Config Development Environment"
    echo ""
    echo "Available commands:"
    echo "  rebuild [switch] - Rebuild NixOS (default: boot)"
    echo "  clean [N]        - Clean old generations (default: keep 5)"
    echo "  sysinfo          - Show system information"
    echo "  generations      - List NixOS generations"
    echo "  wifi-debug       - Capture WiFi debug logs (run if WiFi fails)"
    echo "  update           - Update flake inputs"
    echo ""
    echo "Slash commands (Claude Code):"
    echo "  /rebuild  - Rebuild and switch configuration"
    echo "  /boot     - Rebuild and activate on next boot"
    echo "  /test     - Test configuration without persisting"
    echo "  /update   - Update flake inputs"
    echo "  /check    - Check flake for errors"
    echo "  /format   - Format Nix files"
    echo "  /lint     - Lint Nix files with statix"
    echo "  /clean    - Clean old generations (keep 5)"
    echo ""

    # Show git status if in a git repository
    if ${pkgs.git}/bin/git rev-parse --git-dir > /dev/null 2>&1; then
      echo "Git status:"
      ${pkgs.git}/bin/git status --short --branch
      echo ""
    fi

    # Check for uncommitted changes
    if ! ${pkgs.git}/bin/git diff-index --quiet HEAD -- 2>/dev/null; then
      echo "⚠️  You have uncommitted changes"
    fi
  '';

  # Scripts - Additional helper scripts available in PATH
  scripts = {
    # Rebuild NixOS configuration using nh (Nix Helper)
    # Usage: rebuild [switch] [nh-options]
    # Default action is 'boot', use 'rebuild switch' to activate immediately
    rebuild.exec = ''
      action="boot"

      # If first arg is 'switch', change action
      if [ "$1" = "switch" ]; then
        action="switch"
        shift
      fi

      echo "+ ${pkgs.nh}/bin/nh os $action --accept-flake-config $HOME/nixos-config $@"
      ${pkgs.nh}/bin/nh os "$action" --accept-flake-config "$HOME/nixos-config" "$@"
      exit_code=$?

      # Show changelog links after successful switch
      if [ $exit_code -eq 0 ] && [ "$action" = "switch" ]; then
        ${showChangelogs}
      fi

      exit $exit_code
    '';

    # Quick system info
    sysinfo.exec = ''
      echo "System: $(${pkgs.coreutils}/bin/uname -a)"
      echo "NixOS version: $(${pkgs.coreutils}/bin/cat /etc/os-release | ${pkgs.gnugrep}/bin/grep VERSION= | ${pkgs.coreutils}/bin/cut -d'"' -f2)"
      echo "Generation: $(sudo ${pkgs.nix}/bin/nix-env --list-generations --profile /nix/var/nix/profiles/system | ${pkgs.coreutils}/bin/tail -1)"
    '';

    # List all available NixOS generations
    generations.exec = ''
      sudo ${pkgs.nix}/bin/nix-env --list-generations --profile /nix/var/nix/profiles/system
    '';

    # Clean up old generations using nh
    # Usage: clean [keep-count]
    # Default keeps 5 generations
    clean.exec = ''
      keep="''${1:-5}"
      echo "+ ${pkgs.nh}/bin/nh clean all --keep $keep"
      ${pkgs.nh}/bin/nh clean all --keep "$keep"
    '';

    # Capture WiFi debug logs when WiFi fails to initialize
    # Run this BEFORE rebooting if WiFi is not working
    wifi-debug.exec = ''
      output_dir="$HOME/wifi-debug-$(${pkgs.coreutils}/bin/date +%Y%m%d-%H%M%S)"
      ${pkgs.coreutils}/bin/mkdir -p "$output_dir"

      echo "📡 Capturing WiFi debug information to $output_dir"
      echo ""

      echo "→ Capturing kernel messages (dmesg)..."
      ${pkgs.util-linux}/bin/dmesg > "$output_dir/dmesg.log" 2>&1

      echo "→ Capturing boot kernel logs (iwlwifi/wifi related)..."
      ${pkgs.systemd}/bin/journalctl -b 0 -k | ${pkgs.gnugrep}/bin/grep -i -E "(iwl|wifi|wlan|firmware|network)" > "$output_dir/kernel-wifi.log" 2>&1

      echo "→ Capturing NetworkManager logs..."
      ${pkgs.systemd}/bin/journalctl -b 0 -u NetworkManager > "$output_dir/networkmanager.log" 2>&1

      echo "→ Capturing full boot log..."
      ${pkgs.systemd}/bin/journalctl -b 0 > "$output_dir/full-boot.log" 2>&1

      echo "→ Capturing network interface state..."
      ${pkgs.iproute2}/bin/ip a > "$output_dir/ip-addr.log" 2>&1
      ${pkgs.iproute2}/bin/ip link > "$output_dir/ip-link.log" 2>&1

      echo "→ Capturing loaded modules..."
      ${pkgs.kmod}/bin/lsmod | ${pkgs.gnugrep}/bin/grep -i -E "(iwl|wifi|cfg80211|mac80211)" > "$output_dir/modules.log" 2>&1

      echo "→ Capturing PCI devices..."
      ${pkgs.pciutils}/bin/lspci | ${pkgs.gnugrep}/bin/grep -i network > "$output_dir/pci-network.log" 2>&1

      echo ""
      echo "✅ Debug logs captured to: $output_dir"
      echo ""
      echo "Files captured:"
      ${pkgs.coreutils}/bin/ls -la "$output_dir"
      echo ""
      echo "💡 Share these files when reporting WiFi issues."
    '';

    update.exec = ''
      echo "Updating flake inputs..."
      nix flake update --accept-flake-config
    '';
  };

  # Language support (optional - uncomment if needed for scripts)
  # languages.nix.enable = true;
}
