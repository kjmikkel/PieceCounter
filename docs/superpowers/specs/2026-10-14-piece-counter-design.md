# PieceCounter — Design Spec

**Date:** 2026-10-14
**Status:** Approved in brainstorming, pending written-spec review
**Target device:** Samsung Galaxy S23 Ultra (SM-S918B)

## 1. Purpose

After playing a board game away from home, the owner wants to verify that no
components were lost by counting pieces and comparing against the manual.
Counting by hand is slow. PieceCounter counts game pieces (wooden pieces,
cardboard tiles) spread out on a surface from a single photo, per colour type,
and shows a numbered overlay so the count can be verified by eye.

**Success criteria**

- On the golden photo set (section 8), every type's final count is correct
  after at most a few correction taps per photo.
- The numbered overlay lets the user find any missed or double-counted piece.
- Fully offline and on-device; no account, no network.

## 2. Requirements

### Stated by the user

- Take a photo with the built-in camera; the subject is a flat surface.
- Pieces lie on the surface, not touching (not always perfectly achieved —
  see section 5), in no particular arrangement.
- Other objects in the shot may be counted too; that is accepted.
- Results show counts and the analysed image with markers on each piece.
- Several piece types (by colour) may share one photo; counts are per type.
  Pieces of the same colour but different shape (e.g. red meeples and red
  cubes) are **one type**.
- Types are defined by **tapping sample pieces**, not by automatic clustering.
- Numbering is **per type**, in reading order (top-left first, row by row),
  each type's labels drawn in its own marker colour; a toggle shows dots
  instead of numbers.
- Results support manual correction (add / remove / move between types).
- Optional **expected count per type** typed in from the manual, shown as
  ✅ match or ❌ "n missing" / "n extra".

### Assumptions (confirmed)

- Results are not persisted between sessions (no history in v1).
- Choosing a photo from the gallery is supported alongside the camera.
- Reading order uses row grouping with a tolerance, not a strict y-then-x sort.

### Out of scope for v1 (possible later)

- Saved game presets ("Agricola: red 20, blue 15…") and count history.
- Distinguishing same-coloured pieces by shape or size.
- Splitting touching pieces geometrically (watershed etc.); v1 estimates and
  flags them instead.

## 3. Platform and tech stack

- Kotlin, Jetpack Compose (Material 3), single activity, one `ViewModel`.
- OpenCV Android SDK from Maven Central (`org.opencv:opencv`), the newest
  release at implementation time, pinned in the version catalog.
- `minSdk` 29, `targetSdk`/`compileSdk` = latest stable at implementation time.
- Photo capture via the system camera app
  (`ActivityResultContracts.TakePicture`) into an app-private file; gallery via
  `ActivityResultContracts.PickVisualMedia`. No CameraX.
- Application id / package: `app.piececounter`.

## 4. User flow and screens

### Screen 1 — Start

- Buttons: **Take photo**, **Choose from gallery**.
- Tip text: "Plain or evenly patterned surface, pieces spread out, shoot from
  directly above."
- Cancelling the camera or picker returns here silently.

### Screen 2 — Pick types

- The photo fills the screen; pinch-zoom and pan.
- Prompt: "Tap one piece of each type."
- **Tap on a piece:**
  - with no type chip selected → creates a new type with that sample;
  - with a type chip selected → adds another sample to that type
    (needed for wood grain, shiny/metallic pieces, lit vs shaded pieces).
