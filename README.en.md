# TBPower AS

[Italiano](README.md) | **English**

**TBPower AS** is a macOS menu-bar app for **Apple Silicon** Macs
(M1, M2, M3, M4…): power profiles, an automatic profile, **Amphetamine**, temperatures,
fans (read-only) and, above all, a **battery charge limit** that keeps working
even when the app is closed.

> 💻 **Have an Intel MacBook Pro?** Use the sibling repo
> **[TBPower (Intel)](https://github.com/tonybasspower/TBPower)**: turbo, Radeon GPU, manual fans.
> The two apps are separate and must not be mixed.

---

## Contents

1. [Features](#features)
2. [How the charge limit works](#how-the-charge-limit-works)
3. [Requirements](#requirements)
4. [Download and build](#download-and-build)
5. [Installation (helper, sudo once)](#installation)
6. [Launch](#launch)
7. [The menu, item by item](#the-menu-item-by-item)
8. [Complete uninstall](#complete-uninstall)
9. [Troubleshooting](#troubleshooting)
10. [Security: what it does as root](#security-what-it-does-as-root)
11. [Donation](#donation)
12. [License and credits](#license-and-credits)

---

## Features

| Feature | Notes |
|---|---|
| **Power saving / Normal profiles** | Power saving = *Low Power Mode* (`pmset lowpowermode 1`); Normal = `lowpowermode 0` |
| **Automatic profile** | A different profile on battery and on power adapter, switched automatically when you plug in or unplug |
| **Amphetamine** | Display and disks stay awake (long copies, downloads); restores the `pmset` timers when you turn it off or quit |
| **Lid closed: don't sleep** | Only with an external display connected (`pmset disablesleep`) |
| **Temperatures** | CPU (max of `Tp01/Tp05/Tp09/Tp0D`, fallback `Tp0T`), GPU (`Tg05/Tg0D`), battery (`TB0T/TB1T/TB2T`) |
| **Read-only fans** | Current speeds from SMC keys `F0Ac/F1Ac`; **no** fan writes |
| **Charge limit** 50–100 % | Charge inhibit via SMC `CHTE` (fallback `CH0B`/`CH0C`), 2 % hysteresis, daemon every 15 s |
| **Conflict detection** | If `battery maintain` (actuallymentor) is running, TBPower AS leaves charging alone and reports it |
| **Menu bar** | Logo, CPU temp, CPU %, RAM, GPU temp, network traffic (Options ⚙︎) |
| **Italiano / English**, launch at login | No password after installation |

On Apple Silicon there is **no** Turbo Boost and no switchable GPU: that is why the
Intel edition's "turbo" and "Maximum" profiles are missing (on the 14" M1 Pro, macOS does not expose
`highpowermode`).

Tested on **MacBook Pro 14" M1 Pro (MacBookPro18,3)** with **macOS 15.3.1**.
Other models/firmware should work, but the SMC is not documented by Apple:
always verify that charging actually stops (see below).

## How the charge limit works

On Apple Silicon the old `BCLM` key does not exist. TBPower AS **blocks charging**
(SMC inhibit) when you reach the limit and **re-enables** it when you drop by 2 points:

- percentage ≥ limit **and** power adapter connected → charging **inhibited** (you stay powered from the outlet, the battery does not rise);
- percentage ≤ limit − 2 → charging **re-enabled** (e.g. limit 80: it stops at 80, resumes at 78);
- limit 100 % or power adapter unplugged → inhibit is always cleared;
- it never forces a discharge and never turns the adapter off.

SMC keys, chosen **according to which ones exist** (not according to the macOS version):

1. **`CHTE`** (`ui32`, 4 bytes): pause `01 00 00 00`, resume `00 00 00 00`. Preferred: on the M1 Pro with
   macOS 15.3 it is the only one that actually stops charging.
2. **`CH0B` + `CH0C`** (`hex_`, 1 byte): pause `02`, resume `00` on both. Fallback for older firmware.
3. Neither present with the expected type/size → **no write**.

Every write is **read back**; if it does not "take" (error `-15`) the helper tries to re-enable charging
(*fail-open*) and reports the error.

Who applies the rule:
- **the app**, while it is open, checks about every 2 seconds;
- the **LaunchDaemon** `com.tbp.tbpower-as.chargelimit` runs `tbpower-as-helper enforce`
  **at boot and every 15 seconds**, even when the app is closed and before login.

## Requirements

- **Apple Silicon** Mac (arm64), macOS **13 Ventura or later**.
- Xcode **Command Line Tools** (Swift 5.8+). Full Xcode is **not** required:
  ```sh
  xcode-select --install
  ```
- An administrator account (`sudo` is needed **once**, for the helper).
- **No other charge limiter running** (battery, AlDente, batt…): see [Troubleshooting](#troubleshooting).

## Download and build

Clone into your home folder (`~/TBPowerAS`): that is the path the app suggests when the helper needs updating.

```sh
cd ~
git clone https://github.com/tonybasspower/TBPowerAS.git
cd TBPowerAS
./build-app.sh            # as a normal user, NOT with sudo
```

Alternatively: *Code › Download ZIP* on GitHub, extract into `~/TBPowerAS` and enter the folder from Terminal.

`build-app.sh` compiles **arm64 only** with `clang` + `swiftc` (no SwiftPM, so it also works with
"awkward" Command Line Tools), creates the icon and ad-hoc signs. Result:

- `build/TBPower AS.app` — the app (executable `TBPowerAS`, bundle id `com.tbp.tbpower-as`)
- `build/tbpower-as-helper` — the root helper

Optional charge-protocol test (mock, no hardware access):

```sh
cc -Wall -Wextra -Werror -I Sources/CSMC/include Sources/CSMC/charge.c tests/charge-test.c -o /tmp/charge-test
/tmp/charge-test
```

Diagnostics without sudo and without writes:

```sh
./build/tbpower-as-helper charge-supported && echo "SMC carica supportato"
./build/tbpower-as-helper status        # backend=2 (CHTE) | 1 (CH0B/CH0C) | 0, conflict, paused, limit
```

## Installation

```sh
sudo ./install-helper.sh 80     # 80 = charge limit in % (50–100, default 93)
```

What it does, in order:

| Step | What | Path |
|---|---|---|
| 1 | Checks: root, Apple Silicon Mac, normal user, limit 50–100, arm64 helper already built | — |
| 2 | Support folder (root:wheel 755) | `/Library/Application Support/TBPowerAS/` |
| 3 | Stops only **its own** daemon (if one was present) | — |
| 4 | Root helper (root:wheel 755) and uninstall script | `…/TBPowerAS/tbpower-as-helper`, `…/TBPowerAS/uninstall.sh` |
| 5 | Verifies that the SMC supports charge inhibit (otherwise it stops **without** creating the sudo rule) | — |
| 6 | sudo rule **for the helper only**, without a password | `/etc/sudoers.d/tbpower-as` |
| 7 | Saves the limit **only on the first install** (then you change it from the app) | `…/TBPowerAS/config` (`charge_limit=80`) |
| 8 | `reapply`: re-enables charging (clean state) | — |
| 9 | LaunchDaemon (boot + every 15 s) | `/Library/LaunchDaemons/com.tbp.tbpower-as.chargelimit.plist`, log `/var/log/tbpower-as-chargelimit.log` |
| 10 | The app | `/Applications/TBPower AS.app` |

It does not install or remove anything else (no migration from other apps). To update: `git pull`,
`./build-app.sh`, then again `sudo ./install-helper.sh <limit>`.

Verify:

```sh
"/Library/Application Support/TBPowerAS/tbpower-as-helper" status
cat "/Library/Application Support/TBPowerAS/config"
sudo launchctl print system/com.tbp.tbpower-as.chargelimit | head
```

Optional local archive: `./package.sh` → `dist/TBPowerAS-arm64.tar.gz` (does not publish anything).

## Launch

```sh
open "/Applications/TBPower AS.app"
```

The icon appears in the menu bar (no Dock). For automatic startup: **Options ⚙︎ › Launch at login**.

**Recommended test**: set a limit *below* the current charge (e.g. battery at 88 % → limit 80),
leave the adapter plugged in and check that the menu shows *SMC charge inhibit is on* and that in
*System Settings › Battery* the battery is not charging. `status` should show `paused=1`.

## The menu, item by item

**Header and alerts**
- *Update the helper* — click to copy `cd ~/TBPowerAS && sudo ./install-helper.sh 93` (change the number if you want).
- *Fan stats / control is running* — another app managing fans/sensors may interfere.
- *Amphetamine on* — reminder.
- Sensor row: CPU, GPU, battery temperatures and fan speeds.

**Amphetamine** — display on and disks stay awake; turning it off (or quitting) restores the previous timers.

**Lid closed: don't sleep** — with an external display the Mac stays awake with the lid closed.

**Active profile** — *Power saving* (Low Power) / *Normal*; underneath you see whether you are *On battery* or *On power adapter*.

**Automatic profile** — *Enabled* + profile for **Battery** and **Power adapter**
(default: Power saving on battery, Normal on power adapter).

**Fans** — current speeds, read-only.

**Battery › Charge limit** — 50–100 % slider and *Apply* (the slider alone does not change anything).
- *SMC charge inhibit is on* = charging is held at the limit.
- *Charging managed by another tool (battery maintain …)* = TBPower AS does not intervene while that tool is active.
- Any helper errors; after an error the app retries with increasing delays (up to 5 minutes), without getting stuck.

**About** — version, license, *Project website*, *☕ Buy me a coffee*.

**Footer** — ⚙︎ *Options* (language, launch at login, what to show in the menu bar: Chip / TBP apple / None logo,
CPU temp, CPU %, RAM in GB or %, GPU temp, network) and *Quit*. On quit, sleep and Amphetamine return to normal;
the charge limit stays active thanks to the daemon.

## Complete uninstall

1. In Terminal:
   ```sh
   sudo "/Library/Application Support/TBPowerAS/uninstall.sh"
   ```
   or, from the repo folder: `sudo ./Support/uninstall.sh`.

   The script quits the app, stops and removes the LaunchDaemon (and the log), **re-enables charging**
   (`charge-pause 0`), sets sleep back to normal and Amphetamine off, then deletes `/etc/sudoers.d/tbpower-as`,
   `/Applications/TBPower AS.app` and `/Library/Application Support/TBPowerAS/`.
2. If you were using *Power saving*: `sudo pmset -a lowpowermode 0`.
3. Optional, preferences: `defaults delete com.tbp.tbpower-as`.
4. Remove TBPower AS from *System Settings › General › Login Items* if it is still there.

Manual (if the script is missing):
```sh
sudo launchctl bootout system/com.tbp.tbpower-as.chargelimit
sudo "/Library/Application Support/TBPowerAS/tbpower-as-helper" charge-pause 0
sudo rm -f /Library/LaunchDaemons/com.tbp.tbpower-as.chargelimit.plist /etc/sudoers.d/tbpower-as
sudo rm -rf "/Applications/TBPower AS.app" "/Library/Application Support/TBPowerAS"
```

## Troubleshooting

**Charging is held and I want it to resume immediately**
```sh
sudo "/Library/Application Support/TBPowerAS/tbpower-as-helper" charge-pause 0
```
The daemon will however reapply the limit within 15 s. To remove the limit entirely:
```sh
sudo "/Library/Application Support/TBPowerAS/tbpower-as-helper" charge-limit 100
```
(or 100 % from the app). With no daemon, nothing inhibits charging: the uninstall script
still runs `charge-pause 0` before removing the helper.

**Conflict with `battery` (actuallymentor)** — if the menu says *Charging managed by another tool*,
`battery maintain` is active and writes the same keys. Stop it and uninstall it:
```sh
battery maintain stop
battery uninstall
```
**AlDente / batt / other limiters** — quit the app and uninstall it (including its helper): two
programs inhibiting charging will fight over the same SMC keys.

**The battery is not rising but TBPower AS is not paused** (`status` → `paused=0`) — that is macOS. Check:
```sh
ioreg -rn AppleSmartBattery | grep -E '"NotChargingReason"|"ChargerInhibitReason"|"MaxCapacity"|"CurrentCapacity"'
```
`ChargerInhibitReason` is the inhibit set by TBPower AS; a `NotChargingReason` other than 0 with
`ChargerInhibitReason` at 0 means the system itself is not charging: **Optimized Battery Charging** /
*Battery Health Management* (System Settings › Battery › ⓘ), a hot battery, a weak adapter.
If you want TBPower AS alone to decide, turn off *Optimized Battery Charging*.

**Error `-15` / `inibizione carica fallita`** — the firmware ignores the chosen key. Update to the latest
version (CHTE takes precedence) and reinstall the helper. If it persists, open an issue with the output of `status`.

**`SMC carica non supportato`** during installation — this model/firmware exposes neither `CHTE`
nor `CH0B/CH0C`: the charge limit is not available (the sudo rule is not created).

**The app is unresponsive / high CPU** — quit it with `killall TBPowerAS`, update and reinstall.

**macOS blocks the app** — it is ad-hoc signed. If you built it yourself this usually does not happen; otherwise
right-click › Open or `xattr -dr com.apple.quarantine "/Applications/TBPower AS.app"`.

**Logs** — `/var/log/tbpower-as-chargelimit.log` (exit code 2 = conflict with `battery maintain`).

## Security: what it does as root

- The app runs **as a normal user**. Privileged actions go through
  `/Library/Application Support/TBPowerAS/tbpower-as-helper` (root:wheel 755).
- `/etc/sudoers.d/tbpower-as` allows **only that binary** without a password (rule checked with `visudo`).
- Allowed commands (closed list, validated arguments, otherwise code 64):
  `charge-limit <50-100>` (saves only the config), `charge-pause 0|1`, `lowpower 0|1`, `nosleep 0|1`,
  `amphetamine 0|1`, `enforce`, `reapply` (re-enables charging), and read-only even without sudo
  `charge-supported`, `status`.
- **No fan commands**, no kext, no forced discharge.
- SMC writes concern **only** charge inhibit (`CHTE` or `CH0B/CH0C`), with a read-back and
  *fail-open* restore; the app and the daemon are serialized by a lock (`helper.lock`).
- It runs only `/usr/bin/pmset` and `/usr/bin/pgrep` with absolute paths, with no shell, cleaned environment.
- No network, no telemetry.
- **Use at your own risk**: the SMC is not documented by Apple and can change with updates.

## Donation

TBPower AS is free. If you find it useful, buy me a coffee:

**[☕ Buy me a coffee (€2)](https://paypal.me/tonybasspower/2EUR)**

## License and credits

- TBPower AS: **MIT** — © 2026 Tony Basspower, see [`LICENSE`](LICENSE) (same license as TBPower Intel).
- Charge SMC protocol implemented independently after checking the public values of
  [charlie0129/batt](https://github.com/charlie0129/batt) (GPL-2.0, **no code copied**) and
  [actuallymentor/battery](https://github.com/actuallymentor/battery) (MIT). See
  [`Support/Licenses/THIRD-PARTY-NOTICES.md`](Support/Licenses/THIRD-PARTY-NOTICES.md).
- Hardware probe data: [`docs/probe-M1Pro.md`](docs/probe-M1Pro.md#english).
- Not affiliated with Apple. *Apple Silicon, Mac and macOS are trademarks of Apple Inc.*
- Intel version: **[TBPower](https://github.com/tonybasspower/TBPower)**.
