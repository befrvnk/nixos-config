"""Source only Atuin's generated integration in a private, noninteractive Nu."""

import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


class AtuinNushellTests(unittest.TestCase):
    def run_nu(self, integration):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ("config", "data", "state", "atuin"):
                (root / name).mkdir()
            environment = {key: value for key, value in os.environ.items()
                           if not key.startswith("ATUIN_")}
            environment.update(
                HOME=directory, XDG_CONFIG_HOME=str(root / "config"),
                XDG_DATA_HOME=str(root / "data"), XDG_STATE_HOME=str(root / "state"),
                ATUIN_CONFIG_DIR=str(root / "atuin"), NO_COLOR="1", TERM="dumb",
            )
            code = (f'$env.config.keybindings = []\nsource "{integration}"\n'
                    '$env.config.keybindings | to json --raw')
            return subprocess.run(
                [os.environ["NUSHELL_CLI"], "--no-config-file", "--no-history", "-c", code],
                env=environment, capture_output=True, text=True, timeout=20,
            )

    def test_current_home_manager_atuin_init_has_unique_names_and_original_keys(self):
        config = Path(os.environ["NU_MANAGED_CONFIG"]).read_text()
        matches = re.findall(r'^source ([^\n]*atuin-nushell-config\.nu)\s*$', config, re.M)
        self.assertEqual(len(matches), 1)
        integration = Path(matches[0].strip('"\''))
        self.assertTrue(integration.is_file())
        result = self.run_nu(integration)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("shared_keybindings_name", result.stderr)
        self.assertNotIn("invalid_config", result.stderr)
        bindings = json.loads(result.stdout)
        names = [binding["name"] for binding in bindings]
        self.assertEqual(len(names), len(set(names)))
        self.assertEqual(len(bindings), 2)
        keys = {binding["keycode"]: binding for binding in bindings}
        self.assertEqual(keys["char_r"]["modifier"], "control")
        self.assertEqual(keys["up"]["modifier"], "none")
        for binding in bindings:
            self.assertEqual(binding["mode"], ["emacs", "vi_normal", "vi_insert"])

    def test_probe_detects_the_reported_duplicate_name_warning(self):
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory) / "duplicate.nu"
            fixture.write_text('''$env.config.keybindings = [
              {name: atuin, modifier: control, keycode: char_r,
               mode: emacs, event: {send: historysearch}}
              {name: atuin, modifier: none, keycode: up,
               mode: emacs, event: {send: up}}
            ]
''')
            result = self.run_nu(fixture)
        self.assertIn("shared_keybindings_name", result.stderr)


if __name__ == "__main__":
    unittest.main()
