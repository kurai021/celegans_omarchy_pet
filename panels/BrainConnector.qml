import QtQuick
import "Celegans.js" as CElegans

// Única fuente de verdad del conectoma: crea y avanza el cerebro,
// y expone lo que Pet.qml necesita para moverse y reaccionar.
Item {
    id: brainController

    property var brainInstance: null
    property real leftMotor: 0
    property real rightMotor: 0

    // Se emite al final de cada ciclo de simulación (10 Hz)
    signal updated()

    Component.onCompleted: {
        brainInstance = new CElegans.Brain()
        brainInstance.setup()

        // Sin esto, Brain.update() no ejecuta nada: el conectoma original
        // necesita un estímulo activo (tacto u olfato) para propagar señales.
        // Lo dejamos "explorando" de forma continua, como el robot original.
        brainInstance.stimulateFoodSenseNeurons = true
    }

    property int touchCooldown: 0

    // Pulso principal del conectoma (10 Hz)
    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            if (!brainController.brainInstance) return

            // Mantener el estímulo activo durante varios ciclos de simulación
              if (brainController.touchCooldown > 0) {
                brainController.brainInstance.postSynaptic["ALML"][brainController.brainInstance.nextState] += 120
                brainController.brainInstance.postSynaptic["ALMR"][brainController.brainInstance.nextState] += 120
                brainController.brainInstance.stimulateNoseTouchNeurons = true
                brainController.touchCooldown--
              } else {
                brainController.brainInstance.stimulateNoseTouchNeurons = false
              }

            brainController.brainInstance.update()

            brainController.leftMotor = brainController.brainInstance.accumleft
            brainController.rightMotor = brainController.brainInstance.accumright

            brainController.brainInstance.accumleft = 0
            brainController.brainInstance.accumright = 0

            brainController.updated()
        }
    }

    // Estimula las neuronas táctiles anteriores (equivalente a tocar al gusano).
    // ALML/ALMR son los nombres reales en el conectoma (no existe "ALM").
    function stimulateTouch() {
        if (!brainInstance) return

        touchCooldown = 10 // Mantener el estímulo activo durante 10 ciclos de simulación (1 segundo)
    }
}
