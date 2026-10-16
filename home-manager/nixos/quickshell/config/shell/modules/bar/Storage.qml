import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common

// Storage module — hidden when no removable devices. Bar shows icon + name/count.
// Popup renders each mounted device with an Open and Eject button (Phase 2).
Item {
    id: root

    implicitWidth: Math.max(22, lbl.implicitWidth + 34)
    implicitHeight: 34

    // Device list (JSON array of {name,used,size}) refreshed on popup open.
    property var devices: []

    ScriptPoll { id: statusPoll; command: Config.storageStatus; interval: 5000 }
    ScriptPoll { id: showPoll; command: Config.storageHas; interval: 5000 }
    ScriptPoll {
        id: listPoll
        command: Config.storageList
        interval: 5000
        onUpdated: parseDevices()
    }

    function parseDevices() {
        try {
            devices = JSON.parse(listPoll.text)
        } catch (e) {
            devices = []
        }
    }

    function reloadList() {
        listPoll.refresh()
    }

    // Show while devices are mounted; treat unknown (-1) as shown (avoid blink on start).
    visible: showPoll.exitCode !== 1

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
        text: statusPoll.text
        color: Config.base05
        font.family: Config.fontName
font.pixelSize: 16
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
            popup.open = !popup.open
            if (popup.open) reloadList()
        }
    }

    Popup {
        id: popup
        anchor: root
        barSize: 52
        useContent: true
        content: Component {
            ColumnLayout {
                width: 300
                spacing: 6

                Repeater {
                    model: root.devices

                    delegate: RowLayout {
                        width: parent.width
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: modelData.name + "  ·  " + modelData.used + "/" + modelData.size
                            color: Config.base05
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            Layout.preferredWidth: 44
                            Layout.preferredHeight: 26
                            radius: 6
                            color: Config.base02
                            Text {
                                anchors.centerIn: parent
                                text: "Open"
                                color: Config.base05
                                font.pixelSize: 11
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: Quickshell.execDetached([Config.storageOpen, String(model.index + 1)])
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 44
                            Layout.preferredHeight: 26
                            radius: 6
                            color: Config.base02
                            Text {
                                anchors.centerIn: parent
                                text: "⏏"
                                color: Config.base08
                                font.pixelSize: 12
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    Quickshell.execDetached([Config.storageEject, String(model.index + 1)])
                                    // Refresh the list shortly after (eject is async).
                                    Qt.callLater(() => { root.reloadList() })
                                }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillHeight: true
                }
            }
        }
    }
}