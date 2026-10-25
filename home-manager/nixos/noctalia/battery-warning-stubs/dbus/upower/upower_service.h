#pragma once

// Check-only stand-in for Noctalia's dbus/upower/upower_service.h. It mirrors the battery-facing
// API that system/battery_warning_monitor.cpp consumes (types, device fields, the two free
// helpers) without dragging in sdbus-c++, which would otherwise need linking just to construct a
// UPowerService in a standalone probe. The real header is compiled by the package build itself;
// keep these declarations in sync when the upstream API moves.

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

// Mirrors the org.freedesktop.UPower.Device "Type" wire enum.
enum class UPowerDeviceType : std::uint32_t {
  Unknown = 0,
  LinePower = 1,
  Battery = 2,
  Ups = 3,
  Mouse = 5,
  Keyboard = 6,
};

enum class BatteryState : std::uint8_t {
  Unknown = 0,
  Charging = 1,
  Discharging = 2,
  Empty = 3,
  FullyCharged = 4,
  PendingCharge = 5,
  PendingDischarge = 6,
};

struct UPowerState {
  double percentage = 0.0;
  BatteryState state = BatteryState::Unknown;
  bool isPresent = false;
  bool onBattery = false;
};

struct UPowerDeviceInfo {
  std::string path;
  std::string nativePath;
  std::string vendor;
  std::string model;
  std::string serial;
  UPowerDeviceType type = UPowerDeviceType::Unknown;
  bool powerSupply = false;
  bool isPresent = false;
  UPowerState state;

  [[nodiscard]] bool isLaptopBattery() const { return type == UPowerDeviceType::Battery && powerSupply; }
};

// Whether the battery state implies external power; empty when the state does not say (Unknown,
// Empty). Verbatim semantics of the upstream helper — the probe links its own copy.
[[nodiscard]] std::optional<bool> batteryStatePlugged(BatteryState state);

[[nodiscard]] bool upowerDeviceMatchesSelector(const UPowerDeviceInfo& info, std::string_view selector);

// The probe backs these with its own globals instead of a live D-Bus connection.
class UPowerService {
public:
  [[nodiscard]] std::vector<UPowerDeviceInfo> batteryDevices() const;
  [[nodiscard]] const UPowerDeviceInfo* defaultSystemBattery() const noexcept;
  [[nodiscard]] const UPowerDeviceInfo* deviceForSelector(std::string_view selector) const;
};
