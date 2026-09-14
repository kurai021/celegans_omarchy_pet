import QtQuick

// Purely visual + raw interaction layer. It doesn't know brainController
// or windowRef: it only draws the undulating body and emits signals.
Item {
    id: petVisual
    anchors.fill: parent

    signal clicked()
    signal dragged(real dx, real dy)

    // Wave/phase adjustment for undulation
    property real phase: 0.0
    property real currentSpeed: 1.0

    property bool isStartled: false

    // Set to false (e.g. while the panel is hidden) to stop repainting the
    // canvas in the background: the shell is a long-running process.
    property bool animating: true

    // Curled resting pose: the body stops undulating and the "z" glyphs drift.
    property bool sleeping: false
    property real zzzPhase: 0

    // Smooth animation of the body undulation
    NumberAnimation on phase {
        from: 0
        to: Math.PI * 2
        // Higher motor speed, shorter duration (undulates faster)
        duration: Math.max(300, 1500 / Math.max(0.1, petVisual.currentSpeed))
        loops: Animation.Infinite
        running: petVisual.animating && !petVisual.sleeping
    }

    NumberAnimation on zzzPhase {
        from: 0
        to: 14
        duration: 1600
        loops: Animation.Infinite
        running: petVisual.sleeping
    }

    onPhaseChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {

            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            // Control points for the worm's body (from head to tail)
            var points = 17;
            var path = [];

            var centerX = width / 2;
            var startY = height * 0.15;
            var endY = height * 0.85;
            var stepY = (endY - startY) / (points - 1);

            for (var i = 0; i < points; i++) {
                // Generate sinusoidal curve along the body; a curled nap
                // pose uses a much smaller amplitude.
                var amp = petVisual.sleeping ? 5 : 18
                var wave = Math.sin(petVisual.phase - (i * 0.5)) * amp;
                path.push({ x: centerX + wave, y: startY + (i * stepY) });
            }

            // --- 1. DRAW OUTER GLOW (NEON) ---
            ctx.beginPath();
            ctx.moveTo(path[0].x, path[0].y);
            for (var j = 1; j < points; j++) {
                ctx.lineTo(path[j].x, path[j].y);
            }
            ctx.strokeStyle = petVisual.isStartled ? "rgba(255, 60, 100, 0.9)" : "rgba(0, 255, 240, 0.4)";
            ctx.lineWidth = 14;
            ctx.lineCap = "round";
            ctx.lineJoin = "round";
            ctx.stroke();

            // --- 2. DRAW TRANSLUCENT BODY ---
            ctx.beginPath();
            ctx.moveTo(path[0].x, path[0].y);
            for (var k = 1; k < points; k++) {
                ctx.lineTo(path[k].x, path[k].y);
            }
            ctx.strokeStyle = "rgba(255, 255, 255, 0.85)";
            ctx.lineWidth = 8;
            ctx.stroke();

            // --- 3. WORM HEAD ---
            ctx.beginPath();
            ctx.arc(path[0].x, path[0].y, 6, 0, 2 * Math.PI);
            ctx.fillStyle = "#00FFF0";
            ctx.fill();

            // --- 4. DREAMING "z" GLYPHS (while napping) ---
            if (petVisual.sleeping) {
                ctx.fillStyle = "rgba(180, 240, 245, 1)";
                ctx.font = "bold 11px monospace";
                var zDrop = petVisual.zzzPhase;
                for (var zi = 0; zi < 3; zi++) {
                    ctx.globalAlpha = 0.85 - zi * 0.25;
                    ctx.fillText("z", path[0].x + 9 + zi * 5, path[0].y - 8 - zi * 9 - zDrop);
                }
                ctx.globalAlpha = 1;
            }
        }
    }

    // Tactile interaction over the worm area
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        property point dragPos

        onClicked: petVisual.clicked()

        onPressed: (mouse) => { dragPos = Qt.point(mouse.x, mouse.y) }
        onPositionChanged: (mouse) => {
            if (pressed) {
                let dx = mouse.x - dragPos.x;
                let dy = mouse.y - dragPos.y;
                petVisual.dragged(dx, dy);
            }
        }
    }
}
