import { Gtk } from "astal/gtk3"
import { bind } from "astal"
import Niri from "../services/niri"

export default function NiriWorkspaces() {
  const workspaces = bind(Niri.getWorkspaces())

  return (
    <box className="workspaces bar-section" spacing={4}>
      {workspaces.as((ws) =>
        ws.map((workspace) => (
          <button
            key={workspace.id}
            className={`workspace ${workspace.is_active ? "active" : ""} ${
              workspace.is_focused ? "focused" : ""
            }`}
            onClicked={() => Niri.focusWorkspace(workspace.idx)}
          >
            <label
              label={
                workspace.name || workspace.idx.toString()
              }
            />
          </button>
        ))
      )}
    </box>
  )
}
