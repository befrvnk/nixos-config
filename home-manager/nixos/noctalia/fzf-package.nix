{
  configHome,
  fzf,
  lib,
  makeWrapper,
  symlinkJoin,
}:
symlinkJoin {
  name = "fzf-noctalia";
  inherit (fzf) version;
  meta = fzf.meta // {
    outputsToInstall = [ "out" ];
  };
  paths = [
    fzf
    (lib.getMan fzf)
  ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    wrapProgram "$out/bin/fzf" --run ${lib.escapeShellArg ''
      noctalia_fzf_theme="''${XDG_CONFIG_HOME:-${configHome}}/fzf/themes/noctalia.sh"
      if [[ -r "$noctalia_fzf_theme" ]]; then
        source "$noctalia_fzf_theme"
      fi
    ''}
  '';
}
