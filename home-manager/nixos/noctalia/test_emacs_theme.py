"""Load the pinned native theme in batch Emacs, never user init files/daemons."""

import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

import prepare_theme_output as migration


class EmacsThemeTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.output = self.root / "state/noctalia/emacs/noctalia-theme.el"
        self.output.parent.mkdir(parents=True)
        self.template = Path(os.environ["NOCTALIA_SOURCE"]) / "assets/templates/emacs/emacs.el"
        self.init = self.root / "managed-init.el"
        self.init.write_text(Path(os.environ["EMACS_MANAGED_INIT"]).read_text().replace(
            os.environ["MANAGED_STATE_HOME"], str(self.root / "state")))
        self.environment = dict(os.environ, HOME=str(self.root),
                                XDG_CONFIG_HOME=str(self.root / "config"),
                                XDG_STATE_HOME=str(self.root / "state"),
                                XDG_DATA_HOME=str(self.root / "data"), XDG_CACHE_HOME=str(self.root / "cache"))

    def render(self, palette, mode):
        tokens = set(re.findall(r"colors\.([a-z_0-9]+)\.default\.hex", self.template.read_text()))
        fixture = self.root / "colors.json"
        fixture.write_text(json.dumps({
            name: {token: color for token in tokens} for name, color in palette.items()
        }))
        result = subprocess.run([
            os.environ["NOCTALIA_BIN"], "theme", "--theme-json", str(fixture), "--both",
            "--default-mode", mode, "--render", f"{self.template}:{self.output}",
        ], env=self.environment, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("{{", self.output.read_text())

    def probe(self):
        probe = self.root / "probe.el"
        probe.write_text('''(require 'json)
(princ (json-encode
        `((themes . ,(vconcat (mapcar #'symbol-name custom-enabled-themes)))
          (background . ,(face-attribute 'default :background nil t))
          (foreground . ,(face-attribute 'default :foreground nil t))
          (family . ,(face-attribute 'default :family nil t))
          (opacity . ,(cdr (assq 'alpha-background default-frame-alist))))))
''')
        result = subprocess.run([
            os.environ["EMACS_CLI"], "--batch", "--quick", "--load", str(self.init), "--load", str(probe),
        ], env=self.environment, cwd=self.root, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_two_palettes_and_modes_load_in_real_batch_emacs(self):
        for palette in ({"dark": "#123456", "light": "#d0e0f0"},
                        {"dark": "#653412", "light": "#f0e0d0"}):
            for mode, expected in palette.items():
                self.render(palette, mode)
                actual = self.probe()
                self.assertEqual(actual["themes"], ["noctalia"])
                self.assertEqual(actual["background"], expected)
                self.assertEqual(actual["foreground"], expected)

    def test_managed_font_and_opacity_are_preserved(self):
        self.render({"dark": "#123456", "light": "#d0e0f0"}, "dark")
        actual = self.probe()
        self.assertEqual(actual["opacity"], 100)
        text = self.init.read_text()
        # Batch Emacs has a TTY frame and reports family 'default'; preserve the
        # exact configured font-spec here rather than claiming GUI resolution.
        self.assertIn(':family "JetBrainsMono Nerd Font"', text)
        self.assertIn(":size 11", text)
        self.assertNotIn("base16-stylix", text)
        self.assertNotIn("emacsclient", text)

    def test_missing_and_placeholder_output_do_not_break_startup(self):
        self.assertEqual(self.probe()["themes"], [])
        migration.prepare(self.output, self.root / "backup.el",
                          '(deftheme noctalia "Awaiting native colors.") (provide-theme (quote noctalia))')
        self.assertEqual(self.probe()["themes"], ["noctalia"])

    def test_personal_doom_and_spacemacs_wrapper_routes_are_unchanged(self):
        routes = json.loads(Path(os.environ["EMACS_ROUTES"]).read_text())
        self.assertEqual({route["name"] for route in routes}, {"doom-emacs", "spacemacs"})
        for route in routes:
            text = Path(route["path"]).read_text()
            directory = "emacs-doom" if route["name"] == "doom-emacs" else "emacs-spacemacs"
            self.assertIn(f'--init-directory="$HOME/.config/{directory}"', text)
            self.assertNotIn("noctalia", text)
            self.assertNotIn("with-packages", text)

    def test_native_render_and_batch_probe_never_write_personal_profiles(self):
        personal = [self.root / "config/doom/config.el", self.root / ".spacemacs"]
        for path in personal:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(";;; personal file must remain untouched\n")
        before = {path: path.read_bytes() for path in personal}
        init_before = self.init.read_bytes()
        self.render({"dark": "#123456", "light": "#d0e0f0"}, "dark")
        self.probe()
        self.assertEqual(self.init.read_bytes(), init_before)
        for path, content in before.items():
            self.assertEqual(path.read_bytes(), content)

    def test_protected_runtime_output_is_backed_up_without_losing_theme(self):
        self.render({"dark": "#123456", "light": "#d0e0f0"}, "dark")
        before = self.output.read_bytes()
        self.output.chmod(0o444)
        backup = self.root / "backup.el"
        self.assertTrue(migration.prepare(self.output, backup, "unused"))
        self.assertEqual(backup.read_bytes(), before)
        self.assertFalse(migration.prepare(self.output, backup, "unused"))
        self.assertEqual(self.probe()["background"], "#123456")


if __name__ == "__main__":
    unittest.main()
