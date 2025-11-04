import { App } from "resource:///com/github/Aylur/ags/app.js"
import { exec, execAsync } from "resource:///com/github/Aylur/ags/utils.js"

// Import widgets
import Bar from "./widgets/Bar.js"

// Apply styles
App.addIcons(`${App.configDir}/assets`)
App.config({
  style: `${App.configDir}/style.css`,
  windows: [
    Bar(),
  ],
})
