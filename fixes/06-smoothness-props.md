# Smoothness and refresh properties

**Status: applied; refresh rates 60/90/120 Hz confirmed working by the author.**

| Property / change | Purpose |
|---|---|
| `debug.sf.set_idle_timer_ms 0` (set early in init) | Logs showed SurfaceFlinger switching 60→30→60 Hz about every 1.15 s; disabling the idle timer stopped it. Normal-use flicker improved (confirmed). |
| `persist.sys.oplus.anim_level=2` | ColorOS animation level |
| render turbo, texture optimize props | Rendering smoothness tweaks |
| nandswap / hybridswap disabled | Not supported on this storage/kernel setup |

These are build-time property settings applied by `scripts/03_merge_and_patch_port.sh`. Their
individual performance impact was not benchmarked.
