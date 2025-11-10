final: prev: {
  gemini-cli = prev.stdenv.mkDerivation rec {
    pname = "gemini-cli";
    version = "0.15.0-nightly.20251107.cd27cae8";

    src = prev.fetchurl {
      url = "https://github.com/google-gemini/gemini-cli/releases/download/v${version}/gemini.js";
      hash = "sha256-ZkDCLq/GdzA1QPhQ3lLefM0NzNCHCfbgUfjK5Vq8dSk=";
    };

    dontUnpack = true;
    dontBuild = true;

    nativeBuildInputs = [ prev.makeWrapper ];

    installPhase = ''
      mkdir -p $out/bin $out/lib
      cp $src $out/lib/gemini.js

      makeWrapper ${prev.nodejs}/bin/node $out/bin/gemini \
        --add-flags "$out/lib/gemini.js"
    '';

    meta = with prev.lib; {
      description = "An open-source AI agent that brings the power of Gemini directly into your terminal";
      homepage = "https://github.com/google-gemini/gemini-cli";
      license = licenses.asl20;
      maintainers = [ ];
      platforms = platforms.all;
    };
  };
}
