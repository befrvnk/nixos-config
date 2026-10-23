"""Declarative shared bar policy; native geometry is separately probed without GUI."""

import json
import os
from pathlib import Path
import unittest


class BarStyleTests(unittest.TestCase):
    def setUp(self):
        self.policy = json.loads(Path(os.environ["NATIVE_BAR_STYLE"]).read_text())
        self.bar = self.policy["bar"]

    def test_continuous_background_preserves_one_floating_gap_and_side_insets(self):
        self.assertFalse(self.bar["capsule"])
        self.assertEqual(self.bar["background_opacity"], 1.0)
        self.assertEqual(self.bar["margin_edge"], 16)
        self.assertEqual(self.bar["margin_ends"], 16)
        self.assertEqual(self.bar["thickness"], 34)
        self.assertFalse(self.bar["shadow"])
        self.assertFalse(self.bar["compositor_blur"])
        self.assertIn("bar-ipc-edge-slide.patch", self.policy["patches"])

    def test_overview_visibility_does_not_gain_pointer_reveal_or_reserved_space(self):
        for key in ("auto_hide", "smart_auto_hide", "show_on_workspace_switch", "reserve_space"):
            with self.subTest(key=key):
                self.assertFalse(self.bar[key])
        self.assertEqual(self.bar["position"], "top")

    def test_widgets_type_and_neutral_text_are_preserved(self):
        self.assertEqual(self.policy["font"], "JetBrainsMono Nerd Font")
        self.assertEqual(self.bar["font_scale"], 1.14)
        self.assertEqual(self.bar["widget_spacing"], 12)
        self.assertEqual(self.bar["border"], "outline")
        self.assertEqual(self.bar["border_width"], 1.0)
        self.assertEqual(self.bar["radius"], 16)
        self.assertEqual(self.bar["padding"], 12)  # Main-axis inset replaces outer capsule padding.
        self.assertEqual(self.bar["color"], "on_surface")
        self.assertEqual(self.bar["start"], ["cpu", "ram", "temperature"])
        self.assertEqual(self.bar["center"], ["weather", "clock", "notifications"])
        self.assertEqual(self.bar["end"], ["tray", "storage", "network", "bluetooth",
                                          "volume", "brightness", "caffeine", "lid-guard", "battery", "control-center"])
        self.assertEqual(self.policy["widget"]["clock"]["format"], "{:%a %d %b  %H:%M}")
        self.assertTrue(self.policy["widget"]["clock"]["anchor"])
        for name in ("cpu", "ram", "temperature"):
            self.assertEqual(self.policy["widget"][name]["highlight_color"], "on_surface")
            self.assertEqual(self.policy["widget"][name]["visualization"], "none")

    def test_native_numeric_min_widths_reduce_jitter_without_removing_values(self):
        for name, width in (("cpu", 48), ("ram", 48), ("temperature", 56)):
            widget = self.policy["widget"][name]
            self.assertEqual(widget["label_min_width"], width)
            self.assertTrue(widget.get("show_value", True))
            self.assertTrue(widget.get("label_show_units", True))
        self.assertTrue(self.policy["widget"]["network"]["show_label"])
        self.assertTrue(self.policy["widget"]["bluetooth"]["show_label"])


if __name__ == "__main__":
    unittest.main()
