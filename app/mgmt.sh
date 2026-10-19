#!/system/bin/sh
# =============================================================
# DVM Lite 管理脚本
# 用法: sh mgmt.sh {status|start|stop|restart|net|logs|ql|a2a|mp}
# 所有操作限定在 /data/adb/dvm-* 下，不触碰 box_for_root 等代理模块
# =============================================================

CHROOT=/data/adb/dvm-root
PAYLOAD=/data/adb/dvm-payload
SERVICES=/data/adb/dvm-services
LOG=/data/adb/dvm-lite.log

A2A_PAT='^/usr/local/bin/agent2api-server'
A2A_PORT=3065
QL_ROOT=$SERVICES/qinglong
QL_PORT=5700
MP_ROOT=$SERVICES/mipaiai
MP_PORT=36592

log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

# ---------- 工具函数 ----------
is_running() { pgrep -f "$1" >/dev/null 2>&1; }

port_listening() {
    netstat -tln 2>/dev/null | grep -q ":$1 "
}

lan_ip() {
    ip -4 addr show wlan0 2>/dev/null | grep -oE 'inet [0-9.]+' | cut -d' ' -f2 | head -1
}

mem_used() {
    free -m 2>/dev/null | awk '/Mem:/{print $3"/"$2" MB"}'
}

# ---------- 服务控制 ----------
a2a_start() {
    if is_running "$A2A_PAT"; then
        echo "agent2api 已在运行 (pid=$(pgrep -f "$A2A_PAT" | head -1))"
        return 0
    fi
    if [ -x /data/adb/modules/dvm_lite/common/start.sh ]; then
        sh /data/adb/modules/dvm_lite/common/start.sh
    elif [ -x /data/adb/dvm-lite/start.sh ]; then
        sh /data/adb/dvm-lite/start.sh
    else
        echo "找不到 start.sh"
        return 1
    fi
    sleep 3
    if is_running "$A2A_PAT"; then
        echo "agent2api 启动成功 (pid=$(pgrep -f "$A2A_PAT" | head -1))"
        log "a2a started"
    else
        echo "agent2api 启动失败，见 $LOG"
        return 1
    fi
}

a2a_stop() {
    if ! is_running "$A2A_PAT"; then
        echo "agent2api 未运行"
        return 0
    fi
    P=$(pgrep -f "$A2A_PAT" | head -1)
    kill "$P" 2>/dev/null
    sleep 3
    is_running "$A2A_PAT" && kill -9 "$P" 2>/dev/null
    sleep 1
    echo "agent2api 已停止"
    log "a2a stopped"
}

ql_start() {
    if is_running '^/usr/bin/node .*qinglong'; then
        echo "qinglong 已在运行"
        return 0
    fi
    if [ ! -d "$QL_ROOT" ]; then
        echo "qinglong rootfs 未部署（$QL_ROOT 不存在）"
        return 1
    fi
    sh "$SERVICES/qinglong-start.sh"
}

mp_start() {
    if is_running 'mi-paiai'; then
        echo "mi-paiai 已在运行"
        return 0
    fi
    if [ ! -d "$MP_ROOT" ]; then
        echo "mi-paiai rootfs 未部署（$MP_ROOT 不存在）"
        return 1
    fi
    sh "$SERVICES/mipaiai-start.sh"
}

# ---------- 主命令 ----------
cmd_status() {
    echo "###HOST###"
    IP=$(lan_ip)
    echo "LAN_IP=$IP"
    echo "UPTIME=$(uptime 2>/dev/null | sed 's/.*up //;s/,.*//')"
    echo "MEM=$(mem_used)"
    # 用 df 代替 du：du 扫 1.6G rootfs 会卡住 App 十几秒
    echo "ROOTFS=$(df -h "$CHROOT" 2>/dev/null | tail -1 | awk '{print $3" used / "$2}')"

    echo "###SERVICES###"
    # agent2api
    if is_running "$A2A_PAT"; then
        echo "agent2api|RUNNING|$(pgrep -f "$A2A_PAT" | head -1)|$A2A_PORT|$(port_listening $A2A_PORT && echo LISTEN || echo CLOSED)"
    else
        echo "agent2api|STOPPED|-|$A2A_PORT|CLOSED"
    fi
    # qinglong
    if port_listening $QL_PORT; then
        echo "qinglong|RUNNING|$(pgrep -f 'qinglong' | head -1)|$QL_PORT|LISTEN"
    else
        echo "qinglong|STOPPED|-|$QL_PORT|CLOSED"
    fi
    # mi-paiai
    if port_listening $MP_PORT; then
        echo "mi-paiai|RUNNING|$(pgrep -f 'mi-paiai' | head -1)|$MP_PORT|LISTEN"
    else
        echo "mi-paiai|STOPPED|-|$MP_PORT|CLOSED"
    fi

    echo "###MODULE###"
    if [ -d /data/adb/modules/dvm_lite ]; then
        [ -f /data/adb/modules/dvm_lite/disable ] && echo "DISABLED" || echo "ENABLED"
    else
        echo "NOT_INSTALLED"
    fi
}

# ---------- K40 容器控制（经 chroot SSH；不用远程容器可留空） ----------
K40_HOST=""
K40_SSH="chroot /data/adb/dvm-root /usr/bin/env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o ServerAliveInterval=10 -p 2222 dvm@$K40_HOST"

