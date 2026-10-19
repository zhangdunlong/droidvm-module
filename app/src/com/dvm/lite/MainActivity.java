package com.dvm.lite;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.method.ScrollingMovementMethod;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.io.BufferedReader;
import java.io.InputStreamReader;

/**
 * DVM Lite —— 本机 agent2api / 服务管理面板
 * 所有操作通过 su 调用 /data/adb/dvm-lite/mgmt.sh，不触碰代理模块。
 */
public class MainActivity extends Activity {

    private static final String MGMT = "/data/adb/dvm-lite/mgmt.sh";
    /** 移动端适配面板（agent2api-mobile.html，PWA/深色/安全区） */
    private static final String API_BASE = "http://127.0.0.1:3065";
    private static final String API_PANEL = API_BASE + "/mobile.html";
    /** 本地面板登录凭据（首次部署时自行修改） */
    private static final String API_USER = "dvmadmin";
    private static final String API_PASS = "CHANGE_ME_ON_DEPLOY";
    /**
     * 远程面板（可选）——若青龙/mi-paiai 等容器跑在另一台机器上，填局域网地址；
     * 不用远程面板可留空字符串，按钮会提示未配置。
     */
    private static final String QL_REMOTE = "";   // 例: "http://192.168.x.x:5700"
    private static final String MP_REMOTE = "";   // 例: "http://192.168.x.x:36592"
    /** 远程面板凭据（不用远程面板可忽略） */
    private static final String QL_USER = "admin";
    private static final String QL_PASS = "CHANGE_ME_ON_DEPLOY";
    private static final String MP_USER = "admin";
    private static final String MP_PASS = "CHANGE_ME_ON_DEPLOY";

    /** 兼容 Magisk / KernelSU / APatch 的 su 路径（精简，避免多次授权弹窗） */
    private static final String[] SU_CANDIDATES = {
            "/debug_ramdisk/su",      // Magisk (一加 13 实测)
            "/system/bin/su",
            "/data/adb/ksu/bin/su",
            "/data/adb/ap/bin/su",
    };

    private String suPath = null;

    /**
     * 直接返回 su 路径，不做运行探测。
     * 探测会触发 Magisk 授权弹窗，而弹窗在后台不显示，导致 waitFor() 永久阻塞。
     * 一加 13（Magisk 30700）实测路径为 /debug_ramdisk/su。
     */
    private String findSu() {
        if (suPath != null) return suPath;
        suPath = "/debug_ramdisk/su";
        return suPath;
    }

