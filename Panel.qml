import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "panels" as Panels

Panel {
  id: root
  moduleName: "io.github.kurai021.celegans-pet"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  function open() { 
    console.log("Panel: open() called");
    root.controller.show() 
  }
  function close() { 
    console.log("Panel: close() called");
    root.controller.hide() 
  }
  function toggle() { 
    console.log("Panel: toggle() called. Opened state:", root.opened);
    if (root.opened) close(); else open() 
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  Panels.BrainConnector {
    id: brainController
  }

    KeyboardPanel {
      id: panel
      bar: root.bar
      anchorItem: root.anchorItem
      owner: root.hostWidget || root
      open: root.opened
      focusTarget: keyCatcher
      contentWidth: 640
      contentHeight: 480

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Rectangle {
        anchors.fill: parent
        color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)

        Panels.Pet {
          width: 60
          height: 90
          x: (parent.width - width) / 2
          y: (parent.height - height) / 2
          brainController: brainController
        }
      }
    }
  }
}
