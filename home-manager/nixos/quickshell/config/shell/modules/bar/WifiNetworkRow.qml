import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Networking
import qs.modules.common

// A native WifiNetwork row. Open/known networks connect directly; unknown
// secured networks reveal a PSK input and call WifiNetwork.connectWithPsk().
Item {
    id: root

    property var network: null
    readonly property bool secured: network !== null && network.security !== WifiSecurityType.Open
    readonly property bool connected: network !== null && network.connected
    readonly property bool directConnect: !secured || (network !== null && network.known)
    property bool showPsk: false

    implicitHeight: 32 + (showPsk ? 32 : 0)

    RowLayout {
        id: mainRow
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 32
        spacing: 7

        Text {
            Layout.fillWidth: true
            text: root.network ? root.network.name : ""
            color: root.connected ? Config.base05 : Config.base05
            font.pixelSize: 13
            elide: Text.ElideRight
        }
        Text {
            text: root.secured ? "●" : ""
            color: Config.base05
            font.pixelSize: 9
            visible: root.secured
        }
        Text {
            text: root.connected ? "●" : ""
            color: Config.base05
            font.pixelSize: 9
            visible: root.connected
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                if (!root.network || root.connected) return
                if (root.directConnect) root.network.connect()
                else {
                    root.showPsk = !root.showPsk
                    if (root.showPsk) pskInput.forceActiveFocus()
                }
            }
        }
    }

    Rectangle {
        id: pskRow
        anchors { top: mainRow.bottom; left: parent.left; right: parent.right }
        height: 28
        radius: 7
        color: Config.base02
        visible: root.showPsk

        TextInput {
            id: pskInput
            anchors {
                left: parent.left
                right: connectButton.left
                verticalCenter: parent.verticalCenter
                leftMargin: 8
                rightMargin: 8
            }
            color: Config.base05
            echoMode: TextInput.Password
            font.pixelSize: 13
            selectByMouse: true
            onAccepted: {
                if (root.network) root.network.connectWithPsk(text)
                root.showPsk = false
            }
        }

        Rectangle {
            id: connectButton
            anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 4 }
            width: 60
            height: 22
            radius: 6
            color: Config.base03
            Text { anchors.centerIn: parent; text: "Connect"; color: Config.base05; font.pixelSize: 11 }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (root.network) root.network.connectWithPsk(pskInput.text)
                    root.showPsk = false
                }
            }
        }
    }
}