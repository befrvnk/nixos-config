import { GLib, Variable } from "astal"
import { Gtk } from "astal/gtk3"

// Variable to control calendar popup visibility
export const showCalendar = Variable(false)

export default function DateTime() {
  const time = Variable("").poll(
    1000,
    () => GLib.DateTime.new_now_local().format("%H:%M") || ""
  )

  const date = Variable("").poll(
    60000,
    () => GLib.DateTime.new_now_local().format("%a %b %d") || ""
  )

  return (
    <button
      className="datetime bar-section"
      onClicked={() => showCalendar.set(!showCalendar.get())}
    >
      <box spacing={8}>
        <label label={date()} />
        <label label={time()} css="font-weight: 600;" />
      </box>
    </button>
  )
}
