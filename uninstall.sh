#!/system/bin/sh
# ============================================================
# DroidVM - 卸载脚本
# 默认行为：停止虚拟机，保留全部数据（数据盘/rootfs/settings）
# 如需连数据一起删除：卸载前执行
#   su -c 'touch /data/local/droidvm/.remove_all'
# ============================================================
DATADIR=/data/local/droidvm

# 停止虚拟机
if pgrep -f 'qemu-system-aarch64' >/dev/null 2>&1; then
  echo "[*] 停止虚拟机..."
  kill $(pgrep -f 'qemu-system-aarch64') 2>/dev/null
  sleep 3
  pgrep -f 'qemu-system-aarch64' >/dev/null 2>&1 && kill -9 $(pgrep -f 'qemu-system-aarch64') 2>/dev/null
fi

if [ -f "$DATADIR/.remove_all" ]; then
  echo "[*] 检测到 .remove_all，删除全部数据（rootfs/数据盘/日志）..."
  # 解除 bind mount
  for d in proc sys dev dev/pts vm; do
    umount "$DATADIR/rootfs/$d" 2>/dev/null
  done
  rm -rf "$DATADIR"
  echo "[+] 数据已全部删除"
else
  echo "[=] 数据保留在 $DATADIR（重装模块后可继续使用原数据盘）"
  echo "[=] 如需彻底删除: su -c 'rm -rf $DATADIR'"
fi
