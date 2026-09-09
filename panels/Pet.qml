import QtQuick

// Conector entre el cerebro (BrainConnector) y su posición dentro de la
// ventana. brainController se INYECTA desde Main.qml como propiedad:
// un id declarado en otro documento .qml no es visible aquí adentro.
Item {
    id: petInstance

    // Define que cualquier rotación se haga desde el centro del ítem
    transformOrigin: Item.Center
    property var brainController: null

    // Variable interna para dar algo de inercia o exploración caótica
    property real randomTurnFactor: 0.0

    // Cada vez que el conectoma completa un ciclo, traducimos la fuerza
    // motora izquierda/derecha en giro + desplazamiento dentro de la ventana.
    Connections {
        target: petInstance.brainController
        function onUpdated() {
            if (!petInstance.brainController || !petInstance.parent) return

            var muscles = petInstance.brainController.muscles

            var left = petInstance.brainController.leftMotor
            var right = petInstance.brainController.rightMotor

            // 1. Exploración caótica natural:
            // Ocasionalmente añadimos un pequeño sesgo estocástico (ruido biológico)
            if (Math.random() < 0.05) {
                petInstance.randomTurnFactor = (Math.random() - 0.5) * 15.0;
            } else {
                petInstance.randomTurnFactor *= 0.8; // Decaimiento suave
            }

            var forwardSpeed = (left + right) * 0.02
            var turnDiff = (left - right) + petInstance.randomTurnFactor

            // Al modificar rotation, el elemento ahora girará sobre su centro
            petInstance.rotation += turnDiff * 0.2

            var rad = petInstance.rotation * Math.PI / 180
            var newX = petInstance.x + Math.cos(rad) * forwardSpeed
            var newY = petInstance.y + Math.sin(rad) * forwardSpeed

            var maxX = petInstance.parent.width - petInstance.width
            var maxY = petInstance.parent.height - petInstance.height

            // 2. Detección consciente de la pared:
            // Si la nueva posición toca el borde, ESTIMULAMOS el conectoma
            // en lugar de forzar un refraccionamiento matemático.
            if (newX <= 0 || newX >= maxX || newY <= 0 || newY >= maxY) {
                if (petInstance.brainController) {
                    // Estimulo mecanorreceptor frontal (choque con obstáculo)
                    petInstance.brainController.stimulateTouch()
                }

                // Giramos la orientación aleatoriamente para simular que el choque lo desorientó
                petInstance.rotation += (Math.random() > 0.5 ? 90 : -90) + (Math.random() * 30 - 15);
            } else {
                // Si la vía está libre, avanza normalmente
                petInstance.x = newX;
                petInstance.y = newY;
            }
        }
    }

    PetVisual {
        id: petVisual
        anchors.fill: parent
        rotation: 90 // O -90, para alinear el dibujo vertical con el vector de movimiento horizontal
        transformOrigin: Item.Center

        // Un clic = estímulo táctil real sobre el conectoma
        onClicked: {
          if (petInstance.brainController) {
            petInstance.brainController.stimulateTouch();
            // Feedback visual inmediato
            petVisual.isStartled = true;
            flashTimer.start();
          }
        }

        Timer {
          id: flashTimer
          interval: 800
          onTriggered: petVisual.isStartled = false
        }

        // Arrastrar la mascota manualmente dentro de la ventana
        onDragged: (dx, dy) => {
            if (!petInstance.parent) return

            var maxX = petInstance.parent.width - petInstance.width
            var maxY = petInstance.parent.height - petInstance.height
            petInstance.x = Math.max(0, Math.min(maxX, petInstance.x + dx))
            petInstance.y = Math.max(0, Math.min(maxY, petInstance.y + dy))
        }
    }
}
