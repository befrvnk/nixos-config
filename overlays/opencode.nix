final: prev: {
  opencode = prev.stdenv.mkDerivation rec {
    pname = "opencode";
    version = "0.0.55";

    src = prev.fetchurl {
      url = "https://github.com/opencode-ai/opencode/releases/download/v${version}/opencode-linux-x86_64.tar.gz";
      hash = "sha256-fx9BID55IOrEjz4iFtM06c6MbQp7EHzrdY7+vaTUmAU=";
    };

    nativeBuildInputs = [ prev.autoPatchelfHook ];

    buildInputs = [ prev.stdenv.cc.cc.lib ];

    installPhase = ''
      mkdir -p $out/bin
      cp opencode $out/bin/opencode
      chmod +x $out/bin/opencode
    '';

    meta = with prev.lib; {
      description = "A powerful AI coding agent built for the terminal";
      homepage = "https://github.com/opencode-ai/opencode";
      license = licenses.asl20;
      maintainers = [ ];
      platforms = [ "x86_64-linux" ];
    };
  };
}

# Update instructions:
# 1. Visit https://github.com/opencode-ai/opencode/releases
# 2. Find the latest release version
# 3. Download checksums.txt from the release
# 4. Find the SHA256 for opencode-linux-x86_64.tar.gz
# 5. Convert to base64 hash: nix-hash --to-base64 --type sha256 <hex-hash>
# 6. Update version and hash above
