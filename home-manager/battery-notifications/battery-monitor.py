"""
Battery notification monitor
Sends notifications for:
- 5% battery (critical) when discharging
- 20% battery (low) when discharging
- 100% battery (full) when charging
"""

import subprocess
import sys
import time
from pathlib import Path
import os
import shutil

# Find command paths at runtime
UPOWER_PATH = shutil.which('upower') or 'upower'
NOTIFY_SEND_PATH = shutil.which('notify-send') or 'notify-send'


class BatteryMonitor:
    def __init__(self):
        # State directory for tracking sent notifications
        runtime_dir = os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')
        self.state_dir = Path(runtime_dir) / 'battery-notify'
        self.state_dir.mkdir(parents=True, exist_ok=True)

        self.sent_5 = self.state_dir / 'sent_5'
        self.sent_20 = self.state_dir / 'sent_20'
        self.sent_full = self.state_dir / 'sent_full'

    def find_battery(self):
        """Find the first valid battery device"""
        try:
            result = subprocess.run(
                [UPOWER_PATH, '-e'],
                capture_output=True,
                text=True,
                check=True
            )

            for device in result.stdout.splitlines():
                if 'battery' not in device:
                    continue

                info_result = subprocess.run(
                    [UPOWER_PATH, '-i', device],
                    capture_output=True,
                    text=True,
                    check=True
                )

                info = info_result.stdout

                # Skip if battery should be ignored
                if 'should be ignored' in info:
                    continue

                # Check if power supply is explicitly "no" on the same line
                skip_device = False
                for line in info.splitlines():
                    if 'power supply' in line and line.strip().endswith('no'):
                        skip_device = True
                        break

                if skip_device:
                    continue

                return device
        except subprocess.CalledProcessError as e:
            print(f"Error running upower: {e}", file=sys.stderr)

        return None

    def get_battery_info(self, device):
        """Get battery percentage and state"""
        try:
            result = subprocess.run(
                [UPOWER_PATH, '-i', device],
                capture_output=True,
                text=True,
                check=True
            )

            percentage = None
            state = None

            for line in result.stdout.splitlines():
                if 'percentage:' in line:
                    percentage = int(line.split(':')[1].strip().rstrip('%'))
                elif 'state:' in line:
                    state = line.split(':')[1].strip()

            return percentage, state
        except (subprocess.CalledProcessError, ValueError, IndexError):
            return None, None

    def send_notification(self, urgency, summary, body, icon):
        """Send a desktop notification"""
        try:
            subprocess.run(
                [
                    NOTIFY_SEND_PATH,
                    '-u', urgency,
                    '-i', icon,
                    summary,
                    body
                ],
                check=True
            )
            print(f"Sent notification: {summary}", file=sys.stderr)
        except subprocess.CalledProcessError as e:
            print(f"Failed to send notification: {e}", file=sys.stderr)
        except FileNotFoundError as e:
            print(f"notify-send not found: {e}", file=sys.stderr)

    def run(self):
        """Main monitoring loop"""
        print("Battery notification monitor started", file=sys.stderr)
        while True:
            battery_device = self.find_battery()

            if not battery_device:
                # No battery found, sleep and retry
                time.sleep(30)
                continue

            percentage, state = self.get_battery_info(battery_device)

            if percentage is None or state is None:
                time.sleep(30)
                continue

            # Handle discharging state
            if state == 'discharging':
                # Reset full charge notification when discharging
                self.sent_full.unlink(missing_ok=True)

                # Check for 5% battery (critical)
                if percentage <= 5 and not self.sent_5.exists():
                    self.send_notification(
                        'critical',
                        'Battery Critical!',
                        f'Battery at {percentage}%. Please plug in your charger immediately.',
                        'battery-caution'
                    )
                    self.sent_5.touch()
                    # Also reset the 20% notification for next charge cycle
                    self.sent_20.unlink(missing_ok=True)

                # Check for 20% battery (low)
                elif percentage <= 20 and not self.sent_20.exists():
                    self.send_notification(
                        'normal',
                        'Battery Low',
                        f'Battery at {percentage}%. Consider plugging in your charger.',
                        'battery-low'
                    )
                    self.sent_20.touch()

                # Reset notifications when battery goes above thresholds
                elif percentage > 20 and self.sent_20.exists():
                    self.sent_20.unlink(missing_ok=True)
                    self.sent_5.unlink(missing_ok=True)

            # Handle charging/fully-charged states
            elif state in ('charging', 'fully-charged'):
                # Reset low battery notifications when charging
                self.sent_5.unlink(missing_ok=True)
                self.sent_20.unlink(missing_ok=True)

                # Check if battery is full
                if state == 'fully-charged' and not self.sent_full.exists():
                    self.send_notification(
                        'normal',
                        'Battery Fully Charged',
                        'Your battery is at 100%. You can unplug the charger.',
                        'battery-full-charged'
                    )
                    self.sent_full.touch()

            # Check every 30 seconds
            time.sleep(30)


if __name__ == '__main__':
    monitor = BatteryMonitor()
    monitor.run()
