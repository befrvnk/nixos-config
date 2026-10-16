import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common

// A reusable bar module as a single pill (exactly matching ironbar): base00 bg,
// 1px base03 border, rounded corners, base05 text (neutral). showIf gating via
// script exit code (0 => show). Hidden when the label text is empty.
Item {
    id: root

    // Status (bar) label script + poll interval (ms).
    property string statusCmd: ""
    property int statusInterval: 3000
    // Popup text script + interval. Empty disables the popup.
    property string popupCmd: ""
    property int popupInterval: 5000
    // show_if script + interval (exit 0 = show); empty = always visible.
    property string showCmd: ""
    property int showInterval: 10000
    // Font size (matches ironbar 16px).
    property int fontSize: 16

    readonly property bool hasPopup: popupCmd !== ""

    implicitWidth: Math.max(22, (statusLbl ? statusLbl.implicitWidth : 0) + 34)
    implicitHeight: 34

    ScriptPoll { id: statusPoll; command: root.statusCmd; interval: root.statusInterval }
    ScriptPoll { id: showPoll; command: root.showCmd; interval: root.showInterval }
    ScriptPoll { id: popupPoll; command: root.popupCmd; interval: root.popupInterval }

    // Show when there's content, and (if gated) only when the show_if passes.
    visible: {
        const gated = root.showCmd === "" || showPoll.exitCode === 0
        return gated && statusPoll.text.trim() !== ""
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
        id: statusLbl
        anchors.centerIn: parent
        text: statusPoll.text
        color: Config.base05
        font.family: Config.fontName
font.pixelSize: root.fontSize
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    Popup {
        id: popup
        anchor: root
        barSize: 52
        text: popupPoll.text
        open: false
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        enabled: root.hasPopup
        hoverEnabled: true
        onClicked: {
            popup.open = !popup.open
            if (popup.open) popupPoll.refresh()
        }
    }
}