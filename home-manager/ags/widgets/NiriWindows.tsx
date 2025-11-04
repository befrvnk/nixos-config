import { Gtk, Gdk, App } from "astal/gtk3"
import { bind } from "astal"
import Niri from "../services/niri"

function getIconForAppId(appId: string): string {
  // Map app_ids to icon names
  const iconMap: Record<string, string> = {
    "org.mozilla.firefox": "firefox",
    "chromium": "chromium",
    "org.gnome.Nautilus": "org.gnome.Nautilus",
    "org.gnome.Console": "org.gnome.Console",
    "kitty": "kitty",
    "alacritty": "Alacritty",
    "code": "visual-studio-code",
    "spotify": "spotify",
    "discord": "discord",
    "slack": "slack",
  }

  return iconMap[appId] || appId || "application-x-executable"
}

export default function NiriWindows() {
  const windows = bind(Niri.getWindows())

  return (
    <box className="window-icons bar-section" spacing={4}>
      {windows.as((wins) =>
        wins
          .filter((win) => {
            // Only show windows from focused workspace
            const workspaces = Niri.getWorkspaces()
            const focusedWs = workspaces.find((ws) => ws.is_focused)
            return focusedWs && win.workspace_id === focusedWs.id
          })
          .map((window) => (
            <button
              key={window.id}
              className={`window-icon ${window.is_focused ? "focused" : ""}`}
              onClicked={() => Niri.focusWindow(window.id)}
              tooltipText={window.title}
            >
              <icon
                icon={getIconForAppId(window.app_id)}
                css="font-size: 20px;"
              />
            </button>
          ))
      )}
    </box>
  )
}
