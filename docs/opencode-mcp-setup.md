# OpenCode MCP Server Integration

This document explains the MCP (Model Context Protocol) server setup for OpenCode, including Context7 and Anytype integration.

## Overview

We've configured OpenCode with two MCP servers:
1. **Context7** - Remote MCP server for up-to-date library documentation
2. **Anytype** - Local MCP server for personal knowledge base integration

## File Structure

```
home-manager/
├── mcp/
│   └── anytype.nix              # Reusable Anytype MCP module
├── opencode/
│   ├── default.nix              # Main OpenCode configuration
│   └── commands/
│       └── commit.md
└── claude-code.nix              # Can reuse mcp/anytype.nix

# Per-project agents (version-controlled)
.opencode/
└── agent/                       # Project-specific agents (singular!)
    ├── coder.md
    ├── quick.md
    ├── planner.md
    ├── tester.md
    ├── docs.md
    ├── debugger.md
    ├── committer.md
    └── investigator.md
```

## Agent Configuration

opencode now uses per-project agents instead of global definitions.

### Per-Project Agents

**Location:** `.opencode/agent/` (version-controlled with project, note: singular "agent"!)

Project-specific agents are stored in the project repository and provide context-aware assistance tailored to the project's needs.

**Format (opencode):**
```markdown
---
description: Agent description
model: anthropic/claude-sonnet-4 | anthropic/claude-haiku-3.5 | google/gemini-2.5-pro
temperature: 0.3
maxTokens: 8000
---

# Agent instructions...
```

