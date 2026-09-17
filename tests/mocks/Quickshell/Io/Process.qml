import QtQuick

QtObject {
  property bool running: false
  property var command: []
  property QtObject stdout: null
  signal exited(int exitCode, int exitStatus)
}
