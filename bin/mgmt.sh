#!/system/bin/sh
# ============================================================
# DroidVM 管理脚本
# 用法: su -c 'sh /data/adb/modules/DroidVM/bin/mgmt.sh {start|stop|restart|status|ssh|docker|log|reseed}'
# 路径约定:
#   /data/adb/modules/DroidVM  模块目录(只读基准: rootfs模板/磁盘模板/脚本模板)
#   /data/local/droidvm        运行数据(rootfs解包/数据盘/seed/日志/settings)
#   chroot 内 /vm  ->  安卓侧 /data/local/droidvm/vm (bind mount)
# ============================================================
MODDIR=/data/adb/modules/DroidVM
DATADIR=/data/local/droidvm
ROOTFS=$DATADIR/rootfs
VMDIR=$DATADIR/vm
PIDF=$VMDIR/qemu.pid
SETTINGS=$DATADIR/settings.conf
LOG=$VMDIR/console.log

# ---------- 工具函数 ----------
log() { echo "[$(date '+%m-%d %H:%M:%S')] $*"; }
die() { echo "[!] $*" >&2; exit 1; }

load_settings() {
  # 数据目录可能不存在（全新安装），必须先建——否则 cp 静默失败
  mkdir -p "$DATADIR" "$VMDIR" 2>/dev/null
  if [ ! -f "$SETTINGS" ]; then
    cp "$MODDIR/settings.conf" "$SETTINGS" 2>/dev/null
  fi
  [ -f "$SETTINGS" ] || die "settings.conf 缺失"
  # 内含明文凭据：无论新建还是旧版遗留（644），一律收紧到 600
  chmod 600 "$SETTINGS" 2>/dev/null
  . "$SETTINGS"
  # 内存自适应: MemTotal 的 40%，钳制 1536~6144MB
  if [ "$VM_MEM" = "auto" ] || [ -z "$VM_MEM" ]; then
    MT=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null)
    [ -z "$MT" ] && MT=8388608
    VM_MEM=$(( MT * 40 / 100 / 1024 ))
    [ "$VM_MEM" -lt 1536 ] && VM_MEM=1536
    [ "$VM_MEM" -gt 6144 ] && VM_MEM=6144
  fi
  [ -z "$VM_SMP" ] && VM_SMP=2
  [ -z "$VM_DISK_AUTO" ] && VM_DISK_AUTO=1
}

lan_ip() {
  ip route get 1.1.1.1 2>/dev/null | sed -n 's/.*src \([0-9.]*\).*/\1/p' | head -1
}

# 注意：不能用 pgrep -x ——Linux comm 截断 15 字符，"qemu-system-aarch64" 是 19 字符，
# -x 精确匹配永远失败（真我实测 pkill -x 杀不掉进程）。
# 用 -f 匹配命令行特征（-machine 是 QEMU 独有，不会误伤 nc/shell）
ps_qemu() { pgrep -f 'qemu-system-aarch64 -machine' 2>/dev/null; }

build_hostfwd() {
  # netdev 选项之间必须用逗号连接（空格会被 QEMU 当成独立参数，
  # 报 "Unknown protocol 'hostfwd=tcp'"——真我 RMX1971 实测）
  #
  # 支持两种写法：
  #   hp:gp              只写两段 -> 绑 0.0.0.0（局域网可访问）
  #   bind:hp:gp         写三段   -> 绑指定地址，如 127.0.0.1 仅本机
  # 例：VM_PORTS="2222:22 127.0.0.1:5700:5700"
  #     SSH 对整个局域网开放，青龙只允许手机本机访问（配隧道/反代更安全）
  HOSTFWD=""
  for p in $VM_PORTS; do
    case "$p" in
      *:*:*)
        bind=${p%%:*}
        rest=${p#*:}
        hp=${rest%%:*}; gp=${rest##*:}
        ;;
      *)
        bind=0.0.0.0
        hp=${p%%:*}; gp=${p##*:}
        ;;
    esac
    HOSTFWD="$HOSTFWD,hostfwd=tcp:$bind:$hp-:$gp"
  done
}

# 从 VM_PORTS 某一项里取出宿主端口（兼容两段/三段写法）
port_of() {
  case "$1" in
    *:*:*) echo "$1" | cut -d: -f2 ;;
    *) echo "$1" | cut -d: -f1 ;;
  esac
}

