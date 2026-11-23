#!/usr/bin/env bash
set -euo pipefail

PROJ="/Users/tahaermis/Desktop/ColorOS17-Garnet"
DL_DIR="$PROJ/downloads"
mkdir -p "$DL_DIR"

export PATH="$PROJ/tools/bin:/opt/homebrew/bin:$PATH"

GARNET_TGZ_URL="https://bkt-sgp-miui-ota-update-alisgp.oss-ap-southeast-1.aliyuncs.com/OS3.0.306.0.WNRCNXM/garnet_images_OS3.0.306.0.WNRCNXM_20260715.0000.00_16.0_cn_0f51515e4e.tgz"
GARNET_TGZ_NAME="garnet_images_OS3.0.306.0.WNRCNXM_16.0_cn.tgz"
GARNET_TGZ="$DL_DIR/$GARNET_TGZ_NAME"
GARNET_MD5="0f51515e4e9125ea5ab4fbdf058cad74"

PKJ_ZIP_NAME="PKJ110_ColorOS17_CN.zip"
PKJ_ZIP="$DL_DIR/$PKJ_ZIP_NAME"
PKJ_LATEST_GATE="https://component-ota-cn.allawntech.com/downloadCheck?c=d59daed9cc4881a8dea26ef8d2447224&p=a6c78fdd3654888b38cedca9119f37669578fbb4496254f184bb03b9c32f05c7b8ea62d3e57d6576bb38d3282179&d=e181cd82745f88956e8098ec0182623bca30a2a51b7b03ead6e04ce9ca7400d5b4e921c5b4276d&g=10eab6008d5642cf42abd2aa41f847cb&id=6af3a9a2350d39017fff3d6c&taste=1&supportDLTaste=0&mode=1&tr=manual&s=8f6246b0573e5363e4e18afd877a57ba"

echo "[1/2] Downloading Redmi Note 13 Pro 5G (garnet) China HyperOS 3 Fastboot TGZ (OS3.0.306.0.WNRCNXM)..."
aria2c -c -x 16 -s 16 -k 1M --max-tries=20 --retry-wait=5 \
    --summary-interval=30 --console-log-level=notice \
    -d "$DL_DIR" -o "$GARNET_TGZ_NAME" "$GARNET_TGZ_URL"

echo "Verifying Garnet TGZ MD5..."
ACTUAL_GARNET_MD5=$(md5 -q "$GARNET_TGZ")
if [[ "$ACTUAL_GARNET_MD5" != "$GARNET_MD5" ]]; then
    echo "ERROR: Garnet MD5 mismatch! Expected $GARNET_MD5, got $ACTUAL_GARNET_MD5" >&2
    exit 1
fi
echo "Garnet Fastboot TGZ verified OK ($ACTUAL_GARNET_MD5)."

echo "[2/2] Resolving and downloading OPPO Find X8 Ultra (PKJ110) ColorOS 17 China..."
PKJ_CDN_URL=$(curl -sI -H "userId: oplus-ota|16001011" "$PKJ_LATEST_GATE" | awk '/^[Ll]ocation:/ {print $2}' | tr -d '\r' || true)
if [[ -z "${PKJ_CDN_URL:-}" ]]; then
    echo "Falling back to live OPPO OTA query for PKJ110_17.0.0.104(CN01)..."
    PKJ_CDN_URL=$("$PROJ/.venv/bin/python" "$PROJ/scripts/query_oplus_ota.py" --model PKJ110 --ota-version "PKJ110_11.F.01_0001_197001010000" --url-only)
fi

HTTP_STATUS=$(curl -sI -H "userId: oplus-ota|16001011" -r 0-0 "$PKJ_CDN_URL" | awk 'NR==1 {print $2}')
if [[ "$HTTP_STATUS" != "200" && "$HTTP_STATUS" != "206" ]]; then
    ALT_URL="${PKJ_CDN_URL/gauss-compota-c-cn.allawnfs.com/gauss-compotaauto-c-cn.allawnfs.com}"
    ALT_STATUS=$(curl -sI -H "userId: oplus-ota|16001011" -r 0-0 "$ALT_URL" | awk 'NR==1 {print $2}')
    if [[ "$ALT_STATUS" == "200" || "$ALT_STATUS" == "206" ]]; then
        echo "Switched PKJ110 CDN host to gauss-compotaauto-c-cn.allawnfs.com (HTTP $ALT_STATUS)."
        PKJ_CDN_URL="$ALT_URL"
    fi
fi

echo "Downloading PKJ110 ColorOS 17 from resolved CDN via aria2c..."
aria2c -c -x 16 -s 16 -k 1M --max-tries=20 --retry-wait=5 \
    --summary-interval=30 --console-log-level=notice \
    --header="userId: oplus-ota|16001011" \
    -d "$DL_DIR" -o "$PKJ_ZIP_NAME" "$PKJ_CDN_URL"

echo "Downloads complete in $DL_DIR:"
ls -lh "$DL_DIR"
