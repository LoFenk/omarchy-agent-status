import QtQuick
import QtTest
import Quickshell.Wayland
import Quickshell.Hyprland
import ".." as Plugin

TestCase {
  id: testCase
  name: "AgentStatus"
  width: 1280
  height: 100
  visible: true
  when: windowShown

  property var widget: null
  property var windows: []

  QtObject {
    id: fakeBar
    property bool vertical: false
    property int barSize: 30
    property color barForeground: "#e2e8f0"
    property string fontFamily: "DejaVu Sans Mono"
    property string tooltip: ""
    function showTooltip(target, text) { tooltip = text }
    function hideTooltip(target) { tooltip = "" }
  }

  Component {
    id: windowComponent
    QtObject {
      property string title: "Ready | Improve the checkout flow | storefront"
      property string appId: "foot"
      property bool activated: false
      function activate() { ToplevelManager.activeToplevel = this }
    }
  }
  Component {
    id: workspaceComponent
    QtObject { property int id: 1; property string name: "1" }
  }
  Component {
    id: hyprlandComponent
    QtObject { property var wayland: null; property var workspace: null }
  }
  Component {
    id: widgetComponent
    Plugin.AgentStatus {
      bar: fakeBar
      width: implicitWidth
      height: implicitHeight
    }
  }

  function createWindow(title, workspaceId, workspaceName) {
    var window = createTemporaryObject(windowComponent, testCase, { title: title })
    var workspace = createTemporaryObject(workspaceComponent, testCase,
      { id: workspaceId, name: workspaceName || String(workspaceId) })
    var hyprland = createTemporaryObject(hyprlandComponent, testCase,
      { wayland: window, workspace: workspace })
    windows.push(window)
    ToplevelManager.toplevels.values = windows.slice()
    Hyprland.toplevels.values = Hyprland.toplevels.values.concat([hyprland])
    return window
  }

  function init() {
    windows = []
    fakeBar.vertical = false
    fakeBar.tooltip = ""
    ToplevelManager.activeToplevel = null
    ToplevelManager.toplevels.values = []
    Hyprland.toplevels.values = []
    widget = createTemporaryObject(widgetComponent, testCase)
    verify(widget !== null)
  }

  function cleanup() {
    ToplevelManager.activeToplevel = null
    ToplevelManager.toplevels.values = []
    Hyprland.toplevels.values = []
  }

  function slotFor(window) {
    var repeater = findChild(widget, "sessionRepeater")
    for (var i = 0; i < repeater.count; i++) {
      var slot = repeater.itemAt(i)
      if (slot && slot.modelData === window) return slot
    }
    return null
  }

  function compareWindowOrder(expected) {
    compare(widget.sessionWindows.length, expected.length)
    for (var i = 0; i < expected.length; i++) compare(widget.sessionWindows[i], expected[i])
    for (var j = 1; j < widget.visibleSlots.length; j++) {
      var left = widget.visibleSlots[j - 1]
      var right = widget.visibleSlots[j]
      verify(left.x + left.width <= right.x, "Rendered pills follow the same order without overlap")
    }
  }

  function test_workspace_order_is_numeric_data() {
    return [{ tag: "badges shown", badges: true }, { tag: "badges hidden", badges: false }]
  }

  function test_workspace_order_is_numeric(data) {
    var ten = createWindow("Ready | Ten | repo", 10)
    var two = createWindow("Ready | Two | repo", 2)
    var one = createWindow("Ready | One | repo", 1)
    widget.settings = { hideSessionNames: true, showWorkspaceNumber: data.badges }
    tryCompare(widget, "shownSessions", 3)
    compareWindowOrder([one, two, ten])
    wait(200)
    mouseClick(findChild(slotFor(one), "sessionChip"))
    compare(ToplevelManager.activeToplevel, one)
  }

  function test_workspace_move_reorders_existing_pills() {
    var one = createWindow("Working | One | repo", 1)
    var two = createWindow("Ready | Two | repo", 2)
    var three = createWindow("Ready | Three | repo", 3)
    widget.settings = { hideSessionNames: true, showWorkspaceNumber: true }
    var original = slotFor(one)
    compareWindowOrder([one, two, three])
    Hyprland.toplevels.values[0].workspace.id = 4
    compareWindowOrder([two, three, one])
    compare(slotFor(one), original)
    compare(original.previousState, "busy")
    compare(findChild(original, "workspaceLabel").text, "4")
    one.title = "Ready | One | repo"
    compare(slotFor(one), original)
    compare(original.previousState, "ready")
    compareWindowOrder([two, three, one])
  }

  function test_same_workspace_order_survives_title_and_focus_changes() {
    var first = createWindow("Ready | Zulu | repo", 2)
    var second = createWindow("Ready | Alpha | repo", 2)
    var earlier = createWindow("Ready | Earlier | repo", 1)
    widget.settings = { hideSessionNames: true, highlightActive: true }
    compareWindowOrder([earlier, first, second])
    ToplevelManager.activeToplevel = second
    first.title = "Working | A renamed conversation | repo"
    compareWindowOrder([earlier, first, second])
  }

  function test_named_and_missing_workspaces_follow_numbered_ones() {
    var missing = createWindow("Ready | Missing | repo", 10)
    var review = createWindow("Ready | Review | repo", -99, "special:review")
    var alpha = createWindow("Ready | Alpha | repo", -98, "alpha")
    var two = createWindow("Ready | Two | repo", 2)
    widget.settings = { hideSessionNames: true, showWorkspaceNumber: true }
    var mapping = Hyprland.toplevels.values[0]
    mapping.wayland = null
    compareWindowOrder([two, alpha, review, missing])
    mapping.wayland = missing
    compareWindowOrder([two, missing, alpha, review])
  }

  function test_workspace_order_with_active_overflow_session() {
    var nine = createWindow("Ready | Nine | repo", 9)
    var one = createWindow("Ready | One | repo", 1)
    var seven = createWindow("Ready | Seven | repo", 7)
    var two = createWindow("Ready | Two | repo", 2)
    widget.settings = { hideSessionNames: true, showWorkspaceNumber: true,
      highlightActive: true, maxSessions: 2 }
    ToplevelManager.activeToplevel = nine
    compareWindowOrder([one, two, seven, nine])
    compare(widget.visibleSessionWindows[0], one)
    compare(widget.visibleSessionWindows[1], nine)
    compare(widget.hiddenSessionNames(), "Two · Seven")
    var last = slotFor(nine)
    verify(findChild(widget, "overflowSlot").x >= last.x + last.width)
    ToplevelManager.activeToplevel = two
    compareWindowOrder([one, two, seven, nine])
    compare(widget.visibleSessionWindows[1], two)
  }

  function test_defaults_off() {
    var window = createWindow("Ready | Checkout | storefront", 3)
    ToplevelManager.activeToplevel = window
    compare(widget.showWorkspaceNumber, false)
    compare(widget.showActiveDetail, false)
    compare(widget.highlightActive, false)
    compare(widget.hideSessionNames, false)
    tryCompare(widget, "visible", true)
    compare(findChild(widget, "workspaceLabel").visible, false)
    compare(findChild(widget, "sessionChip").border.width, 1)
    compare(findChild(widget, "activeDetail").visible, false)
    compare(findChild(widget, "sessionName").visible, true)
  }

  function test_workspace_moves_and_named_workspaces() {
    createWindow("Ready | Checkout | storefront", 3)
    widget.settings = { showWorkspaceNumber: true }
    var badge = findChild(widget, "workspaceLabel")
    tryCompare(badge, "text", "3")
    var workspace = Hyprland.toplevels.values[0].workspace
    workspace.id = 12
    tryCompare(badge, "text", "12")
    workspace.id = -99
    workspace.name = "special:review"
    tryCompare(badge, "text", "review")
    verify(badge.width <= widget.workspaceBadgeWidth)
    verify(badge.x < findChild(widget, "sessionName").x)
  }

  function test_missing_metadata_never_guesses_workspace() {
    createWindow("Ready | Same title | repo", 3)
    widget.settings = { showWorkspaceNumber: true }
    var unrelated = createTemporaryObject(windowComponent, testCase, { title: windows[0].title })
    Hyprland.toplevels.values[0].wayland = unrelated
    var badge = findChild(widget, "workspaceLabel")
    tryCompare(badge, "text", "")
    compare(badge.visible, false)
  }

  function test_focus_tracks_window_identity() {
    var first = createWindow("Ready | Same title | repo", 1)
    var second = createWindow("Ready | Same title | repo", 2)
    widget.settings = { highlightActive: true }
    ToplevelManager.activeToplevel = first
    var chip = findChild(widget, "sessionChip")
    tryCompare(chip.border, "width", 2)
    compare(findChild(widget, "sessionName").font.bold, true)
    ToplevelManager.activeToplevel = second
    tryCompare(chip.border, "width", 1)
    compare(findChild(widget, "sessionName").font.bold, false)
    ToplevelManager.activeToplevel = null
    compare(widget.activeSession, null)
  }

  function test_active_session_is_not_lost_in_overflow() {
    createWindow("Ready | First | repo", 1)
    createWindow("Ready | Second | repo", 2)
    var last = createWindow("Ready | Third | repo", 3)
    widget.settings = { highlightActive: true, maxSessions: 1 }
    ToplevelManager.activeToplevel = last
    tryCompare(widget, "shownSessions", 1)
    compare(widget.visibleSessionWindows[0], last)
    compare(widget.hiddenSessions, 2)
    compare(widget.hiddenSessionNames(), "First · Second")
    widget.settings = { highlightActive: false, maxSessions: 1 }
    compare(widget.visibleSessionWindows[0], windows[0])
  }

  function test_detail_follows_active_agent_and_stable_topic() {
    var codex = createWindow("Working | Improve the checkout flow | storefront", 3)
    var claude = createWindow("◐ Build a calendar integration", 4)
    widget.settings = { view: "detail", showActiveDetail: true }
    ToplevelManager.activeToplevel = codex
    tryCompare(widget, "visible", true)
    compare(widget.activeTopic, "storefront · Improve the checkout flow")
    codex.title = "Ready | Improve the checkout flow | storefront"
    compare(widget.activeTopic, "storefront · Improve the checkout flow")
    ToplevelManager.activeToplevel = claude
    compare(widget.activeTopic, "Build a calendar integration")
    verify(widget.implicitWidth <= widget.maxDetailWidth)
    claude.appId = "browser"
    tryCompare(widget, "visible", false)
    compare(widget.implicitWidth, 0)
    ToplevelManager.activeToplevel = null
    compare(widget.activeTopic, "")
  }

  function test_detail_disabled_stays_empty() {
    ToplevelManager.activeToplevel = createWindow("Ready | Checkout | repo", 3)
    widget.settings = { view: "detail" }
    compare(widget.visible, false)
    compare(widget.implicitWidth, 0)
    widget.settings = { view: "detail", showActiveDetail: true }
    tryCompare(widget, "visible", true)
    widget.settings = { view: "detail", showActiveDetail: false }
    tryCompare(widget, "visible", false)
  }

  function test_separate_instances_have_independent_settings() {
    ToplevelManager.activeToplevel = createWindow("Ready | Checkout | repo", 3)
    widget.settings = { showWorkspaceNumber: true }
    var detail = createTemporaryObject(widgetComponent, testCase,
      { settings: { view: "detail", showActiveDetail: true } })
    tryCompare(detail, "visible", true)
    compare(widget.detailView, false)
    compare(detail.showWorkspaceNumber, false)
    compare(findChild(widget, "workspaceLabel").text, "3")
    detail.settings = { view: "detail", showActiveDetail: false }
    compare(detail.visible, false)
    tryCompare(widget, "visible", true)
  }

  function test_string_false_does_not_enable_features() {
    ToplevelManager.activeToplevel = createWindow("Ready | Checkout | repo", 3)
    widget.settings = { showWorkspaceNumber: "false", highlightActive: "false", showActiveDetail: "false", hideSessionNames: "false" }
    compare(widget.showWorkspaceNumber, false)
    compare(widget.highlightActive, false)
    compare(widget.showActiveDetail, false)
    compare(widget.hideSessionNames, false)
    widget.settings = { showWorkspaceNumber: "true", highlightActive: "true", hideSessionNames: "true" }
    compare(widget.showWorkspaceNumber, true)
    compare(widget.highlightActive, true)
    compare(widget.hideSessionNames, true)
  }

  function test_compact_keeps_activity_tooltip_and_click_to_focus() {
    var window = createWindow("Working | Checkout | storefront", 3)
    widget.settings = { hideSessionNames: true, showWorkspaceNumber: true, highlightActive: true }
    tryCompare(widget, "visible", true)
    var name = findChild(widget, "sessionName")
    var badge = findChild(widget, "workspaceLabel")
    var mark = findChild(widget, "stateMark")
    var ring = findChild(widget, "activityRing")
    var chip = findChild(widget, "sessionChip")
    compare(name.visible, false)
    compare(name.width, 0)
    compare(badge.visible, true)
    compare(badge.text, "3")
    compare(mark.visible, false)
    var rotation = ring.rotation
    wait(120)
    verify(ring.rotation !== rotation, "The activity ring still spins in compact mode")
    mouseMove(widget, widget.width + 20, 80)
    mouseMove(chip, chip.width / 2, chip.height / 2)
    tryVerify(function() { return fakeBar.tooltip.indexOf("Checkout") >= 0 })
    mouseClick(chip, chip.width / 2, chip.height / 2)
    compare(ToplevelManager.activeToplevel, window)
    compare(chip.border.width, 2)
    window.title = "Ready | Checkout | storefront"
    tryCompare(mark, "visible", true)
    compare(mark.text, "✓")
    window.title = "Waiting | Checkout | storefront"
    compare(mark.text, "!")
    widget.settings = { hideSessionNames: false, showWorkspaceNumber: true }
    compare(name.visible, true)
    verify(name.width > 0)
  }

  function test_compact_fits_four_numbered_sessions_in_small_budget() {
    for (var i = 1; i <= 4; i++) createWindow("Ready | Session " + i + " | repo", i)
    widget.settings = { showWorkspaceNumber: true }
    var withNames = widget.shownSessions
    widget.settings = { showWorkspaceNumber: true, hideSessionNames: true }
    compare(widget.shownSessions, 4)
    verify(widget.shownSessions >= withNames)
    compare(widget.hiddenSessions, 0)
    wait(200)
    verify(widget.implicitWidth <= widget.widthBudget + 12)
    widget.settings = { showWorkspaceNumber: true, hideSessionNames: true, maxSessions: 2 }
    compare(widget.shownSessions, 2)
    compare(widget.hiddenSessions, 2)
  }

  function test_compact_overflow_accounts_for_active_named_workspace() {
    for (var i = 1; i <= 11; i++) createWindow("Ready | Session " + i + " | repo", i)
    var active = createWindow("Ready | Named session | repo", -99, "special:long-name")
    ToplevelManager.activeToplevel = active
    widget.settings = { showWorkspaceNumber: true, hideSessionNames: true,
      highlightActive: true, maxSessions: 12 }
    verify(widget.visibleSessionWindows.indexOf(active) >= 0)
    wait(200)
    verify(widget.implicitWidth <= widget.widthBudget + 12)
    var count = widget.shownSessions
    active.title = "Working | Named session | repo"
    compare(widget.shownSessions, count)
    active.title = "Ready | Named session | repo"
    compare(widget.shownSessions, count)
  }

  function test_compact_does_not_hide_detail_or_require_workspace_badges() {
    var active = createWindow("Ready | Checkout | storefront", 3)
    ToplevelManager.activeToplevel = active
    widget.settings = { hideSessionNames: true }
    tryCompare(widget, "visible", true)
    compare(findChild(widget, "workspaceLabel").visible, false)
    compare(findChild(widget, "sessionName").visible, false)
    compare(findChild(widget, "activityRing").visible, true)
    widget.settings = { view: "detail", showActiveDetail: true, hideSessionNames: true }
    tryCompare(findChild(widget, "activeTopic"), "visible", true)
    compare(widget.activeTopic, "storefront · Checkout")
  }

  function test_titles_are_plain_text() {
    var title = '<img src="https://invalid.example/tracker">'
    ToplevelManager.activeToplevel = createWindow("Ready | " + title + " | repo", 3)
    compare(findChild(widget, "sessionName").textFormat, Text.PlainText)
    compare(findChild(widget, "sessionName").text, title)
    widget.settings = { view: "detail", showActiveDetail: true }
    compare(findChild(widget, "activeTopic").textFormat, Text.PlainText)
    compare(findChild(widget, "activeTopic").text, "repo · " + title)
  }

  function test_vertical_bar_hides_both_views() {
    ToplevelManager.activeToplevel = createWindow("Ready | Checkout | repo", 3)
    fakeBar.vertical = true
    compare(widget.visible, false)
    widget.settings = { view: "detail", showActiveDetail: true }
    compare(widget.visible, false)
    compare(widget.implicitWidth, 0)
  }

  function test_long_workspace_label_fits_chip_budget() {
    createWindow("Ready | A much longer conversation title | repo", -99, "A very long workspace name")
    widget.settings = { showWorkspaceNumber: true }
    var badge = findChild(widget, "workspaceLabel")
    verify(badge.width <= widget.workspaceBadgeWidth)
    wait(200)
    verify(widget.implicitWidth <= widget.widthBudget + 12)
  }
}
