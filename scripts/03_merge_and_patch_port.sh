#!/usr/bin/env bash
set -euo pipefail

# Phase 2/3 Assembly: Hybrid Port Synthesis (PKJ110 ColorOS 17 + garnet HyperOS hardware base)
# - Stages garnet stock hardware partitions (boot, dtbo, vendor, vendor_dlkm, odm)
# - Copies PKJ110 system, system_ext, product (preserving SELinux xattrs)
# - Flattens my_* directly into SAR root (/my_*) with /system/my_* symlinks
# - Strips removable del-app* bloatware to fit garnet's 9.0 GiB super limit
# - Grafts garnet VNDK v32/v33/v34 APEXes & VINTF compatibility matrices
# - Patches my_product feature flags (optical FOD, flat screen, 1220x2712 @ 480dpi)
# - Enables early-boot insecure ADB & patches vendor_boot + vbmeta

PROJ="/Users/tahaermis/Desktop/ColorOS17-Garnet"
# shellcheck source=/dev/null
source "$PROJ/scripts/00_mount_workspace.sh"

GARNET_IMG="$MNT_POINT/base_garnet/images"
GARNET_EXT="$MNT_POINT/base_garnet/extracted"
DONOR_EXT="$MNT_POINT/donor_fx8u/extracted"
PORT="$MNT_POINT/port_build"

for req in "$GARNET_IMG/vendor.img" "$GARNET_IMG/vendor_boot.img" "$DONOR_EXT/system" "$DONOR_EXT/system_ext" "$DONOR_EXT/product"; do
    if [[ ! -e "$req" ]]; then
        echo "ERROR: Missing extracted input ($req). Run scripts/02_extract_firmwares.sh first." >&2
        exit 1
    fi
done

echo "=== [1/7] Staging garnet stock hardware partitions ==="
mkdir -p "$PORT/stock_images" "$PORT/boot_work" "$PORT/config"
for img in boot.img dtbo.img vendor.img vendor_dlkm.img odm.img; do
    if [[ -f "$GARNET_IMG/$img" ]]; then
        cp -f "$GARNET_IMG/$img" "$PORT/stock_images/$img"
    fi
done

echo "=== [2/7] Copying PKJ110 ColorOS 17 system, system_ext, and product ==="
for part in system system_ext product; do
    rm -rf "${PORT:?}/$part"
    mkdir -p "$PORT/$part"
    cp -a "$DONOR_EXT/$part/." "$PORT/$part/"
done

SYS_ROOT="$PORT/system"
SYS_INNER="$PORT/system/system"
if [[ ! -d "$SYS_INNER" ]]; then
    echo "ERROR: Expected System-As-Root layout at $SYS_INNER" >&2
    exit 1
fi

echo "=== [3/7] Flattening my_* into SAR root (/my_*) and stripping del-app bloat ==="
MY_PARTS=(my_product my_stock my_heytap my_bigball my_region my_manifest my_carrier my_company my_preload)
for myp in "${MY_PARTS[@]}"; do
    if [[ -d "$DONOR_EXT/$myp" ]]; then
        echo "  -> Placing $myp at /$myp (with /system/$myp symlink)..."
        rm -rf "$SYS_ROOT/$myp"
        mkdir -p "$SYS_ROOT/$myp"
        cp -a "$DONOR_EXT/$myp/." "$SYS_ROOT/$myp/"
        rm -rf "$SYS_INNER/$myp"
        ln -sfn "/$myp" "$SYS_INNER/$myp"
    fi
done

echo "  -> Removing removable third-party del-app* packages and demo videos..."
rm -rf "$SYS_ROOT"/my_*/del-app* "$SYS_ROOT"/my_*/non_overlay/del-app* "$SYS_ROOT/my_product/media/video/"*demo* 2>/dev/null || true

echo "=== [4/7] Grafting garnet VNDK APEXes & VINTF compatibility matrices ==="
mkdir -p "$PORT/system_ext/apex"
for vndk in com.android.vndk.v32.apex com.android.vndk.v33.apex com.android.vndk.v34.apex; do
    if [[ -f "$GARNET_EXT/system_ext/apex/$vndk" ]]; then
        echo "  -> Copying $vndk into /system_ext/apex/..."
        cp -a "$GARNET_EXT/system_ext/apex/$vndk" "$PORT/system_ext/apex/"
    fi
done

mkdir -p "$SYS_INNER/etc/vintf"
for cm in compatibility_matrix.5.xml compatibility_matrix.6.xml; do
    if [[ -f "$GARNET_EXT/system/system/etc/vintf/$cm" ]]; then
        echo "  -> Copying garnet $cm into /system/etc/vintf/..."
        cp -a "$GARNET_EXT/system/system/etc/vintf/$cm" "$SYS_INNER/etc/vintf/"
    fi
done

DEV_CM="$SYS_INNER/etc/vintf/compatibility_matrix.device.xml"
if [[ -f "$DEV_CM" ]]; then
    echo "  -> Marking HAL entries optional in compatibility_matrix.device.xml..."
    python3 - "$DEV_CM" << 'PYEOF'
import re, sys
p = sys.argv[1]
txt = open(p, "r", encoding="utf-8", errors="replace").read()
def repl(m):
    tag = m.group(0)
    if "optional=" in tag:
        return re.sub(r'optional="[^"]*"', 'optional="true"', tag)
    return tag[:-1] + ' optional="true">'
txt = re.sub(r'<hal\b[^>]*>', repl, txt)
open(p, "w", encoding="utf-8").write(txt)
PYEOF
    xattr -w security.selinux "u:object_r:system_file:s0" "$DEV_CM"
fi

echo "=== [5/7] Patching my_product features, build.prop, and staging garnet overlays ==="
MY_PROD_PERM="$SYS_ROOT/my_product/etc/permissions"
if [[ -d "$MY_PROD_PERM" ]]; then
    echo "  -> Patching $MY_PROD_PERM (Optical FOD, flat display, strip PKJ110 exclusives)..."
    python3 - "$MY_PROD_PERM" << 'PYEOF'
import os, re, subprocess, sys

perm_dir = sys.argv[1]
STRIP_PATTERNS = [
    r'oplus\.software\.fingeprint_ultrasonic',
    r'oplus\.software\.fingerprint_ultrasonic',
    r'oplus\.hardware\.alert_slider',
    r'oplus\.software\.audio\.alert_slider',
    r'oplus\.software\.vibrator_alert_slider',
    r'oplus\.software\.radio\.satellite',
    r'android\.hardware\.telephony\.satellite',
    r'oplus\.software\.satellite',
    r'oppo\.common\.support\.curved\.display',
    r'oppo\.back\.touch\.fingerprint\.sensor',
    r'oplus\.software\.display\.resolution_switch_support',
    r'oplus\.software\.app_resolution_switch',
]
strip_re = re.compile("|".join(STRIP_PATTERNS))

saw_oplus_optical = False
saw_oppo_optical = False

