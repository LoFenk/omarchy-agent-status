.pragma library

// CLI settings may arrive as strings. In particular, "false" must stay off.
function enabled(value) {
  return value === true || value === "true"
}

function workspaceLabel(workspace) {
  if (!workspace) return ""
  if (workspace.id > 0) return String(workspace.id)
  // Hyprland assigns negative internal IDs to named/special workspaces.
  return String(workspace.name || "").replace(/^special:/, "").trim()
}

function orderWindows(windows, workspaceFor) {
  var entries = []
  for (var i = 0; i < windows.length; i++) {
    var workspace = workspaceFor(windows[i])
    entries.push({ window: windows[i], index: i,
      group: !workspace ? 2 : workspace.id > 0 ? 0 : 1,
      number: workspace && workspace.id > 0 ? workspace.id : 0,
      name: workspaceLabel(workspace).toLowerCase() })
  }
  entries.sort(function(a, b) {
    if (a.group !== b.group) return a.group - b.group
    if (a.number !== b.number) return a.number - b.number
    if (a.group === 1 && a.name !== b.name) return a.name < b.name ? -1 : 1
    // Keep the compositor's existing order within each workspace. Titles,
    // agent state and focus must not reshuffle neighbours.
    return a.index - b.index
  })
  return entries.map(function(entry) { return entry.window })
}

function visibleWindows(windows, count, activeWindow, highlightActive) {
  var visible = windows.slice(0, count)
  if (highlightActive && count > 0 && windows.indexOf(activeWindow) >= count)
    visible[count - 1] = activeWindow
  return visible
}

function topic(session) {
  if (!session) return ""
  // The agent-provided conversation title describes the topic. Run-state
  // words and transient action text deliberately do not participate.
  return (session.context ? session.context + " · " : "") + session.name
}
