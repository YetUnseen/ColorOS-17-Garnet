#!/usr/bin/env bash
set -euo pipefail

PROJ="$(cd "$(dirname "$0")/.." && pwd)"
: "${ANDROID_BUILD_TOOLS:?Set ANDROID_BUILD_TOOLS to the Android build-tools directory}"
: "${GARNET_OVERLAY_KEYSTORE:?Set GARNET_OVERLAY_KEYSTORE to the signing keystore}"
: "${GARNET_OVERLAY_KEY_ALIAS:?Set GARNET_OVERLAY_KEY_ALIAS to the signing key alias}"
: "${GARNET_OVERLAY_STORE_PASSWORD:?Set GARNET_OVERLAY_STORE_PASSWORD}"
: "${GARNET_OVERLAY_KEY_PASSWORD:?Set GARNET_OVERLAY_KEY_PASSWORD}"
export GARNET_OVERLAY_STORE_PASSWORD GARNET_OVERLAY_KEY_PASSWORD

FRAMEWORK="$PROJ/mnt_workspace/port_build/system/system/framework/framework-res.apk"
TMP="$(mktemp -d)"
trap 'rm -f "$TMP/resources.zip" "$TMP/unsigned.apk" "$TMP/aligned.apk" "$TMP/signed.apk"; rmdir "$TMP"' EXIT

for name in island_padding island_statusbar; do
    SRC="$PROJ/configs/garnet_overlays/$name"
    OUT="$PROJ/configs/garnet_overlays/garnet-$name.apk"
    "$ANDROID_BUILD_TOOLS/aapt2" compile --dir "$SRC/res" -o "$TMP/resources.zip"
    "$ANDROID_BUILD_TOOLS/aapt2" link --no-resource-deduping -I "$FRAMEWORK" --manifest "$SRC/AndroidManifest.xml" \
        --min-sdk-version 29 --target-sdk-version 37 -o "$TMP/unsigned.apk" "$TMP/resources.zip"
    "$ANDROID_BUILD_TOOLS/zipalign" -f 4 "$TMP/unsigned.apk" "$TMP/aligned.apk"
    "$ANDROID_BUILD_TOOLS/apksigner" sign --ks "$GARNET_OVERLAY_KEYSTORE" \
        --ks-key-alias "$GARNET_OVERLAY_KEY_ALIAS" --ks-pass env:GARNET_OVERLAY_STORE_PASSWORD \
        --key-pass env:GARNET_OVERLAY_KEY_PASSWORD --v4-signing-enabled false \
        --out "$TMP/signed.apk" "$TMP/aligned.apk"
    "$ANDROID_BUILD_TOOLS/apksigner" verify "$TMP/signed.apk"
    cp "$TMP/signed.apk" "$OUT"
done
