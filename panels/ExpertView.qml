import QtQuick
import "ConnectomeGraph.js" as GraphData

// Expert View (F4): a read-only window into the live connectome, tied to the
// F3-derived behavior.
//
//    what you see                        what it really is in the model
//    grid cell brightness  = accumulated synaptic charge postSynaptic[n][state],
//                            normalized by the firing threshold (continuous)
//    white rim             = the neuron fired on the last cycle (real)
//    teal frame            = high recent activity (monitor's decaying buffer)
//    circuit graph         = REAL nodes/edges parsed from Celegans.js, laid out
//                            in layers (sources -> interneurons -> muscles)
//    sparklines / bars     = sums of charge over curated sets (labelled "derived")
//
// Everything is read-only: nothing here writes into the simulation. The
// monitor samples the connectome only while this view is open.
Item {
    id: expert
    visible: false

    property var pet: null
    property var monitor: null
    property string selectedNode: ""
    property string hoverNode: ""

    readonly property int gridCell: 12
    readonly property int gridGap: 2
    property int gridCols: 34
    property int gridRows: 14
    property int graphCount: 0

    // frame counter: recompute/repaint once per connectome cycle while open
    property int frame: 0

    property var groupColors: {
        "chemosensation": [0.21, 0.82, 0.67],
        "mechanosensation": [0.88, 0.64, 0.23],
        "feeding": [0.81, 0.36, 0.82],
        "arousal": [0.48, 0.56, 0.88],
        "environment": [0.44, 0.78, 0.42],
        "locomotion": [0.35, 0.72, 0.88],
        "motor": [0.88, 0.42, 0.35],
        "other": [0.33, 0.38, 0.42]
    }

    // F3 state -> the real circuit worth watching (drives the active circuit)
    property var stateToCircuit: {
        "hunting": "chemosensation", "hungry": "chemosensation",
        "exploring": "chemosensation", "grumpy": "mechanosensation",
        "sleeping": "arousal", "resting": "locomotion", "full": "locomotion"
    }
    property var activeChain: ({})
    property var chainLayout: ({ "pos": {}, "maxX": 1, "nodeCount": 0 })
    property string contextKey: ""
    property int lastFiredTotal: 0
    property int lastAvgCharge: 0

    signal closed()

Component.onCompleted: {
        try {
            var gd = GraphData.graphNodes()
            expert.graphCount = gd.length
            gridCols = 34
            gridRows = Math.max(1, Math.ceil(gd.length / gridCols))
        } catch (e) {
            gridRows = 14
        }
        refreshChain()
    }

    function contextName() {
        var key = stateToCircuit[pet ? pet.stateLabel : ""]
        return key === "arousal" ? "locomotion" : (key || "locomotion")
    }

    // Pick the real chain for the current behavior (BFS edges, built in the
    // monitor). Only re-layouts when the behavior context changes.
    function refreshChain() {
        var key = contextName()
        if (key === contextKey) return
        contextKey = key
        activeChain = key === "chemosensation" ? monitor.chainChemo
            : key === "mechanosensation" ? monitor.chainTouch
            : monitor.chainLocomotion
        if (!activeChain.nodes) {
            chainLayout = { "pos": {}, "maxX": 1, "nodeCount": 0 }
            return
        }
        chainLayout = computeChainLayout(activeChain)
    }

    // Layout: x = BFS layer (sources left, muscles right), y spread per layer.
    function computeChainLayout(chain) {
        var layers = []
        var i
        for (i = 0; i < chain.nodes.length; i++) {
            var n = chain.nodes[i]
            var lv = chain.layer[n]
            if (!layers[lv]) layers[lv] = []
            layers[lv].push(n)
        }
        var pos = {}
        for (i = 0; i < layers.length; i++) {
            var row = layers[i]
            for (var j = 0; j < row.length; j++)
                pos[row[j]] = { "x": i, "y": row.length === 1 ? 0.5 : j / (row.length - 1) }
        }
        return { "pos": pos, "maxX": layers.length, "nodeCount": chain.nodes.length }
    }

    // ---- honest helpers ------------------------------------------------
    function nodeIdx(name) { return GraphData.graphNodes().indexOf(name) }
    function chargeOf(name) { var i = nodeIdx(name); return i === -1 ? 0 : (monitor.charges[i] || 0) }
    function firedOf(name) { var i = nodeIdx(name); return i !== -1 && monitor.fired[i] }
    function recentOf(name) { var i = nodeIdx(name); return i === -1 ? 0 : (monitor.recent[i] || 0) }

    function nodeColor(group, intensity, alpha) {
        var c = groupColors[group] || groupColors.other
        var r = c[0] + (1 - c[0]) * intensity
        var g = c[1] + (1 - c[1]) * intensity
        var b = c[2] + (1 - c[2]) * intensity
        return Qt.rgba(r, g, b, alpha)
    }

    function shortGroupName(n) {
        if (n === "chemosensation") return "chemosensation"
        if (n === "mechanosensation") return "touch"
        if (n === "locomotion") return "motor"
        if (n === "feeding") return "feeding"
        if (n === "arousal") return "arousal"
        return n
    }

    // Inspector text for the selection (or hover). All numbers are real.
    function inspectorText() {
        var name = selectedNode || hoverNode
        if (!name) return "Select a neuron in the grid or circuit to inspect it."
        var i = nodeIdx(name)
        if (i === -1) return ""
        var lines = []
        lines.push("◆ " + name.toUpperCase())
        var role = GraphData.graphRoleOf()[name]
        lines.push(role ? ("· " + role + "  ·  " + (GraphData.graphCircuitOf()[name] || GraphData.graphGroupOf()[name]))
                        : ("· " + (GraphData.graphCircuitOf()[name] || GraphData.graphGroupOf()[name]) + " · not annotated"))
        var isMuscle = GraphData.graphMuscleList().indexOf(name) !== -1
        lines.push("· charge " + (monitor.charges[i] || 0).toFixed(2) + " / 1"
            + (isMuscle ? "  ·  " + (GraphData.graphmLeft().indexOf(name) !== -1 ? "left" : "right") + " muscle" : ""))
        lines.push("· fired last cycle " + (monitor.fired[i] ? "yes" : "no")
            + "  ·  recent " + (monitor.recent[i] || 0).toFixed(2)
            + "  ·  idle " + (monitor.idleCycles[i] || 0) + " cycles")
        var outs = GraphData.graphAdj()[name]
        if (outs && outs.length) {
            var o = []
            for (var j = 0; j < Math.min(4, outs.length); j++) o.push(outs[j][0] + " (" + outs[j][1] + ")")
            lines.push("· connects to: " + o.join(", "))
        }
        var ins = monitor.reverseAdj[name]
        if (ins && ins.length) {
            var iv = []
            for (j = 0; j < Math.min(4, ins.length); j++) iv.push(ins[j][0] + " (" + ins[j][1] + ")")
            lines.push("· receives from: " + iv.join(", "))
        }
        return lines.join("\n")
    }

    // ---- chrome ----------------------------------------------------------
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

                // ---- header: F3 chip + context + close --------------------
                Row {
                    width: parent.width
                    height: 26
                    spacing: 8

                    Text {
                        id: titleTxt
                        text: "🧠 " + (pet ? pet.petName : "?") + " · expert view"
                        color: "white"
                        font.pixelSize: 17
                        font.bold: true
                    }

                    Rectangle {
                        id: ctxChip
                        height: 24
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: ctxText.width + 14
                        radius: 9
                        color: Qt.rgba(0.18, 0.8, 0.75, 0.22)
                        border.color: Qt.rgba(0.45, 1, 0.9, 0.4)
                        border.width: 1

                        Text {
                            id: ctxText
                            anchors.centerIn: parent
                            text: pet ? pet.stateLabelText : ""
                            color: "white"
                            font.pixelSize: 12
                            font.bold: true
                        }
                    }

                    Text {
                        width: parent.width - titleTxt.implicitWidth
                            - ctxChip.implicitWidth - closeBtn.implicitWidth - 34
                        height: 24
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: "watching the " + (expert.contextKey === "mechanosensation" ? "touch"
                            : expert.contextKey === "chemosensation" ? "chemosensation" : "motor order from " + (pet ? pet.petName : "the pet"))
                            + " circuit — " + (pet ? pet.mindSummary() : "")
                        color: Qt.rgba(0.82, 0.9, 0.88, 1)
                        font.pixelSize: 12
                    }

                    Text {
                        id: closeBtn
                        text: "✕"
                        anchors.verticalCenter: parent.verticalCenter
                        color: Qt.rgba(0.82, 0.9, 0.88, 1)
                        font.pixelSize: 16
                        MouseArea {
                            anchors.fill: parent
                            onClicked: expert.close()
                        }
                    }
                }

                // ---- signals + timeline (derived, honest) -------------------
                Row {
                    width: parent.width
                    spacing: 10

                    Repeater {
                        model: expert.monitor ? expert.monitor.groupNames : []
                        delegate: Column {
                            width: (parent.width - parent.spacing * 4) / 5
                            spacing: 3

                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: expert.shortGroupName(modelData)
                                color: Qt.rgba(0.82, 0.9, 0.88, 1)
                                font.pixelSize: 10
                            }

                            Canvas {
                                id: spark
                                width: parent.width
                                height: 28

                                Connections {
                                    target: expert
                                    function onFrameChanged() { spark.requestPaint() }
                                }

                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)
                                    var w = width, h = height
                                    var line = expert.monitor ? expert.monitor.historyLine(model.index) : []
                                    if (!line.length) return
                                    var seg = Math.max(1, Math.round(line.length / w))
                                    for (var i = 0; i < w; i++) {
                                        var v = 0
                                        for (var j = 0; j < seg; j++) {
                                            var idx = line.length - 1 - Math.floor(i * seg) - j
                                            if (idx >= 0 && line[idx] > v) v = line[idx]
                                        }
                                        var barH = Math.max(1, v * (h - 2))
                                        ctx.fillStyle = Qt.rgba(0.3, 1, 0.9, 0.3 + 0.6 * v)
                                        ctx.fillRect(i, h - barH, 1, barH)
                                    }
                                }
                            }

                            Rectangle {
                                width: parent.width
                                height: 5
                                radius: 2
                                color: Qt.rgba(1, 1, 1, 0.12)
                                Rectangle {
                                    width: parent.width * Math.max(0, Math.min(1,
                                        expert.monitor ? expert.monitor.groupWeights[model.index] : 0))
                                    height: parent.height
                                    radius: 2
                                    color: "#35d0ac"
                                }
                            }

                            Text {
                                text: "derived 0–1"
                                color: Qt.rgba(0.55, 0.65, 0.65, 1)
                                font.pixelSize: 9
                            }
                        }
                    }
                }

                // ---- main row: neuron matrix + circuit/inspector ------------
                Row {
                    width: parent.width
                    spacing: 14

                    // --- neuron matrix (grid) --------------------------------
                    Column {
                        width: expert.gridCols * (expert.gridCell + expert.gridGap)
                        spacing: 10

                        Text {
                            text: "neuron matrix · " + expert.graphCount + " cells"
                            color: Qt.rgba(0.82, 0.9, 0.88, 1)
                            font.pixelSize: 12
                            font.bold: true
                        }

                        Canvas {
                            id: grid
                            width: expert.gridCols * (expert.gridCell + expert.gridGap)
                            height: expert.gridRows * (expert.gridCell + expert.gridGap)

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onMouseXChanged: if (containsMouse) grid.updateHover(mouseX, mouseY)
                                onMouseYChanged: if (containsMouse) grid.updateHover(mouseX, mouseY)
                                onExited: expert.hoverNode = ""
                                onClicked: expert.selectedNode = grid.nodeAt(mouseX, mouseY)
                            }

                            Connections {
                                target: expert
                                function onFrameChanged() { grid.requestPaint() }
                            }

                            function cellColor(i) {
                                var ch = expert.monitor ? (expert.monitor.charges[i] || 0) : 0
                                if (ch < 0.0001) return Qt.rgba(0.1, 0.12, 0.15, 0.8)
                                return expert.nodeColor(GraphData.graphGroupOf()[GraphData.graphNodes()[i]], ch, 0.9)
                            }

                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                var cs = expert.gridCell, gp = expert.gridGap
                                var n = expert.graphCount
                                if (!n) return
                                for (var i = 0; i < n; i++) {
                                    var x = (i % expert.gridCols) * (cs + gp)
                                    var y = Math.floor(i / expert.gridCols) * (cs + gp)
                                    ctx.fillStyle = cellColor(i)
                                    ctx.fillRect(x + 1, y + 1, cs - 2, cs - 2)
                                    if (expert.monitor && expert.monitor.fired[i]) {
                                        ctx.strokeStyle = "white"
                                        ctx.lineWidth = 1.5
                                        ctx.strokeRect(x + 1, y + 1, cs - 2, cs - 2)
                                    } else if (expert.recentOf(GraphData.graphNodes()[i]) > 0.35) {
                                        ctx.strokeStyle = Qt.rgba(0.3, 1, 0.9, 0.8)
                                        ctx.lineWidth = 1
                                        ctx.strokeRect(x + 1, y + 1, cs - 2, cs - 2)
                                    }
                                }
                            }

                            function nodeAt(mx, my) {
                                var step = expert.gridCell + expert.gridGap
                                var col = Math.floor(mx / step)
                                var row = Math.floor(my / step)
                                if (col < 0 || row < 0) return ""
                                var i = row * expert.gridCols + col
                                if (i >= 0 && i < GraphData.graphNodes().length) return GraphData.graphNodes()[i]
                                return ""
                            }
                            function updateHover(mx, my) {
                                expert.hoverNode = nodeAt(mx, my)
                            }
                        }

                        // legend (honest)
                        Row {
                            width: parent.width
                            spacing: 8

                            Rectangle {
                                width: 13; height: 13; radius: 2
                                color: expert.nodeColor("chemosensation", 0.9, 0.9)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "charge (acc. input / threshold)"
                                color: Qt.rgba(0.7, 0.8, 0.8, 1)
                                font.pixelSize: 10
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "·  ⬜ fired last cycle"
                                color: Qt.rgba(0.7, 0.8, 0.8, 1)
                                font.pixelSize: 10
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "·  recently active"
                                color: Qt.rgba(0.3, 1, 0.9, 0.9)
                                font.pixelSize: 10
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Row {
                            spacing: 6
                            Repeater {
                                model: ["chemosensation", "mechanosensation", "feeding", "arousal", "locomotion", "motor"]
                                delegate: Rectangle {
                                    width: 14
                                    height: 14
                                    radius: 2
                                    color: Qt.rgba(expert.groupColors[modelData][0],
                                        expert.groupColors[modelData][1], expert.groupColors[modelData][2], 0.9)
                                }
                            }
                            Text {
                                text: "group tints (refer to the circuit)"
                                color: Qt.rgba(0.55, 0.65, 0.65, 1)
                                font.pixelSize: 9
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    // --- active circuit + inspector ----------------------------
                    Column {
                        width: parent.width - expert.gridCols * (expert.gridCell + expert.gridGap) - parent.spacing
                        spacing: 10

                        Text {
                            text: "active circuit · real edges"
                            color: Qt.rgba(0.82, 0.9, 0.88, 1)
                            font.pixelSize: 12
                            font.bold: true
                        }

                        Canvas {
                            id: circuit
                            width: parent.width
                            height: 200

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onMouseXChanged: if (containsMouse) circuit.updateHover(mouseX, mouseY)
                                onMouseYChanged: if (containsMouse) circuit.updateHover(mouseX, mouseY)
                                onClicked: expert.selectedNode = circuit.nodeAt(mouseX, mouseY)
                            }

                            Connections {
                                target: expert
                                function onFrameChanged() { circuit.requestPaint() }
                            }

                            function nodeAt(mx, my) {
                                var layout = expert.chainLayout
                                var chain = expert.activeChain
                                if (!layout.pos || layout.nodeCount === 0) return ""
                                var xPad = 22, yPad = 10
                                var nW = (width - xPad * 2) / Math.max(1, layout.maxX)
                                var nH = height - yPad * 2
                                var pos = layout.pos
                                for (var i = 0; i < chain.nodes.length; i++) {
                                    var nn = chain.nodes[i]
                                    var p = pos[nn]
                                    if (!p) continue
                                    var cx = xPad + p.x * nW + nW / 2
                                    var cy = yPad + p.y * nH + 8
                                    var dx = mx - cx, dy = my - cy
                                    if (dx * dx + dy * dy < 100) return nn
                                }
                                return ""
                            }
                            function updateHover(mx, my) {
                                expert.hoverNode = nodeAt(mx, my)
                            }

                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                var layout = expert.chainLayout
                                var chain = expert.activeChain
                                if (!layout || !layout.pos || layout.nodeCount === 0 || !chain || !chain.nodes) {
                                    ctx.fillStyle = Qt.rgba(0.3, 0.55, 0.5, 0.8)
                                    ctx.font = "12px sans-serif"
                                    ctx.fillText("no live circuit here yet", 8, 18)
                                    return
                                }
                                var xPad = 22, yPad = 10
                                var nW = (width - xPad * 2) / Math.max(1, layout.maxX)
                                var nH = height - yPad * 2
                                var pos = layout.pos

                                // edges: real, weighted; brightness follows the SOURCE activity
                                ctx.lineCap = "round"
                                var edges = chain.edges || []
                                for (var i = 0; i < edges.length; i++) {
                                    var e = edges[i]
                                    var p1 = pos[e[0]], p2 = pos[e[1]]
                                    if (!p1 || !p2 || e[0] === e[1]) continue
                                    var x1 = xPad + p1.x * nW + nW / 2
                                    var y1 = yPad + p1.y * nH + 8
                                    var x2 = xPad + p2.x * nW + nW / 2
                                    var y2 = yPad + p2.y * nH + 8
                                    var act = Math.max(0.08, expert.chargeOf(e[0]) * 2)
                                    ctx.strokeStyle = Qt.rgba(0.25, 1, 0.9, act)
                                    ctx.lineWidth = Math.min(3, 1 + e[2] / 22)
                                    ctx.beginPath()
                                    ctx.moveTo(x1, y1)
                                    ctx.lineTo(x2, y2)
                                    ctx.stroke()
                                }

                                // nodes: radius ~ charge, tint = group, white rim = fired.
                                // Labels only for hovered / selected / sparse sources
                                // and muscles, to stay legible in the big chains.
                                var nodes = chain.nodes
                                var isLabel = function (nn) {
                                    if (nn === expert.selectedNode || nn === expert.hoverNode) return true
                                    if (GraphData.graphChemoSources().indexOf(nn) !== -1
                                        || GraphData.graphTouchSources().indexOf(nn) !== -1) return nodes.length <= 46
                                    if (GraphData.graphMuscleList().indexOf(nn) !== -1) return nodes.length <= 20
                                    return false
                                }
                                for (i = 0; i < nodes.length; i++) {
                                    var nn = nodes[i]
                                    var p = pos[nn]
                                    if (!p) continue
                                    var cx = xPad + p.x * nW + nW / 2
                                    var cy = yPad + p.y * nH + 8
                                    var ch = expert.chargeOf(nn)
                                    var grp = GraphData.graphGroupOf()[nn] || "other"
                                    var rad = 3.5 + ch * 4
                                    ctx.beginPath()
                                    ctx.arc(cx, cy, rad, 0, 6.2832)
                                    ctx.fillStyle = expert.nodeColor(grp, ch, 0.95)
                                    ctx.fill()
                                    if (expert.firedOf(nn)) {
                                        ctx.strokeStyle = "white"
                                        ctx.lineWidth = 1.5
                                        ctx.stroke()
                                    }
                                    if (nn === expert.selectedNode) {
                                        ctx.strokeStyle = "cyan"
                                        ctx.lineWidth = 1
                                        ctx.stroke()
                                    }
                                    if (isLabel(nn)) {
                                        ctx.fillStyle = "white"
                                        ctx.font = "9px sans-serif"
                                        ctx.fillText(nn, cx - 10, cy - rad - 3)
                                    }
                                }
                            }
                        }

                        // Inspector (select / hover a neuron)
                        Text {
                            id: inspector
                            width: parent.width
                            wrapMode: Text.Wrap
                            color: "white"
                            font.pixelSize: 10
                            text: expert.inspectorText()
                        }

                        Text {
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: "charge = accumulated synaptic input (model units, capped at the firing threshold). Bars/sparklines are derived from sums of real charge; every circuit node and edge is an actual connection in Celegans.js."
                            color: Qt.rgba(0.55, 0.65, 0.65, 1)
                            font.pixelSize: 9
                        }
                    }
                }
            }
        }
    }

    // Drive one refresh per connectome cycle and refresh the chain context.
    Timer {
        interval: 100
        running: expert.visible
        repeat: true
        onTriggered: {
            expert.frame++
            expert.refreshChain()
            expert.lastFiredTotal = expert.monitor ? expert.monitor.lastFiredCount : 0
            expert.lastAvgCharge = expert.monitor ? expert.monitor.averageCharge : 0
        }
    }

    function close() {
        expert.closed()
    }
}