pragma Singleton
import QtQuick

QtObject {
  readonly property var font: ({ body: 12, caption: 10, family: "DejaVu Sans Mono" })
  readonly property var bar: ({ sizeHorizontal: 30 })
  function space(value) { return value }
}
