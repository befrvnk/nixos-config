final: prev: {
  user-scanner = prev.python3Packages.buildPythonApplication rec {
    pname = "user-scanner";
    version = "1.0.8.1";
    pyproject = true;

    src = prev.fetchPypi {
      pname = "user_scanner";
      inherit version;
      hash = "sha256-d4+oLf3k+EmxUWCH2S5NSLpnOeF4gRQmvDVqlNxZuLY=";
    };

    build-system = [ prev.python3Packages.flit-core ];

    dependencies = with prev.python3Packages; [
      httpx
      colorama
    ];

    # No tests in the package
    doCheck = false;

    meta = {
      description = "Multi-platform username availability checker";
      homepage = "https://github.com/kaifcodec/user-scanner";
      license = prev.lib.licenses.mit;
      mainProgram = "user-scanner";
    };
  };
}
