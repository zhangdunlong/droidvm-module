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
# 三个坑（真我 RMX1971 实测）：
# 1. 部分机型 df 设备名过长，数字列会折到下一行，不能假定 NR==2
# 2. 折行后字段整体左移，Available 不是固定的 $4
# 3. 表头 "Use%" 也含 %，会抢先匹配——必须匹配「数字%」取其前一列
FREE_MB=$(df /data 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+%$/) {print int($(i-1)/1024); exit}}')
[ -z "$FREE_MB" ] && FREE_MB=99999
ui_print "- /data/local 可用空间: ${FREE_MB}MB"
if [ "$FREE_MB" -lt 1536 ]; then
  ui_print "! 空间不足（需 ≥1536MB），请清理后重试"
  abort "! 安装中止：存储空间不足"
fi

# ---- 首次装配凭据：随机生成（避免公开默认密码） ----
# busybox 环境：head/base64/tr 均可用；按字段名锚定回写 settings.conf
gen_pass() {
    head -c 16 /dev/urandom | base64 | tr -d '/+=' | head -c 16
}
GEN_DVM_PASS=$(gen_pass)
GEN_PANEL_PASS=$(gen_pass)
GEN_ENTRANCE=$(gen_pass | tr 'A-Z' 'a-z')
sed -i "s|^DVM_PASSWORD=.*|DVM_PASSWORD='$GEN_DVM_PASS'|" "$MODPATH/settings.conf" 2>/dev/null
sed -i "s|^PANEL_PASSWORD=.*|PANEL_PASSWORD='$GEN_PANEL_PASS'|" "$MODPATH/settings.conf" 2>/dev/null
sed -i "s|^PANEL_ENTRANCE=.*|PANEL_ENTRANCE='$GEN_ENTRANCE'|" "$MODPATH/settings.conf" 2>/dev/null

# 回写校验（失败必须可见，不能静默——$MODPATH 拼错曾导致此坑）
if grep -q "__AUTO_GENERATED__" "$MODPATH/settings.conf" 2>/dev/null; then
  ui_print "! 警告：随机密码回写失败，请手动编辑 $MODPATH/settings.conf"
  ui_print "!   SSH/root: $GEN_DVM_PASS  1Panel: $GEN_PANEL_PASS  入口: $GEN_ENTRANCE"
fi

ui_print ""
ui_print "! 已为本机生成随机凭据（请抄走，重启后 VM 首次启动生效）:"
ui_print "!   SSH/root 密码 : $GEN_DVM_PASS"
ui_print "!   1Panel 密码   : $GEN_PANEL_PASS"
ui_print "!   1Panel 入口   : $GEN_ENTRANCE"
ui_print "! 首次启动后请立即修改: 编辑 /data/adb/modules/DroidVM/settings.conf"
ui_print "! 或登录虚拟机后 passwd 修改"
ui_print ""

# ---- 权限 ----
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/bin/mgmt.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/customize.sh" 0 0 0755
chmod 0755 "$MODPATH/bin/mgmt.sh" 2>/dev/null

ui_print "- 安装完成"
ui_print "- 用法: su -c 'sh /data/adb/modules/DroidVM/bin/mgmt.sh start'"
ui_print "- 或重启手机自动启动（默认 AUTOSTART=1）"
ui_print "- 首次启动将自动解压 rootfs 并装配 Debian"
