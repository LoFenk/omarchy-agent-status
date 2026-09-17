# Changelog

## Unreleased

- Make the existing 1–12 pill limit easier to find as “Maximum visible pills” beside compact mode; keep the default at four.
- Detect local Codex sessions by foreground process identity, keeping idle pills visible without editing Codex's title settings, including after a bar restart.
- Share process discovery across widget instances and keep title-based detection for remote or unsupported terminal layouts.
- Regression coverage for spinner removal, already-idle sessions, process exit, unrelated terminals and failed/stale discovery.
- Order pills numerically by workspace, updating on moves without recreating pills or resetting activity animations.

- Optional compact pills hide session names and fit more sessions while keeping workspace badges, activity indicators, tooltips and click-to-focus.
- Optional workspace badges before each agent logo, including named workspaces.
- Optional active-session highlight, keeping the focused session out of overflow.
- Optional right-hand conversation detail through a second widget instance.
- All optional additions default to off and have settings in the widget panel.
- Render conversation titles as plain text in both views.
- Headless QML tests for focus, workspace changes, optional settings and detail visibility.

## 2.2.0

- Tooltips work: the bar only shows them for a hovered chip, not for the widget as a whole.
- The done pulse only fires for a visible working-to-done switch, not when a session first appears.
- Unreadable colors fall back to the default instead of rendering black; theme roles such as `accent` are accepted.
- `maxSessions` and `maxWidth` are clamped to their documented ranges.
- The width budget also caps the number of chips, so the bar never reaches the clock however many sessions are open.
- More terminals are recognised (`org.codeberg.dnkl.foot`, `wezterm`, `TUI.*`, `claude`, `codex`), plus an `extraAppIds` setting for custom app ids.
- A Codex chip keeps its label while the thread is still unnamed instead of switching from project to thread title.
- The attention ring returns to its resting opacity after breathing.
- Marks and rings are drawn as vectors through the curve renderer instead of a scaled 24 px texture.
- README states what is and is not detected: Claude Code and Codex only, no approval prompts, tmux caveat.
- Codex setup is shown during installation, and only known Codex run states are accepted so unrelated terminal titles cannot become false sessions.
- README includes a polished visual of the Claude Code and Codex working/ready chip states and distinguishes them from terminal-title markers.
- README is reorganized around a single top-level preview, setup, usage, settings and concise detection details.

## 2.1.0

- Published as a standalone repository for the Omarchy plugin marketplace.
- Plugin id renamed from `mae.agent-status` to `io.github.mae240.agent-status`.

## 2.0.0

- Codex sessions next to Claude Code sessions, with the vendor's mark on each chip.
- Chips are capped at `maxSessions` and share a width budget so the bar never grows over the clock.

## 1.0.0

- First version as `mae.claude-status`: one chip per open Claude Code session.
