final: prev: {
  opencode = prev.stdenv.mkDerivation rec {
    pname = "opencode";
    version = "1.0.55";

    src = prev.fetchurl {
      url = "https://github.com/sst/opencode/releases/download/v${version}/opencode-linux-x64.zip";
      hash = "sha256-prL9Ws3xnMLniPQPb1zZgY14vV2KH0RbJQ85dBcss/Q=";
    };

    nativeBuildInputs = [
      prev.autoPatchelfHook
      prev.unzip
    ];

    buildInputs = [ prev.stdenv.cc.cc.lib ];

    unpackPhase = ''
      unzip $src
    '';

    installPhase = ''
      mkdir -p $out/bin
      # The zip extracts to a single file named 'opencode'
      cp opencode $out/bin/opencode
      chmod +x $out/bin/opencode
    '';

    meta = with prev.lib; {
      description = "A powerful AI coding agent built for the terminal";
      homepage = "https://github.com/sst/opencode";
      license = licenses.mit;
      maintainers = [ ];
      platforms = [ "x86_64-linux" ];
    };
  };
}

# Update instructions:
# 1. Visit https://github.com/sst/opencode/releases
# 2. Find the latest release version
# 3. Get the SHA256 hash from the release API or download page
# 4. Convert to base64:
#    python3 -c "import base64; print('sha256-' + base64.b64encode(bytes.fromhex('<HEX_HASH>')).decode())"
# 5. Update version and hash above
