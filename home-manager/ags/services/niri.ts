import { GLib, Gio } from "astal"
import { Variable } from "astal"

// Types for Niri IPC responses
export interface NiriWindow {
  id: number
  title: string
  app_id: string
  workspace_id: number
  is_focused: boolean
}

export interface NiriWorkspace {
  id: number
  name?: string
  idx: number
  is_active: boolean
  is_focused: boolean
  output: string
  windows: NiriWindow[]
}

export interface NiriOutput {
  name: string
  make: string
  model: string
  workspaces: NiriWorkspace[]
}

class NiriService {
  private socketPath: string
  private workspaces = Variable<NiriWorkspace[]>([])
  private windows = Variable<NiriWindow[]>([])
  private focusedWindow = Variable<NiriWindow | null>(null)

  constructor() {
    // Get Niri IPC socket path from environment
    this.socketPath = GLib.getenv("NIRI_SOCKET") || ""

    if (!this.socketPath) {
      console.error("NIRI_SOCKET environment variable not set")
      return
    }

    // Initial data fetch
    this.refresh()

    // Subscribe to Niri events
    this.subscribeToEvents()
  }

  private async sendCommand(command: string): Promise<any> {
    try {
      const socketAddr = Gio.UnixSocketAddress.new(this.socketPath)
      const client = new Gio.SocketClient()
      const connection = await client.connect_async(socketAddr, null)
      const outputStream = connection.get_output_stream()
      const inputStream = connection.get_input_stream()

      // Send command
      const commandJson = JSON.stringify({ action: command }) + "\n"
      await outputStream.write_async(
        new TextEncoder().encode(commandJson),
        GLib.PRIORITY_DEFAULT,
        null
      )

      // Read response
      const [bytes] = await inputStream.read_bytes_async(
        8192,
        GLib.PRIORITY_DEFAULT,
        null
      )

      const response = new TextDecoder().decode(bytes.get_data())
      connection.close(null)

      return JSON.parse(response)
    } catch (error) {
      console.error("Error communicating with Niri:", error)
      return null
    }
  }

  private subscribeToEvents() {
    // Monitor socket for events
    // In a real implementation, you would keep a persistent connection
    // and listen for events. For now, we'll poll periodically.

    // Poll every 500ms for updates
    GLib.timeout_add(GLib.PRIORITY_DEFAULT, 500, () => {
      this.refresh()
      return true
    })
  }

  private async refresh() {
    try {
      const outputs = await this.sendCommand("Workspaces")

      if (!outputs || !outputs.Ok) return

      const allWorkspaces: NiriWorkspace[] = []
      const allWindows: NiriWindow[] = []
      let focused: NiriWindow | null = null

      // Process outputs and collect workspaces and windows
      for (const output of outputs.Ok) {
        for (const ws of output.workspaces) {
          allWorkspaces.push({
            id: ws.id,
            name: ws.name,
            idx: ws.idx,
            is_active: ws.is_active,
            is_focused: ws.is_focused,
            output: output.name,
            windows: ws.windows || []
          })

          for (const win of ws.windows || []) {
            allWindows.push(win)
            if (win.is_focused) {
              focused = win
            }
          }
        }
      }

      this.workspaces.set(allWorkspaces)
      this.windows.set(allWindows)
      this.focusedWindow.set(focused)
    } catch (error) {
      console.error("Error refreshing Niri data:", error)
    }
  }

  async focusWorkspace(idx: number) {
    await this.sendCommand(`FocusWorkspace ${idx}`)
  }

  async focusWindow(id: number) {
    await this.sendCommand(`FocusWindow ${id}`)
  }

  getWorkspaces() {
    return this.workspaces()
  }

  getWindows() {
    return this.windows()
  }

  getFocusedWindow() {
    return this.focusedWindow()
  }

  // Subscribe to changes
  onWorkspacesChanged(callback: (workspaces: NiriWorkspace[]) => void) {
    return this.workspaces.subscribe(callback)
  }

  onWindowsChanged(callback: (windows: NiriWindow[]) => void) {
    return this.windows.subscribe(callback)
  }

  onFocusedWindowChanged(callback: (window: NiriWindow | null) => void) {
    return this.focusedWindow.subscribe(callback)
  }
}

// Singleton instance
export default new NiriService()
