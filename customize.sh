#!/sbin/sh
# ============================================================
# DroidVM for Magisk - 安装脚本
# 运行环境: Magisk 安装器 (busybox ash)
# ============================================================

SKIPMOUNT=false
PROPFILE=false
POSTFSDATA=false
LATESTARTSERVICE=true

ARCH=$(grep -E '^ro.product.cpu.abi' /system/build.prop 2>/dev/null | head -1 | cut -d= -f2)
[ -z "$ARCH" ] && ARCH=$(getprop ro.product.cpu.abi 2>/dev/null)

ui_print "- DroidVM for Magisk v1.0.0"
ui_print "- 在已 root 的安卓手机上运行完整 Debian 12 虚拟机"
ui_print "- (QEMU/TCG + Docker + 1Panel)"

# ---- 架构检查 ----
case "$ARCH" in
  arm64*|aarch64*) ui_print "- 架构: $ARCH (支持)" ;;
  *)
    ui_print "! 架构: $ARCH"
    ui_print "! 本模块仅支持 arm64 安卓设备（内置 aarch64 QEMU）"
    ui_print "! 安装将继续，但虚拟机无法启动"
    ;;
esac

# ---- 存储空间检查（rootfs+磁盘约需 1.5GB 可用） ----
FREE_MB=$(df /data/local 2>/dev/null | awk 'NR==2 {print int($4/1024)}')
[ -z "$FREE_MB" ] && FREE_MB=99999
ui_print "- /data/local 可用空间: ${FREE_MB}MB"
if [ "$FREE_MB" -lt 1536 ]; then
  ui_print "! 空间不足（需 ≥1536MB），请清理后重试"
  abort "! 安装中止：存储空间不足"
fi

# ---- 默认凭据警告 ----
ui_print ""
ui_print "! 默认密码: DroidVM2026!  (dvm / root / 1Panel)"
ui_print "! 首次启动后请立即修改: 编辑 /data/local/droidvm/settings.conf"
ui_print "! 或登录虚拟机后 passwd 修改"
ui_print ""

# ---- 权限 ----
set_perm_recursive "$MODDIR" 0 0 0755 0644
set_perm "$MODDIR/bin/mgmt.sh" 0 0 0755
set_perm "$MODDIR/service.sh" 0 0 0755
set_perm "$MODDIR/customize.sh" 0 0 0755
chmod 0755 "$MODDIR/bin/mgmt.sh" 2>/dev/null

ui_print "- 安装完成"
ui_print "- 用法: su -c 'sh /data/adb/modules/DroidVM/bin/mgmt.sh start'"
ui_print "- 或重启手机自动启动（默认 AUTOSTART=1）"
ui_print "- 首次启动将自动解压 rootfs 并装配 Debian"
