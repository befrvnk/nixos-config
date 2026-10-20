"""Native NUON rendering and real Nu prompt-reader behavior in temporary homes."""

import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

import prepare_theme_output as migration


class NushellThemeTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.output = self.root / "state/nushell/theme.nuon"
        self.output.parent.mkdir(parents=True)
        self.template = Path(os.environ["NUSHELL_THEME_TEMPLATE"])
        self.reader = Path(os.environ["NUSHELL_THEME_READER"])
        self.environment = dict(os.environ)
        for key in ("NOCTALIA_CONFIG_HOME", "NOCTALIA_STATE_HOME", "NUSHELL_THEME_MTIME"):
            self.environment.pop(key, None)
        self.environment.update(HOME=str(self.root), XDG_STATE_HOME=str(self.root / "state"),
                                XDG_CONFIG_HOME=str(self.root / "config"),
                                XDG_DATA_HOME=str(self.root / "data"), XDG_CACHE_HOME=str(self.root / "cache"))

    def nu(self, code):
        script = self.root / "test.nu"
        script.write_text(code)
        result = subprocess.run([os.environ["NUSHELL_CLI"], "--no-config-file", str(script)],
                                env=self.environment, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def render(self, palette, mode, output=None):
        tokens = set(re.findall(r"colors\.([a-z_0-9]+)\.default\.hex", self.template.read_text()))
        fixture = self.root / "colors.json"
        fixture.write_text(json.dumps({
            name: {token: color for token in tokens} for name, color in palette.items()
        }))
        result = subprocess.run([
            os.environ["NOCTALIA_BIN"], "theme", "--theme-json", str(fixture), "--both",
            "--default-mode", mode, "--render", f"{self.template}:{output or self.output}",
        ], env=self.environment, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)

    def source(self):
        return f"source '{self.reader}'\n"

    def test_native_renderer_produces_real_nu_color_records_for_two_palettes_and_modes(self):
        for palette in ({"dark": "#123456", "light": "#d0e0f0"},
                        {"dark": "#653412", "light": "#f0e0d0"}):
            for mode, expected in palette.items():
                self.render(palette, mode)
                theme = self.nu(self.source() + "$env.config.color_config | to json --raw\n")
                self.assertEqual(theme["header"], expected)
                self.assertEqual(theme["string"], expected)
                self.assertEqual(theme["hints"], expected)
                self.assertEqual(theme["shape_int"], {"fg": expected, "attr": "b"})
                self.assertEqual(theme["shape_garbage"], {"fg": expected, "bg": expected})

    def test_same_session_prompt_reload_preserves_other_hooks_and_settings(self):
        self.render({"dark": "#123456", "light": "#d0e0f0"}, "dark")
        next_file = self.root / "next.nuon"
        self.render({"dark": "#653412", "light": "#f0e0d0"}, "light", next_file)
        code = '''$env.config.hooks.pre_prompt = [{|| $env.EXISTING_HOOK = 'kept'}]
$env.config.show_banner = false
let bindings = $env.config.keybindings
let completions = $env.config.completions
'''
        code += self.source() + f'''
let before = $env.config.color_config.header
sleep 20ms
open --raw '{next_file}' | save --force (nushell-theme-path)
do --env ($env.config.hooks.pre_prompt | last)
do --env ($env.config.hooks.pre_prompt | first)
{{before: $before, after: $env.config.color_config.header,
 hooks: ($env.config.hooks.pre_prompt | length), existing: $env.EXISTING_HOOK,
 keys_unchanged: ($bindings == $env.config.keybindings),
 completion_unchanged: ($completions == $env.config.completions), banner: $env.config.show_banner}} | to json --raw
'''
        actual = self.nu(code)
        self.assertEqual(actual, {"before": "#123456", "after": "#f0e0d0", "hooks": 2,
                                  "existing": "kept", "keys_unchanged": True,
                                  "completion_unchanged": True, "banner": False})

    def test_missing_empty_nonrecord_and_partial_data_leave_existing_colors_intact(self):
        for contents in (None, "{}", "[1 2]", "{ header:"):
            if contents is None:
                self.output.unlink(missing_ok=True)
            else:
                self.output.write_text(contents)
            actual = self.nu("$env.config.color_config = {header: 'green'}\n" + self.source() + '''
{header: $env.config.color_config.header, cached: ('NUSHELL_THEME_MTIME' in $env)} | to json --raw
''')
            self.assertEqual(actual, {"header": "green", "cached": False})

    def test_failed_refresh_keeps_colors_and_retries_when_valid_data_arrives(self):
        self.render({"dark": "#123456", "light": "#d0e0f0"}, "dark")
        next_file = self.root / "next.nuon"
        self.render({"dark": "#653412", "light": "#f0e0d0"}, "dark", next_file)
        code = self.source() + f'''
let stamp = $env.NUSHELL_THEME_MTIME
sleep 20ms
'{{ header:' | save --force (nushell-theme-path)
refresh-nushell-theme
let retained = ($env.config.color_config.header == '#123456' and $env.NUSHELL_THEME_MTIME == $stamp)
open --raw '{next_file}' | save --force (nushell-theme-path)
refresh-nushell-theme
{{retained: $retained, repaired: $env.config.color_config.header}} | to json --raw
'''
        self.assertEqual(self.nu(code), {"retained": True, "repaired": "#653412"})

    def test_unchanged_file_skips_reload_and_xdg_path_is_used(self):
        self.render({"dark": "#123456", "light": "#d0e0f0"}, "dark")
        actual = self.nu(self.source() + '''
$env.config.color_config.header = 'yellow'
refresh-nushell-theme
{header: $env.config.color_config.header, path: (nushell-theme-path)} | to json --raw
''')
        self.assertEqual(actual, {"header": "yellow", "path": str(self.output)})
        self.assertFalse((self.root / ".local/state/nushell").exists())

    def test_bootstrap_and_protected_output_preserve_native_data(self):
        backup = self.root / "original.nuon"
        migration.prepare(self.output, backup, "{}")
        self.assertIsNone(self.nu(self.source() + "load-nushell-theme | to json --raw\n"))
        self.render({"dark": "#123456", "light": "#d0e0f0"}, "dark")
        before = self.output.read_bytes()
        self.output.chmod(0o444)
        self.assertTrue(migration.prepare(self.output, backup, "{}"))
        self.assertEqual(backup.read_bytes(), before)
        self.assertFalse(migration.prepare(self.output, backup, "{}"))
        self.assertEqual(self.nu(self.source() + "$env.config.color_config.header | to json --raw\n"), "#123456")


if __name__ == "__main__":
    unittest.main()
