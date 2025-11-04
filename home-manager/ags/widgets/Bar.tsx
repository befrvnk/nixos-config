import { Widget } from "resource:///com/github/Aylur/ags/widget.js"

export default () => Widget.Window({
  name: "bar",
  anchor: ["top", "left", "right"],
  exclusivity: "exclusive",
  child: Widget.CenterBox({
    className: "bar",
    startWidget: Widget.Box({
      className: "bar-section left",
      hpack: "start",
      spacing: 8,
      children: [
        Widget.Label("Workspaces"), // Placeholder - will implement Niri workspaces
        Widget.Label("Windows"), // Placeholder - will implement Niri windows
      ],
    }),
    centerWidget: Widget.Box({
      className: "bar-section center",
      children: [
        Widget.Label({
          className: "datetime",
          setup: (self) => self.poll(1000, () => {
            const now = new Date()
            self.label = `${now.toLocaleDateString()} ${now.toLocaleTimeString()}`
          }),
        }),
      ],
    }),
    endWidget: Widget.Box({
      className: "bar-section right",
      hpack: "end",
      spacing: 8,
      children: [
        Widget.Label("Indicators"), // Placeholder - will implement system indicators
      ],
    }),
  }),
})
