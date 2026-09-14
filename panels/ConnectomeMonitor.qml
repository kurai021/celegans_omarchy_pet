import QtQuick
import "ConnectomeGraph.js" as GraphData

// Observation pipeline for the Expert View. It only does work while `active`
// is true (i.e. while the Expert View overlay is open), and it NEVER writes
// back into the connectome — every magnitude below is a read of the real
// per-cycle state the simulation already produces:
//   charge    = postSynaptic[n][thisState]  (continuous, 0..30+, model units)
//   fired     = the neuron exceeded fireThreshold this cycle (brain logs it)
//   idle      = real cycles since the neuron last received input
//   motorL/R  = accumulated body-muscle drive (brainController.leftMotor/rightMotor)
// The "circuit chains" are computed by BFS over the REAL adjacency parsed
// from Celegans.js — nodes and edges are only ever real model connections.
Item {
    id: monitor

    property var brainController: null
    property bool active: false

    // Synchronizes one sample with each connectome cycle while active.
    Connections {
        target: monitor.brainController
        enabled: monitor.active
        function onUpdated() { monitor.sample() }
    }

    readonly property int historyLen: 160    // ~16 s @ 10 Hz
    property var brain: null

    // Per-neuron state, arrays parallel to GraphData.graphNodes()
    property var charges: []        // 0..1 normalized against fireThreshold
    property var fired: []          // true if it fired last cycle
    property var recent: []         // activity decaying toward 0 (recent history)
    property var idleCycles: []     // real cycles without input
    property int averageCharge: 0   // mean charge across all neurons (0..1000 scale)
    property int lastFiredCount: 0  // how many neurons fired last cycle
    property int lastDepolarizedCount: 0

    // Derived group signals (honest sums over curated neuron sets)
    property var groupNames: ["chemosensation", "mechanosensation", "locomotion", "feeding", "arousal"]
    property var groupWeights: [0, 0, 0, 0, 0]   // current normalized activity per group
    property var groupHistory: []                // [len historyLen] per group
    property var groupWrap: []                   // ring pointer per group

    signal sampled()

    function init() {
        monitor.brain = monitor.brainController ? monitor.brainController.brainInstance : null
        var n = GraphData.graphNodes().length
        var i, g
        monitor.charges = []
        monitor.fired = []
        monitor.recent = []
        monitor.idleCycles = []
        for (i = 0; i < n; i++) {
            monitor.charges.push(0)
            monitor.fired.push(false)
            monitor.recent.push(0)
            monitor.idleCycles.push(0)
        }
        for (g = 0; g < monitor.groupNames.length; g++) {
            var hist = []
            for (i = 0; i < monitor.historyLen; i++) hist.push(0)
            monitor.groupHistory[g] = hist
            monitor.groupWrap[g] = 0
        }
        monitor.buildReverse()
        monitor.buildChains()
    }

    // Reverse adjacency (target -> [sources, weight]) built once from the real graph.
    property var reverseAdj: ({})

    function buildReverse() {
        var rev = {}
        var nodes = GraphData.graphNodes()
        for (var i = 0; i < nodes.length; i++) rev[nodes[i]] = []
        var adj = GraphData.graphAdj()
        var spreaders = Object.keys(adj)
        for (var s = 0; s < spreaders.length; s++) {
            var src = spreaders[s]
            var es = adj[src]
            for (var e = 0; e < es.length; e++) {
                var t = es[e][0]
                if (!rev[t]) rev[t] = []
                rev[t].push([src, es[e][1]])
            }
        }
        monitor.reverseAdj = rev
    }

    // Real circuit chains: BFS from the source sets over the real adjacency,
    // without propagating into the body muscles (they are sinks).
    property var chainChemo: ({})
    property var chainTouch: ({})
    property var chainLocomotion: ({})

    function buildChain(sourceNames, maxDepth, maxNodes) {
        var layer = {}
        var nodes = GraphData.graphNodes()
        var visited = []
        var queue = []
        var i
        for (i = 0; i < sourceNames.length; i++) {
            var s = sourceNames[i]
            if (nodes.indexOf(s) !== -1 && layer[s] === undefined) {
                layer[s] = 0
                visited.push(s)
                queue.push(s)
            }
        }
        while (queue.length) {
            var cur = queue.shift()
            if (layer[cur] >= maxDepth) continue
            if (GraphData.graphMuscleList().indexOf(cur) !== -1) continue // muscles are sinks
            var es = GraphData.graphAdj()[cur] || []
            for (i = 0; i < es.length && visited.length < maxNodes; i++) {
                var t = es[i][0]
                if (layer[t] === undefined && nodes.indexOf(t) !== -1) {
                    layer[t] = layer[cur] + 1
                    visited.push(t)
                    queue.push(t)
                }
            }
        }
        var edges = []
        for (i = 0; i < visited.length; i++) {
            var v = visited[i]
            var ve = GraphData.graphAdj()[v] || []
            for (var j = 0; j < ve.length; j++) {
                var tt = ve[j][0]
                if (layer[tt] !== undefined && layer[tt] > layer[v])
                    edges.push([v, tt, ve[j][1]])
            }
        }
        return { "nodes": visited, "layer": layer, "edges": edges }
    }

    function buildChains() {
        // Chemosensation: from the injected food-smell neurons through every
        // real edge up to depth 7, wide enough to also reach the one head
        // grip muscle this wiring actually drives (ADF -> AIZ -> SMB -> MVL).
        monitor.chainChemo = monitor.buildChain(GraphData.graphChemoSources(), 7, 120)
        // Touch / mechanosensation: sensory -> command decision neurons.
        monitor.chainTouch = monitor.buildChain(GraphData.graphTouchSources(), 7, 80)
        // Locomotion: reverse BFS from a bounded spread of real body muscles,
        // then displayed the other way round, so the chain reads as
        // command neurons -> motor neurons -> the muscles they drive.
        // The motor-neuron fan-out is bounded so the BFS still reaches the
        // command layer (AVA/AVB/AVD/AVE/RIM...) above them.
        var seeds = GraphData.graphMuscleList().filter(function (m, i) { return i % 6 === 0 })
        monitor.chainLocomotion = monitor.buildReverseChain(seeds, 3, 60, 24)
    }

    // BFS over the REVERSE adjacency (who projects INTO a node), starting from
    // the muscle seeds. Layers are then inverted so the returned chain always
    // goes source-side (left) -> muscle-side (right) with real forward edges.
    function buildReverseChain(muscleSeeds, maxDepth, maxNodes, driverCap) {
        var rev = monitor.reverseAdj
        var layer = {}
        var nodes = GraphData.graphNodes()
        var visited = []
        var queue = []
        var boundDrivers = []
        var i
        // Deterministic bound on the motor-neuron layer: first `driverCap`
        // nodes in node order that project into a real body muscle.
        if (driverCap) {
            for (i = 0; i < nodes.length && boundDrivers.length < driverCap; i++) {
                var es = GraphData.graphAdj()[nodes[i]] || []
                for (var ek = 0; ek < es.length; ek++) {
                    if (GraphData.graphMuscleList().indexOf(es[ek][0]) !== -1) {
                        boundDrivers.push(nodes[i])
                        break
                    }
                }
            }
        }
        for (i = 0; i < muscleSeeds.length; i++) {
            var s = muscleSeeds[i]
            if (layer[s] === undefined) {
                layer[s] = 0
                visited.push(s)
                queue.push(s)
            }
        }
        while (queue.length && visited.length < maxNodes) {
            var cur = queue.shift()
            if (layer[cur] >= maxDepth) continue
            // Muscles are reverse-BFS sources here: expand them to find their
            // driving motor neurons, but never let them be added repeatedly.
            var inEs = rev[cur] || []
            for (i = 0; i < inEs.length && visited.length < maxNodes; i++) {
                var t = inEs[i][0]
                if (layer[t] === undefined && nodes.indexOf(t) !== -1
                    && (!boundDrivers.length || layer[cur] > 0 || boundDrivers.indexOf(t) !== -1)) {
                    layer[t] = layer[cur] + 1
                    visited.push(t)
                    queue.push(t)
                }
            }
        }
        var maxL = 0
        for (i = 0; i < visited.length; i++) maxL = Math.max(maxL, layer[visited[i]])
        var edges = []
        for (i = 0; i < visited.length; i++) {
            var v = visited[i]
            layer[v] = maxL - layer[v] // invert: commands left, muscles right
            var ve = GraphData.graphAdj()[v] || []
            for (var j = 0; j < ve.length; j++) {
                var tt = ve[j][0]
                if (layer[tt] !== undefined && layer[tt] > layer[v])
                    edges.push([v, tt, ve[j][1]])
            }
        }
        return { "nodes": visited, "layer": layer, "edges": edges }
    }

    // One read-only pass over the live connectome state.
    function sample() {
        if (!monitor.brain) return
        var b = monitor.brain
        var thisState = b.thisState
        var firedSet = b.firedThisCycle || []
        var firedCount = 0
        var chargeTotal = 0
        var n = GraphData.graphNodes().length
        var charges = monitor.charges
        var firedFlags = monitor.fired
        var recent = monitor.recent
        var idle = monitor.idleCycles
        for (var i = 0; i < n; i++) {
            var name = GraphData.graphNodes()[i]
            var c = b.postSynaptic[name][thisState] || 0
            var ci = Math.max(0, Math.min(1, c / b.fireThreshold))
            charges[i] = ci
            firedFlags[i] = firedSet.indexOf(name) !== -1
            if (firedFlags[i]) firedCount++
            recent[i] = Math.max(ci, recent[i] * 0.86)
            idle[i] = b.idleCycles[name] || 0
            chargeTotal += ci
        }
        monitor.lastFiredCount = firedCount
        monitor.averageCharge = Math.round(chargeTotal / n * 1000)
        monitor.lastDepolarizedCount = b.lastDepolarizedCount || 0

        // Group derived signals: sum of per-neuron charge across each curated
        // set, plus the real motor output for locomotion.
        monitor.groupWeights = monitor.computeGroupWeights()
        monitor.pushHistory()
        monitor.sampled()
    }

    function groupNodes(groupName) {
        var out = []
        var i
        for (i = 0; i < GraphData.graphNodes().length; i++) {
            if (GraphData.graphGroupOf()[GraphData.graphNodes()[i]] === groupName) out.push(i)
        }
        return out
    }

    // weights: 0..1 per group. chemosensation / mechanosensation / feeding /
    // arousal are sums of normalized charge over their curated neuron sets
    // (scaled by size so a big set doesn't just win); locomotion is the real
    // motor drive normalized to a fixed scale.
    function computeGroupWeights() {
        var gNames = monitor.groupNames
        var w = [0, 0, 0, 0, 0]
        var i, j
        for (i = 0; i < gNames.length; i++) {
            var key = gNames[i]
            var members = key === "locomotion" ? null : monitor.groupCache[i] || monitor.buildGroupCache(key)
            var sum = 0
            if (key === "locomotion") {
                var motor = Math.abs(monitor.brainController ? monitor.brainController.leftMotor : 0)
                    + Math.abs(monitor.brainController ? monitor.brainController.rightMotor : 0)
                w[i] = Math.min(1, motor / 120)
            } else {
                for (j = 0; j < members.length; j++) sum += monitor.charges[members[j]]
                w[i] = members.length
                    ? Math.min(1, sum / members.length * 3)
                    : 0
            }
        }
        return w
    }

    property var groupCache: []

    function buildGroupCache(key) {
        var idx = monitor.groupNames.indexOf(key)
        var list = monitor.groupNodes(key)
        monitor.groupCache[idx] = list
        return list
    }

    function pushHistory() {
        var g
        for (g = 0; g < monitor.groupNames.length; g++) {
            var h = monitor.groupHistory[g]
            var p = monitor.groupWrap[g]
            h[p] = monitor.groupWeights[g]
            monitor.groupWrap[g] = (p + 1) % monitor.historyLen
        }
    }

    // Ring buffer → ordered list for the UI (oldest first). Never throws:
    // if the ring isn't built yet (first frame while opening) it fills it
    // lazily and returns a zero line.
    function historyLine(groupIndex) {
        if (!monitor.groupHistory || !monitor.groupHistory.length) monitor.init()
        var h = monitor.groupHistory[groupIndex] || []
        var p = monitor.groupWrap[groupIndex] || 0
        var out = []
        var i
        for (i = 0; i < monitor.historyLen; i++)
            out.push(h[(p + i) % monitor.historyLen] !== undefined ? h[(p + i) % monitor.historyLen] : 0)
        return out
    }

    // Rebuild everything when the view opens.
    onActiveChanged: if (monitor.active) monitor.init()
}