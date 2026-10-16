import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common

// A clickable row button that shows a label (from a polled status script) and
// runs a toggle command when clicked. Used for the display module's toggles.
Item {
    id: root

    property string labelValue: ""
    property string command: ""

    Layout.fillWidth: true
    implicitHeight: 28

    signal clicked()

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: ma.containsMouse ? Config.base03 : Config.base02
    }

    Text {
        anchors.centerIn: parent
        text: root.labelValue
        color: Config.base06
        font.pixelSize: 12
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
            if (root.command !== "") {
                Quickshell.execDetached([root.command])
            }
            root.clicked()
        }
    }
}