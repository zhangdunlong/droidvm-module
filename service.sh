#!/system/bin/sh
# ============================================================
# DroidVM - 开机自启（Magisk late_start service 阶段）
# 读取 settings.conf: AUTOSTART=1 才启动，BOOT_DELAY 秒后执行
# ============================================================
MODDIR=/data/adb/modules/DroidVM
DATADIR=/data/local/droidvm
SETTINGS=$DATADIR/settings.conf
LOG=$DATADIR/boot.log

mkdir -p "$DATADIR" 2>/dev/null
exec >> "$LOG" 2>&1
echo "=========== [$(date)] DroidVM boot service ==========="

[ -f "$SETTINGS" ] || cp "$MODDIR/settings.conf" "$SETTINGS" 2>/dev/null
. "$SETTINGS" 2>/dev/null

[ "$AUTOSTART" = "1" ] || { echo "AUTOSTART=0，跳过"; exit 0; }

# 等待系统就绪（默认 45s，避免与开机服务争抢）
sleep "${BOOT_DELAY:-45}"

# 已在运行则跳过
if pgrep -f 'qemu-system-aarch64' >/dev/null 2>&1; then
  echo "QEMU already running, skip."
  exit 0
fi

# 网络就绪后再启动（VM 内 docker 拉取需要网络）
i=0
while [ $i -lt 12 ]; do
  IP=$(ip route get 1.1.1.1 2>/dev/null | sed -n 's/.*src \([0-9.]*\).*/\1/p' | head -1)
  [ -n "$IP" ] && break
  sleep 5; i=$((i+1))
done
echo "network ready: ${IP:-127.0.0.1} (waited $((i*5))s)"

sh "$MODDIR/bin/mgmt.sh" start
echo "=========== [$(date)] DroidVM boot service done ==========="
