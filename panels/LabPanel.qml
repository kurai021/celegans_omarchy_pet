import QtQuick
import "ConnectomeGraph.js" as GraphData

// Phase B Stimulus Lab: ask a question, apply a stimulus through the REAL
// connectome, watch the response, and log the experiment.
//
// Honesty contract:
//   - Every stimulus lands on real cells (AFD thermo, AWA chemical-B, PLM
//     tail) and everything downstream is real wiring from Celegans.js.
//   - The gradient->charge mapping is a SYNTHETIC harness on those real cells
//     and is labelled as such in the UI.
//   - The pet never bypasses the connectome for these channels: there is no
//     auxiliary steering for thermo/chemB (only food smell may assist), so
//     whatever the worm does comes from the actual nervous response.
//   - Isolation: while the Lab is open the brain is snapshotted; closing or
//     ending a session restores the exact same synaptic state. Nothing here
//     writes to pet.json (that is the pet's own memory) — results live in the
//     separate experiment-journal.json.
Item {
    id: lab
    visible: false

    property var pet: null
    property var monitor: null
    property var brainController: null
    property var world: null
    property var journal: null

    signal closed()
    signal toMind()

    // --- channel arming -----------------------------------------------------
    property bool running: false
    property bool thermoOn: false
    property bool chemBOn: false
    property bool thermoOpen: true
    property bool chemBOpen: true
    property bool tailOpen: true
    property real thermoStrength: 0.5
    property real chemBStrength: 0.5
    readonly property real thermoBaseWeight: 30
    readonly property real chemBBaseWeight: 45

    // Real cells each channel drives (live readout + results).
    readonly property var thermoCells: ["AFDL", "AFDR", "AIYL", "AIYR"]
    readonly property var chemBCells: ["AWAL", "AWAR", "AIZL", "AIZR"]
    readonly property var tailCells: ["PLML", "PLMR", "AVAL", "AVAR"]

    // --- observed results (accumulated only while `running`) ----------------
    property int thermoFires: 0
    property int chemBFires: 0
    property int tailFires: 0
    property int motorSamples: 0
    property real motorTotal: 0
    property real motorPeak: 0

    property string hypothesis: ""
    property string observation: ""

    // live readouts
    property string motorLText: "0"
    property string motorRText: "0"
    property string liveContext: "waiting for cycles…"
    property int frame: 0

    readonly property string honestyNote:
        "Cells are real (AFD thermo, AWA chemical-B, PLM tail); the gradient→charge mapping is synthetic. No auxiliary steering for these channels — the response is the wiring's. Seeded reproductions: node experiments/stimulus-lab.js"

    function pushWeights() {
        if (!lab.brainController) return
        lab.brainController.thermoWeight = lab.running && lab.thermoOn
            ? lab.thermoBaseWeight * lab.thermoStrength : 0
        lab.brainController.chemBWeight = lab.running && lab.chemBOn
            ? lab.chemBBaseWeight * lab.chemBStrength : 0
    }

    function startSession() {
        if (lab.running) return
        if (lab.monitor && (!lab.monitor.charges || !lab.monitor.charges.length)) {
            if (typeof lab.monitor.init === "function") lab.monitor.init()
        }
        if (lab.brainController && typeof lab.brainController.snapshotBrain === "function")
            lab.brainController.snapshotBrain()
        lab.thermoFires = 0
        lab.chemBFires = 0
        lab.tailFires = 0
        lab.motorSamples = 0
        lab.motorTotal = 0
        lab.motorPeak = 0
        lab.brainController.labSessionActive = true
        lab.running = true
        lab.pushWeights()
    }

    function endSession() {
        lab.brainController.labSessionActive = false
        lab.thermoOn = false
        lab.chemBOn = false
        lab.running = false
        lab.pushWeights()
        if (lab.brainController && typeof lab.brainController.restoreBrain === "function")
            lab.brainController.restoreBrain()
    }

    function clearStimuli() {
        if (!lab.world) return
        lab.world.labPlaceMode = "none"
        lab.world.clearLabStimuli()
    }

    function pokeTail(side) {
        if (lab.brainController) lab.brainController.stimulateTail(side, 1)
    }

    function togglePlaceMode(mode) {
        if (!lab.world) return
        if (lab.world.labPlaceMode === mode) lab.world.labPlaceMode = "none"
        else if (mode === "thermo") lab.world.labPlaceMode = "thermo"
        else if (mode === "chemB") lab.world.labPlaceMode = "chemB"
    }

    Connections {
        target: lab.monitor
        enabled: lab.running && lab.monitor !== null
        function onSampled() { lab.tick() }
    }

    function tick() {
        if (!lab.running || !lab.brainController) return
        var m = lab.monitor
        if (m && m.fired && m.fired.length) {
            var i
            for (i = 0; i < lab.thermoCells.length; i++) {
                var ti = GraphData.graphNodes().indexOf(lab.thermoCells[i])
                if (ti !== -1 && m.fired[ti]) lab.thermoFires++
            }
            for (i = 0; i < lab.chemBCells.length; i++) {
                var ci = GraphData.graphNodes().indexOf(lab.chemBCells[i])
                if (ci !== -1 && m.fired[ci]) lab.chemBFires++
            }
            for (i = 0; i < lab.tailCells.length; i++) {
                var pl = GraphData.graphNodes().indexOf(lab.tailCells[i])
                if (pl !== -1 && m.fired[pl]) lab.tailFires++
            }
        }
        var mag = (Math.abs(lab.brainController.leftMotor) || 0)
            + (Math.abs(lab.brainController.rightMotor) || 0)
        lab.motorTotal += mag
        lab.motorSamples++
        if (mag > lab.motorPeak) lab.motorPeak = mag
        lab.pushWeights()
    }

    function cellIdx(name) { return GraphData.graphNodes().indexOf(name) }
    function chargeOf(name) { var i = cellIdx(name); return i === -1 ? 0 : (lab.monitor ? lab.monitor.charges[i] || 0 : 0) }
    function firedOf(name) { var i = cellIdx(name); return i !== -1 && lab.monitor && lab.monitor.fired[i] }

    function configSnapshot() {
        return {
            "thermo": { "on": lab.thermoOn, "strength": lab.thermoStrength, "base": lab.thermoBaseWeight,
                        "sources": lab.world ? lab.world.thermoSources.slice() : [] },
            "chemB": { "on": lab.chemBOn, "strength": lab.chemBStrength, "base": lab.chemBBaseWeight,
                       "sources": lab.world ? lab.world.chemBSources.slice() : [] }
        }
    }

    function resultsSnapshot() {
        return {
            "stateContext": lab.pet ? lab.pet.stateLabel : "",
            "cyclesObserved": lab.motorSamples,
            "thermoFires": lab.thermoFires,
            "chemBFires": lab.chemBFires,
            "tailFires": lab.tailFires,
            "motorAvg": lab.motorSamples ? (lab.motorTotal / lab.motorSamples).toFixed(2) : "0",
            "motorPeak": lab.motorPeak.toFixed(2)
        }
    }

    function saveExperiment() {
        lab.journal.add({
            "type": "stimulus",
            "hypothesis": lab.hypothesis,
            "config": lab.configSnapshot(),
            "results": lab.resultsSnapshot(),
            "observation": lab.observation
        })
        lab.observation = ""
        obsEdit.text = ""
    }

    // Re-apply a saved experiment's config (reproducibility).
    function applyConfig(cfg) {
        if (!cfg) return
        if (cfg.thermo) {
            lab.thermoOn = !!cfg.thermo.on
            lab.thermoStrength = Number(cfg.thermo.strength) || 0
            if (lab.world) lab.world.thermoSources = (cfg.thermo.sources || []).slice()
        }
        if (cfg.chemB) {
            lab.chemBOn = !!cfg.chemB.on
            lab.chemBStrength = Number(cfg.chemB.strength) || 0
            if (lab.world) lab.world.chemBSources = (cfg.chemB.sources || []).slice()
        }
        lab.pushWeights()
        if (lab.world && typeof lab.world.refresh === "function") lab.world.refresh()
    }

    onVisibleChanged: {
        if (lab.visible) lab.startSession()
        else if (lab.running) lab.endSession()
    }

    Timer {
        interval: 100
        running: lab.visible
        repeat: true
        onTriggered: {
            lab.frame++
            lab.motorLText = lab.brainController ? Math.abs(lab.brainController.leftMotor).toFixed(1) : "0"
            lab.motorRText = lab.brainController ? Math.abs(lab.brainController.rightMotor).toFixed(1) : "0"
            lab.liveContext = lab.pet
                ? lab.pet.stateLabelText + " — " + lab.pet.mindSummary() : "waiting…"
        }
    }

    // --- journal presentation helpers ----------------------------------------
    function journalTitle(e) {
        var parts = []
        if (e.config && e.config.thermo && e.config.thermo.on) parts.push("🔥")
        if (e.config && e.config.chemB && e.config.chemB.on) parts.push("🧪")
        if (!parts.length) parts.push("(none)")
        return parts.join(" ") + (e.hypothesis ? " — " + e.hypothesis : "")
    }
    function journalSummary(e) {
        var parts = []
        if (e.results) {
            if (Number(e.results.thermoFires)) parts.push("thermo " + e.results.thermoFires + " fires")
            if (Number(e.results.chemBFires)) parts.push("chemB " + e.results.chemBFires + " fires")
            if (Number(e.results.tailFires)) parts.push("tail " + e.results.tailFires + " fires")
            parts.push("motor∅" + e.results.motorAvg)
        }
        return parts.join(" · ") || (e.observation || "recorded")
    }
    function relativeStamp(t) {
        var s = Math.floor((Date.now() - t) / 1000)
        if (s < 10) return "just now"
        if (s < 60) return s + "s ago"
        var m = Math.floor(s / 60)
        if (m < 60) return m + "m ago"
        return Math.floor(m / 60) + "h ago"
    }

    // --- chrome ---------------------------------------------------------------
    Rectangle {
        id: bg
        anchors.fill: parent
        radius: 14
        color: Qt.rgba(0.06, 0.08, 0.11, 0.97)
        border.color: Qt.rgba(0.45, 1, 0.9, 0.25)
        border.width: 1

        Flickable {
            anchors.fill: parent
            anchors.margins: 18
            clip: true
            contentHeight: contentCol.height

            Column {
                id: contentCol
                width: parent.width
                spacing: 14

                // header
                Row {
                    width: parent.width
                    height: 26
                    spacing: 8

                    Text {
                        id: titleTxt
                        text: "🧪 " + (pet ? pet.petName : "?") + " · stimulus lab"
                        color: "white"
                        font.pixelSize: 17
                        font.bold: true
                    }

                    Rectangle {
                        id: runChip
                        height: 24
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: runText.implicitWidth + 14
                        radius: 9
                        color: lab.running ? Qt.rgba(0.35, 0.9, 0.55, 0.22) : Qt.rgba(0.6, 0.6, 0.6, 0.18)
                        border.color: lab.running ? Qt.rgba(0.4, 1, 0.6, 0.4) : Qt.rgba(0.6, 0.6, 0.6, 0.3)
                        border.width: 1

                        Text {
                            id: runText
                            anchors.centerIn: parent
                            text: lab.running ? "● observing" : "◦ idle"
                            color: "white"
                            font.pixelSize: 12
                            font.bold: true
                        }
                    }

                    Text {
                        width: parent.width - titleTxt.implicitWidth - runChip.implicitWidth
                            - closeBtn.implicitWidth - mindBtn.implicitWidth - parent.spacing * 4
                        height: 24
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: "bottom-up: inject stimulus, watch the wiring respond"
                        color: Qt.rgba(0.82, 0.9, 0.88, 1)
                        font.pixelSize: 12
                    }

                    Text {
                        id: mindBtn
                        text: "🧠 mind"
                        anchors.verticalCenter: parent.verticalCenter
                        color: Qt.rgba(0.7, 1, 0.95, 1)
                        font.pixelSize: 10
                        MouseArea {
                            anchors.fill: parent
                            onClicked: lab.toMind()
                        }
                    }

                    Text {
                        id: closeBtn
                        text: "✕"
                        anchors.verticalCenter: parent.verticalCenter
                        color: Qt.rgba(0.82, 0.9, 0.88, 1)
                        font.pixelSize: 16
                        MouseArea {
                            anchors.fill: parent
                            onClicked: lab.close()
                        }
                    }
                }

                Row {
                    width: parent.width
                    spacing: 14

                    // =================== stimuli ============================
                    Column {
                        width: 250
                        spacing: 10

                        Text {
                            text: "stimuli"
                            color: Qt.rgba(0.82, 0.9, 0.88, 1)
                            font.pixelSize: 12
                            font.bold: true
                        }

                        // -- thermo card -------------------------------------
                        Rectangle {
                            width: parent.width
                            height: lab.thermoOpen ? 128 : 32
                            radius: 10
                            color: Qt.rgba(1, 1, 1, 0.05)
                            border.color: Qt.rgba(0.45, 1, 0.9, 0.18)
                            border.width: 1

                            Column {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 7

                                Row {
                                    width: parent.width
                                    spacing: 6

                                    Text {
                                        text: lab.thermoOpen ? "▾" : "▸"
                                        color: Qt.rgba(0.6, 0.7, 0.7, 1)
                                        font.pixelSize: 9
                                        anchors.verticalCenter: parent.verticalCenter
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: lab.thermoOpen = !lab.thermoOpen
                                        }
                                    }

                                    Text {
                                        text: "🔥 thermo AFD"
                                        color: "white"
                                        font.pixelSize: 10
                                        font.bold: true
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        text: "synthetic"
                                        color: Qt.rgba(0.9, 0.72, 0.3, 1)
                                        font.pixelSize: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Item { width: parent.parent.width - 210; height: 1 }

                                    Text {
                                        text: lab.thermoOn ? "on" : "off"
                                        color: lab.thermoOn ? "#4dff88" : Qt.rgba(0.6, 0.7, 0.7, 1)
                                        font.pixelSize: 9
                                        font.bold: true
                                        anchors.verticalCenter: parent.verticalCenter
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: { lab.thermoOn = !lab.thermoOn; lab.pushWeights() }
                                        }
                                    }
                                }

                                Text {
                                    visible: lab.thermoOpen
                                    width: parent.width
                                    wrapMode: Text.Wrap
                                    text: "AFDL/AFDR — real thermo cells; mapping synthetic (charge ∝ ΔT on probes)"
                                    color: Qt.rgba(0.65, 0.78, 0.75, 1)
                                    font.pixelSize: 8
                                }

                                Row {
                                    visible: lab.thermoOpen
                                    width: parent.width
                                    spacing: 6

                                    LabSlider {
                                        id: thermoSlider
                                        anchors.verticalCenter: parent.verticalCenter
                                        value: lab.thermoStrength
                                        width: parent.width - 96
                                        showValue: true
                                        onChanged: { lab.thermoStrength = value; lab.pushWeights() }
                                    }

                                    Rectangle {
                                        width: 88
                                        height: 16
                                        radius: 8
                                        color: world.labPlaceMode === "thermo"
                                            ? Qt.rgba(0.9, 0.6, 0.3, 0.4) : Qt.rgba(1, 1, 1, 0.08)
                                        Text {
                                            anchors.centerIn: parent
                                            text: world.labPlaceMode === "thermo" ? "placing…" : "place source"
                                            color: "white"
                                            font.pixelSize: 8
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: lab.togglePlaceMode("thermo")
                                        }
                                    }
                                }

                                Text {
                                    visible: lab.thermoOpen
                                    text: (world.thermoSources.length || 0) + " placing · "
                                        + (world.thermoSources.length === 1 ? "1" : world.thermoSources.length) + " in arena · clear"
                                    color: Qt.rgba(0.6, 0.7, 0.7, 1)
                                    font.pixelSize: 8
                                    Text {
                                        text: "clear"
                                        anchors.right: parent.right
                                        color: Qt.rgba(0.9, 0.6, 0.6, 1)
                                        font.pixelSize: 8
                                        MouseArea { anchors.fill: parent; onClicked: { world.clearThermo(); world.refresh() } }
                                    }
                                }
                            }
                        }

                        // -- chemB card --------------------------------------
                        Rectangle {
                            width: parent.width
                            height: lab.chemBOpen ? 128 : 32
                            radius: 10
                            color: Qt.rgba(1, 1, 1, 0.05)
                            border.color: Qt.rgba(0.45, 1, 0.9, 0.18)
                            border.width: 1

                            Column {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 7

                                Row {
                                    width: parent.width
                                    spacing: 6

                                    Text {
                                        text: lab.chemBOpen ? "▾" : "▸"
                                        color: Qt.rgba(0.6, 0.7, 0.7, 1)
                                        font.pixelSize: 9
                                        anchors.verticalCenter: parent.verticalCenter
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: lab.chemBOpen = !lab.chemBOpen
                                        }
                                    }

                                    Text {
                                        text: "🧪 chem-B AWA"
                                        color: "white"
                                        font.pixelSize: 10
                                        font.bold: true
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        text: "synthetic"
                                        color: Qt.rgba(0.9, 0.72, 0.3, 1)
                                        font.pixelSize: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Item { width: parent.parent.width - 210; height: 1 }

                                    Text {
                                        text: lab.chemBOn ? "on" : "off"
                                        color: lab.chemBOn ? "#4dff88" : Qt.rgba(0.6, 0.7, 0.7, 1)
                                        font.pixelSize: 9
                                        font.bold: true
                                        anchors.verticalCenter: parent.verticalCenter
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: { lab.chemBOn = !lab.chemBOn; lab.pushWeights() }
                                        }
                                    }
                                }

                                Text {
                                    visible: lab.chemBOpen
                                    width: parent.width
                                    wrapMode: Text.Wrap
                                    text: "AWAL/AWAR — real chemosensory A; mapping synthetic (charge ∝ gradient)"
                                    color: Qt.rgba(0.65, 0.78, 0.75, 1)
                                    font.pixelSize: 8
                                }

                                Row {
                                    visible: lab.chemBOpen
                                    width: parent.width
                                    spacing: 6

                                    LabSlider {
                                        id: chemBSlider
                                        anchors.verticalCenter: parent.verticalCenter
                                        value: lab.chemBStrength
                                        width: parent.width - 96
                                        showValue: true
                                        onChanged: { lab.chemBStrength = value; lab.pushWeights() }
                                    }

                                    Rectangle {
                                        width: 88
                                        height: 16
                                        radius: 8
                                        color: world.labPlaceMode === "chemB"
                                            ? Qt.rgba(0.35, 0.9, 0.7, 0.4) : Qt.rgba(1, 1, 1, 0.08)
                                        Text {
                                            anchors.centerIn: parent
                                            text: world.labPlaceMode === "chemB" ? "placing…" : "place source"
                                            color: "white"
                                            font.pixelSize: 8
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: lab.togglePlaceMode("chemB")
                                        }
                                    }
                                }

                                Text {
                                    visible: lab.chemBOpen
                                    text: (world.chemBSources.length || 0) + " placing · "
                                        + (world.chemBSources.length === 1 ? "1" : world.chemBSources.length) + " in arena · clear"
                                    color: Qt.rgba(0.6, 0.7, 0.7, 1)
                                    font.pixelSize: 8
                                    Text {
                                        text: "clear"
                                        anchors.right: parent.right
                                        color: Qt.rgba(0.9, 0.6, 0.6, 1)
                                        font.pixelSize: 8
                                        MouseArea { anchors.fill: parent; onClicked: { world.clearChemB(); world.refresh() } }
                                    }
                                }
                            }
                        }

                        // -- tail card ----------------------------------------
                        Rectangle {
                            width: parent.width
                            height: lab.tailOpen ? 150 : 32
                            radius: 10
                            color: Qt.rgba(1, 1, 1, 0.05)
                            border.color: Qt.rgba(0.45, 1, 0.9, 0.18)
                            border.width: 1

                            Column {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 7

                                Row {
                                    width: parent.width
                                    spacing: 6

                                    Text {
                                        text: lab.tailOpen ? "▾" : "▸"
                                        color: Qt.rgba(0.6, 0.7, 0.7, 1)
                                        font.pixelSize: 9
                                        anchors.verticalCenter: parent.verticalCenter
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: lab.tailOpen = !lab.tailOpen
                                        }
                                    }

                                    Text {
                                        text: "🔔 tail-touch PLM"
                                        color: "white"
                                        font.pixelSize: 10
                                        font.bold: true
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        text: "real reflex"
                                        color: Qt.rgba(0.5, 0.85, 0.6, 1)
                                        font.pixelSize: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Item { width: parent.parent.width - 210; height: 1 }

                                    Text {
                                        text: "poke"
                                        color: Qt.rgba(0.7, 1, 0.95, 1)
                                        font.pixelSize: 9
                                        font.bold: true
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                Text {
                                    visible: lab.tailOpen
                                    width: parent.width
                                    wrapMode: Text.Wrap
                                    text: "PLML/PLMR — real tail mechanosensory; the reflex emerges from wiring (PLM→AVA/AS→body muscles)"
                                    color: Qt.rgba(0.65, 0.78, 0.75, 1)
                                    font.pixelSize: 8
                                }

                                Row {
                                    visible: lab.tailOpen
                                    width: parent.width
                                    spacing: 6

                                    Text {
                                        text: "side:"
                                        color: Qt.rgba(0.6, 0.7, 0.7, 1)
                                        font.pixelSize: 9
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Rectangle {
                                        width: 46; height: 20; radius: 6
                                        color: Qt.rgba(1, 1, 1, 0.08)
                                        Text { anchors.centerIn: parent; text: "↰ left"; color: "white"; font.pixelSize: 9 }
                                        MouseArea { anchors.fill: parent; onClicked: lab.pokeTail("left") }
                                    }
                                    Rectangle {
                                        width: 46; height: 20; radius: 6
                                        color: Qt.rgba(1, 1, 1, 0.08)
                                        Text { anchors.centerIn: parent; text: "↱ right"; color: "white"; font.pixelSize: 9 }
                                        MouseArea { anchors.fill: parent; onClicked: lab.pokeTail("right") }
                                    }
                                    Rectangle {
                                        width: 46; height: 20; radius: 6
                                        color: Qt.rgba(1, 1, 1, 0.08)
                                        Text { anchors.centerIn: parent; text: "↕ both"; color: "white"; font.pixelSize: 9 }
                                        MouseArea { anchors.fill: parent; onClicked: lab.pokeTail("none") }
                                    }
                                }

                                Text {
                                    visible: lab.tailOpen
                                    text: "poke = one short charge burst (~0.4 s) on PLML/PLMR"
                                    color: Qt.rgba(0.6, 0.7, 0.7, 1)
                                    font.pixelSize: 8
                                }
                            }
                        }

                        // -- session controls ----------------------------------
                        Row {
                            width: parent.width
                            spacing: 6

                            Rectangle {
                                width: (parent.width - 6) / 2
                                height: 24
                                radius: 8
                                color: lab.running ? Qt.rgba(0.9, 0.45, 0.35, 0.35) : Qt.rgba(0.35, 0.9, 0.55, 0.25)
                                Text {
                                    anchors.centerIn: parent
                                    text: lab.running ? "■ end & restore" : "● restart"
                                    color: "white"
                                    font.pixelSize: 9
                                    font.bold: true
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: lab.running ? lab.endSession() : lab.startSession()
                                }
                            }

                            Rectangle {
                                width: (parent.width - 6) / 2
                                height: 24
                                radius: 8
                                color: Qt.rgba(1, 1, 1, 0.08)
                                Text {
                                    anchors.centerIn: parent
                                    text: "✳ clear sources"
                                    color: Qt.rgba(0.82, 0.9, 0.88, 1)
                                    font.pixelSize: 9
                                    font.bold: true
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: lab.clearStimuli()
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: lab.honestyNote
                            color: Qt.rgba(0.5, 0.62, 0.6, 1)
                            font.pixelSize: 8
                        }
                    }

                    // =================== observation ==========================
                    Column {
                        width: 240
                        spacing: 10

                        Text {
                            text: "observation (live)"
                            color: Qt.rgba(0.82, 0.9, 0.88, 1)
                            font.pixelSize: 12
                            font.bold: true
                        }

                        Row {
                            width: parent.width
                            spacing: 8

                            Column {
                                width: (parent.width - 8) / 2
                                spacing: 2
                                Text { text: "motor L"; color: Qt.rgba(0.6, 0.7, 0.7, 1); font.pixelSize: 8 }
                                Text { text: lab.motorLText; color: "white"; font.pixelSize: 16; font.bold: true }
                            }
                            Column {
                                width: (parent.width - 8) / 2
                                spacing: 2
                                Text { text: "motor R"; color: Qt.rgba(0.6, 0.7, 0.7, 1); font.pixelSize: 8 }
                                Text { text: lab.motorRText; color: "white"; font.pixelSize: 16; font.bold: true }
                            }
                        }

                        Text {
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: lab.liveContext
                            color: Qt.rgba(0.82, 0.9, 0.88, 1)
                            font.pixelSize: 9
                        }

                        Text {
                            text: "fires in the last " + lab.motorSamples + " cycles (real cells)"
                            color: Qt.rgba(0.5, 0.62, 0.6, 1)
                            font.pixelSize: 8
                        }

                        CellRow { title: "🔥 thermo"; count: lab.thermoFires; cells: lab.thermoCells; src: lab.monitor }
                        CellRow { title: "🧪 chem-B"; count: lab.chemBFires; cells: lab.chemBCells; src: lab.monitor }
                        CellRow { title: "🔔 tail"; count: lab.tailFires; cells: lab.tailCells; src: lab.monitor }

                        Rectangle {
                            width: parent.width
                            height: 20
                            radius: 8
                            color: Qt.rgba(1, 1, 1, 0.06)
                            Text {
                                anchors.centerIn: parent
                                text: "motor avg " + (lab.motorSamples ? (lab.motorTotal / lab.motorSamples).toFixed(2) : "0")
                                    + " · peak " + lab.motorPeak.toFixed(2)
                                color: Qt.rgba(0.82, 0.9, 0.88, 1)
                                font.pixelSize: 9
                            }
                        }
                    }

                    // =================== journal =============================
                    Column {
                        width: parent.width - 250 - 240 - parent.spacing * 2
                        spacing: 8

                        Text {
                            text: "experiment journal"
                            color: Qt.rgba(0.82, 0.9, 0.88, 1)
                            font.pixelSize: 12
                            font.bold: true
                        }

                        Text {
                            text: "hypothesis / question"
                            color: Qt.rgba(0.5, 0.62, 0.6, 1)
                            font.pixelSize: 8
                        }
                        Rectangle {
                            width: parent.width
                            height: 36
                            radius: 6
                            color: Qt.rgba(1, 1, 1, 0.05)
                            border.color: Qt.rgba(0.45, 1, 0.9, 0.15)
                            border.width: 1
                            TextEdit {
                                id: hypEdit
                                anchors.fill: parent
                                anchors.margins: 6
                                color: "white"
                                font.pixelSize: 9
                                wrapMode: TextEdit.Wrap
                                selectByMouse: true
                                text: lab.hypothesis
                                onTextChanged: lab.hypothesis = text
                                clip: true
                            }
                        }

                        Text {
                            text: "observation"
                            color: Qt.rgba(0.5, 0.62, 0.6, 1)
                            font.pixelSize: 8
                        }
                        Rectangle {
                            width: parent.width
                            height: 36
                            radius: 6
                            color: Qt.rgba(1, 1, 1, 0.05)
                            border.color: Qt.rgba(0.45, 1, 0.9, 0.15)
                            border.width: 1
                            TextEdit {
                                id: obsEdit
                                anchors.fill: parent
                                anchors.margins: 6
                                color: "white"
                                font.pixelSize: 9
                                wrapMode: TextEdit.Wrap
                                selectByMouse: true
                                text: lab.observation
                                onTextChanged: lab.observation = text
                                clip: true
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 22
                            radius: 6
                            color: Qt.rgba(0.35, 0.9, 0.55, 0.25)
                            Text {
                                anchors.centerIn: parent
                                text: "💾 save experiment"
                                color: "white"
                                font.pixelSize: 9
                                font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: lab.saveExperiment()
                            }
                        }

                        Text {
                            text: journal.entries.length + " recorded · tap entry to re-apply"
                            color: Qt.rgba(0.5, 0.62, 0.6, 1)
                            font.pixelSize: 8
                        }

                        ListView {
                            id: journalList
                            width: parent.width
                            height: 230
                            clip: true
                            spacing: 4
                            model: journal.entries

                            delegate: Rectangle {
                                width: ListView.view.width
                                height: 52
                                radius: 8
                                color: Qt.rgba(1, 1, 1, 0.05)
                                border.color: Qt.rgba(0.45, 1, 0.9, 0.15)
                                border.width: 1

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 7
                                    spacing: 3

                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: "#" + modelData.id + " · " + lab.journalTitle(modelData)
                                        color: "white"
                                        font.pixelSize: 9
                                        font.bold: true
                                    }
                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: lab.journalSummary(modelData)
                                        color: Qt.rgba(0.65, 0.78, 0.75, 1)
                                        font.pixelSize: 8
                                    }
                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: lab.relativeStamp(modelData.date)
                                            + (modelData.results && modelData.results.stateContext
                                                ? " · state: " + modelData.results.stateContext : "")
                                        color: Qt.rgba(0.5, 0.62, 0.6, 1)
                                        font.pixelSize: 8
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: lab.applyConfig(modelData.config)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    function close() {
        lab.closed()
    }
}