package com.dvm.lite;

import android.app.Activity;
import android.app.AlertDialog;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.method.ScrollingMovementMethod;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.CookieManager;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.Spinner;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 青龙抓取：内置 WebView 打开站点，登录后一键抓 Cookie/localStorage 并写入青龙环境变量。
 * 等价于 PC 端「青龙签到助手」扩展，但用 Android CookieManager 读 HttpOnly Cookie。
 */
public class GrabActivity extends Activity {

    // ===== 青龙配置（部署时改成你的环境；不用可留空） =====
    private static final String QL_BASE = "";   // 例: "http://192.168.x.x:5700"
    private static final String QL_USER = "admin";
    private static final String QL_PASS = "CHANGE_ME_ON_DEPLOY";

    // ===== 站点规则（从 sites.js 转换） =====
    private static final String[][] SITE_TABLE = {
            // {id, 名称, 域名, 变量名, 类型, 参数}
            {"nodeseek", "NodeSeek", "nodeseek.com", "NODESEEK_COOKIE", "cookie", ""},
            {"nodeseek2", "NodeSeek(NS)", "nodeseek.com", "NS_COOKIE", "cookie", ""},
            {"bilibili", "哔哩哔哩", "bilibili.com", "BILIBILI_COOKIE", "cookie", ""},
            {"tieba", "百度贴吧", "tieba.baidu.com", "TIEBA_COOKIE", "cookie", ""},
            {"baidupan", "百度网盘", "pan.baidu.com", "BAIDU_COOKIE", "cookie", ""},
            {"quark", "夸克网盘", "pan.quark.cn", "QUARK_COOKIE", "cookie", ""},
            {"deepflood", "DeepFlood", "deepflood.com", "DEEPFLOOD_COOKIE", "cookie", ""},
            {"enshan", "恩山论坛", "right.com.cn", "enshan_cookie", "cookie", ""},
            {"isvoro", "Isvoro", "isvoro.com", "ISVORO_ACCOUNTS", "cookie-pick", "pmt_access#pmt_csrf"},
            {"svyun", "速维云", "svyun.com", "SVYUN_TOKEN", "cookie-pick", "idcsmart_jwt"},
            {"acck", "ACCK", "acck.io", "ACCK_CF_CLEARANCE", "cookie-pick", "cf_clearance"},
            {"aliyunpan", "阿里云盘", "alipan.com", "ALIYUN_REFRESH_TOKEN", "localstorage", "token|refresh_token"},
            {"kcyun", "快冲云", "kcyun666.xyz", "KCY_ACCESS_TOKEN", "localstorage", "accessToken|"},
    };

