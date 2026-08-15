#!/usr/bin/env python3
"""
Razer BlackShark V2 Pro 2.4G 接收器电量/充电状态读取
协议逆向自 openrazer PR #2862 (github.com/openrazer/openrazer/pull/2862)
用法: sudo python3 razer-battery.py   (或配置 udev 后直接运行)
"""
import hid, time, sys

VID, PID = 0x1532, 0x0555
CMD_BATTERY = 0x21   # 返回 0-100
CMD_CHARGING = 0x2a  # 0=使用电池, 非0=插线充电

def find_path():
    for d in hid.enumerate(VID, PID):
        if d.get('interface_number') == 3 and d.get('usage_page') == 0xff00:
            return d['path']
    return None

def _frame():
    return bytearray(64)

def remote_mode(on: bool) -> bytes:
    b = _frame()
    b[0] = 0x02; b[1] = 0x80; b[2] = 0x07
    b[5] = ord('P'); b[6] = ord('A'); b[7] = 0x0E
    b[9] = 0x02; b[10] = 0xE1; b[11] = 1 if on else 0
    return bytes(b)

def query(cmd_id: int) -> bytes:
    b = _frame()
    b[0] = 0x02; b[1] = 0x80; b[2] = 0x08
    b[5] = ord('P'); b[6] = ord('A'); b[7] = 0x08
    b[9] = 0x03; b[10] = cmd_id; b[12] = 0x00
    return bytes(b)

def do_query(h, cmd_id, name, attempts=3):
    for _ in range(attempts):
        h.write(remote_mode(True));  time.sleep(0.05)
        h.write(query(cmd_id));      time.sleep(0.05)
        for _ in range(6):           # 设备会先发无关的 'PI' 遥测帧,需跳过
            r = bytes(h.read(64, timeout=400))
            if not r:
                break
            if len(r) > 15 and r[12] == cmd_id and r[13] == 0x01:
                h.write(remote_mode(False)); time.sleep(0.03)
                return r[15]
        h.write(remote_mode(False)); time.sleep(0.05)
    raise RuntimeError(f"{name} 查询失败(耳机是否已开机且与接收器连接?)")

def main():
    path = find_path()
    if not path:
        print("未找到 BlackShark V2 Pro 接收器(请确认已插入)"); sys.exit(1)
    h = hid.Device(path=path)
    print(f"设备: {h.manufacturer} {h.product}")
    try:
        bat = do_query(h, CMD_BATTERY, "电量")
        chg = do_query(h, CMD_CHARGING, "充电")
        print(f"\n🔋 电量: {bat}%")
        print(f"🔌 状态: {'充电中(插线)' if chg else '使用电池'}")
    except RuntimeError as e:
        print(f"❌ {e}"); sys.exit(2)
    finally:
        h.close()

if __name__ == '__main__':
    main()
