# DVM Lite —— DroidVM 管理 App

安卓管理端：服务启停、状态监控、面板直达（agent2api 移动版/原版、青龙、mi-paiai）、
青龙 Cookie 抓取写入、K40 容器远程开关。

纯 Java 无第三方依赖，`build.py` 用 Android SDK（aapt2 + d8 + apksigner）
一条命令出签名 APK。

## 构建

依赖：JDK 17 + Android SDK（platform android-34 + build-tools 34.0.0）。

```bash
# 修改 build.py 顶部的 SDK/JDK 路径后执行
python build.py
# 产物: build/dvm-lite.apk（v2+v3 签名）
```

安装：`adb install -r build/dvm-lite.apk`，首次使用需在 Magisk 弹窗点「允许」。

## 部署后端脚本

App 所有 root 操作通过 `mgmt.sh` 完成，推到手机：

```bash
adb push mgmt.sh /data/local/tmp/
adb shell "su -c 'mkdir -p /data/adb/dvm-lite && cp /data/local/tmp/mgmt.sh /data/adb/dvm-lite/ && chmod 755 /data/adb/dvm-lite/mgmt.sh'"
```

`mgmt.sh` 命令：`status` / `net` / `logs` / `a2a {start|stop|restart}` /
`containers`（远程容器列表）/ `ctl <name> <start|stop|restart>`（远程容器控制）。

## 部署前配置（重要）

源码中以下常量是**占位符**，部署到你的环境前必须改：

| 文件 | 常量 | 说明 |
|---|---|---|
| `MainActivity.java` | `API_USER` / `API_PASS` | agent2api 面板登录凭据 |
| `MainActivity.java` | `QL_REMOTE` / `MP_REMOTE` | 青龙 / mi-paiai 远程地址，留空则不显示对应按钮 |
| `MainActivity.java` | `QL_USER`/`QL_PASS`/`MP_USER`/`MP_PASS` | 远程面板凭据 |
| `GrabActivity.java` | `QL_BASE` / `QL_USER` / `QL_PASS` | 青龙 API 地址与凭据 |
| `mgmt.sh` | `K40_HOST` | 远程容器宿主 IP，留空则容器管理不可用 |

## su 路径说明

`MainActivity.findSu()` 硬编码 `/debug_ramdisk/su`（Magisk 实测路径）。
**不要改成「运行探测」**：探测会触发 Magisk 授权弹窗，弹窗在后台不显示时
`waitFor()` 永久阻塞导致 App 卡死。KernelSU/APatch 设备请自行改为对应路径。

## 已知设计取舍

- **QEMU/TCG 下 `docker export` 速度约 150KB/s**（672MB 需 80 分钟），
  所以大容器不迁移，App 用「局域网直连远程面板」方案替代。
- 青龙抓取页用 Android `CookieManager.getCookie` 读全量 Cookie
  （含 HttpOnly），与 PC 扩展 `chrome.cookies.getAll` 等价。
