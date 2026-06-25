{ pkgs, ... }:

let
  worktrunkCopyGradleBuildCache = pkgs.writeShellApplication {
    name = "worktrunk-copy-gradle-build-cache";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.git
    ];
    text = ''
      if [ "$#" -lt 2 ]; then
        echo "usage: worktrunk-copy-gradle-build-cache SOURCE... DEST" >&2
        exit 2
      fi

      dest_root="''${!#}"
      source_count=$(($# - 1))
      sources=("''${@:1:source_count}")

      if [ ! -d "$dest_root" ]; then
        exit 0
      fi

      is_gradle_repo() {
        local root="$1"
        [ -f "$root/settings.gradle" ] \
          || [ -f "$root/settings.gradle.kts" ] \
          || [ -f "$root/build.gradle" ] \
          || [ -f "$root/build.gradle.kts" ] \
          || [ -x "$root/gradlew" ]
      }

      copy_entry() {
        local src="$1"
        local dst_parent="$2"

        if [ "$(uname -s)" = "Darwin" ]; then
          # Prefer APFS clone copies on macOS for large Gradle build artifacts.
          if /bin/cp -cR -p "$src" "$dst_parent/" 2>/dev/null; then
            return 0
          fi

          if /bin/cp -R -p "$src" "$dst_parent/" 2>/dev/null; then
            return 0
          fi
        elif cp -a --reflink=auto "$src" "$dst_parent/" 2>/dev/null; then
          return 0
        fi

        printf 'warning: failed to copy %s to %s\n' "$src" "$dst_parent" >&2
        return 0
      }

      copy_build_dirs_from() {
        local source_root="$1"
        local copied=0

        if [ ! -d "$source_root" ] || [ "$source_root" = "$dest_root" ]; then
          return 0
        fi

        if ! is_gradle_repo "$source_root"; then
          return 0
        fi

        while IFS= read -r -d "" build_dir; do
          local rel="''${build_dir#"$source_root"/}"

          # Keep this personal hook conservative: only copy directories Git already
          # considers ignored in the source worktree.
          if ! git -C "$source_root" check-ignore -q -- "$rel/"; then
            continue
          fi

          local dest_dir="$dest_root/$rel"
          mkdir -p "$dest_dir"

          shopt -s nullglob dotglob
          local children=("$build_dir"/*)
          shopt -u nullglob dotglob

          local child
          for child in "''${children[@]}"; do
            local name="''${child##*/}"
            local dest_child="$dest_dir/$name"
            if [ -e "$dest_child" ]; then
              continue
            fi
            copy_entry "$child" "$dest_dir"
            copied=$((copied + 1))
          done
        done < <(
          find "$source_root" \
            \( -name .git -o -name .gradle -o -name node_modules -o -name .worktrees \) -prune -o \
            -type d -name build -print0 -prune
        )

        if [ "$copied" -gt 0 ]; then
          echo "Copied Gradle build cache entries from $source_root: $copied" >&2
        fi
      }

      if ! is_gradle_repo "$dest_root"; then
        exit 0
      fi

      for source_root in "''${sources[@]}"; do
        copy_build_dirs_from "$source_root"
      done
    '';
  };
in
{
  home.packages = [
    pkgs.worktrunk
    worktrunkCopyGradleBuildCache
  ];

  xdg.configFile."worktrunk/config.toml".text = ''
    [commit]
    stage = "tracked"

    # Auto-allow direnv when new worktrees contain an .envrc.
    [pre-start]
    direnv = "test ! -e .envrc || direnv allow"

    # Personal Gradle worktree warm-up: copy ignored **/build/* artifacts from
    # existing worktrees into newly-created Gradle worktrees. This intentionally
    # avoids requiring per-repository .worktreeinclude or .gitignore changes.
    [post-start]
    copy-gradle-build-cache = "worktrunk-copy-gradle-build-cache {{ base_worktree_path }} {{ primary_worktree_path }} {{ worktree_path }}"
  '';
}