for root, _, files in os.walk(perm_dir):
    for fn in sorted(files):
        if not fn.endswith(".xml"):
            continue
        p = os.path.join(root, fn)
        with open(p, "r", encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
        new_lines = []
        changed = False
        for line in lines:
            if "oplus.software.fingeprint_optical" in line or "oplus.software.fingerprint_optical" in line:
                saw_oplus_optical = True
            if "oppo.hardware.fingerprint.optical.support" in line:
                saw_oppo_optical = True
            if strip_re.search(line):
                changed = True
                continue
            new_lines.append(line)
        if changed:
            with open(p, "w", encoding="utf-8") as f:
                f.writelines(new_lines)
            subprocess.run(["xattr", "-w", "security.selinux", "u:object_r:system_file:s0", p], check=True)

if not saw_oplus_optical or not saw_oppo_optical:
    out_xml = os.path.join(perm_dir, "oplus.feature.garnet_optical_fod.xml")
    with open(out_xml, "w", encoding="utf-8") as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n<oplus-config>\n')
        f.write('    <oplus-feature name="oplus.software.fingeprint_optical" />\n')
        f.write('    <oplus-feature name="oplus.software.display.local_hbm_support" />\n')
        f.write('    <oplus-feature name="oplus.software.display.fingerprint_disable_dimlayer" />\n')
        f.write("</oplus-config>\n")
    subprocess.run(["xattr", "-w", "security.selinux", "u:object_r:system_file:s0", out_xml], check=True)
PYEOF
fi

echo "  -> Unblocking ConsumerIrService (hiding unsupported HIDL consumerir feature on Android 17)..."
mkdir -p "$SYS_INNER/etc/permissions"
cat << 'EOF' > "$SYS_INNER/etc/permissions/garnet_unavailable_features.xml"
<?xml version="1.0" encoding="utf-8"?>
<permissions>
    <unavailable-feature name="android.hardware.consumerir" />
</permissions>
EOF
chmod 0644 "$SYS_INNER/etc/permissions/garnet_unavailable_features.xml"
xattr -w security.selinux "u:object_r:system_file:s0" "$SYS_INNER/etc/permissions/garnet_unavailable_features.xml"

cat << 'EOF' > "$SYS_ROOT/my_product/etc/permissions/oplus.feature.garnet_optical_fod.xml"
<?xml version="1.0" encoding="utf-8"?>
<oplus-config>
    <oplus-feature name="oplus.software.fingeprint_optical" />
    <oplus-feature name="oplus.software.display.local_hbm_support" />
    <oplus-feature name="oplus.software.display.fingerprint_disable_dimlayer" />
</oplus-config>
EOF
chmod 0644 "$SYS_ROOT/my_product/etc/permissions/oplus.feature.garnet_optical_fod.xml"
xattr -w security.selinux "u:object_r:system_file:s0" "$SYS_ROOT/my_product/etc/permissions/oplus.feature.garnet_optical_fod.xml"

echo "  -> Fixing QSPM HAL hang (HIDL qspmhal + clearing SM8750 GPU profiles)..."
for qspm_json in \
    "$SYS_ROOT/my_product/etc/extension/sys_graphics_game_gpu_control_panel.json" \
    "$SYS_ROOT/my_product/etc/extension/sys_graphic_enhancement_config.json"; do
    if [[ -f "$qspm_json" ]]; then
        python3 - "$qspm_json" << 'PYEOF'
import json, subprocess, sys
p = sys.argv[1]
with open(p, "r", encoding="utf-8") as f:
    data = json.load(f)
panel = data.get("feature", {}).get("GameGpuControlPanel", {})
preload = panel.get("preload_data", {})
if "qcom_private_data" in preload:
    preload["qcom_private_data"] = []
with open(p, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=4)
    f.write("\n")
subprocess.run(["xattr", "-w", "security.selinux", "u:object_r:system_file:s0", p], check=True)
PYEOF
        chmod 0644 "$qspm_json"
    fi
done

for lib_pair in \
    "$GARNET_EXT/system_ext/lib64/libupdateprof.qti.so:$PORT/system_ext/lib64/libupdateprof.qti.so" \
    "$GARNET_EXT/system_ext/lib/libupdateprof.qti.so:$PORT/system_ext/lib/libupdateprof.qti.so" \
    "$GARNET_EXT/system_ext/lib64/libtrigger-handler.so:$PORT/system_ext/lib64/libtrigger-handler.so" \
    "$GARNET_EXT/system_ext/lib/libtrigger-handler.so:$PORT/system_ext/lib/libtrigger-handler.so" \
    "$GARNET_EXT/system/system/lib64/libhidltransport.so:$PORT/system_ext/lib64/libhidltransport.so" \
    "$GARNET_EXT/system/system/lib/libhidltransport.so:$PORT/system_ext/lib/libhidltransport.so"; do
    src="${lib_pair%%:*}"
    dst="${lib_pair#*:}"
    if [[ -f "$src" ]]; then
        cp -a "$src" "$dst"
        chmod 0644 "$dst"
        xattr -w security.selinux "u:object_r:system_lib_file:s0" "$dst"
    fi
done

echo "  -> Suppressing false Oplus charger voltage alerts & wireless charging in my_product app-features..."
APP_FEAT="$SYS_ROOT/my_product/etc/extension/com.oplus.app-features.xml"
if [[ -f "$APP_FEAT" ]]; then
    python3 - "$APP_FEAT" << 'PYEOF'
import re, subprocess, sys
p = sys.argv[1]
txt = open(p, "r", encoding="utf-8").read()
wireless_names = [
    "oplus.power.onwirelesscharger.support",
    "os.charge.settings.wirelesscharge.support",
    "oplus.power.wirelesschgwhenwired.support",
    "os.charge.settings.wirelesscharging.power",
    "os.charge.settings.wirelesschargingcoil.position",
]
for name in wireless_names:
    txt = re.sub(
        rf'^[ \t]*<app_feature\s+name="{re.escape(name)}"[^/>]*/>\r?\n?',
        f'<!-- disabled on garnet: {name} -->\n',
        txt,
        flags=re.MULTILINE,
    )
if "com.android.systemui.chargingerror_noalert" not in txt:
    txt = txt.replace(
        "</extend_features>",
        '    <app_feature name="com.android.systemui.chargingerror_noalert"/>\n</extend_features>',
        1,
    )
open(p, "w", encoding="utf-8").write(txt)
subprocess.run(["xattr", "-w", "security.selinux", "u:object_r:system_file:s0", p], check=True)
PYEOF
    chmod 0644 "$APP_FEAT"
fi

echo "  -> Removing SM8750 Adreno 830 precompiled Skia shader caches..."
rm -f \
    "$SYS_ROOT/my_product/etc/com.android.launcher/cache/com.android.skia.shaders_cache_oplus" \
    "$SYS_ROOT/my_product/etc/com.android.systemui/cache/com.android.skia.shaders_cache_oplus" \
    "$SYS_ROOT/my_product/etc/com.coloros.assistantscreen/cache/com.android.skia.shaders_cache_oplus" \
    "$SYS_ROOT/my_product/etc/com.coloros.gallery3d/cache/com.android.skia.shaders_cache_oplus"

echo "  -> Disabling incompatible OPPO nandswap/hybridswap/memcg props..."
SYS_EXT_PROP="$PORT/system_ext/etc/build.prop"
if [[ -f "$SYS_EXT_PROP" ]]; then
    python3 - "$SYS_EXT_PROP" << 'PYEOF'
import re, subprocess, sys
p = sys.argv[1]
txt = open(p, "r", encoding="utf-8", errors="replace").read()
for k, v in [
    ("persist.sys.oplus.nandswap.condition", "false"),
    ("persist.sys.oplus.nandswap", "false"),
    ("persist.sys.oplus.hybridswap_app_memcg", "false"),
]:
    if re.search(rf'^{re.escape(k)}=.*$', txt, flags=re.MULTILINE):
        txt = re.sub(rf'^{re.escape(k)}=.*$', f'{k}={v}', txt, flags=re.MULTILINE)
    else:
        txt += f"\n{k}={v}\n"
open(p, "w", encoding="utf-8").write(txt)
subprocess.run(["xattr", "-w", "security.selinux", "u:object_r:system_file:s0", p], check=True)
PYEOF
    chmod 0644 "$SYS_EXT_PROP"
fi

MY_STOCK_PROP="$SYS_ROOT/my_stock/build.prop"
if [[ -f "$MY_STOCK_PROP" ]]; then
    python3 - "$MY_STOCK_PROP" << 'PYEOF'
import re, subprocess, sys
p = sys.argv[1]
txt = open(p, "r", encoding="utf-8", errors="replace").read()
if re.search(r'^ro\.oplus\.osense_app_memcg=.*$', txt, flags=re.MULTILINE):
    txt = re.sub(r'^ro\.oplus\.osense_app_memcg=.*$', 'ro.oplus.osense_app_memcg=false', txt, flags=re.MULTILINE)
else:
    txt += "\nro.oplus.osense_app_memcg=false\n"
open(p, "w", encoding="utf-8").write(txt)
subprocess.run(["xattr", "-w", "security.selinux", "u:object_r:system_file:s0", p], check=True)
PYEOF
    chmod 0644 "$MY_STOCK_PROP"
fi

echo "  -> Fixing restricted binary/prop permissions for --all-root EROFS repack (logd, run-as, build.prop)..."
for f in "$SYS_INNER/bin/logd" "$SYS_INNER/bin/run-as" "$SYS_INNER/bin/simpleperf_app_runner" "$SYS_ROOT/init.environ.rc"; do
    [[ -f "$f" ]] && chmod 0755 "$f"
done
for f in "$SYS_INNER/build.prop" "$PORT/system_ext/etc/build.prop" "$PORT/product/etc/build.prop"; do
    [[ -f "$f" ]] && chmod 0644 "$f"
done

DEBUG_RC="$PORT/system_ext/etc/init/init.oplus.debug.rc"
if [[ -f "$DEBUG_RC" ]]; then
    echo "  -> Disabling non-OPPO minidumpreader service in init.oplus.debug.rc..."
    python3 - "$DEBUG_RC" << 'PYEOF'
import re, subprocess, sys
p = sys.argv[1]
txt = open(p, "r", encoding="utf-8", errors="replace").read()
if "service readdump" in txt:
    txt = re.sub(
        r'(service readdump system/system_ext/bin/minidumpreader\n(?:    (?!disabled).+\n)*?)(    oneshot)',
        r'\1    disabled\n\2',
        txt,
    )
open(p, "w", encoding="utf-8").write(txt)
subprocess.run(["xattr", "-w", "security.selinux", "u:object_r:system_file:s0", p], check=True)
PYEOF
fi

MY_PROD_PROP="$SYS_ROOT/my_product/build.prop"
if [[ -f "$MY_PROD_PROP" ]]; then
    echo "  -> Patching my_product/build.prop for garnet (480dpi, punch-hole, optical FOD, LMK, ADB)..."
    python3 - "$MY_PROD_PROP" << 'PYEOF'
import re, subprocess, sys

p = sys.argv[1]
txt = open(p, "r", encoding="utf-8", errors="replace").read()

replacements = [
    (r'^ro\.sf\.lcd_density=.*$', 'ro.sf.lcd_density=480'),
    (r'^ro\.oplus\.density\.qhd_default=.*$', 'ro.oplus.density.qhd_default=480'),
    (r'^ro\.oplus\.display\.screenhole\.positon=.*$', 'ro.oplus.display.screenhole.positon=568,18:652,128'),
    (r'^ro\.oplus\.key\.actionbutton=.*$', '# disabled on garnet: ro.oplus.key.actionbutton=1'),
    (r'^persist\.sys\.block\.fingerprint=.*$', '# disabled on garnet: persist.sys.block.fingerprint=true'),
    (r'^ro\.oplus\.resolution\.low=.*$', 'ro.oplus.resolution.low=1220,2712'),
    (r'^ro\.oplus\.resolution\.high=.*$', 'ro.oplus.resolution.high=1220,2712'),
    (r'^persist\.oplus\.display\.vrr=.*$', 'persist.oplus.display.vrr=0'),
    (r'^persist\.oplus\.display\.vrr\.adfr=.*$', 'persist.oplus.display.vrr.adfr=0'),
    (r'^persist\.oplus\.display\.vrr\.adfr\.ept=.*$', 'persist.oplus.display.vrr.adfr.ept=false'),
    (r'^persist\.oplus\.display\.vrr\.pdfr=.*$', 'persist.oplus.display.vrr.pdfr=0'),
    (r'^ro\.surface_flinger\.use_content_detection_for_refresh_rate=.*$', 'ro.surface_flinger.use_content_detection_for_refresh_rate=false'),
    (r'^debug\.sf\.disable_client_composition_cache=.*$', 'debug.sf.disable_client_composition_cache=1'),
    (r'^debug\.sf\.enable_hwc_vds=.*$', 'debug.sf.enable_hwc_vds=false'),
    (r'^debug\.sf\.disable_backpressure=.*$', 'debug.sf.disable_backpressure=1'),
    (r'^debug\.sf\.oplus_display_trace\.enable=.*$', 'debug.sf.oplus_display_trace.enable=0'),
    (r'^debug\.sf\.skip_dolphin=.*$', 'debug.sf.skip_dolphin=1'),
    (r'^persist\.sys\.oplus\.anim_level=.*$', 'persist.sys.oplus.anim_level=2'),
]
for pat, rep in replacements:
    txt = re.sub(pat, rep, txt, flags=re.MULTILINE)

txt = re.sub(r'\n?# === Project Garnet Hardware & Bring-Up Overrides ===[\s\S]*$', '', txt)
txt += """

# === Project Garnet Hardware & Bring-Up Overrides ===
ro.sf.lcd_density=480
ro.oplus.resolution.low=1220,2712
ro.oplus.resolution.high=1220,2712
ro.oplus.display.screenhole.positon=568,18:652,128
persist.vendor.fingerprint.sensor_type=optical
persist.vendor.fingerprint.optical.iconsize=210
persist.vendor.fingerprint.optical.iconlocation=275
persist.vendor.fingerprint.optical.iconnumber=1
persist.vendor.fingerprint.sensor_location=610|2437|105
persist.sys.lmk.oplus.kill_memleak_process=0
persist.sys.oplus.nandswap=false
persist.sys.oplus.nandswap.condition=false
persist.sys.oplus.hybridswap_app_memcg=false
sys.batterylow.hidetips=true

# Build #5 Garnet display/smoothness/cutout tuning
persist.oplus.display.vrr=0
persist.oplus.display.vrr.adfr=0
persist.oplus.display.vrr.adfr.ept=false
persist.oplus.display.vrr.pdfr=0
ro.surface_flinger.use_content_detection_for_refresh_rate=false
debug.sf.disable_client_composition_cache=1
debug.sf.enable_hwc_vds=false
debug.sf.disable_backpressure=1
debug.sf.oplus_display_trace.enable=0
debug.sf.skip_dolphin=1
persist.sys.hwui.enable_texture_optimize=true
persist.sys.render_turbo=true
persist.sys.trim_rendernode.enable=true
persist.sys.oplus.anim_level=2

# Early-boot insecure ADB for initial bring-up (remove in release builds)
ro.adb.secure=0
ro.secure=0
ro.debuggable=1
persist.sys.usb.config=mtp,adb
"""

open(p, "w", encoding="utf-8").write(txt)
subprocess.run(["xattr", "-w", "security.selinux", "u:object_r:system_file:s0", p], check=True)
PYEOF
    chmod 0644 "$MY_PROD_PROP"
fi

MY_MANIFEST_PROP="$SYS_ROOT/my_manifest/build.prop"
if [[ ! -f "$MY_MANIFEST_PROP" ]]; then
    echo "ERROR: Missing $MY_MANIFEST_PROP" >&2
    exit 1
fi
python3 - "$MY_MANIFEST_PROP" << 'PYEOF'
import re, sys

p = sys.argv[1]
with open(p, encoding="utf-8") as f:
    txt = f.read()
for key in ("ro.vendor.oplus.market.name", "ro.vendor.oplus.market.enname"):
    value = f"{key}=OPPO Find X8 Ultra by YetUnseen"
    pattern = rf"^{re.escape(key)}=.*$"
    if re.search(pattern, txt, flags=re.MULTILINE):
        txt = re.sub(pattern, lambda _: value, txt, flags=re.MULTILINE)
    else:
        txt = txt.rstrip("\n") + "\n" + value + "\n"
with open(p, "w", encoding="utf-8") as f:
    f.write(txt)
PYEOF

echo "  -> Creating /system/etc/init/init.garnet.port.rc to override stale persist.* props and start FOD LHBM helper..."
mkdir -p "$SYS_INNER/etc/init"
cat << 'EOF' > "$SYS_INNER/etc/init/init.garnet.port.rc"
on init
    # Avoid the 1100ms SurfaceFlinger idle timer repeatedly switching the panel to 30Hz.
    setprop debug.sf.set_idle_timer_ms 0

on post-fs-data
    setprop persist.vendor.fingerprint.sensor_type optical
    setprop persist.vendor.fingerprint.optical.iconsize 210
    setprop persist.vendor.fingerprint.optical.iconlocation 275
    setprop persist.vendor.fingerprint.optical.iconnumber 1
    setprop persist.sys.oplus.nandswap false
    setprop persist.sys.oplus.nandswap.condition false
    setprop persist.sys.oplus.hybridswap_app_memcg false
    setprop persist.sys.lmk.oplus.kill_memleak_process 0
    setprop sys.batterylow.hidetips true
    setprop persist.oplus.display.vrr 0
    setprop persist.oplus.display.vrr.adfr 0
    setprop persist.oplus.display.vrr.adfr.ept false
    setprop persist.oplus.display.vrr.pdfr 0
    setprop persist.sys.oplus.anim_level 2

on boot
    setprop persist.vendor.fingerprint.sensor_type optical
    setprop persist.vendor.fingerprint.optical.iconsize 210
    setprop persist.vendor.fingerprint.optical.iconlocation 275
    setprop persist.vendor.fingerprint.optical.iconnumber 1
    setprop persist.sys.oplus.nandswap false
    setprop persist.sys.oplus.nandswap.condition false
    setprop persist.sys.oplus.hybridswap_app_memcg false
    setprop persist.sys.lmk.oplus.kill_memleak_process 0
    setprop sys.batterylow.hidetips true
    setprop persist.oplus.display.vrr 0
    setprop persist.oplus.display.vrr.adfr 0
    setprop persist.oplus.display.vrr.adfr.ept false
    setprop persist.oplus.display.vrr.pdfr 0
    setprop persist.sys.oplus.anim_level 2
    start garnet_lhbm_helper

on property:sys.boot_completed=1
    exec_background u:r:su:s0 -- /system/bin/sh -c "for i in 1 2 3 4 5; do /system/bin/settings get secure Setting_AodEnable >/dev/null 2>&1 && break; sleep 1; done; /system/bin/settings put secure oplus_keyguard_panoramic_aod_support 1; /system/bin/settings put secure oplus_keyguard_panoramic_aod_all_day_support 1; /system/bin/settings put secure oplus_keyguard_workshop_aod_support 1; /system/bin/settings put secure panoramic_aod_enable 1; /system/bin/settings put secure full_screen_aod 1; /system/bin/settings put secure Setting_AodEnable 1; /system/bin/settings put secure Setting_AodSwitchEnable 1; /system/bin/settings put secure Setting_AodState 1; /system/bin/settings put secure Setting_AodState_Local 1; /system/bin/settings put secure Setting_AodUserEnergySavingSet 0; /system/bin/settings put secure Setting_AodUserSetTime 0; /system/bin/settings put secure doze_always_on 1"

service garnet_lhbm_helper /system/bin/garnet_lhbm_helper
    class main
    user root
    group root graphics input system
    seclabel u:r:su:s0
EOF
chmod 0644 "$SYS_INNER/etc/init/init.garnet.port.rc"
xattr -w security.selinux "u:object_r:system_file:s0" "$SYS_INNER/etc/init/init.garnet.port.rc"

SYS_PROP="$SYS_INNER/build.prop"
if [[ -f "$SYS_PROP" ]] && ! grep -q "Project Garnet Bring-Up Overrides" "$SYS_PROP"; then
    echo "  -> Appending early-boot ADB debug overrides to /system/build.prop..."
    cat << 'EOF' >> "$SYS_PROP"

# === Project Garnet Bring-Up Overrides ===
ro.adb.secure=0
ro.secure=0
ro.debuggable=1
persist.sys.usb.config=mtp,adb
EOF
    xattr -w security.selinux "u:object_r:system_file:s0" "$SYS_PROP"
fi

mkdir -p "$PORT/config/garnet_overlays_src" "$PORT/product/overlay"
cp -a "$PROJ/configs/reference_garnet/overlay/." "$PORT/config/garnet_overlays_src/"

rm -f "$PORT/product/overlay/DevicesOverlay.apk" "$PORT/product/overlay/DevicesAndroidOverlay.apk"
# Build #6: Do NOT copy Xiaomi DevicesAndroidOverlay.apk (it overrides config_dozeComponent to non-existent MiuiDozeService)

if [[ -d "$SYS_ROOT/my_product/product_overlay" ]]; then
    echo "  -> Merging my_product/product_overlay into /product (Camera SDK & permissions)..."
    cp -R "$SYS_ROOT/my_product/product_overlay/." "$PORT/product/"
    CAM_SDK_XML="$PORT/product/etc/permissions/com.oplus.camera.unit.sdk_product.xml"
    if [[ -f "$CAM_SDK_XML" ]]; then
        python3 - "$CAM_SDK_XML" << 'PYEOF'
import sys
p = sys.argv[1]
txt = open(p, "r", encoding="utf-8").read()
txt = txt.replace('<? xml version = "1.0" encoding = "utf-8" ?>', '<?xml version="1.0" encoding="utf-8"?>')
open(p, "w", encoding="utf-8").write(txt)
PYEOF
    fi
    for d in "$PORT/product/framework" "$PORT/product/framework/oat" "$PORT/product/framework/oat/arm64" "$PORT/product/etc/permissions"; do
        [[ -d "$d" ]] && chmod 0755 "$d" && xattr -w security.selinux "u:object_r:system_file:s0" "$d"
    done
    find "$PORT/product/framework" "$PORT/product/etc/permissions" -type f -name "*camera*" | while read -r f; do
        chmod 0644 "$f"
        xattr -w security.selinux "u:object_r:system_file:s0" "$f"
    done
fi

echo "  -> [Build #4] Patching AudioPolicy QSSI selector & missing-OPPO-HAL AServiceManager_getService stalls..."
python3 - "$PORT" << 'PYEOF'
import os, struct, subprocess, sys

pb = sys.argv[1]
def vma_to_offset(data, vma):
    e_phoff = struct.unpack_from("<Q", data, 32)[0]
    e_phentsize, e_phnum = struct.unpack_from("<HH", data, 54)
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        pt, pf, po, pv, pp, pfs, pms, pa = struct.unpack_from("<IIQQQQQQ", data, off)
        if pt == 1 and pv <= vma < pv + pfs:
            return (vma - pv) + po
    raise RuntimeError(f"VMA 0x{vma:x} not mapped in PT_LOAD")

patches = [
    ("system/system/lib64/libaudiopolicycomponents.so", [
        (0x5bd24, bytes.fromhex("0101939a"), bytes.fromhex("e10313aa")),
        (0x5beb8, bytes.fromhex("0101939a"), bytes.fromhex("e10313aa")),
    ]),
    ("system/system/lib64/oplus_performance_shared.so", [(0xe790, bytes.fromhex("863d0094"), bytes.fromhex("000080d2"))]),
    ("system/system/lib64/liboplusvideoboostservice.so", [(0x1d418, bytes.fromhex("124a0094"), bytes.fromhex("000080d2"))]),
    ("system_ext/lib64/libaudioclientextimpl.so", [(0x19d54, bytes.fromhex("11410094"), bytes.fromhex("000080d2"))]),
    ("system_ext/lib64/libcsextimpl.so", [
        (0x74da0, bytes.fromhex("2c9e0394"), bytes.fromhex("000080d2")),
        (0xdb6f4, bytes.fromhex("d7030294"), bytes.fromhex("000080d2")),
        (0x10f094, bytes.fromhex("6f350194"), bytes.fromhex("000080d2")),
    ]),
    ("system_ext/lib64/lib_inputflingerEx.so", [(0x3b24, bytes.fromhex("7f030094"), bytes.fromhex("000080d2"))]),
    ("system/system/lib64/libcwb_client.so", [(0x6920, bytes.fromhex("880f0094"), bytes.fromhex("000080d2"))]),
    ("system_ext/lib64/libOplusVirtualAudio.so", [(0x7ea4, bytes.fromhex("dd100094"), bytes.fromhex("000080d2"))]),
]

for rel, entries in patches:
    path = os.path.join(pb, rel)
    if not os.path.isfile(path):
        continue
    raw = bytearray(open(path, "rb").read())
    changed = False
    for vma, exp_orig, new_b in entries:
        fo = vma_to_offset(raw, vma)
        cur = bytes(raw[fo:fo+4])
        if cur == new_b:
            continue
        assert cur == exp_orig, f"{rel} @ 0x{vma:x}: unexpected bytes {cur.hex()}"
        raw[fo:fo+4] = new_b
        changed = True
    if changed:
        open(path, "wb").write(raw)
    os.chmod(path, 0o644)
    subprocess.run(["xattr", "-w", "security.selinux", "u:object_r:system_lib_file:s0", path], check=True)
PYEOF

OPLUS_SVC_JAR="$SYS_INNER/framework/oplus-services.jar"
if [[ -f "$OPLUS_SVC_JAR" ]] && command -v apktool >/dev/null 2>&1; then
    echo "  -> [Build #4] Patching OplusBatteryServiceFeature ICharger fallback returns in oplus-services.jar..."
    BATT_TMP="$PORT/boot_work/oplus_batt_patch"
    rm -rf "$BATT_TMP"
    mkdir -p "$BATT_TMP"
    python3 - "$OPLUS_SVC_JAR" "$BATT_TMP" << 'PYEOF'
import sys, zipfile
jar, tmp = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(jar) as zin, zipfile.ZipFile(f"{tmp}/classes_only.jar", "w") as zout:
    data = zin.read("classes.dex")
    zout.writestr("classes.dex", data, compress_type=zipfile.ZIP_STORED)
PYEOF
    apktool d -q -r -f "$BATT_TMP/classes_only.jar" -o "$BATT_TMP/decoded"
    python3 - "$BATT_TMP/decoded/smali/com/android/server/OplusBatteryServiceFeature.smali" << 'PYEOF'
import sys
p = sys.argv[1]
lines = open(p).read().splitlines()
int_fallbacks = {
    ".method public getPsyBatteryNotify()I": ("0x0", "const/4"),
    ".method public getPsyBatteryShortStatus()I": ("0x1", "const/4"),
    ".method public getBattShortIcOtpStatus()I": ("0x1", "const/4"),
    ".method public getPsyUsbStatus()I": ("0x0", "const/4"),
    ".method public getPsyOtgOnline()I": ("0x0", "const/4"),
    ".method public getPsyBatteryRm()I": ("0x0", "const/4"),
    ".method public getPsyBatteryFcc()I": ("0x13ec", "const/16"),
    ".method public getBattPPSChgIng()I": ("0x0", "const/4"),
    ".method public getBattPPSChgPower()I": ("0x0", "const/4"),
    ".method public getBmsHeatingStatus()I": ("0x0", "const/4"),
    ".method public getWirelessAdapterPower()I": ("0x0", "const/4"),
}
out, cur, in_if_nez = [], None, False
for l in lines:
    if l.startswith(".method "):
        cur, in_if_nez = l.strip(), False
        out.append(l); continue
    if l.startswith(".end method"):
        cur, in_if_nez = None, False
        out.append(l); continue
    if cur in (".method public getChgConfig(ILjava/lang/String;I)Ljava/lang/String;", ".method public getNodeData(I)I"):
        if l.strip().startswith("if-nez "): in_if_nez = True
        elif l.strip().startswith(":cond_0"): in_if_nez = False
    if cur in int_fallbacks and l.strip() == "const/4 v0, -0x1":
        val, op = int_fallbacks[cur]
        out.append(f"    {op} v0, {val}"); continue
    if cur == ".method public getChgConfig(ILjava/lang/String;I)Ljava/lang/String;" and in_if_nez and l.strip() == "return-object v0":
        out.extend(["    const/16 v1, 0x1f", "    if-eq p1, v1, :cond_ret_neg1_garnet", '    const-string v0, "0"', "    :cond_ret_neg1_garnet", "    return-object v0"])
        in_if_nez = False; continue
    if cur == ".method public getNodeData(I)I" and in_if_nez and l.strip() == "return v1":
        out.extend(["    const/4 v0, 0x2", "    if-ne p1, v0, :cond_ret0_garnet", "    const/4 v0, 0x1", "    return v0", "    :cond_ret0_garnet", "    const/4 v0, 0x0", "    return v0"])
        in_if_nez = False; continue
    out.append(l)
open(p, "w").write("\n".join(out) + "\n")
PYEOF
    apktool b -q "$BATT_TMP/decoded" -o "$BATT_TMP/rebuilt.jar"
    python3 - "$OPLUS_SVC_JAR" "$BATT_TMP/rebuilt.jar" << 'PYEOF'
import os, sys, zipfile
jar, rebuilt = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(rebuilt) as zr:
    new_dex = zr.read("classes.dex")
tmp_jar = jar + ".tmp"
with zipfile.ZipFile(jar, "r") as zin, zipfile.ZipFile(tmp_jar, "w") as zout:
    for info in zin.infolist():
        zi = zipfile.ZipInfo(filename=info.filename, date_time=info.date_time)
        zi.compress_type = info.compress_type
        zi.external_attr = info.external_attr
        zout.writestr(zi, new_dex if info.filename == "classes.dex" else zin.read(info.filename), compress_type=info.compress_type)
os.replace(tmp_jar, jar)
PYEOF
    rm -f "$OPLUS_SVC_JAR.fsv_meta" "$SYS_INNER/framework/oat/arm64/oplus-services."{odex,vdex,art,odex.fsv_meta,vdex.fsv_meta,art.fsv_meta}
    chmod 0644 "$OPLUS_SVC_JAR"
    xattr -w security.selinux "u:object_r:system_file:s0" "$OPLUS_SVC_JAR"
    rm -rf "$BATT_TMP"
fi

echo "  -> [Build #5] Installing 1220x2712 cutout overlay, resolution config, and garnet_lhbm_helper FOD bridge..."
if [[ -f "$PROJ/configs/garnet_overlays/android_framework_res_overlay.display.product.24019.apk" ]]; then
    cp -f "$PROJ/configs/garnet_overlays/android_framework_res_overlay.display.product.24019.apk" \
        "$SYS_ROOT/my_product/overlay/android_framework_res_overlay.display.product.24019.apk"
    chmod 0644 "$SYS_ROOT/my_product/overlay/android_framework_res_overlay.display.product.24019.apk"
    xattr -w security.selinux "u:object_r:system_file:s0" "$SYS_ROOT/my_product/overlay/android_framework_res_overlay.display.product.24019.apk"
fi
if [[ ! -f "$PROJ/configs/garnet_overlays/garnet-cutout-fix.apk" ]]; then
    echo "ERROR: Missing garnet cutout overlay APK" >&2
    exit 1
fi
cp -f "$PROJ/configs/garnet_overlays/garnet-cutout-fix.apk" "$SYS_ROOT/my_product/overlay/garnet-cutout-fix.apk"
chmod 0644 "$SYS_ROOT/my_product/overlay/garnet-cutout-fix.apk"
xattr -w security.selinux "u:object_r:system_file:s0" "$SYS_ROOT/my_product/overlay/garnet-cutout-fix.apk"
for overlay in island_padding island_statusbar; do
    overlay_apk="garnet-${overlay}.apk"
    if [[ ! -f "$PROJ/configs/garnet_overlays/$overlay_apk" ]]; then
        echo "ERROR: Missing $overlay_apk; build the island overlays first" >&2
        exit 1
    fi
    cp -f "$PROJ/configs/garnet_overlays/$overlay_apk" "$SYS_ROOT/my_product/overlay/$overlay_apk"
    chmod 0644 "$SYS_ROOT/my_product/overlay/$overlay_apk"
    xattr -w security.selinux "u:object_r:system_file:s0" "$SYS_ROOT/my_product/overlay/$overlay_apk"
done
if [[ -f "$SYS_ROOT/my_product/etc/sys_resolution_switch_config.xml" ]]; then
    python3 - "$SYS_ROOT/my_product/etc/sys_resolution_switch_config.xml" << 'PYEOF'
import sys
p = sys.argv[1]
txt = open(p, "r", encoding="utf-8").read().replace('screenwidth="1440"', 'screenwidth="1220"')
open(p, "w", encoding="utf-8").write(txt)
PYEOF
    chmod 0644 "$SYS_ROOT/my_product/etc/sys_resolution_switch_config.xml"
    xattr -w security.selinux "u:object_r:system_file:s0" "$SYS_ROOT/my_product/etc/sys_resolution_switch_config.xml"
fi
if [[ -f "$PROJ/src/garnet_fod/garnet_lhbm_helper.c" ]] && command -v aarch64-elf-gcc >/dev/null 2>&1; then
    aarch64-elf-gcc -O2 -fno-builtin -ffreestanding -nostdlib -static -fPIE -Wl,-e,_start \
        "$PROJ/src/garnet_fod/garnet_lhbm_helper.c" -o "$PROJ/src/garnet_fod/garnet_lhbm_helper"
fi
if [[ -f "$PROJ/src/garnet_fod/garnet_lhbm_helper" ]]; then
    cp -f "$PROJ/src/garnet_fod/garnet_lhbm_helper" "$SYS_INNER/bin/garnet_lhbm_helper"
    chmod 0755 "$SYS_INNER/bin/garnet_lhbm_helper"
    xattr -w security.selinux "u:object_r:system_file:s0" "$SYS_INNER/bin/garnet_lhbm_helper"
fi
VINTF_MANIFEST="$SYS_INNER/etc/vintf/manifest.xml"
if [[ -f "$VINTF_MANIFEST" ]] && ! grep -q "vendor.oplus.hardware.displaypanelfeature" "$VINTF_MANIFEST"; then
    python3 - "$VINTF_MANIFEST" << 'PYEOF'
import sys
p = sys.argv[1]
txt = open(p, "r", encoding="utf-8").read()
entry = """    <hal format="aidl">
        <name>vendor.oplus.hardware.displaypanelfeature</name>
        <fqname>IDisplayPanelFeature/default</fqname>
    </hal>\n"""
anchor = "    <hal format=\"aidl\">\n        <name>vendor.oplus.hardware.hummingbird</name>"
if anchor in txt:
    txt = txt.replace(anchor, entry + anchor, 1)
    open(p, "w", encoding="utf-8").write(txt)
PYEOF
    chmod 0644 "$VINTF_MANIFEST"
    xattr -w security.selinux "u:object_r:system_file:s0" "$VINTF_MANIFEST"
fi

if [[ -f "$OPLUS_SVC_JAR" ]] && [[ -f "$PROJ/src/garnet_fod/GarnetFodHelper.java" ]] && command -v apktool >/dev/null 2>&1; then
    FOD_TMP="$PORT/boot_work/oplus_fod_patch"
    rm -rf "$FOD_TMP" && mkdir -p "$FOD_TMP/classes" "$FOD_TMP/dex"
    AJAR_PATH="/Users/tahaermis/Library/Android/sdk/platforms/android-37.0/android.jar"
    D8_BIN="/Users/tahaermis/Library/Android/sdk/build-tools/36.0.0/d8"
    if [[ -f "$AJAR_PATH" ]] && [[ -x "$D8_BIN" ]]; then
        javac --release 11 -cp "$AJAR_PATH" -d "$FOD_TMP/classes" "$PROJ/src/garnet_fod/GarnetFodHelper.java"
        "$D8_BIN" --lib "$AJAR_PATH" --output "$FOD_TMP/dex" "$FOD_TMP/classes/com/garnet/fod/"*.class
        (cd "$FOD_TMP/dex" && jar cf gf.jar classes.dex && apktool d -q -r -f gf.jar -o "$FOD_TMP/gf_smali")
        python3 - "$OPLUS_SVC_JAR" "$FOD_TMP/classes_only.jar" << 'PYEOF'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as zin, zipfile.ZipFile(sys.argv[2], "w") as zout:
    zout.writestr("classes.dex", zin.read("classes.dex"), compress_type=zipfile.ZIP_STORED)
PYEOF
        apktool d -q -r -f "$FOD_TMP/classes_only.jar" -o "$FOD_TMP/decoded"
        mkdir -p "$FOD_TMP/decoded/smali/com/garnet/fod"
        cp -f "$FOD_TMP/gf_smali/smali/com/garnet/fod/"*.smali "$FOD_TMP/decoded/smali/com/garnet/fod/"
        python3 - "$FOD_TMP/decoded/smali/com/android/server/biometrics/sensors/fingerprint" << 'PYEOF'
import re, sys
base = sys.argv[1]
p_ext = f"{base}/aidl/FingerprintServiceProviderExtImpl.smali"
p_auth = f"{base}/aidl/FingerprintAuthenticationClientAidlExtImpl.smali"
p_udfps = f"{base}/UdfpsHelperExtImpl.smali"
txt = open(p_ext, "r", encoding="utf-8").read()
if "Lcom/garnet/fod/GarnetFodHelper;" not in txt:
    def inject_top(text, sig, lines_to_add):
        idx = text.find(sig)
        assert idx != -1, f"Missing {sig}"
        end_m = text.find("\n.end method", idx)
        m = re.search(r'\n    \.line \d+\n', text[idx:end_m])
        assert m is not None, f"No .line in {sig}"
        ins = idx + m.end()
        while text[ins:].startswith("    .local ") or text[ins:].startswith("\n    .local "):
            ins = text.find("\n", ins + 1) + 1
        return text[:ins] + "\n".join("    " + l for l in lines_to_add) + "\n\n" + text[ins:]
    def inject_before(text, sig, needle, lines_to_add):
        idx = text.find(sig)
        end_m = text.find("\n.end method", idx)
        nidx = text[idx:end_m].find(needle)
        assert nidx != -1, f"Missing '{needle}' in {sig}"
        abs_nidx = idx + nidx
        return text[:abs_nidx] + "\n".join("    " + l for l in lines_to_add) + "\n\n    " + text[abs_nidx:]
    def inject_after(text, sig, needle, lines_to_add):
        idx = text.find(sig)
        end_m = text.find("\n.end method", idx)
        nidx = text[idx:end_m].find(needle)
        assert nidx != -1, f"Missing '{needle}' in {sig}"
        abs_end = idx + nidx + len(needle)
        return text[:abs_end] + "\n\n" + "\n".join("    " + l for l in lines_to_add) + text[abs_end:]

    for s, c in [
        (".method public init(", ["invoke-static {}, Lcom/garnet/fod/GarnetFodHelper;->registerDisplayPanelService()V"]),
        (".method public enrollPreOperation(", ["invoke-static {}, Lcom/garnet/fod/GarnetFodHelper;->onEnrollStart()V"]),
        (".method public authPreOperation(", ["invoke-static {}, Lcom/garnet/fod/GarnetFodHelper;->onAuthStart()V"]),
        (".method public handleOnPointerDown(", ["invoke-static {}, Lcom/garnet/fod/GarnetFodHelper;->onFingerDown()V"]),
        (".method public dispatchTouchDown(", ["invoke-static {}, Lcom/garnet/fod/GarnetFodHelper;->onFingerDown()V"]),
        (".method public handleOnPointerUp(", ["invoke-static {}, Lcom/garnet/fod/GarnetFodHelper;->onFingerUp()V"]),
        (".method public dispatchTouchUp(", ["invoke-static {}, Lcom/garnet/fod/GarnetFodHelper;->onFingerUp()V"]),
        (".method public onAuthenticated(", ["invoke-static/range {p2 .. p2}, Lcom/garnet/fod/GarnetFodHelper;->onAuthResult(I)V"]),
        (".method public onAcquired(", ["invoke-static {p1}, Lcom/garnet/fod/GarnetFodHelper;->onAcquired(I)V"]),
    ]:
        txt = inject_top(txt, s, c)
    txt = inject_after(txt, ".method public handleCancelAuthentication(", "sput-boolean v1, Lcom/android/server/biometrics/sensors/fingerprint/UdfpsHelperExtImpl;->sRealUdfpsIconShow:Z", ["invoke-static {}, Lcom/garnet/fod/GarnetFodHelper;->onOverlayHide()V"])
    txt = inject_after(txt, ".method public handleCancelEnrollment(", "sput-boolean v1, Lcom/android/server/biometrics/sensors/fingerprint/UdfpsHelperExtImpl;->sRealUdfpsIconShow:Z", ["invoke-static {}, Lcom/garnet/fod/GarnetFodHelper;->onOverlayHide()V"])
    txt = inject_before(txt, ".method public hideFingerprintIcon(", "invoke-virtual {v1, v2}, Lcom/android/server/biometrics/sensors/SensorOverlays;->hide(I)V", ["invoke-static {}, Lcom/garnet/fod/GarnetFodHelper;->onOverlayHide()V"])
    txt = inject_before(txt, ".method public showFingerprintIcon(", "invoke-virtual {v2, v3, v1, v4}, Lcom/android/server/biometrics/sensors/SensorOverlays;->show(IILcom/android/server/biometrics/sensors/AcquisitionClient;)V", ["invoke-static {}, Lcom/garnet/fod/GarnetFodHelper;->onOverlayShow()V"])
    open(p_ext, "w", encoding="utf-8").write(txt)

    txt_auth = open(p_auth, "r", encoding="utf-8").read()
    txt_auth = inject_top(txt_auth, ".method public startHalOperation(", ["invoke-static {}, Lcom/garnet/fod/GarnetFodHelper;->onAuthStart()V"])
    txt_auth = inject_top(txt_auth, ".method public onAuthenticated(", ["invoke-static {}, Lcom/garnet/fod/GarnetFodHelper;->onFingerUp()V"])
    open(p_auth, "w", encoding="utf-8").write(txt_auth)

    txt_udfps = open(p_udfps, "r", encoding="utf-8").read()
    txt_udfps = inject_after(txt_udfps, ".method public preHideUdfpsOverlay()V", "if-eqz v0, :cond_1", ["invoke-static {}, Lcom/garnet/fod/GarnetFodHelper;->onOverlayHide()V"])
    txt_udfps = inject_after(txt_udfps, ".method public preShowUdfpsOverlay(II)V", "if-ne p2, v0, :cond_1", ["invoke-static {}, Lcom/garnet/fod/GarnetFodHelper;->onOverlayShow()V"])
    txt_udfps = inject_top(txt_udfps, ".method public writeLcdHighLightPath(I)V", ["invoke-static {p1}, Lcom/garnet/fod/GarnetFodHelper;->onHighLight(I)V"])
    open(p_udfps, "w", encoding="utf-8").write(txt_udfps)
PYEOF
        apktool b -q "$FOD_TMP/decoded" -o "$FOD_TMP/rebuilt.jar"
        python3 - "$OPLUS_SVC_JAR" "$FOD_TMP/rebuilt.jar" << 'PYEOF'
import os, sys, zipfile
jar, rebuilt = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(rebuilt) as zr:
    new_dex = zr.read("classes.dex")
tmp_jar = jar + ".tmp"
with zipfile.ZipFile(jar, "r") as zin, zipfile.ZipFile(tmp_jar, "w") as zout:
    for info in zin.infolist():
        zi = zipfile.ZipInfo(filename=info.filename, date_time=info.date_time)
        zi.compress_type = info.compress_type
        zi.external_attr = info.external_attr
        zout.writestr(zi, new_dex if info.filename == "classes.dex" else zin.read(info.filename), compress_type=info.compress_type)
os.replace(tmp_jar, jar)
PYEOF
        rm -f "$OPLUS_SVC_JAR.fsv_meta" "$SYS_INNER/framework/oat/arm64/oplus-services."{odex,vdex,art,odex.fsv_meta,vdex.fsv_meta,art.fsv_meta}
        chmod 0644 "$OPLUS_SVC_JAR"
        xattr -w security.selinux "u:object_r:system_file:s0" "$OPLUS_SVC_JAR"
    fi
    rm -rf "$FOD_TMP"
fi

echo "=== [6/7] Patching garnet vendor_boot.img (fstab AVB + permissive SELinux) ==="
BOOT_WORK="$PORT/boot_work/vendor_boot"
rm -rf "$BOOT_WORK"
mkdir -p "$BOOT_WORK"
cp -f "$GARNET_IMG/vendor_boot.img" "$BOOT_WORK/vendor_boot.img"
(
    cd "$BOOT_WORK"
    magiskboot unpack -h vendor_boot.img
    if [[ -f ramdisk.cpio ]]; then
        if magiskboot decompress ramdisk.cpio ramdisk_dec.cpio 2>/dev/null; then
            RAMDISK_CPIO="ramdisk_dec.cpio"
            WAS_LZ4=1
        else
            RAMDISK_CPIO="ramdisk.cpio"
            WAS_LZ4=0
        fi
        if magiskboot cpio "$RAMDISK_CPIO" "exists first_stage_ramdisk/fstab.qcom" 2>/dev/null; then
            echo "  -> Patching AVB/verity flags in first_stage_ramdisk/fstab.qcom via magiskboot cpio..."
            magiskboot cpio "$RAMDISK_CPIO" "extract first_stage_ramdisk/fstab.qcom fstab.qcom"
            python3 - fstab.qcom << 'PYEOF'
import re, sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8", errors="replace") as f:
    text = f.read()
lines = []
for line in text.splitlines(True):
    if re.match(r"^(system|system_ext|product|vendor|vendor_dlkm|odm)\b", line):
        line = re.sub(r",avb_keys=[^,\s]+", "", line)
        line = re.sub(r",avb=[^,\s]+", "", line)
        line = re.sub(r",avb(?=[,\s]|$)", "", line)
    lines.append(line)
with open(path, "w", encoding="utf-8") as f:
    f.writelines(lines)
PYEOF
            magiskboot cpio "$RAMDISK_CPIO" "add 0644 first_stage_ramdisk/fstab.qcom fstab.qcom"
            rm -f fstab.qcom
        fi
        if [[ "$WAS_LZ4" -eq 1 ]]; then
            magiskboot compress=lz4_legacy "$RAMDISK_CPIO" ramdisk.cpio
            rm -f "$RAMDISK_CPIO"
        fi
    fi
    if [[ -f header ]]; then
        if ! grep -q "androidboot.selinux=permissive" header; then
            python3 - header << 'PYEOF'
import sys
p = sys.argv[1]
txt = open(p, "r").read().splitlines()
out = []
for line in txt:
    if line.startswith("cmdline=") and "androidboot.selinux=permissive" not in line:
        line = line + " androidboot.selinux=permissive"
    out.append(line)
open(p, "w").write("\n".join(out) + "\n")
PYEOF
        fi
    fi
    magiskboot repack vendor_boot.img vendor_boot_patched.img
)
cp -f "$BOOT_WORK/vendor_boot_patched.img" "$PORT/stock_images/vendor_boot.img"

echo "=== [7/7] Generating disabled-verity vbmeta images ==="
avbtool make_vbmeta_image --flags 3 --padding_size 4096 --output "$PORT/stock_images/vbmeta.img"
avbtool make_vbmeta_image --flags 3 --padding_size 4096 --output "$PORT/stock_images/vbmeta_system.img"

echo "Merge and patch staging complete in $PORT."