- After every tap, detection re-runs and all pieces matching each type are
  highlighted (outlined in the type's marker colour) as a live preview.
- Type chips along the bottom: `[■ swatch · name · expected: __ ]`. Name and
  expected count are editable and optional. A chip can be deleted; a sample
  can be removed by tapping its sample marker.
- **Count** → Screen 3. Disabled until at least one type exists.
- A small debug icon toggles a view of the piece/cloth mask.

### Screen 3 — Results

- Legend row per type: `■ Red 18 / 18 ✅`, `■ Brown 27 / 28 ❌ 1 missing`,
  `■ Grey 13 / 12 ❌ 1 extra`, or `■ Wood 18` when no expected count is set.
  Tapping a legend entry selects that type for adding pieces.
- Image with per-type numbering (section 6). Toggle: numbers ↔ dots.
  Label size scales with the type's median piece size.
- **Merged blobs** (estimated to contain more than one piece) show a range
  label such as `4–5?` in a distinct (dashed-outline) style.
- Corrections:
  - Tap empty spot → add a piece to the selected type (manual marker style).
  - Tap a marker → menu: *Remove* · *Move to → other types*.
  - Tap a merged blob → menu: *Set count: 1 / 2 / 3 / …* (default is the
    estimate; confirming clears the `?`).
  - Long-press a missed piece → *Add as sample for <type>*; detection
    re-runs, and existing manual edits are preserved (section 7).
- **New photo** → Screen 1 (discards the session).

## 5. Detection pipeline

Validated by a throwaway Python/OpenCV spike on three real photos taken on a
black/beige striped cloth (see section 9 for results). All distances use Lab
colour (`L` 0–100, `a`/`b` in standard units) computed from a float image.

1. **Load and normalise.** Decode with `inSampleSize` so the full-resolution
   (up to 200 MP) image is never in memory; apply EXIF rotation; resize so the
   long side is 2000 px. Convert to Lab, Gaussian blur 5×5.
2. **Learn the cloth.** Take a border strip (6 % of the short side) from all
   four edges, subsample, and run k-means with k = 6. The centroids are the
   cloth colours (e.g. black stripe, beige stripe, blended stripe edges).
3. **Learn the samples.** For each tap, flood-fill from the tap point in fixed
   range mode with tolerance (L 10, a 6, b 6) to get that piece's pixels.
   Split them at the median L into a lit half and a shaded half and keep both
   means as centroids. A type's centroids are the union over its samples.
4. **Piece vs cloth per pixel.** Weighted Euclidean distance with weights
   (L 0.35, a 1, b 1). A pixel is *piece* if its distance to the nearest type
   centroid is smaller than to the nearest cloth centroid **and** below 14.
5. **Clean the mask.** Open (5×5 ellipse), close twice, then fill each
   external contour's interior (heals holes from artwork and grain).
6. **Blobs.** External contours of the cleaned mask → per blob: outline,
   centroid, bounding box, area.
7. **Assign type per blob by majority vote.** For each blob, the type whose
   centroids are nearest for the most of its pixels wins. This fixes pieces
   whose bright top matches another type's pixels.
8. **Filter noise.** Per type, drop blobs smaller than 0.3 × that type's
   median blob area (median taken over blobs ≥ 5 % of the largest).
9. **Merged estimate.** If a blob's area ≥ 1.7 × its type's median area,
   estimate `round(area / median)` pieces and flag it as merged; otherwise 1.

Tunable constants (weights, k, thresholds) live in one `DetectorConfig`
object so the golden-set test can drive tuning.

**Known limitations:** extra objects whose colour matches a type (game box art,
a tin) are counted; touching pieces rely on the flagged estimate; pale pieces
very close to a cloth colour may need an extra sample.

## 6. Reading order and numbering

Per type, independently:

1. Sort pieces by centroid y.
2. Sweep: a piece starts a new row when its y is more than 0.5 × the type's
   median bounding-box height below the first piece of the current row.
3. Sort each row by centroid x; concatenate rows.
4. Number sequentially from 1. A merged blob estimated at n pieces consumes n
   numbers and is labelled with the range (`4–5?`).

## 7. Code structure and data model

```
app/src/main/java/app/piececounter/
├── core/        pure Kotlin — no Android or OpenCV imports
│   ├── Model.kt          Lab, Piece, PieceType, Session
│   ├── ColorMath.kt      sRGB↔Lab, weighted distance
│   ├── ReadingOrder.kt   row grouping + numbering
│   ├── Tally.kt          counts vs expected → status text
│   └── Results.kt        Session + detection → per-type numbered pieces
├── detect/      OpenCV lives only here
│   ├── DetectorConfig.kt
│   └── PieceDetector.kt  steps 1–9 of section 5
└── ui/
    ├── CounterViewModel.kt
    ├── StartScreen.kt, PickTypesScreen.kt, ResultsScreen.kt
    └── ImageTransform.kt screen ↔ image coordinates
```

```kotlin
data class Lab(val l: Float, val a: Float, val b: Float)
data class Pt(val x: Float, val y: Float)          // own types, so core/ stays
data class Box(val left: Float, val top: Float,   // free of android.graphics
               val right: Float, val bottom: Float)

data class Piece(
    val id: Int,
    val center: Pt, val bounds: Box, val area: Float,
    val outline: List<Pt>,          // empty for manual pieces
    val typeId: Int,                // from majority vote
    val estimatedCount: Int = 1,    // > 1 means merged
    val manual: Boolean = false,
)

data class PieceType(
    val id: Int, val name: String,
    val samples: List<Pt>,          // tap positions in image coordinates
    val expected: Int?,
)

data class Session(
    val photoPath: String,          // app-private copy of the photo
    val types: List<PieceType>,
    val added: List<Piece>,         // manual additions
    val removed: Set<Int>,          // ids of removed detected pieces
    val moved: Map<Int, Int>,       // pieceId → typeId
    val countOverrides: Map<Int, Int>, // merged pieceId → confirmed count
)
```

- Detected pieces are **derived** from photo + type samples and are not
  stored; the session stores only inputs and user edits. Final results =
  detected + added − removed, then `moved` and `countOverrides` applied.
- Detected piece ids must be stable across re-runs with added samples so
  edits keep applying: id = index of the blob in a deterministic order
  (sorted by centroid y, then x), and edits referencing a blob that no longer
  exists are dropped silently.
- Process death: the `Session` is saved via `SavedStateHandle`; detection
  re-runs on restore (deterministic).
- Detection runs on `Dispatchers.Default`; Screen 2 shows a spinner while it
  runs, and a newer tap cancels an in-flight run.

## 8. Error handling

| Situation | Behaviour |
|---|---|
| Camera/picker cancelled | Back to Start, no message |
| Photo cannot be decoded | "Couldn't open that photo — try another" |
| A tap's flood fill yields < 30 px (tapped a tiny highlight or edge) | Snackbar "Tap the middle of a piece"; no type created |
| 0 pieces for all types | Message with tips; buttons *Retake* · *Count by hand* |
| > 400 blobs, or > 40 % of pixels classed as piece | Banner "The surface looks too similar to the pieces — results may be off" |
| OpenCV fails to initialise | Error screen; not recoverable |

## 9. Testing

1. **`core/` unit tests (JUnit, JVM):** reading order (grid, staggered,
   tilted row, single piece, empty), merged-range numbering, tally text
   (match / missing / extra / no expectation), session derivation (add,
   remove, move, count override, edits referencing vanished blobs), Lab
   conversion against reference values.
2. **Detector golden-set test (instrumented, on the phone):** photos in
   `app/src/androidTest/assets/golden/` with a JSON file per photo listing
   tap positions per type and true counts. The test fails if any type's
   *raw* count (before manual correction) differs by more than a per-photo
   allowance recorded in the JSON (initially the known extra-object counts),
   and reports all deltas.
   Initial golden set — the three photos in `Test data/`:

   | Photo | True counts |
   |---|---|
   | `20261014_182938.jpg` | grey 12, yellow 10, red 18, brown 28 |
   | `20261014_182953.jpg` | grey 12, yellow 10, red 18, brown 28 |
   | `20261014_183235.jpg` | red 12, yellow 12 |

   Spike baseline (Python prototype, before majority vote): photo 1 —
   grey 12, yellow 11, red 18, brown 31 (+3 from box art); photo 2 — grey 12,
   yellow 10, red 17, brown 35 (tin and box counted); photo 3 — red 12,
   yellow 11. The Kotlin implementation should match or beat this.
3. **Manual checklist on the S23 Ultra:** camera and gallery flows, rotation,
   zoom/tap accuracy, sample adding, every correction action, numbers/dots
   toggle, process-death restore.
