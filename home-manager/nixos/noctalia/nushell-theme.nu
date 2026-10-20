# The palette producer is Noctalia; this is the existing prompt-time reader.
def nushell-theme-path [] {
  ($env.XDG_STATE_HOME? | default ($env.HOME | path join ".local" "state"))
  | path join "nushell" "theme.nuon"
}

def load-nushell-theme [] {
  try {
    let theme = (open --raw (nushell-theme-path) | from nuon)
    if (($theme | describe | str starts-with "record") and not ($theme | is-empty)) {
      $theme
    } else {
      null
    }
  } catch { null }
}

def --env refresh-nushell-theme [] {
  # Don't cache failures: a partial write/missing file is retried next prompt.
  let update = (try {
    let modified = (ls -l (nushell-theme-path) | get 0.modified)
    if $modified == ($env.NUSHELL_THEME_MTIME? | default null) {
      null
    } else {
      let theme = (load-nushell-theme)
      if $theme == null { null } else { {theme: $theme, modified: $modified} }
    }
  } catch { null })
  if $update != null {
    $env.config.color_config = $update.theme
    $env.NUSHELL_THEME_MTIME = $update.modified
  }
}

refresh-nushell-theme
$env.config.hooks.pre_prompt = ($env.config.hooks.pre_prompt | default [] | append {||
  refresh-nushell-theme
})
