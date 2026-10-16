import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common

// One row in the WiFi popup: network name + lock indicator. Clicking an open
// network connects immediately; clicking a secured network reveals an inline
// password input with a Connect button.
Item {
    id: row

    property string name: ""
    property bool secured: false
    signal connectRequested(string name, string password)

    height: maRow.height + (showPassword ? pwBox.height : 0)
    width: parent ? parent.width : 0

    RowLayout {
        id: maRow
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 28
        spacing: 6

        Text {
            Layout.fillWidth: true
            text: row.name
            color: Config.base06
            font.pixelSize: 12
            elide: Text.ElideRight
        }
        Text {
            text: row.secured ? "●" : ""
            color: Config.base0B
            font.pixelSize: 8
            visible: row.secured
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                if (row.secured) {
                    row.showPassword = !row.showPassword
                    if (row.showPassword) pwInput.forceActiveFocus()
                } else {
                    row.connectRequested(row.name, "")
                }
            }
        }
    }

    property bool showPassword: false

    Rectangle {
        id: pwRow
        anchors { top: maRow.bottom; left: parent.left; right: parent.right }
        height: 28
        radius: 5
        color: Config.base02
        visible: row.showPassword

        TextInput {
            id: pwInput
            anchors { left: parent.left; right: goBtn.left; verticalCenter: parent.verticalCenter; leftMargin: 8; rightMargin: 6 }
            color: Config.base06
            echoMode: TextInput.Password
            font.pixelSize: 12
            selectByMouse: true
        }

        Rectangle {
            id: goBtn
            anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 4 }
            width: 52; height: 20; radius: 4; color: Config.base0B
            Text { anchors.centerIn: parent; text: "Connect"; color: "#111"; font.pixelSize: 10 }
            MouseArea { anchors.fill: parent
                onClicked: { row.connectRequested(row.name, pwInput.text); row.showPassword = false }
            }
        }
    }
}