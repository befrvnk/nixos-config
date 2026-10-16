import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common

// A minimal horizontal slider built from base QtQuick primitives (no
// QtQuick.Controls dependency). Drags its handle to set a value 0..100.
Item {
    id: root

    property real value: 0
    property real from: 0
    property real to: 100
    signal changed(real value)
    signal committed(real value)

    implicitHeight: 24
    width: parent ? parent.width : 200

    Rectangle {
        id: track
        height: 4
        width: parent.width
        anchors.verticalCenter: parent.verticalCenter
        radius: 2
        color: Config.base03

        Rectangle {
            id: fill
            height: parent.height
            width: (thumb.x + thumb.width/2)
            radius: 2
            color: Config.base0B
        }

        Rectangle {
            id: thumb
            width: 14; height: 14; radius: 7
            anchors.verticalCenter: parent.verticalCenter
            x: (root.to > root.from)
                ? ((root.value - root.from) / (root.to - root.from)) * (track.width - width)
                : 0
            color: Config.base06
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        onPressed: (mouse) => updateFromMouse(mouse.x)
        onPositionChanged: {
            if (pressed) { updateFromMouse(mouse.x); committedInternal = true }
        }
        onReleased: if (committedInternal) { root.committed(root.value); committedInternal = false }
    }

    property bool committedInternal: false

    function updateFromMouse(x) {
        if (track.width <= 0) return
        const frac = Math.min(1, Math.max(0, x / track.width))
        root.value = Math.round(root.from + (root.to - root.from) * frac)
        root.changed(root.value)
    }

    // stub internals
    property string _unused: ""
}