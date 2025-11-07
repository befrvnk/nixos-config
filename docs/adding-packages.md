# Adding Packages

This guide explains how to add packages to your NixOS configuration.

## System vs User Packages

- **System packages** are available to all users and installed in `/run/current-system`
- **User packages** are specific to your home-manager user and installed in `~/.nix-profile`

Choose system packages for:
- System services and daemons
- Security tools (sbctl, tpm2-tss)
- Core utilities needed by root or multiple users

Choose user packages for:
- Applications you use (browsers, editors, terminals)
- Development tools
- Personal utilities

## Adding System Packages

Edit `modules/system/packages.nix`:

```nix
environment.systemPackages = with pkgs; [
  # Essential CLI tools
  git
  vim
  wget
  your-new-package  # Add here

  # System security & boot
  tpm2-tss
  sbctl

  # Desktop environment packages
  gnome-control-center
  gnome-bluetooth
  networkmanager
];
```

Then rebuild:
```bash
sudo nixos-rebuild switch --flake .#framework
```

## Adding User Packages

Edit `home-manager/packages.nix`:

```nix
home.packages = (
  with pkgs;
  [
    # Your applications
    _1password-cli
    _1password-gui
    discord
    your-new-package  # Add here

    # CLI tools
    bat
    eza
    fd
  ]
);
```

Then rebuild:
```bash
home-manager switch --flake .#frank@framework
```

Or rebuild the full system (which includes home-manager):
```bash
sudo nixos-rebuild switch --flake .#framework
```

## Searching for Packages

### Online Search
Visit [search.nixos.org](https://search.nixos.org/packages) to search the package database.

### Command Line
```bash
# Search for a package
nix search nixpkgs firefox

# Show package info
nix eval nixpkgs#firefox.meta.description
```

## Package Naming Conventions

- Packages starting with numbers use underscore: `_1password-cli`
- Some packages are in attribute sets: `pkgs.jetbrains.idea-community-bin`
- Font packages: `pkgs.nerd-fonts.fira-code`

## Testing Packages Temporarily

Try a package without adding it to your configuration:

```bash
# Run once
nix run nixpkgs#firefox

# Start a shell with the package
nix shell nixpkgs#firefox nixpkgs#chromium
```

## Unfree Packages

Unfree packages (like Discord, Spotify, 1Password) are already enabled via:
```nix
nixpkgs.config.allowUnfree = true;
```

This is set in `modules/system/packages.nix`.

## Application-Specific Configuration

For applications that need configuration beyond just installation:

1. Create a new file in `home-manager/` (e.g., `home-manager/firefox.nix`)
2. Add the configuration:
   ```nix
   { pkgs, ... }:

   {
     programs.firefox = {
       enable = true;
       # ... more config
     };
   }
   ```
3. Import it in `home-manager/frank.nix`:
   ```nix
   imports = [
     # ... other imports
     ./firefox.nix
   ];
   ```

## Example: Adding a New Application

Let's add Neovim with configuration:

1. Create `home-manager/neovim.nix`:
   ```nix
   { pkgs, ... }:

   {
     programs.neovim = {
       enable = true;
       viAlias = true;
       vimAlias = true;
       plugins = with pkgs.vimPlugins; [
         telescope-nvim
         nvim-treesitter
       ];
     };
   }
   ```

2. Add to `home-manager/frank.nix`:
   ```nix
   imports = [
     # ... existing imports
     ./neovim.nix
   ];
   ```

3. Rebuild and test
