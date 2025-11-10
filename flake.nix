{
  description = "NixOS from Scratch";

  inputs = {
    # Using nixpkgs-unstable as the main channel for latest packages
    # All system and user packages use this channel
    nixpkgs.url = "nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    android-nixpkgs = {
      url = "github:tadfisher/android-nixpkgs/stable";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dankMaterialShell = {
      url = "github:AvengeMedia/DankMaterialShell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    vicinae = {
      url = "github:vicinaehq/vicinae";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      nixos-hardware,
      zen-browser,
      android-nixpkgs,
      lanzaboote,
      stylix,
      dankMaterialShell,
      vicinae,
      niri,
      pre-commit-hooks,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      # Common overlays applied to all hosts
      commonOverlays = [
        # To update gemini-cli to a new version:
        # 1. Check latest release: https://github.com/google-gemini/gemini-cli/releases
        # 2. Update 'version' in overlays/gemini-cli.nix
        # 3. Get new hash with:
        #    curl -sL https://github.com/google-gemini/gemini-cli/releases/download/v<VERSION>/gemini.js | sha256sum
        #    python3 -c "import base64; print('sha256-' + base64.b64encode(bytes.fromhex('<HEX_HASH>')).decode())"
        # 4. Update 'hash' in overlays/gemini-cli.nix with the output
        (import ./overlays/gemini-cli.nix)
      ];
    in
    {
      nixosConfigurations.framework = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit nixos-hardware lanzaboote inputs;
          inherit
            stylix
            dankMaterialShell
            vicinae
            zen-browser
            android-nixpkgs
            niri
            ;
        };
        modules = [
          # Apply common overlays to all hosts
          { nixpkgs.overlays = commonOverlays; }
          ./hosts/framework
          ./hosts/framework/overlays.nix
          ./hosts/framework/home.nix
          home-manager.nixosModules.home-manager
          stylix.nixosModules.stylix
        ];
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.nixfmt-rfc-style ];

        inherit
          (pre-commit-hooks.lib.${system}.run {
            src = ./.;
            hooks = {
              nixfmt-rfc-style = {
                enable = true;
                name = "nixfmt";
                description = "Format Nix code with nixfmt";
                files = "\\.nix$";
                entry = "${pkgs.nixfmt-rfc-style}/bin/nixfmt";
              };
            };
          })
          shellHook
          ;
      };
    };
}
