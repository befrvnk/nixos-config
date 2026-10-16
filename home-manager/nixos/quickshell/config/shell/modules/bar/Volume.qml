import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import qs.modules.common

// Native volume pill — uses Quickshell's Pipewire service directly (no scripts):
// real-time reactive volume/mute. The default sink is bound via PwObjectTracker
// (volume/muted are only valid on a bound node), and we read node.audio.*.
Item {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool hasSink: sink !== null
    // Audio props are only valid once the node is ready and has audio.
    readonly property bool ready: hasSink && !!sink.ready && sink.audio !== null

    // Bound copy of the sink so its audio volume/mute are valid/reactive.
    PwObjectTracker {
        objects: [ Pipewire.defaultAudioSink ]
    }

    readonly property bool isMuted: ready ? sink.audio.muted : false
    // Show 0 when muted (matches the label "icon 0%"). Keep the real level
    // available for the slider separately.
    readonly property int rawPct: ready ? Math.round(sink.audio.volume * 100) : 0
    readonly property int pct: isMuted ? 0 : rawPct

    readonly property string icon: {
        if (!hasSink) return "󰖁"
        if (isMuted || pct === 0) return "󰖁"
        if (pct < 33) return "󰕿"
        if (pct < 66) return "󰖀"
        return "󰕾"
    }

    implicitWidth: Math.max(40, lbl.implicitWidth + 34)
    implicitHeight: 34

    function setVol(v) {
        if (ready) {
            sink.audio.muted = false
            sink.audio.volume = Math.max(0, Math.min(1, v / 100))
        }
    }
    function toggleMute() {
        if (ready) sink.audio.muted = !sink.audio.muted
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
        text: icon + "  " + pct + "%"
        color: Config.base05
        font.family: Config.fontName
        font.pixelSize: 16
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        onClicked: popup.open = !popup.open
    }

    Popup {
        id: popup
        anchor: root
        barSize: 52
        useContent: true
        content: Component {
            ColumnLayout {
                width: 220
                spacing: 10

                Text {
                    text: icon + "  " + pct + "%"
                    color: Config.base05
                    font.family: Config.fontName
                    font.pixelSize: 16
                }

                Slider {
                    id: volSlider
                    Layout.fillWidth: true
                    from: 0
                    to: 100
                    value: root.pct
                    onCommitted: (v) => root.setVol(Math.round(v))
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    radius: 8
                    color: Config.base02
                    Text {
                        anchors.centerIn: parent
                        text: root.isMuted ? "Unmute" : "Mute"
                        color: Config.base05
                        font.pixelSize: 13
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.toggleMute()
                    }
                }
            }
        }
    }
}