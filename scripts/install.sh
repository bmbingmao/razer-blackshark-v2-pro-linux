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
dkms build --force -m openrazer-driver -k "$KERNEL" >/dev/null 2>&1 || dkms build --force "$(dkms status | awk -F'[,/ ]' '/openrazer/{print $2"/"$3; exit}')" -k "$KERNEL"
VERSION="$(dkms status | awk -F'[,/ ]' '/openrazer/{print $3; exit}')"
dkms install --force -m openrazer-driver -v "$VERSION" -k "$KERNEL"

echo "==> 3/5 写入 udev 规则 + sensors 配置"
install -m 644 "$SRC_DIR/udev/99-razer-blackshark.rules" /etc/udev/rules.d/
install -m 644 "$SRC_DIR/udev/90-razer-blackshark-sound.rules" /etc/udev/rules.d/
install -Dm 644 "$SRC_DIR/sensors.d/razer-blackshark.conf" /etc/sensors.d/razer-blackshark.conf
echo 'razerblackshark' > /etc/modules-load.d/razerblackshark.conf
udevadm control --reload
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
if [ -f /sys/class/power_supply/razer_blackshark_battery/capacity ]; then
  echo "✅ 电量: $(cat /sys/class/power_supply/razer_blackshark_battery/capacity)%  $(cat /sys/class/power_supply/razer_blackshark_battery/status)"
else
  echo "⚠️ 电源设备未出现 —— 确认接收器已插入;若耳机未开机则查询会超时,属正常"
fi
echo "✅ 完成。KDE 侧如未显示:重启 plasmashell (systemctl --user restart plasma-plasmashell.service) 或重新登录"
