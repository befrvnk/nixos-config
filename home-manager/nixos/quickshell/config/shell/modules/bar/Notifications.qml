import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common

// Notifications module — count badge on the bar; popup shows recent history
// (list + Clear All), kept minimal per design decision.
Item {
    id: root

    implicitWidth: Math.max(22, lbl.implicitWidth + 34)
    implicitHeight: 34

    ScriptPoll { id: countPoll; command: Config.notifCount; interval: 2000 }
    ScriptPoll { id: histPoll; command: Config.notifHistory; interval: 5000 }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: popup.open || ma.containsMouse ? Config.base02 : Config.base00
        opacity: 0.9
        border.color: Config.base03
        border.width: 1
    }

    Text {
        id: lbl
        anchors.centerIn: parent
        text: countPoll.text
        color: Config.base05
        font.family: Config.fontName
font.pixelSize: 16
    }

    Popup {
        id: popup
        anchor: root
        barSize: 52
        useContent: true
        content: Component {
            ColumnLayout {
                width: 280
                spacing: 8

                Text {
                    text: histPoll.text
                    color: Config.base05
                    font.family: "monospace"
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    radius: 6
                    color: Config.base02

                    Text {
                        anchors.centerIn: parent
                        text: "Clear All"
                        color: Config.base08
                        font.pixelSize: 12
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: Quickshell.exec(Config.notifClear.split(" "))
                    }
                }
            }
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
            popup.open = !popup.open
            if (popup.open) histPoll.refresh()
        }
    }
}