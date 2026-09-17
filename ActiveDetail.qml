import QtQuick
import qs.Commons

// A separate bar instance lets the host reserve real space in its right
// section rather than positioning an overlay over other bar widgets.
Item {
  id: root

  property QtObject bar: null
  property string topic: ""
  property color textColor: Color.foreground
  property string textFont: Style.font.family
  property real maxWidth: 480

  readonly property bool tooltipHovered: hover.containsMouse
  implicitWidth: Math.max(0, Math.min(maxWidth, label.implicitWidth + Style.space(8) * 2))
  implicitHeight: bar ? bar.barSize : Style.bar.sizeHorizontal
  clip: true

  Text {
    id: label
    objectName: "activeTopic"
    anchors.verticalCenter: parent.verticalCenter
    x: Style.space(8)
    width: Math.max(0, root.width - Style.space(8) * 2)
    text: root.topic
    textFormat: Text.PlainText
    color: root.textColor
    font.family: root.textFont
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
  }

  MouseArea {
    id: hover
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
    onEntered: if (root.bar) root.bar.showTooltip(root, root.topic)
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  onTopicChanged: {
    if (bar && tooltipHovered) {
      if (topic) bar.showTooltip(root, topic)
      else bar.hideTooltip(root)
    }
  }
  onVisibleChanged: if (!visible && bar) bar.hideTooltip(root)
}
