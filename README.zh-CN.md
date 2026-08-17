# Razer BlackShark V2 Pro 2.4 — Linux 完整支持(电量等)

让 **Razer BlackShark V2 Pro 2.4G 接收器(USB 1532:0555)** 在 Linux 上完整工作:
电池电量、充电状态、均衡器、麦克风监听等(基于 openrazer 未合并的 PR #2862 驱动),
并额外打通 **KDE Plasma 托盘 / 电源与电池设置 / 信息中心 / System Monitor 传感器列表** 的完整显示链路。

## 特性

| 功能 | 状态 |
|---|---|
| 电量 / 充电状态 | ✅ 内核 power_supply(共享 helper,PR #2868)+ upower |
| KDE 托盘 / 电源与电池设置 / 信息中心 | ✅ 电池图标实时显示 |
| System Monitor 传感器列表(电源分组) | ✅ `power/<serial>/chargePercentage` |
| 均衡器 / 侧音 / 自动关机 / DND(驱动自带) | ✅ 来自 PR #2862 |
| 无需内核驱动的轻量读取脚本 | ✅ `scripts/razer-battery.py`(hidraw) |

## 为什么需要这个仓库

openrazer 官方驱动**不支持任何耳机**。社区的 PR
[#2862](https://github.com/openrazer/openrazer/pull/2862) 为 1532:0555 添加了完整驱动
(64 字节 MXIC 厂商协议,由作者从 Synapse USB 抓包逆向),但**尚未合并**。
本仓库把它做成一键安装,并补上 PR 缺失的拼图:

1. **`power_supply` 注册** — 让电池出现在 `/sys/class/power_supply/` 和 upower。
   作为 openrazer [#2868](https://github.com/openrazer/openrazer/pull/2868) 的
   **共享 `razer_power_supply` helper** 的扩展:纯缓存读取(绝不阻塞 HID 路径)、
   异步 worker 刷新、耳机射频链路休眠时返回 last-known-good 缓存值
2. **`SOUND_FORM_FACTOR=headset` hwdb 条目** ⭐ — 让 KDE 托盘/电源面板/信息中心显示它

*(早期版本还注册了 hwmon chip,上游评审后已移除 —— power_supply 内核核心本就会自动
注册一个空的 hwmon 节点,而把百分比伪装成 µW 只会误导 `sensors`。)*

### 关于第 2 点(本仓库的独特发现)

型号名 "BlackShark V2 Pro" 不含 headset/headphone 关键字 → systemd 的
`78-sound-card.rules` 不会设置 `SOUND_FORM_FACTOR` → upower 把设备归类为
`UP_DEVICE_KIND_OTHER_AUDIO`(21)→ Solid 的 `queryDeviceInterface(Battery)`
白名单拒绝暴露 Battery 接口 → **KDE 所有界面都看不到电量**。

一条 hwdb 条目即可修复(**对任何 USB 耳机电池通用**;这是 systemd 自己在
`70-sound-card.hwdb` 里用的形式,可以纯数据补丁方式上游到 systemd):

```
# /etc/udev/hwdb.d/71-sound-card-local.hwdb(属性行前导空格必须有)
usb:v1532p0555*
 SOUND_FORM_FACTOR=headset
```

属性必须落在 sound `card*` 兄弟节点 —— 也就是 upower `up-device-supply.c`
读取 `SOUND_FORM_FACTOR` 的那个节点。

## 安装

```bash
git clone https://github.com/bmbingmao/razer-blackshark-v2-pro-linux
cd razer-blackshark-v2-pro-linux
sudo ./scripts/install.sh
```

脚本会自动:应用驱动补丁到已装的 openrazer-driver(DKMS)、重编译重装模块、
写入 udev 规则、加载模块并绑定设备。**无需重启**(重启或插拔接收器后依然生效)。

要求:已安装 `openrazer-driver-dkms`、`dkms`(内核头文件会自动装)。

> ⚠️ **openrazer 包更新后**:`/usr/src/openrazer-driver-*` 会被覆盖,重跑一遍 `install.sh` 即可恢复。

## 验证

```bash
cat /sys/class/power_supply/razer_battery_*/capacity   # 79
cat /sys/class/power_supply/razer_blackshark_battery/status     # Charging
upower -d | grep -A8 razer
# KDE: 托盘电池图标 / 系统设置-电源与电池 / 信息中心 → Razer BlackShark V2 Pro 2.4
```

如果 KDE 界面还没显示(电池是会话中途出现的):
`systemctl --user restart plasma-plasmashell.service`,或注销重登。

## 不想装内核驱动?

只想偶尔看一眼电量,不需要内核模块:

```bash
python3 scripts/razer-battery.py        # 需要 udev/99-razer-blackshark.rules(脚本已含安装)
```

## 目录结构

```
patches/                  # 补丁后的驱动源码(基于 openrazer PR #2862,power_supply 走 #2868 helper)
udev/                     # hidraw 权限规则 + SOUND_FORM_FACTOR hwdb 条目
scripts/install.sh        # 一键安装(幂等,可重复执行)
scripts/razer-battery.py  # hidraw 直读电量脚本(免内核驱动)
```

## 致谢

- [openrazer PR #2862](https://github.com/openrazer/openrazer/pull/2862) — FalconHeavy57
  逆向出 MXIC 协议并提供完整驱动(本仓库驱动即基于它)
- AlexandreFournier / mehmetbayoglu — 协议细节讨论
- 本仓库补丁(驱动部分)基于 GPL-2.0-or-later 的 openrazer 驱动修改

## 许可证

GPL-2.0-or-later(与 openrazer 驱动一致)

[English version](README.md)
