import QtQuick

// 0..1 weight slider for the Circuit Lab synapses. Same look as LabSlider but
// the signal carries the new fraction so a Repeater/model row can update its
// model object without id captures.
Item {
    id: ws

    property real value: 0.5
    signal changedValue(real v)

    implicitWidth: 100
    implicitHeight: 14

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.12)
    }

    Rectangle {
        id: fill
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 2

        property real frac: sliderMouse.pressed ? sliderMouse.frac : ws.value
        width: (parent.width - 4) * Math.max(0, Math.min(1, frac))
        radius: (height - 4) / 2
        color: Qt.rgba(0.35, 1, 0.9, 0.55)
    }

    MouseArea {
        id: sliderMouse
        anchors.fill: parent
        property real frac: 0.5
        onPressed: { frac = clamp(); ws.value = frac; ws.changedValue(frac) }
        onPositionChanged: { if (pressed) { frac = clamp(); ws.value = frac; ws.changedValue(frac) } }
        function clamp() {
            if (ws.width <= 0) return 0.5
            return Math.max(0, Math.min(1, sliderMouse.mouseX / ws.width))
        }
    }
}