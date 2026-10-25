// Behavioral probe for the battery-warning-no-spam patch.
//
// Compiles the real (patched) battery_warning_monitor.cpp against Noctalia's real headers and
// drives it through the discharge/charge flap sequences that used to produce repeated low-battery
// toasts while the charger was connected. Only the external symbols the monitor links against are
// provided here, mirroring their upstream implementations in upower_service.cpp /
// notification_manager.cpp / i18n_service.h.

#include "system/battery_warning_monitor.h"

#include "dbus/upower/upower_service.h"
#include "i18n/i18n.h"
#include "notification/notification_manager.h"
#include "util/string_utils.h"

#include <cstdio>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

struct SentNotification {
  std::string summary;
  std::string body;
  Urgency urgency = Urgency::Normal;
  int32_t timeout = 0;
};

static std::vector<SentNotification> g_sent;
static std::vector<UPowerDeviceInfo> g_devices;
static int g_failures = 0;

// --- upstream symbols the monitor links against ---------------------------------------------

std::optional<bool> batteryStatePlugged(BatteryState state) {
  switch (state) {
  case BatteryState::Charging:
  case BatteryState::FullyCharged:
  case BatteryState::PendingCharge:
    return true;
  case BatteryState::Discharging:
  case BatteryState::PendingDischarge:
    return false;
  case BatteryState::Unknown:
  case BatteryState::Empty:
    break;
  }
  return std::nullopt;
}

namespace {
  bool selectorMatchesField(std::string_view value, std::string_view selector) {
    if (value == selector) {
      return true;
    }
    if (value.empty() || selector.empty() || value.size() < selector.size()) {
      return false;
    }
    const std::size_t start = value.size() - selector.size();
    if (value.substr(start) != selector) {
      return false;
    }
    if (start == 0) {
      return true;
    }
    const char before = value[start - 1];
    return before == '/' || before == '_' || before == '-' || before == ':' || before == '.';
  }
} // namespace

bool upowerDeviceMatchesSelector(const UPowerDeviceInfo& info, std::string_view selector) {
  const std::string trimmed = StringUtils::trim(selector);
  if (trimmed.empty()) {
    return false;
  }
  return selectorMatchesField(info.path, trimmed) || selectorMatchesField(info.nativePath, trimmed)
      || selectorMatchesField(info.model, trimmed) || selectorMatchesField(info.serial, trimmed)
      || selectorMatchesField(info.vendor, trimmed);
}

std::vector<UPowerDeviceInfo> UPowerService::batteryDevices() const {
  return g_devices;
}

const UPowerDeviceInfo* UPowerService::defaultSystemBattery() const noexcept {
  for (const auto& device : g_devices) {
    if (device.isLaptopBattery() && device.isPresent) {
      return &device;
    }
  }
  return nullptr;
}

const UPowerDeviceInfo* UPowerService::deviceForSelector(std::string_view selector) const {
  for (const auto& device : g_devices) {
    const bool batteryCapable = device.type != UPowerDeviceType::Unknown && device.type != UPowerDeviceType::LinePower;
    if (batteryCapable && upowerDeviceMatchesSelector(device, selector)) {
      return &device;
    }
  }
  return nullptr;
}

uint32_t NotificationManager::addInternal(
    std::string appName, std::string summary, std::string body, Urgency urgency, int32_t timeout,
    std::optional<std::string> icon, std::optional<NotificationImageData> imageData,
    std::optional<std::string> category, std::optional<std::string> desktopEntry, NotificationDndPolicy dndPolicy
) {
  (void)appName;
  (void)icon;
  (void)imageData;
  (void)category;
  (void)desktopEntry;
  (void)dndPolicy;
  g_sent.push_back(SentNotification{std::move(summary), std::move(body), urgency, timeout});
  return static_cast<uint32_t>(g_sent.size());
}

// Timer's destructor is declared out of line upstream; NotificationManager owns one.
Timer::~Timer() {
}

namespace i18n {
  Service& Service::instance() {
    static Service service;
    return service;
  }

  std::string_view Service::lookup(std::string_view) const {
    return {}; // real tr() then renders "!!key!!", which the assertions match on
  }

  namespace detail {
    // Unreachable with the empty lookup above, but the instantiated tr<> overloads reference it.
    std::string interpolate(std::string_view tmpl, std::span<const Pair>) {
      return std::string(tmpl);
    }
  } // namespace detail
} // namespace i18n

