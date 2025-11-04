import { App, Astal, Gtk, Gdk } from "astal/gtk3"
import { bind, Variable, exec, execAsync } from "astal"
import { showControlPanel } from "./SystemIndicators"
import Wp from "gi://AstalWp"
import Network from "gi://AstalNetwork"

function VolumeSlider() {
  const audio = Wp.get_default()?.audio
  const speaker = audio?.defaultSpeaker

  if (!speaker) {
    return <box />
  }

  return (
    <box className="slider" vertical spacing={6}>
      <box spacing={8}>
        <label label="󰕾" css="font-size: 16px;" />
        <label label="Volume" hexpand halign={Gtk.Align.START} />
        <label label={bind(speaker, "volume").as((v) => `${Math.round(v * 100)}%`)} />
      </box>
      <slider
        value={bind(speaker, "volume")}
        onDragged={({ value }) => (speaker.volume = value)}
        min={0}
        max={1}
        hexpand
      />
    </box>
  )
}

function MicrophoneSlider() {
  const audio = Wp.get_default()?.audio
  const microphone = audio?.defaultMicrophone

  if (!microphone) {
    return <box />
  }

  return (
    <box className="slider" vertical spacing={6}>
      <box spacing={8}>
        <label label="󰍬" css="font-size: 16px;" />
        <label label="Microphone" hexpand halign={Gtk.Align.START} />
        <label label={bind(microphone, "volume").as((v) => `${Math.round(v * 100)}%`)} />
      </box>
      <slider
        value={bind(microphone, "volume")}
        onDragged={({ value }) => (microphone.volume = value)}
        min={0}
        max={1}
        hexpand
      />
    </box>
  )
}

function BrightnessSlider() {
  const brightness = Variable(0.5).poll(1000, () => {
    try {
      const max = Number(exec("cat /sys/class/backlight/*/max_brightness"))
      const current = Number(exec("cat /sys/class/backlight/*/brightness"))
      return current / max
    } catch {
      return 0.5
    }
  })

  const setBrightness = (value: number) => {
    try {
      const max = Number(exec("cat /sys/class/backlight/*/max_brightness"))
      const newValue = Math.round(value * max)
      execAsync(`brightnessctl set ${newValue}`)
    } catch (error) {
      console.error("Failed to set brightness:", error)
    }
  }

  return (
    <box className="slider" vertical spacing={6}>
      <box spacing={8}>
        <label label="󰃠" css="font-size: 16px;" />
        <label label="Brightness" hexpand halign={Gtk.Align.START} />
        <label label={bind(brightness).as((b) => `${Math.round(b * 100)}%`)} />
      </box>
      <slider
        value={bind(brightness)}
        onDragged={({ value }) => setBrightness(value)}
        min={0}
        max={1}
        hexpand
      />
    </box>
  )
}

function WiFiToggle() {
  const network = Network.get_default()
  const wifi = network.wifi

  if (!wifi) {
    return <box />
  }

  return (
    <button
      className={`quick-toggle ${wifi.enabled ? "active" : ""}`}
      onClicked={() => (wifi.enabled = !wifi.enabled)}
    >
      <box vertical spacing={6}>
        <label label="󰖩" css="font-size: 24px;" />
        <label label="WiFi" css="font-size: 11px;" />
        {wifi.enabled && wifi.ssid && (
          <label label={wifi.ssid} css="font-size: 10px; color: rgba(255, 255, 255, 0.7);" />
        )}
      </box>
    </button>
  )
}

function BluetoothToggle() {
  // Simplified Bluetooth toggle
  // In a full implementation, you'd use AstalBluetooth
  const enabled = Variable(false)

  return (
    <button
      className={`quick-toggle ${enabled.get() ? "active" : ""}`}
      onClicked={() => enabled.set(!enabled.get())}
    >
      <box vertical spacing={6}>
        <label label="󰂯" css="font-size: 24px;" />
        <label label="Bluetooth" css="font-size: 11px;" />
      </box>
    </button>
  )
}

function DNDToggle() {
  const dnd = Variable(false)

  return (
    <button
      className={`quick-toggle ${dnd.get() ? "active" : ""}`}
      onClicked={() => dnd.set(!dnd.get())}
    >
      <box vertical spacing={6}>
        <label label="󰂛" css="font-size: 24px;" />
        <label label="DND" css="font-size: 11px;" />
      </box>
    </button>
  )
}

function QuickToggles() {
  return (
    <box spacing={8} homogeneous>
      <WiFiToggle />
      <BluetoothToggle />
      <DNDToggle />
    </box>
  )
}

export default function ControlPanel({ gdkmonitor }: { gdkmonitor: Gdk.Monitor }) {
  const { TOP, RIGHT } = Astal.WindowAnchor

  return (
    <window
      className="control-panel"
      gdkmonitor={gdkmonitor}
      exclusivity={Astal.Exclusivity.NORMAL}
      anchor={TOP | RIGHT}
      visible={bind(showControlPanel)}
      application={App}
      keymode={Astal.Keymode.ON_DEMAND}
      onKeyPressEvent={(self, event: Gdk.Event) => {
        if (event.get_keyval()[1] === Gdk.KEY_Escape) {
          showControlPanel.set(false)
        }
      }}
    >
      <box
        vertical
        spacing={12}
        css="padding: 16px; min-width: 360px;"
      >
        <label
          label="Quick Settings"
          halign={Gtk.Align.START}
          css="font-size: 16px; font-weight: 600; margin-bottom: 8px;"
        />

        {/* Sliders Section */}
        <box className="control-panel-section" vertical spacing={8}>
          <VolumeSlider />
          <MicrophoneSlider />
          <BrightnessSlider />
        </box>

        <separator />

        {/* Quick Toggles Section */}
        <box className="control-panel-section" vertical spacing={8}>
          <label
            label="Toggles"
            halign={Gtk.Align.START}
            css="font-weight: 600; margin-bottom: 4px;"
          />
          <QuickToggles />
        </box>
      </box>
    </window>
  )
}
