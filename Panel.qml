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
  property var pluginRegistry: null // injected; lets a UI rename sync shell.json

  // pet.json is the single source of truth for the name. The CLI setting only
  // seeds a name while the pet has never been named (everNamed); once named it
  // can never overwrite pet.json, regardless of event order.
  property string petNameSetting: root.setting("petName", "")
  onPetNameSettingChanged: root.seedSetting()
  Component.onCompleted: root.seedSetting()
  onOpenedChanged: if (!root.opened) root.mindOpen = false

  function seedSetting() {
    if (petState) petState.seedName(String(root.petNameSetting || ""))
  }

  // Best-effort: keep shell.json in sync after a UI rename so the two never
  // drift apart. pet.json wins either way if they disagree.
  function syncNameToSetting(name) {
    if (root.pluginRegistry && typeof root.pluginRegistry.setBarWidget === "function")
      root.pluginRegistry.setBarWidget(root.moduleName, "petName", String(name), {})
  }

  // Human relative time for the Mind overlay's recent-events list.
  function relativeTime(t) {
    if (t <= 0) return "long ago"
    var s = Math.floor((Date.now() - t) / 1000)
    if (s < 10) return "just now"
    if (s < 60) return s + "s ago"
    var m = Math.floor(s / 60)
    if (m < 60) return m + "m ago"
    var h = Math.floor(m / 60)
    if (h < 24) return h + "h ago"
    return Math.floor(h / 24) + "d ago"
  }

  readonly property bool needsOnboarding: root.opened
      && petState && !petState.everNamed && !root.petNameSetting

  property bool renameActive: false
  property bool mindOpen: false

  function commitRename() {
    var name = renameField.text
    var applied = petState ? petState.setName(name) : ""
    if (applied && applied !== String(root.petNameSetting)) root.syncNameToSetting(applied)
    root.renameActive = false
  }

  function commitOnboarding() {
    var applied = petState.setName(onboardField.text)
    if (applied) root.syncNameToSetting(applied)
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

  Panels.PetState {
    id: petState
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
          id: pet
          width: 60
          height: 90
          x: (parent.width - width) / 2
          y: (parent.height - height) / 2
          brainController: brainController
          world: world
          petState: petState
        }

        // Tiny HUD: name (+ inline rename), state chip, energy bar
        Column {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 6
          spacing: 4

          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4

            Text {
              id: nameText
              visible: !root.renameActive
              height: 16
              verticalAlignment: Text.AlignVCenter
              text: petState.petName
              color: Qt.rgba(0.7, 1, 0.95, 1)
              font.pixelSize: 10
              font.bold: true
            }

            TextInput {
              id: renameField
              visible: root.renameActive
              width: 90
              height: 16
              verticalAlignment: TextInput.AlignVCenter
              text: petState.petName
              color: Qt.rgba(0.7, 1, 0.95, 1)
              font.pixelSize: 10
              font.bold: true
              selectByMouse: true
              onAccepted: root.commitRename()
              onActiveFocusChanged: if (!activeFocus && root.renameActive) root.renameActive = false
              Keys.onEscapePressed: root.renameActive = false
            }

            Text {
              id: pencil
              visible: !root.renameActive
              height: 16
              verticalAlignment: Text.AlignVCenter
              text: "✏️"
              font.pixelSize: 9
              MouseArea {
                anchors.fill: parent
                onClicked: {
                  root.renameActive = true
                  renameField.forceActiveFocus()
                  Qt.callLater(function() { renameField.selectAll() })
                }
              }
            }

            // Mind overlay toggle: reads "what is it doing / why" — read-only.
            Text {
              id: mindBtn
              visible: !root.renameActive
              height: 16
              verticalAlignment: Text.AlignVCenter
              text: "🧠"
              opacity: root.mindOpen ? 1.0 : 0.55
              font.pixelSize: 9
              MouseArea {
                anchors.fill: parent
                onClicked: root.mindOpen = !root.mindOpen
              }
            }
          }

          // Fixed status chip (always available); bubbles cover one-off events.
          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            implicitWidth: chipText.width + 12
            implicitHeight: chipText.height + 4
            radius: Math.min(11, implicitHeight / 2)
            color: {
              var l = pet.stateLabel
              if (l === "sleeping") return Qt.rgba(0.28, 0.4, 0.75, 0.55)
              if (l === "grumpy")  return Qt.rgba(0.75, 0.35, 0.3, 0.6)
              if (l === "hunting") return Qt.rgba(0.85, 0.65, 0.25, 0.6)
              if (l === "hungry")  return Qt.rgba(0.85, 0.55, 0.2, 0.6)
              if (l === "full")    return Qt.rgba(0.3, 0.75, 0.45, 0.55)
              if (l === "resting") return Qt.rgba(0.4, 0.55, 0.5, 0.5)
              return Qt.rgba(0.25, 0.6, 0.62, 0.55)
            }

            Text {
              id: chipText
              anchors.centerIn: parent
              text: pet.stateLabelText
              color: "white"
              font.pixelSize: 9
              font.bold: true
            }
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

        // First-run naming. Only shows while the pet has never been named and
        // no CLI setting seeded one; the pet keeps living behind it.
        Rectangle {
          id: onboarding
          visible: root.needsOnboarding
          anchors.fill: parent
          color: Qt.rgba(0, 0, 0, 0.5)

          Rectangle {
            anchors.centerIn: parent
            width: 300
            height: 150
            radius: 12
            color: Qt.rgba(0.1, 0.12, 0.16, 0.95)

            Column {
              anchors.fill: parent
              anchors.margins: 16
              spacing: 10

              Text {
                text: "🐛 Meet your pet"
                color: "white"
                font.pixelSize: 14
                font.bold: true
              }

              Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: "It's a real tiny nervous system. What would you call it?"
                color: Qt.rgba(0.82, 0.9, 0.88, 1)
                font.pixelSize: 10
              }

              TextInput {
                id: onboardField
                width: parent.width
                height: 22
                color: "white"
                font.pixelSize: 11
                focus: root.needsOnboarding
                selectByMouse: true
                onAccepted: root.commitOnboarding()
              }

              Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 120
                height: 24
                radius: 6
                color: "#4dff88"

                Text {
                  anchors.centerIn: parent
                  text: "Continue"
                  color: "#0a0f0d"
                  font.pixelSize: 10
                  font.bold: true
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: root.commitOnboarding()
                }
              }
            }
          }
        }

        // 🧠 Mind overlay: reads what the pet is doing and why. Pure
        // interpretation (state + drivers live in Pet.qml) + presentation —
        // nothing here feeds back into the simulation or moves the worm.
        Rectangle {
          id: mindOverlay
          visible: root.mindOpen && !root.needsOnboarding
          z: 100
          width: Math.min(parent.width - 40, 420)
          height: Math.min(parent.height - 70, 380)
          anchors.centerIn: parent
          anchors.verticalCenterOffset: -6
          radius: 12
          color: Qt.rgba(0.08, 0.1, 0.14, 0.97)
          border.color: Qt.rgba(0.45, 1, 0.9, 0.25)
          border.width: 1

          Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 8

            Row {
              width: parent.width
              spacing: 6

              Text {
                id: mindTitle
                text: "🧠 " + petState.petName + "'s mind"
                color: "white"
                font.pixelSize: 13
                font.bold: true
              }

              Item {
                width: parent.width - mindTitle.width - closeMindBtn.width - parent.spacing
                height: 1
              }

              Text {
                id: closeMindBtn
                text: "✕"
                color: Qt.rgba(0.82, 0.9, 0.88, 1)
                font.pixelSize: 12
                MouseArea {
                  anchors.fill: parent
                  onClicked: root.mindOpen = false
                }
              }
            }

            // Primary state: the same stable, hysteresis-backed chip label,
            // plus one sentence of interpretation.
            Text {
              text: pet.stateLabelText
              color: "white"
              font.pixelSize: 15
              font.bold: true
            }

            Text {
              width: parent.width
              wrapMode: Text.Wrap
              text: pet.mindSummary()
              color: Qt.rgba(0.82, 0.9, 0.88, 1)
              font.pixelSize: 10
            }

            Text {
              text: "Why:"
              color: Qt.rgba(0.45, 1, 0.9, 1)
              font.pixelSize: 9
              font.bold: true
            }

            Flow {
              width: parent.width
              spacing: 4

              Repeater {
                model: pet.mindDrivers
                delegate: Rectangle {
                  implicitHeight: 16
                  implicitWidth: driverText.width + 10
                  radius: 8
                  color: Qt.rgba(1, 1, 1, 0.08)

                  Text {
                    id: driverText
                    anchors.centerIn: parent
                    text: modelData.icon + " " + modelData.text
                    color: "white"
                    font.pixelSize: 9
                  }
                }
              }
            }

            Text {
              text: "Recent:"
              color: Qt.rgba(0.45, 1, 0.9, 1)
              font.pixelSize: 9
              font.bold: true
            }

            ListView {
              width: parent.width
              height: 150
              clip: true
              spacing: 2
              model: pet.eventLog.slice(0, 8)

              delegate: Item {
                width: ListView.view.width
                height: 16

                Text {
                  text: modelData.text
                  width: parent.width - 52
                  elide: Text.ElideRight
                  color: "white"
                  font.pixelSize: 9
                }

                Text {
                  text: root.relativeTime(modelData.time)
                  anchors.right: parent.right
                  color: Qt.rgba(0.6, 0.7, 0.7, 1)
                  font.pixelSize: 8
                }
              }

              Text {
                visible: parent.count === 0
                anchors.centerIn: parent
                color: Qt.rgba(0.6, 0.7, 0.7, 1)
                text: "Nothing yet — give the pet a moment."
                font.pixelSize: 9
              }
            }
          }
        }
      }
    }
  }
}