#!/usr/bin/env bash
# ============================================================
# DroidVM 打包脚本 -> 生成可刷入 Magisk 的 zip
# 用法: bash tools/build-zip.sh [版本号]
# 产物: DroidVM-vX.Y.Z.zip （含 rootfs/vm 大文件，需先跑 fetch-assets.sh）
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VER="${1:-$(grep '^version=' module.prop | cut -d= -f2)}"
OUT="DroidVM-${VER}.zip"

echo "[*] 校验必要资源 ..."
[ -f rootfs/ubuntu22-qemu.tar.xz ] || { echo "[!] 缺少 rootfs/ubuntu22-qemu.tar.xz，先跑 tools/fetch-assets.sh"; exit 1; }
[ -f vm/debian12-cloud-arm64.qcow2 ] || { echo "[!] 缺少 vm/debian12-cloud-arm64.qcow2，先跑 tools/fetch-assets.sh"; exit 1; }

echo "[*] 打包 $OUT ..."
# 排除: 源码管理/构建中间物/大文件之外的开发目录
zip -r "$OUT" \
  module.prop settings.conf customize.sh service.sh uninstall.sh \
  bin \
  vm/templates \
  rootfs vm \
  META-INF \
  LICENSE README.md \
  -x '*.git*' 'tools/*' '.build/*' '*.DS_Store' '*.swp' || {
    echo "[!] zip 失败（Windows 无 zip？用 7z 或 git bash 自带 zip）"; exit 1;
  }

echo "[✓] 已生成: $OUT ($(du -h "$OUT" | cut -f1))"
echo "    可到 Magisk -> 本地安装 刷入。"
