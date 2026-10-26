#!/system/bin/sh
# ============================================================
# DroidVM - 开机自启（Magisk late_start service 阶段）
# 读取 settings.conf: AUTOSTART=1 才启动，BOOT_DELAY 秒后执行
#
# ⚠ 为什么整个逻辑要包在 ( ... ) & 里：
#   Magisk 的 service.sh 是同步执行的，一个脚本卡住会拖着同阶段
#   其它模块一起等。v1.0.0 是同步的：sleep 45 秒 + mgmt.sh start
#   内部最多再等 180 秒（轮询 SSH 就绪），最坏阻塞 225 秒。
#   v1.0.1 起改为后台子 shell，service.sh 立即返回。
# ============================================================
MODDIR=/data/adb/modules/DroidVM
DATADIR=/data/local/droidvm
SETTINGS=$DATADIR/settings.conf
LOG=$DATADIR/boot.log

(
  mkdir -p "$DATADIR" 2>/dev/null
  exec >> "$LOG" 2>&1
  echo "=========== [$(date)] DroidVM boot service ==========="

  [ -f "$SETTINGS" ] || {
    cp "$MODDIR/settings.conf" "$SETTINGS" 2>/dev/null
    chmod 600 "$SETTINGS" 2>/dev/null
  }
  . "$SETTINGS" 2>/dev/null

  [ "$AUTOSTART" = "1" ] || { echo "AUTOSTART=0，跳过"; exit 0; }

  # 等开机动画结束（比固定 sleep 可靠：慢设备不会抢跑，快设备不白等）
  i=0
  until [ "$(getprop init.svc.bootanim)" = "stopped" ]; do
    sleep 5
    i=$((i+1))
    [ $i -gt 120 ] && break      # 兜底：最多等 10 分钟
  done

  sleep "${BOOT_DELAY:-45}"

  # 已在运行则跳过
  if pgrep -f 'qemu-system-aarch64 -machine' >/dev/null 2>&1; then
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
) &
