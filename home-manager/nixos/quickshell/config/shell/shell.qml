import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Niri
import "./modules/bar/"

// Quickshell scaffold — an overview-only top bar using the Option B binding.
// The bar is visible only while niri's overview is open.
ShellRoot {
    id: root

    Niri {
        id: niri
        Component.onCompleted: connect()

        onConnected: () => console.info("[quickshell] connected to niri")
        onErrorOccurred: (error) => console.error("[quickshell] niri error:", error)
    }

    LazyLoader {
        active: true
        component: Bar {}
    }
}