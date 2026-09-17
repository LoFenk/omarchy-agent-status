pragma Singleton
import QtQuick
import Quickshell.Hyprland
import Quickshell.Io

// One probe shared by every widget instance and monitor. Window titles remain
// the state signal; process identity lets an unmarked idle title stay visible.
QtObject {
  id: root
  property var sessions: ({})
  property double lastSuccess: 0
  property string pendingRequest: ""
  property var consumers: []

  function registerConsumer(consumer) {
    if (consumers.indexOf(consumer) < 0) consumers = consumers.concat([consumer])
  }

  function unregisterConsumer(consumer) {
    consumers = consumers.filter(function(item) { return item !== consumer })
  }

  readonly property string request: {
    var counts = {}
    var terminals = {}
    var items = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (var i = 0; i < items.length; i++) {
      var ipc = items[i].lastIpcObject
      var pid = ipc ? Number(ipc.pid) : 0
      if (!(pid > 0 && Math.floor(pid) === pid)) continue
      counts[pid] = (counts[pid] || 0) + 1
      var window = items[i].wayland
      for (var j = 0; window && j < consumers.length; j++) {
        if (consumers[j].isTerminal(window.appId)) terminals[pid] = true
      }
    }
    // Shared terminal servers may own several windows. A PID alone cannot
    // identify their active pane, so leave those windows to title detection.
    return JSON.stringify(Object.keys(counts).filter(function(pid) {
      return counts[pid] === 1 && terminals[pid] === true
    }).map(Number).sort(function(a, b) { return a - b }))
  }

  function refresh() {
    if (request === "[]" || Date.now() - lastSuccess > 5000) sessions = ({})
    if (request === "[]" || probe.running) return
    pendingRequest = request
    probe.command = ["python3", decodeURIComponent(Qt.resolvedUrl(
      "../scripts/codex_processes.py").toString().replace(/^file:\/\//, "")), request]
    probe.running = true
  }

  function acceptOutput(text) {
    if (pendingRequest !== request) return
    try {
      var result = JSON.parse(text)
      if (!result || typeof result !== "object" || Array.isArray(result)) throw new Error("Invalid process snapshot")
      sessions = result
      lastSuccess = Date.now()
    } catch (error) {
      sessions = ({})
    }
  }

  onRequestChanged: {
    sessions = ({})
    Qt.callLater(refresh)
  }

  property Timer poll: Timer {
    interval: 1500
    repeat: true
    running: root.request !== "[]"
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  property Process probe: Process {
    stdout: StdioCollector {
      onStreamFinished: root.acceptOutput(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.sessions = ({})
      if (root.pendingRequest !== root.request) Qt.callLater(root.refresh)
    }
  }
}
