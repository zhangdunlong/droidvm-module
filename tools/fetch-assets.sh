#!/usr/bin/env bash
# ============================================================
# DroidVM 资源获取脚本（开发者/构建用）
# 在一台 Linux (amd64/arm64) 主机上运行，生成模块所需的 rootfs 与磁盘模板。
# 生成的文件体积大，不进 git，作为 GitHub Release 附件发布。
# 依赖: bash, curl, tar, xz, chroot, apt
#   - amd64 宿主: 还需 qemu-user-static（跨架构 chroot）
#   - arm64 宿主: 原生 chroot，无需 qemu-user-static
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOTFS_TAR="$ROOT/rootfs/ubuntu22-qemu.tar.xz"
DISK="$ROOT/vm/debian12-cloud-arm64.qcow2"

# 可覆盖的镜像源
# Ubuntu 22.04 base rootfs（arm64）。注意：minimal cloudimg 不提供 arm64 root.tar.xz，
# 故使用 ubuntu-base 归档（含完整 apt 源，可 chroot 内 apt install）。
UBUNTU_BASE_URL="${UBUNTU_BASE_URL:-https://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/ubuntu-base-22.04.5-base-arm64.tar.gz}"
DEBIAN_IMG_URL="${DEBIAN_IMG_URL:-https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-arm64.qcow2}"

echo "[*] 工作目录: $ROOT"
echo "[*] 宿主架构: $(uname -m)"

# ---------- 1. chroot rootfs (Ubuntu 22.04 + QEMU) ----------
build_rootfs() {
  [ -f "$ROOTFS_TAR" ] && { echo "[=] rootfs 已存在，跳过: $ROOTFS_TAR"; return 0; }
  local work="$ROOT/.build/rootfs"; rm -rf "$work"; mkdir -p "$work"
  echo "[*] 下载 Ubuntu 22.04 base rootfs ..."
  curl -fL "$UBUNTU_BASE_URL" -o "$work/ubuntu.tar.gz"
  echo "[*] 解包 ..."
  tar -xzf "$work/ubuntu.tar.gz" -C "$work"

  # 同架构原生 chroot 不需要 qemu-user-static；跨架构才需要
  local host_arch; host_arch="$(uname -m)"
  if [ "$host_arch" = "aarch64" ] || [ "$host_arch" = "arm64" ]; then
    echo "[=] 宿主为 aarch64，原生 chroot，跳过 qemu-user-static"
  else
    echo "[*] 跨架构：注入 qemu-aarch64-static ..."
    cp /usr/bin/qemu-aarch64-static "$work/usr/bin/" 2>/dev/null || \
      { echo "[!] 需要 qemu-user-static (apt install qemu-user-static)"; exit 1; }
  fi

  # chroot 内需要能解析 DNS
  cp -f /etc/resolv.conf "$work/etc/resolv.conf" 2>/dev/null || true

  echo "[*] 准备 chroot 环境 ..."
  for d in proc sys dev dev/pts; do mount --bind "/$d" "$work/$d" 2>/dev/null || true; done

  echo "[*] apt 安装 QEMU + AAVMF + genisoimage (chroot 内，可能较慢) ..."
  chroot "$work" /bin/bash -c '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y --no-install-recommends \
      qemu-system-arm qemu-efi-aarch64 genisoimage cloud-init \
      openssh-server openssh-client systemd systemd-sysv sudo \
      ca-certificates curl wget
    apt-get clean
  '
  # 清理以减小体积
  rm -rf "$work"/var/lib/apt/lists/* "$work"/var/cache/apt/* "$work/usr/bin/qemu-aarch64-static"
  for d in proc sys dev/pts dev; do umount "$work/$d" 2>/dev/null || true; done

  # 校验关键文件齐备（mgmt.sh 依赖）
  for f in usr/bin/qemu-system-aarch64 usr/bin/genisoimage usr/share/AAVMF/AAVMF_CODE.fd usr/share/AAVMF/AAVMF_VARS.fd; do
    [ -e "$work/$f" ] || { echo "[!] rootfs 缺少关键文件: /$f"; exit 1; }
  done

  echo "[*] 打包 rootfs -> $ROOTFS_TAR ..."
  mkdir -p "$ROOT/rootfs"
  tar -cJf "$ROOTFS_TAR" -C "$work" .
  echo "[+] rootfs 完成: $(du -h "$ROOTFS_TAR" | cut -f1)"
}

# ---------- 2. Debian 12 cloud 磁盘模板 ----------
fetch_disk() {
  [ -f "$DISK" ] && { echo "[=] 磁盘模板已存在，跳过: $DISK"; return 0; }
  mkdir -p "$ROOT/vm"
  echo "[*] 下载 Debian 12 cloud-arm64 qcow2 ..."
  curl -fL "$DEBIAN_IMG_URL" -o "$DISK"
  # 校验 qcow2 magic
  magic=$(head -c 4 "$DISK" | od -An -tx1 | tr -d ' \n')
  [ "$magic" = "514649fb" ] || { echo "[!] 下载的磁盘不是合法 qcow2 (magic=$magic)"; exit 1; }
  echo "[+] 磁盘模板: $(du -h "$DISK" | cut -f1)"
}

build_rootfs
fetch_disk
echo "[✓] 全部资源就绪。运行 tools/build-zip.sh 打包。"
