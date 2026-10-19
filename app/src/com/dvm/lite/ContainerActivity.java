package com.dvm.lite;

import android.app.Activity;
import android.app.AlertDialog;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.List;

/**
 * 容器管理：列出 K40 上的 Docker 容器，支持启动/停止/重启。
 * 后端：su -c 'sh /data/adb/dvm-lite/mgmt.sh containers|ctl'
 */
public class ContainerActivity extends Activity {

    private static final String MGMT = "/data/adb/dvm-lite/mgmt.sh";

    private final Handler ui = new Handler(Looper.getMainLooper());
    private LinearLayout listBox;
    private TextView tvInfo;

    private static class Container {
        String name;
        String status;
        String image;
        boolean running;
    }

    private final List<Container> containers = new ArrayList<>();

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.parseColor("#12141A"));
        int pad = dp(12);
        root.setPadding(pad, pad, pad, pad);

        // 标题行
        LinearLayout head = new LinearLayout(this);
        head.setOrientation(LinearLayout.HORIZONTAL);

        TextView title = new TextView(this);
        title.setText("容器管理（K40）");
        title.setTextColor(Color.parseColor("#E8EAFF"));
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 20);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        LinearLayout.LayoutParams tlp = new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        head.addView(title, tlp);

        Button btnRefresh = makeBtn("刷新", "#4A7CFF");
        btnRefresh.setOnClickListener(v -> loadContainers());
        head.addView(btnRefresh);

        root.addView(head);

        tvInfo = new TextView(this);
        tvInfo.setText("正在获取容器列表…");
        tvInfo.setTextColor(Color.parseColor("#7A8099"));
        tvInfo.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        tvInfo.setPadding(0, dp(4), 0, dp(8));
        root.addView(tvInfo);

        // 容器列表（可滚动）
        listBox = new LinearLayout(this);
        listBox.setOrientation(LinearLayout.VERTICAL);

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.addView(listBox);
        root.addView(scroll, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        setContentView(root);
        loadContainers();
    }

    // ================= 数据 =================

    private void loadContainers() {
        tvInfo.setText("正在获取容器列表…");
        new Thread(() -> {
            final String out = exec("sh " + MGMT + " containers");
            ui.post(() -> renderContainers(out));
        }).start();
    }

    private void renderContainers(String out) {
        containers.clear();
        listBox.removeAllViews();

        if (out == null || !out.contains("###CONTAINERS###")) {
            tvInfo.setText("获取失败：" + (out == null ? "无输出" : out.trim()));
            return;
        }

        for (String line : out.split("\n")) {
            line = line.trim();
            if (line.isEmpty() || line.startsWith("###")) continue;
            String[] p = line.split("\\|");
            if (p.length < 2) continue;
            Container c = new Container();
            c.name = p[0];
            c.status = p[1];
            c.image = p.length >= 3 ? p[2] : "";
            c.running = c.status.startsWith("Up");
            containers.add(c);
        }

        if (containers.isEmpty()) {
            tvInfo.setText("没有容器");
            return;
        }

        tvInfo.setText("共 " + containers.size() + " 个容器");
        for (Container c : containers) {
            listBox.addView(makeContainerRow(c));
        }
    }

    private View makeContainerRow(Container c) {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setBackgroundColor(Color.parseColor("#1C1F2A"));
        card.setPadding(dp(12), dp(10), dp(12), dp(10));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.bottomMargin = dp(10);
        card.setLayoutParams(lp);

        // 第一行：名称 + 状态点
        LinearLayout r1 = new LinearLayout(this);
        r1.setOrientation(LinearLayout.HORIZONTAL);
        r1.setGravity(Gravity.CENTER_VERTICAL);

        TextView tvName = new TextView(this);
        tvName.setText(c.name);
        tvName.setTextColor(Color.parseColor("#E8EAFF"));
        tvName.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
        tvName.setTypeface(Typeface.DEFAULT_BOLD);
        r1.addView(tvName, new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        TextView tvSt = new TextView(this);
        tvSt.setText(c.running ? "运行中" : "已停止");
        tvSt.setTextColor(Color.parseColor(c.running ? "#4ADE80" : "#F87171"));
        tvSt.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        r1.addView(tvSt);
        card.addView(r1);

        // 第二行：镜像
        if (!c.image.isEmpty()) {
            TextView tvImg = new TextView(this);
            tvImg.setText(c.image);
            tvImg.setTextColor(Color.parseColor("#7A8099"));
            tvImg.setTextSize(TypedValue.COMPLEX_UNIT_SP, 10);
            tvImg.setTypeface(Typeface.MONOSPACE);
            tvImg.setPadding(0, dp(2), 0, dp(6));
            card.addView(tvImg);
        }

        // 第三行：状态详情
        TextView tvStatus = new TextView(this);
        tvStatus.setText(c.status);
        tvStatus.setTextColor(Color.parseColor("#8A90A8"));
        tvStatus.setTextSize(TypedValue.COMPLEX_UNIT_SP, 10);
        tvStatus.setPadding(0, 0, 0, dp(8));
        card.addView(tvStatus);

        // 第四行：操作按钮
        LinearLayout r4 = new LinearLayout(this);
        r4.setOrientation(LinearLayout.HORIZONTAL);

        Button bStart = makeBtn("启动", "#2FA37A");
        bStart.setEnabled(!c.running);
        bStart.setAlpha(c.running ? 0.4f : 1f);
        bStart.setOnClickListener(v -> control(c.name, "start"));
        r4.addView(bStart);

        Button bStop = makeBtn("停止", "#C25A4A");
        bStop.setEnabled(c.running);
        bStop.setAlpha(c.running ? 1f : 0.4f);
        bStop.setOnClickListener(v -> confirmStop(c.name));
        r4.addView(bStop);

        Button bRestart = makeBtn("重启", "#8A6BD1");
        bRestart.setOnClickListener(v -> confirmRestart(c.name));
        r4.addView(bRestart);

        card.addView(r4);
        return card;
    }

    private void confirmStop(String name) {
        new AlertDialog.Builder(this)
                .setTitle("停止 " + name + "？")
                .setMessage("停止后该容器的服务将不可访问，确定继续？")
                .setPositiveButton("停止", (d, w) -> control(name, "stop"))
                .setNegativeButton("取消", null)
                .show();
    }

    private void confirmRestart(String name) {
        new AlertDialog.Builder(this)
                .setTitle("重启 " + name + "？")
                .setMessage("重启期间服务会短暂中断（青龙约需 2-3 分钟恢复）。")
                .setPositiveButton("重启", (d, w) -> control(name, "restart"))
                .setNegativeButton("取消", null)
                .show();
    }

    private void control(String name, String action) {
        tvInfo.setText("正在对 " + name + " 执行 " + action + " …");
        new Thread(() -> {
            final String out = exec("sh " + MGMT + " ctl " + name + " " + action);
            ui.post(() -> {
                boolean ok = out != null && !out.contains("ERROR");
                Toast.makeText(this,
                        (ok ? "✅ " : "❌ ") + name + " " + action + (ok ? " 已执行" : " 失败"),
                        Toast.LENGTH_SHORT).show();
                if (out != null && !out.trim().isEmpty()) {
                    tvInfo.setText(out.trim());
                }
                loadContainers();
            });
        }).start();
    }

    // ================= 工具 =================

    private String exec(String cmd) {
        StringBuilder sb = new StringBuilder();
        Process p = null;
        try {
            p = Runtime.getRuntime().exec(new String[]{"/debug_ramdisk/su", "-c", cmd});
            BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()));
            String line;
            while ((line = r.readLine()) != null) sb.append(line).append('\n');
            p.waitFor();
        } catch (Exception e) {
            sb.append("执行失败: ").append(e.getMessage());
        } finally {
            if (p != null) p.destroy();
        }
        return sb.toString().trim();
    }

    private int dp(int v) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v,
                getResources().getDisplayMetrics());
    }

    private Button makeBtn(String text, String color) {
        Button b = new Button(this);
        b.setText(text);
        b.setAllCaps(false);
        b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        b.setTextColor(Color.WHITE);
        b.setBackgroundColor(Color.parseColor(color));
        b.setPadding(dp(12), dp(6), dp(12), dp(6));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.rightMargin = dp(8);
        b.setLayoutParams(lp);
        return b;
    }
}
