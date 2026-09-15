import QtQuick

// Small labelled text field for the Circuit Lab (cell name pickers). Same
// plain-QtQuick style as the rest: a TextEdit with a dim placeholder, emits
// edited(v) on every edit.
Item {
    id: field

    property string value: ""
    property string placeholder: ""
    signal edited(string v)

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: Qt.rgba(1, 1, 1, 0.05)
        border.color: Qt.rgba(0.9, 0.75, 1, 0.2)
        border.width: 1

        TextInput {
            id: input
            anchors.fill: parent
            anchors.margins: 6
            color: "white"
            font.pixelSize: 11
            selectByMouse: true
            verticalAlignment: TextInput.AlignVCenter
            text: field.value
            renderType: Text.NativeRendering

            onTextChanged: field.edited(text)
        }
    }

    Text {
        visible: input.text.length === 0
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        anchors.topMargin: 3
        verticalAlignment: TextInput.AlignVCenter
        text: field.placeholder
        color: Qt.rgba(0.6, 0.6, 0.65, 1)
        font.pixelSize: 11
    }
}