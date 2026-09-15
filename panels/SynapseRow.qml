import QtQuick

// One editable synapse in the Circuit Lab: "FROM → TO" with its real base
// weight and a slider that overrides it (absolute weight 0..maxWeight).
// `changed()` fires with the new weight, `remove()` when the patch should go
// away. Deliberately self-contained (no QtQuick.Controls) like the rest.
Item {
    id: row

    property string from: ""
    property string to: ""
    property real base: 0
    property real weight: base
    property real maxWeight: 30
    property bool live: false            // show the value chip as "live patch"
    signal changed(real w)
    signal remove()

    height: 50
    width: parent ? parent.width : 220

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: row.live ? Qt.rgba(0.35, 0.9, 0.7, 0.12) : Qt.rgba(1, 1, 1, 0.05)
        border.color: row.live ? Qt.rgba(0.45, 1, 0.85, 0.4) : Qt.rgba(0.45, 1, 0.9, 0.12)
        border.width: 1

        Column {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 2

            Row {
                width: parent.width
                spacing: 4

                Text {
                    text: row.from + " → " + row.to
                    color: "white"
                    font.pixelSize: 10
                    font.bold: true
                    elide: Text.ElideRight
                    width: 116
                }

                Text {
                    text: "base " + row.base
                    color: Qt.rgba(0.55, 0.65, 0.65, 1)
                    font.pixelSize: 9
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: row.weight === row.base ? "= " + row.base : "→ " + row.weight
                    color: row.weight === row.base ? Qt.rgba(0.6, 0.7, 0.7, 1)
                        : (row.weight > row.base ? "#6fdd8c" : "#e08a6a")
                    font.pixelSize: 9
                    font.bold: row.weight !== row.base
                    anchors.verticalCenter: parent.verticalCenter
                }

                Item { width: parent.parent.width - 230; height: 1 }

                Text {
                    text: "✕"
                    color: Qt.rgba(0.9, 0.6, 0.6, 1)
                    font.pixelSize: 10
                    anchors.verticalCenter: parent.verticalCenter
                    MouseArea {
                        anchors.fill: parent
                        onClicked: row.remove()
                    }
                }
            }

            Row {
                width: parent.width
                spacing: 4

                WeightSlider {
                    id: slider
                    width: parent.width - 64
                    value: Math.max(0, Math.min(1, row.weight / row.maxWeight))
                    onChangedValue: {
                        row.weight = v * row.maxWeight
                        row.changed(row.weight)
                    }
                }

                Text {
                    text: "0"
                    color: Qt.rgba(0.75, 0.8, 0.8, 1)
                    font.pixelSize: 8
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: "∓"
                    color: Qt.rgba(0.7, 1, 0.95, 1)
                    font.pixelSize: 10
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            row.weight = row.weight === 0 ? -Math.max(1, Math.abs(row.base)) : -row.weight
                            slider.value = Math.max(0, Math.min(1, row.weight / row.maxWeight))
                            row.changed(row.weight)
                        }
                    }
                }
            }
        }
    }
}