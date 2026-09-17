# Agent Status

See every open Claude Code and Codex session at a glance, directly in the
Omarchy bar. Each session gets its own chip with the agent mark, session name
and live working or ready state.

![Claude Code ready, Codex working, and Codex ready](chip-states.png)

**Supported agents:** Claude Code and Codex. No other coding agents are
detected.

## Install

Agent Status requires Omarchy 4 (Quattro), a horizontal bar and Python 3
(included with Omarchy).

```bash
omarchy plugin add https://github.com/mae240/omarchy-agent-status.git --enable
```

The widget is added to the left side of the bar, next to the workspaces. Move
it to another section at any time:

```bash
omarchy bar move io.github.mae240.agent-status --section right
```

### Codex works without configuration

Local Codex sessions in ordinary terminal windows remain visible when they
finish, including sessions already idle when the bar starts. The plugin
identifies the foreground Codex process and uses its terminal title for the
label and activity state. It never edits Codex's configuration.

Optional: to show conversation names instead of the default project name,
or to use title detection over SSH or in a multiplexer, configure a title
with an explicit state in `~/.codex/config.toml`:

```toml
[tui]
terminal_title = ["run-state", "thread-title", "project-name"]
```

Restart existing Codex sessions only if you change this optional title setting.

## Using the widget

| State | Appearance |
|-------|------------|
| Working | Spinning arc with a dimmed mark and session name |
| Ready | Closed ring and checkmark, with a short green pulse when the run finishes |
| Attention | Breathing ring and exclamation mark in the theme's urgent color |

- Pills follow workspace order (1, 2, 3, …, 10), updating when a terminal
  moves. Sessions on the same workspace retain their compositor order.
  Named/special workspaces follow numbered ones in name order; windows with
  unavailable workspace metadata come last. This ordering applies even when
  workspace badges are hidden.
- Click a chip to focus its terminal window.
- Hover a chip to see the agent, full session name, project and state.
- Open sessions beyond `maxSessions` collapse into a `+n` chip; its tooltip
  lists the hidden sessions.
- Labels shrink and elide automatically so the widget cannot overlap the
  centered clock.
- The widget hides itself when no supported session is open and on vertical
  bars.

## Settings

Change settings from the widget settings panel, with `omarchy bar set`, or in
the widget entry inside `~/.config/omarchy/shell.json`.

| Key | Default | Description |
|-----|---------|-------------|
| `view` | `sessions` | `sessions` for pills; `detail` for a second instance on the right |
| `showWorkspaceNumber` | `false` | Workspace badge before each agent logo |
| `hideSessionNames` | `false` | Compact pills without session names; keeps badges, logos and activity indicators |
| `showActiveDetail` | `false` | Enable the focused conversation topic in the detail view |
| `highlightActive` | `false` | Accent outline and bold label for the focused session |
| `maxDetailWidth` | `480` | Maximum detail-view width in pixels (120–1000), also capped at a quarter of the screen |
| `maxWidth` | `180` | Maximum session-label width in pixels (60–480) |
| `maxSessions` | `4` | Maximum visible session chips before `+n` (1–12) |
| `doneColor` | `#4ade80` | Ring, checkmark and pulse when ready |
| `attentionColor` | theme | Ring and exclamation mark when attention is needed |
| `claudeColor` | `#d97757` | Claude mark color |
| `codexColor` | bar text | Codex mark color |
| `extraAppIds` | empty | Additional comma-separated terminal app IDs |

To change the number of pills, open the Agent Status widget settings and set
**Maximum visible pills** to a value from **1 to 12**. The default is **4**.
For example, to allow five pills on the left bar:

```bash
omarchy bar set io.github.mae240.agent-status maxSessions 5 --json --section left
```

The limit belongs to each widget instance. Extra sessions appear in the `+n`
pill. Available screen space can reduce the visible count; enable **Hide
session names (compact pills)** to fit more.

Colors accept `#RGB`, `#RRGGBB`, `#RRGGBBAA`, `rgb(r,g,b)` and theme roles
such as `accent`, `urgent` or `foreground`. Invalid colors fall back to their
defaults; numeric values are clamped to the documented ranges.

