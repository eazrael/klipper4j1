package com.test.sucheck;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.provider.Settings;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileWriter;
import java.io.InputStreamReader;
import java.lang.reflect.Method;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

public class MainActivity extends Activity {

    private static final String[] RUNTIME_PERMS = {
        Manifest.permission.READ_EXTERNAL_STORAGE,
        Manifest.permission.WRITE_EXTERNAL_STORAGE,
        Manifest.permission.ACCESS_FINE_LOCATION,
        Manifest.permission.ACCESS_COARSE_LOCATION,
    };
    private static final int REQ_CODE = 1;

    private TextView output;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private StringBuilder logBuffer;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().setType(WindowManager.LayoutParams.TYPE_SYSTEM_ALERT);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(4, 4, 4, 4);

        // Horizontal button bar — fits landscape without eating vertical space
        LinearLayout buttons = new LinearLayout(this);
        buttons.setOrientation(LinearLayout.HORIZONTAL);
        LinearLayout.LayoutParams btnParams = new LinearLayout.LayoutParams(
            0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f);

        Button btnExit = new Button(this);
        btnExit.setText("Exit");
        btnExit.setTextSize(11);
        btnExit.setOnClickListener(v -> finish());
        btnExit.setLayoutParams(btnParams);

        Button btnRun = new Button(this);
        btnRun.setText("Diagnostics");
        btnRun.setTextSize(11);
        btnRun.setOnClickListener(v -> {
            output.setText("");
            new Thread(this::runDiagnostics).start();
        });
        btnRun.setLayoutParams(new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.WRAP_CONTENT, 1f));

        Button btnEdl = new Button(this);
        btnEdl.setText("REBOOT TO EDL");
        btnEdl.setTextSize(11);
        btnEdl.setOnClickListener(v -> rebootEdl());
        btnEdl.setLayoutParams(new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.WRAP_CONTENT, 1f));

        Button btnUninstall = new Button(this);
        btnUninstall.setText("Uninstall");
        btnUninstall.setTextSize(11);
        btnUninstall.setOnClickListener(v -> selfUninstall());
        btnUninstall.setLayoutParams(new LinearLayout.LayoutParams(0,
            LinearLayout.LayoutParams.WRAP_CONTENT, 1f));

        buttons.addView(btnExit);
        buttons.addView(btnRun);
        buttons.addView(btnEdl);
        buttons.addView(btnUninstall);

        output = new TextView(this);
        output.setPadding(8, 4, 8, 4);
        output.setTextSize(11);
        output.setTypeface(android.graphics.Typeface.MONOSPACE);

        ScrollView scroll = new ScrollView(this);
        scroll.setLayoutParams(new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f));
        scroll.addView(output);

        root.addView(buttons);
        root.addView(scroll);
        setContentView(root);

         requestAllPermissions();
    }

    // --- Permissions ---

    private void requestAllPermissions() {
        append("--- Permission Check ---\n");
        if (!Settings.System.canWrite(this)) {
            append("WRITE_SETTINGS: NOT GRANTED — opening system screen\n");
            startActivity(new Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS,
                Uri.parse("package:" + getPackageName())));
        } else {
            append("WRITE_SETTINGS: GRANTED\n");
        }
        boolean secureSettings = checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS)
            == PackageManager.PERMISSION_GRANTED;
        append("WRITE_SECURE_SETTINGS: " + (secureSettings ? "GRANTED" : "NOT GRANTED") + "\n");
        boolean allGranted = true;
        for (String p : RUNTIME_PERMS) {
            boolean ok = checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED;
            append(leaf(p) + ": " + (ok ? "GRANTED" : "NOT GRANTED") + "\n");
            if (!ok) allGranted = false;
        }
        if (!allGranted) requestPermissions(RUNTIME_PERMS, REQ_CODE);
    }

    @Override
    public void onRequestPermissionsResult(int code, String[] perms, int[] results) {
        append("\n--- Permission Results ---\n");
        for (int i = 0; i < perms.length; i++) {
            append(leaf(perms[i]) + ": " +
                (results[i] == PackageManager.PERMISSION_GRANTED ? "GRANTED" : "DENIED") + "\n");
        }
    }

    private static String leaf(String perm) {
        return perm.substring(perm.lastIndexOf('.') + 1);
    }

    // --- Diagnostics ---

    private void runDiagnostics() {
        logBuffer = new StringBuilder();

        section("Identity");
        runShell("id");

        section("System Properties");
        getProp("ro.build.version.release");
        getProp("ro.product.model");
        getProp("ro.adb.secure");
        getProp("service.adb.tcp.port");
        getProp("persist.adb.tcp.port");
        getProp("init.svc.adbd");

        section("Partitions (/dev/block/bootdevice/by-name)");
        File byName = new File("/dev/block/bootdevice/by-name");
        if (byName.exists()) {
            File[] entries = byName.listFiles();
            if (entries != null) {
                Arrays.sort(entries, (a, b) -> a.getName().compareTo(b.getName()));
                for (File f : entries) append(f.getName() + " -> " + resolveSymlink(f) + "\n");
            }
        } else {
            runShell("ls -la /dev/block/platform/");
        }

        section("Mounts");
        runShell("mount");

        section("Disk Usage");
        runShell("df");

        section("Installed Packages");
        listPackages();

        section("USB Log");
        tryWriteLogToUsb();
    }

    private void listPackages() {
        try {
            List<PackageInfo> pkgs = getPackageManager().getInstalledPackages(0);
            pkgs.sort((a, b) -> a.packageName.compareTo(b.packageName));
            for (PackageInfo p : pkgs) {
                append(p.packageName + "  " + p.versionName + "  (" + p.versionCode + ")\n");
            }
        } catch (Exception e) {
            append("failed: " + e.getMessage() + "\n");
        }
    }

    private void tryWriteLogToUsb() {
        Set<String> skip = new HashSet<>(Arrays.asList("emulated", "self"));
        String[] bases = {"/mnt/media_rw", "/storage"};
        for (String base : bases) {
            File dir = new File(base);
            if (!dir.exists()) continue;
            File[] vols = dir.listFiles();
            if (vols == null) continue;
            for (File vol : vols) {
                if (skip.contains(vol.getName())) continue;
                File logFile = new File(vol, "j1_diagnostics.txt");
                try (FileWriter fw = new FileWriter(logFile)) {
                    fw.write(logBuffer.toString());
                    append("written to " + logFile + "\n");
                    return;
                } catch (Exception ignored) {}
            }
        }
        append("no writable USB storage found\n");
    }

    private void section(String title) {
        append("\n--- " + title + " ---\n");
    }

    private String resolveSymlink(File f) {
        try { return f.getCanonicalPath(); } catch (Exception e) { return "?"; }
    }

    private void getProp(String key) {
        try {
            Class<?> sp = Class.forName("android.os.SystemProperties");
            Method get = sp.getDeclaredMethod("get", String.class);
            append(key + "=" + get.invoke(null, key) + "\n");
        } catch (Exception e) {
            append(key + " read failed: " + e.getMessage() + "\n");
        }
    }

    private void runShell(String cmd) {
        try {
            Process p = Runtime.getRuntime().exec(new String[]{"sh", "-c", cmd});
            BufferedReader out = new BufferedReader(new InputStreamReader(p.getInputStream()));
            BufferedReader err = new BufferedReader(new InputStreamReader(p.getErrorStream()));
            String line;
            while ((line = out.readLine()) != null) append(line + "\n");
            while ((line = err.readLine()) != null) append("[err] " + line + "\n");
            p.waitFor();
        } catch (Exception e) {
            append("exec failed: " + e.getMessage() + "\n");
        }
    }

    // --- EDL ---

    private void rebootEdl() {
        append("Attempting reboot into EDL (9008)...\n");
        try {
            PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
            Method reboot = pm.getClass().getMethod("reboot", String.class);
            reboot.setAccessible(true);
            reboot.invoke(pm, "edl");
            return;
        } catch (Exception e) {
            append("PowerManager.reboot(edl) failed: " + e.getMessage() + "\n");
        }
        runShell("reboot edl");
        runShell("svc power reboot edl");
        trySetProp("sys.powerctl", "reboot,edl");
        append("All EDL methods attempted.\n");
    }

    private void trySetProp(String key, String value) {
        try {
            Class<?> sp = Class.forName("android.os.SystemProperties");
            Method set = sp.getDeclaredMethod("set", String.class, String.class);
            set.invoke(null, key, value);
        } catch (Exception ignored) {}
    }

    // --- Uninstall ---

    private void selfUninstall() {
        append("Uninstalling...\n");
        try {
            Runtime.getRuntime().exec(new String[]{"pm", "uninstall", getPackageName()});
        } catch (Exception e) {
            Intent intent = new Intent(Intent.ACTION_UNINSTALL_PACKAGE);
            intent.setData(Uri.parse("package:" + getPackageName()));
            startActivity(intent);
        }
    }

    // --- Output ---

    private void append(String text) {
        if (logBuffer != null) logBuffer.append(text);
        handler.post(() -> output.append(text));
    }
}
