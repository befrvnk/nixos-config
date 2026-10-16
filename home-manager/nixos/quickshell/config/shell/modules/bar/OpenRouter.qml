import QtQuick
import QtQuick.Layouts
import qs.modules.common

// OpenRouter usage module — label + popup (details script), from the account API.
ModuleItem {
    statusCmd: Config.openrouterStatus
    statusInterval: 300000
    popupCmd: Config.openrouterDetails
    popupInterval: 300000
}