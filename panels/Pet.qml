import QtQuick

// Connector between the brain (BrainConnector) and its position within the
// window. brainController is INJECTED from Main.qml as a property:
// an id declared in another .qml document is not visible here.
Item {
    id: petInstance

    // Define that any rotation is done from the center of the item
    transformOrigin: Item.Center
    property var brainController: null

    // Internal variable to provide some inertia or chaotic exploration
    property real randomTurnFactor: 0.0

    property string currentMessage: ""
    readonly property var phrases: [
        "Don't touch me!",
        "Gross!",
        "Personal space, please!",
        "I'm not a toy!",
        "Stop it!",
        "Go away!",
        "I'm busy being a worm!",
        "No touching!"
    ]

    // Every time the connectome completes a cycle, we translate the motor
    // force left/right into rotation + displacement within the window.
    Connections {
        target: petInstance.brainController
        function onUpdated() {
            if (!petInstance.brainController || !petInstance.parent) return

            var muscles = petInstance.brainController.muscles

            var left = petInstance.brainController.leftMotor
            var right = petInstance.brainController.rightMotor

            // 1. Natural chaotic exploration:
            // Occasionally we add a small stochastic bias (biological noise)
            if (Math.random() < 0.05) {
                petInstance.randomTurnFactor = (Math.random() - 0.5) * 15.0;
            } else {
                petInstance.randomTurnFactor *= 0.8; // Smooth decay
            }

            var forwardSpeed = (left + right) * 0.02
            var turnDiff = (left - right) + petInstance.randomTurnFactor

            // By modifying rotation, the element now rotates around its center
            petInstance.rotation += turnDiff * 0.2

            var rad = petInstance.rotation * Math.PI / 180
            var newX = petInstance.x + Math.cos(rad) * forwardSpeed
            var newY = petInstance.y + Math.sin(rad) * forwardSpeed

            var maxX = petInstance.parent.width - petInstance.width
            var maxY = petInstance.parent.height - petInstance.height

            // 2. Conscious wall detection:
            // If the new position touches the edge, we STIMULATE the connectome
            // instead of forcing a mathematical refraction.
            if (newX <= 0 || newX >= maxX || newY <= 0 || newY >= maxY) {
                if (petInstance.brainController) {
                    // Frontal mechanoreceptor stimulus (collision with obstacle)
                    petInstance.brainController.stimulateTouch()
                }

                // Randomly rotate orientation to simulate disorienting collision
                petInstance.rotation += (Math.random() > 0.5 ? 90 : -90) + (Math.random() * 30 - 15);
            } else {
                // If the path is clear, move forward normally
                petInstance.x = newX;
                petInstance.y = newY;
            }
        }
    }

    PetVisual {
        id: petVisual
        anchors.fill: parent
        rotation: 90 // Or -90, to align vertical drawing with horizontal movement vector
        transformOrigin: Item.Center

        // A click = real tactile stimulus on the connectome
        onClicked: {
          if (petInstance.brainController) {
            petInstance.brainController.stimulateTouch();
            petInstance.rotation += (Math.random() > 0.5 ? 90 : -90) + (Math.random() * 30 - 15);

            petInstance.currentMessage = petInstance.phrases[Math.floor(Math.random() * petInstance.phrases.length)];
            messageTimer.start();

            // Immediate visual feedback
            petVisual.isStartled = true;
            flashTimer.start();
          }
        }

        Timer {
          id: flashTimer
          interval: 800
          onTriggered: petVisual.isStartled = false
        }

        Timer {
          id: messageTimer
          interval: 2000
          onTriggered: petInstance.currentMessage = ""
        }

        // Manually drag the mascota manually within the window
        onDragged: (dx, dy) => {
            if (!petInstance.parent) return

            var maxX = petInstance.parent.width - petInstance.width
            var maxY = petInstance.parent.height - petInstance.height
            petInstance.x = Math.max(0, Math.min(maxX, petInstance.x + dx))
            petInstance.y = Math.max(0, Math.min(maxY, petInstance.y + dy))
        }
    }

    // Speech bubble for funny reactions
    Rectangle {
        id: bubble
        visible: petInstance.currentMessage !== ""
        color: "white"
        radius: 8
        border.color: "#ccc"
        border.width: 1
        rotation: -petInstance.rotation // Counter-rotate to stay upright
        
        width: bubbleText.width + 20
        height: bubbleText.height + 10
        x: (petInstance.width - width) / 2
        y: -height - 10 // Positioned above the pet

        Text {
            id: bubbleText
            anchors.centerIn: parent
            text: petInstance.currentMessage
            color: "black"
            font.pixelSize: 12
            font.bold: true
        }
    }
}
