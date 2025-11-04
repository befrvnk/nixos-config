import { Variable, GLib, exec, execAsync } from "astal"
import { Gtk } from "astal/gtk3"
import { bind } from "astal"
import Battery from "gi://AstalBattery"
import Network from "gi://AstalNetwork"
import Wp from "gi://AstalWp"

// Variable to control control panel visibility
export const showControlPanel = Variable(false)

function CPUIndicator() {
  const cpuUsage = Variable(0).poll(2000, () => {
    try {
      const stat = exec("cat /proc/stat")
      const lines = stat.split("\n")
      const cpuLine = lines[0].split(/\s+/)
      const idle = parseInt(cpuLine[4])
      const total = cpuLine.slice(1).reduce((acc, val) => acc + parseInt(val), 0)
      const usage = Math.round((1 - idle / total) * 100)
      return usage
    } catch {
      return 0
    }
  })

  return (
    <box className="indicator" spacing={4}>
      <label label="󰻠" className="indicator-icon" />
      <label label={cpuUsage().as((u) => `${u}%`)} />
    </box>
  )
}

function GPUIndicator() {
  const gpuUsage = Variable(0).poll(2000, () => {
    try {
      // Use radeontop for AMD GPU monitoring
      const output = exec("timeout 0.5 radeontop -d - -l 1 2>/dev/null | grep 'gpu' | awk '{print $2}'")
      const usage = parseFloat(output.replace("%", ""))
      return isNaN(usage) ? 0 : Math.round(usage)
    } catch {
      return 0
    }
  })

  return (
    <box className="indicator" spacing={4}>
      <label label="󰾲" className="indicator-icon" />
      <label label={gpuUsage().as((u) => `${u}%`)} />
    </box>
  )
}

function BatteryIndicator() {
  const battery = Battery.get_default()

  const getIcon = (percentage: number, isCharging: boolean) => {
    if (isCharging) return "󰂄"
    if (percentage > 90) return "󰁹"
    if (percentage > 70) return "󰂀"
    if (percentage > 50) return "󰁾"
    if (percentage > 30) return "󰁼"
    if (percentage > 10) return "󰁺"
    return "󰂃"
  }

  return (
    <box className="indicator" spacing={4}>
      <label
        label={bind(battery, "percentage").as((p) =>
          getIcon(p * 100, battery.charging)
        )}
        className="indicator-icon"
      />
      <label
        label={bind(battery, "percentage").as((p) => `${Math.round(p * 100)}%`)}
      />
    </box>
  )
}

function NetworkIndicator() {
  const network = Network.get_default()
  const wifi = bind(network, "wifi")

  return (
    <box className="indicator" spacing={4}>
      <label
        label={wifi.as((w) => (w && w.enabled ? "󰖩" : "󰖪"))}
        className="indicator-icon"
      />
      <label
        label={wifi.as((w) => (w && w.ssid ? w.ssid : "Disconnected"))}
      />
    </box>
  )
}

function VolumeIndicator() {
  const audio = Wp.get_default()?.audio
  const speaker = audio?.defaultSpeaker

  if (!speaker) {
    return <box />
  }

  const getIcon = (volume: number, muted: boolean) => {
    if (muted || volume === 0) return "󰸈"
    if (volume < 0.33) return "󰕿"
    if (volume < 0.66) return "󰖀"
    return "󰕾"
  }

  return (
    <box className="indicator" spacing={4}>
      <label
        label={bind(speaker, "volume").as((v) => getIcon(v, speaker.mute))}
        className="indicator-icon"
      />
      <label
        label={bind(speaker, "volume").as((v) => `${Math.round(v * 100)}%`)}
      />
    </box>
  )
}

function BluetoothIndicator() {
  // Simplified Bluetooth indicator
  // In a full implementation, you'd use AstalBluetooth
  return (
    <box className="indicator" spacing={4}>
      <label label="󰂯" className="indicator-icon" />
    </box>
  )
}

export default function SystemIndicators() {
  return (
    <box
      className="system-indicators bar-section"
      spacing={4}
      onClick={() => showControlPanel.set(!showControlPanel.get())}
      css="cursor: pointer;"
    >
      <CPUIndicator />
      <GPUIndicator />
      <NetworkIndicator />
      <BluetoothIndicator />
      <VolumeIndicator />
      <BatteryIndicator />
    </box>
  )
}
