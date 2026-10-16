import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs.modules.common

// Native battery pill — uses Quickshell's UPower service for live percentage,
// state and charge. Power-profile switching still drives your tuned-adm setup
// (framework profiles) via the existing scripts, since your config is tuned-based.
Item {
    id: root

    readonly property var dev: UPower.displayDevice
    readonly property bool hasBattery: dev !== null && !!dev.isLaptopBattery
    readonly property int pct: hasBattery ? Math.round(dev.percentage * 100) : -1
    readonly property bool charging: hasBattery && (dev.state === UPowerDeviceState.Charging)
    readonly property bool full: hasBattery && (dev.state === UPowerDeviceState.FullyCharged)

    property string currentProfile: ""

    readonly property string icon: {
        if (!hasBattery) return "󰂑"
        if (charging) {
            if (pct >= 90) return "󰂅"
            if (pct >= 70) return "󰂋"
            if (pct >= 50) return "󰂉"
            if (pct >= 30) return "󰂇"
            if (pct >= 10) return "󰢝"
            return "󰢜"
        } else if (full) {
            return "󰁹"
        } else {
            if (pct >= 90) return "󰁹"
            if (pct >= 80) return "󰂂"
            if (pct >= 70) return "󰂁"
            if (pct >= 60) return "󰂀"
            if (pct >= 50) return "󰁿"
            if (pct >= 40) return "󰁾"
            if (pct >= 30) return "󰁽"
            if (pct >= 20) return "󰁼"
            if (pct >= 10) return "󰁻"
            return "󰁺"
        }
    }

    implicitWidth: Math.max(40, lbl.implicitWidth + 34)
    implicitHeight: 34
    visible: hasBattery

    // Current tuned profile (scripts) for highlighting.
    ScriptPoll {
        id: profilePoll
        command: Config.batteryGetProfile
        interval: 5000
        onUpdated: root.currentProfile = profilePoll.text.trim()
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: popup.open || maa.containsMouse ? Config.base02 : Config.base00
        border.color: Config.base03
        border.width: 1
        opacity: 0.95
    }

    Text {
        id: lbl
        anchors.centerIn: parent
        text: icon + "  " + (hasBattery ? pct + "%" : "—")
        color: Config.base05
        font.family: Config.fontName
        font.pixelSize: 16
    }

    MouseArea {
        id: maa
        anchors.fill: parent
        hoverEnabled: true
        onClicked: { popup.open = !popup.open; if (popup.open) profilePoll.refresh() }
    }

    Popup {
        id: popup
        anchor: root
        barSize: 52
        useContent: true
        content: Component {
            ColumnLayout {
                width: 240
                spacing: 8

                Text {
                    text: icon + "  " + pct + "%"
                    color: Config.base05
                    font.family: Config.fontName
                    font.pixelSize: 16
                }
                Text {
                    text: charging ? "Charging" : (full ? "Fully charged" : "On battery")
                    color: Config.base04
                    font.pixelSize: 12
                }

                Text { text: "Power profile"; color: Config.base05; font.pixelSize: 12; font.bold: true; Layout.topMargin: 6 }

                Repeater {
                    model: [
                        { name: "low-power",   label: "Low power" },
                        { name: "balanced",    label: "Balanced" },
                        { name: "performance", label: "Performance" },
                    ]
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        radius: 8
                        color: root.currentProfile === modelData.name
                            ? Qt.rgba(0.5, 0.8, 0.6, 0.35)
                            : Config.base02

                        Text {
                            anchors.centerIn: parent
                            text: modelData.label + (root.currentProfile === modelData.name ? "   ●" : "")
                            color: Config.base05
                            font.pixelSize: 13
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                Quickshell.execDetached([Config.batterySetProfile, modelData.name])
                                Qt.callLater(() => profilePoll.refresh())
                            }
                        }
                    }
                }
            }
        }
    }
}