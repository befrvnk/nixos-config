import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.modules.common

// Native status-notifier app tray. SystemTray.items is an UntypedObjectModel;
// use .values for a reactive JS list so an empty tray does not render a pill.
Item {
    id: tray

    readonly property var items: SystemTray.items.values
    readonly property bool hasActive: items.some(item => item.status !== Status.Passive)

    implicitHeight: 34
    implicitWidth: row.implicitWidth + 28
    visible: hasActive

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Config.base00
        opacity: 0.95
        border.color: Config.base03
        border.width: 1
    }

    Row {
        id: row
        spacing: 5
        anchors.centerIn: parent

        Repeater {
            model: tray.items

            delegate: Item {
                readonly property var item: modelData
                visible: item.status !== Status.Passive
                width: 24
                height: 24

                IconImage {
                    anchors.centerIn: parent
                    height: 20
                    width: 20
                    source: item.icon
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: {
                        if (mouse.button === Qt.LeftButton) item.activate()
                        else if (mouse.button === Qt.RightButton) item.secondaryActivate()
                    }
                }
            }
        }
    }
}