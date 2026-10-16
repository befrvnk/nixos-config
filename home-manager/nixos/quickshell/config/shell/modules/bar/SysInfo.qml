import QtQuick
import QtQuick.Layouts
import qs.modules.common

// System info — CPU% · MEM% · TEMP°C. No popup.
ModuleItem {
    statusCmd: Config.sysinfoStatus
    statusInterval: 2500
}