#!/usr/bin/env bash
# Razer BlackShark V2 Pro 2.4 (1532:0555) — Linux 一键安装/修复脚本
# 幂等:可重复执行;openrazer 包更新后重跑即可恢复
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRIVER_SRC="$(ls -d /usr/src/openrazer-driver-* 2>/dev/null | head -1 || true)"
KERNEL="$(uname -r)"
USB_VENDOR=1532
USB_PRODUCT=0555
HID_DEV="$(ls /sys/bus/hid/devices/ 2>/dev/null | grep -i "0003:${USB_VENDOR}:${USB_PRODUCT}" | head -1 || true)"

need() { command -v "$1" >/dev/null 2>&1 || { echo "❌ 缺少依赖: $1 (sudo pacman -S $1)"; exit 1; }; }
need dkms; need modprobe; need udevadm

echo "==> 1/5 应用驱动补丁到 $DRIVER_SRC"
[ -n "$DRIVER_SRC" ] || { echo "❌ 未找到 openrazer-driver 源码,请先安装 openrazer-driver-dkms"; exit 1; }
cp "$SRC_DIR/patches/razerblackshark_driver.c" "$DRIVER_SRC/driver/"
cp "$SRC_DIR/patches/razerblackshark_driver.h" "$DRIVER_SRC/driver/"
# razercommon.{c,h}: power_supply helper(PR #2868)扩展,耳机接入 shared helper
cp "$SRC_DIR/patches/razercommon.c" "$DRIVER_SRC/driver/razercommon.c"
cp "$SRC_DIR/patches/razercommon.h" "$DRIVER_SRC/driver/razercommon.h"

# Makefile: obj-m 注册
grep -q 'razerblackshark' "$DRIVER_SRC/driver/Makefile" || {
  sed -i 's/^obj-m := .*/& razerblackshark.o/' "$DRIVER_SRC/driver/Makefile"
  echo 'razerblackshark-y := razerblackshark_driver.o razercommon.o' >> "$DRIVER_SRC/driver/Makefile"
}
# 3.12.x 树没有 compat.c,去掉(如有)
sed -i 's/razerblackshark-y := razerblackshark_driver.o razercommon.o compat.o/razerblackshark-y := razerblackshark_driver.o razercommon.o/' "$DRIVER_SRC/driver/Makefile"

# dkms.conf: 注册模块
grep -q 'razerblackshark' "$DRIVER_SRC/dkms.conf" || {
  N=$(grep -c 'BUILT_MODULE_NAME\[' "$DRIVER_SRC/dkms.conf" || true)
  cat >> "$DRIVER_SRC/dkms.conf" <<EOF
BUILT_MODULE_NAME[$N]="razerblackshark"
BUILT_MODULE_LOCATION[$N]="driver"
DEST_MODULE_LOCATION[$N]="/kernel/drivers/hid"
EOF
}

echo "==> 2/5 编译 + 安装内核模块"
# 内核若用 clang 构建(gcc 会不认识 clang 专属参数),失败时回退 LLVM 编译
dkms build --force -m openrazer-driver -k "$KERNEL" >/dev/null 2>&1 || \
  dkms build --force "$(dkms status | awk -F'[,/ ]+' '/openrazer/{print $1"/"$2; exit}')" -k "$KERNEL" >/dev/null 2>&1 || \
  { CC=clang LLVM=1 dkms build --force -m openrazer-driver -k "$KERNEL" || \
    CC=clang LLVM=1 dkms build --force "$(dkms status | awk -F'[,/ ]+' '/openrazer/{print $1"/"$2; exit}')" -k "$KERNEL"; }
VERSION="$(dkms status | awk -F'[,/ ]+' '/openrazer/{print $2; exit}')"
dkms install --force -m openrazer-driver -v "$VERSION" -k "$KERNEL"

echo "==> 3/5 写入 udev 规则 + hwdb"
install -m 644 "$SRC_DIR/udev/99-razer-blackshark.rules" /etc/udev/rules.d/
install -Dm 644 "$SRC_DIR/udev/71-sound-card-local.hwdb" /etc/udev/hwdb.d/71-sound-card-local.hwdb
echo 'razerblackshark' > /etc/modules-load.d/razerblackshark.conf
udevadm control --reload
# SOUND_FORM_FACTOR 走 hwdb(systemd 原生形式):先触发 usb 导入 ID,再触发 sound card
systemd-hwdb update 2>/dev/null || true
udevadm trigger --action=change --subsystem-match=usb --attr-match=idVendor=1532
udevadm trigger --action=change --subsystem-match=sound

echo "==> 4/5 加载模块 + 绑定设备"
rmmod razerblackshark 2>/dev/null || true
modprobe razerblackshark || true
sleep 1
if [ -n "$HID_DEV" ]; then
  echo "$HID_DEV" > "/sys/bus/hid/drivers/hid-generic/unbind" 2>/dev/null || true
  echo "$HID_DEV" > "/sys/bus/hid/drivers/razerblackshark/bind" 2>/dev/null || true
fi

echo "==> 5/5 验证"
sleep 1
PS_NAME="$(ls /sys/class/power_supply/ 2>/dev/null | grep '^razer_battery_' | head -1 || true)"
if [ -n "$PS_NAME" ]; then
  echo "✅ 电量: $(cat /sys/class/power_supply/$PS_NAME/capacity)%  $(cat /sys/class/power_supply/$PS_NAME/status)"
  echo "   (power_supply 设备: $PS_NAME,耳机休眠时查询超时、显示缓存值为正常)"
else
  echo "⚠️ 电源设备未出现 —— 确认接收器已插入;若耳机未开机则查询会超时,属正常"
fi
echo "✅ 完成。KDE 侧如未显示:重启 plasmashell (systemctl --user restart plasma-plasmashell.service) 或重新登录"
