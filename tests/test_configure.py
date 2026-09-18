import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import stat
import tempfile
import unittest


spec = importlib.util.spec_from_file_location(
    "configure", Path(__file__).parents[1] / "scripts" / "configure.py")
configure = importlib.util.module_from_spec(spec)
spec.loader.exec_module(configure)
PLUGIN_ID = configure.PLUGIN_ID


class ConfigureTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "shell.json"
        self.defaults = Path(self.temp.name) / "defaults.json"
        self.document = {
            "version": 1,
            "idle": {"lock": 300},
            "plugins": [{"id": "another.plugin", "option": "keep"}],
            "bar": {"position": "top", "layout": {
                "left": [{"id": "omarchy.menu"}, {"id": "omarchy.workspaces"},
                         {"id": "custom.widget", "setting": [1, 2]}],
                "center": [{"id": "omarchy.clock", "format": "HH:mm"}],
                "right": [{"id": "omarchy.tray"}, {"id": "omarchy.audio"}],
            }},
        }
        self.defaults.write_text(json.dumps(self.document))
        self.path.write_text(json.dumps(self.document))

    def apply(self, action="preset", **kwargs):
        with contextlib.redirect_stdout(io.StringIO()):
            return configure.apply_configuration(self.path, action, self.defaults, **kwargs)

    def test_preset_preserves_unrelated_widgets_and_settings(self):
        original = copy.deepcopy(self.document)
        result = configure.configure_document(self.document, "preset", self.defaults)
        self.assertEqual(self.document, original)
        self.assertEqual(result["idle"], original["idle"])
        self.assertEqual(result["plugins"], original["plugins"])
        layout = result["bar"]["layout"]
        self.assertEqual(layout["left"][2], {
            "id": PLUGIN_ID, "view": "sessions", "showWorkspaceNumber": True,
            "highlightActive": True, "hideSessionNames": True, "maxSessions": 5,
        })
        self.assertEqual(layout["right"][0], {
            "id": PLUGIN_ID, "view": "detail", "showActiveDetail": True,
            "maxDetailWidth": 480,
        })
        for section in configure.SECTIONS:
            self.assertEqual([entry for entry in layout[section] if entry["id"] != PLUGIN_ID],
                             original["bar"]["layout"][section])

    def test_preset_consolidates_fork_instances_and_retains_other_options(self):
        layout = self.document["bar"]["layout"]
        upstream = {"id": "io.github.mae240.agent-status", "maxSessions": 2}
        layout["left"].append(upstream)
        layout["center"].extend([
            {"id": PLUGIN_ID, "maxSessions": 1, "doneColor": "#123456", "extraAppIds": "terminal"},
            {"id": PLUGIN_ID, "view": "detail", "codexColor": "accent"},
            {"id": PLUGIN_ID, "maxSessions": 9},
        ])
        result = configure.configure_document(self.document, "preset", self.defaults)
        updated = result["bar"]["layout"]
        self.assertIn(upstream, updated["left"])
        self.assertEqual(updated["left"][2]["doneColor"], "#123456")
        self.assertEqual(updated["left"][2]["extraAppIds"], "terminal")
        self.assertEqual(updated["right"][0]["codexColor"], "accent")
        widgets = [entry for section in configure.SECTIONS for entry in updated[section]]
        self.assertEqual(sum(entry["id"] == PLUGIN_ID for entry in widgets), 2)
        self.assertEqual(configure.configure_document(result, "preset", self.defaults), result)

    def test_migration_changes_only_legacy_ids(self):
        layout = self.document["bar"]["layout"]
        layout["left"].append({"id": "io.github.mae240.agent-status", "maxSessions": 7})
        layout["right"].append({"id": "mae.agent-status", "view": "detail", "maxDetailWidth": 240})
        expected = copy.deepcopy(self.document)
        expected["bar"]["layout"]["left"][-1]["id"] = PLUGIN_ID
        expected["bar"]["layout"]["right"][-1]["id"] = PLUGIN_ID
        result = configure.configure_document(self.document, "migrate", self.defaults)
        self.assertEqual(result, expected)
        self.assertEqual(configure.configure_document(result, "migrate", self.defaults), result)

    def test_migration_refuses_ambiguous_coexisting_widgets_without_writing(self):
        self.document["bar"]["layout"]["left"].extend([
            {"id": PLUGIN_ID}, {"id": "io.github.mae240.agent-status"},
        ])
        self.path.write_text(json.dumps(self.document))
        original = self.path.read_bytes()
        with self.assertRaisesRegex(ValueError, "Both upstream and fork"):
            self.apply("migrate")
        self.assertEqual(self.path.read_bytes(), original)
        self.assertEqual(list(self.path.parent.glob("shell.json.bak.*")), [])

    def test_backup_is_exact_and_repeat_application_does_not_write(self):
        original = self.path.read_bytes()
        self.path.chmod(0o640)
        backup = self.apply()
        self.assertEqual(backup.read_bytes(), original)
        self.assertEqual(stat.S_IMODE(self.path.stat().st_mode), 0o640)
        after = self.path.stat().st_mtime_ns
        self.assertIsNone(self.apply())
        self.assertEqual(self.path.stat().st_mtime_ns, after)
        self.assertEqual(list(self.path.parent.glob("shell.json.bak.*")), [backup])

    def test_missing_config_uses_host_defaults(self):
        self.path.unlink()
        self.assertIsNone(self.apply())
        result = json.loads(self.path.read_text())
        self.assertEqual(result["idle"], self.document["idle"])
        self.assertEqual(result["bar"]["layout"]["center"], self.document["bar"]["layout"]["center"])
        self.assertEqual(result["bar"]["layout"]["left"][2]["id"], PLUGIN_ID)

    def test_partial_config_inherits_only_missing_sections(self):
        result = configure.configure_document({"bar": {"layout": {"left": []}}}, "preset", self.defaults)
        self.assertEqual(len(result["bar"]["layout"]["left"]), 1)
        self.assertEqual(result["bar"]["layout"]["center"], self.document["bar"]["layout"]["center"])

    def test_symlink_to_dotfile_is_preserved(self):
        target = self.path.with_name("managed-shell.json")
        self.path.rename(target)
        self.path.symlink_to(target)
        backup = self.apply()
        self.assertTrue(self.path.is_symlink())
        self.assertEqual(json.loads(backup.read_text()), self.document)
        self.assertEqual(json.loads(target.read_text())["bar"]["layout"]["left"][2]["id"], PLUGIN_ID)

    def test_dry_run_does_not_write_or_create_backup(self):
        original = self.path.read_bytes()
        self.apply(dry_run=True)
        self.assertEqual(self.path.read_bytes(), original)
        self.assertEqual(list(self.path.parent.glob("shell.json.bak.*")), [])
        self.path.unlink()
        self.apply(dry_run=True)
        self.assertFalse(self.path.exists())

    def test_invalid_config_is_not_replaced(self):
        for content in ("broken json", "[]", '{"bar": null}',
                        '{"bar": {"layout": []}}',
                        '{"bar": {"layout": {"left": ["bad widget"]}}}'):
            with self.subTest(content=content):
                self.path.write_text(content)
                with self.assertRaises(ValueError):
                    self.apply()
                self.assertEqual(self.path.read_text(), content)
                self.assertEqual(list(self.path.parent.glob("shell.json.bak.*")), [])

    def test_missing_defaults_do_not_erase_partial_configuration(self):
        self.defaults.unlink()
        self.path.write_text('{"idle": {"lock": 600}}')
        original = self.path.read_bytes()
        with self.assertRaises(OSError):
            self.apply()
        self.assertEqual(self.path.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