### Optional workspace context

The following features are **off by default** and can be enabled independently
in the widget settings panel:

- **Show workspace number** puts the terminal's Hyprland workspace number to
  the left of its agent logo. This is the virtual desktop number, not a physical
  monitor number. Named and special workspaces show their name; unavailable
  workspace metadata leaves the badge hidden.
- **Hide session names (compact pills)** removes only the name from each pill.
  With workspace numbers enabled, the left bar shows just the workspace, agent
  logo, activity ring and ready/attention mark. Clicking still focuses the
  terminal; hovering still shows its full name and status. Compact pills use
  their smaller widths to fit more sessions; the `maxSessions` limit still
  applies (default 4, configurable up to 12). The right-hand conversation detail
  remains available. Turn this option off to restore names.
- **Highlight the active session** adds a solid accent outline, tinted
  background and bold label to the focused terminal's pill. Its activity ring
  keeps its usual meaning. A focused session beyond the display limit replaces
  the last visible pill, so it can still be identified.
- **Show active conversation detail** enables a longer topic label in the
  **detail** view. It follows the focused agent window and disappears when a
  browser, ordinary terminal, or other non-agent window takes focus.

To keep the pills on the left and place the detail on the right, add a second
**Agent Status** instance in the bar's layout settings. Place it in the **right**
section, select **Widget view → detail**, and enable **Show active conversation
detail** on that instance. The original instance keeps **Widget view → sessions**.
Settings belong to each instance; disabling detail hides that instance rather
than replacing it with another set of pills.

The corresponding entries inside your existing `bar.layout` look like this
(keep your other widgets):

```json
{
  "left": [
    {
      "id": "io.github.mae240.agent-status",
      "showWorkspaceNumber": true,
      "highlightActive": true
    }
  ],
  "right": [
    {
      "id": "io.github.mae240.agent-status",
      "view": "detail",
      "showActiveDetail": true,
      "maxDetailWidth": 480
    }
  ]
}
```

You can also toggle a configured instance from the CLI:

```bash
omarchy bar set io.github.mae240.agent-status showWorkspaceNumber true --json --section left
omarchy bar set io.github.mae240.agent-status highlightActive true --json --section left
omarchy bar set io.github.mae240.agent-status hideSessionNames true --json --section left
omarchy bar set io.github.mae240.agent-status showActiveDetail false --json --section right
```

The detail comes directly from the agent's **conversation title**, plus the
project when Codex supplies it: for example, `storefront · Improve the checkout
flow`. It excludes run-state words such as Working or Ready, so finishing a
step does not replace the topic with the latest action. It is not an additional
AI-generated summary: a vague, stale or unnamed conversation title cannot
provide a richer feature description. Rename the conversation in the agent
when you want a more useful topic. No transcript reading, model calls, or
additional credentials are involved.

The detail is elided at `maxDetailWidth` and at a quarter of the screen width;
hover it to read the full text. Reduce the width if your right bar section is
already crowded. Both views remain hidden on vertical bars. As with the
existing session list, bar instances on different monitors follow the same
focused window.

## How detection works

Agent Status reads titles and focus from Quickshell's toplevel list. It joins
windows to Hyprland's workspace and process metadata using their Wayland
handle, never by matching titles.

One shared Python helper runs every 1.5 seconds to identify foreground Codex
processes belonging to those windows. It reads local `/proc` process ancestry,
terminal attachment and executable identity. It does not read conversations,
credentials or Codex configuration, and makes no network calls. All bar
instances share the probe; failed or stale probes clear the process fallback
while explicit agent titles continue to work.

### Claude Code

Claude Code places a state glyph and session name in its terminal title:

| Terminal title | State |
|----------------|-------|
| `◐ my-session` | Working |
| `✳ my-session` | Ready |

These glyphs are input signals only. The widget renders the Claude mark and
status ring shown in the preview instead of displaying the title glyph.

Claude Code does not expose approval prompts separately, so a session waiting
for approval can still look like it is working. Inside tmux, screen or zellij,
Claude Code uses a static ready glyph and therefore always appears ready.

### Codex

