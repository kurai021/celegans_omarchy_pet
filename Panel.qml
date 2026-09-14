import QtQuick
import qs.Ui
import "panels" as Panels

Panel {
  id: root
  moduleName: "io.github.kurai021.celegans-pet"
  ipcTarget: "io.github.kurai021.celegans-pet"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  property string petNameSetting: root.setting("petName", "")
  onPetNameSettingChanged: {
    if (petState) petState.petName = root.petNameSetting || "Wormy"
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  // Pause the connectome while the panel is closed so the simulation only
  // spends CPU when the pet is actually on screen.
  Panels.BrainConnector {
    id: brainController
    simulationActive: root.opened
  }

  // Persisted pet memory (energy, sleep, name, stats).
  Panels.PetState {
    id: petState
    Component.onCompleted: petState.petName = root.petNameSetting || "Wormy"
  }

  KeyboardPanel {
    id: panel
    bar: root.bar
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(640)
    contentHeight: panel.fittedContentHeight(480)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Rectangle {
        id: aquarium
        anchors.fill: parent
        color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)

        // World first so the pet renders on top (and wins the click when the
        // cursor is over it; anywhere else drops food).
        Panels.World {
          id: world
          anchors.fill: parent
          autoFeedEnabled: petState.energy < 55
        }

        Panels.Pet {
          width: 60
          height: 90
          x: (parent.width - width) / 2
          y: (parent.height - height) / 2
          brainController: brainController
          world: world
          petState: petState
        }

        // Tiny HUD: name + energy bar
        Column {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 6
          spacing: 3

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: petState.petName
            color: Qt.rgba(0.7, 1, 0.95, 1)
            font.pixelSize: 10
            font.bold: true
          }

          Rectangle {
            width: 80
            height: 5
            radius: 2.5
            color: Qt.rgba(1, 1, 1, 0.12)

            Rectangle {
              width: parent.width * Math.max(0, Math.min(1, petState.energy / 100))
              height: parent.height
              radius: 2.5
              color: petState.energy > 50 ? "#4dff88"
                    : petState.energy > 20 ? "#ffbf5e"
                    : "#ff4d5e"
            }
          }
        }
      }
    }
  }
}