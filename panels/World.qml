import QtQuick

// The pet's world: decorative obstacles the worm avoids and food pellets it
// can smell and eat. Everything lives in this item's coordinate space (the
// aquarium). The connectome never sees our geometry --- it only receives the
// smell values via Pet/BrainConnector --- so "chemotaxis" comes out of the
// real wiring, not hardcoded steering.
Item {
  id: world

  // Static decor placed by the host (Panel). Each: { x, y, width, height }.
  property var obstacleLayout: [
    { "x": 36,  "y": 116, "width": 44, "height": 34 },
    { "x": 552, "y": 92,  "width": 40, "height": 44 },
    { "x": 124, "y": 396, "width": 50, "height": 32 },
    { "x": 470, "y": 352, "width": 42, "height": 38 },
    { "x": 324, "y": 58,  "width": 36, "height": 28 },
    { "x": 238, "y": 246, "width": 46, "height": 34 }
  ]

  // --- food ----------------------------------------------------------------
  property int maxFood: 6
  property real smellRadius: 220     // chemical range of a pellet
  property var foodItems: []         // [{ id, x, y, r }]

  // --- Phase B: Lab stimulus fields ---------------------------------------
  // Two extra soluble fields the connectome senses through its own real cells
  // (AFD thermo, AWA chemical-B), each with its own falloff and a DECORATIVE,
  // collision-free source. Sources only exist while the Lab places them; the
  // pet never walks around them, it only smells/feels their field.
  property real thermoRadius: 260
  property real chemBRadius: 260
  property var thermoSources: []     // [{ x, y }] warm gradient
  property var chemBSources: []      // [{ x, y }] chemical-B gradient

  // --- interaction ---------------------------------------------------------
  property bool allowFoodDrop: true
  property bool autoFeedEnabled: false   // host (Panel) flips on when hungry
  // Lab placement mode: while set, clicks place a stimulus source instead of
  // dropping food. "none" | "thermo" | "chemB".
  property string labPlaceMode: "none"
  // Emitted whenever a pellet appears. `source` is "hand" when the user
  // clicked to drop it and "auto" when the auto feeder spawned it; Pet uses
  // it to credit hand->food memories only for real hand actions.
  signal foodDropped(real x, real y, string source)

  // Random pellet position free of obstacles (only used by the auto feeder).
  function randomClearSpot() {
    var m = 20
    for (var attempt = 0; attempt < 12; attempt++) {
      var x = m + Math.random() * (world.width - 2 * m)
      var y = m + Math.random() * (world.height - 2 * m)
      var ok = true
      var rocks = world.obstacleLayout
      for (var i = 0; i < rocks.length; i++) {
        if (x >= rocks[i].x - 8 && x <= rocks[i].x + rocks[i].width + 8
            && y >= rocks[i].y - 8 && y <= rocks[i].y + rocks[i].height + 8) { ok = false; break }
      }
      if (ok) return { "x": x, "y": y }
    }
    return { "x": world.width / 2, "y": world.height * 0.3 }
  }

  // Give a hungry, idle pet food once in a while so the chemotaxis loop is
  // self-sustaining: food spawns only when there is none left on the floor.
  Timer {
    interval: 15000
    running: true
    repeat: true
    onTriggered: {
      if (!world.autoFeedEnabled || world.foodItems.length > 0) return
      var spot = world.randomClearSpot()
      world.dropFood(spot.x, spot.y, "auto")
    }
  }

  signal worldTouched(real x, real y)
  signal foodEaten(real x, real y)

  // Drop a new pellet at aquarium coordinates (clamped, spaced from walls).
  // `source` distinguishes a deliberate user drop ("hand") from auto-feeding.
  function dropFood(x, y, source) {
    if (!world.allowFoodDrop || world.foodItems.length >= world.maxFood) return
    var r = 7
    x = Math.max(14, Math.min(world.width - 14, x))
    y = Math.max(14, Math.min(world.height - 14, y))
    var id = (world.foodItems.length ? world.foodItems[world.foodItems.length - 1].id : 0) + 1
    world.foodItems = world.foodItems.concat([{ "id": id, "x": x, "y": y, "r": r, "age": 0 }])
    world.foodDropped(x, y, source === "hand" ? "hand" : "auto")
    canvas.requestPaint()
  }

  // Total smell intensity at (x, y): smooth falloff with distance from each
  // pellet. This is the only input Pet asks from us for chemotaxis.
  function smellAt(x, y) {
    var s = 0
    var items = world.foodItems
    for (var i = 0; i < items.length; i++) {
      var dx = items[i].x - x
      var dy = items[i].y - y
      var d = Math.sqrt(dx * dx + dy * dy)
      if (d < world.smellRadius) {
        var t = 1 - d / world.smellRadius
        s += t * t
      }
    }
    return s
  }

  // Like items[i], but each source contributes its own decayed gradient. The
  // Lab fields use the same peak-normalized falloff as the food smell (0..1
  // per source) so probe intensities across channels are directly comparable.
  function fieldAt(sources, radius, x, y) {
    var s = 0
    for (var i = 0; i < sources.length; i++) {
      var dx = sources[i].x - x
      var dy = sources[i].y - y
      var d = Math.sqrt(dx * dx + dy * dy)
      if (d < radius) {
        var t = 1 - d / radius
        s += t * t
      }
    }
    return s
  }
  function thermoAt(x, y) { return world.fieldAt(world.thermoSources, world.thermoRadius, x, y) }
  function chemBAt(x, y) { return world.fieldAt(world.chemBSources, world.chemBRadius, x, y) }

  function addThermoSource(x, y) {
    x = Math.max(14, Math.min(world.width - 14, x))
    y = Math.max(14, Math.min(world.height - 14, y))
    world.thermoSources = world.thermoSources.concat([{ "x": x, "y": y }])
    canvas.requestPaint()
  }
  function addChemBSource(x, y) {
    x = Math.max(14, Math.min(world.width - 14, x))
    y = Math.max(14, Math.min(world.height - 14, y))
    world.chemBSources = world.chemBSources.concat([{ "x": x, "y": y }])
    canvas.requestPaint()
  }
  function clearLabStimuli() {
    world.thermoSources = []
    world.chemBSources = []
    canvas.requestPaint()
  }

  // Public repaint hook (the Lab panel calls it after re-applying a config).
  function refresh() {
    canvas.requestPaint()
  }
  function clearThermo() {
    world.thermoSources = []
    canvas.requestPaint()
  }
  function clearChemB() {
    world.chemBSources = []
    canvas.requestPaint()
  }

  // Obstacles as plain rect objects (for the steering logic).
  function getObstacles() {
    var out = []
    var list = world.obstacleLayout
    for (var i = 0; i < list.length; i++)
      out.push({ "x": list[i].x, "y": list[i].y, "width": list[i].width, "height": list[i].height })
    return out
  }

  // Near point on an obstacle rect to (x, y).
  function closestOnRect(r, x, y) {
    var cx = Math.max(r.x, Math.min(r.x + r.width, x))
    var cy = Math.max(r.y, Math.min(r.y + r.height, y))
    return { "x": cx, "y": cy }
  }

  // Eat a pellet within `reach` of (px, py). Returns true + removes it.
  function eatAt(px, py, reach) {
    var items = world.foodItems
    for (var i = 0; i < items.length; i++) {
      var dx = items[i].x - px
      var dy = items[i].y - py
      var d = Math.sqrt(dx * dx + dy * dy)
      if (d <= reach + items[i].r) {
        var ex = items[i].x, ey = items[i].y
        world.foodItems.splice(i, 1)
        world.foodEaten(ex, ey)
        canvas.requestPaint()
        return true
      }
    }
    return false
  }

  // --- rendering -----------------------------------------------------------
  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      var items = world.foodItems
      for (var i = 0; i < items.length; i++) items[i].age++
      canvas.requestPaint()
    }
  }

  Canvas {
    id: canvas
    anchors.fill: parent

    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)

      // obstacle rocks: irregular lumpy silhouettes with shading so they read
      // as stones, not plain circles. A deterministic per-rock seed keeps the
      // shape stable across repaints. Collision still uses the layout rects.
      var rocks = world.obstacleLayout
      for (var r = 0; r < rocks.length; r++) {
        var o = rocks[r]
        var cx = o.x + o.width / 2
        var cy = o.y + o.height / 2
        var radX = o.width / 2
        var radY = o.height / 2
        var n = 14
        var seed = (r + 1) * 7919 + 13
        var pr = function() { seed = seed * 16807 % 2147483647; return seed / 2147483647 }

        // lumpy blob: radius wobbles around the ellipse, smoothed with quadratics
        var pts = []
        for (var i = 0; i < n; i++) {
          var a = i / n * 2 * Math.PI
          var wob = 1 + (pr() - 0.5) * 0.5 + (pr() - 0.5) * 0.2
          pts.push({ x: cx + Math.cos(a) * radX * wob, y: cy + Math.sin(a) * radY * wob })
        }
        ctx.beginPath()
        ctx.moveTo(pts[0].x, pts[0].y)
        for (var pi = 0; pi < n; pi++) {
          var p1 = pts[pi]
          var p2 = pts[(pi + 1) % n]
          ctx.quadraticCurveTo(p1.x, p1.y, (p1.x + p2.x) / 2, (p1.y + p2.y) / 2)
        }
        ctx.closePath()

        var grad = ctx.createLinearGradient(cx, cy - radY, cx, cy + radY)
        grad.addColorStop(0, "rgba(38, 60, 82, 0.9)")
        grad.addColorStop(1, "rgba(10, 16, 26, 0.9)")
        ctx.fillStyle = grad
        ctx.fill()
        ctx.strokeStyle = "rgba(0, 255, 240, 0.45)"
        ctx.lineWidth = 1.5
        ctx.stroke()

        // moon-lit rim: bright arc on the lit side, deep shade on the far side
        ctx.beginPath()
        ctx.ellipse(cx - radX * 0.28, cy - radY * 0.32, radX * 0.55, radY * 0.42,
                    -0.55, 0.6 * Math.PI, 1.5 * Math.PI)
        ctx.strokeStyle = "rgba(120, 255, 245, 0.4)"
        ctx.lineWidth = 2
        ctx.stroke()
        ctx.beginPath()
        ctx.ellipse(cx + radX * 0.15, cy + radY * 0.38, radX * 0.6, radY * 0.45,
                    0.4, 0.7 * Math.PI, 1.9 * Math.PI)
        ctx.strokeStyle = "rgba(0, 0, 0, 0.5)"
        ctx.lineWidth = 3.5
        ctx.stroke()

        // faceted interior: two hairline cracks so it reads as stone, not glass
        ctx.beginPath()
        ctx.moveTo(cx - radX * 0.45, cy - radY * 0.25)
        ctx.lineTo(cx - radX * 0.12, cy + radY * 0.05)
        ctx.lineTo(cx + radX * 0.4, cy - radY * 0.12)
        ctx.moveTo(cx - radX * 0.05, cy + radY * 0.12)
        ctx.lineTo(cx + radX * 0.22, cy + radY * 0.42)
        ctx.strokeStyle = "rgba(0, 0, 0, 0.35)"
        ctx.lineWidth = 1
        ctx.stroke()

        // a few glowing mineral specks
        for (var s = 0; s < 3; s++) {
          ctx.beginPath()
          ctx.arc(cx + (pr() - 0.5) * radX * 1.35, cy + (pr() - 0.5) * radY * 1.35,
                  pr() * 1.4 + 0.4, 0, 2 * Math.PI)
          ctx.fillStyle = "rgba(120, 255, 245, 0.35)"
          ctx.fill()
        }
      }

      // food pellets: glow + solid core, gentle bob
      var foods = world.foodItems
      for (var f = 0; f < foods.length; f++) {
        var p = foods[f]
        var bob = Math.sin(p.age * 0.45) * 2
        var py = p.y + bob
        ctx.globalAlpha = 0.9
        ctx.beginPath()
        ctx.arc(p.x, py, p.r + 5, 0, 2 * Math.PI)
        ctx.fillStyle = "rgba(255, 191, 94, 0.22)"
        ctx.fill()
        ctx.beginPath()
        ctx.arc(p.x, py, p.r, 0, 2 * Math.PI)
        ctx.fillStyle = "#ffbf5e"
        ctx.fill()
        ctx.beginPath()
        ctx.arc(p.x - 1.5, py - 1.5, 2, 0, 2 * Math.PI)
        ctx.fillStyle = "rgba(255, 255, 255, 0.85)"
        ctx.fill()
        ctx.globalAlpha = 1
      }

      // thermo sources: warm glow + core, no collision (decorative field)
      var thermos = world.thermoSources
      for (var th = 0; th < thermos.length; th++) {
        var hs = thermos[th]
        ctx.beginPath()
        ctx.arc(hs.x, hs.y, 16, 0, 2 * Math.PI)
        ctx.fillStyle = "rgba(255, 140, 40, 0.18)"
        ctx.fill()
        ctx.beginPath()
        ctx.arc(hs.x, hs.y, 8, 0, 2 * Math.PI)
        ctx.fillStyle = "rgba(255, 170, 70, 0.5)"
        ctx.fill()
        ctx.beginPath()
        ctx.arc(hs.x, hs.y, 3.5, 0, 2 * Math.PI)
        ctx.fillStyle = "rgba(255, 230, 160, 0.95)"
        ctx.fill()
      }

      // chemical-B sources: teal pellet look, distinct from food
      var cbs = world.chemBSources
      for (var cb = 0; cb < cbs.length; cb++) {
        var cs = cbs[cb]
        ctx.beginPath()
        ctx.arc(cs.x, cs.y, 9, 0, 2 * Math.PI)
        ctx.fillStyle = "rgba(64, 210, 190, 0.25)"
        ctx.fill()
        ctx.beginPath()
        ctx.arc(cs.x, cs.y, 4.5, 0, 2 * Math.PI)
        ctx.fillStyle = "#40d2be"
        ctx.fill()
        ctx.beginPath()
        ctx.arc(cs.x - 1, cs.y - 1, 1.5, 0, 2 * Math.PI)
        ctx.fillStyle = "rgba(255, 255, 255, 0.8)"
        ctx.fill()
      }
    }
  }

  // Click anywhere that is not the pet drops a pellet of food.
  MouseArea {
    id: touch
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    onClicked: (mouse) => {
      if (world.labPlaceMode === "thermo") {
        world.addThermoSource(mouse.x, mouse.y)
      } else if (world.labPlaceMode === "chemB") {
        world.addChemBSource(mouse.x, mouse.y)
      } else if (world.allowFoodDrop) {
        world.dropFood(mouse.x, mouse.y, "hand")
      }
    }
  }
}