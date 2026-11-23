# Compatibility

Status reflects what the developer tested on one Xiaomi Redmi Note 13 Pro 5G (`garnet`) unit with
the images listed in [INSTALLATION.md](INSTALLATION.md). Nothing here is officially supported, and
this port is **not** bug-free. "Verified working" means confirmed on device by the developer; it is
not a guarantee across other units, regions, or untested workloads.

## Verified working (developer-confirmed)

| Feature | Notes |
|---|---|
| Boot & daily use | ColorOS 17 boots on `garnet`; smooth daily use reported by the developer (subject to further regression testing) |
| Fingerprint (optical FOD) | Unlock plus press animation on the awake lock screen; AOD is excluded from the animation patch |
| Double-tap to wake | Worked without any change |
| Always-On Display (AOD) | Working |
| Wake / AOD flicker | Fixed, see [fixes/01](fixes/01-wake-aod-flicker.md) |
| Bluetooth | Pairing and audio |
| Speaker / microphone | |
| NFC | |
| Auto-brightness | |
| Refresh rate | 60 / 90 / 120 Hz |
| Proximity sensor, auto-rotation | |
| Torch | |
| USB-C audio, OTG | |
| GPS | |
| Wi-Fi 5 GHz | |
| Charging | Wired |
| Camera | Works in the apps tried; not exhaustively tested |

## Fix applied, pending verification

| Feature | Notes |
|---|---|
| Vibration / vibrate mode | [fixes/03](fixes/03-vibration.md). Some Oplus haptic effect IDs may not map to the Xiaomi HAL |
| App lock (privacy password) | [fixes/04](fixes/04-app-lock-cryptoeng.md). Software stand-in with limitations |
| Dynamic Island size | Reduced to a modest size (120 px capsule, 135 px status bar); a screenshot looks reasonable, awaiting the author's visual confirmation |

## Known limitations (not working)

| Feature | Reason |
|---|---|
| Face unlock | Unavailable because a compatible face HAL implementation was not found in the ColorOS donor or stock `garnet` vendor |

## Untested / subject to regression testing

| Feature | Reason |
|---|---|
| Cellular / SIM / calls / mobile data / VoLTE | The developer's IMEI is out of registration, so it could not be tested |
| Anything else not listed above (e.g. HDR video, video recording modes, eSIM, IR, secondary cameras, long-term stability) | Not exhaustively checked; subject to further regression testing |

## Not applicable

| Feature | Reason |
|---|---|
| Wireless charging | Hardware is not present on this device |

## Known caveats

- SELinux is **permissive** in this build.
- The build is signed with test/debug keys for the added overlays; verified boot state is `orange`
  (unlocked bootloader).
- "About device" shows the donor branding (`OPPO Find X8 Ultra by YetUnseen`) because the ROM
  properties come from the donor build.
