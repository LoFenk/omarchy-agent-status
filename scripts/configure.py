#!/usr/bin/env python3
"""Apply the optional bar preset or migrate upstream widget IDs. No dependencies."""

import argparse
import copy
import json
import os
from pathlib import Path
import stat
import sys
import tempfile


PLUGIN_ID = "io.github.lofenk.agent-status"
LEGACY_IDS = {"io.github.mae240.agent-status", "mae.agent-status"}
SECTIONS = ("left", "center", "right")
DEFAULTS = Path("/usr/share/omarchy/config/omarchy/shell.json")


def read_document(path):
    document = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(document, dict):
        raise ValueError(f"{path}: expected a JSON object")
    return document


def configure_document(document, action, defaults_path=DEFAULTS):
    result = copy.deepcopy(document)
    bar = result.setdefault("bar", {})
    if not isinstance(bar, dict):
        raise ValueError("bar must be an object")
    layout = bar.setdefault("layout", {})
    if not isinstance(layout, dict):
        raise ValueError("bar.layout must be an object")
    for section in SECTIONS:
        # Missing sections inherit the current machine's Omarchy defaults.
        if section not in layout:
            defaults = read_document(defaults_path)
            layout[section] = copy.deepcopy(defaults["bar"]["layout"][section])
        entries = layout[section]
        if not isinstance(entries, list) or any(
            not isinstance(entry, dict) or not isinstance(entry.get("id"), str)
            for entry in entries
        ):
            raise ValueError(f"bar.layout.{section} must be a list of widget objects with IDs")

    widgets = [entry for section in SECTIONS for entry in layout[section]]
    if action == "migrate":
        if not any(entry["id"] in LEGACY_IDS for entry in widgets):
            return document  # Already migrated, or nothing to migrate.
        if any(entry["id"] == PLUGIN_ID for entry in widgets):
            raise ValueError("Both upstream and fork widgets are configured; remove the unwanted instances in bar settings before migrating")
        for entry in widgets:
            if entry["id"] in LEGACY_IDS:
                entry["id"] = PLUGIN_ID
        return result
    if action != "preset":
        raise ValueError(f"Unknown action: {action}")

    # Keep existing colors/terminal filters and other settings on the first
    # instance of each view. Only the preset's layout choices are overridden.
    existing = [entry for entry in widgets if entry["id"] == PLUGIN_ID]
    sessions = next((entry for entry in existing if entry.get("view", "sessions") == "sessions"), {})
    detail = next((entry for entry in existing if entry.get("view") == "detail"), {})
    sessions.update(id=PLUGIN_ID, view="sessions", showWorkspaceNumber=True,
                    highlightActive=True, hideSessionNames=True, maxSessions=5)
    detail.update(id=PLUGIN_ID, view="detail", showActiveDetail=True, maxDetailWidth=480)
    for section in SECTIONS:
        layout[section] = [entry for entry in layout[section] if entry["id"] != PLUGIN_ID]
    left = layout["left"]
    index = next((index + 1 for index, entry in enumerate(left)
                  if entry["id"] == "omarchy.workspaces"), len(left))
    left.insert(index, sessions)
    layout["right"].insert(0, detail)
    return result


def apply_configuration(path, action, defaults_path=DEFAULTS, dry_run=False):
    # Resolve dotfile symlinks so atomic replacement preserves the symlink.
    path = path.expanduser().resolve()
    original = path.read_bytes() if path.exists() else None
    document = json.loads(original) if original is not None else read_document(defaults_path)
    if not isinstance(document, dict):
        raise ValueError(f"{path}: expected a JSON object")
    result = configure_document(document, action, defaults_path)
    if dry_run:
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return None
    if result == document:
        print("Already configured; no changes.")
        return None
    content = (json.dumps(result, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = stat.S_IMODE(path.stat().st_mode) if original is not None else 0o600
    backup = None
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix=f".{path.name}.", delete=False) as output:
        temporary = Path(output.name)
        try:
            output.write(content)
            output.flush()
            os.fsync(output.fileno())
            os.fchmod(output.fileno(), mode)
            current = path.read_bytes() if path.exists() else None
            if current != original:
                raise ValueError("Configuration changed while preparing the update; run the command again")
            if original is not None:
                with tempfile.NamedTemporaryFile(dir=path.parent, prefix=f"{path.name}.bak.agent-status-", delete=False) as saved:
                    backup = Path(saved.name)
                    saved.write(original)
                    saved.flush()
                    os.fsync(saved.fileno())
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)
    print(f"Updated {path}")
    if backup:
        print(f"Backup: {backup}")
    print("Omarchy watches shell.json and should reload the layout automatically.")
    return backup


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("preset", "migrate"),
                        help="preset: compact left pills and right topic; migrate: replace upstream IDs in place")
    parser.add_argument("--config", type=Path, default=Path.home() / ".config/omarchy/shell.json")
    parser.add_argument("--dry-run", action="store_true", help="print the proposed JSON without writing")
    args = parser.parse_args()
    try:
        apply_configuration(args.config, args.action, dry_run=args.dry_run)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"agent-status: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
