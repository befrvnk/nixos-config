import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common

// Display module: bar shows brightness + stay-on indicator. Popup has a
// brightness slider, plus toggles for ABM, Stay On, and Night Light (Phase 3).
Item {
    id: root

    property int brightness: 50

    implicitWidth: Math.max(22, lbl.implicitWidth + 34)
    implicitHeight: 34

    ScriptPoll {
        id: statusPoll
        command: Config.displayStatus
        interval: 2000
        onUpdated: {
            const m = statusPoll.text.match(/(\d+)%/)
            root.brightness = m ? Math.min(100, Math.max(0, parseInt(m[1]))) : 0
        }
    }
    ScriptPoll { id: abmPoll; command: Config.displayAbmBtn; interval: 2000 }
    ScriptPoll { id: stayPoll; command: Config.displayStayBtn; interval: 2000 }
    ScriptPoll { id: redPoll; command: Config.displayRedlightBtn; interval: 2000 }

    function refreshAll() {
        statusPoll.refresh(); abmPoll.refresh(); stayPoll.refresh(); redPoll.refresh()
    }
    function toggle(cmd) {
        Quickshell.execDetached([cmd])
        Qt.callLater(() => refreshAll())
    }

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
        onClicked: { popup.open = !popup.open; if (popup.open) refreshAll() }
    }

    Popup {
        id: popup
        anchor: root
        barSize: 52
        useContent: true
        content: Component {
            ColumnLayout {
                width: 270
                spacing: 8

                Text { text: "Brightness  " + root.brightness + "%"; color: Config.base06; font.pixelSize: 12 }

                Slider {
                    id: brightSlider
                    Layout.fillWidth: true
                    from: 0; to: 100
                    value: root.brightness
                    onCommitted: (v) => Quickshell.execDetached([Config.brightnessSet, String(Math.round(v))])
                }

                RowBtn { labelValue: abmPoll.text;    command: Config.displayAbmToggle;   onClicked: root.refreshAll() }
                RowBtn { labelValue: stayPoll.text;   command: Config.displayStayToggle;  onClicked: root.refreshAll() }
                RowBtn { labelValue: redPoll.text;    command: Config.displayRedlightToggle; onClicked: root.refreshAll() }
            }
        }
    }
}