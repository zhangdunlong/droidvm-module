#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
DroidVM 打包脚本（跨平台，无需 zip/7z）
用法: python tools/build-zip.py [版本号]
产物: DroidVM-vX.Y.Z.zip  —— 可直接在 Magisk 中「本地安装」
前置: 已由 fetch-assets（或 K40 侧脚本）生成
      rootfs/ubuntu22-qemu.tar.xz 与 vm/debian12-cloud-arm64.qcow2
"""
import os
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)


def read_version():
    try:
        with open("module.prop", encoding="utf-8") as f:
            for line in f:
                if line.startswith("version="):
                    return line.split("=", 1)[1].strip()
    except OSError:
        pass
    return "v0.0.0"


def check_assets():
    missing = []
    for p in ("rootfs/ubuntu22-qemu.tar.xz", "vm/debian12-cloud-arm64.qcow2"):
        if not os.path.isfile(p):
            missing.append(p)
    if missing:
        print("[!] 缺少资源，先跑 tools/fetch-assets.sh（或 K40 侧打包脚本）:")
        for m in missing:
            print("    - " + m)
        sys.exit(1)


# 要打进 zip 的顶层条目
INCLUDE = [
    "module.prop", "settings.conf", "customize.sh", "service.sh", "uninstall.sh",
    "bin", "vm", "rootfs", "META-INF", "LICENSE", "README.md",
]
# 排除规则（相对仓库根的路径片段）
EXCLUDE_PREFIX = ("tools/", ".build/", ".git/", ".github/")
EXCLUDE_NAME = {".DS_Store", "Thumbs.db"}


def iter_files():
    for entry in INCLUDE:
        if not os.path.exists(entry):
            print("[!] 缺少条目: " + entry)
            sys.exit(1)
        if os.path.isfile(entry):
            yield entry
            continue
        for dirpath, dirnames, filenames in os.walk(entry):
            # 就地裁剪，避免进入排除目录
            dirnames[:] = [d for d in dirnames if d != ".git"]
            for fn in filenames:
                full = os.path.join(dirpath, fn).replace(os.sep, "/")
                if full.startswith(EXCLUDE_PREFIX) or fn in EXCLUDE_NAME:
                    continue
                if fn.endswith((".swp", ".pyc")):
                    continue
                yield full


def main():
    ver = sys.argv[1] if len(sys.argv) > 1 else read_version()
    out = "DroidVM-%s.zip" % ver
    check_assets()

    print("[*] 打包 %s ..." % out)
    files = sorted(set(iter_files()))
    total = len(files)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for i, path in enumerate(files, 1):
            # 大文件已压缩（.xz/.qcow2），用 store 省时间
            store = path.endswith((".xz", ".qcow2", ".gz", ".zip"))
            zi = zipfile.ZipInfo.from_file(path, arcname=path)
            zi.compress_type = zipfile.ZIP_STORED if store else zipfile.ZIP_DEFLATED
            with open(path, "rb") as src, z.open(zi, "w") as dst:
                while True:
                    chunk = src.read(1024 * 1024)
                    if not chunk:
                        break
                    dst.write(chunk)
            if i % 20 == 0 or i == total:
                print("    [%d/%d] %s" % (i, total, path))

    size_mb = os.path.getsize(out) / 1024 / 1024
    print("[✓] 已生成: %s (%.1f MB, %d 个条目)" % (out, size_mb, total))
    print("    可到 Magisk -> 模块 -> 本地安装 刷入。")


if __name__ == "__main__":
    main()
