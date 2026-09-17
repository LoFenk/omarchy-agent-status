#!/usr/bin/env python3
"""Find foreground Codex CLIs below terminal PIDs, using only local /proc data."""

import json
from pathlib import Path
import sys


def is_foreground_codex(path, process):
    if (process["name"] != "codex" or process["state"] in ("Z", "T", "t", "X")
            or not process["tty"] or process["group"] != process["foreground"]):
        return False
    try:
        # The TUI owns a terminal input. Background app servers, tools and
        # subagents use pipes, even when they inherit a controlling tty.
        stdin = str((path / "fd" / "0").readlink())
        executable = (path / "exe").readlink().name.removesuffix(" (deleted)")
        return executable == "codex" and (stdin.startswith("/dev/pts/") or stdin == "/dev/tty")
    except OSError:
        return False


def read_processes(proc_root, terminal_pids):
    processes = {}
    pending = list(terminal_pids)
    visited = set()
    while pending:
        pid = pending.pop()
        if pid in visited:
            continue
        visited.add(pid)
        path = proc_root / str(pid)
        try:
            raw = (path / "stat").read_text()
            # comm may contain spaces and parentheses; fields after its final
            # ')' start with state (field 3 of proc_pid_stat(5)).
            end = raw.rindex(")")
            fields = raw[end + 2:].split()
            processes[pid] = {
                "name": raw[raw.index("(") + 1:end],
                "state": fields[0],
                "parent": int(fields[1]),
                "group": int(fields[2]),
                "tty": int(fields[4]),
                "foreground": int(fields[5]),
            }
        except (OSError, ValueError, IndexError):
            # Processes can exit mid-scan; inaccessible processes aren't proof
            # of a session either.
            continue
        processes[pid]["codex"] = is_foreground_codex(path, processes[pid])
        if processes[pid]["codex"]:
            # Once the terminal's foreground CLI is found, its tools and
            # subagents cannot identify additional terminal windows.
            continue
        # Walk only terminal descendants, not every process on the machine.
        # A multithreaded terminal can spawn its shell from any thread.
        try:
            for task in (path / "task").iterdir():
                try:
                    pending.extend(int(child) for child in (task / "children").read_text().split())
                except (OSError, ValueError):
                    continue
        except OSError:
            continue
    return processes


def find_codex(terminal_pids, proc_root=Path("/proc")):
    processes = read_processes(proc_root, terminal_pids)
    terminals = set(terminal_pids)
    found = {}
    for pid, process in processes.items():
        if not process["codex"]:
            continue
        ancestor = pid
        seen = set()
        while ancestor in processes and ancestor not in seen:
            if ancestor in terminals:
                found[str(ancestor)] = True
                break
            seen.add(ancestor)
            ancestor = processes[ancestor]["parent"]
    return found


def main():
    pids = json.loads(sys.argv[1])
    if not isinstance(pids, list) or any(type(pid) is not int or pid <= 0 for pid in pids):
        raise ValueError("expected a JSON array of positive terminal PIDs")
    print(json.dumps(find_codex(pids), sort_keys=True))


if __name__ == "__main__":
    main()