    private final Handler ui = new Handler(Looper.getMainLooper());
    private TextView tvSummary;
    private TextView tvOutput;
    private Button btnToggle;
    private boolean agentRunning = false;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.parseColor("#12141A"));
        int pad = dp(12);
        root.setPadding(pad, pad, pad, pad);

        // ---------- 标题 ----------
        TextView title = new TextView(this);
        title.setText("DVM Lite");
        title.setTextColor(Color.parseColor("#E8EAFF"));
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 22);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        root.addView(title);

        TextView subtitle = new TextView(this);
        subtitle.setText("本机 agent2api 管理 · 零模拟 chroot");
        subtitle.setTextColor(Color.parseColor("#7A8099"));
        subtitle.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        subtitle.setPadding(0, dp(2), 0, dp(10));
        root.addView(subtitle);

        // ---------- 状态摘要卡 ----------
        tvSummary = new TextView(this);
        tvSummary.setText("加载中…");
        tvSummary.setTextColor(Color.parseColor("#A8B0CC"));
        tvSummary.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        tvSummary.setTypeface(Typeface.MONOSPACE);
        tvSummary.setBackgroundColor(Color.parseColor("#1C1F2A"));
        tvSummary.setPadding(dp(12), dp(10), dp(12), dp(10));
        root.addView(tvSummary, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        addSpacer(root, 10);

        // ---------- 按钮区（两行） ----------
        LinearLayout row1 = makeRow();
        row1.addView(makeButton("刷新状态", "#4A7CFF", v -> runCmd("status", true)));
        row1.addView(makeButton("网络诊断", "#2FA37A", v -> runCmd("net", false)));
        root.addView(row1);

        LinearLayout row2 = makeRow();
        btnToggle = makeButton("停止服务", "#C25A4A", v -> toggleAgent());
        row2.addView(btnToggle);
        row2.addView(makeButton("查看日志", "#5A5F78", v -> runCmd("logs 60", false)));
        root.addView(row2);

        LinearLayout row3 = makeRow();
        row3.addView(makeButton("重启 API", "#8A6BD1", v -> runCmd("restart", true)));
        row3.addView(makeButton("API 面板·移动版", "#3A7FAD",
                v -> openWebPanel("agent2api 面板（移动版）", API_PANEL,
                        API_USER, API_PASS)));
        root.addView(row3);

        LinearLayout row4 = makeRow();
        row4.addView(makeButton("API 面板·原版", "#5A6B8C",
                v -> openWebPanel("agent2api 面板（原版桌面）", API_BASE + "/",
                        API_USER, API_PASS)));
        row4.addView(makeButton("青龙面板", "#D17A3A",
                v -> openWebPanel("青龙面板", QL_REMOTE,
                        QL_USER, QL_PASS)));
        root.addView(row4);

        LinearLayout row5 = makeRow();
        row5.addView(makeButton("mi-paiai", "#3AA0AD",
                v -> openWebPanel("mi-paiai 面板", MP_REMOTE,
                        MP_USER, MP_PASS)));
        row5.addView(makeButton("容器管理", "#6B5BB5",
                v -> startActivity(new Intent(MainActivity.this, ContainerActivity.class))));
        root.addView(row5);

        LinearLayout row6 = makeRow();
        row6.addView(makeButton("青龙抓取（登录网站 → 写入 Cookie）", "#C25A9A",
                v -> startActivity(new Intent(MainActivity.this, GrabActivity.class))));
        root.addView(row6);

        addSpacer(root, 10);

        // ---------- 输出区 ----------
        tvOutput = new TextView(this);
        tvOutput.setText("点击上方按钮开始检测。\n\n提示：首次使用需在 Magisk 中授权 su。");
        tvOutput.setTextColor(Color.parseColor("#8A90A8"));
        tvOutput.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11);
        tvOutput.setTypeface(Typeface.MONOSPACE);
        tvOutput.setTextIsSelectable(true);
        tvOutput.setMovementMethod(new ScrollingMovementMethod());
        tvOutput.setPadding(dp(10), dp(10), dp(10), dp(10));
        tvOutput.setBackgroundColor(Color.parseColor("#0C0E13"));

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.addView(tvOutput);

        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f);
        root.addView(scroll, lp);

        setContentView(root);

        // 进入即刷新
        runCmd("status", true);
    }

    // ================= UI 辅助 =================

    private int dp(int v) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v,
                getResources().getDisplayMetrics());
    }

    private void addSpacer(LinearLayout parent, int h) {
        View v = new View(this);
        parent.addView(v, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(h)));
    }

    private LinearLayout makeRow() {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.bottomMargin = dp(8);
        row.setLayoutParams(lp);
        return row;
    }

    private interface ClickAction {
        void onClick(View v);
    }

    private Button makeButton(String text, String color, ClickAction action) {
        Button b = new Button(this);
        b.setText(text);
        b.setAllCaps(false);
        b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        b.setTextColor(Color.WHITE);
        b.setBackgroundColor(Color.parseColor(color));
        b.setPadding(dp(4), dp(10), dp(4), dp(10));
        b.setOnClickListener(action::onClick);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        lp.rightMargin = dp(8);
        b.setLayoutParams(lp);
        return b;
    }

    // ================= 命令执行 =================

    private void runCmd(final String args, final boolean refreshSummary) {
        setOutput("执行中: mgmt.sh " + args + " …");
        new Thread(() -> {
            final String out = exec("sh " + MGMT + " " + args);
            ui.post(() -> {
                setOutput(out);
                if (refreshSummary) updateSummary(out);
            });
        }).start();
    }

    private String exec(String cmd) {
        StringBuilder sb = new StringBuilder();
        Process p = null;
        try {
            String su = findSu();
            p = Runtime.getRuntime().exec(new String[]{su, "-c", cmd});
            BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()));
            String line;
            while ((line = r.readLine()) != null) {
                sb.append(line).append('\n');
            }
            BufferedReader er = new BufferedReader(new InputStreamReader(p.getErrorStream()));
            String el;
            boolean hasErr = false;
            while ((el = er.readLine()) != null) {
                if (!hasErr) {
                    sb.append("\n[stderr]\n");
                    hasErr = true;
                }
                sb.append(el).append('\n');
            }
            p.waitFor();
        } catch (Exception e) {
            sb.append("执行失败: ").append(e.getMessage())
              .append("\n\n请确认 Magisk 已授予 root 权限。");
        } finally {
            if (p != null) p.destroy();
        }
        return sb.toString().trim();
    }

    private void setOutput(final String text) {
        tvOutput.post(() -> {
            tvOutput.setText(text);
            tvOutput.scrollTo(0, 0);
        });
    }

    /** 从 status 输出里摘出关键行 */
    private void updateSummary(String out) {
        if (out == null) return;
        String ip = "-", mem = "-", mod = "-", a2a = "UNKNOWN";
        for (String line : out.split("\n")) {
            line = line.trim();
            if (line.startsWith("LAN_IP=")) ip = line.substring(7);
            else if (line.startsWith("MEM=")) mem = line.substring(4);
            else if (line.equals("ENABLED") || line.equals("DISABLED") || line.equals("NOT_INSTALLED")) mod = line;
            else if (line.startsWith("agent2api|")) {
                String[] p = line.split("\\|");
                if (p.length >= 2) a2a = p[1];
            }
        }
        agentRunning = "RUNNING".equals(a2a);

        final String s = "LAN IP   " + ip + "\n"
                + "内存      " + mem + "\n"
                + "模块      " + mod + "\n"
                + "agent2api " + a2a;
        tvSummary.post(() -> tvSummary.setText(s));

        btnToggle.post(() -> {
            if (agentRunning) {
                btnToggle.setText("停止服务");
                btnToggle.setBackgroundColor(Color.parseColor("#C25A4A"));
            } else {
                btnToggle.setText("启动服务");
                btnToggle.setBackgroundColor(Color.parseColor("#2FA37A"));
            }
        });
    }

    private void toggleAgent() {
        runCmd(agentRunning ? "a2a stop" : "a2a start", true);
    }

    /** 面板入口：弹窗显示可复制的地址与账号密码，再选「内置」或「浏览器」 */
    private void openWebPanel(String title, String url, String account, String password) {
        if (url == null || url.trim().isEmpty()) {
            Toast.makeText(this, title + " 未配置：请在源码中填写地址后重新构建",
                    Toast.LENGTH_LONG).show();
            return;
        }
        String msg = "地址：\n" + url + "\n\n账号：" + account + "\n密码：" + password;

        TextView tv = new TextView(this);
        tv.setText(msg);
        tv.setTextIsSelectable(true);   // 长按即可选择复制
        tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        tv.setTextColor(Color.parseColor("#E8EAFF"));
        tv.setPadding(dp(20), dp(12), dp(20), dp(12));

        new AlertDialog.Builder(this)
                .setTitle(title)
                .setView(tv)
                .setPositiveButton("内置打开", (d, w) -> showWebView(title, url))
                .setNegativeButton("浏览器打开", (d, w) -> openInBrowser(url))
                .setNeutralButton("复制凭据", (d, w) -> {
                    android.content.ClipboardManager cm =
                            (android.content.ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
                    cm.setPrimaryClip(android.content.ClipData.newPlainText(
                            title, "地址: " + url + "\n账号: " + account + "\n密码: " + password));
                    Toast.makeText(this, "已复制到剪贴板", Toast.LENGTH_SHORT).show();
                })
                .show();
    }

    /** 内置 WebView 打开 */
    private void showWebView(String title, String url) {
        try {
            android.webkit.WebView wv = new android.webkit.WebView(this);
            wv.getSettings().setJavaScriptEnabled(true);
            wv.getSettings().setDomStorageEnabled(true);
            wv.getSettings().setLoadWithOverviewMode(true);
            wv.getSettings().setUseWideViewPort(true);
            wv.getSettings().setBuiltInZoomControls(true);
            wv.getSettings().setDisplayZoomControls(false);
            wv.setWebViewClient(new android.webkit.WebViewClient());
            wv.loadUrl(url);

            new AlertDialog.Builder(this)
                    .setTitle(title)
                    .setView(wv)
                    .setPositiveButton("关闭", (d, w) -> d.dismiss())
                    .setNegativeButton("刷新", (d, w) -> wv.reload())
                    .show();
        } catch (Exception e) {
            Toast.makeText(this, "打开失败: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    /** 用系统浏览器打开 */
    private void openInBrowser(String url) {
        try {
            Intent i = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(i);
        } catch (Exception e) {
            Toast.makeText(this, "无法打开浏览器: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
    }
}
