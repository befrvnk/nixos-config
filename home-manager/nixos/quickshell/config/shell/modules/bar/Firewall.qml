import QtQuick
import QtQuick.Layouts
import qs.modules.common

// Firewall module — hidden when no external refused connections; popup shows
// details and per-source breakdown.
ModuleItem {
    statusCmd: Config.firewallStatus
    statusInterval: 60000
    showCmd: Config.firewallHasRefused
    showInterval: 60000
    popupCmd: Config.firewallDetails
    popupInterval: 60000
}