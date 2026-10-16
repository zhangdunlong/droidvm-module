#!/usr/bin/env bash
# ============================================================
# DroidVM 资源获取脚本（开发者/构建用）
# 在一台 Linux (amd64/arm64) 主机上运行，生成模块所需的 rootfs 与磁盘模板。
# 生成的文件体积大，不进 git，作为 GitHub Release 附件发布。
# 依赖: bash, curl, tar, xz, chroot, qemu-user-static, apt
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROOTFS_TAR="$ROOT/rootfs/ubuntu22-qemu.tar.xz"
DISK="$ROOT/vm/debian12-cloud-arm64.qcow2"

# 可覆盖的镜像源
UBUNTU_BASE_URL="${UBUNTU_BASE_URL:-https://cloud-images.ubuntu.com/minimal/releases/22.04/release/ubuntu-22.04-minimal-cloudimg-arm64-root.tar.xz}"
DEBIAN_IMG_URL="${DEBIAN_IMG_URL:-https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-arm64.qcow2}"

echo "[*] 工作目录: $ROOT"

# ---------- 1. chroot rootfs (Ubuntu 22.04 + QEMU) ----------
build_rootfs() {
  [ -f "$ROOTFS_TAR" ] && { echo "[=] rootfs 已存在，跳过: $ROOTFS_TAR"; return 0; }
  local work="$ROOT/.build/rootfs"; rm -rf "$work"; mkdir -p "$work"
  echo "[*] 下载 Ubuntu 22.04 base rootfs ..."
  curl -fL "$UBUNTU_BASE_URL" -o "$work/ubuntu.tar.xz"
  echo "[*] 解包 ..."
  tar -xJf "$work/ubuntu.tar.xz" -C "$work"
  echo "[*] 准备 chroot 环境 ..."
  cp /usr/bin/qemu-aarch64-static "$work/usr/bin/" 2>/dev/null || \
    { echo "[!] 需要 qemu-user-static (apt install qemu-user-static)"; exit 1; }
  for d in proc sys dev dev/pts; do mount --bind "/$d" "$work/$d" 2>/dev/null || true; done
  echo "[*] apt 安装 QEMU + AAVMF + genisoimage (chroot 内，可能较慢) ..."
  chroot "$work" /bin/bash -c '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y --no-install-recommends \
      qemu-system-arm qemu-efi genisoimage cloud-init openssh-server \
      systemd systemd-sysv sudo ca-certificates curl wget
  '
  # 清理以减小体积
  chroot "$work" apt-get clean
  rm -rf "$work/var/lib/apt/lists/*" "$work/usr/bin/qemu-aarch64-static"
  for d in proc sys dev/pts dev; do umount "$work/$d" 2>/dev/null || true; done
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
  echo "[+] 磁盘模板: $(du -h "$DISK" | cut -f1)"
}

build_rootfs
fetch_disk
echo "[✓] 全部资源就绪。运行 tools/build-zip.sh 打包。"
