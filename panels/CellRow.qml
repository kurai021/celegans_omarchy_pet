import QtQuick
import "ConnectomeGraph.js" as GraphData

// Small per-cell charge/fire readout reused for the Lab channels. Shows one
// coloured square per target cell (charge level) with a "!" when it fired on
// the last sampled cycle, plus the accumulated fire count for the set.
Item {
    id: cr
    property string title: ""
    property int count: 0
    property var cells: []
    property var src: null
    height: 21
    width: parent ? parent.width : 200

    Row {
        anchors.fill: parent
        spacing: 5

        Text {
            text: cr.title
            width: 76
            elide: Text.ElideRight
            color: Qt.rgba(0.82, 0.9, 0.88, 1)
            font.pixelSize: 10
            anchors.verticalCenter: parent.verticalCenter
        }

        Repeater {
            model: cr.cells
            delegate: Rectangle {
                property int ci: GraphData.graphNodes().indexOf(modelData)
                width: 14
                height: 14
                radius: 3
                anchors.verticalCenter: parent.verticalCenter
                color: {
                    var ch = (cr.src && ci !== -1) ? (cr.src.charges[ci] || 0) : 0
                    return Qt.rgba(0.25 + 0.55 * ch, 1 - 0.25 * ch, 0.9 - 0.45 * ch, 0.3 + 0.7 * ch)
                }
                border.width: (cr.src && ci !== -1 && cr.src.fired && cr.src.fired[ci]) ? 1.5 : 0
                border.color: "white"
                Text {
                    visible: !!(cr.src && ci !== -1 && cr.src.fired && cr.src.fired[ci])
                    anchors.centerIn: parent
                    text: "!"
                    color: "white"
                    font.pixelSize: 9
                    font.bold: true
                }
            }
        }

        Text {
            text: cr.count + " fires"
            color: Qt.rgba(0.55, 0.65, 0.65, 1)
            font.pixelSize: 9
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}