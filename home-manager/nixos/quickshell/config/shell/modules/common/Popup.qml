import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.modules.common

// A popup panel that appears beneath a bar module. Created on demand via a
// LazyLoader + PanelWindow. Positioned under the anchor module and clamped to
// the screen edges. Repositioning is driven by a Timer so it always runs a
// frame after the window is created/mapped (avoids exceptions at creation time).
Item {
    id: root

    property bool open: false
    property Item anchor: null
    property string text: ""
    property int barSize: 52
    // Optional custom content (Component); when set it is loaded instead of text.
    property Component content: null
    property bool useContent: content !== null

    onOpenChanged: {
        if (open) {
            Qt.callLater(() => { repositionTimer.restart() })
        }
    }

    Timer {
        id: repositionTimer
        interval: 40
        repeat: false
        onTriggered: {
            if (popupLoader.item) popupLoader.item.reposition()
        }
    }

    LazyLoader {
        id: popupLoader
        active: root.open

        component: PanelWindow {
            id: popupWindow
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore

            anchors { left: true; top: true }
            margins { top: root.barSize }

            property int offsetX: 0

            // Recompute if the popup's own size changes after it opens.
            onImplicitWidthChanged: Qt.callLater(() => reposition())

            function reposition() {
                if (!root.anchor) return
                const barWin = root.anchor.QsWindow
                if (!barWin) return
                const moduleLeft = barWin.mapFromItem(root.anchor, 0, 0).x
                const w = popupWindow.implicitWidth || 200
                // Center under the module; clamp so it never leaves the screen.
                let off = Math.round(moduleLeft - (w - root.anchor.width) / 2)
                const avail = barWin.width
                if (avail > 0) {
                    off = Math.max(0, Math.min(off, avail - w))
                }
                offsetX = off
                margins.left = off
            }

            implicitWidth: contentPop.implicitWidth
            implicitHeight: contentPop.implicitHeight

            Rectangle {
                id: contentPop
                color: Config.base01
                radius: 10
                border.color: Config.base03
                border.width: 1
                implicitWidth: Math.max(200, root.useContent ? 220 : popupBody.implicitWidth + 24)
                implicitHeight: Math.min(420, (root.useContent ? custom.implicitHeight : popupBody.implicitHeight) + 24)

                Loader {
                    id: custom
                    anchors.fill: parent
                    anchors.margins: 6
                    visible: root.useContent
                    sourceComponent: root.content
                }

                Text {
                    id: popupBody
                    anchors.fill: parent
                    anchors.margins: 12
                    visible: !root.useContent
                    text: root.text
                    color: Config.base05
                    font.family: "monospace"
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }
            }
        }
    }
}