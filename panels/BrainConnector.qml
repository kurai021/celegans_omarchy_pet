import QtQuick
import "Celegans.js" as CElegans

// Single source of truth for the connectome: creates and advances the brain,
// and exposes what Pet.qml needs to move and react.
//
// The connectome receives two kinds of external sensory input, both injected
// as electric charge into real sensory neurons:
//  - touch:   ALML/ALMR (body mechanoreceptors) via stimulateTouch(side)
//  - smell:   ADFL/ADFR (+ the rest of the chemo pool) by an asymmetric
//             surplus current derived from the food gradient. Pet computes
//             left/right/forward probes and hands them in with
//             setChemoSense(); the actual turn comes out of the wiring
//             (ADFL/ADFR -> AIZ/RIM/SMB/SMD -> body muscles).
Item {
    id: brainController

    property var brainInstance: null
    property real leftMotor: 0
    property real rightMotor: 0

    // Set to false (e.g. while the panel is hidden) to pause the connectome
    // and stop spending CPU on a pet nobody can see.
    property bool simulationActive: true

    // Emitted at the end of each simulation cycle (10 Hz)
    signal updated()

    // --- pending sensory input for the NEXT cycle -------------------------
    property real pendingSmellForward: 0   // intensity straight ahead
    property real pendingSmellLeft: 0      // intensity to the pet's left
    property real pendingSmellRight: 0     // intensity to the pet's right
    property int touchCooldown: 0
    property real pendingTouchScale: 1 // habituation factor (0..1) for the next touch
    property string pendingTouchSide: "none" // none | front | left | right

    // Tuning: how strongly the smell imbalance traduces into lateral charge.
    // The surplus (left - right) is added to ADFL and subtracted from ADFR,
    // so the real connectome turns toward the smellier side.
    property real chemoSideWeight: 26

    Component.onCompleted: {
        brainInstance = new CElegans.Brain()
        brainInstance.setup()

        // Without a stimulus Brain.update() does nothing: the connectome
        // needs active sensory input to propagate. The ambient food-sense
        // drive below keeps the worm "exploring"; chemotaxis only adds an
        // asymmetry on top of it when food is in range.
        brainInstance.stimulateFoodSenseNeurons = true
    }

    // Main connectome pulse (10 Hz)
    Timer {
        interval: 100
        running: brainController.simulationActive
        repeat: true
        onTriggered: {
            if (!brainController.brainInstance) return

            var brain = brainController.brainInstance
            var next = brain.nextState

            // --- touch stimulus (body mechanoreceptors) ---
            if (brainController.touchCooldown > 0) {
                var wl = 1.0
                var wr = 1.0
                if (brainController.pendingTouchSide === "left") { wl = 0.6; wr = 1.4 }
                else if (brainController.pendingTouchSide === "right") { wl = 1.4; wr = 0.6 }
                var charge = 120 * brainController.pendingTouchScale
                brain.postSynaptic["ALML"][next] += charge * wl
                brain.postSynaptic["ALMR"][next] += charge * wr
                brain.stimulateNoseTouchNeurons = true
                brainController.touchCooldown--
            } else {
                brain.stimulateNoseTouchNeurons = false
            }
            brainController.pendingTouchSide = "none"
            brainController.pendingTouchScale = 1

            // --- chemosense (food gradient) ---
            var sf = brainController.pendingSmellForward
            var sl = brainController.pendingSmellLeft
            var sr = brainController.pendingSmellRight
            if (sl > 0 || sr > 0 || sf > 0) {
                // Surplus onto the smellier side steers through the wiring.
                var bal = sl - sr
                if (Math.abs(bal) > 0.02) {
                    brain.postSynaptic["ADFL"][next] += brainController.chemoSideWeight * bal
                    brain.postSynaptic["ADFR"][next] += -brainController.chemoSideWeight * bal
                }
                // Forward-food drive: food ahead raises overall chemo activity,
                // keeping the run going instead of tumbling away.
                var drive = brainController.chemoSideWeight * 0.4 * sf
                if (drive > 0) {
                    brain.postSynaptic["ADFL"][next] += drive
                    brain.postSynaptic["ADFR"][next] += drive
                }
            }
            brainController.pendingSmellForward = 0
            brainController.pendingSmellLeft = 0
            brainController.pendingSmellRight = 0

            brain.update()

            brainController.leftMotor = brain.accumleft
            brainController.rightMotor = brain.accumright

            brain.accumleft = 0
            brain.accumright = 0

            brainController.updated()
        }
    }

    // Prime the next cycle with the current smell gradient. Pet calls this
    // right after updating (so it describes the pose the worm will hold).
    function setChemoSense(forward, left, right) {
        brainController.pendingSmellForward = forward
        brainController.pendingSmellLeft = left
        brainController.pendingSmellRight = right
    }

    // Stimulates the anterior/body tactile neurons. `side` hints whether the
    // contact came from the front or one of the pet's flanks, which only
    // tilts the otherwise symmetric reflex. `chargeScale` (0..1) is the
    // habituation factor: how strongly the stimulus lands on the connectome.
    // 1 = full response (default), floor ~0.35 = habituated. The avoidance
    // reflex itself stays intact; only the sensory charge is damped.
    function stimulateTouch(side, chargeScale) {
        if (!brainInstance) return
        var scale = (chargeScale === undefined || chargeScale === null) ? 1 : chargeScale
        brainController.pendingTouchScale = Math.max(0, Math.min(1, scale))
        brainController.pendingTouchSide = side || "front"
        brainController.touchCooldown = 10 // keep the stimulus 1 second
    }
}