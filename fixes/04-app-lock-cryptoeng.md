# App lock (privacy password) via software cryptoeng

**Status: fix applied, pending verification.**

## Symptom
Settings / SafeCenter could not set a privacy password (app lock).

## Cause
The privacy password goes through `CryptoEngManager` →
`vendor.oplus.hardware.cryptoeng.ICryptoeng/default`. That HAL does not exist on this device.
File-based encryption is active, so "device not encrypted" was not the cause.

## Change
`GarnetCryptoEng` is a software stand-in implementing the PMS commands 4001-4007. It is registered
with `ServiceManager.addService`, and a VINTF manifest entry was added to
`/system/etc/vintf/manifest.xml`. State is stored in `/data/system/garnet_pms.dat`.

## Files
- `src/garnet_fod/GarnetCryptoEng.java` (built into `oplus-services.jar`)
- `/system/etc/vintf/manifest.xml` (entry added)

## Limitations (not equivalent to the hardware-backed original)
- No brute-force lockout; retry count fixed at 5.
- No online / email password reset.
- Command 4006 (ENCRYPT) is not implemented.
- Stored in software; not hardware-protected. Do not treat it as strong security.
