import QtQuick

Item {
  property QtObject bar: null
  property string moduleName: ""
  property var settings: ({})
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : 30
  function setting(key, fallback) {
    var value = settings[key]
    return value === undefined || value === null ? fallback : value
  }
}
