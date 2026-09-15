import QtQuick
import "ConnectomeGraph.js" as GraphData

// Phase A Circuit Lab: tune the REAL synapses (absolute weight overrides on
// the live connectome), test presets, and — only if you press "apply to pet" —
// persist the patch set in pet.json so it survives the session.
//
// Honesty contract:
//   - Every patch is an absolute override of a REAL connection in Celegans.js
//     (from-to base weights are introspected at setup, not guessed). Editing a
//     slider or "∓" is a real electrical change to the wiring.
//   - Isolation: while the Circuit is open the brain is snapshotted including
//     the active patch map; closing or ending the session restores both. Only
//     "apply to pet" writes to pet.json, and that is an explicit, labelled act.
//   - The results are what the wiring does: same motor readout as the Live Lab,
//     same journal, same "seeded reproductions" story. Presets are hypotheses,
//     not guarantees — the harness (node experiments/circuit-tuner.js) measures.
Item {
    id: circuit
    visible: false

    property var pet: null
    property var petState: null
    property var monitor: null
    property var brainController: null
    property var journal: null

    signal closed()
    signal toMind()

    // --- session ----------------------------------------------------------
    property bool running: false

    // --- observed results (accumulated only while `running`) ----------------
    property int firesObserved: 0
    property int motorSamples: 0
    property real motorTotal: 0
    property real motorPeak: 0

    property string hypothesis: ""
    property string observation: ""
    property string patchSummary: "0 patches · untouched wiring"
    property string applyFeedback: ""

    // live readouts
    property string motorLText: "0"
    property string motorRText: "0"
    property string liveContext: "waiting for cycles…"
    property int frame: 0

    property bool expanded: false      // browse the full connectome vs the focus pool
    property int maxWeight: 30
    // Synapse search / filter: when non-empty, only rows whose FROM or TO
    // contains the text are shown (case-insensitive). Presets that don't
    // touch a matching cell are dimmed in the bar above.
    property string filterText: ""
    // Display list for the editor: keys of the rows matching the current
    // filter. editorModel stays the master (session edits keep all rows, so
    // hidden synapses are never lost); the view only filters the rendering.
    property var viewKeys: []

    readonly property string honestyNote:
        "Patches override REAL synapses (absolute weight; base = the untouched wiring, introspected from Celegans.js). The session is isolated: ending restores the exact pre-session wiring. Only 'apply to pet' writes to pet.json. Seeded reproductions: node experiments/circuit-tuner.js"

    // Intensional neurons the Circuit normally cares about (behavior-adjacent):
    // sensors -> interneurons -> command + a few muscles.
    readonly property var focusSources: [
        "ADFL", "ADFR", "AFDL", "AFDR", "AWAL", "AWAR",
        "AIYL", "AIYR", "AIZL", "AIZR", "AIBL", "AIBR",
        "RIML", "RIMR", "AVAL", "AVAR", "AVBL", "AVBR",
        "AVEL", "AVER", "AVDL", "AVDR", "SMBVL", "SMBVR",
        "SMBDL", "SMBDR", "SMDDL", "SMDDR", "SMDVL", "SMDVR",
        "PLML", "PLMR", "ALML", "ALMR", "ASHL", "ASHR"
    ]

    readonly property var commandCells: ["AVAL", "AVAR", "AVBL", "AVBR", "RIML", "RIMR"]
    readonly property var interCells: ["AIZL", "AIZR", "AIYL", "AIYR", "AIBL", "AIBR"]

    // Editor rows (all browsed synapses, weight = current live value).
    ListModel {
        id: editorModel
    }

    // Defined presets (hypotheses: tuned REAL weights or brand-new connections;
    // the add/edit feedback tells you which is which — "patched" = real synapse,
    // "NEW" = base 0). The harness measures whether they change behavior.
    property var presets: [
        { "key": "chemotaxis", "label": "chemotaxis ↑", "patches": [
            { from: "ADFL", to: "AIZL", weight: 18 },
            { from: "ADFR", to: "AIZR", weight: 12 },
            { from: "AIZL", to: "SMBDL", weight: 14 },
            { from: "AIZR", to: "SMBDR", weight: 9 },
            { from: "AIZL", to: "SMBVL", weight: 10 },
            { from: "AIZR", to: "SMBVR", weight: 5 }
        ] },
        { "key": "escape", "label": "escape kick", "patches": [
            { from: "PLML", to: "AVDR", weight: 5 },
            { from: "PLMR", to: "AVDL", weight: 5 },
            { from: "AVDR", to: "AVAL", weight: 24 },
            { from: "AVDL", to: "AVAR", weight: 28 }
        ] },
        { "key": "shortcut", "label": "new: chemo shortcut", "patches": [
            { from: "ADFL", to: "SMDVL", weight: 4 },
            { from: "ADFR", to: "SMDVR", weight: 4 },
            { from: "AFDL", to: "SMBVL", weight: 5 },
            { from: "AFDR", to: "SMBVR", weight: 5 }
        ] },
        { "key": "calm", "label": "calm touch", "patches": [
            { from: "ALML", to: "BDUL", weight: 3 },
            { from: "ALMR", to: "BDUR", weight: 3 },
            { from: "ALML", to: "AVDR", weight: 0 },
            { from: "PLMR", to: "AVDR", weight: 0 }
        ] }
    ]

    // --- editors -----------------------------------------------------------
    property var synapseBase: ({})        // [from] -> {to: base}
    property string fromField: ""
    property string toField: ""
    property real newWeight: 10

    function buildBase() {
        var b = {}
        var brain = circuit.brainController ? circuit.brainController.brainInstance : null
        if (!brain || !brain.synapseBase) return
        var names = Object.keys(brain.synapseBase)
        for (var i = 0; i < names.length; i++) {
            var from = names[i]
            var out = {}
            var es = brain.synapseBase[from]
            for (var to in es) out[to] = es[to]
            b[from] = out
        }
        circuit.synapseBase = b
    }

    function poolSources() {
        var names = Object.keys(circuit.synapseBase).sort()
        if (!circuit.expanded) {
            var keep = []
            for (var i = 0; i < circuit.focusSources.length; i++)
                if (names.indexOf(circuit.focusSources[i]) !== -1) keep.push(circuit.focusSources[i])
            return keep
        }
        return names
    }

    function baseOf(from, to) {
        if (circuit.synapseBase[from] && circuit.synapseBase[from][to] !== undefined)
            return circuit.synapseBase[from][to]
        return 0
    }

    function liveWeightOf(from, to) {
        var k = from + ":" + to
        var m = circuit.brainController ? circuit.brainController.circuitPatches : null
        if (m && m[k] !== undefined) return m[k]
        return circuit.baseOf(from, to)
    }

    // --- filtering (view over the master editorModel) ----------------------
    // The list the ListView renders is a key array (`viewKeys`); icons behind
    // the delegate resolve each key back into the master model so filtering
    // never crops edits made on rows that are currently hidden.
    function rebuildView() {
        var keys = []
        var q = String(circuit.filterText || "").toUpperCase()
        for (var i = 0; i < editorModel.count; i++) {
            var r = editorModel.get(i)
            if (q && String(r.from).toUpperCase().indexOf(q) === -1
                && String(r.to).toUpperCase().indexOf(q) === -1) continue
            keys.push(r.key)
        }
        circuit.viewKeys = keys
    }

    function viewIndex(key) {
        for (var i = 0; i < editorModel.count; i++)
            if (editorModel.get(i).key === key) return i
        return -1
    }
    function keyFrom(key) { var i = circuit.viewIndex(key); return i === -1 ? "" : editorModel.get(i).from }
    function keyTo(key) { var i = circuit.viewIndex(key); return i === -1 ? "" : editorModel.get(i).to }
    function keyBase(key) { var i = circuit.viewIndex(key); return i === -1 ? 0 : editorModel.get(i).base }
    function keyWeight(key) { var i = circuit.viewIndex(key); return i === -1 ? 0 : editorModel.get(i).weight }
    function keySetWeight(key, w) {
        var i = circuit.viewIndex(key)
        if (i === -1) return
        editorModel.setProperty(i, "weight", w)
        circuit.sync()
    }
    // A preset is "associated" with a cell when any of its patches touches it
    // (as from or to). Used to dim presets that don't match the filter.
    function presetMatches(patches, q) {
        if (!q) return true
        for (var i = 0; i < patches.length; i++) {
            if (String(patches[i].from).toUpperCase().indexOf(q) !== -1
                || String(patches[i].to).toUpperCase().indexOf(q) !== -1) return true
        }
        return false
    }

    function rebuildList() {
        editorModel.clear()
        var srcs = circuit.poolSources()
        var maxW = 0
        for (var i = 0; i < srcs.length; i++) {
            var from = srcs[i]
            var es = circuit.synapseBase[from]
            var tos = Object.keys(es).sort()
            for (var j = 0; j < tos.length; j++) {
                var to = tos[j]
                var w = circuit.liveWeightOf(from, to)
                if (!isFinite(w)) w = 0
                if (Math.abs(w) > maxW) maxW = Math.abs(w)
                editorModel.append({ "key": from + ":" + to, "from": from, "to": to, "base": es[to], "weight": w })
            }
        }
        circuit.maxWeight = Math.max(12, Math.ceil(maxW / 5) * 5)
        circuit.rebuildView()
        circuit.refreshSummary()
    }

    function activePatchList() {
        var list = []
        for (var i = 0; i < editorModel.count; i++) {
            var r = editorModel.get(i)
            if (r.weight !== r.base) list.push({ from: r.from, to: r.to, weight: r.weight })
        }
        return list
    }

    function sync() {
        if (circuit.brainController) circuit.brainController.setLiveCircuit(circuit.activePatchList())
        circuit.refreshSummary()
    }

    function refreshSummary() {
        var list = circuit.activePatchList()
        if (!list.length) { circuit.patchSummary = "0 patches · untouched wiring"; return }
        var bits = []
        for (var i = 0; i < list.length && i < 5; i++)
            bits.push(list[i].from + "→" + list[i].to + " " + list[i].weight)
        if (list.length > 5) bits.push("+" + (list.length - 5) + " more")
        circuit.patchSummary = list.length + " patch" + (list.length === 1 ? "" : "es")
            + " · " + bits.join(", ")
    }

    // Set (or create) a row in the editor for synapse (from,to) with weight w.
    function setRowWeight(from, to, w) {
        var key = from + ":" + to
        for (var i = 0; i < editorModel.count; i++) {
            if (editorModel.get(i).key === key) {
                editorModel.setProperty(i, "weight", w)
                return
            }
        }
        editorModel.append({ "key": key, "from": from, "to": to, "base": circuit.baseOf(from, to), "weight": w })
    }

    function loadPreset(key) {
        var p = null
        for (var i = 0; i < circuit.presets.length; i++)
            if (circuit.presets[i].key === key) { p = circuit.presets[i]; break }
        if (!p) return
        for (var j = 0; j < p.patches.length; j++) {
            var e = p.patches[j]
            circuit.setRowWeight(e.from, e.to, e.weight)
        }
        circuit.rebuildView()
        circuit.sync()
        circuit.applyFeedback = "preset '" + p.label + "' loaded into the session"
    }

    function addCustomSynapse() {
        var from = String(circuit.fromField || "").trim()
        var to = String(circuit.toField || "").trim()
        if (!from || !to) { circuit.applyFeedback = "need a from and a to cell"; return }
        if (!circuit.synapseBase[from]) { circuit.applyFeedback = "unknown source cell: " + from; return }
        var exists = false
        for (var i = 0; i < editorModel.count; i++) {
            if (editorModel.get(i).to === to) { exists = true; break }
        }
        if (!exists && !circuit.targetIsValid(to)) {
            circuit.applyFeedback = "unknown postsynaptic cell: " + to
            return
        }
        var base = circuit.baseOf(from, to)
        circuit.setRowWeight(from, to, circuit.newWeight)
        circuit.rebuildView()
        circuit.applyFeedback = (base ? "patched " : "NEW synapse ") + from + "→" + to + " = " + circuit.newWeight
        circuit.sync()
    }

    function targetIsValid(to) {
        var brain = circuit.brainController ? circuit.brainController.brainInstance : null
        if (brain && brain.postSynaptic && brain.postSynaptic[to]) return true
        return false
    }

    function clearAll() {
        for (var i = 0; i < editorModel.count; i++) {
            var r = editorModel.get(i)
            editorModel.setProperty(i, "weight", r.base)
        }
        circuit.sync()
        circuit.applyFeedback = "all patches cleared in session"
    }

    // --- session lifecycle ---------------------------------------------------
    function startSession() {
        if (circuit.running) return
        if (circuit.monitor && (!circuit.monitor.charges || !circuit.monitor.charges.length)) {
            if (typeof circuit.monitor.init === "function") circuit.monitor.init()
        }
        if (circuit.brainController && typeof circuit.brainController.snapshotBrain === "function")
            circuit.brainController.snapshotBrain()
        circuit.firesObserved = 0
        circuit.motorSamples = 0
        circuit.motorTotal = 0
        circuit.motorPeak = 0
        if (circuit.brainController) circuit.brainController.circuitSessionActive = true
        circuit.running = true
        circuit.applyFeedback = ""
    }

    function endSession() {
        if (circuit.brainController) circuit.brainController.circuitSessionActive = false
        circuit.running = false
        if (circuit.brainController && typeof circuit.brainController.restoreBrain === "function")
            circuit.brainController.restoreBrain()
        // Rebuild the editor from the restored wiring so the window reflects
        // EXACTLY what the pet now runs (reverts to the applied/persisted
        // values, or to base if nothing was applied).
        circuit.rebuildList()
        circuit.applyFeedback = "session ended · wiring and editor restored from snapshot"
        Qt.callLater(function () { circuit.applyFeedback = "" })
    }

    // Explicit persistence: the ONLY path that writes to pet.json.
    function applyToPet() {
        if (!circuit.petState || !circuit.running) return
        var list = circuit.activePatchList()
        circuit.petState.setCircuit(list)
        if (circuit.brainController && typeof circuit.brainController.commitCircuitSession === "function")
            circuit.brainController.commitCircuitSession()
        circuit.applyFeedback = "⚡ applied to pet (" + list.length + " patches) · survives this session"
    }

    // --- observation ----------------------------------------------------------
    Connections {
        target: circuit.monitor
        enabled: circuit.running && circuit.monitor !== null
        function onSampled() { circuit.tick() }
    }

    function tick() {
        if (!circuit.running || !circuit.brainController) return
        var m = circuit.monitor
        if (m && m.fired && m.fired.length) {
            var i
            var set = circuit.commandCells.concat(circuit.interCells)
            for (i = 0; i < set.length; i++) {
                var idx = GraphData.graphNodes().indexOf(set[i])
                if (idx !== -1 && m.fired[idx]) circuit.firesObserved++
            }
        }
        var mag = (Math.abs(circuit.brainController.leftMotor) || 0)
            + (Math.abs(circuit.brainController.rightMotor) || 0)
        circuit.motorTotal += mag
        circuit.motorSamples++
        if (mag > circuit.motorPeak) circuit.motorPeak = mag
    }

    // --- journal ---------------------------------------------------------------
    function configSnapshot() {
        return { "patches": circuit.activePatchList(), "count": circuit.activePatchList().length,
                 "applied": circuit.petState ? (circuit.petState.circuit || []).length : 0 }
    }

    function resultsSnapshot() {
        return {
            "stateContext": circuit.pet ? circuit.pet.stateLabel : "",
            "cyclesObserved": circuit.motorSamples,
            "commandFires": circuit.firesObserved,
            "motorAvg": circuit.motorSamples ? (circuit.motorTotal / circuit.motorSamples).toFixed(2) : "0",
            "motorPeak": circuit.motorPeak.toFixed(2)
        }
    }

    function saveExperiment() {
        circuit.journal.add({
            "type": "circuit",
            "hypothesis": circuit.hypothesis,
            "config": circuit.configSnapshot(),
            "results": circuit.resultsSnapshot(),
            "observation": circuit.observation
        })
        circuit.observation = ""
        obsEdit.text = ""
    }

    // Re-apply a saved circuit entry's patch set (reproducibility).
    function applyConfig(cfg) {
        if (!cfg || !cfg.patches || !cfg.patches.length) return
        circuit.buildBase()
        circuit.rebuildList()
        for (var i = 0; i < cfg.patches.length; i++) {
            var e = cfg.patches[i]
            if (e && e.from && e.to && typeof e.weight === "number")
                circuit.setRowWeight(e.from, e.to, e.weight)
        }
        circuit.sync()
    }

    onVisibleChanged: {
        if (circuit.visible) {
            circuit.buildBase()
            circuit.rebuildList()
            circuit.startSession()
        } else if (circuit.running) {
            circuit.endSession()
        }
    }

    // --- journal presentation helpers --------------------------------------------
    function journalTitle(e) {
        var n = (e.config && e.config.count) ? e.config.count : 0
        return "🧬 " + n + " patches" + (e.hypothesis ? " — " + e.hypothesis : "")
    }
    function journalSummary(e) {
        var bits = []
        if (e.config && e.config.count) bits.push(e.config.count + " patches")
        if (e.results) {
            if (Number(e.results.commandFires)) bits.push(e.results.commandFires + " fires")
            bits.push("motor∅" + e.results.motorAvg)
        }
        return bits.join(" · ") || (e.observation || "recorded")
    }
    function relativeStamp(t) {
        var s = Math.floor((Date.now() - t) / 1000)
        if (s < 10) return "just now"
        if (s < 60) return s + "s ago"
        var m = Math.floor(s / 60)
        if (m < 60) return m + "m ago"
        return Math.floor(m / 60) + "h ago"
    }

    // --- chrome ---------------------------------------------------------------------
    Rectangle {
        id: bg
        anchors.fill: parent
        radius: 14
        color: Qt.rgba(0.06, 0.08, 0.11, 0.97)
        border.color: Qt.rgba(0.9, 0.75, 1, 0.28)
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
                        text: "🧬 " + (pet ? pet.petName : "?") + " · circuit lab"
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
                        color: circuit.running ? Qt.rgba(0.65, 0.55, 0.95, 0.22) : Qt.rgba(0.6, 0.6, 0.6, 0.18)
                        border.color: circuit.running ? Qt.rgba(0.8, 0.7, 1, 0.45) : Qt.rgba(0.6, 0.6, 0.6, 0.3)
                        border.width: 1

                        Text {
                            id: runText
                            anchors.centerIn: parent
                            text: circuit.running ? "● editing wiring" : "◦ idle"
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
                        text: "real synapses · edit a weight, watch the worm react"
                        color: Qt.rgba(0.9, 0.85, 0.94, 1)
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
                            onClicked: circuit.toMind()
                        }
                    }

                    Text {
                        id: closeBtn
                        text: "✕"
                        anchors.verticalCenter: parent.verticalCenter
                        color: Qt.rgba(0.9, 0.85, 0.94, 1)
                        font.pixelSize: 16
                        MouseArea {
                            anchors.fill: parent
                            onClicked: circuit.close()
                        }
                    }
                }

                Row {
                    width: parent.width
                    spacing: 14

                    // =================== synapse editor ============================
                    Column {
                        width: 340
                        spacing: 10

                        Row {
                            width: parent.width
                            spacing: 6

                            Text {
                                text: "synapse editor"
                                color: Qt.rgba(0.9, 0.85, 0.94, 1)
                                font.pixelSize: 12
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Rectangle {
                                width: 64
                                height: 18
                                radius: 9
                                color: Qt.rgba(0.7, 0.6, 0.95, 0.22)
                                Text {
                                    anchors.centerIn: parent
                                    text: circuit.expanded ? "⋮ all cells" : "focus pool"
                                    color: "white"
                                    font.pixelSize: 8
                                    font.bold: true
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: { circuit.expanded = !circuit.expanded; circuit.rebuildList() }
                                }
                            }

                            Item { width: Math.max(1, parent.parent.width - 180); height: 1 }

                            Text {
                                text: circuit.viewKeys.length + " / " + editorModel.count + " synapses"
                                color: Qt.rgba(0.7, 0.7, 0.75, 1)
                                font.pixelSize: 8
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        // synapse filter: type a cell name to narrow the list
                        // (and dim presets that don't touch it).
                        CircuitField {
                            width: parent.width
                            height: 22
                            placeholder: "filter: neuron (e.g. ADFL)"
                            value: circuit.filterText
                            onEdited: function(v) { circuit.filterText = v; circuit.rebuildView() }
                        }

                        // presets
                        Flow {
                            width: parent.width
                            spacing: 5

                            Repeater {
                                model: circuit.presets
                                delegate: Rectangle {
                                    implicitHeight: 20
                                    implicitWidth: presetTxt.implicitWidth + 12
                                    radius: 8
                                    color: Qt.rgba(0.55, 0.45, 0.9, 0.2)
                                    border.color: Qt.rgba(0.8, 0.7, 1, 0.4)
                                    border.width: 1
                                    // Dim presets whose patches don't touch the
                                    // current filter: shows at a glance which
                                    // presets are relevant.
                                    opacity: circuit.presetMatches(modelData.patches,
                                        String(circuit.filterText).toUpperCase()) ? 1 : 0.3

                                    Text {
                                        id: presetTxt
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        color: "white"
                                        font.pixelSize: 9
                                        font.bold: true
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: circuit.loadPreset(modelData.key)
                                    }
                                }
                            }
                        }

                        // summary + clear
                        Row {
                            width: parent.width
                            spacing: 6

                            Text {
                                width: parent.width - 70
                                elide: Text.ElideRight
                                text: circuit.patchSummary
                                color: Qt.rgba(0.75, 0.8, 0.85, 1)
                                font.pixelSize: 8
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: "✳ clear"
                                color: Qt.rgba(0.9, 0.6, 0.6, 1)
                                font.pixelSize: 9
                                anchors.verticalCenter: parent.verticalCenter
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: circuit.clearAll()
                                }
                            }
                        }

                        // editable synapses
                        Rectangle {
                            width: parent.width
                            height: 330
                            radius: 10
                            color: Qt.rgba(1, 1, 1, 0.04)
                            border.color: Qt.rgba(0.9, 0.75, 1, 0.15)
                            border.width: 1
                            clip: true

                            ListView {
                                id: editorList
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 3
                                clip: true
                                // Master list stays in editorModel (session
                                // edits are never lost on hidden rows); the
                                // visible list is the filtered key array.
                                model: circuit.viewKeys

                                delegate: SynapseRow {
                                    width: ListView.view.width
                                    from: circuit.keyFrom(modelData)
                                    to: circuit.keyTo(modelData)
                                    base: circuit.keyBase(modelData)
                                    weight: circuit.keyWeight(modelData)
                                    maxWeight: circuit.maxWeight
                                    live: circuit.keyWeight(modelData) !== circuit.keyBase(modelData)
                                    onChanged: circuit.keySetWeight(modelData, w)
                                    onRemove: circuit.keySetWeight(modelData, circuit.keyBase(modelData))
                                }

                                Text {
                                    visible: editorList.count === 0
                                    anchors.centerIn: parent
                                    text: "no synapses to edit"
                                    color: Qt.rgba(0.6, 0.7, 0.7, 1)
                                    font.pixelSize: 9
                                }
                            }
                        }

                        // add custom synapse
                        Column {
                            width: parent.width
                            spacing: 4

                            Text {
                                text: "create a (new) connection"
                                color: Qt.rgba(0.7, 0.7, 0.75, 1)
                                font.pixelSize: 9
                                font.bold: true
                            }

                            Row {
                                width: parent.width
                                spacing: 5

CircuitField {
                                  id: fromEdit
                                  width: (parent.width - 10) / 2
                                  height: 22
                                  placeholder: "from cell (ADFL)"
                                  value: circuit.fromField
                                  onEdited: function(v) { circuit.fromField = v }
                                }
                                CircuitField {
                                  id: toEdit
                                  width: (parent.width - 10) / 2
                                  height: 22
                                  placeholder: "to cell (SMDVL)"
                                  value: circuit.toField
                                  onEdited: function(v) { circuit.toField = v }
                                }
                            }

                            Row {
                                width: parent.width
                                spacing: 5

                                WeightSlider {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 100
                                    value: circuit.newWeight / 40
                                    onChangedValue: circuit.newWeight = Math.round(v * 40)
                                }

                                Text {
                                    text: "weight " + circuit.newWeight
                                    color: Qt.rgba(0.8, 0.75, 0.9, 1)
                                    font.pixelSize: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Rectangle {
                                    width: 48
                                    height: 20
                                    radius: 6
                                    color: Qt.rgba(0.65, 0.55, 0.95, 0.25)
                                    Text {
                                        anchors.centerIn: parent
                                        text: "add"
                                        color: "white"
                                        font.pixelSize: 9
                                        font.bold: true
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: circuit.addCustomSynapse()
                                    }
                                }
                            }

                            Text {
                                width: parent.width
                                wrapMode: Text.Wrap
                                text: circuit.applyFeedback
                                color: Qt.rgba(0.85, 0.8, 0.95, 1)
                                font.pixelSize: 8
                            }
                        }

                        Text {
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: circuit.honestyNote
                            color: Qt.rgba(0.55, 0.55, 0.6, 1)
                            font.pixelSize: 8
                        }
                    }

                    // =================== observation ==========================
                    Column {
                        width: 240
                        spacing: 10

                        Text {
                            text: "observation (live)"
                            color: Qt.rgba(0.9, 0.85, 0.94, 1)
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
                                Text { text: circuit.motorLText; color: "white"; font.pixelSize: 16; font.bold: true }
                            }
                            Column {
                                width: (parent.width - 8) / 2
                                spacing: 2
                                Text { text: "motor R"; color: Qt.rgba(0.6, 0.7, 0.7, 1); font.pixelSize: 8 }
                                Text { text: circuit.motorRText; color: "white"; font.pixelSize: 16; font.bold: true }
                            }
                        }

                        Text {
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: circuit.liveContext
                            color: Qt.rgba(0.9, 0.85, 0.94, 1)
                            font.pixelSize: 9
                        }

                        Text {
                            text: "fires in the last " + circuit.motorSamples + " cycles (command/inter)"
                            color: Qt.rgba(0.6, 0.6, 0.65, 1)
                            font.pixelSize: 8
                        }

                        CellRow { title: "🕹 command"; count: circuit.firesObserved; cells: circuit.commandCells; src: circuit.monitor }
                        CellRow { title: "🧭 inter"; count: circuit.firesObserved; cells: circuit.interCells; src: circuit.monitor }

                        Text {
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: "baseline = the wiring with NO patches. What you change moves the real connectome; the harness judges the rest."
                            color: Qt.rgba(0.55, 0.55, 0.6, 1)
                            font.pixelSize: 8
                        }

                        Rectangle {
                            width: parent.width
                            height: 20
                            radius: 8
                            color: Qt.rgba(1, 1, 1, 0.06)
                            Text {
                                anchors.centerIn: parent
                                text: "motor avg " + (circuit.motorSamples ? (circuit.motorTotal / circuit.motorSamples).toFixed(2) : "0")
                                    + " · peak " + circuit.motorPeak.toFixed(2)
                                color: Qt.rgba(0.9, 0.85, 0.94, 1)
                                font.pixelSize: 9
                            }
                        }
                    }

                    // =================== journal + session =====================
                    Column {
                        width: parent.width - 340 - 240 - parent.spacing * 2
                        spacing: 8

                        Text {
                            text: "experiment journal"
                            color: Qt.rgba(0.9, 0.85, 0.94, 1)
                            font.pixelSize: 12
                            font.bold: true
                        }

                        // session controls
                        Row {
                            width: parent.width
                            spacing: 6

                            Rectangle {
                                width: (parent.width - 6) * 0.45
                                height: 26
                                radius: 8
                                color: circuit.running ? Qt.rgba(0.9, 0.45, 0.35, 0.3) : Qt.rgba(0.55, 0.45, 0.9, 0.25)
                                Text {
                                    anchors.centerIn: parent
                                    text: circuit.running ? "■ end & restore" : "● start session"
                                    color: "white"
                                    font.pixelSize: 9
                                    font.bold: true
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: circuit.running ? circuit.endSession() : circuit.startSession()
                                }
                            }

                            Rectangle {
                                width: (parent.width - 6) * 0.55
                                height: 26
                                radius: 8
                                color: Qt.rgba(0.35, 0.85, 0.6, 0.28)
                                border.color: Qt.rgba(0.5, 1, 0.75, 0.45)
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text: "⚡ apply to pet"
                                    color: "white"
                                    font.pixelSize: 9
                                    font.bold: true
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: circuit.running
                                    onClicked: circuit.applyToPet()
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: "apply to pet = the only write to pet.json; the patch set then survives sessions, reloads and restarts. Anything else is restored on close."
                            color: Qt.rgba(0.55, 0.55, 0.6, 1)
                            font.pixelSize: 8
                        }

                        Text {
                            text: "hypothesis / question"
                            color: Qt.rgba(0.6, 0.6, 0.65, 1)
                            font.pixelSize: 8
                        }
                        Rectangle {
                            width: parent.width
                            height: 36
                            radius: 6
                            color: Qt.rgba(1, 1, 1, 0.05)
                            border.color: Qt.rgba(0.9, 0.75, 1, 0.15)
                            border.width: 1
                            TextEdit {
                                id: hypEdit
                                anchors.fill: parent
                                anchors.margins: 6
                                color: "white"
                                font.pixelSize: 9
                                wrapMode: TextEdit.Wrap
                                selectByMouse: true
                                text: circuit.hypothesis
                                onTextChanged: circuit.hypothesis = text
                                clip: true
                            }
                        }

                        Text {
                            text: "observation"
                            color: Qt.rgba(0.6, 0.6, 0.65, 1)
                            font.pixelSize: 8
                        }
                        Rectangle {
                            width: parent.width
                            height: 36
                            radius: 6
                            color: Qt.rgba(1, 1, 1, 0.05)
                            border.color: Qt.rgba(0.9, 0.75, 1, 0.15)
                            border.width: 1
                            TextEdit {
                                id: obsEdit
                                anchors.fill: parent
                                anchors.margins: 6
                                color: "white"
                                font.pixelSize: 9
                                wrapMode: TextEdit.Wrap
                                selectByMouse: true
                                text: circuit.observation
                                onTextChanged: circuit.observation = text
                                clip: true
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 22
                            radius: 6
                            color: Qt.rgba(0.55, 0.45, 0.9, 0.25)
                            Text {
                                anchors.centerIn: parent
                                text: "💾 save experiment"
                                color: "white"
                                font.pixelSize: 9
                                font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: circuit.saveExperiment()
                            }
                        }

                        Text {
                            text: journal.entries.length + " recorded · ↺ re-apply · 🗑 delete"
                            color: Qt.rgba(0.6, 0.6, 0.65, 1)
                            font.pixelSize: 8
                        }

                        ListView {
                            id: journalList
                            width: parent.width
                            height: 210
                            clip: true
                            spacing: 4
                            model: journal.entries

                            delegate: Rectangle {
                                width: ListView.view.width
                                height: 52
                                radius: 8
                                color: Qt.rgba(1, 1, 1, 0.05)
                                border.color: Qt.rgba(0.9, 0.75, 1, 0.15)
                                border.width: 1

                                Column {
                                    anchors.fill: parent
                                    anchors.leftMargin: 7
                                    anchors.topMargin: 7
                                    anchors.bottomMargin: 7
                                    anchors.rightMargin: 40
                                    spacing: 3

                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: "#" + modelData.id + " · " + circuit.journalTitle(modelData)
                                        color: "white"
                                        font.pixelSize: 9
                                        font.bold: true
                                    }
                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: circuit.journalSummary(modelData)
                                        color: Qt.rgba(0.8, 0.78, 0.85, 1)
                                        font.pixelSize: 8
                                    }
                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: circuit.relativeStamp(modelData.date)
                                            + (modelData.results && modelData.results.stateContext
                                                ? " · state: " + modelData.results.stateContext : "")
                                        color: Qt.rgba(0.6, 0.6, 0.65, 1)
                                        font.pixelSize: 8
                                    }
                                }

                                // explicit re-apply / delete actions (the whole
                                // row also re-applies on click for muscle memory);
                                // declared AFTER the row MouseArea so they sit on
                                // top and win the hit test.
                                Column {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 5
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 3

                                    Rectangle {
                                        width: 30; height: 16; radius: 4
                                        color: Qt.rgba(0.55, 0.45, 0.9, 0.25)
                                        Text { anchors.centerIn: parent; text: "↺"; color: "white"; font.pixelSize: 9 }
                                        MouseArea { anchors.fill: parent; onClicked: circuit.applyConfig(modelData.config) }
                                    }
                                    Rectangle {
                                        width: 30; height: 16; radius: 4
                                        color: Qt.rgba(0.9, 0.45, 0.35, 0.22)
                                        Text { anchors.centerIn: parent; text: "🗑"; color: "white"; font.pixelSize: 9 }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                if (circuit.journal && typeof circuit.journal.remove === "function")
                                                    circuit.journal.remove(modelData.id)
                                            }
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: circuit.applyConfig(modelData.config)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Timer {
        interval: 100
        running: circuit.visible
        repeat: true
        onTriggered: {
            circuit.frame++
            circuit.motorLText = circuit.brainController ? Math.abs(circuit.brainController.leftMotor).toFixed(1) : "0"
            circuit.motorRText = circuit.brainController ? Math.abs(circuit.brainController.rightMotor).toFixed(1) : "0"
            circuit.liveContext = circuit.pet
                ? circuit.pet.stateLabelText + " — " + circuit.pet.mindSummary() : "waiting…"
        }
    }

    function close() {
        circuit.closed()
    }
}