# 远程执行命令（base64 封装，规避多层引号问题）
k40_exec() {
    B64=$(printf '%s' "$1" | base64 2>/dev/null | tr -d '\n')
    [ -z "$B64" ] && return 1
    $K40_SSH "echo $B64 | base64 -d | bash" 2>/dev/null
}

cmd_containers() {
    echo "###CONTAINERS###"
    k40_exec 'sudo -n docker ps -a --format "{{.Names}}|{{.Status}}|{{.Image}}"' || echo "ERROR: 无法连接 K40"
}

cmd_ctl() {
    NAME="$2"
    ACT="$3"
    case "$ACT" in
        start|stop|restart) ;;
        *) echo "usage: mgmt.sh ctl <name> <start|stop|restart>"; return 1 ;;
    esac
    [ -z "$NAME" ] && { echo "usage: mgmt.sh ctl <name> <action>"; return 1; }
    R=$(k40_exec "sudo -n docker $ACT $NAME")
    if [ -n "$R" ]; then
        echo "$R"
    else
        echo "ERROR: 操作失败（$NAME $ACT）"
    fi
}

cmd_net() {
    echo "###NETWORK###"
    echo "LAN_IP=$(lan_ip)"
    echo "WIFI=$(settings get global wifi_on)"
    # Android 多路由表：用 ip route get 探测实际网关
    GW=$(ip route get 1.1.1.1 2>/dev/null | grep -oE 'via [0-9.]+' | cut -d' ' -f2 | head -1)
    [ -z "$GW" ] && GW=$(ip route 2>/dev/null | grep -E '^default' | awk '{print $3}' | head -1)
    echo "GATEWAY=${GW:-unknown}"
    if [ -n "$GW" ]; then
        ping -c 2 -W 2 "$GW" >/dev/null 2>&1 && echo "GATEWAY_PING=OK" || echo "GATEWAY_PING=FAIL"
    else
        echo "GATEWAY_PING=NO_ROUTE"
    fi
    # 外网
    ping -c 2 -W 3 223.5.5.5 >/dev/null 2>&1 && echo "INTERNET=OK" || echo "INTERNET=FAIL"
    # DNS：用域名解析连通性判断（Android 无 nslookup 时回退到 ping 域名）
    if ping -c 1 -W 3 www.baidu.com >/dev/null 2>&1; then
        echo "DNS=OK"
    else
        echo "DNS=FAIL"
    fi
    # 延迟采样
    LAT=$(ping -c 3 -W 2 223.5.5.5 2>/dev/null | grep -oE 'time=[0-9.]+' | tail -1 | cut -d= -f2)
    echo "LATENCY_MS=${LAT:-n/a}"
    # 服务端口
    echo "###PORTS###"
    for p in $A2A_PORT $QL_PORT $MP_PORT; do
        port_listening $p && echo "$p|OPEN" || echo "$p|CLOSED"
    done
    # 代理模块状态（只读检测，不修改）
    echo "###PROXY###"
    if [ -d /data/adb/modules/box_for_root ]; then
        echo "box_for_root=INSTALLED"
        if pgrep -f -l mihomo >/dev/null 2>&1 || pgrep -f clash >/dev/null 2>&1 || pgrep -f box_for_root >/dev/null 2>&1; then
            echo "proxy_core=RUNNING"
        else
            echo "proxy_core=STOPPED"
        fi
        # TUN 接口检测
        PIF=$(ip -o link show 2>/dev/null | grep -oE '^[0-9]+: (tun|utun|meta|mihomo)[a-z0-9]*' | head -1)
        echo "tun_iface=${PIF:-none}"
    else
        echo "box_for_root=NOT_FOUND"
    fi
}

cmd_logs() {
    echo "###LOG###"
    tail -n "${2:-50}" "$LOG" 2>/dev/null
}

case "$1" in
    status)   cmd_status ;;
    net)      cmd_net ;;
    logs)     cmd_logs "$@" ;;
    start)    a2a_start; ql_start 2>/dev/null; mp_start 2>/dev/null ;;
    stop)     a2a_stop; pkill -f 'qinglong' 2>/dev/null; pkill -f 'mi-paiai' 2>/dev/null ;;
    restart)  a2a_stop; sleep 2; a2a_start ;;
    a2a)      case "$2" in start) a2a_start;; stop) a2a_stop;; restart) a2a_stop; sleep 2; a2a_start;; *) echo "usage: mgmt.sh a2a {start|stop|restart}";; esac ;;
    containers) cmd_containers ;;
    ctl)      cmd_ctl "$@" ;;
    ql)       case "$2" in start) ql_start;; stop) pkill -f 'qinglong';; *) echo "usage: mgmt.sh ql {start|stop}";; esac ;;
    mp)       case "$2" in start) mp_start;; stop) pkill -f 'mi-paiai';; *) echo "usage: mgmt.sh mp {start|stop}";; esac ;;
    *)
        echo "DVM Lite 管理脚本"
        echo "用法: sh mgmt.sh <命令>"
        echo ""
        echo "  status            查看所有服务状态"
        echo "  net               网络诊断"
        echo "  logs [n]          查看日志（默认 50 行）"
        echo "  start             启动所有服务"
        echo "  stop              停止所有服务"
        echo "  restart           重启 agent2api"
        echo "  a2a {start|stop}  单独控制 agent2api"
        echo "  ql  {start|stop}  单独控制 qinglong"
        echo "  mp  {start|stop}  单独控制 mi-paiai"
        ;;
esac
