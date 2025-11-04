import { App, Astal, Gtk, Gdk } from "astal/gtk3"
import { GLib, Variable, bind } from "astal"
import { showCalendar } from "./DateTime"
import Notifd from "gi://AstalNotifd"
import Mpris from "gi://AstalMpris"

function Calendar() {
  return (
    <box className="calendar" vertical>
      <label
        label={Variable("").poll(
          60000,
          () => GLib.DateTime.new_now_local().format("%B %Y") || ""
        )()}
        css="font-size: 18px; font-weight: 600; margin-bottom: 12px;"
      />
      <calendar />
    </box>
  )
}

function Notifications() {
  const notifd = Notifd.get_default()
  const notifications = bind(notifd, "notifications")

  return (
    <box className="notifications" vertical spacing={8}>
      <label
        label="Notifications"
        halign={Gtk.Align.START}
        css="font-weight: 600; margin-bottom: 4px;"
      />
      <scrollable
        vexpand
        css="min-height: 200px; max-height: 300px;"
      >
        <box vertical spacing={6}>
          {notifications.as((notifs) =>
            notifs.length === 0 ? (
              <label
                label="No notifications"
                halign={Gtk.Align.CENTER}
                valign={Gtk.Align.CENTER}
                css="color: rgba(255, 255, 255, 0.5); margin: 20px;"
              />
            ) : (
              notifs.map((notif) => (
                <box
                  key={notif.id}
                  className="notification"
                  vertical
                  css="background-color: rgba(127, 132, 156, 0.2); padding: 12px; border-radius: 8px;"
                >
                  <box spacing={8}>
                    <label
                      label={notif.summary}
                      halign={Gtk.Align.START}
                      css="font-weight: 600;"
                      wrap
                    />
                    <button
                      halign={Gtk.Align.END}
                      onClicked={() => notif.dismiss()}
                      css="padding: 2px 8px;"
                    >
                      <label label="×" css="font-size: 16px;" />
                    </button>
                  </box>
                  {notif.body && (
                    <label
                      label={notif.body}
                      halign={Gtk.Align.START}
                      wrap
                      css="margin-top: 4px; font-size: 12px; color: rgba(255, 255, 255, 0.8);"
                    />
                  )}
                </box>
              ))
            )
          )}
        </box>
      </scrollable>
    </box>
  )
}

function MediaControls() {
  const mpris = Mpris.get_default()
  const player = bind(mpris, "players").as((ps) => ps[0])

  return (
    <box className="media-controls" vertical spacing={8}>
      <label
        label="Media"
        halign={Gtk.Align.START}
        css="font-weight: 600; margin-bottom: 4px;"
      />
      {player ? (
        <box
          vertical
          spacing={8}
          css="background-color: rgba(127, 132, 156, 0.2); padding: 12px; border-radius: 8px;"
        >
          <label
            label={bind(player, "title").as((t) => t || "Unknown")}
            halign={Gtk.Align.START}
            css="font-weight: 600;"
            truncate
          />
          <label
            label={bind(player, "artist").as((a) => a || "Unknown Artist")}
            halign={Gtk.Align.START}
            css="font-size: 12px; color: rgba(255, 255, 255, 0.8);"
            truncate
          />
          <box spacing={8} halign={Gtk.Align.CENTER} css="margin-top: 8px;">
            <button
              onClicked={() => player.previous()}
              css="padding: 8px 12px;"
            >
              <label label="⏮" />
            </button>
            <button
              onClicked={() => player.play_pause()}
              css="padding: 8px 16px;"
            >
              <label
                label={bind(player, "playbackStatus").as((s) =>
                  s === "Playing" ? "⏸" : "▶"
                )}
              />
            </button>
            <button
              onClicked={() => player.next()}
              css="padding: 8px 12px;"
            >
              <label label="⏭" />
            </button>
          </box>
        </box>
      ) : (
        <label
          label="No media playing"
          halign={Gtk.Align.CENTER}
          css="color: rgba(255, 255, 255, 0.5); margin: 20px;"
        />
      )}
    </box>
  )
}

export default function CalendarPopup({ gdkmonitor }: { gdkmonitor: Gdk.Monitor }) {
  const { TOP } = Astal.WindowAnchor

  return (
    <window
      className="calendar-popup"
      gdkmonitor={gdkmonitor}
      exclusivity={Astal.Exclusivity.NORMAL}
      anchor={TOP}
      visible={bind(showCalendar)}
      application={App}
      keymode={Astal.Keymode.ON_DEMAND}
      onKeyPressEvent={(self, event: Gdk.Event) => {
        if (event.get_keyval()[1] === Gdk.KEY_Escape) {
          showCalendar.set(false)
        }
      }}
    >
      <box
        vertical
        spacing={16}
        css="padding: 16px; min-width: 400px;"
      >
        <Calendar />
        <separator />
        <Notifications />
        <separator />
        <MediaControls />
      </box>
    </window>
  )
}