guest_ssh() {
  chroot "$ROOTFS" /usr/bin/env -i PATH=/usr/bin:/bin \
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -p 2222 dvm@127.0.0.1 "$@"
}

# ---------- rootfs 就绪 ----------
ensure_rootfs() {
  if [ ! -x "$ROOTFS/usr/bin/qemu-system-aarch64" ]; then
    log "[*] 首次运行：解压 rootfs 模板（约 1-2 分钟）..."
    mkdir -p "$ROOTFS"
    TARBALL="$MODDIR/rootfs/ubuntu22-qemu.tar.xz"
    [ -f "$TARBALL" ] || die "rootfs 模板缺失: $TARBALL"
    # 必须用带 xz applet 的 tar：系统 toybox tar 调不到 xz 二进制（真我 RMX1971 实测失败）
    TARBIN=""
    for BB in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox \
              $(command -v busybox 2>/dev/null); do
      [ -n "$BB" ] && [ -x "$BB" ] && TARBIN="$BB" && break
    done
    [ -n "$TARBIN" ] || die "未找到 busybox（xz 解压需要）"
    "$TARBIN" tar -xJf "$TARBALL" -C "$ROOTFS" || die "rootfs 解压失败（存储空间不足？）"
    # toybox tar 遇 xz 缺失时可能返回 0 但实际没解开——必须校验产物
    [ -x "$ROOTFS/usr/bin/qemu-system-aarch64" ] || die "rootfs 解压不完整（qemu 二进制缺失）"
    rm -f "$ROOTFS"/etc/ssh/ssh_host_* 2>/dev/null
    chroot "$ROOTFS" /usr/sbin/ssh-keygen -A 2>/dev/null
    log "[+] rootfs 就绪"
  fi
  # bind mount 基础文件系统 + 数据目录
  for d in proc sys dev dev/pts; do
    mountpoint -q "$ROOTFS/$d" 2>/dev/null || mount --bind "/$d" "$ROOTFS/$d" 2>/dev/null
  done
  mkdir -p "$VMDIR" "$ROOTFS/vm"
  mountpoint -q "$ROOTFS/vm" 2>/dev/null || mount --bind "$VMDIR" "$ROOTFS/vm" 2>/dev/null
}

# ---------- 数据盘就绪 ----------
ensure_disk() {
  DISK_QEMU="/vm/dvmsrv.qcow2"
  if [ -n "$VM_DISK_CUSTOM" ] && [ -f "$VM_DISK_CUSTOM" ]; then
    # 自定义盘: bind 其所在目录到 chroot /vmext
    mkdir -p "$ROOTFS/vmext"
    mountpoint -q "$ROOTFS/vmext" 2>/dev/null || \
      mount --bind "$(dirname "$VM_DISK_CUSTOM")" "$ROOTFS/vmext" 2>/dev/null
    DISK_QEMU="/vmext/$(basename "$VM_DISK_CUSTOM")"
  elif [ ! -f "$VMDIR/dvmsrv.qcow2" ] && [ "$VM_DISK_AUTO" = "1" ]; then
    TPL="$MODDIR/vm/debian12-cloud-arm64.qcow2"
    [ -f "$TPL" ] || die "磁盘模板缺失: $TPL"
    log "[*] 首次运行：从模板创建数据盘（325MB， cloud-init 装配 20-120 分钟（视机型））..."
    cp "$TPL" "$VMDIR/dvmsrv.qcow2" || die "数据盘创建失败（存储空间不足？）"
    log "[+] 数据盘已创建"
  fi
  [ -f "$VMDIR/dvmsrv.qcow2" ] || [ -n "$VM_DISK_CUSTOM" ] || die "数据盘不存在且未启用自动创建"
  if [ ! -f "$VMDIR/AAVMF_VARS.fd" ]; then
    cp "$ROOTFS/usr/share/AAVMF/AAVMF_VARS.fd" "$VMDIR/AAVMF_VARS.fd" 2>/dev/null
  fi
}