**Available Agents (nixos-config project):**
- `coder.md` - Main implementation agent (converted from Claude Code's `code.md`)
- `quick.md` - Quick tasks helper (converted from `code-quick.md`)
- `planner.md` - Planning and research (converted from `plan.md`)
- `tester.md` - Testing specialist (converted from `test.md`)
- `docs.md` - Documentation (converted from `docs.md`)
- `debugger.md` - Bug investigation and fixes (converted from `debug.md`)
- `committer.md` - Git commit helper (converted from `commit.md`)
- `investigator.md` - System diagnostics (converted from `investigate.md`)

### Default Agents (Fallback)

When a project doesn't have its own agents in `.opencode/agent/`, opencode falls back to its [built-in agents](https://opencode.ai/docs/agents/) which provide general-purpose coding assistance.

### Format Differences

**opencode vs Claude Code:**
- opencode uses `description:` field in frontmatter
- Claude Code uses `name:` field
- opencode doesn't use `tools:` section (removed during conversion)
- Models are fully qualified (e.g., `anthropic/claude-sonnet-4` not just `sonnet`)

This separation allows each tool to have optimized agent configurations while maintaining similar workflows.

## Context7 Setup

Context7 is a remote MCP server that fetches up-to-date documentation. No API key required.

### Configuration

In `home-manager/opencode/default.nix`:

```nix
settings = {
  mcp = {
    context7 = {
      type = "remote";
      url = "https://mcp.context7.com/mcp";
    };
  };
};
```

### Usage

Just mention Context7 in your prompts:
```
"Use context7 to show me the latest React hooks documentation"
```

## Anytype Setup

Anytype is a local MCP server that connects to your Anytype desktop app for knowledge base management.

### Requirements

1. Anytype desktop app installed and running
2. API key generated in Anytype (Settings → API Keys)
3. API key stored in 1Password at `op://NixOS/Anytype API Key/credential`

### Architecture

The Anytype integration consists of:

1. **Reusable Module** (`home-manager/mcp/anytype.nix`):
   - `anytype-mcp-wrapper`: Script that runs the MCP server with proper PATH
   - `wrapWithAnytypeKey`: Function to wrap any tool with Anytype key loading
   - `anytype-mcp-config`: Pre-configured MCP settings

2. **OpenCode Wrapper** (generated from configuration):
   - On first run: Fetches API key from 1Password
   - Saves key to `~/.config/opencode/anytype-api-key` (chmod 600)
   - Subsequent runs: Loads key from file (fast, no 1Password prompt)
   - Sets `OPENAPI_MCP_HEADERS` environment variable
   - Launches OpenCode with proper environment

### Configuration

In `home-manager/opencode/default.nix`:

```nix
let
  anytype = import ../mcp/anytype.nix { inherit pkgs; };
  opencode-wrapped = anytype.wrapWithAnytypeKey {
    package = pkgs.opencode;
    name = "opencode";
  };
in
{
  programs.opencode = {
    enable = true;
    package = opencode-wrapped;

    settings = {
      mcp = {
        anytype = anytype.anytype-mcp-config anytype.anytype-mcp-wrapper;
      };
    };
  };
}
```

### First Run

On first launch, you'll see:
```
First run: Fetching Anytype API key from 1Password...
[1Password authentication prompt]
API key saved to /home/frank/.config/opencode/anytype-api-key
```

All subsequent runs use the cached key.

### Usage

Interact with Anytype through natural language:
```
"Create a new space in Anytype called 'Project Ideas'"
"Search Anytype for notes about NixOS"
```

## Key Problems Solved

### Problem 1: Agent Model Names Required Provider Prefix

**Error:** `Agent coder's configured model gemini-2.5-pro is not valid`

**Solution:** Agent models need provider prefix:
- ❌ `model: gemini-2.5-pro`
- ✅ `model: google/gemini-2.5-pro`

### Problem 2: Config Schema Mismatch

**Error:** `Unrecognized keys: "defaultModel", "providers", "ui"`

**Solution:** Use correct OpenCode config schema:
- ❌ `defaultModel`, `providers`, `ui`
- ✅ `model`, `provider`, `theme` (at top level)

### Problem 3: Home-Manager Module vs Manual Config

**Issue:** Manually creating config file with `xdg.configFile` prevented MCP servers from loading.

**Solution:** Use `programs.opencode.settings` option:
```nix
programs.opencode = {
  enable = true;
  settings = { ... };  # Use this
  agents = { ... };    # Use this
  commands = { ... };  # Use this
};

# Don't use:
# xdg.configFile."opencode/.opencode.json".text = ...
```

### Problem 4: 1Password CLI Integration in Wrapper

**Error:** `connecting to desktop app: read: connection reset`

**Root Cause:** `writeShellApplication` creates isolated environment where `op` can't connect to 1Password desktop app.

**Solution:** Use system-wrapped `op` command from PATH instead of package reference:
```nix
# ❌ Don't include pkgs._1password-cli in runtimeInputs
# ✅ Use system `op` from PATH (has proper setgid wrapper)
if command -v op >/dev/null 2>&1; then
  op read "op://..."
fi
```

Requires NixOS modules:
```nix
programs._1password.enable = true;
programs._1password-gui = {
  enable = true;
  polkitPolicyOwners = [ "frank" ];
};
```

### Problem 5: NPX Can't Find Node

**Error:** `env: 'node': No such file or directory`

**Root Cause:** When OpenCode spawns MCP server subprocess, it uses minimal PATH without node.

**Solution:** Add nodejs to PATH in wrapper script:
```nix
anytype-mcp-wrapper = pkgs.writeShellScript "anytype-mcp-wrapper" ''
  export PATH="${pkgs.nodejs}/bin:$PATH"
  exec ${pkgs.nodejs}/bin/npx -y @anyproto/anytype-mcp
'';
```

## Adding More MCP Servers

### Remote MCP Server (like Context7)

```nix
settings = {
  mcp = {
    my-server = {
      type = "remote";
      url = "https://example.com/mcp";
      # Optional:
      headers = {
        Authorization = "Bearer {env:MY_API_KEY}";
      };
    };
  };
};
```

### Local MCP Server with NPX

```nix
let
  my-mcp-wrapper = pkgs.writeShellScript "my-mcp-wrapper" ''
    export PATH="${pkgs.nodejs}/bin:$PATH"
    exec ${pkgs.nodejs}/bin/npx -y @org/my-mcp-server
  '';
in
{
  settings = {
    mcp = {
      my-server = {
        type = "local";
        command = [ "${my-mcp-wrapper}" ];
        timeout = 60000;  # 60 seconds
      };
    };
  };
}
```

### Reusing Anytype Module for Other Tools

For Claude Code:

```nix
{ config, pkgs, ... }:

let
  anytype = import ./mcp/anytype.nix { inherit pkgs; };
in
{
  programs.claude-code = {
    enable = true;
    mcpServers = {
      anytype = anytype.anytype-mcp-config anytype.anytype-mcp-wrapper;
    };
  };

  # Optional: Wrap to auto-fetch API key
  home.packages = [
    (anytype.wrapWithAnytypeKey {
      package = pkgs.claude-code;
      name = "claude-code";
    })
  ];
}
```

## Troubleshooting

### Check MCP Status

```bash
opencode
# Then in OpenCode:
/status
```

### Check OpenCode Logs

```bash
ls -lt ~/.local/share/opencode/log/
tail -100 ~/.local/share/opencode/log/$(ls -t ~/.local/share/opencode/log/ | head -1) | grep -i mcp
```

### Verify API Key

```bash
cat ~/.config/opencode/anytype-api-key
# Should show your API key (44 characters)
```

### Test MCP Server Manually

```bash
export ANYTYPE_API_KEY=$(cat ~/.config/opencode/anytype-api-key)
export OPENAPI_MCP_HEADERS='{"Authorization":"Bearer '"$ANYTYPE_API_KEY"'", "Anytype-Version":"2025-05-20"}'
npx -y @anyproto/anytype-mcp
# Should show: "Anytype MCP Server running on stdio"
```

### Reset API Key

To fetch a new key from 1Password:

```bash
rm ~/.config/opencode/anytype-api-key
opencode  # Will prompt for 1Password again
```

## Security Considerations

### Anytype API Key Storage

- **Stored in:** `~/.config/opencode/anytype-api-key`
- **Permissions:** 600 (owner read/write only)
- **Scope:** Local-only API (connects to localhost Anytype app)
- **Risk Level:** Low (key only works on your machine)
- **Alternative:** For public nixos-config repos, consider using sops-nix or agenix

### 1Password Integration

- Uses system-wrapped `op` command (setgid wrapper)
- Requires `programs._1password.enable = true` in NixOS config
- API key fetched once and cached to file
- No repeated 1Password prompts

## References

- [OpenCode Documentation](https://opencode.ai/docs/)
- [OpenCode MCP Servers](https://opencode.ai/docs/mcp-servers/)
- [Context7 MCP Server](https://github.com/upstash/context7)
- [Anytype MCP Server](https://github.com/anyproto/anytype-mcp)
- [Anytype API Documentation](https://developers.anytype.io/)
- [Model Context Protocol](https://modelcontextprotocol.io/)
- [1Password CLI on NixOS](https://wiki.nixos.org/wiki/1Password)

## Future Improvements

- [ ] Add more MCP servers (filesystem, git, etc.)
- [ ] Consider using sops-nix for API key encryption in public repos
- [ ] Create a unified MCP management module
- [ ] Add MCP server health checks
- [ ] Document Context7 usage patterns