    private final Handler ui = new Handler(Looper.getMainLooper());
    private Spinner spSite;
    private WebView webView;
    private TextView tvStatus;
    private TextView tvLog;
    private String[] siteLabels;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.parseColor("#12141A"));
        int pad = dp(10);
        root.setPadding(pad, pad, pad, pad);

        // 标题
        TextView title = new TextView(this);
        title.setText("青龙抓取");
        title.setTextColor(Color.parseColor("#E8EAFF"));
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 20);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        root.addView(title);

        tvStatus = new TextView(this);
        tvStatus.setText("选择站点 → 登录 → 点「抓取并写入」");
        tvStatus.setTextColor(Color.parseColor("#7A8099"));
        tvStatus.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        tvStatus.setPadding(0, dp(2), 0, dp(8));
        root.addView(tvStatus);

        // 站点选择 + 打开
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);

        spSite = new Spinner(this);
        siteLabels = new String[SITE_TABLE.length];
        for (int i = 0; i < SITE_TABLE.length; i++) {
            siteLabels[i] = SITE_TABLE[i][1] + " (" + SITE_TABLE[i][2] + ")";
        }
        ArrayAdapter<String> ad = new ArrayAdapter<>(this,
                android.R.layout.simple_spinner_dropdown_item, siteLabels);
        spSite.setAdapter(ad);
        row.addView(spSite, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

        Button btnOpen = makeBtn("打开", "#4A7CFF");
        btnOpen.setOnClickListener(v -> openSite());
        row.addView(btnOpen);

        Button btnGrab = makeBtn("抓取并写入", "#2FA37A");
        btnGrab.setOnClickListener(v -> grabAndWrite());
        row.addView(btnGrab);

        root.addView(row);
        addSpacer(root, 8);

        // WebView
        webView = new WebView(this);
        webView.getSettings().setJavaScriptEnabled(true);
        webView.getSettings().setDomStorageEnabled(true);
        webView.getSettings().setLoadWithOverviewMode(true);
        webView.getSettings().setUseWideViewPort(true);
        webView.getSettings().setBuiltInZoomControls(true);
        webView.getSettings().setDisplayZoomControls(false);
        webView.getSettings().setUserAgentString(
                "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) " +
                "Chrome/120.0.0.0 Mobile Safari/537.36");
        webView.setWebViewClient(new WebViewClient());
        CookieManager.getInstance().setAcceptCookie(true);
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true);

        LinearLayout.LayoutParams wlp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f);
        root.addView(webView, wlp);

        // 日志
        tvLog = new TextView(this);
        tvLog.setText("");
        tvLog.setTextColor(Color.parseColor("#8A90A8"));
        tvLog.setTextSize(TypedValue.COMPLEX_UNIT_SP, 10);
        tvLog.setTypeface(Typeface.MONOSPACE);
        tvLog.setTextIsSelectable(true);
        tvLog.setMovementMethod(new ScrollingMovementMethod());
        tvLog.setBackgroundColor(Color.parseColor("#0C0E13"));
        tvLog.setPadding(dp(8), dp(6), dp(8), dp(6));
        root.addView(tvLog, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(120)));

        setContentView(root);
    }

    // ================= UI 辅助 =================

    private int dp(int v) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v,
                getResources().getDisplayMetrics());
    }

    private void addSpacer(LinearLayout p, int h) {
        View v = new View(this);
        p.addView(v, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(h)));
    }

    private Button makeBtn(String text, String color) {
        Button b = new Button(this);
        b.setText(text);
        b.setAllCaps(false);
        b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
        b.setTextColor(Color.WHITE);
        b.setBackgroundColor(Color.parseColor(color));
        b.setPadding(dp(10), dp(6), dp(10), dp(6));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.leftMargin = dp(6);
        b.setLayoutParams(lp);
        return b;
    }

    private void log(String s) {
        ui.post(() -> {
            tvLog.append(s + "\n");
            tvStatus.setText(s);
        });
    }

    // ================= 站点操作 =================

    private String[] currentSite() {
        int idx = spSite.getSelectedItemPosition();
        if (idx < 0 || idx >= SITE_TABLE.length) return null;
        return SITE_TABLE[idx];
    }

    private void openSite() {
        String[] site = currentSite();
        if (site == null) return;
        String url = "https://" + site[2];
        log("打开 " + url);
        webView.loadUrl(url);
    }

    private void grabAndWrite() {
        final String[] site = currentSite();
        if (site == null) return;
        final String siteId = site[0];
        final String domain = site[2];
        final String varName = site[3];
        final String type = site[4];
        final String param = site[5];

        String cookie = CookieManager.getInstance().getCookie("https://" + domain);
        if (cookie == null || cookie.isEmpty()) {
            // 尝试当前 WebView URL
            String cur = webView.getUrl();
            if (cur != null) {
                cookie = CookieManager.getInstance().getCookie(cur);
            }
        }
        if (cookie == null) cookie = "";

        final String finalCookie = cookie;
        log("抓到 Cookie " + finalCookie.length() + " 字符");

        if ("localstorage".equals(type)) {
            // localStorage 需要 evaluateJavascript
            String[] parts = param.split("\\|", -1);
            final String key = parts[0];
            final String path = parts.length > 1 ? parts[1] : "";
            String js = "(function(){try{var v=localStorage.getItem('" + key + "');" +
                    "if(v===null)return '';try{v=JSON.parse(v)}catch(e){}" +
                    (path.isEmpty() ? "" :
                            "if(v&&typeof v==='object'){v=v['" + path + "']}" ) +
                    "if(v===null||v===undefined)return '';" +
                    "return typeof v==='string'?v:JSON.stringify(v)}catch(e){return '__ERR__'+e.message}})()";
            webView.evaluateJavascript(js, value -> {
                String v = value == null ? "" : value;
                if (v.startsWith("\"") && v.endsWith("\"")) {
                    v = v.substring(1, v.length() - 1);
                }
                v = v.replace("\\u003c", "<").replace("\\/", "/");
                if (v.startsWith("__ERR__")) {
                    log("localStorage 读取失败: " + v);
                    return;
                }
                final String val = v;
                log("localStorage[" + key + "] = " + (val.length() > 40 ? val.substring(0, 40) + "..." : val));
                new Thread(() -> writeToQinglong(varName, val, site[1] + " · " + type)).start();
            });
        } else {
            String value = finalCookie;
            if ("cookie-pick".equals(type)) {
                Map<String, String> map = new HashMap<>();
                for (String kv : finalCookie.split(";\\s*")) {
                    int eq = kv.indexOf('=');
                    if (eq > 0) map.put(kv.substring(0, eq).trim(), kv.substring(eq + 1).trim());
                }
                String[] names = param.split("#");
                StringBuilder sb = new StringBuilder();
                for (String n : names) {
                    String v = map.get(n);
                    if (v != null && !v.isEmpty()) {
                        if (sb.length() > 0) sb.append("#");
                        sb.append(v);
                    }
                }
                value = sb.toString();
            }
            if (value.isEmpty()) {
                log("抓到的值为空，请确认已登录 " + domain);
                return;
            }
            final String val = value;
            new Thread(() -> writeToQinglong(varName, val, site[1] + " · " + type)).start();
        }
    }

    // ================= 青龙 API =================

    private String qlLogin() throws Exception {
        if (QL_BASE.trim().isEmpty()) {
            throw new Exception("青龙地址未配置：请在源码填写 QL_BASE 后重新构建");
        }
        JSONObject body = new JSONObject();
        body.put("username", QL_USER);
        body.put("password", QL_PASS);
        String r = http("POST", QL_BASE + "/api/user/login", null, body.toString());
        JSONObject j = new JSONObject(r);
        return j.getJSONObject("data").getString("token");
    }

    private void writeToQinglong(String name, String value, String remarks) {
        try {
            log("登录青龙…");
            String token = qlLogin();
            log("登录成功");

            // 查现有
            String listRaw = http("GET", QL_BASE + "/api/envs?searchValue=", token, null);
            JSONObject lj = new JSONObject(listRaw);
            JSONArray arr = lj.optJSONArray("data");
            JSONObject existing = null;
            if (arr != null) {
                for (int i = 0; i < arr.length(); i++) {
                    JSONObject e = arr.getJSONObject(i);
                    if (name.equals(e.optString("name"))) {
                        existing = e;
                        break;
                    }
                }
            }

            String resp;
            if (existing != null) {
                JSONObject body = new JSONObject();
                body.put("id", existing.getInt("id"));
                body.put("name", name);
                body.put("value", value);
                body.put("remarks", remarks);
                resp = http("PUT", QL_BASE + "/api/envs", token, body.toString());
                log("更新 " + name + " -> " + truncate(resp));
            } else {
                JSONArray body = new JSONArray();
                JSONObject one = new JSONObject();
                one.put("name", name);
                one.put("value", value);
                one.put("remarks", remarks);
                body.put(one);
                resp = http("POST", QL_BASE + "/api/envs", token, body.toString());
                log("创建 " + name + " -> " + truncate(resp));
            }

            ui.post(() -> tvStatus.setText("✅ 已写入 " + name));
        } catch (Exception e) {
            log("❌ 写入失败: " + e.getMessage());
        }
    }

    private String truncate(String s) {
        if (s == null) return "";
        return s.length() > 150 ? s.substring(0, 150) + "…" : s;
    }

    private String http(String method, String urlStr, String token, String body) throws Exception {
        HttpURLConnection c = (HttpURLConnection) new URL(urlStr).openConnection();
        c.setRequestMethod(method);
        c.setConnectTimeout(15000);
        c.setReadTimeout(20000);
        c.setRequestProperty("Content-Type", "application/json");
        if (token != null) c.setRequestProperty("Authorization", "Bearer " + token);
        if (body != null) {
            c.setDoOutput(true);
            try (OutputStream os = c.getOutputStream()) {
                os.write(body.getBytes("UTF-8"));
            }
        }
        int code = c.getResponseCode();
        InputStream is = code >= 400 ? c.getErrorStream() : c.getInputStream();
        BufferedReader r = new BufferedReader(new InputStreamReader(is, "UTF-8"));
        StringBuilder sb = new StringBuilder();
        String line;
        while ((line = r.readLine()) != null) sb.append(line);
        r.close();
        c.disconnect();
        return sb.toString();
    }
}