# ---------- 生成 seed.iso（cloud-init，chroot 内 genisoimage） ----------
gen_seed() {
  UD="$VMDIR/user-data"; MD="$VMDIR/meta-data"
  mkdir -p "$VMDIR"
  sed -e "s|__DVM_PASSWORD__|$DVM_PASSWORD|g" \
      -e "s|__PANEL_PORT__|$PANEL_PORT|g" \
      -e "s|__PANEL_ENTRANCE__|$PANEL_ENTRANCE|g" \
      -e "s|__PANEL_USER__|$PANEL_USER|g" \
      -e "s|__PANEL_PASSWORD__|$PANEL_PASSWORD|g" \
      "$MODDIR/vm/templates/user-data" > "$UD" || die "user-data 生成失败"
  cp "$MODDIR/vm/templates/meta-data" "$MD"
  chroot "$ROOTFS" /usr/bin/genisoimage -output /vm/seed.iso -volid cidata -joliet -rock /vm/user-data /vm/meta-data 2>/dev/null \
    || die "seed.iso 生成失败"
  log "[+] seed.iso 已生成"
}

# ---------- 启动 ----------
do_start() {
  load_settings
  [ -n "$(ps_qemu)" ] && { log "[=] 虚拟机已在运行 PID=$(ps_qemu)"; return 0; }
  ensure_rootfs
  ensure_disk
  if [ ! -f "$VMDIR/seed.iso" ] || [ "$VMDIR/seed.iso" -ot "$SETTINGS" ]; then
    gen_seed
  fi
  build_hostfwd
  # 端口占用检查（netstat 不可用时跳过）
  if command -v netstat >/dev/null 2>&1; then
    for p in $VM_PORTS; do
      hp=$(port_of "$p")
      if netstat -tln 2>/dev/null | grep -q ":$hp "; then
        die "端口 $hp 已被占用，请修改 $SETTINGS 中的 VM_PORTS"
      fi
    done
  fi
  log "[*] 启动 QEMU（mem=${VM_MEM}MB smp=$VM_SMP disk=$DISK_QEMU）..."
  chroot "$ROOTFS" /usr/bin/env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    /usr/bin/qemu-system-aarch64 \
    -machine virt -cpu max -smp "$VM_SMP" -m "$VM_MEM" -accel tcg,thread=multi \
    -drive if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/AAVMF/AAVMF_CODE.fd \
    -drive if=pflash,format=raw,unit=1,file=/vm/AAVMF_VARS.fd \
    -drive if=none,id=d0,format=qcow2,file="$DISK_QEMU" \
    -device virtio-blk-device,drive=d0,bootindex=0 \
    -drive if=none,id=cd0,format=raw,file=/vm/seed.iso \
    -device virtio-blk-device,drive=cd0,bootindex=1 \
    -netdev user,id=n0$HOSTFWD \
    -device virtio-net-device,netdev=n0,mac=52:54:00:12:34:56 \
    -display none \
    -serial tcp:127.0.0.1:6666,server,nowait \
    -monitor tcp:127.0.0.1:5555,server,nowait \
    >> "$LOG" 2>&1 &
  P=$(ps_qemu)
  [ -n "$P" ] && { echo "$P" > "$PIDF"; log "[+] 已启动 PID=$P"; } || die "启动失败，见 $LOG"
  log "[i] 等待系统就绪（TCG 启动约 40-120 秒）..."
  IP=$(lan_ip); [ -z "$IP" ] && IP=127.0.0.1
  i=0
  while [ $i -lt 36 ]; do
    sleep 5
    if guest_ssh true 2>/dev/null; then
      log "[+] SSH 就绪（$((i*5+5)) 秒）"
      break
    fi
    i=$((i+1))
  done
  [ $i -ge 36 ] && log "[!] 等待超时，VM 可能仍在启动，稍后执行 status 查看"
  log "[i] SSH:   ssh -p 2222 dvm@$IP"
  log "[i] Panel: http://$IP:$PANEL_PORT/$PANEL_ENTRANCE"
}

