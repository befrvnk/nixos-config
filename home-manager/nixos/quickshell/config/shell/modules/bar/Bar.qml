import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common

// Overview-only top bar. Visibility driven by Option B (niri.overview.isOpen).
// Transparent background: modules render as floating pills (ironbar style).
// Pills get consistent padding: between modules (spacing), from the row's
// horizontal edge, and from the screen sides.
PanelWindow {
    id: bar
    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: 54
    color: "transparent"
    visible: niri.overview.isOpen

    // Shared horizontal padding: same value for pills-between-pills spacing and
    // the screen-edge gap, so spacing is consistent horizontally.
    readonly property int edgePadding: 16
    readonly property int pillSpacing: 16
    readonly property int topPadding: 8

    // LEFT — start region
    RowLayout {
        id: leftRow
        anchors {
            left: parent.left
            top: parent.top
            leftMargin: bar.edgePadding
            topMargin: bar.topPadding
        }
        spacing: bar.pillSpacing

        OpenRouter {}
        Firewall {}
        SysInfo {}
    }

    // CENTER region
    RowLayout {
        id: centerRow
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: bar.topPadding
        spacing: bar.pillSpacing

        Aurora {}
        Weather {}
        Clock {}
        Notifications {}
    }

    // RIGHT — end region
    RowLayout {
        id: rightRow
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: bar.edgePadding
        anchors.topMargin: bar.topPadding
        spacing: bar.pillSpacing

        Tray {}
        Storage {}
        Volume {}
        Display {}
        Wifi {}
        Bluetooth {}
        PeripheralBattery {}
        Battery {}
    }
}