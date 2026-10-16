import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs.modules.common

// Native Bluetooth pill — Quickshell.Bluetooth replaces bluetoothctl polling.
// Device state is reactive; devices support connect/disconnect/pair directly.
Item {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool available: adapter !== null
    readonly property var devices: Bluetooth.devices.values
    readonly property bool enabled: available && adapter.enabled
    readonly property int connectedCount: {
        let count = 0
        for (const device of devices) {
            if (device.connected) count++
        }
        return count
    }

    implicitWidth: Math.max(40, lbl.implicitWidth + 34)
    implicitHeight: 34
    visible: available

    // Match the old bar: explicitly expose a disabled adapter, rather than
    // rendering an ambiguous bare Bluetooth icon.
    readonly property string label: !enabled
        ? "󰂯  Off"
        : "󰂯" + (connectedCount > 0 ? "  " + connectedCount : "")

    function toggleEnabled() {
        if (adapter) adapter.enabled = !adapter.enabled
    }
    function startDiscovery() {
        if (adapter && adapter.enabled) adapter.discovering = true
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: popup.open || ma.containsMouse ? Config.base02 : Config.base00
        border.color: Config.base03
        border.width: 1
        opacity: 0.95
    }

    Text {
        id: lbl
        anchors.centerIn: parent
        text: label
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
            if (popup.open) startDiscovery()
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
                spacing: 7

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: adapter && adapter.enabled ? "Bluetooth enabled" : "Bluetooth disabled"
                        color: Config.base05
                        font.pixelSize: 13
                    }
                    Rectangle {
                        Layout.preferredWidth: 72
                        Layout.preferredHeight: 30
                        radius: 8
                        color: Config.base02
                        Text {
                            anchors.centerIn: parent
                            text: adapter && adapter.enabled ? "Turn off" : "Turn on"
                            color: Config.base05
                            font.pixelSize: 12
                        }
                        MouseArea { anchors.fill: parent; onClicked: root.toggleEnabled() }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    radius: 8
                    color: Config.base02
                    visible: adapter && adapter.enabled
                    Text {
                        anchors.centerIn: parent
                        text: adapter && adapter.discovering ? "Scanning…" : "Scan devices"
                        color: Config.base05
                        font.pixelSize: 13
                    }
                    MouseArea { anchors.fill: parent; onClicked: root.startDiscovery() }
                }

                Text {
                    text: "Devices"
                    color: Config.base05
                    font.pixelSize: 13
                    font.bold: true
                    Layout.topMargin: 4
                }

                Repeater {
                    model: root.devices
                    delegate: RowLayout {
                        Layout.fillWidth: true
                        spacing: 7

                        Text {
                            Layout.fillWidth: true
                            text: modelData.name || modelData.deviceName || modelData.address
                            color: Config.base05
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }
                        Text {
                            text: modelData.batteryAvailable ? Math.round(modelData.battery * 100) + "%" : ""
                            color: Config.base04
                            font.pixelSize: 11
                        }
                        Rectangle {
                            Layout.preferredWidth: modelData.connected ? 78 : (modelData.paired ? 64 : 50)
                            Layout.preferredHeight: 30
                            radius: 8
                            color: Config.base02
                            Text {
                                anchors.centerIn: parent
                                text: modelData.connected ? "Disconnect" : (modelData.paired ? "Connect" : "Pair")
                                color: Config.base05
                                font.pixelSize: 12
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (modelData.connected) modelData.disconnect()
                                    else if (modelData.paired) modelData.connect()
                                    else modelData.pair()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}