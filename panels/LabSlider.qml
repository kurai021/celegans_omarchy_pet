import QtQuick

// Tiny reusable Lab control: a 0..1 slider on a track. Kept dependency-free
// (no QtQuick.Controls) to match the rest of the plugin's plain QtQuick style.
Item {
    id: slider

    property real value: 0.5
    property alias interactive: mouse.enabled
    property bool showValue: false
    signal changed()

    implicitWidth: 100
    implicitHeight: 18

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

        property real frac: mouse.pressed ? mouse.frac : slider.value
        width: (parent.width - 4) * Math.max(0, Math.min(1, frac))
        radius: (height - 4) / 2
        color: Qt.rgba(0.35, 1, 0.9, 0.55)
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        property real frac: 0.5
        onPressed: { frac = clamp()
                     slider.value = frac; slider.changed() }
        onPositionChanged: { if (pressed) { frac = clamp(); slider.value = frac; slider.changed() } }
        function clamp() {
            if (slider.width <= 0) return 0.5
            return Math.max(0, Math.min(1, mouseX / slider.width))
        }
    }

    Text {
        visible: slider.showValue
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        text: (slider.value * 100).toFixed(0)
        color: "white"
        font.pixelSize: 10
    }
}