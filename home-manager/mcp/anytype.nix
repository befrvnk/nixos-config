{ pkgs, ... }:

{
  # Reusable Anytype MCP server wrapper
  # Can be used with OpenCode, Claude Code, or other MCP clients

  anytype-mcp-wrapper = pkgs.writeShellScript "anytype-mcp-wrapper" ''
    # Add nodejs to PATH so npx can find node
    export PATH="${pkgs.nodejs}/bin:$PATH"
    exec ${pkgs.nodejs}/bin/npx -y @anyproto/anytype-mcp
  '';

  # Helper function to create a wrapper that loads Anytype API key
  # Usage: wrapWithAnytypeKey { package = pkgs.opencode; name = "opencode"; }
  wrapWithAnytypeKey =
    { package, name }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [ package ];
      text = ''
        ANYTYPE_KEY_FILE="$HOME/.config/${name}/anytype-api-key"

        # Create API key file from 1Password if it doesn't exist
        if [ ! -f "$ANYTYPE_KEY_FILE" ]; then
          if command -v op >/dev/null 2>&1; then
            echo "First run: Fetching Anytype API key from 1Password..." >&2
            mkdir -p "$HOME/.config/${name}"
            if op read "op://NixOS/Anytype API Key/credential" > "$ANYTYPE_KEY_FILE" 2>/dev/null; then
              chmod 600 "$ANYTYPE_KEY_FILE"
              echo "API key saved to $ANYTYPE_KEY_FILE" >&2
            else
              echo "Warning: Could not fetch API key from 1Password" >&2
            fi
          fi
        fi

        # Load API key from file and set environment
        if [ -f "$ANYTYPE_KEY_FILE" ]; then
          ANYTYPE_API_KEY=$(cat "$ANYTYPE_KEY_FILE")
          export OPENAPI_MCP_HEADERS="{\"Authorization\":\"Bearer $ANYTYPE_API_KEY\", \"Anytype-Version\":\"2025-05-20\"}"
        fi

        exec ${package}/bin/${name} "$@"
      '';
    };

  # MCP server configuration for use in config files
  anytype-mcp-config = anytypeMcpWrapper: {
    type = "local";
    command = [ "${anytypeMcpWrapper}" ];
    timeout = 60000;
  };
}
