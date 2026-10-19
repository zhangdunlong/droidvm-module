"""
DVM Lite APK 构建脚本（无 Gradle，直接用 aapt2 + javac + d8 + apksigner）
"""
import os
import shutil
import subprocess
import sys
import zipfile

BASE = r"C:\Users\zdl\dvm-module"
APP = os.path.join(BASE, "app")
SDK = os.path.join(BASE, "sdk")
BT = os.path.join(SDK, "build-tools", "34.0.0")
PLATFORM = os.path.join(SDK, "platforms", "android-34", "android.jar")
JAVA_HOME = os.path.join(BASE, "jdk", "jdk-17.0.20.1+1")

JAVA = os.path.join(JAVA_HOME, "bin", "java.exe")
JAVAC = os.path.join(JAVA_HOME, "bin", "javac.exe")
KEYTOOL = os.path.join(JAVA_HOME, "bin", "keytool.exe")
AAPT2 = os.path.join(BT, "aapt2.exe")
D8 = os.path.join(BT, "d8.bat")
ZIPALIGN = os.path.join(BT, "zipalign.exe")
APKSIGNER = os.path.join(BT, "apksigner.bat")

BUILD = os.path.join(BASE, "build")
KS = os.path.join(BASE, "dvm-lite.keystore")
KS_PASS = "dvmlite2026"
KS_ALIAS = "dvmlite"

PKG = "com.dvm.lite"
APK_NAME = "dvm-lite.apk"


def run(cmd, cwd=None, allow_fail=False):
    print(f"$ {' '.join(str(c) for c in cmd) if isinstance(cmd, list) else cmd}")
    env = os.environ.copy()
    env["JAVA_HOME"] = JAVA_HOME
    env["PATH"] = os.path.join(JAVA_HOME, "bin") + os.pathsep + env.get("PATH", "")
    # Android 工具在中文 Windows 下可能输出 GBK，统一容错解码
    r = subprocess.run(cmd, cwd=cwd, shell=isinstance(cmd, str), env=env,
                       capture_output=True)
    for stream_name, raw in (("stdout", r.stdout), ("stderr", r.stderr)):
        if not raw:
            continue
        try:
            txt = raw.decode("utf-8")
        except UnicodeDecodeError:
            try:
                txt = raw.decode("gbk")
            except UnicodeDecodeError:
                txt = raw.decode("utf-8", "replace")
        txt = txt.strip()
        if txt:
            print(txt[:2000])
    if r.returncode != 0:
        if not allow_fail:
            sys.exit(f"FAILED rc={r.returncode}")
    return r


def main():
    # 清理
    if os.path.exists(BUILD):
        shutil.rmtree(BUILD)
    os.makedirs(BUILD, exist_ok=True)
    for d in ["res", "gen", "classes", "dex"]:
        os.makedirs(os.path.join(BUILD, d), exist_ok=True)

    print("=" * 60)
    print("STEP 1: aapt2 compile (resources)")
    print("=" * 60)
    res_zip = os.path.join(BUILD, "res.zip")
    run([AAPT2, "compile", "--dir", os.path.join(APP, "res"), "-o", res_zip])

    print("=" * 60)
    print("STEP 2: aapt2 link (manifest + R.java + base apk)")
    print("=" * 60)
    base_apk = os.path.join(BUILD, "base.apk")
    run([AAPT2, "link", "-o", base_apk,
         "-I", PLATFORM,
         "--manifest", os.path.join(APP, "AndroidManifest.xml"),
         "-R", res_zip,
         "--java", os.path.join(BUILD, "gen"),
         "--min-sdk-version", "26",
         "--target-sdk-version", "34",
         "--auto-add-overlay"])

    print("=" * 60)
    print("STEP 3: javac")
    print("=" * 60)
    srcs = []
    for root, dirs, files in os.walk(os.path.join(BUILD, "gen")):
        for f in files:
            if f.endswith(".java"):
                srcs.append(os.path.join(root, f))
    for root, dirs, files in os.walk(os.path.join(APP, "src")):
        for f in files:
            if f.endswith(".java"):
                srcs.append(os.path.join(root, f))
    print(f"源文件: {len(srcs)}")

    classes_dir = os.path.join(BUILD, "classes")
    run([JAVAC, "-source", "8", "-target", "8",
         "-encoding", "UTF-8",
         "-classpath", PLATFORM,
         "-d", classes_dir] + srcs)

    print("=" * 60)
    print("STEP 4: d8 (dex)")
    print("=" * 60)
    class_files = []
    for root, dirs, files in os.walk(classes_dir):
        for f in files:
            if f.endswith(".class"):
                class_files.append(os.path.join(root, f))
    print(f"class 文件: {len(class_files)}")
    dex_dir = os.path.join(BUILD, "dex")
    run([D8, "--lib", PLATFORM, "--min-api", "26",
         "--output", dex_dir] + class_files)

    print("=" * 60)
    print("STEP 5: 把 classes.dex 塞进 APK")
    print("=" * 60)
    dex_file = os.path.join(dex_dir, "classes.dex")
    if not os.path.exists(dex_file):
        sys.exit("classes.dex 未生成")
    # aapt2 生成的 base.apk 是 zip，用 python 追加
    tmp_apk = os.path.join(BUILD, "with_dex.apk")
    shutil.copy2(base_apk, tmp_apk)
    with zipfile.ZipFile(tmp_apk, "a", zipfile.ZIP_DEFLATED) as z:
        z.write(dex_file, "classes.dex")
    print(f"已加入 classes.dex ({os.path.getsize(dex_file)} bytes)")

    print("=" * 60)
    print("STEP 6: zipalign")
    print("=" * 60)
    aligned = os.path.join(BUILD, "aligned.apk")
    run([ZIPALIGN, "-f", "4", tmp_apk, aligned])

    print("=" * 60)
    print("STEP 7: keystore + sign")
    print("=" * 60)
    if not os.path.exists(KS):
        run([KEYTOOL, "-genkeypair", "-v",
             "-keystore", KS, "-alias", KS_ALIAS,
             "-keyalg", "RSA", "-keysize", "2048", "-validity", "10000",
             "-storepass", KS_PASS, "-keypass", KS_PASS,
             "-dname", "CN=DVM Lite, OU=Dev, O=zdl, L=Wuxi, ST=Jiangsu, C=CN"])

    signed = os.path.join(BUILD, APK_NAME)
    run([APKSIGNER, "sign",
         "--ks", KS, "--ks-pass", f"pass:{KS_PASS}",
         "--ks-key-alias", KS_ALIAS,
         "--key-pass", f"pass:{KS_PASS}",
         "--out", signed, aligned])

    print("=" * 60)
    print("BUILD OK")
    print("=" * 60)
    print(f"输出: {signed}")
    print(f"大小: {os.path.getsize(signed)/1024:.1f} KB")

    # 验证
    run([APKSIGNER, "verify", "--verbose", signed], allow_fail=True)


if __name__ == "__main__":
    main()
