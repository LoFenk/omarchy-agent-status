import QtQuick
import QtQuick.Shapes
import Quickshell.Wayland
import Quickshell.Hyprland
import "SessionContext.js" as Context
import "internal" as Internal
import qs.Commons
import qs.Ui

// One chip per open coding-agent session, read off the terminal title each
// agent writes. Claude Code writes "◐ <session>" while it works and
// "✳ <session>" once it is done. Codex's default spinner disappears when idle;
// a local process probe keeps those sessions identifiable without configuring
// Codex. Explicit run-state titles continue to work too.
BarWidget {
  id: root
  moduleName: "io.github.lofenk.agent-status"

  Component.onCompleted: Internal.CodexProcesses.registerConsumer(root)
  Component.onDestruction: Internal.CodexProcesses.unregisterConsumer(root)

  // Moon frames Claude cycles through while working, braille frames Codex uses
  // when its title carries no run state. Anything from the ready set means the
  // agent is done.
  readonly property string claudeBusyGlyphs: "◐◓◑◒◴◵◶◷"
  readonly property string codexBusyGlyphs: "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏⠍⠌⠓⠒⠆⠖⠶"
  readonly property string readyGlyphs: "✳✻✽✶✢❋⁕*·⏺"

  // Codex run-state words, as they land in the first title segment. Keep this
  // list explicit: accepting every leading word would turn unrelated terminal
  // titles such as "Vim | project" into false Codex sessions.
  readonly property var codexBusy: ["Working"]
  readonly property var codexReady: ["Ready", "Idle", "Done"]
  readonly property var codexAttention: ["Waiting", "Blocked", "Approval"]

  // Titles are only read from windows an agent can live in: everything
  // omarchy-launch-tui opens carries an org.omarchy.* or TUI.* app id, and a
  // hand-started session sits in one of the terminals Omarchy ships. Without
  // that, any window titled "Inbox | Mail" would look like a Codex session.
  // A custom --app-id can be added through the extraAppIds setting.
  readonly property var terminalAppIdPrefixes: ["org.omarchy.", "tui."]
  readonly property var terminalAppIds: ["foot", "footclient", "org.codeberg.dnkl.foot",
    "alacritty", "com.mitchellh.ghostty", "kitty", "wezterm", "org.wezfurlong.wezterm",
    "claude", "codex"]
  readonly property var extraAppIds: String(setting("extraAppIds", "") || "")
    .toLowerCase().split(",")
    .map(function (id) { return id.trim() })
    .filter(function (id) { return id !== "" })

  // The manifest schema documents these ranges, but the shell stores whatever
  // `omarchy bar set` is given, so they are enforced here too.
  // Settings are per instance. A second instance in the right bar section can
  // render the active conversation topic without moving or widening the pills.
  readonly property bool detailView: setting("view", "sessions") === "detail"
  readonly property bool showWorkspaceNumber: Context.enabled(setting("showWorkspaceNumber", false))
  readonly property bool showActiveDetail: Context.enabled(setting("showActiveDetail", false))
  readonly property bool highlightActive: Context.enabled(setting("highlightActive", false))
  readonly property bool hideSessionNames: Context.enabled(setting("hideSessionNames", false))
  readonly property int maxDetailWidth: intSetting("maxDetailWidth", 480, 120, 1000)
  readonly property var activeWindow: ToplevelManager.activeToplevel
  readonly property var activeSession: activeWindow
    ? sessionForWindow(activeWindow) : null
  readonly property string activeTopic: Context.topic(activeSession)
  readonly property real workspaceBadgeWidth: Style.font.caption * 3

  readonly property int minLabelWidth: 56
  readonly property int maxLabelWidth: intSetting("maxWidth", 180, 60, 480)
  readonly property int maxSessions: intSetting("maxSessions", 4, 1, 12)
  readonly property color doneColor: colorSetting("doneColor", "#4ade80")
  readonly property color attentionColor: colorSetting("attentionColor", Color.urgent)
  readonly property color claudeColor: colorSetting("claudeColor", "#d97757")
  readonly property color codexColor: colorSetting("codexColor", textColor)

  readonly property color textColor: root.bar ? root.bar.barForeground : Color.foreground
  readonly property string textFont: root.bar ? root.bar.fontFamily : Style.font.family

  readonly property var sessionWindows: {
    var list = []
    var items = ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []
    for (var i = 0; i < items.length; i++) {
      if (items[i] && sessionForWindow(items[i])) list.push(items[i])
    }
    return Context.orderWindows(list, function(window) { return root.workspaceFor(window) })
  }

  readonly property real markSize: Style.font.body
  readonly property real ringSize: Math.min(markSize * 1.9,
    Math.max(markSize + Style.space(4), root.barSize - Style.space(10)))

  // The bar anchors its center section to the middle of the screen, so a left
  // section that keeps growing ends up drawn over the clock. The chips share a
  // width budget: names are elided at an equal share of it, and once even the
  // shortest label would not fit, the remaining sessions are counted in one
  // "+n" chip instead, whatever maxSessions allows.
  readonly property real widthBudget: Math.max(240, Screen.width * 0.28)
  readonly property real chipSpacing: Style.space(4)
  readonly property real chipChrome: ringSize + Style.space(7) * 2
    + Style.space(4) * 2 + Style.font.caption
    + (showWorkspaceNumber ? workspaceBadgeWidth + Style.space(4) : 0)
  readonly property real overflowChrome: Style.font.caption * 2.4 + Style.space(7) * 2 + chipSpacing
  readonly property int budgetSessions: hideSessionNames ? compactBudgetSessions()
    : Math.max(1, Math.floor(
      (widthBudget - overflowChrome) / (chipChrome + minLabelWidth + chipSpacing)))
  readonly property int shownSessions: Math.min(sessionWindows.length, maxSessions, budgetSessions)
  readonly property var visibleSessionWindows: Context.visibleWindows(
    sessionWindows, shownSessions, activeWindow, highlightActive)
  // Keep the compositor model as the delegate owner, and only reorder their
  // positions. Replacing a Repeater array would destroy the pills and reset
  // their spinner/pulse state whenever a title or workspace changed.
  property int slotsRevision: 0
  readonly property var visibleSlots: {
    var revision = slotsRevision
    var slots = []
    for (var i = 0; i < visibleSessionWindows.length; i++) {
      for (var j = 0; j < sessionRepeater.count; j++) {
        var slot = sessionRepeater.itemAt(j)
        if (slot && slot.modelData === visibleSessionWindows[i]) {
          slots.push(slot)
          break
        }
      }
    }
    return slots
  }
  readonly property real sessionChipsWidth: {
    var width = chipSpacing * Math.max(0, visibleSlots.length - 1)
    for (var i = 0; i < visibleSlots.length; i++) width += visibleSlots[i].width
    return width
  }
  readonly property int hiddenSessions: sessionWindows.length - shownSessions
  readonly property int labelWidth: {
    if (hideSessionNames) return 0
    var budget = widthBudget
      - (hiddenSessions > 0 ? overflowChrome : 0)
      - chipSpacing * Math.max(0, shownSessions - 1)
    var share = budget / Math.max(1, shownSessions) - chipChrome
    return Math.max(minLabelWidth, Math.min(maxLabelWidth, Math.round(share)))
  }

  FontMetrics {
    id: compactMetrics
    font.family: root.textFont
    font.pixelSize: Style.font.caption
    font.bold: true
  }

  function compactChipWidth(window) {
    // Reserve the ready/attention mark even while working, so a finished
    // session cannot push its neighbours into overflow. Labels need no space.
    var statusWidth = Math.ceil(Math.max(compactMetrics.advanceWidth("✓"),
      compactMetrics.advanceWidth("!")))
    var width = ringSize + Style.space(7) * 2 + Style.space(4) + statusWidth
    var label = showWorkspaceNumber ? Context.workspaceLabel(workspaceFor(window)) : ""
    if (label !== "")
      width += Math.min(workspaceBadgeWidth, Math.ceil(compactMetrics.advanceWidth(label)))
        + Style.space(4)
    return width
  }

  function compactBudgetSessions() {
    // Try the largest allowed set first. Count the actual workspace badge
    // widths, including a focused session promoted out of overflow. A +n
    // reserve is only needed if there really are hidden sessions.
    for (var count = Math.min(maxSessions, sessionWindows.length); count > 0; count--) {
      var windows = Context.visibleWindows(sessionWindows, count, activeWindow, highlightActive)
      var used = chipSpacing * (count - 1)
        + (count < sessionWindows.length ? overflowChrome : 0)
      for (var i = 0; i < windows.length; i++) used += compactChipWidth(windows[i])
      if (used <= widthBudget) return count
    }
    return 1
  }

  function workspaceFor(window) {
    // Join by the compositor's window handle, never by a title (two terminals
    // can have the same title). Missing metadata is left blank.
    var items = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (var i = 0; i < items.length; i++) {
      if (window && items[i].wayland === window) return items[i].workspace
    }
    return null
  }

  function sessionOffset(window) {
    var offset = 0
    for (var i = 0; i < visibleSlots.length; i++) {
      if (visibleSlots[i].modelData === window) return offset
      offset += visibleSlots[i].width + chipSpacing
    }
    return 0
  }

  function intSetting(name, fallback, min, max) {
    var value = Number(setting(name, fallback))
    if (!isFinite(value)) value = fallback
    return Math.max(min, Math.min(max, Math.round(value)))
  }

  // A cleared color arrives as an empty string, which is not a color, so it
  // can only mean "keep the default". Anything else goes through the shell's
  // own parser, which understands hex, rgb() and theme roles; a value it
  // cannot read would otherwise render as opaque black.
  function colorSetting(name, fallback) {
    var value = String(setting(name, "") || "").trim()
    if (value === "") return fallback
    var parsed = Color.flatColor(value, fallback)
    if (typeof parsed === "string" && !/^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(parsed))
      return fallback
    return parsed
  }

  function isTerminal(appId) {
    var id = String(appId || "").toLowerCase()
    for (var i = 0; i < terminalAppIdPrefixes.length; i++) {
      if (id.indexOf(terminalAppIdPrefixes[i]) === 0) return true
    }
    return terminalAppIds.indexOf(id) >= 0 || extraAppIds.indexOf(id) >= 0
  }

  function isThreadId(value) {
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)
  }

  function sessionForWindow(window) {
    if (!window || !isTerminal(window.appId)) return null
    var detected = sessionFor(window.title, window.appId)
    var items = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (var i = 0; i < items.length; i++) {
      if (items[i].wayland !== window) continue
      var ipc = items[i].lastIpcObject
      if (ipc && Internal.CodexProcesses.sessions[String(ipc.pid)] === true) {
        if (detected && detected.agent === "codex") return detected
        // A live foreground Codex process establishes identity even with a
        // plain project/title, including when the bar first starts up idle.
        return codexTitle(window.title || "", "ready", "Ready")
      }
      break
    }
    return detected
  }

  function codexTitle(title, state, detail) {
    var parts = title.split(/\s+\|\s+/)
      .map(function(part) { return part.trim() })
      .filter(function(part) { return part !== "" })
    var name = parts.length > 0 && !isThreadId(parts[0]) ? parts[0] : "Codex"
    var context = parts.slice(1).filter(function(part) { return !isThreadId(part) }).join(" · ")
    return { agent: "codex", state: state, detail: detail, name: name, context: context }
  }

  function sessionFor(title, appId) {
    if (!title || !isTerminal(appId)) return null

    // Codex, configured: "<Run state> | <thread title> | <project>".
    var runState = /^([A-Z][a-z]+)\s+\|\s+(.+)$/.exec(title)
    if (runState) {
      var word = runState[1]
      if (codexBusy.indexOf(word) < 0 && codexReady.indexOf(word) < 0
          && codexAttention.indexOf(word) < 0) return null
      var state = codexReady.indexOf(word) >= 0 ? "ready"
        : codexAttention.indexOf(word) >= 0 ? "attention" : "busy"
      // Remaining segments are thread title and project, in the order
      // config.toml lists them. Codex shows the raw thread id until it has
      // named the thread; the segment keeps its position so the chip does not
      // change identity the moment the thread gets a name.
      return codexTitle(runState[2], state, word)
    }

    if (title.length < 3 || title.charAt(1) !== " ") return null
    var glyph = title.charAt(0)
    var name = title.slice(2).trim()
    if (name === "") return null
    if (claudeBusyGlyphs.indexOf(glyph) >= 0)
      return { agent: "claude", state: "busy", detail: "working…", name: name, context: "" }
    if (readyGlyphs.indexOf(glyph) >= 0)
      return { agent: "claude", state: "ready", detail: "done", name: name, context: "" }
    // Default Codex titles use a spinner while working. Idle identity comes
    // from sessionForWindow's process lookup instead of retaining stale titles.
    if (codexBusyGlyphs.indexOf(glyph) >= 0)
      return codexTitle(name, "busy", "working…")
    return null
  }

  function agentLabel(agent) {
    return agent === "codex" ? "Codex" : "Claude Code"
  }

  function hiddenSessionNames() {
    var names = []
    for (var i = 0; i < sessionWindows.length; i++) {
      if (visibleSessionWindows.indexOf(sessionWindows[i]) >= 0) continue
      var session = sessionForWindow(sessionWindows[i])
      if (session) names.push(session.name)
    }
    return names.join(" · ")
  }

  // Only visible session slots and the overflow chip contribute width.
  visible: !vertical && (detailView
    ? showActiveDetail && activeTopic !== "" : chipRow.implicitWidth > 0)
  implicitWidth: !visible ? 0 : detailView
    ? activeDetail.implicitWidth : chipRow.implicitWidth + Style.space(6) * 2
  implicitHeight: barSize

  Behavior on implicitWidth {
    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
  }

  ActiveDetail {
    id: activeDetail
    objectName: "activeDetail"
    anchors.fill: parent
    visible: root.detailView && root.showActiveDetail && root.activeTopic !== ""
    bar: root.bar
    topic: root.activeTopic
    textColor: root.textColor
    textFont: root.textFont
    maxWidth: Math.min(root.maxDetailWidth, Screen.width * 0.25)
  }

  Item {
    id: chipRow
    visible: !root.detailView
    anchors.verticalCenter: parent.verticalCenter
    x: Style.space(6)
    height: root.barSize
    implicitWidth: root.sessionChipsWidth + (root.hiddenSessions > 0
      ? overflowSlot.width + (root.visibleSlots.length > 0 ? root.chipSpacing : 0) : 0)

    Repeater {
      id: sessionRepeater
      objectName: "sessionRepeater"
      model: ToplevelManager.toplevels
      onItemAdded: root.slotsRevision++
      onItemRemoved: root.slotsRevision++

      delegate: Item {
        id: slot
        objectName: "agentSession"

        required property var modelData
        readonly property var session: root.sessionForWindow(modelData)
        readonly property bool isSession: session !== null
        // Empty while the window holds no session, so the first state a
        // session ever shows is not mistaken for a transition.
        readonly property string agentState: isSession ? session.state : ""
        readonly property bool busy: agentState === "busy"
        readonly property bool attention: agentState === "attention"
        readonly property string agent: isSession ? session.agent : "claude"
        readonly property color agentColor: agent === "codex" ? root.codexColor : root.claudeColor
        readonly property color agentStateColor: agentState === "ready" ? root.doneColor
          : attention ? root.attentionColor : agentColor
        readonly property bool active: root.highlightActive && modelData === root.activeWindow
        readonly property string workspaceLabel: root.showWorkspaceNumber
          ? Context.workspaceLabel(root.workspaceFor(modelData)) : ""
        property string previousState: ""

        visible: !root.detailView && isSession && root.visibleSessionWindows.indexOf(modelData) >= 0
        x: root.sessionOffset(modelData)
        width: chip.width
        height: root.barSize

        // The pulse marks the moment work turns into an answer, so it only
        // runs for a busy -> ready switch the user can actually see.
        onAgentStateChanged: {
          if (agentState === "ready" && previousState === "busy" && visible) donePulse.restart()
          previousState = agentState
          // The spinner stops wherever it happens to be, and the idle ring
          // would keep that tilt.
          spinner.rotation = 0
        }

        Rectangle {
          id: chip
          objectName: "sessionChip"
          anchors.verticalCenter: parent.verticalCenter
          width: chipContent.width + Style.space(7) * 2
          height: Math.min(root.barSize - Style.space(4), chipContent.height + Style.space(4) * 2)
          radius: height / 2
          color: slot.active ? Util.alpha(Color.accent, 0.22)
            : Util.alpha(slot.agentStateColor, slot.busy ? 0.06 : 0.09)
          border.width: slot.active ? 2 : 1
          border.color: slot.active ? Color.accent
            : Util.alpha(slot.agentStateColor, slot.busy ? 0.18 : 0.3)

          // The bar only shows a tooltip for a target that reports itself
          // hovered, and centers the bubble under that target.
          readonly property bool tooltipHovered: slot.visible && chipMouse.containsMouse

          Behavior on color { ColorAnimation { duration: 250 } }
          Behavior on border.color { ColorAnimation { duration: 250 } }

          // Accent flash layered on top so the base colors stay declarative.
          Rectangle {
            id: doneFlash
            anchors.fill: parent
            radius: parent.radius
            color: Util.alpha(root.doneColor, 0.35)
            opacity: 0
          }

          Row {
            id: chipContent
            anchors.centerIn: parent
            spacing: Style.space(4)

            Text {
              objectName: "workspaceLabel"
              anchors.verticalCenter: parent.verticalCenter
              visible: slot.workspaceLabel !== ""
              width: Math.min(implicitWidth, root.workspaceBadgeWidth)
              text: slot.workspaceLabel
              textFormat: Text.PlainText
              color: root.textColor
              font.family: root.textFont
              font.pixelSize: Style.font.caption
              font.bold: true
              elide: Text.ElideRight
            }

            Item {
              anchors.verticalCenter: parent.verticalCenter
              width: root.ringSize
              height: root.ringSize

              Shape {
                id: spinner
                objectName: "activityRing"
                anchors.fill: parent
                antialiasing: true
                preferredRendererType: Shape.CurveRenderer
                transformOrigin: Item.Center
                // Attention is the one state that has to catch the eye without
                // a spinner, so the ring breathes instead of turning. The
                // breath lives in its own property, so leaving the state puts
                // the opacity back where the binding says.
                property real breath: 1.0
                opacity: slot.attention ? breath : (slot.busy ? 1.0 : 0.55)

                Behavior on opacity {
                  enabled: !slot.attention
                  NumberAnimation { duration: 250 }
                }

                ShapePath {
                  strokeColor: slot.agentStateColor
                  strokeWidth: Math.max(1, Math.round(root.ringSize / 12))
                  fillColor: "transparent"
                  capStyle: ShapePath.RoundCap

                  PathAngleArc {
                    centerX: root.ringSize / 2
                    centerY: root.ringSize / 2
                    radiusX: (root.ringSize - Math.max(1, Math.round(root.ringSize / 12))) / 2
                    radiusY: radiusX
                    startAngle: -90
                    sweepAngle: slot.busy ? 100 : 360

                    Behavior on sweepAngle {
                      NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                    }
                  }
                }

                NumberAnimation on rotation {
                  running: slot.busy && slot.visible
                  from: 0
                  to: 360
                  duration: 1100
                  loops: Animation.Infinite
                }

                SequentialAnimation on breath {
                  running: slot.attention && slot.visible
                  loops: Animation.Infinite
                  NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutQuad }
                  NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutQuad }
                }
              }

              AgentMark {
                anchors.centerIn: parent
                agent: slot.agent
                // The sunburst reads smaller than the solid OpenAI knot at the
                // same box size, so it gets a touch more room.
                iconSize: root.markSize * (slot.agent === "codex" ? 0.92 : 1.06)
                color: slot.agentColor
                opacity: slot.busy ? 0.8 : 1.0

                Behavior on opacity { NumberAnimation { duration: 250 } }
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, root.labelWidth)
              objectName: "sessionName"
              visible: !root.hideSessionNames
              text: slot.isSession ? slot.session.name : ""
              textFormat: Text.PlainText
              color: root.textColor
              font.family: root.textFont
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              font.bold: slot.active
              opacity: slot.busy && !slot.active ? 0.7 : 1.0

              Behavior on opacity { NumberAnimation { duration: 250 } }
            }

            Text {
              objectName: "stateMark"
              anchors.verticalCenter: parent.verticalCenter
              visible: !slot.busy
              text: slot.attention ? "!" : "✓"
              color: slot.agentStateColor
              font.family: root.textFont
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          SequentialAnimation {
            id: donePulse
            loops: 2

            ParallelAnimation {
              NumberAnimation {
                target: chip
                property: "scale"
                from: 1.0
                to: 1.08
                duration: 140
                easing.type: Easing.OutQuad
              }
              NumberAnimation {
                target: doneFlash
                property: "opacity"
                from: 0
                to: 1
                duration: 140
              }
            }
            ParallelAnimation {
              NumberAnimation {
                target: chip
                property: "scale"
                to: 1.0
                duration: 260
                easing.type: Easing.InOutQuad
              }
              NumberAnimation {
                target: doneFlash
                property: "opacity"
                to: 0
                duration: 260
              }
            }
          }

          MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (slot.modelData) slot.modelData.activate()
            onEntered: if (root.bar && slot.isSession) root.bar.showTooltip(chip,
              root.agentLabel(slot.agent)
                + " · " + slot.session.name
                + (slot.session.context ? " · " + slot.session.context : "")
                + (slot.workspaceLabel ? " · Workspace " + slot.workspaceLabel : "")
                + " · " + slot.session.detail)
            onExited: if (root.bar) root.bar.hideTooltip(chip)
          }
        }
      }
    }

    // Everything past the cap, so a burst of sessions cannot push the left
    // section of the bar over the clock.
    Item {
      id: overflowSlot
      objectName: "overflowSlot"
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.detailView && root.hiddenSessions > 0
      x: root.sessionChipsWidth + (root.visibleSlots.length > 0 ? root.chipSpacing : 0)
      width: overflowChip.width
      height: root.barSize

      Rectangle {
        id: overflowChip
        anchors.verticalCenter: parent.verticalCenter
        width: overflowLabel.implicitWidth + Style.space(7) * 2
        height: Math.min(root.barSize - Style.space(4),
          overflowLabel.implicitHeight + Style.space(4) * 2)
        radius: height / 2
        color: Util.alpha(root.textColor, 0.06)
        border.width: 1
        border.color: Util.alpha(root.textColor, 0.18)

        readonly property bool tooltipHovered: visible && overflowMouse.containsMouse

        Text {
          id: overflowLabel
          anchors.centerIn: parent
          text: "+" + root.hiddenSessions
          color: root.textColor
          font.family: root.textFont
          font.pixelSize: Style.font.caption
          opacity: 0.7
        }

        MouseArea {
          id: overflowMouse
          anchors.fill: parent
          hoverEnabled: true
          onEntered: if (root.bar) root.bar.showTooltip(overflowChip, root.hiddenSessionNames())
          onExited: if (root.bar) root.bar.hideTooltip(overflowChip)
        }
      }
    }
  }
}
