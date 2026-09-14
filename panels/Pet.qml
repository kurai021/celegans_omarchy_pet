import QtQuick

// Connector between the brain (BrainConnector) and its position within the
// window. brainController, world and state are INJECTED from Panel.qml as
// properties: ids declared in another .qml document are not visible here.
//
// Steering is NOT hardcoded: the heading only changes toward a geometrically
// computed escape direction (wall reflection or obstacle repulsion) and the
// turn is rate-limited, so the worm curves smoothly instead of teleporting a
// random angle. The connectome still gets the real tactile stimulus when we
// actually touch something, and the smell gradient is fed back into the
// connectome's chemo neurons --- the turning when food is around is produced
// by the wiring, not by this file.
Item {
    id: petInstance

    transformOrigin: Item.Center
    property var brainController: null
    property var world: null
    property var petState: null

    // --- tuning ------------------------------------------------------------
    property real bodyRadius: 17        // collision circle around the center
    property real turnRate: 28          // max heading change / cycle (°)
    property real hardTurnRate: 60      // allowed right after a collision (out of the corner)
    property real innerNudge: 2         // step back into free space after a hit
    property real eatReach: 26          // how close the nose must get to a pellet
    property int sleepCycles: 0
    property int wakeAfterCycles: 400   // nap length (40 s); a click wakes sooner
    property real lastSmellForward: 0   // smell ahead from the previous cycle
    property real lastSmellLeft: 0      // ... and off the left probe
    property real lastSmellRight: 0     // ... and off the right probe
    property real randomTurnFactor: 0   // biological noise, damped near food

    // Chemotaxis is computed from the worm's own odor samples (same three
    // probes we already feed into the connectome). The connectome's direct
    // ADFL/ADFR -> muscle asymmetry is real but a few tenths of a degree
    // per cycle, far below what is visible, so the heading correction uses
    // the gradient the probes read: turn is proportional to side imbalance
    // (Braitenberg-style), rate-limited, so the worm visibly homes in.
    property real gradientGain: 300     // lateral smell imbalance -> heading (°)
    property real maxGradientTurn: 60   // cap on gradient-triggered turn
    property real brainTurnGain: 0.05   // connectome signature on the heading
    property real steerLean: 0          // IIR-smoothed heading demand
    property real steerAlpha: 0.35      // smoothing weight for steerLean
    property real huntFloor: 0.3        // hunt multiplier left at full energy
    property real foodLureEnergy: 90   // above this the pet is "full": ignores food

    // energy gate: re-uses lastSmell* probes only when the pet is actually
    // hungry; a full pet wanders and only eats what it stumbles into.
    property real forwardProbe: 80      // how far the nose smells ahead
    property real sideProbeForward: 60  // lateral probes ride 60 px ahead
    property real sideProbeSpread: 24   // ... splayed 24 px to each side

    readonly property string petName: petState ? (petState.petName || "Wormy") : "Wormy"
    readonly property bool isNight: {
        var h = new Date().getHours()
        return h >= 1 && h < 5
    }

    property string currentMessage: ""

    // --- derived state (F1) -------------------------------------------------
    // Every label below is backed by a real model signal so the chip never
    // invents a state: sleeping = the real nap; hungry = the same < 55 cutoff
    // the auto-feed uses; hunting = smell present while feeding drive active
    // (distinct from merely hungry); full = the energy > foodLureEnergy rule
    // that already stops hunting; resting = no movement for ~4 s (never a
    // couple of still frames); grumpy = a user touch in the last 2.5 s.
    property int stillCycles: 0          // consecutive cycles without movement
    property real lastHandTouchAt: 0     // ms timestamp of the last user click
    property string stateEmoji: "🔍"
    property string stateLabel: "exploring"
    readonly property string stateLabelText: petInstance.stateEmoji + " " + petInstance.stateLabel
    function setState(emoji, label) {
        petInstance.stateEmoji = emoji
        petInstance.stateLabel = label
    }

    readonly property var phrases: {
        "startle": [
            "Don't touch me!", "Gross!", "Personal space, please!",
            "I'm not a toy!", "Stop it!", "Go away!",
            "I'm busy being a worm!", "No touching!"
        ],
        "hungry": [
            "I'm so hungry...", "Feed me!", "{name} is starving...",
            "My tummy is empty."
        ],
        "sleepy": [
            "*yawn* ...", "So sleepy...", "Naptime...", "{name} needs a break."
        ],
        "wake": [
            "*yawn*", "Good nap!", "What time is it?!", "I dreamed of grass."
        ],
        "meal": [
            "Mmm!", "Delicious!", "More!", "*nom nom nom*", "Best day ever!"
        ]
    }

    function pick(pool) {
        var list = petInstance.phrases[pool]
        var raw = list[Math.floor(Math.random() * list.length)]
        return raw.replace("{name}", petInstance.petName)
    }
    function say(pool) {
        petInstance.currentMessage = petInstance.pick(pool)
        messageTimer.restart()
    }

    // Every time the connectome completes a cycle we translate the motor
    // forces into rotation + displacement within the window, then prime the
    // next cycle with fresh sensory (smell) input.
    Connections {
        target: petInstance.brainController
        function onUpdated() {
            if (!petInstance.brainController || !petInstance.parent) return

            var left = petInstance.brainController.leftMotor
            var right = petInstance.brainController.rightMotor
            var moving = false

            // --- sleep ---
            if (petInstance.petState && petInstance.petState.asleep) {
                petVisual.sleeping = true
                petVisual.currentSpeed = 0.3 // near-static body during the nap
                petInstance.lastSmellForward = 0
                petInstance.randomTurnFactor = 0
                petInstance.stillCycles = 0
                petInstance.setState("💤", "sleeping")
                // resting restores energy
                petInstance.petState.energy = Math.min(100, petInstance.petState.energy + 0.08)
                petInstance.sleepCycles++
                if (petInstance.sleepCycles >= petInstance.wakeAfterCycles) {
                    petInstance.petState.wake()
                    petInstance.sleepCycles = 0
                    petInstance.say("wake")
                }
                return
            }
            petVisual.sleeping = false

            // hunger slows the worm down
            var energyFactor = petInstance.petState
                ? 0.5 + 0.5 * Math.max(0, petInstance.petState.energy / 100)
                : 1
            var forwardSpeed = (left + right) * 0.02 * energyFactor
            forwardSpeed = Math.min(4.2, forwardSpeed)
            moving = forwardSpeed > 0.05

            petVisual.currentSpeed = Math.max(0.4, Math.min(6.0,
                (Math.abs(left) + Math.abs(right)) * 0.02 * energyFactor))

            // hunger gates how hard the worm hunts: a full pet ambles past
            // food, a hungry one homes in. hunt = 1 at 0 energy, and
            // huntFloor at full energy (it still won't ignore a pellet that
            // is right in its path). Above foodLureEnergy the pet is "full"
            // and stops hunting entirely, wandering until energy drops again.
            var hunger = petInstance.petState
                ? 1 - Math.max(0, petInstance.petState.energy / 100)
                : 1
            var hunt = (petInstance.petState
                && petInstance.petState.energy > petInstance.foodLureEnergy)
                ? 0 : petInstance.huntFloor + (1 - petInstance.huntFloor) * hunger

            if (petInstance.petState) petInstance.petState.tick(100, moving)

            // --- go to sleep on your own ---
            if (petInstance.petState && !petInstance.petState.asleep
                && (petInstance.petState.sleepiness >= 1
                    || (petInstance.petState.energy <= 6 && petInstance.isNight))) {
                petInstance.petState.goSleep()
                petInstance.sleepCycles = 0
                petInstance.say("sleepy")
                return
            }

            // biological noise, suppressed while homing in on food
            var focus = Math.min(1, petInstance.lastSmellForward / 1.0)
            if (Math.random() < 0.05 * (1 - 0.75 * focus)) {
                petInstance.randomTurnFactor = (Math.random() - 0.5) * 15.0
            } else {
                petInstance.randomTurnFactor *= 0.8
            }
            // Brain-steered heading: the connectome's (left - right) imbalance
            // is a small but real signature; the dominant correction comes
            // from the odor gradient the probes read (see tuning notes above).
            // Random biological noise is damped while homing in on food. A
            // bump on a wall/obstacle still overrides `desired` below.
            var side = petInstance.lastSmellLeft - petInstance.lastSmellRight
            var gradientTurn = Math.max(-petInstance.maxGradientTurn,
                Math.min(petInstance.maxGradientTurn,
                    side * petInstance.gradientGain * hunt))
            var brainSteer = (left - right) * petInstance.brainTurnGain
                + gradientTurn
                + petInstance.randomTurnFactor * (1 - 0.7 * focus)
            petInstance.steerLean = petInstance.steerLean * (1 - petInstance.steerAlpha)
                + brainSteer * petInstance.steerAlpha

            var ang = petInstance.rotation
            var rad = ang * Math.PI / 180
            var fdx = Math.cos(rad)
            var fdy = Math.sin(rad)

            var maxX = petInstance.parent.width - petInstance.width
            var maxY = petInstance.parent.height - petInstance.height

            // --- propose the next position ---
            var nx = petInstance.x + fdx * forwardSpeed
            var ny = petInstance.y + fdy * forwardSpeed

            var desired = ang + petInstance.steerLean
            var contact = "none"
            var hit = false

            // 1) walls: mirror the heading across the wall (physics), and
            //    make the worm walk back a step so it can clear the edge.
            var rX = 1, rY = 1
            if (nx < petInstance.innerNudge) { nx = petInstance.innerNudge; rX = -1 }
            if (nx > maxX - petInstance.innerNudge) { nx = maxX - petInstance.innerNudge; rX = -1 }
            if (ny < petInstance.innerNudge) { ny = petInstance.innerNudge; rY = -1 }
            if (ny > maxY - petInstance.innerNudge) { ny = maxY - petInstance.innerNudge; rY = -1 }
            if (rX < 0 || rY < 0) {
                desired = Math.atan2(fdy * rY, fdx * rX) * 180 / Math.PI
                contact = "front"
                hit = true
            }

            // 2) obstacles: repulsion straight out of the nearest face,
            //    which produces a smooth curve around the decor instead of
            //    a hardcoded spin.
            var centerX = nx + petInstance.width / 2
            var centerY = ny + petInstance.height / 2
            var obstacles = petInstance.world ? petInstance.world.getObstacles() : []
            var bodyR = petInstance.bodyRadius
            for (var oi = 0; oi < obstacles.length; oi++) {
                var rect = obstacles[oi]
                var cl = petInstance.world.closestOnRect(rect, centerX, centerY)
                var vx = centerX - cl.x
                var vy = centerY - cl.y
                var d2 = vx * vx + vy * vy
                if (d2 < bodyR * bodyR && d2 > 0.0001) {
                    var d = Math.sqrt(d2)
                    // push the body back out to the obstacle surface
                    centerX = cl.x + vx / d * bodyR
                    centerY = cl.y + vy / d * bodyR
                    var normalAng = Math.atan2(vy / d, vx / d) * 180 / Math.PI
                    var diff = ((normalAng - desired + 540) % 360) - 180
                    desired = normalAng
                    contact = (Math.abs(diff) > 55) ? "front"
                            : (diff > 0 ? "left" : "right")
                    hit = true
                }
            }

            // 3) rate-limited turn toward the brain's goal --- or the escape direction
            //    in the cycle right after a bump: the worm curves toward food,
            //    it never teleports an angle.
            var delta = ((desired - petInstance.rotation + 540) % 360) - 180
            var rate = hit ? petInstance.hardTurnRate : petInstance.turnRate
            if (delta > rate) delta = rate
            if (delta < -rate) delta = -rate
            petInstance.rotation += delta

            petInstance.x = Math.max(0, Math.min(maxX, nx))
            petInstance.y = Math.max(0, Math.min(maxY, ny))

            if (hit && petInstance.brainController) {
                petInstance.brainController.stimulateTouch(contact)
            }

            if (petInstance.petState) petInstance.petState.addDistance(forwardSpeed)

            // --- sense the world for the NEXT cycle (chemotaxis) ---
            var cx = petInstance.x + petInstance.width / 2
            var cy = petInstance.y + petInstance.height / 2
            var rad2 = petInstance.rotation * Math.PI / 180
            var c = Math.cos(rad2)
            var s = Math.sin(rad2)

            var f0 = 0, l0 = 0, r0 = 0
            if (petInstance.world) {
                f0 = petInstance.world.smellAt(cx + c * petInstance.forwardProbe,
                    cy + s * petInstance.forwardProbe)
                var px = cx + c * petInstance.sideProbeForward
                var py = cy + s * petInstance.sideProbeForward
                l0 = petInstance.world.smellAt(px - s * petInstance.sideProbeSpread,
                    py + c * petInstance.sideProbeSpread)
                r0 = petInstance.world.smellAt(px + s * petInstance.sideProbeSpread,
                    py - c * petInstance.sideProbeSpread)
            }
            petInstance.lastSmellForward = f0
            petInstance.lastSmellLeft = l0
            petInstance.lastSmellRight = r0
            petInstance.brainController.setChemoSense(f0, l0, r0)

            // --- eat when the nose reaches a pellet ---
            if (petInstance.world && petInstance.world.eatAt(cx, cy, petInstance.eatReach)) {
                if (petInstance.petState) petInstance.petState.addMeal()
                petInstance.say("meal")
                petVisual.isStartled = true
                flashTimer.start()
            }

            // --- derived state for the HUD chip ---
            petInstance.stillCycles = moving ? 0 : (petInstance.stillCycles + 1)
            var peakSmell = Math.max(f0, Math.max(l0, r0))
            var grumpy = Date.now() - petInstance.lastHandTouchAt < 2500
            if (grumpy) {
                petInstance.setState("😾", "grumpy")
            } else if (peakSmell > 0.03 && hunt > 0.05) {
                petInstance.setState("🍎", "hunting")
            } else if (petInstance.petState && petInstance.petState.energy < 55) {
                petInstance.setState("🍽️", "hungry")
            } else if (petInstance.petState && petInstance.petState.energy > petInstance.foodLureEnergy) {
                petInstance.setState("😌", "full")
            } else if (petInstance.stillCycles >= 40) {
                petInstance.setState("🌿", "resting")
            } else {
                petInstance.setState("🔍", "exploring")
            }
        }
    }

    PetVisual {
        id: petVisual
        anchors.fill: parent
        rotation: 90 // Or -90, to align vertical drawing with horizontal movement vector
        transformOrigin: Item.Center

        // Pause the body wave while the brain is paused (panel hidden) and
        // while the pet naps.
        animating: petInstance.brainController
            ? petInstance.brainController.simulationActive
              && (!petInstance.petState || !petInstance.petState.asleep)
            : true

        // A click = real tactile stimulus on the connectome
        onClicked: {
            if (!petInstance.brainController) return
            petInstance.lastHandTouchAt = Date.now() // feeds the "grumpy" state
            petInstance.brainController.stimulateTouch("front")
            if (petInstance.petState && petInstance.petState.asleep) {
                petInstance.petState.wake()
                petInstance.sleepCycles = 0
                petInstance.say("wake")
            } else {
                petInstance.rotation += (Math.random() > 0.5 ? 90 : -90) + (Math.random() * 30 - 15)
                if (petInstance.petState) petInstance.petState.addStartle()
                petInstance.say("startle")
            }
            petVisual.isStartled = true
            flashTimer.start()
        }

        Timer {
            id: flashTimer
            interval: 800
            onTriggered: petVisual.isStartled = false
        }

        Timer {
            id: messageTimer
            interval: 2200
            onTriggered: petInstance.currentMessage = ""
        }

        // Drag the pet manually within the window
        onDragged: (dx, dy) => {
            if (!petInstance.parent) return
            var maxX = petInstance.parent.width - petInstance.width
            var maxY = petInstance.parent.height - petInstance.height
            petInstance.x = Math.max(0, Math.min(maxX, petInstance.x + dx))
            petInstance.y = Math.max(0, Math.min(maxY, petInstance.y + dy))
        }
    }

    // Speech bubble for funny reactions
    Rectangle {
        id: bubble
        visible: petInstance.currentMessage !== ""
        color: "white"
        radius: 8
        border.color: "#ccc"
        border.width: 1
        rotation: -petInstance.rotation // Counter-rotate to stay upright

        width: bubbleText.width + 20
        height: bubbleText.height + 10
        x: (petInstance.width - width) / 2
        y: -height - 10 // Positioned above the pet

        Text {
            id: bubbleText
            anchors.centerIn: parent
            text: petInstance.currentMessage
            color: "black"
            font.pixelSize: 12
            font.bold: true
        }
    }
}