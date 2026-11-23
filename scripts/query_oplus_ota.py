#!/usr/bin/env python3
"""
Query OPPO/Oplus official OTA v5 server for full OTA download URLs.
Useful for fetching fresh, active CDN links (e.g., for OPPO Find X8 Ultra PKJ110).
"""

import argparse
import base64
import json
import os
import sys
import time
from Crypto.Cipher import AES, PKCS1_OAEP
from Crypto.Hash import SHA1
from Crypto.PublicKey import RSA
from Crypto.Random import get_random_bytes
from Crypto.Util import Counter
import requests

PUBLIC_KEY_CN = """-----BEGIN RSA PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEApXYGXQpNL7gmMzzvajHa
oZIHQQvBc2cOEhJc7/tsaO4sT0unoQnwQKfNQCuv7qC1Nu32eCLuewe9LSYhDXr9
KSBWjOcCFXVXteLO9WCaAh5hwnUoP/5/Wz0jJwBA+yqs3AaGLA9wJ0+B2lB1vLE4
FZNE7exUfwUc03fJxHG9nCLKjIZlrnAAHjRCd8mpnADwfkCEIPIGhnwq7pdkbamZ
coZfZud1+fPsELviB9u447C6bKnTU4AaMcR9Y2/uI6TJUTcgyCp+ilgU0JxemrSI
PFk3jbCbzamQ6Shkw/jDRzYoXpBRg/2QDkbq+j3ljInu0RHDfOeXf3VBfHSnQ66H
CwIDAQAB
-----END RSA PUBLIC KEY-----"""


def aes_ctr_crypt(data: bytes, key: bytes, iv: bytes) -> bytes:
    ctr = Counter.new(128, initial_value=int.from_bytes(iv, byteorder="big"))
    cipher = AES.new(key, AES.MODE_CTR, counter=ctr)
    return cipher.encrypt(data)


def query_oplus_ota(model: str, ota_version: str, mode: str = "manual", nv_carrier: str = "10010111") -> dict:
    iv = get_random_bytes(16)
    key = get_random_bytes(32)
    rsa_key = RSA.import_key(PUBLIC_KEY_CN)
    cipher_rsa = PKCS1_OAEP.new(rsa_key, hashAlgo=SHA1)
    # OplusUpdater encrypts base64(key) with RSA-OAEP
    key_b64 = base64.b64encode(key)
    protected_key = base64.b64encode(cipher_rsa.encrypt(key_b64)).decode("ascii")
    version_ts = str(int((time.time() + 86400) * 1e9))

    pkm = {
        "SCENE_1": {
            "protectedKey": protected_key,
            "version": version_ts,
            "negotiationVersion": "1615879139745",
        }
    }
    device_id = "0" * 64
    headers = {
        "language": "zh-CN",
        "androidVersion": "unknown",
        "colorOSVersion": "unknown",
        "romVersion": "unknown",
        "otaVersion": ota_version,
        "model": model,
        "mode": mode,
        "nvCarrier": nv_carrier,
        "infVersion": "1",
        "version": "2",
        "deviceId": device_id,
        "protectedKey": json.dumps(pkm, separators=(",", ":")),
        "Content-Type": "application/json; charset=utf-8",
    }

    inner_payload = json.dumps({
        "mode": "0",
        "time": int(time.time() * 1000),
        "isRooted": "0",
        "isLocked": True,
        "type": "0",
        "deviceId": device_id,
        "opex": {"check": True},
    }, separators=(",", ":")).encode("utf-8")

    req_body_inner = json.dumps({
        "cipher": base64.b64encode(aes_ctr_crypt(inner_payload, key, iv)).decode("ascii"),
        "iv": base64.b64encode(iv).decode("ascii"),
    }, separators=(",", ":"))

    resp = requests.post(
        "https://component-ota-cn.allawntech.com/update/v5",
        headers=headers,
        json={"params": req_body_inner},
        timeout=20,
    )
    resp.raise_for_status()
    res = resp.json()
    if isinstance(res.get("body"), str):
        body_wrap = json.loads(res["body"])
        r_iv = base64.b64decode(body_wrap["iv"])
        r_cipher = base64.b64decode(body_wrap["cipher"])
        decrypted = aes_ctr_crypt(r_cipher, key, r_iv).decode("utf-8", errors="replace")
        try:
            res["body"] = json.loads(decrypted)
        except json.JSONDecodeError:
            res["body"] = decrypted
    return res


def resolve_download_gate(url: str) -> str:
    """Resolve component-ota-*.allawntech.com/downloadCheck to a direct CDN URL."""
    if "/downloadCheck" not in url:
        return url
    resp = requests.get(
        url,
        headers={
            "userId": "oplus-ota|16001011",
            "User-Agent": "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
            "Accept": "*/*",
        },
        allow_redirects=False,
        timeout=20,
    )
    if 300 <= resp.status_code < 400 and "Location" in resp.headers:
        return resp.headers["Location"]
    return url


def main():
    parser = argparse.ArgumentParser(description="Query OPPO CN OTA server for a model/otaVersion")
    parser.add_argument("--model", default="PKJ110", help="Model code (default: PKJ110)")
    parser.add_argument("--ota-version", default="PKJ110_11.F.01_0001_197001010000", help="Baseline OTA version string")
    parser.add_argument("--mode", default="manual", choices=["manual", "server_auto", "client_auto", "taste"])
    parser.add_argument("--url-only", action="store_true", help="Print only the resolved CDN download URL")
    args = parser.parse_args()

    res = query_oplus_ota(args.model, args.ota_version, args.mode)
    try:
        components = res.get("body", {}).get("components", [])
        if components:
            packets = components[0].get("componentPackets", {})
            raw_url = packets.get("url") or packets.get("manualUrl")
            if raw_url:
                resolved = resolve_download_gate(raw_url)
                packets["resolved_cdn_url"] = resolved
                if args.url_only:
                    print(resolved)
                    return
    except Exception as exc:
        if args.url_only:
            print(f"ERROR: {exc}", file=sys.stderr)
            sys.exit(1)

    if args.url_only:
        print("ERROR: No download URL returned by OPPO OTA server", file=sys.stderr)
        sys.exit(1)

    print(json.dumps(res, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
