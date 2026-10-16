import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Networking
import qs.modules.common

// Native WiFi pill — Quickshell.Networking replaces nmcli polling/scripts.
// Uses the NetworkManager backend: WifiDevice.networks are reactive and a
// WifiNetwork can connect directly or with a PSK.
Item {
    id: root

    readonly property var wifi: {
        for (const device of Networking.devices.values) {
            if (device.type === DeviceType.Wifi)
                return device
        }
        return null
    }
    readonly property var networks: wifi ? wifi.networks.values : []
    readonly property var currentNetwork: {
        for (const network of networks) {
            if (network.connected)
                return network
        }
        return null
    }
    readonly property bool connected: currentNetwork !== null
    readonly property string networkName: connected ? currentNetwork.name : "Disconnected"
    readonly property bool available: wifi !== null && Networking.backend === NetworkBackendType.NetworkManager

    readonly property int signal: {
        if (!connected || currentNetwork.signalStrength === undefined)
            return 0
        return Math.round(currentNetwork.signalStrength)
    }
    readonly property string icon: {
        if (!Networking.wifiEnabled) return "󰤭"
        if (!connected) return "󰤮"
        if (signal >= 75) return "󰤨"
        if (signal >= 50) return "󰤥"
        if (signal >= 25) return "󰤢"
        return "󰤟"
    }

    implicitWidth: Math.max(40, lbl.implicitWidth + 34)
    implicitHeight: 34
    visible: available

    function scan() {
        if (wifi) wifi.scannerEnabled = true
    }
    function connectNetwork(network, psk) {
        if (network.security === WifiSecurityType.Open) {
            network.connect()
        } else {
            network.connectWithPsk(psk)
        }
    }
    function disconnect() {
        if (wifi) wifi.disconnect()
    }
    function toggleWifi() {
        Networking.wifiEnabled = !Networking.wifiEnabled
        if (Networking.wifiEnabled) scan()
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
        text: icon + "  " + networkName
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
            if (popup.open) scan()
        }
    }

    Popup {
        id: popup
        anchor: root
        barSize: 52
        useContent: true
        content: Component {
            ColumnLayout {
                width: 330
                spacing: 7

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: Networking.wifiEnabled ? "WiFi enabled" : "WiFi disabled"
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
                            text: Networking.wifiEnabled ? "Turn off" : "Turn on"
                            color: Config.base05
                            font.pixelSize: 12
                        }
                        MouseArea { anchors.fill: parent; onClicked: root.toggleWifi() }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    radius: 8
                    color: Config.base02
                    Text {
                        anchors.centerIn: parent
                        text: "↻  Rescan"
                        color: Config.base05
                        font.family: Config.fontName
                        font.pixelSize: 13
                    }
                    MouseArea { anchors.fill: parent; onClicked: root.scan() }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    radius: 8
                    color: Config.base02
                    visible: root.connected
                    Text {
                        anchors.centerIn: parent
                        text: "Disconnect " + root.networkName
                        color: Config.base05
                        font.pixelSize: 13
                    }
                    MouseArea { anchors.fill: parent; onClicked: root.disconnect() }
                }

                Text {
                    text: "Networks"
                    color: Config.base05
                    font.pixelSize: 13
                    font.bold: true
                    Layout.topMargin: 4
                }

                Repeater {
                    model: root.networks
                    delegate: WifiNetworkRow {
                        Layout.fillWidth: true
                        network: modelData
                    }
                }

                Text {
                    visible: root.networks.length === 0 && Networking.wifiEnabled
                    text: "Scanning for networks…"
                    color: Config.base04
                    font.pixelSize: 12
                }
            }
        }
    }
}