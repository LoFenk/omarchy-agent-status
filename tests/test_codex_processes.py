import importlib.util
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location(
    "codex_processes", Path(__file__).parents[1] / "scripts" / "codex_processes.py")
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class ProcessDetectionTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.proc = Path(self.temp.name)
        self.process(10, "foot", 1, tty=0)
        self.process(11, "bash", 10)

    def process(self, pid, name, parent, group=20, foreground=20, tty=34816,
                state="S", stdin="/dev/pts/0", executable="/usr/bin/codex"):
        path = self.proc / str(pid)
        (path / "fd").mkdir(parents=True, exist_ok=True)
        (path / "stat").write_text(
            f"{pid} ({name}) {state} {parent} {group} 11 {tty} {foreground} 0 0\n")
        (path / "fd" / "0").symlink_to(stdin)
        (path / "exe").symlink_to(executable)
        task = self.proc / str(parent) / "task" / str(parent)
        task.mkdir(parents=True, exist_ok=True)
        with (task / "children").open("a") as children:
            children.write(f"{pid} ")

    def test_foreground_codex_maps_to_its_terminal(self):
        self.process(20, "codex", 11)
        self.process(30, "foot", 1, tty=0)
        self.assertEqual(probe.find_codex([10, 30], self.proc), {"10": True})

    def test_exit_clears_session_without_remembering_title(self):
        self.process(20, "codex", 11)
        self.assertEqual(probe.find_codex([10], self.proc), {"10": True})
        (self.proc / "20" / "stat").unlink()
        self.assertEqual(probe.find_codex([10], self.proc), {})

    def test_ignores_background_stopped_dead_and_noninteractive_processes(self):
        cases = [dict(group=21), dict(tty=0), dict(state="T"), dict(state="Z"),
                 dict(stdin="pipe:[123]"), dict(executable="/usr/bin/python3")]
        for index, options in enumerate(cases):
            self.process(20 + index, "codex", 11, **options)
        self.assertEqual(probe.find_codex([10], self.proc), {})

    def test_terminal_identity_is_ancestry_not_name_or_working_directory(self):
        self.process(30, "foot", 1, tty=0)
        self.process(31, "bash", 30)
        self.process(40, "codex", 31)
        self.assertEqual(probe.find_codex([10], self.proc), {})
        self.assertEqual(probe.find_codex([10, 30], self.proc), {"30": True})

    def test_stat_names_with_parentheses_and_executable_replaced_on_update(self):
        self.process(12, "wrapper (shell)", 11)
        self.process(20, "codex", 12, executable="/opt/codex (deleted)")
        self.assertEqual(probe.find_codex([10], self.proc), {"10": True})

    def test_missing_metadata_and_ancestry_cycles_are_safe(self):
        self.process(20, "codex", 21)
        self.process(21, "wrapper", 20)
        self.process(22, "codex", 11)
        (self.proc / "22" / "fd" / "0").unlink()
        self.process(23, "codex", 11)
        (self.proc / "23" / "stat").write_text("gone")
        self.assertEqual(probe.find_codex([10], self.proc), {})

    def test_shell_spawned_by_terminal_worker_thread_is_found(self):
        (self.proc / "10" / "task" / "10" / "children").unlink()
        worker = self.proc / "10" / "task" / "99"
        worker.mkdir()
        (worker / "children").write_text("11")
        self.process(20, "codex", 11)
        self.assertEqual(probe.find_codex([10], self.proc), {"10": True})


if __name__ == "__main__":
    unittest.main()
