"""Manifest mode: every app's output seeded by a single preparer invocation.

Home Manager used to spawn one python process per app on the boot-critical
activation path, so this covers the batched `--manifest` entry point itself:
placeholder defaults, skipping already-prepared outputs, idempotence and the
still-supported positional form.
"""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import prepare_theme_output as migration

SCRIPT = Path(__file__).with_name("prepare_theme_output.py")


class PrepareManifestTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.manifest = self.root / "prepare-outputs.json"

    def run_preparer(self, *arguments):
        return subprocess.run(
            [sys.executable, str(SCRIPT), *map(str, arguments)],
            capture_output=True, text=True, timeout=30,
        )

    def entries(self):
        return [
            {"theme": str(self.root / "config/app/theme.toml"),
             "backup": str(self.root / "state/app.pre-template"),
             "placeholder": "# seeded app"},
            # A null placeholder mirrors the option default: use the preparer's own.
            {"theme": str(self.root / "config/ghostty/theme"),
             "backup": str(self.root / "state/ghostty.pre-template"),
             "placeholder": None},
        ]

    def test_manifest_seeds_every_entry_in_one_invocation(self):
        self.manifest.write_text(json.dumps(self.entries()))
        result = self.run_preparer("--manifest", self.manifest)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            (self.root / "config/app/theme.toml").read_text(), "# seeded app"
        )
        self.assertEqual(
            (self.root / "config/ghostty/theme").read_text(), migration.PLACEHOLDER
        )
        self.assertEqual(result.stdout.splitlines(), [
            f"Prepared writable Noctalia theme output: {self.root / 'config/app/theme.toml'}",
            f"Prepared writable Noctalia theme output: {self.root / 'config/ghostty/theme'}",
        ])

    def test_manifest_skips_prepared_outputs_and_is_idempotent(self):
        for entry in self.entries():
            migration.prepare(Path(entry["theme"]), Path(entry["backup"]),
                              entry["placeholder"] or migration.PLACEHOLDER)
        theme = self.root / "config/app/theme.toml"
        theme.write_text("runtime colors\n")
        self.manifest.write_text(json.dumps(self.entries()))

        first = self.run_preparer("--manifest", self.manifest)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(first.stdout, "")
        self.assertEqual(theme.read_text(), "runtime colors\n")
        self.assertFalse((self.root / "state/app.pre-template").exists())

        second = self.run_preparer("--manifest", self.manifest)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(second.stdout, "")

    def test_missing_placeholder_key_falls_back_to_the_default(self):
        entry = {"theme": str(self.root / "config/default/theme"),
                 "backup": str(self.root / "state/default.pre-template")}
        self.manifest.write_text(json.dumps([entry]))
        result = self.run_preparer("--manifest", self.manifest)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            Path(entry["theme"]).read_text(), migration.PLACEHOLDER
        )

    def test_positional_form_still_prepares_a_single_output(self):
        theme = self.root / "config/one/theme"
        result = self.run_preparer(
            theme, self.root / "state/one.pre-template", "--placeholder", "# one"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(theme.read_text(), "# one")

    def test_manifest_and_positional_arguments_are_both_required(self):
        result = self.run_preparer()
        self.assertEqual(result.returncode, 2)
        self.assertIn("--manifest", result.stderr)
        result = self.run_preparer(self.root / "config/only-theme")
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
