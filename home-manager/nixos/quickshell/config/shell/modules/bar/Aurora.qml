import QtQuick
import QtQuick.Layouts
import qs.modules.common

// Aurora watch module — hidden when Kp < 4; popup has details, forecast and
// recent Kp history. The status script also sends its own storm notifications.
ModuleItem {
    statusCmd: Config.auroraStatus
    statusInterval: 600000
    showCmd: Config.auroraHasActivity
    showInterval: 300000
    popupCmd: Config.auroraDetails
    popupInterval: 300000
}