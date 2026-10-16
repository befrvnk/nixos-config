import QtQuick
import Quickshell
import Quickshell.Io

// Reusable component that runs a shell command path and exposes its stdout as
// `text` plus the exit code. Optionally polls on an interval. Non-blocking
// (Quickshell Process + StdioCollector).
Item {
    id: root

    // Absolute path of the script (store path, no spaces). May include args.
    property string command: ""
    // Polling interval in milliseconds. 0 disables periodic refresh.
    property int interval: 0
    // Trim trailing newlines from the output.
    property bool trim: true
    // Latest stdout (single line for bar labels).
    property string text: ""
    // Exit code of the last run (0 = success); -1 if not run / still running.
    property int exitCode: -1

    signal updated()

    Process {
        id: proc
        command: root.command.split(" ")
        stdout: StdioCollector {
            onStreamFinished: {
                root.text = root.trim ? this.text.trim() : this.text
                root.updated()
            }
        }
        // capture the exit status regardless of stdout content
        onExited: (code) => { root.exitCode = code == 0 ? 0 : 1 }
    }

    function refresh() {
        if (root.command === "") return
        proc.running = false
        proc.running = true
    }

    Timer {
        interval: root.interval
        running: root.command !== "" && root.interval > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}