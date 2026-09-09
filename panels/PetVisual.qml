import QtQuick

// Capa puramente visual + de interacción cruda. No conoce brainController
// ni windowRef: solo dibuja el cuerpo ondulante y emite señales.
Item {
    id: petVisual
    anchors.fill: parent

    signal clicked()
    signal dragged(real dx, real dy)

    // Ajuste de ondas/fase para la ondulación
    property real phase: 0.0
    property real currentSpeed: 1.0

    property bool isStartled: false

    // Animación suave de la ondulación del cuerpo
    NumberAnimation on phase {
        from: 0
        to: Math.PI * 2
        // A mayor velocidad de los motores, menor duración (ondula más rápido)
        duration: Math.max(300, 1500 / Math.max(0.1, petVisual.currentSpeed))
        loops: Animation.Infinite
        running: true
    }

    onPhaseChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {

            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            // Puntos de control para el cuerpo del gusano (de cabeza a cola)
            var points = 17;
            var path = [];

            var centerX = width / 2;
            var startY = height * 0.15;
            var endY = height * 0.85;
            var stepY = (endY - startY) / (points - 1);

            for (var i = 0; i < points; i++) {
                // Generar curva sinusoidal a lo largo del cuerpo
                var wave = Math.sin(petVisual.phase - (i * 0.5)) * 18;
                path.push({ x: centerX + wave, y: startY + (i * stepY) });
            }

            // --- 1. DIBUJAR RESPLANDOR EXTERIOR (NEÓN) ---
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

            // --- 2. DIBUJAR CUERPO TRANSLÚCIDO ---
            ctx.beginPath();
            ctx.moveTo(path[0].x, path[0].y);
            for (var k = 1; k < points; k++) {
                ctx.lineTo(path[k].x, path[k].y);
            }
            ctx.strokeStyle = "rgba(255, 255, 255, 0.85)";
            ctx.lineWidth = 8;
            ctx.stroke();

            // --- 3. CABEZA DEL GUSANO ---
            ctx.beginPath();
            ctx.arc(path[0].x, path[0].y, 6, 0, 2 * Math.PI);
            ctx.fillStyle = "#00FFF0";
            ctx.fill();
        }
    }

    // Interacción táctil sobre el área del gusano
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
