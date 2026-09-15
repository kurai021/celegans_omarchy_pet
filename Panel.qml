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
  onOpenedChanged: if (!root.opened) { root.mindOpen = false; root.expertOpen = false; root.labOpen = false; root.circuitOpen = false }

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
  // F4 Expert View: advanced read-only mode opened from the Mind overlay.
  // While open, it pauses the Mind overlay and samples the connectome.
  property bool expertOpen: false
  // Phase B Stimulus Lab: third overlay, same ladder, opened from Mind. Its
  // session snapshots the brain and never writes to pet.json.
  property bool labOpen: false
  // Phase A Circuit Lab: fourth overlay, opened from Mind. Same snapshot
  // isolation; only the explicit "apply to pet" writes to pet.json.
  property bool circuitOpen: false

  function commitRename() {
    var name = renameField.text
    var applied = petState ? petState.setName(name) : ""
    if (applied && applied !== String(root.petNameSetting)) root.syncNameToSetting(applied)
    // A new name reshuffles the tank decor (first-ever naming does too).
    if (applied && world) world.regenerateObstacles()
    root.renameActive = false
  }

  function commitOnboarding() {
    var applied = petState.setName(onboardField.text)
    if (applied) root.syncNameToSetting(applied)
    if (world) world.regenerateObstacles()
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
    // Pause pet aging when the panel is closed: energy never drains (nor
    // recovers) in the background, so an overnight away no longer starves it.
    lifeActive: root.opened
  }

  // Observation pipeline for the Expert View. Does zero work while the
  // overlay is closed (its Connections are disabled), and never writes back.
  // The Lab and Circuit overlays share it so their live readouts see the same
  // real signals.
  Panels.ConnectomeMonitor {
    id: monitor
    brainController: brainController
    active: root.expertOpen || root.labOpen || root.circuitOpen
  }

  // Phase A: the pet's applied circuit patches seed the live brain as soon as
  // pet.json has loaded (and after each "apply to pet"), except while the
  // Circuit overlay is actively editing its own session copy.
  Connections {
    target: petState
    function onCircuitChanged() {
      if (!root.circuitOpen && petState && brainController)
        brainController.setLiveCircuit(petState.circuit)
    }
  }

  // Phase B: persistent journal of Lab experiments (separate file from pet.json).
  Panels.ExperimentJournal {
    id: journal
  }

  KeyboardPanel {
    id: panel
    bar: root.bar
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(root.expertOpen || root.labOpen || root.circuitOpen ? 1024 : 960)
    contentHeight: panel.fittedContentHeight(root.expertOpen || root.labOpen || root.circuitOpen ? 768 : 640)
    centerOnBar: root.expertOpen || root.labOpen || root.circuitOpen

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        anchors.fill: parent
        spacing: 0

        Rectangle {
          id: aquarium
          width: parent.width
          height: parent.height - hudBar.height
          color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)

        // World first so the pet renders on top (and wins the click when the
        // cursor is over it; anywhere else drops food).
        Panels.World {
          id: world
          anchors.fill: parent
          // The auto feeder and the world's own timers only run while the
          // panel is open (the pet can't eat while nobody is watching), so
          // food never rains down in the background.
          live: root.opened
          autoFeedEnabled: root.opened && petState.energy < 55
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
                font.pixelSize: 12
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
                  font.pixelSize: 12
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
          visible: root.mindOpen && !root.needsOnboarding && !root.expertOpen && !root.labOpen && !root.circuitOpen
          z: 100
          width: Math.min(parent.width - 40, 520)
          height: Math.min(parent.height - 70, 500)
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
                font.pixelSize: 15
                font.bold: true
              }

              Item {
                width: parent.width - mindTitle.width - expertBtn.implicitWidth
                    - labBtn.implicitWidth - circuitBtn.implicitWidth - closeMindBtn.width
                    - parent.spacing * 5
                height: 1
              }

              Rectangle {
                id: circuitBtn
                implicitWidth: circuitBtnText.implicitWidth + 14
                implicitHeight: 22
                anchors.verticalCenter: parent.verticalCenter
                radius: 9
                color: Qt.rgba(0.62, 0.5, 0.95, 0.28)
                border.color: Qt.rgba(0.85, 0.75, 1, 0.5)
                border.width: 1

                Text {
                  id: circuitBtnText
                  anchors.centerIn: parent
                  text: "🧬 circuit"
                  color: "white"
                  font.pixelSize: 11
                  font.bold: true
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    // Enter the circuit lab (tune real synapses, no consequences
                    // until an explicit "apply to pet").
                    root.mindOpen = false
                    root.circuitOpen = true
                  }
                }
              }

              Rectangle {
                id: labBtn
                implicitWidth: labBtnText.implicitWidth + 14
                implicitHeight: 22
                anchors.verticalCenter: parent.verticalCenter
                radius: 9
                color: Qt.rgba(0.35, 0.85, 0.7, 0.25)
                border.color: Qt.rgba(0.55, 1, 0.85, 0.45)
                border.width: 1

                Text {
                  id: labBtnText
                  anchors.centerIn: parent
                  text: "🧪 lab"
                  color: "white"
                  font.pixelSize: 11
                  font.bold: true
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    // Enter the stimulus lab (experiment without consequences).
                    root.mindOpen = false
                    root.labOpen = true
                  }
                }
              }

              Rectangle {
                id: expertBtn
                implicitWidth: expertBtnText.implicitWidth + 14
                implicitHeight: 22
                anchors.verticalCenter: parent.verticalCenter
                radius: 9
                color: Qt.rgba(0.35, 0.72, 0.88, 0.25)
                border.color: Qt.rgba(0.55, 0.9, 1, 0.45)
                border.width: 1

                Text {
                  id: expertBtnText
                  anchors.centerIn: parent
                  text: "🔬 expert"
                  color: "white"
                  font.pixelSize: 11
                  font.bold: true
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: {
                    // Enter the advanced (read-only) connectome view.
                    root.mindOpen = false
                    root.expertOpen = true
                  }
                }
              }

              Text {
                id: closeMindBtn
                text: "✕"
                color: Qt.rgba(0.82, 0.9, 0.88, 1)
                font.pixelSize: 13
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
              font.pixelSize: 16
              font.bold: true
            }

            Text {
              width: parent.width
              wrapMode: Text.Wrap
              text: pet.mindSummary()
              color: Qt.rgba(0.82, 0.9, 0.88, 1)
              font.pixelSize: 12
            }

            Text {
              text: "Why:"
              color: Qt.rgba(0.45, 1, 0.9, 1)
              font.pixelSize: 11
              font.bold: true
            }

            Flow {
              width: parent.width
              spacing: 4

              Repeater {
                model: pet.mindDrivers
                delegate: Rectangle {
                  implicitHeight: 20
                  implicitWidth: driverText.width + 12
                  radius: 8
                  color: Qt.rgba(1, 1, 1, 0.08)

                  Text {
                    id: driverText
                    anchors.centerIn: parent
                    text: modelData.icon + " " + modelData.text
                    color: "white"
                    font.pixelSize: 11
                  }
                }
              }
            }

            Text {
              text: "Recent:"
              color: Qt.rgba(0.45, 1, 0.9, 1)
              font.pixelSize: 11
              font.bold: true
            }

            ListView {
              width: parent.width
              height: 210
              clip: true
              spacing: 2
              model: pet.eventLog.slice(0, 8)

              delegate: Item {
                width: ListView.view.width
                height: 20

                Text {
                  text: modelData.text
                  width: parent.width - 60
                  elide: Text.ElideRight
                  color: "white"
                  font.pixelSize: 11
                }

                Text {
                  text: root.relativeTime(modelData.time)
                  anchors.right: parent.right
                  color: Qt.rgba(0.6, 0.7, 0.7, 1)
                  font.pixelSize: 11
                }
              }

              Text {
                visible: parent.count === 0
                anchors.centerIn: parent
                color: Qt.rgba(0.6, 0.7, 0.7, 1)
                text: "Nothing yet — give the pet a moment."
                font.pixelSize: 11
              }
            }
          }
        }

        // 🔬 F4 Expert View: read-only live connectome view. Opened from the
        // Mind overlay; while it is open the simulator keeps running untouched
        // and the monitor samples it (nothing here writes back).
        Panels.ExpertView {
          id: expertView
          anchors.fill: parent
          anchors.margins: 10
          visible: root.expertOpen && !root.needsOnboarding
          z: 102
          pet: pet
          monitor: monitor
          onClosed: root.expertOpen = false
        }

        // 🧪 Phase B Stimulus Lab: the third rung of the ladder. Snapshot-based
        // isolation: stimuli only touch synaptic charges while it is open, and
        // closing restores the brain; the journal keeps what WE learned.
        Panels.LabPanel {
          id: labView
          anchors.fill: parent
          anchors.margins: 10
          visible: root.labOpen && !root.needsOnboarding
          z: 102
          pet: pet
          monitor: monitor
          brainController: brainController
          world: world
          journal: journal
          onClosed: root.labOpen = false
          onToMind: { root.labOpen = false; root.mindOpen = true }
        }

        // 🧬 Phase A Circuit Lab: the fourth rung of the ladder. Same snapshot
        // isolation as the Lab (brain + patch map restored on close); the only
        // path that writes to pet.json is the explicit "apply to pet".
        Panels.CircuitPanel {
          id: circuitView
          anchors.fill: parent
          anchors.margins: 10
          visible: root.circuitOpen && !root.needsOnboarding
          z: 103
          pet: pet
          petState: petState
          monitor: monitor
          brainController: brainController
          journal: journal
          onClosed: root.circuitOpen = false
          onToMind: { root.circuitOpen = false; root.mindOpen = true }
        }
      }

        // HUD strip below the tank — outside the aquarium, so clicks here can
        // never fall through and drop food in the tank:
        //   left  : name ·  emoji+state chip
        //          : energy bar
        //   right : edit-name and mind-view buttons (big, hard to misclick).
        Rectangle {
          id: hudBar
          width: parent.width
          height: 62
          color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.09)

          Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Qt.rgba(0.45, 1, 0.9, 0.25)
          }

          Column {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7

            Row {
              spacing: 10

              Text {
                id: nameText
                visible: !root.renameActive
                height: 26
                verticalAlignment: Text.AlignVCenter
                text: petState.petName
                color: Qt.rgba(0.7, 1, 0.95, 1)
                font.pixelSize: 15
                font.bold: true
              }

              TextInput {
                id: renameField
                visible: root.renameActive
                width: 140
                height: 26
                verticalAlignment: TextInput.AlignVCenter
                text: petState.petName
                color: Qt.rgba(0.7, 1, 0.95, 1)
                font.pixelSize: 15
                font.bold: true
                selectByMouse: true
                onAccepted: root.commitRename()
                onActiveFocusChanged: if (!activeFocus && root.renameActive) root.renameActive = false
                Keys.onEscapePressed: root.renameActive = false
              }

              // Fixed status chip (always available); bubbles cover one-off events.
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: chipText.width + 18
                implicitHeight: chipText.height + 6
                radius: Math.min(14, implicitHeight / 2)
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
                  font.pixelSize: 13
                  font.bold: true
                }
              }

              // Applied circuit patches (pet.json). Always visible so it is
              // obvious when the pet's wiring is altered and survives sessions.
              Text {
                anchors.verticalCenter: parent.verticalCenter
                height: 26
                verticalAlignment: Text.AlignVCenter
                visible: (petState.circuit || []).length > 0
                text: "🧬 " + (petState.circuit || []).length + (petState.circuit.length === 1 ? " patch" : " patches")
                color: Qt.rgba(0.85, 0.75, 1, 1)
                font.pixelSize: 12
                font.bold: true
              }
            }

            Row {
              spacing: 8

              Text {
                height: 9
                verticalAlignment: Text.AlignVCenter
                text: "⚡"
                font.pixelSize: 11
              }

              Rectangle {
                width: 170
                height: 9
                radius: 4.5
                color: Qt.rgba(1, 1, 1, 0.12)

                Rectangle {
                  width: parent.width * Math.max(0, Math.min(1, petState.energy / 100))
                  height: parent.height
                  radius: 4.5
                  color: petState.energy > 50 ? "#4dff88"
                        : petState.energy > 20 ? "#ffbf5e"
                        : "#ff4d5e"
                }
              }
            }
          }

          // Right corner: rename + mind-view actions as roomy buttons.
          Row {
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Rectangle {
              id: editNameBtn
              visible: !root.renameActive
              width: 38
              height: 38
              radius: 10
              color: Qt.rgba(1, 1, 1, 0.08)
              border.color: Qt.rgba(0.45, 1, 0.9, 0.25)
              border.width: 1

              Text {
                anchors.centerIn: parent
                text: "✏️"
                font.pixelSize: 18
              }
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: parent.color = Qt.rgba(1, 1, 1, 0.16)
                onExited: parent.color = Qt.rgba(1, 1, 1, 0.08)
                onClicked: {
                  root.renameActive = true
                  renameField.forceActiveFocus()
                  Qt.callLater(function() { renameField.selectAll() })
                }
              }
            }

            Rectangle {
              id: mindBtn
              width: 38
              height: 38
              radius: 10
              color: Qt.rgba(1, 1, 1, root.mindOpen ? 0.18 : 0.08)
              border.color: Qt.rgba(0.45, 1, 0.9, 0.25)
              border.width: 1

              Text {
                anchors.centerIn: parent
                text: "🧠"
                font.pixelSize: 18
              }
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: parent.color = Qt.rgba(1, 1, 1, 0.16)
                onExited: parent.color = Qt.rgba(1, 1, 1, root.mindOpen ? 0.18 : 0.08)
                onClicked: root.mindOpen = !root.mindOpen
              }
            }
          }
        }
      }
    }
  }
}