Codex's default title has a braille spinner while working and a plain project
name when idle. The process lookup keeps the idle pill visible and removes it
after Codex exits, normally within 1.5 seconds. Custom titles with an activity
spinner work too; the first title segment is the label, with remaining
segments shown as context. The plugin does not guess that an ordinary terminal
is Codex just because its title looks like a project or conversation.

With the optional configuration shown above, titles follow this pattern:

```text
<run state> | <thread title> | <project>
```

`Working` appears as working; `Ready`, `Idle` and `Done` appear as ready;
`Waiting`, `Blocked` and `Approval` appear as attention. Until Codex names a
thread, the chip is labeled `Codex`.

Codex currently reports `Working` while an approval prompt is open. Its
attention state is therefore most commonly seen while it waits for a
background terminal.

### Terminal filtering

The widget reads terminals launched by `omarchy-launch-tui`, the terminals
shipped with Omarchy (foot, Alacritty, Ghostty, kitty and WezTerm), and windows
with the app IDs `claude` or `codex`. Other applications are ignored even when
their titles resemble an agent session. Add a custom terminal app ID with the
`extraAppIds` setting.

## Limitations

- Only Claude Code and Codex are supported.
- Approval prompts are not reliably distinguishable from active work.
- Terminal multiplexers must pass pane titles through to the window title;
  Claude Code sessions inside a multiplexer always appear ready.
- Automatic idle Codex detection requires a local foreground CLI attached to
  a terminal with a unique window PID. SSH, detached multiplexers, shared
  terminal-server windows and inaccessible process metadata fall back to
  titles; an explicit `run-state` title is needed for idle detection there.
- Disabling Codex's title activity indicator prevents reliable busy/ready
  detection. A process alone proves the session is open, not that it is busy.
- The widget shows session state, not usage or rate limits. Use the built-in
  `omarchy.agents` widget for account usage.

## Remove

```bash
omarchy plugin remove io.github.mae240.agent-status
```

This disables the widget, removes its entry from
`~/.config/omarchy/shell.json` and deletes the plugin directory. The plugin
writes nothing else to the system.

## Upgrade from `mae.agent-status`

Versions before 2.1.0 used the ID `mae.agent-status`. Replace the old plugin
with the current one:

```bash
omarchy plugin remove mae.agent-status
omarchy plugin add https://github.com/mae240/omarchy-agent-status.git --enable
```

## Development

```bash
git clone https://github.com/mae240/omarchy-agent-status.git \
  ~/.config/omarchy/plugins/io.github.mae240.agent-status
omarchy plugin validate ~/.config/omarchy/plugins/io.github.mae240.agent-status
omarchy plugin enable io.github.mae240.agent-status
```

Detection lives in `sessionForWindow(window)` in `AgentStatus.qml`, combining
`sessionFor(title, appId)` with the shared `internal/CodexProcesses.qml` probe
and `scripts/codex_processes.py`. It returns either a Claude Code or Codex
session with a `busy`, `ready` or `attention` state. Supporting another agent
requires a new detection branch and a mark in `AgentMark.qml`.

After changing QML, run `omarchy restart shell`. Plugin-file hot reload is not
reliable in every shell version.

### Tests

The QML tests use synthetic windows, process snapshots, workspace metadata and
a minimal mock of the shell's widget API. Python tests exercise process
discovery against a temporary `/proc` fixture. They run without starting
Hyprland, changing your desktop, reading conversations or making network calls.
Qt 6's QML Test runner, Qt Quick Shapes and Python 3 are required.

```bash
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=basic QT_QUICK_BACKEND=software \
  /usr/lib/qt6/bin/qmltestrunner -import tests/mocks -input tests
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_*.py'
omarchy plugin validate .
```

For desktop acceptance, enable each option separately and together, switch
between two agent windows and a browser, move a terminal to another workspace,
and focus a session that would normally be in `+n`. Check the right-hand detail
on your actual bar layout and use `maxDetailWidth` to leave room for your other
widgets. Turn all optional features back off to confirm the original appearance.

## License

[MIT](LICENSE). The Claude and OpenAI marks in `AgentMark.qml` are the vendors'
own trademarks and are used only to identify their products.