do_stop() {
  P=$(ps_qemu)
  [ -z "$P" ] && { log "[=] 未运行"; rm -f "$PIDF"; return 0; }
  log "[*] 停止虚拟机 PID=$(echo $P | tr '\n' ' ') ..."
  # 必须杀全部实例：漏杀会导致双 QEMU 同时写同一 qcow2（磁盘损坏）
  for p in $P; do kill "$p" 2>/dev/null; done
  i=0
  while [ $i -lt 20 ]; do sleep 1; [ -z "$(ps_qemu)" ] && break; i=$((i+1)); done
  if [ -n "$(ps_qemu)" ]; then
    for p in $(ps_qemu); do kill -9 "$p" 2>/dev/null; done
    log "[!] 已强制终止"
  else log "[+] 已停止"; fi
  rm -f "$PIDF"
}

do_status() {
  load_settings
  P=$(ps_qemu)
  echo "=== 宿主机 (Android) ==="
  [ -n "$P" ] && echo "QEMU: running PID=$P (mem=${VM_MEM}MB smp=$VM_SMP)" || echo "QEMU: stopped"
  netstat -tln 2>/dev/null | grep -E ':(2222|6666|10086)[[:space:]]' || echo "(端口未监听)"
  echo "LAN IP: $(lan_ip)"
  if [ -x "$ROOTFS/usr/bin/qemu-system-aarch64" ]; then echo "rootfs: 就绪"; else echo "rootfs: 未解压（首次 start 自动解压）"; fi
  echo "=== 访客 (Debian) ==="
  [ -n "$P" ] || { echo "(VM 未运行)"; return 0; }
  timeout 30 guest_ssh 'bash -s' 2>&1 <<'G'
hostname; uname -r
echo "--- services ---"
for s in ssh docker; do printf "%-10s %s\n" "$s" "$(systemctl is-active $s 2>/dev/null)"; done
echo "--- docker ---"
sudo docker ps --format '{{.Names}}\t{{.Status}}' 2>/dev/null | head -8
echo "--- resources ---"
free -h | head -2; df -h / | tail -1
G
}

case "$1" in
  start)   do_start ;;
  stop)    load_settings; do_stop ;;
  restart) load_settings; do_stop; sleep 2; do_start ;;
  status)  do_status ;;
  ssh)     shift; do_ssh() { exec chroot "$ROOTFS" /usr/bin/env -i PATH=/usr/bin:/bin ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 dvm@127.0.0.1 "$@"; }; do_ssh "$@" ;;
  docker)  shift; guest_ssh "sudo docker $*" ;;
  log)     tail -n "${2:-40}" "$LOG" 2>/dev/null || echo "(无日志)" ;;
  reseed)  load_settings; ensure_rootfs; gen_seed; log "[i] seed 仅对全新数据盘首启生效；reseed 后需删除数据盘重来，或进 guest 手动改密" ;;
  *)
    echo "DroidVM 管理脚本"
    echo "用法: su -c 'sh $0 {start|stop|restart|status|ssh|docker|log|reseed}'"
    echo "  start    启动虚拟机（首次自动解压 rootfs、创建数据盘、生成 seed）"
    echo "  stop     停止虚拟机"
    echo "  restart  重启"
    echo "  status   宿主机 + 访客全量状态"
    echo "  ssh      进入访客 shell"
    echo "  docker   访客内执行 docker，如: docker ps -a"
    echo "  log      查看 QEMU 日志"
    echo "  reseed   按当前 settings.conf 重新生成 cloud-init seed"
    ;;
esac