// --- scenario helpers -----------------------------------------------------------------------

namespace {

  UPowerDeviceInfo laptopBattery(double percent, BatteryState state, bool onBattery) {
    UPowerDeviceInfo device;
    device.path = "/org/freedesktop/UPower/devices/battery_BAT1";
    device.nativePath = "BAT1";
    device.model = "FRANGWA";
    device.vendor = "NVT";
    device.type = UPowerDeviceType::Battery;
    device.powerSupply = true;
    device.isPresent = true;
    device.state.percentage = percent;
    device.state.state = state;
    device.state.isPresent = true;
    device.state.onBattery = onBattery;
    return device;
  }

  UPowerDeviceInfo mouseBattery(double percent, BatteryState state, bool onBattery) {
    UPowerDeviceInfo device;
    device.path = "/org/freedesktop/UPower/devices/battery_keychron_mouse";
    device.nativePath = "keychron_mouse";
    device.model = "Keychron Mouse";
    device.type = UPowerDeviceType::Battery;
    device.powerSupply = false; // SCOPE_DEVICE → UPower reports "power supply: no"
    device.isPresent = true;
    device.state.percentage = percent;
    device.state.state = state;
    device.state.isPresent = true;
    device.state.onBattery = onBattery;
    return device;
  }

  void expectCount(const char* what, size_t actual, size_t expected) {
    if (actual != expected) {
      std::fprintf(stderr, "FAIL: %s: expected %zu notification(s), got %zu\n", what, expected, actual);
      ++g_failures;
    } else {
      std::printf("ok: %s\n", what);
    }
  }

  void expectTrue(const char* what, bool condition) {
    if (!condition) {
      std::fprintf(stderr, "FAIL: %s\n", what);
      ++g_failures;
    } else {
      std::printf("ok: %s\n", what);
    }
  }

} // namespace

