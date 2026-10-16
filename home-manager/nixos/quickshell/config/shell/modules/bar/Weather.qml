import QtQuick
import QtQuick.Layouts
import qs.modules.common

// Weather module — hidden when no data; popup shows current conditions +
// 3-day forecast.
ModuleItem {
    statusCmd: Config.weatherStatus
    statusInterval: 600000
    showCmd: Config.weatherHasData
    showInterval: 300000
    popupCmd: Config.weatherForecast
    popupInterval: 600000
}