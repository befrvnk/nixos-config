# OpenCode AI Setup

This guide explains how OpenCode AI is configured in your NixOS system and how to set up and use it with Claude and Gemini.

## What is OpenCode AI?

OpenCode is a powerful AI coding agent built for the terminal, actively maintained by [SST](https://sst.dev/). It's model-agnostic and supports multiple AI providers including:
- Anthropic Claude (Sonnet 4.5, 3.7 Sonnet, 3.5 Haiku)
- Google Gemini (2.0 Flash, 1.5 Pro)
- OpenAI, AWS Bedrock, Groq, Azure OpenAI, and more

The project has 32.3k+ stars on GitHub and is actively developed with frequent releases.

## Configuration Overview

OpenCode is configured across multiple files:
- `/overlays/opencode.nix` - Custom Nix package built from upstream releases
- `/home-manager/opencode.nix` - Home-manager module for configuration and environment
- `/flake.nix` - Overlay integration
- `/home-manager/frank.nix` - Module import

## Initial Setup

### 1. Set Up API Keys in 1Password

OpenCode retrieves API keys securely from 1Password CLI. You need to create two items:

**For Claude (Anthropic):**
1. Open 1Password and create a new item in your "Private" vault
2. Name: `Anthropic API Key`
3. Add a field with label `credential` containing your API key
4. Get your API key from: https://console.anthropic.com/

**For Gemini (Google):**
1. Open 1Password and create a new item in your "Private" vault
2. Name: `Gemini API Key`
3. Add a field with label `credential` containing your API key
4. Get your API key from: https://aistudio.google.com/apikey

### 2. Sign in to 1Password CLI

If you haven't already set up 1Password CLI:

```bash
# Sign in to 1Password
op signin

# Verify it works
op read "op://Private/Anthropic API Key/credential"
op read "op://Private/Gemini API Key/credential"
```

### 3. Rebuild Your Configuration

After setting up the API keys:

```bash
# From your nixos-config directory
sudo nixos-rebuild switch --flake .#framework
```

## Usage

### Basic Commands

OpenCode is available through multiple aliases:

```bash
# Launch OpenCode
opencode

# Or use the shorter aliases
ai
code-ai
```

### Selecting Models

OpenCode is configured with these agents by default:

| Agent | Model | Purpose |
|-------|-------|---------|
| coder | claude-sonnet-4-5 | Main coding agent (8000 tokens) |
| architect | claude-sonnet-4-5 | Architecture and design (4000 tokens) |
| reviewer | gemini-2.0-flash | Code review (4000 tokens) |

### External Editor Support

OpenCode is configured to use Zed as the external editor. Press `Ctrl+E` within OpenCode to open your preferred editor for composing messages.

## Configuration File

Your OpenCode configuration is located at:
```
~/.config/opencode/.opencode.json
```

The configuration is managed by home-manager and includes:
- Agent configurations with model preferences
- Default model settings (Claude Sonnet 4.5)
- UI preferences (dark theme, Zed editor)
- Provider configurations for Anthropic and Google

## Changing Default Models

To change the default model or add more configurations, edit `/home-manager/opencode.nix`:

```nix
agents = {
  coder = {
    model = "gemini-2.0-flash";  # Change to Gemini
    maxTokens = 8000;
  };
  # Add more agents as needed
};
```

Then rebuild:
```bash
sudo nixos-rebuild switch --flake .#framework
```

## Available Models

### Claude (Anthropic)
- `claude-sonnet-4-5` - Latest and most capable
- `claude-3-7-sonnet` - Previous generation
- `claude-3-5-haiku` - Faster, more economical

### Gemini (Google)
- `gemini-2.0-flash` - Fast and efficient
- `gemini-1.5-pro` - More capable, slower

## Troubleshooting

### API Keys Not Working

Verify 1Password CLI access:
```bash
# Test Anthropic key
op read "op://Private/Anthropic API Key/credential"

# Test Gemini key
op read "op://Private/Gemini API Key/credential"
```

If these commands fail:
1. Make sure you're signed in: `op signin`
2. Verify the item names match exactly (case-sensitive)
3. Ensure the field is named `credential`

### OpenCode Command Not Found

If `opencode` is not available after rebuild:
1. Check that the overlay is working: `nix-env -qaP | grep opencode`
2. Verify home-manager activated: `systemctl --user status home-manager-frank.service`
3. Try restarting your shell or running: `source ~/.zshrc`

### Model Not Available

If a model fails to load:
1. Verify your API key has access to that model
2. Check your subscription/credits
3. Try a different model from the same provider

### Binary Not Working

If OpenCode fails to run with library errors:
1. The package uses autoPatchelfHook to fix dynamic linking
2. Check the logs for missing libraries
3. Report issues to the package maintainer

## Updating OpenCode

To update to a new version:

1. Check the latest release: https://github.com/sst/opencode/releases
2. OpenCode is actively maintained with frequent updates
3. Update `/overlays/opencode.nix`:
   - Change `version = "1.0.55"` to the new version
   - Get the new SHA256 hash from the release
   - Convert to base64 format (see flake.nix comments for instructions)
4. Rebuild your configuration

## Environment Variables

These environment variables are set by the configuration:

```bash
ANTHROPIC_API_KEY  # Retrieved from 1Password
GEMINI_API_KEY     # Retrieved from 1Password
EDITOR             # Set to "zed"
OPENCODE_CONFIG_DIR # Points to ~/.config/opencode
```

## Additional Resources

- OpenCode GitHub: https://github.com/sst/opencode
- OpenCode Documentation: https://opencode.sh/
- SST (maintainer): https://sst.dev/
- Claude Documentation: https://docs.anthropic.com/
- Gemini Documentation: https://ai.google.dev/
- 1Password CLI: https://developer.1password.com/docs/cli/

## Using the Claude Code Workflow

Your OpenCode is configured to mimic Claude Code's structured workflow when using the default agent. This includes:

- **Automatic complexity detection**: Plans complex tasks, executes simple ones immediately
- **Structured planning**: Research → Plan → Approval → Execute
- **Markdown todo lists**: Track progress with checkboxes
- **Systematic execution**: Work through tasks methodically

### Quick Reference

Different agents for different needs:
- `opencode` (default coder agent): General tasks with Claude Code workflow
- `opencode --agent planner`: Deep architectural planning
- `opencode --agent quick`: Fast execution for simple tasks
- `opencode --agent reviewer`: Code review