int main() {
  static UPowerService upowerService;
  const auto* upower = &upowerService;

  BatteryConfig config;
  config.warningThreshold = 20;

  auto evaluate = [&](BatteryWarningMonitor& monitor, NotificationManager& notifications) {
    monitor.evaluate(config, *upower, notifications);
  };

  // 1. A natural discharge crossing warns exactly once, at normal urgency.
  {
    g_sent.clear();
    BatteryWarningMonitor monitor;
    NotificationManager notifications;
    g_devices = { laptopBattery(25, BatteryState::Discharging, true) };
    evaluate(monitor, notifications);
    g_devices = { laptopBattery(20, BatteryState::Discharging, true) };
    evaluate(monitor, notifications);
    g_devices = { laptopBattery(16, BatteryState::Discharging, true) };
    evaluate(monitor, notifications);
    expectCount("discharge crossing warns once", g_sent.size(), 1);
    expectTrue(
        "low toast is normal urgency with default timeout",
        !g_sent.empty() && g_sent[0].summary.find("battery-low") != std::string::npos
            && g_sent[0].urgency == Urgency::Normal && g_sent[0].timeout == kDefaultNotificationTimeout
    );
  }

  // 2. Restarting below the low threshold no longer repeats the toast (first evaluate is silent).
  {
    g_sent.clear();
    BatteryWarningMonitor monitor;
    NotificationManager notifications;
    g_devices = { laptopBattery(16, BatteryState::Discharging, true) };
    evaluate(monitor, notifications);
    expectCount("startup below the low level stays silent", g_sent.size(), 0);
  }

  // 3. Startup at a critical level still notifies as a safety net.
  {
    g_sent.clear();
    BatteryWarningMonitor monitor;
    NotificationManager notifications;
    g_devices = { laptopBattery(4, BatteryState::Discharging, true) };
    evaluate(monitor, notifications);
    expectCount("startup at a critical level notifies", g_sent.size(), 1);
    expectTrue(
        "startup critical uses critical urgency and double timeout",
        !g_sent.empty() && g_sent[0].urgency == Urgency::Critical
            && g_sent[0].timeout == kDefaultNotificationTimeout * 2
    );
  }

  // 4. Startup while charging is silent.
  {
    g_sent.clear();
    BatteryWarningMonitor monitor;
    NotificationManager notifications;
    g_devices = { laptopBattery(16, BatteryState::Charging, false) };
    evaluate(monitor, notifications);
    expectCount("startup while charging stays silent", g_sent.size(), 0);
  }

  // 5. An unknown charge state on AC must not read as "on battery".
  {
    g_sent.clear();
    BatteryWarningMonitor monitor;
    NotificationManager notifications;
    g_devices = { laptopBattery(16, BatteryState::Unknown, false) };
    evaluate(monitor, notifications);
    expectCount("unknown charge state on AC stays silent", g_sent.size(), 0);
  }

  // 6. The Framework EC flap (discharging reported while AC is online) never re-fires; a genuine
  //    unplug warns once, and re-plugging stops further toasts.
  {
    g_sent.clear();
    BatteryWarningMonitor monitor;
    NotificationManager notifications;
    g_devices = { laptopBattery(16, BatteryState::Charging, false) };
    evaluate(monitor, notifications);
    g_devices = { laptopBattery(16, BatteryState::Discharging, false) }; // EC flap, AC online
    evaluate(monitor, notifications);
    g_devices = { laptopBattery(16, BatteryState::Unknown, false) };
    evaluate(monitor, notifications);
    g_devices = { laptopBattery(16, BatteryState::Discharging, false) }; // flap repeats
    evaluate(monitor, notifications);
    expectCount("flapping while plugged never notifies", g_sent.size(), 0);

    g_devices = { laptopBattery(16, BatteryState::Discharging, true) }; // really unplugged
    evaluate(monitor, notifications);
    expectCount("genuine unplug below threshold notifies once", g_sent.size(), 1);

    g_devices = { laptopBattery(16, BatteryState::Charging, false) }; // re-plugged
    evaluate(monitor, notifications);
    g_devices = { laptopBattery(16, BatteryState::Discharging, false) }; // flap again
    evaluate(monitor, notifications);
    expectCount("flap after re-plug does not re-fire", g_sent.size(), 1);
  }

  // 7. A real recharge past the alert point re-arms the next discharge cycle.
  {
    g_sent.clear();
    BatteryWarningMonitor monitor;
    NotificationManager notifications;
    g_devices = { laptopBattery(16, BatteryState::Discharging, true) };
    evaluate(monitor, notifications);
    g_devices = { laptopBattery(50, BatteryState::Charging, false) };
    evaluate(monitor, notifications);
    g_devices = { laptopBattery(50, BatteryState::Discharging, true) };
    evaluate(monitor, notifications);
    g_devices = { laptopBattery(20, BatteryState::Discharging, true) };
    evaluate(monitor, notifications);
    expectCount("fresh discharge cycle after a real recharge warns again", g_sent.size(), 1);
  }

  // 8. Mid-cycle escalation to the critical level still fires, only once.
  {
    g_sent.clear();
    BatteryWarningMonitor monitor;
    NotificationManager notifications;
    g_devices = { laptopBattery(16, BatteryState::Discharging, true) };
    evaluate(monitor, notifications);
    g_devices = { laptopBattery(4, BatteryState::Discharging, true) };
    evaluate(monitor, notifications);
    evaluate(monitor, notifications);
    expectCount("escalation to critical notifies once", g_sent.size(), 1);
    expectTrue(
        "escalated toast keeps critical urgency and double timeout",
        !g_sent.empty() && g_sent[0].urgency == Urgency::Critical
            && g_sent[0].timeout == kDefaultNotificationTimeout * 2
    );
  }

  // 9. Peripherals keep their own per-device threshold even while the system charges, and stay
  //    silent without one (the mouse driver always reports "discharging").
  {
    BatteryConfig perDevice = config;
    perDevice.deviceThresholds.push_back(BatteryDeviceWarningThreshold{ .selector = "battery_keychron_mouse",
                                                                       .warningThreshold = 10 });
    g_sent.clear();
    BatteryWarningMonitor monitor;
    NotificationManager notifications;
    g_devices = { laptopBattery(90, BatteryState::Charging, false), mouseBattery(8, BatteryState::Discharging, false) };
    monitor.evaluate(perDevice, *upower, notifications);
    expectCount("configured peripheral threshold warns on its own schedule", g_sent.size(), 1);

    g_sent.clear();
    BatteryWarningMonitor freshMonitor;
    NotificationManager freshNotifications;
    freshMonitor.evaluate(config, *upower, freshNotifications);
    expectCount("peripheral without a configured threshold stays silent", g_sent.size(), 0);
  }

  if (g_failures != 0) {
    std::fprintf(stderr, "%d battery-warning check(s) failed\n", g_failures);
    return 1;
  }
  std::printf("all battery-warning checks passed\n");
  return 0;
}
