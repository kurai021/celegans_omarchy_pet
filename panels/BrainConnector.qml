import QtQuick
import "Celegans.js" as CElegans

// Single source of truth for the connectome: creates and advances the brain,
// and exposes what Pet.qml needs to move and react.
Item {
    id: brainController

    property var brainInstance: null
    property real leftMotor: 0
    property real rightMotor: 0

    // Emitted at the end of each simulation cycle (10 Hz)
    signal updated()

    Component.onCompleted: {
        brainInstance = new CElegans.Brain()
        brainInstance.setup()

        // Without this, Brain.update() does nothing: the original connectome
        // needs an active stimulus (touch or smell) to propagate signals.
        // We keep it "exploring" continuously, like the original robot.
        brainInstance.stimulateFoodSenseNeurons = true
    }

    property int touchCooldown: 0

    // Main connectome pulse (10 Hz)
    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            if (!brainController.brainInstance) return

            // Keep the stimulus active for several simulation cycles
              if (brainController.touchCooldown > 0) {
                brainController.brainInstance.postSynaptic["ALML"][brainController.brainInstance.nextState] += 120
                brainController.brainInstance.postSynaptic["ALMR"][brainController.brainInstance.nextState] += 120
                brainController.brainInstance.stimulateNoseTouchNeurons = true
                brainController.touchCooldown--
              } else {
                brainController.brainInstance.stimulateNoseTouchNeurons = false
              }

            brainController.brainInstance.update()

            brainController.leftMotor = brainController.brainInstance.accumleft
            brainController.rightMotor = brainController.brainInstance.accumright

            brainController.brainInstance.accumleft = 0
            brainController.brainInstance.accumright = 0

            brainController.updated()
        }
    }

    // Stimulates the anterior tactile neurons (equivalent to touching the worm).
    // ALML/ALMR are the actual names in the connectome ("ALM" does not exist).
    function stimulateTouch() {
        if (!brainInstance) return

        touchCooldown = 10 // Keep the stimulus active for 10 simulation cycles (1 second)
    }
}
