import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common

// Date + time pill in the center (ironbar style). Uses SystemClock; neutral text.
Item {
    implicitHeight: 34
    implicitWidth: lbl.implicitWidth + 34

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Config.base00
        border.color: Config.base03
        border.width: 1
        opacity: 0.95
    }

    Text {
        id: lbl
        anchors.centerIn: parent
        text: Qt.formatDateTime(clock.date, "ddd dd MMM  HH:mm")
        color: Config.base05
        font.family: Config.fontName
font.pixelSize: 16
        horizontalAlignment: Text.AlignHCenter
    }
}