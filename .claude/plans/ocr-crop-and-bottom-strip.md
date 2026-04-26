# Plan: Fix OCR Crop + Bottom-Strip Recognition

## Evidence from debug log

```
[Scanner] OCR text:
Tech
Repo's
Dn Infra/Devops
Q Search for
Sol Ring
```

Background content ("Tech", "Repo's", etc.) appears *before* the card name — meaning the crop is not applied.  
Set code and collector number are absent entirely — the OCR doesn't reach that part of the card.

---

## Root Cause 1 — Crop is silently skipped on iOS

The crop code is guarded by `image.planes.length == 1`, assuming iOS sends BGRA.  
In practice, the `flutter/camera` plugin on iOS delivers frames in
`kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange` (**NV12**, 2 planes):
- Plane 0 — full-resolution Y (luma)
- Plane 1 — half-resolution interleaved UV (chroma)

Because `planes.length == 2`, the code falls through to the *multi-plane path*,
which concatenates all plane bytes and passes the full image to ML Kit — no crop.

**Confirmation step**: add `debugPrint` of `image.planes.length` and `image.format.raw` to verify.

### Fix: replace byte-crop with ML Kit bounding-box filtering

Cropping raw NV12 bytes (Y plane + UV plane at ½ resolution, both potentially row-padded)
is error-prone and platform-specific. A simpler, format-agnostic alternative:

1. Keep passing the full image to ML Kit (as today).
2. After `processImage`, filter `recognizedText.blocks` to only those whose
   `boundingBox` intersects the viewfinder rectangle **in image coordinates**.
3. Reconstruct the text string from surviving blocks only.

This works for BGRA, NV12, NV21, and any future format.

**Key mapping needed** (already partially implemented in `_viewfinderInNativeCoords`):
- Compute the viewfinder Rect in portrait-image pixel space
  (using FittedBox.cover maths + screen size).
- ML Kit reports `TextBlock.boundingBox` in the coordinate space of the
  *bytes as passed* (before internal rotation).  For NV12 on iOS with
  `sensorOrientation = 90`, that is the **native landscape** frame.
- The existing portrait→native coordinate mapping should therefore be correct;
  confirm by logging a few bounding boxes against the expected viewfinder rect.

---

## Root Cause 2 — Set code / collector number not read by OCR

Even once the crop is fixed the bottom strip may still be missed.  Two sub-causes:

### 2a. Bottom of card may be outside the viewfinder frame
The current viewfinder height is `cardW / (63/88)` which is the full card height.
On a typical ~390 pt wide screen: `cardW = 293 pt`, `cardH = 404 pt`.
The bottom strip occupies roughly the bottom **8 %** of the card height (~32 pt on screen).
If the card doesn't sit perfectly inside the frame, this strip is cut off.

**Fix**: expand the viewfinder height by ~10 % (or add a small padding to the bottom edge
of the crop rect) to ensure the bottom strip is always captured.

### 2b. Small text at `ResolutionPreset.high` may still be marginal
At 1920×1080, the card bottom strip maps to roughly 90 native pixels tall (landscape).
ML Kit can read it, but only if the card is well-lit and reasonably parallel to the lens.

**Fix**: run a *second dedicated OCR pass* on just the bottom 15 % of the card crop.
Use the same `InputImage.fromBytes` path but with a tighter crop so ML Kit focuses its
attention on the densest small-text region.  Merge results with the full-card pass.

---

## Implementation Plan

### Step 1 — Diagnose (no UI change, just logging)

In `scanner_controller.dart › _onFrame`:
```dart
debugPrint('[Scanner] img fmt=${image.format.raw} planes=${image.planes.length}');
```
Run once, confirm `planes=2` on iOS.

### Step 2 — Bounding-box filter (replaces byte-crop)

**`scanner_controller.dart`**

1. Remove `_cropBgra` method.
2. In `_toInputImage`, revert to the original single code path (no crop attempt).
3. Add `_viewfinderInPortraitCoords(CameraImage)` → `Rect?` that returns the viewfinder
   in **portrait image coordinates** (stop before the portrait→native rotation step).
   ML Kit on iOS with `InputImageRotation.rotation90deg` reports bounding boxes already
   in a portrait-equivalent space — verify this empirically with the Step 1 log.
4. In `_analyseFrame`, after `processImage`:
   ```dart
   final roi = _viewfinderInPortraitCoords(image);
   final raw = roi != null
       ? _filterByRoi(recognizedText.blocks, roi)
       : recognizedText.text.trim();
   ```
5. Implement `_filterByRoi`:
   ```dart
   String _filterByRoi(List<TextBlock> blocks, Rect roi) =>
       blocks
           .where((b) => b.boundingBox != null && roi.overlaps(b.boundingBox!))
           .map((b) => b.text)
           .join('\n')
           .trim();
   ```

**Open question before coding Step 2**: determine empirically whether ML Kit returns
bounding boxes in native-landscape coords or in post-rotation portrait coords.
Log `block.boundingBox` for a known card and compare to expected image dimensions.

### Step 3 — Extend viewfinder bottom padding

**`scan_overlay.dart` + `scanner_controller.dart`**

Add a shared constant (or pass a parameter) for a bottom padding factor, e.g. `0.05`
(5 % of card height extra at the bottom). Apply to both the painted `cardRect` and the
crop/filter rect so they stay in sync.

### Step 4 — Dedicated bottom-strip OCR pass

**`scanner_controller.dart › _analyseFrame`**

After the full-card pass, if `hints?.setCode == null || hints?.collectorNumber == null`:
1. Compute the bottom-15%-of-card sub-rect in image coordinates.
2. Create a second `InputImage` cropped to that rect (NV12 Y-plane crop is simpler for
   a horizontal strip: copy the last N rows of each plane).
3. Run `_recognizer.processImage(bottomStripImage)`.
4. Call `OcrExtractor.extract` on the result and merge the extra fields into `hints`.

This ensures the bottom strip gets full ML Kit attention even if it returned no blocks
in the full-card pass.

---

## Coordinate System Reference

For iOS back camera (`sensorOrientation = 90`, NV12, 2 planes):

```
Native frame (landscape)    After ML Kit rotation90deg → portrait
  image.width  = 1920             portrait_width  = 1080
  image.height = 1080             portrait_height = 1920

portrait (xp, yp) → native (xn, yn) = (image.width - 1 - yp, xp)

Viewfinder in portrait (example, 390 pt screen):
  lp = 90 px, tp = 263 px, rp = 630 px, bp = 1017 px  (portrait pixels)

Same in native:
  native_left   = image.width - bp  = 1920 - 1017 = 903
  native_top    = lp                = 90
  native_right  = image.width - tp  = 1920 - 263  = 1657
  native_bottom = rp                = 630
```

---

## Files to change

| File | Change |
|------|--------|
| `scanner_controller.dart` | Add ROI filter; keep full-image ML Kit path; add bottom-strip pass |
| `scan_overlay.dart` | Extract viewfinder rect constants; add bottom padding |
| `ocr_extractor.dart` | Already improved (two-pass collector + set-code); no changes expected |

---

## Success criteria

1. `[Scanner] OCR text` contains only content from inside the drawn frame — no background text.
2. When a card with a visible bottom strip is held in the viewfinder, the OCR text includes
   the collector number (e.g., `182/281`) and a 3-char set code (e.g., `MKM`).
3. Stability check reaches 3/3 on a well-lit card within 2–3 seconds.
