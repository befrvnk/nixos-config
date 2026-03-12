detect_mode() {
  case "$(uname)" in
    Darwin)
      if defaults read -g AppleInterfaceStyle 2>/dev/null | grep -q Dark; then
        echo "dark"
      else
        echo "light"
      fi
      ;;
    *)
      if command -v darkman >/dev/null 2>&1; then
        darkman get 2>/dev/null || echo "dark"
      else
        echo "dark"
      fi
      ;;
  esac
}

MODE=$(detect_mode)
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/gh-dash"

exec gh dash --config "$CONFIG_DIR/config-$MODE.yml" "$@"
