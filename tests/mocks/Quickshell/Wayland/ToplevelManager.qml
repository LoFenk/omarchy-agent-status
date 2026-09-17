pragma Singleton
import QtQuick
import QtQml.Models

QtObject {
  property var activeToplevel: null
  property QtObject toplevels: ListModel {
    dynamicRoles: true
    property var values: []
    onValuesChanged: {
      clear()
      for (var i = 0; i < values.length; i++) append({ modelData: values[i] })
    }
  }
}
