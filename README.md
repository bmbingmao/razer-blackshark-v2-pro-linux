# Razer BlackShark V2 Pro 2.4 — Full Linux Support (Battery & More)

Full working battery/charging support for the **Razer BlackShark V2 Pro 2.4 GHz dongle
(USB 1532:0555)** on Linux, including complete KDE Plasma visibility (system tray,
Power & Battery settings, Info Center, System Monitor sensor list).

## Features

| Feature | Status |
|---|---|
| Battery level / charging state | ✅ kernel power_supply + upower |
| KDE tray / Power & Battery settings / Info Center | ✅ real-time battery icon |
| System Monitor sensor list (Power group) | ✅ `power/<serial>/chargePercentage` |
| Equalizer / sidetone / auto power-off / DND (from the driver) | ✅ via PR #2862 |
| Userspace-only battery script (no kernel driver) | ✅ `scripts/razer-battery.py` (hidraw) |

## Why this repo

The official openrazer driver does **not support any headsets**. Community PR
[#2862](https://github.com/openrazer/openrazer/pull/2862) adds full support for 1532:0555
(the 64-byte MXIC vendor protocol, reverse-engineered from Synapse USB captures),
but it is **not merged yet**. This repo turns it into a one-shot install and adds
the missing pieces for a complete experience:

1. **`power_supply` registration** — battery appears in `/sys/class/power_supply/` and upower,
   with a last-known-good cache so a sleeping headset never blanks the UI
2. **`SOUND_FORM_FACTOR=headset` udev rule** ⭐ — battery appears in the KDE tray / Power & Battery settings / Info Center

*(An earlier version also registered a hwmon chip; it was dropped after upstream review —
the power_supply core already auto-registers an empty hwmon node, and reporting a
percentage as µW only misleads `sensors`.)*

### About point 3 (the unique finding in this repo)

The model string "BlackShark V2 Pro" contains no headset/headphone keyword, so systemd's
`78-sound-card.rules` never sets `SOUND_FORM_FACTOR`; upower then classifies the dongle as
`UP_DEVICE_KIND_OTHER_AUDIO` (21), and Solid's `queryDeviceInterface(Battery)` whitelist
refuses to expose a Battery interface — **so no KDE UI ever shows the battery**.

One udev rule fixes it (**works for any USB headset battery**):

```udev
SUBSYSTEM=="sound", KERNEL=="card*", SUBSYSTEMS=="usb", ATTRS{idVendor}=="1532", ATTRS{idProduct}=="0555", ENV{SOUND_FORM_FACTOR}="headset"
```

## Installation

```bash
git clone https://github.com/bmbingmao/razer-blackshark-v2-pro-linux
cd razer-blackshark-v2-pro-linux
sudo ./scripts/install.sh
```

The script: applies the driver patch to your installed openrazer-driver (DKMS),
rebuilds/reinstalls the module, writes the udev rules, then loads the module and binds
the device. **No reboot required** (persists across reboots and dongle re-plugs).

Requirements: `openrazer-driver-dkms`, `dkms` (kernel headers are pulled automatically).

> ⚠️ **After an openrazer package update**: `/usr/src/openrazer-driver-*` gets overwritten —
> just re-run `install.sh` to restore.

## Verify

```bash
cat /sys/class/power_supply/razer_blackshark_battery/capacity   # 82
cat /sys/class/power_supply/razer_blackshark_battery/status     # Charging
upower -d | grep -A8 razer
# KDE: tray battery icon / Settings > Power & Battery / Info Center → Razer BlackShark V2 Pro 2.4
```

If KDE UIs don't show it yet (device appeared mid-session):
`systemctl --user restart plasma-plasmashell.service`, or log out and back in.

## Don't want a kernel driver?

Just check the battery occasionally — no kernel module needed:

```bash
python3 scripts/razer-battery.py        # requires udev/99-razer-blackshark.rules (installed by the script)
```

## Repository layout

```
patches/                  # patched driver source (based on openrazer PR #2862, + power_supply)
udev/                     # hidraw permission rule + SOUND_FORM_FACTOR rule
scripts/install.sh        # one-shot installer (idempotent, safe to re-run)
scripts/razer-battery.py  # hidraw battery reader (no kernel driver needed)
```

## Credits

- [openrazer PR #2862](https://github.com/openrazer/openrazer/pull/2862) — FalconHeavy57
  reverse-engineered the MXIC protocol and wrote the driver this repo is based on
- AlexandreFournier / mehmetbayoglu — protocol discussions
- Driver patches here are modifications of the GPL-2.0-or-later openrazer driver

## License

GPL-2.0-or-later (same as the openrazer driver)

[简体中文版](README.zh-CN.md)
