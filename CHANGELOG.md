# 更新日志

## v1.0.1 — 2026-10-26

### 修复

1. **`service.sh` 阻塞 Magisk 启动流程**
   v1.0.0 是同步执行的：`sleep 45` 之后调用 `mgmt.sh start`，而后者内部还要轮询 SSH 就绪
   （最多 180 秒），最坏情况下把 late_start 阶段卡住 225 秒，拖慢同阶段其它模块。
   现改为 `( ... ) &` 后台子 shell，`service.sh` 立即返回；并改用等待
   `init.svc.bootanim=stopped` 替代固定 sleep，慢设备不会再抢跑。

2. **`settings.conf` 权限过宽（0644 → 0600）**
   该文件存放安装时随机生成的 SSH / 1Panel 明文密码。原先 `set_perm_recursive` 统一设为 0644，
   root 应用可读。现在安装阶段与 `load_settings` 运行时都会强制收紧到 0600（对旧版遗留文件同样生效）。

3. **`hostfwd` 无法指定绑定地址**
   原先一律 `hostfwd=tcp:0.0.0.0:$port`，青龙等面板对整个局域网开放。
   `VM_PORTS` 现支持三段写法 `绑定地址:宿主端口:虚拟机端口`：
   ```bash
   VM_PORTS="2222:22 127.0.0.1:5700:5700"
   ```
   即 SSH 对局域网开放、青龙只允许手机本机访问（配合隧道或反代更安全）。
   两段旧写法完全兼容，无需改配置。

### 文档

- README 顶部新增横幅，指向 QEMU-free 的 [droidvm-chroot](https://github.com/zhangdunlong/droidvm-chroot)
- README「已知问题」补充说明：TCG 无硬件加速的问题已有解法
- 新增 `CHANGELOG.md`、`.gitattributes`（强制 LF，防止 shell 脚本被转成 CRLF 后在设备上执行失败）

### 升级

模块目录直接覆盖安装即可，`/data/local/droidvm` 下的数据（rootfs / 数据盘 / settings）不受影响。
若你要用三段写法，改完 `settings.conf` 后执行：

```bash
su -c 'sh /data/adb/modules/DroidVM/bin/mgmt.sh restart'
```

---

## v1.0.0 — 2026-10-16

首个公开发布：QEMU/TCG 软件模拟 Debian 12 + Docker + 1Panel，Magisk 模块形态，
`mgmt.sh` 管理，`settings.conf` 可调内存/核数/端口映射。
