{
  config,
  ...
}:

let
  # Vault configuration
  vaultName = "Werkstatt";
  vaultPath = "${config.home.homeDirectory}/Documents/Obsidian/${vaultName}";
  # Generate a stable vault ID from the path (Obsidian accepts any string)
  vaultId = builtins.hashString "md5" vaultPath;
in
{
  # Pre-configure Obsidian vault location
  # This registers the vault so Obsidian opens it on first launch
  xdg.configFile."obsidian/obsidian.json".text = builtins.toJSON {
    vaults = {
      ${vaultId} = {
        path = vaultPath;
        ts = 1733667600000; # Fixed timestamp for reproducibility
        open = true;
      };
    };
  };

  # Create the vault directory structure
  home.file."Documents/Obsidian/${vaultName}/.keep".text = "";
}
