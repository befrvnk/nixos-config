import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs.modules.common

// Native peripheral battery pill. UPower exposes mice/keyboards/gaming devices
// reactively; include non-laptop generic batteries for vendor integrations such
// as Keychron that do not identify their device type correctly.
Item {
    id: root

    readonly property var devices: {
        const result = []
        for (const device of UPower.devices.values) {
            if (!device.isPresent || device.powerSupply)
                continue

            const knownPeripheral = [
                UPowerDeviceType.Mouse,
                UPowerDeviceType.Keyboard,
                UPowerDeviceType.GamingInput,
                UPowerDeviceType.Headset,
                UPowerDeviceType.Headphones,
            ].includes(device.type)
            const genericPeripheralBattery = device.type === UPowerDeviceType.Battery && !device.isLaptopBattery

            if (knownPeripheral || genericPeripheralBattery)
                result.push(device)
        }
        return result
    }

    readonly property string label: devices.map(device => {
        let icon = "󰂀"
        if (device.type === UPowerDeviceType.Mouse) icon = "󰍽"
        else if (device.type === UPowerDeviceType.Keyboard) icon = "󰌌"
        else if (device.type === UPowerDeviceType.GamingInput) icon = "󰊴"
        if (device.state === UPowerDeviceState.Charging) icon += "󱐋"
        return icon + "  " + Math.round(device.percentage * 100) + "%"
    }).join("    ")

    implicitWidth: Math.max(40, lbl.implicitWidth + 34)
    implicitHeight: 34
    visible: devices.length > 0

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Config.base00
        opacity: 0.95
        border.color: Config.base03
        border.width: 1
    }

    Text {
        id: lbl
        anchors.centerIn: parent
        text: label
        color: Config.base05
        font.family: Config.fontName
        font.pixelSize: 16
    }
}