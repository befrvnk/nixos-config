# Add Zen Browser support to profile-sync-daemon
# Based on: https://github.com/graysky2/profile-sync-daemon/blob/master/contrib/zen
# Includes fix from PR #392: https://github.com/graysky2/profile-sync-daemon/pull/392
# (Use ^[Pp]ath= to avoid matching ZenAvatarPath in profiles.ini)
# NixOS-specific: PSNAME matches the wrapped binary name (truncated to 15 chars)
final: prev: {
  profile-sync-daemon = prev.profile-sync-daemon.overrideAttrs (oldAttrs: {
    installPhase = oldAttrs.installPhase + ''
      # Add Zen Browser definition (Firefox fork with profile at ~/.zen)
      cat > $out/share/psd/browsers/zen << 'EOF'
      if [[ -d "$HOME"/.zen ]]; then
        index=0
        PSNAME=".zen-beta-wrapp"
        while read -r profileItem; do
          if [[ $(echo "$profileItem" | cut -c1) = "/" ]]; then
            # path is not relative
            DIRArr[$index]="$profileItem"
          else
            # append the default path for relative paths
            DIRArr[$index]="$HOME/.zen/$profileItem"
          fi
          (( index=index+1 ))
        done <<<$(grep '^[Pp]ath=' "$HOME"/.zen/profiles.ini | sed 's/^[Pp]ath=//')
      fi

      check_suffix=1
      EOF
    '';
  });
}
