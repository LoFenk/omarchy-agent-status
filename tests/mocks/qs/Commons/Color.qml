pragma Singleton
import QtQuick

QtObject {
  readonly property color foreground: "#e2e8f0"
  readonly property color accent: "#60a5fa"
  readonly property color urgent: "#fb923c"
  function flatColor(value, fallback) { return value || fallback }
}
