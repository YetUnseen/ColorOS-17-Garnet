# Island / cutout overlays

**Status: cutout fix confirmed; island size fix applied, looks reasonable in screenshots, awaiting
the author's visual confirmation.**

## Symptoms
1. An extra second punch-hole was drawn (fixed, confirmed).
2. The Dynamic Island looked like it was moved rather than thicker, and the physical camera
   interrupted its top edge.
3. Then the 175 px / 165 px candidates made the island a huge "bagel" around the camera.

## How the island is sized
The ColorOS plugin (`com.oplus.systemui.plugins`, `SystemUIPlugin.apk`) container height is
`clamp(max(capsule_layout_max_height, capsule_hole_safe_height_gap + holeHeight), statusBarHeight - 3)`,
centred on the hole centre. `capsule_max_height_size` caps the visible capsule thickness. Hole
property: `ro.oplus.display.screenhole.positon=568,18:652,128`. At 480 dpi, 1 dp = 3 px.

Stock plugin values: `capsule_max_height_size` 30 dp (90 px), `_high` 33 dp (99 px),
`capsule_hole_safe_height_gap` 4 dp (12 px), status bar 122 px.

## Final values (current)
| Overlay | Resource | Value |
|---|---|---|
| `com.garnet.overlay.islandpadding` (target `com.oplus.systemui.plugins`) | `capsule_hole_safe_height_gap` | 5 dp |
| | `capsule_max_height_size`, `_high` | 120 px |
| `com.garnet.overlay.islandstatusbar` | `status_bar_height_portrait`, `_default` (also sw320/360/411dp) | 135 px |
| `cutout_fix` | `config_fillMainBuiltInDisplayCutout` | false |

Measured on device: status bar frame `[0,0][1220,135]`, island container 125 px (y 10-135), visible
capsule about 322 x 118-120 px with media playing. The earlier 165 px build gave a 168 px status
bar and a capsule spanning y 3-168. See `screenshots/island-capsule-crop.png`.

## Files
- `configs/garnet_overlays/island_padding/`, `island_statusbar/`, `cutout_fix/`
- Earlier candidates: `island_165_test/`, `island_175_test/`
- Build: `scripts/build_garnet_island_overlays.sh`, `scripts/build_garnet_cutout_overlay.sh`
  (signed with a local debug key, `--no-resource-deduping`)
- Output: `configs/garnet_overlays/garnet-island_{padding,statusbar}.apk`, installed in `/my_product/overlay/`

## Notes
Status bar height changes affect all apps' top inset. If content looks clipped or too low, adjust
the 135 px value. `cmd overlay list` may report `STATE_NO_IDMAP` for the statusbar overlay while it
is still enabled and effective.
