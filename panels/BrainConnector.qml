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

    // --- Phase B: Lab stimulus channels (default OFF = pet unchanged) ------
    // Same mechanism as chemotaxis (probe imbalance -> surplus onto real
    // sensory neurons) but on cells that normally receive no injected input:
    //   thermo sensor: AFDL/AFDR (real AFD thermo cells)
    //   chemical B:    AWAL/AWAR (real AWA chemosensory cells)
    // The gradient->charge mapping below is a SYNTHETIC harness on real cells:
    // the source cells and every connection downstream are the real connectome.
    property real thermoWeight: 0            // AFD surplus injection (0 = off)
    property real chemBWeight: 0             // AWA surplus injection (0 = off)
    property bool labSessionActive: false    // Lab snapshot taken; allow injection
    property real pendingThermoForward: 0    // temperature probe ahead
    property real pendingThermoLeft: 0       // temperature probe left
    property real pendingThermoRight: 0      // temperature probe right
    property real pendingChemBForward: 0     // chemical-B probe ahead
    property real pendingChemBLeft: 0        // chemical-B probe left
    property real pendingChemBRight: 0       // chemical-B probe right
    property int tailCooldown: 0             // tail-touch stimulus window
    property real pendingTailScale: 1        // strength of the next tail poke
    property string pendingTailSide: "none"  // left | right | none (symmetric)
    readonly property real thermoDriveFactor: 0.4
    readonly property real chemBDriveFactor: 0.4

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

            // --- thermo (AFDL/AFDR) and chemical B (AWAL/AWAR) channels ---
            // Same surplus + forward-drive shape as the food smell: imbalance
            // steers, "ahead" keeps the run going. Only runs when the Lab has
            // armed the corresponding weight (default 0 keeps the pet normal).
            var tf = brainController.pendingThermoForward
            var tl = brainController.pendingThermoLeft
            var tr = brainController.pendingThermoRight
            if (brainController.labSessionActive && brainController.thermoWeight > 0
                    && (tl > 0 || tr > 0 || tf > 0)) {
                var tBal = tl - tr
                if (Math.abs(tBal) > 0.02) {
                    brain.postSynaptic["AFDL"][next] += brainController.thermoWeight * tBal
                    brain.postSynaptic["AFDR"][next] += -brainController.thermoWeight * tBal
                }
                var tDrive = brainController.thermoWeight * brainController.thermoDriveFactor * tf
                if (tDrive > 0) {
                    brain.postSynaptic["AFDL"][next] += tDrive
                    brain.postSynaptic["AFDR"][next] += tDrive
                }
            }
            brainController.pendingThermoForward = 0
            brainController.pendingThermoLeft = 0
            brainController.pendingThermoRight = 0

            var cb = brainController.pendingChemBForward
            var cbl = brainController.pendingChemBLeft
            var cbr = brainController.pendingChemBRight
            if (brainController.labSessionActive && brainController.chemBWeight > 0
                    && (cbl > 0 || cbr > 0 || cb > 0)) {
                var cbBal = cbl - cbr
                if (Math.abs(cbBal) > 0.02) {
                    brain.postSynaptic["AWAL"][next] += brainController.chemBWeight * cbBal
                    brain.postSynaptic["AWAR"][next] += -brainController.chemBWeight * cbBal
                }
                var cbDrive = brainController.chemBWeight * brainController.chemBDriveFactor * cb
                if (cbDrive > 0) {
                    brain.postSynaptic["AWAL"][next] += cbDrive
                    brain.postSynaptic["AWAR"][next] += cbDrive
                }
            }
            brainController.pendingChemBForward = 0
            brainController.pendingChemBLeft = 0
            brainController.pendingChemBRight = 0

            // --- tail touch (PLML/PLMR) ---
            if (brainController.labSessionActive && brainController.tailCooldown > 0) {
                var twl = 1.0
                var twr = 1.0
                if (brainController.pendingTailSide === "left") { twl = 1.0; twr = 0.5 }
                else if (brainController.pendingTailSide === "right") { twl = 0.5; twr = 1.0 }
                var tailCharge = 150 * brainController.pendingTailScale
                brain.postSynaptic["PLML"][next] += tailCharge * twl
                brain.postSynaptic["PLMR"][next] += tailCharge * twr
                brainController.tailCooldown--
            }
            brainController.pendingTailSide = "none"
            brainController.pendingTailScale = 1

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

    // Prime the thermo channel for the next cycle with the temperature
    // gradient the pet reads (same probe shape as the food smell).
    function setThermoSense(forward, left, right) {
        brainController.pendingThermoForward = forward
        brainController.pendingThermoLeft = left
        brainController.pendingThermoRight = right
    }

    // Prime the chemical-B channel for the next cycle.
    function setChemBSense(forward, left, right) {
        brainController.pendingChemBForward = forward
        brainController.pendingChemBLeft = left
        brainController.pendingChemBRight = right
    }

    // Stimulate the tail mechanoreceptors (PLM cells). Side hints which flank
    // was poked; symmetric by default. The reflex itself comes out of the
    // wiring (PLM -> AVA/AS/VB -> body muscles).
    function stimulateTail(side, chargeScale) {
        if (!brainInstance) return
        var scale = (chargeScale === undefined || chargeScale === null) ? 1 : chargeScale
        brainController.pendingTailScale = Math.max(0, Math.min(1, scale))
        brainController.pendingTailSide = side || "none"
        brainController.tailCooldown = 4 // ~0.4 s stimulus window
    }

    // --- Experiment isolation (Phase B) ------------------------------------
    // Deep copy of every synaptic charge + the contact state, so a Lab session
    // can always return the brain to the exact state it had before any
    // stimulus was injected. Charge arrays are reset every cycle by update();
    // nothing here writes to pet.json.
    property var labSnapshot: null
    function snapshotBrain() {
        if (!brainInstance) return
        var b = brainInstance
        var snap = { "post": {}, "next": b.nextState, "prev": b.thisState }
        for (var name in b.postSynaptic)
            snap.post[name] = [b.postSynaptic[name][0] || 0, b.postSynaptic[name][1] || 0]
        brainController.labSnapshot = snap
    }
    function restoreBrain() {
        if (!brainInstance || !brainController.labSnapshot) return
        var snap = brainController.labSnapshot
        var names = Object.keys(snap.post)
        for (var i = 0; i < names.length; i++) {
            if (brainInstance.postSynaptic[names[i]])
                brainInstance.postSynaptic[names[i]] = [snap.post[names[i]][0], snap.post[names[i]][1]]
        }
        brainInstance.thisState = snap.prev
        brainInstance.nextState = snap.next
        brainController.leftMotor = 0
        brainController.rightMotor = 0
        brainController.labSnapshot = null
    }
}