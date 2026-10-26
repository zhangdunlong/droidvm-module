# DroidVM for Magisk

> ## ⚠️ 这是 QEMU 软件模拟版本，已有更快的继任者
>
> **[droidvm-chroot](https://github.com/zhangdunlong/droidvm-chroot)** 不再使用 QEMU 指令翻译，
> 直接把 Ubuntu rootfs 作为 chroot 跑在 Android 内核上。同一套服务，实测差异：
>
> | | 本项目（QEMU/TCG） | droidvm-chroot |
> |---|---|---|
> | 待机 CPU | ~196% | 0–5% |
> | 机身温度 | 78.7°C | 32.5°C |
> | 青龙首屏 | 2–8 秒 | 0.12 秒 |
> | 首次可服务 | 20–120 分钟 | 5–10 分钟 |
> | 磁盘 | rootfs 4.9G + qcow2 2.3G | 4.9G |
>
> **怎么选**：只跑自建服务 → 用 `droidvm-chroot`；
> 需要完整虚拟机隔离、或依赖现成 Docker 镜像 → 留在本项目。

把一台**完整的 Debian 12 虚拟机**（QEMU/TCG 软解）塞进任意已 Root 的安卓手机。
开机自动启动，内置 **Docker + 1Panel**，可直接跑青龙面板、AList、Agent2API 等容器服务。

> 本项目是把「K40 上 Magisk + QEMU + Debian + Docker + 青龙」这套自用方案，
> 抽成**通用面具模块**并脱敏开源，让其他手机也能一键拥有「手机里的服务器」。

---

## 架构

```
┌─────────────────────────────────────────────────────────────┐
│  安卓手机 (已 Root, Magisk/KernelSU/APatch)                    │
│                                                               │
│  /data/adb/modules/DroidVM/        ← 模块（脚本/模板/资源）    │
│  /data/local/droidvm/              ← 运行数据（rootfs/数据盘） │
│                                                               │
│  chroot 环境 (Ubuntu 22.04 arm64)                             │
│   └─ 仅用来承载 QEMU 二进制 + AAVMF(UEFI) + genisoimage       │
│        │  QEMU-system-aarch64  -machine virt -cpu max         │
│        │  -accel tcg,thread=multi  (纯软件虚拟化，无 KVM)     │
│        ▼                                                       │
│  访客虚拟机 (Debian 12 cloud-arm64)                           │
│   ├─ Docker (青龙 / AList / Agent2API ...)                    │
│   ├─ 1Panel  (面板 :10086)                                   │
│   └─ OpenSSH (:22)                                            │
│        │  hostfwd 端口映射                                      │
│        ▼                                                       │
│  安卓侧端口 (2222=SSH 10086=1Panel 5700=青龙 ...)             │
└─────────────────────────────────────────────────────────────┘
```

- **chroot 只当「QEMU 宿主」**：Android 没有 QEMU + UEFI 固件，所以用 Ubuntu 22.04 的 chroot 提供它们。
- **访客才是真正干活的 Debian 12**：cloud-init 首次启动自动装好 Docker/1Panel/SSH。
- **手机 ↔ 虚拟机** 通过 QEMU `hostfwd` 把访客端口映射到安卓侧，局域网其他设备也能访问。

---

## 兼容性

| 项 | 要求 |
|---|---|
| 架构 | **仅 arm64 / aarch64**（手机 SoC 基本都是） |
| 系统 | Android 10+ |
| Root | Magisk 24+（KernelSU / APatch 需自行改 `customize.sh` 的模块路径） |
| 内存 | 建议 ≥ 6GB；默认分给 VM 4GB（可在 `settings.conf` 调） |
| 存储 | 空机约 8GB 稀疏磁盘，建议预留 ≥ 16GB |

> ⚠️ 手机 SoC 一般**不开放 KVM**，所以 QEMU 走 **TCG 纯软解**，CPU 占用偏高、启动较慢（约 40–120 秒），
> 但兼容性好、任意机型可用。

---

## 目录结构（模块内）

```
DroidVM/
├── module.prop                 # 模块元数据
├── settings.conf               # 用户可改配置（内存/端口/凭据，安装时随机化）
├── customize.sh                # 刷入时执行（权限/环境/随机凭据生成）
├── service.sh                  # 开机自启入口（晚于 boot_completed）
├── uninstall.sh               # 卸载清理
├── bin/
│   └── mgmt.sh                 # 运行期管理脚本（start/stop/status/...）
├── app/                        # 管理 App（DVM Lite）源码，见 app/README.md
│   ├── AndroidManifest.xml
│   ├── build.py                # 一条命令构建签名 APK
│   ├── mgmt.sh                 # App 后端脚本（推到 /data/adb/dvm-lite/）
│   ├── res/values/strings.xml
│   └── src/com/dvm/lite/       # MainActivity / ContainerActivity / GrabActivity
├── vm/
│   └── templates/
│       ├── user-data           # cloud-init 模板（脱敏，凭据占位符）
│       └── meta-data
├── rootfs/                     # (Release 附带) Ubuntu 22.04 + QEMU chroot 模板
│   └── ubuntu22-qemu.tar.xz
└── vm/                         # (Release 附带) Debian 12 cloud 磁盘模板
    └── debian12-cloud-arm64.qcow2
```

> 源码仓库**不含** `rootfs/*.tar.xz` 与 `vm/*.qcow2` 两个大文件（见 `.gitignore`）。
> 发布时由 `tools/fetch-assets.sh` 生成、作为 **GitHub Release 附件** 提供。

---

## 安装

1. 到 [Releases](../../releases) 下载 `DroidVM-vX.Y.Z.zip`（含 rootfs 与磁盘模板）。
2. Magisk → 模块 → 本地安装 → 选该 zip → 重启。
   - **安装时 `customize.sh` 会为本机生成随机密码**（dvm/root/1Panel 三处），请从安装日志抄走。
3. 重启后约 45 秒，模块自动 `start`：
   - 首次会解压 rootfs（1–2 分钟）、从模板建数据盘、生成 cloud-init seed。
   - **装配时间取决于机型**：旗舰机 TCG 约 20–40 分钟；中端机（如 SD730G）实测 **1–2 小时**（apt 在纯软解下极慢）。
   - 判断进度：`su -c 'ssh -p 2222 dvm@127.0.0.1'` 能登录且 `/var/lib/dvm-setup-finished` 出现即装配完成。
4. 浏览器打开 **`http://<手机局域网IP>:10086/<安装日志里的随机入口>`** 即可用 1Panel。
   SSH：`ssh -p 2222 dvm@<手机局域网IP>`（密码同安装日志）

> 🔴 **首次启动后请立即修改密码！** 随机密码在 `settings.conf` 里可改，改后 `mgmt.sh restart` 生效；
> VM 内也可 `passwd` 修改。模块分发**不含任何默认密码**。

---

## 配置（`settings.conf`）

| 键 | 默认 | 说明 |
|---|---|---|
| `VM_MEM` | `4096` | VM 内存(MB)，或填 `auto` 按手机内存 40% 自适应 |
| `VM_SMP` | `4` | VM CPU 核数（建议物理核数一半以下） |
| `VM_PORTS` | `2222:22 10086:10086 5700:5700 3065:3065 5244:5244` | 宿主:访客 端口映射 |
| `AUTOSTART` | `1` | 1=开机自启 |
| `BOOT_DELAY` | `45` | 开机后延迟启动秒数 |
| `DVM_PASSWORD` / `PANEL_*` | — | 首次装配凭据（请改） |

改完执行：`su -c 'sh /data/adb/modules/DroidVM/bin/mgmt.sh restart'`

---

## 管理（`mgmt.sh`）

```bash
su -c 'sh /data/adb/modules/DroidVM/bin/mgmt.sh {start|stop|restart|status|ssh|docker|log|reseed}'
```

| 子命令 | 作用 |
|---|---|
| `start` | 启动（首次自动解压 rootfs / 建盘 / 生成 seed） |
| `stop` / `restart` | 停止 / 重启 |
| `status` | 宿主机 + 访客全量状态（服务/容器/资源） |
| `ssh` | 进入访客 shell |
| `docker <args>` | 访客内执行 docker，如 `docker ps -a` |
| `log` | 看 QEMU 日志 |
| `reseed` | 按当前 `settings.conf` 重新生成 cloud-init seed |

---

## 资源占用与调优

- **空机磁盘**：qcow2 稀疏，初始 ~325MB，随使用增长（建议上限 60GB 内）。
- **运行时内存**：固定吃 `VM_MEM`，别设超过手机内存 50%。
- **CPU**：TCG 软解，编译/压测时手机会明显发热；建议 `VM_SMP` 别拉满。
- **青龙 OCR 等 aarch64 特例**：Alpine/Debian arm64 上 `onnxruntime` 等 wheel 不全，
  需用系统包（如 `apk add py3-onnxruntime`）或源码装，见青龙签到脚本注释。

---

## 管理 App（DVM Lite，随仓库开源）

`app/` 目录是配套的安卓管理端，纯 Java 零依赖：

| 功能 | 说明 |
|---|---|
| 服务管理 | agent2api 启停/重启、状态卡片（IP/内存/模块/服务） |
| 面板直达 | agent2api 移动版 + 原版、青龙、mi-paiai，凭据弹窗可复制 |
| 青龙抓取 | 内置 WebView 登录站点 → 一键抓 Cookie（含 HttpOnly）写入青龙 env |
| 容器管理 | 经 SSH 远程控制另一台机器上的 Docker 容器（启/停/重启） |

```bash
cd app && python build.py    # 产物 build/dvm-lite.apk（JDK17 + SDK34）
```

详见 [app/README.md](./app/README.md)。**部署前需把源码里的占位符改成你的环境**（地址/凭据）。

---

## 安全与脱敏说明

发布内容经过以下脱敏处理：

| 项 | 处理 |
|---|---|
| SSH 主机密钥 | rootfs 内 `etc/ssh/ssh_host_*` 已删除；VM 首启由 cloud-init `ssh-keygen -A` 重建（`tools/fetch-assets.sh` 同步含此清理） |
| 默认密码 | 无任何硬编码默认密码；`customize.sh` 安装时随机生成并回写 `settings.conf` |
| 构建日志 | apt/dpkg 日志已从 rootfs 清除 |
| App 凭据 | 源码内网地址/密码全部改为占位符 |
| 数据资产 | qcow2 为 Debian 官方 cloud 镜像原版（未启动过，无个人数据） |

---

## 构建（开发者）

需要一台 Linux（amd64/arm64 均可，需 `qemu-user-static` + `chroot` + `apt`）：

```bash
# 1. 拉取并构建 chroot rootfs（Ubuntu 22.04 + QEMU + AAVMF + genisoimage）
bash tools/fetch-assets.sh
# 2. 打包成可刷入的 zip
bash tools/build-zip.sh
# 产物: DroidVM-vX.Y.Z.zip
```

`fetch-assets.sh` 会：下载 Ubuntu 22.04 base tarball → chroot 内 `apt install qemu-system-arm qemu-efi genisoimage` →
打包成 `rootfs/ubuntu22-qemu.tar.xz`；并下载 Debian 12 cloud-arm64 qcow2 到 `vm/`。

---

## 已知问题 / 注意事项

- 仅 TCG 软解，无硬件加速；老旧/低内存机型体验差。
  > 这个问题在 [droidvm-chroot](https://github.com/zhangdunlong/droidvm-chroot) 中已不存在——该项目改用 chroot 原生执行，没有指令翻译开销。
- 部分机型 SELinux 策略会拦 `mount --bind`，需 `magiskpolicy` 放行或临时 `setenforce 0` 验证。
- 数据盘在 `/data/local/droidvm/vm/`，重刷模块**不会**删数据；卸载脚本默认只移除模块，保留数据盘（加 `-f` 才清）。
- 本项目仅供学习研究，请遵守当地法律法规与厂商条款。

---

## 开源协议

[GPL-3.0](./LICENSE) © zhangdunlong
