# PieceCounter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An offline Android app that counts board-game pieces per colour type from one photo, with a numbered overlay and manual correction.

**Architecture:** Single-activity Jetpack Compose app. Pure-Kotlin `core/` package (model, numbering, tallies, session edits) unit-tested on the JVM; `detect/` package wraps OpenCV (cloth k-means + sample-driven nearest-centroid segmentation, blob majority vote) and is tested on the phone against a golden photo set; `ui/` holds one `ViewModel` and three screens.

**Tech Stack:** Kotlin, Jetpack Compose (Material 3), OpenCV Android (`org.opencv:opencv`), kotlinx.serialization, androidx.exifinterface, JUnit 4, AndroidX Test.

**Spec:** `docs/superpowers/specs/2026-10-14-piece-counter-design.md`

## Global Constraints

- Package / application id: `app.piececounter`. App name: `PieceCounter`.
- `minSdk` 29; `compileSdk`/`targetSdk` = what the Android Studio template picks (SDK platform 37 is installed).
- `core/` must not import `android.*`, `androidx.*` or `org.opencv.*`.
- OpenCV is only imported in `app/src/main/java/app/piececounter/detect/` and `MainActivity.kt`.
- Images are processed at 2000 px on the long side, upright (EXIF applied). All `Pt` coordinates are in that image space.
- Lab colour: `L` 0–100, `a`/`b` standard units. Distances weight L by 0.35.
- Fully offline: no `INTERNET` permission, no network libraries.
- Shell: Git Bash on Windows. Before any Gradle command: `export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr"`. Run Gradle from the project root as `./gradlew …`.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- If a golden-set count misses its allowance, **do not raise the allowance**. Report the deltas to the user and stop.

## Review Focus

1. **Portrait photos stored sideways with an EXIF rotation tag** → taps and markers must line up with the pieces. Pinned by `DetectorTest.portraitPhotoIsRotatedUprightAndScaled` (Task 7).
2. **Adding a sample after manual corrections** shifts detected piece ids → corrections must stay on the same physical pieces, or vanish if the piece is gone. Pinned by `SessionEditsTest.remapEdits*` (Task 5).
3. **Deleting a type that has manual pieces or moved pieces** → they disappear and nothing crashes. Pinned by `SessionEditsTest.removeTypeDropsItsManualPiecesAndMoves` and `ResultsTest.piecesOfUnknownTypeAreDropped` (Task 5).
4. **Tapping outside the photo (letterbox area) or on a tiny highlight** → no type is created, and the user sees "Tap the middle of a piece". Pinned by `DetectorTest.sampleOutsideImageIsNull` (Task 7).
5. **Expected-count field left empty or containing junk** → treated as "no expectation", never a crash. Pinned by `TallyTest.parseExpected*` (Task 4).

---

## File map

```
app/src/main/java/app/piececounter/
├── MainActivity.kt                    (Task 9)
├── core/
│   ├── Model.kt                       (Task 2) Lab, Pt, Box, Piece, PieceType, Session
│   ├── Stats.kt                       (Task 2) median
│   ├── ColorMath.kt                   (Task 2) sRGB↔Lab
│   ├── ReadingOrder.kt                (Task 3)
│   ├── Tally.kt                       (Task 4) TallyStatus, legendText, parseExpected
│   ├── Results.kt                     (Task 5) buildResults, hitTest, typicalSize
│   └── SessionEdits.kt                (Task 5) all session mutations + remapEdits
├── detect/
│   ├── DetectorConfig.kt              (Task 7)
│   ├── PhotoLoader.kt                 (Task 7)
│   └── PieceDetector.kt               (Tasks 7–8)
└── ui/
    ├── ImageTransform.kt              (Task 6)
    ├── CounterViewModel.kt            (Task 9)
    ├── Common.kt                      (Task 9) ZoomableImage, drawing helpers, snackbar, banner
    ├── StartScreen.kt                 (Task 9)
    ├── PickTypesScreen.kt             (Task 10)
    └── ResultsScreen.kt               (Task 11)
app/src/main/res/xml/file_paths.xml    (Task 9)
app/src/test/java/app/piececounter/…   JVM tests (Tasks 2–6)
app/src/androidTest/java/app/piececounter/detect/  DetectorTest, GoldenSetTest (Tasks 7–8)
app/src/androidTest/assets/golden/     3 photos + golden.json (Task 7)
```

---

### Task 1: Project scaffold and dependencies

**Files:**
- Create (via Android Studio wizard): the Gradle project in the repo root
- Modify: `gradle/libs.versions.toml`, `build.gradle.kts` (root), `app/build.gradle.kts`, `.gitignore`

**Interfaces:**
- Produces: a buildable app module `app` with package `app.piececounter`, the Compose theme `app.piececounter.ui.theme.PieceCounterTheme`, and the dependencies used by later tasks.

- [ ] **Step 1: User creates the project with the wizard** (the user does this step; Android Studio pins current, mutually compatible versions)

  In Android Studio: **File → New → New Project → Empty Activity**. Then:
  - Name: `PieceCounter`
  - Package name: `app.piececounter`
  - Save location: `C:\Users\kjmik\Documents\Programming\Android\PieceCounter` (accept the "directory not empty" warning)
  - Minimum SDK: API 29
  - Build configuration language: Kotlin DSL

  Click **Finish** and wait for the first Gradle sync to complete.

- [ ] **Step 2: Verify the template builds**

  Run: `export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr" && ./gradlew :app:assembleDebug`
  Expected: `BUILD SUCCESSFUL`

- [ ] **Step 3: Add the dependencies to the version catalog**

  In `gradle/libs.versions.toml`, add these lines to the existing sections. Do not remove anything the template created.

  ```toml
  [versions]
  opencv = "4.12.0"
  exifinterface = "1.4.1"
  kotlinxSerializationJson = "1.9.0"

  [libraries]
  opencv = { group = "org.opencv", name = "opencv", version.ref = "opencv" }
  androidx-exifinterface = { group = "androidx.exifinterface", name = "exifinterface", version.ref = "exifinterface" }
  kotlinx-serialization-json = { group = "org.jetbrains.kotlinx", name = "kotlinx-serialization-json", version.ref = "kotlinxSerializationJson" }
  androidx-lifecycle-viewmodel-compose = { group = "androidx.lifecycle", name = "lifecycle-viewmodel-compose", version.ref = "lifecycleRuntimeKtx" }

  [plugins]
  kotlin-serialization = { id = "org.jetbrains.kotlin.plugin.serialization", version.ref = "kotlin" }
  ```

  - If the template's catalog has no `kotlin` version key, use the `version.ref` of the `kotlin-compose` plugin instead.
  - If Gradle reports that one of the pinned versions doesn't exist, use the newest version listed on Maven Central (OpenCV, kotlinx) or Google Maven (exifinterface), and note the change in the commit message.

- [ ] **Step 4: Apply the plugin and dependencies**

  Root `build.gradle.kts`, inside `plugins { }`, add:

  ```kotlin
  alias(libs.plugins.kotlin.serialization) apply false
  ```

  `app/build.gradle.kts`, inside `plugins { }`, add:

  ```kotlin
  alias(libs.plugins.kotlin.serialization)
  ```

  `app/build.gradle.kts`, inside `dependencies { }`, add:

  ```kotlin
  implementation(libs.opencv)
  implementation(libs.androidx.exifinterface)
  implementation(libs.kotlinx.serialization.json)
  implementation(libs.androidx.lifecycle.viewmodel.compose)
  ```

- [ ] **Step 5: Ignore the user's raw photo folder** (the photos get copied into test assets in Task 7)

  Append to the root `.gitignore`:

  ```
  /Test data/
  ```

- [ ] **Step 6: Verify the build with the new dependencies**

  Run: `./gradlew :app:assembleDebug :app:testDebugUnitTest`
  Expected: `BUILD SUCCESSFUL` (the template's example unit test passes)

- [ ] **Step 7: Commit**

  ```bash
  git add -A
  git commit -m "chore: scaffold Android project with OpenCV, serialization, exif

  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
  ```

---

### Task 2: Core model, median, and colour maths

**Files:**
- Create: `app/src/main/java/app/piececounter/core/Model.kt`
- Create: `app/src/main/java/app/piececounter/core/Stats.kt`
- Create: `app/src/main/java/app/piececounter/core/ColorMath.kt`
- Test: `app/src/test/java/app/piececounter/core/StatsTest.kt`
- Test: `app/src/test/java/app/piececounter/core/ColorMathTest.kt`

**Interfaces:**
- Produces:
  - `data class Lab(l: Float, a: Float, b: Float)`, `data class Pt(x: Float, y: Float)`, and `data class Box(left, top, right, bottom: Float)` with `width`, `height`, `contains(p: Pt)`
  - `data class Piece(id: Int, center: Pt, bounds: Box, area: Float, outline: List<Pt> = emptyList(), typeId: Int, estimatedCount: Int = 1, manual: Boolean = false)`
  - `data class PieceType(id: Int, name: String, samples: List<Pt>, expected: Int? = null)`
  - `data class Session(photoPath: String, types: List<PieceType> = [], added: List<Piece> = [], removed: Set<Int> = {}, moved: Map<Int,Int> = {}, countOverrides: Map<Int,Int> = {})`
  - `fun median(values: List<Float>): Float` (0f for an empty list)
  - `object ColorMath { fun srgbToLab(r: Int, g: Int, b: Int): Lab; fun labToSrgb(lab: Lab): Int /* 0xAARRGGBB, alpha FF */ }`

- [ ] **Step 1: Write the failing tests**

  `app/src/test/java/app/piececounter/core/StatsTest.kt`:

  ```kotlin
  package app.piececounter.core

  import org.junit.Assert.assertEquals
  import org.junit.Test

  class StatsTest {
      @Test fun medianOfEmptyIsZero() = assertEquals(0f, median(emptyList()), 0f)
      @Test fun medianOfOddCountIsMiddle() = assertEquals(3f, median(listOf(5f, 1f, 3f)), 0f)
      @Test fun medianOfEvenCountIsMean() = assertEquals(2.5f, median(listOf(4f, 1f, 2f, 3f)), 0f)
  }
  ```

  `app/src/test/java/app/piececounter/core/ColorMathTest.kt`:

  ```kotlin
  package app.piececounter.core

  import org.junit.Assert.assertEquals
  import org.junit.Test

  class ColorMathTest {
      private fun assertLab(expected: Lab, actual: Lab, tol: Float = 0.1f) {
          assertEquals("L", expected.l, actual.l, tol)
          assertEquals("a", expected.a, actual.a, tol)
          assertEquals("b", expected.b, actual.b, tol)
      }

      @Test fun whiteIsL100() = assertLab(Lab(100f, 0f, 0f), ColorMath.srgbToLab(255, 255, 255))
      @Test fun blackIsL0() = assertLab(Lab(0f, 0f, 0f), ColorMath.srgbToLab(0, 0, 0))
      @Test fun pureRedMatchesReference() = assertLab(Lab(53.24f, 80.09f, 67.20f), ColorMath.srgbToLab(255, 0, 0))

      @Test fun labToSrgbRoundTrips() {
          for ((r, g, b) in listOf(Triple(200, 30, 40), Triple(120, 120, 120), Triple(240, 200, 40), Triple(90, 60, 30))) {
              val argb = ColorMath.labToSrgb(ColorMath.srgbToLab(r, g, b))
              assertEquals(0xFF, argb ushr 24)
              assertEquals(r.toDouble(), (argb shr 16 and 0xFF).toDouble(), 1.0)
              assertEquals(g.toDouble(), (argb shr 8 and 0xFF).toDouble(), 1.0)
              assertEquals(b.toDouble(), (argb and 0xFF).toDouble(), 1.0)
          }
      }
  }
  ```

- [ ] **Step 2: Run the tests to verify they fail**

  Run: `./gradlew :app:testDebugUnitTest --tests "app.piececounter.core.*"`
  Expected: compilation FAILS with unresolved references `median`, `Lab`, `ColorMath`

- [ ] **Step 3: Write the implementation**

  `app/src/main/java/app/piececounter/core/Model.kt`:

  ```kotlin
  package app.piececounter.core

  import kotlinx.serialization.Serializable

  @Serializable
  data class Lab(val l: Float, val a: Float, val b: Float)

  @Serializable
  data class Pt(val x: Float, val y: Float)

  @Serializable
  data class Box(val left: Float, val top: Float, val right: Float, val bottom: Float) {
      val width: Float get() = right - left
      val height: Float get() = bottom - top
      fun contains(p: Pt): Boolean = p.x in left..right && p.y in top..bottom
  }

  /** Detected pieces have ids >= 0; manually added pieces have ids < 0. */
  @Serializable
  data class Piece(
      val id: Int,
      val center: Pt,
      val bounds: Box,
      val area: Float,
      val outline: List<Pt> = emptyList(),
      val typeId: Int,
      val estimatedCount: Int = 1,
      val manual: Boolean = false,
  )

  @Serializable
  data class PieceType(
      val id: Int,
      val name: String,
      val samples: List<Pt>,
      val expected: Int? = null,
  )

  /** Inputs and user edits only; detected pieces are derived, never stored. */
  @Serializable
  data class Session(
      val photoPath: String,
      val types: List<PieceType> = emptyList(),
      val added: List<Piece> = emptyList(),
      val removed: Set<Int> = emptySet(),
      val moved: Map<Int, Int> = emptyMap(),
      val countOverrides: Map<Int, Int> = emptyMap(),
  )
  ```

  `app/src/main/java/app/piececounter/core/Stats.kt`:

  ```kotlin
  package app.piececounter.core

  fun median(values: List<Float>): Float {
      if (values.isEmpty()) return 0f
      val s = values.sorted()
      val mid = s.size / 2
      return if (s.size % 2 == 1) s[mid] else (s[mid - 1] + s[mid]) / 2f
  }
  ```

  `app/src/main/java/app/piececounter/core/ColorMath.kt`:

  ```kotlin
  package app.piececounter.core

  import kotlin.math.cbrt
  import kotlin.math.pow
  import kotlin.math.roundToInt

  /** sRGB (D65) <-> CIE Lab, matching OpenCV's float Lab conversion. */
  object ColorMath {
      private const val XN = 0.95047f
      private const val ZN = 1.08883f
      private const val EPS = 216f / 24389f
      private const val KAPPA = 24389f / 27f

      fun srgbToLab(r: Int, g: Int, b: Int): Lab {
          val rl = linear(r / 255f); val gl = linear(g / 255f); val bl = linear(b / 255f)
          val x = (0.4124564f * rl + 0.3575761f * gl + 0.1804375f * bl) / XN
          val y = 0.2126729f * rl + 0.7151522f * gl + 0.0721750f * bl
          val z = (0.0193339f * rl + 0.1191920f * gl + 0.9503041f * bl) / ZN
          val fx = f(x); val fy = f(y); val fz = f(z)
          return Lab(116f * fy - 16f, 500f * (fx - fy), 200f * (fy - fz))
      }

      fun labToSrgb(lab: Lab): Int {
          val fy = (lab.l + 16f) / 116f
          val fx = fy + lab.a / 500f
          val fz = fy - lab.b / 200f
          val x = finv(fx) * XN; val y = finv(fy); val z = finv(fz) * ZN
          val rl = 3.2404542f * x - 1.5371385f * y - 0.4985314f * z
          val gl = -0.9692660f * x + 1.8760108f * y + 0.0415560f * z
          val bl = 0.0556434f * x - 0.2040259f * y + 1.0572252f * z
          return (0xFF shl 24) or (encode(rl) shl 16) or (encode(gl) shl 8) or encode(bl)
      }

      private fun linear(c: Float) = if (c <= 0.04045f) c / 12.92f else ((c + 0.055f) / 1.055f).pow(2.4f)
      private fun gamma(c: Float) = if (c <= 0.0031308f) 12.92f * c else 1.055f * c.pow(1f / 2.4f) - 0.055f
      private fun encode(c: Float) = (gamma(c.coerceIn(0f, 1f)) * 255f).roundToInt().coerceIn(0, 255)
      private fun f(t: Float) = if (t > EPS) cbrt(t) else (KAPPA * t + 16f) / 116f
      private fun finv(t: Float) = if (t * t * t > EPS) t * t * t else (116f * t - 16f) / KAPPA
  }
  ```

- [ ] **Step 4: Run the tests to verify they pass**

  Run: `./gradlew :app:testDebugUnitTest --tests "app.piececounter.core.*"`
  Expected: PASS (7 tests)

- [ ] **Step 5: Commit**

  ```bash
  git add app/src/main/java/app/piececounter/core app/src/test/java/app/piececounter/core
  git commit -m "feat(core): add model, median and Lab colour maths

  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
  ```

---

### Task 3: Reading order

> **Learning-mode note for the executor:** before Step 3, offer the user the chance to write the body of `readingOrder` themselves, since the row-grouping rule is the one they care about. Give them the signature, the tests, and the rule from spec section 6. Use their version if the tests pass.

**Files:**
- Create: `app/src/main/java/app/piececounter/core/ReadingOrder.kt`
- Test: `app/src/test/java/app/piececounter/core/ReadingOrderTest.kt`

**Interfaces:**
- Consumes: `Pt` (Task 2)
- Produces: `fun <T> readingOrder(items: List<T>, rowTolerance: Float, center: (T) -> Pt): List<T>`

- [ ] **Step 1: Write the failing test**

  ```kotlin
  package app.piececounter.core

  import org.junit.Assert.assertEquals
  import org.junit.Test

  class ReadingOrderTest {
      private data class P(val name: String, val x: Float, val y: Float)

      private fun order(vararg ps: P, tol: Float = 10f) =
          readingOrder(ps.toList(), tol) { Pt(it.x, it.y) }.map { it.name }

      @Test fun emptyListGivesEmptyList() = assertEquals(emptyList<String>(), order())

      @Test fun singlePiece() = assertEquals(listOf("a"), order(P("a", 5f, 5f)))

      @Test fun gridReadsRowByRow() {
          val result = order(
              P("c2", 100f, 52f), P("a1", 0f, 1f), P("b3", 50f, 98f),
              P("b1", 50f, -2f), P("a3", 0f, 101f), P("c1", 100f, 3f),
              P("a2", 0f, 49f), P("c3", 100f, 100f), P("b2", 50f, 50f),
          )
          assertEquals(listOf("a1", "b1", "c1", "a2", "b2", "c2", "a3", "b3", "c3"), result)
      }

      @Test fun slightlyUnevenRowDoesNotZigzag() {
          // A strict y-then-x sort would give b, c, a.
          assertEquals(listOf("a", "b", "c"), order(P("a", 0f, 104f), P("b", 50f, 98f), P("c", 100f, 101f)))
      }

      @Test fun gentlyTiltedRowStaysOneRow() {
          assertEquals(
              listOf("a", "b", "c", "d"),
              order(P("d", 150f, 109f), P("b", 50f, 103f), P("a", 0f, 100f), P("c", 100f, 106f)),
          )
      }

      @Test fun pieceBeyondToleranceStartsNewRowEvenIfFurtherLeft() {
          assertEquals(listOf("right", "left"), order(P("left", 0f, 115f), P("right", 100f, 100f)))
      }
  }
  ```

- [ ] **Step 2: Run the test to verify it fails**

  Run: `./gradlew :app:testDebugUnitTest --tests "app.piececounter.core.ReadingOrderTest"`
  Expected: compilation FAILS, unresolved reference `readingOrder`

- [ ] **Step 3: Write the implementation**

  ```kotlin
  package app.piececounter.core

  /**
   * Orders items like reading text: top row first, left to right within a row.
   * An item joins the current row if its y is within [rowTolerance] of the
   * row's FIRST item; otherwise it starts a new row.
   */
  fun <T> readingOrder(items: List<T>, rowTolerance: Float, center: (T) -> Pt): List<T> {
      val rows = mutableListOf<MutableList<T>>()
      for (item in items.sortedBy { center(it).y }) {
          val row = rows.lastOrNull()
          if (row != null && center(item).y - center(row.first()).y <= rowTolerance) row += item
          else rows += mutableListOf(item)
      }
      return rows.flatMap { row -> row.sortedBy { center(it).x } }
  }
  ```

- [ ] **Step 4: Run the test to verify it passes**

  Run: `./gradlew :app:testDebugUnitTest --tests "app.piececounter.core.ReadingOrderTest"`
  Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

  ```bash
  git add app/src/main/java/app/piececounter/core/ReadingOrder.kt app/src/test/java/app/piececounter/core/ReadingOrderTest.kt
  git commit -m "feat(core): add row-grouped reading order

  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
  ```

---

### Task 4: Tally, legend text, expected-count parsing

**Files:**
- Create: `app/src/main/java/app/piececounter/core/Tally.kt`
- Test: `app/src/test/java/app/piececounter/core/TallyTest.kt`

**Interfaces:**
- Consumes: `PieceType` (Task 2)
- Produces:
  - `sealed interface TallyStatus { NoExpectation; Match; Missing(n: Int); Extra(n: Int) }`
  - `fun tally(found: Int, expected: Int?): TallyStatus`
  - `fun TallyStatus.text(): String`
  - `fun legendText(type: PieceType, total: Int): String`
  - `fun parseExpected(text: String): Int?`

- [ ] **Step 1: Write the failing test**

  ```kotlin
  package app.piececounter.core

  import org.junit.Assert.assertEquals
  import org.junit.Assert.assertNull
  import org.junit.Test

  class TallyTest {
      private fun type(expected: Int?) = PieceType(1, "Red", listOf(Pt(0f, 0f)), expected)

      @Test fun noExpectation() = assertEquals(TallyStatus.NoExpectation, tally(5, null))
      @Test fun match() = assertEquals(TallyStatus.Match, tally(18, 18))
      @Test fun missing() = assertEquals(TallyStatus.Missing(2), tally(16, 18))
      @Test fun extra() = assertEquals(TallyStatus.Extra(1), tally(13, 12))

      @Test fun legendWithoutExpectation() = assertEquals("Red 18", legendText(type(null), 18))
      @Test fun legendMatch() = assertEquals("Red 18 / 18 ✅", legendText(type(18), 18))
      @Test fun legendMissing() = assertEquals("Red 27 / 28 ❌ 1 missing", legendText(type(28), 27))
      @Test fun legendExtra() = assertEquals("Red 13 / 12 ❌ 1 extra", legendText(type(12), 13))

      @Test fun parseExpectedAcceptsDigitsWithSpaces() = assertEquals(7, parseExpected(" 7 "))
      @Test fun parseExpectedAcceptsZero() = assertEquals(0, parseExpected("0"))
      @Test fun parseExpectedEmptyIsNull() = assertNull(parseExpected(""))
      @Test fun parseExpectedBlankIsNull() = assertNull(parseExpected("   "))
      @Test fun parseExpectedJunkIsNull() = assertNull(parseExpected("12a"))
      @Test fun parseExpectedNegativeIsNull() = assertNull(parseExpected("-3"))
      @Test fun parseExpectedTooLongIsNull() = assertNull(parseExpected("12345"))
  }
  ```

- [ ] **Step 2: Run the test to verify it fails**

  Run: `./gradlew :app:testDebugUnitTest --tests "app.piececounter.core.TallyTest"`
  Expected: compilation FAILS, unresolved reference `tally`

- [ ] **Step 3: Write the implementation**

  ```kotlin
  package app.piececounter.core

  sealed interface TallyStatus {
      data object NoExpectation : TallyStatus
      data object Match : TallyStatus
      data class Missing(val n: Int) : TallyStatus
      data class Extra(val n: Int) : TallyStatus
  }

  fun tally(found: Int, expected: Int?): TallyStatus = when {
      expected == null -> TallyStatus.NoExpectation
      found == expected -> TallyStatus.Match
      found < expected -> TallyStatus.Missing(expected - found)
      else -> TallyStatus.Extra(found - expected)
  }

  fun TallyStatus.text(): String = when (this) {
      TallyStatus.NoExpectation -> ""
      TallyStatus.Match -> "✅"
      is TallyStatus.Missing -> "❌ $n missing"
      is TallyStatus.Extra -> "❌ $n extra"
  }

  fun legendText(type: PieceType, total: Int): String {
      val expected = type.expected ?: return "${type.name} $total"
      return "${type.name} $total / $expected ${tally(total, expected).text()}"
  }

  /** Digits only (surrounding spaces allowed), at most 4 of them; anything else means "no expectation". */
  fun parseExpected(text: String): Int? =
      text.trim().takeIf { it.isNotEmpty() && it.length <= 4 && it.all(Char::isDigit) }?.toInt()
  ```

- [ ] **Step 4: Run the test to verify it passes**

  Run: `./gradlew :app:testDebugUnitTest --tests "app.piececounter.core.TallyTest"`
  Expected: PASS (15 tests)

- [ ] **Step 5: Commit**

  ```bash
  git add app/src/main/java/app/piececounter/core/Tally.kt app/src/test/java/app/piececounter/core/TallyTest.kt
  git commit -m "feat(core): add tally, legend text and expected-count parsing

  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
  ```

---

### Task 5: Session edits and derived results

This task refines spec section 7's id rule. Detected ids are still the index in (y, x) order. But when detection re-runs, `remapEdits` moves each edit to whichever new piece contains the old piece's centre, instead of trusting that the index stayed the same. Adding a sample can insert new blobs earlier in the order, which would otherwise shift every id after them.

**Files:**
- Create: `app/src/main/java/app/piececounter/core/Results.kt`
- Create: `app/src/main/java/app/piececounter/core/SessionEdits.kt`
- Test: `app/src/test/java/app/piececounter/core/ResultsTest.kt`
- Test: `app/src/test/java/app/piececounter/core/SessionEditsTest.kt`

**Interfaces:**
- Consumes: Task 2 model, `median`; `readingOrder` (Task 3); `tally`, `TallyStatus` (Task 4)
- Produces:
  - `data class NumberedPiece(piece: Piece, typeId: Int, count: Int, first: Int, flagged: Boolean)` with `last` and `label`
  - `data class TypeResult(type: PieceType, pieces: List<NumberedPiece>)` with `total` and `status`
  - `fun buildResults(session: Session, detected: List<Piece>): List<TypeResult>`
  - `fun hitTest(pieces: List<Piece>, p: Pt): Piece?`
  - `fun typicalSize(pieces: List<Piece>): Float`
  - `object SessionEdits` with `addType(s, sample): Pair<Session, Int>`, `addSample(s, typeId, sample)`, `removeSample(s, typeId, index)`, `removeType(s, typeId)`, `rename(s, typeId, name)`, `setExpected(s, typeId, expected: Int?)`, `addPiece(s, typeId, at: Pt, size: Float)`, `removePiece(s, id)`, `movePiece(s, id, typeId)`, `setCount(s, id, n)`, `sampleNear(s, p, radius): Pair<Int, Int>?`, `remapEdits(s, old: List<Piece>, new: List<Piece>)`. All of them return a `Session` unless noted otherwise.

- [ ] **Step 1: Write the failing tests**

  `app/src/test/java/app/piececounter/core/ResultsTest.kt`:

  ```kotlin
  package app.piececounter.core

  import org.junit.Assert.assertEquals
  import org.junit.Assert.assertNull
  import org.junit.Test

  fun piece(id: Int, x: Float, y: Float, typeId: Int, est: Int = 1, size: Float = 10f, manual: Boolean = false) =
      Piece(id, Pt(x, y), Box(x - size / 2, y - size / 2, x + size / 2, y + size / 2), size * size,
          typeId = typeId, estimatedCount = est, manual = manual)

  fun type(id: Int, expected: Int? = null) = PieceType(id, "T$id", listOf(Pt(0f, 0f)), expected)

  class ResultsTest {
      private val session = Session("p.jpg", types = listOf(type(1), type(2)))

      private fun labels(r: TypeResult) = r.pieces.map { it.label }
      private fun ids(r: TypeResult) = r.pieces.map { it.piece.id }

      @Test fun numbersEachTypeSeparatelyInReadingOrder() {
          val detected = listOf(piece(0, 50f, 10f, 1), piece(1, 10f, 10f, 1), piece(2, 10f, 50f, 1), piece(3, 30f, 30f, 2))
          val r = buildResults(session, detected)
          assertEquals(listOf(1, 0, 2), ids(r[0]))
          assertEquals(listOf("1", "2", "3"), labels(r[0]))
          assertEquals(listOf("1"), labels(r[1]))
      }

      @Test fun removedPiecesAreExcluded() {
          val r = buildResults(session.copy(removed = setOf(0)), listOf(piece(0, 0f, 0f, 1), piece(1, 20f, 0f, 1)))
          assertEquals(listOf(1), ids(r[0]))
      }

      @Test fun movedPieceCountsForNewType() {
          val r = buildResults(session.copy(moved = mapOf(0 to 2)), listOf(piece(0, 0f, 0f, 1)))
          assertEquals(0, r[0].total)
          assertEquals(1, r[1].total)
          assertEquals(2, r[1].pieces.single().typeId)
      }

      @Test fun manualPiecesAreIncluded() {
          val s = session.copy(added = listOf(piece(-1, 100f, 0f, 1, manual = true)))
          val r = buildResults(s, listOf(piece(0, 0f, 0f, 1)))
          assertEquals(listOf(0, -1), ids(r[0]))
      }

      @Test fun mergedBlobConsumesRangeAndIsFlagged() {
          val r = buildResults(session, listOf(piece(0, 0f, 0f, 1, est = 2), piece(1, 20f, 0f, 1)))
          assertEquals(listOf("1–2?", "3"), labels(r[0]))
          assertEquals(3, r[0].total)
      }

      @Test fun countOverrideClearsFlag() {
          val r = buildResults(session.copy(countOverrides = mapOf(0 to 1)), listOf(piece(0, 0f, 0f, 1, est = 2)))
          assertEquals(listOf("1"), labels(r[0]))
          assertEquals(false, r[0].pieces.single().flagged)
      }

      @Test fun confirmedMergedCountShowsRangeWithoutQuestionMark() {
          val r = buildResults(session.copy(countOverrides = mapOf(0 to 2)), listOf(piece(0, 0f, 0f, 1, est = 2)))
          assertEquals(listOf("1–2"), labels(r[0]))
      }

      @Test fun piecesOfUnknownTypeAreDropped() {
          val r = buildResults(Session("p.jpg", types = listOf(type(1))), listOf(piece(0, 0f, 0f, 2)))
          assertEquals(1, r.size)
          assertEquals(0, r[0].total)
      }

      @Test fun statusComparesWithExpected() {
          val s = Session("p.jpg", types = listOf(type(1, expected = 2)))
          assertEquals(TallyStatus.Missing(1), buildResults(s, listOf(piece(0, 0f, 0f, 1)))[0].status)
      }

      @Test fun hitTestFindsContainingPiece() {
          val ps = listOf(piece(0, 0f, 0f, 1), piece(1, 100f, 100f, 1))
          assertEquals(1, hitTest(ps, Pt(102f, 98f))?.id)
          assertNull(hitTest(ps, Pt(50f, 50f)))
      }

      @Test fun hitTestPrefersNearestCentreWhenBoxesOverlap() {
          val ps = listOf(piece(0, 0f, 0f, 1, size = 40f), piece(1, 10f, 0f, 1, size = 40f))
          assertEquals(1, hitTest(ps, Pt(9f, 0f))?.id)
      }

      @Test fun typicalSizeFallsBackWhenEmpty() = assertEquals(40f, typicalSize(emptyList()), 0f)
  }
  ```

  `app/src/test/java/app/piececounter/core/SessionEditsTest.kt`:

  ```kotlin
  package app.piececounter.core

  import org.junit.Assert.assertEquals
  import org.junit.Assert.assertNull
  import org.junit.Assert.assertTrue
  import org.junit.Test

  class SessionEditsTest {
      private val empty = Session("p.jpg")

      @Test fun addTypeAssignsIncreasingIds() {
          val (s1, id1) = SessionEdits.addType(empty, Pt(1f, 1f))
          val (s2, id2) = SessionEdits.addType(s1, Pt(2f, 2f))
          assertEquals(1, id1); assertEquals(2, id2)
          assertEquals("Type 2", s2.types[1].name)
      }

      @Test fun addSampleAppendsToType() {
          val (s, id) = SessionEdits.addType(empty, Pt(1f, 1f))
          assertEquals(2, SessionEdits.addSample(s, id, Pt(5f, 5f)).types.single().samples.size)
      }

      @Test fun removeLastSampleRemovesType() {
          val (s, id) = SessionEdits.addType(empty, Pt(1f, 1f))
          assertTrue(SessionEdits.removeSample(s, id, 0).types.isEmpty())
      }

      @Test fun removeTypeDropsItsManualPiecesAndMoves() {
          val s = Session("p.jpg", types = listOf(type(1), type(2)),
              added = listOf(piece(-1, 0f, 0f, 2, manual = true), piece(-2, 5f, 5f, 1, manual = true)),
              moved = mapOf(7 to 2, 8 to 1))
          val r = SessionEdits.removeType(s, 2)
          assertEquals(listOf(1), r.types.map { it.id })
          assertEquals(listOf(-2), r.added.map { it.id })
          assertEquals(mapOf(8 to 1), r.moved)
      }

      @Test fun addPieceGivesUniqueNegativeIds() {
          var s = Session("p.jpg", types = listOf(type(1)))
          s = SessionEdits.addPiece(s, 1, Pt(0f, 0f), 10f)
          s = SessionEdits.addPiece(s, 1, Pt(20f, 0f), 10f)
          s = SessionEdits.removePiece(s, s.added.first().id)
          s = SessionEdits.addPiece(s, 1, Pt(40f, 0f), 10f)
          val ids = s.added.map { it.id }
          assertEquals(ids.size, ids.toSet().size)
          assertTrue(ids.all { it < 0 })
          assertTrue(s.added.all { it.manual })
      }

      @Test fun removeDetectedPieceRecordsIdAndClearsItsEdits() {
          val s = empty.copy(moved = mapOf(3 to 2), countOverrides = mapOf(3 to 2))
          val r = SessionEdits.removePiece(s, 3)
          assertEquals(setOf(3), r.removed)
          assertTrue(r.moved.isEmpty()); assertTrue(r.countOverrides.isEmpty())
      }

      @Test fun sampleNearFindsWithinRadius() {
          val s = Session("p.jpg", types = listOf(PieceType(4, "x", listOf(Pt(0f, 0f), Pt(100f, 100f)))))
          assertEquals(4 to 1, SessionEdits.sampleNear(s, Pt(105f, 98f), 10f))
          assertNull(SessionEdits.sampleNear(s, Pt(50f, 50f), 10f))
      }

      @Test fun remapEditsFollowsPiecesToNewIds() {
          val old = listOf(piece(0, 10f, 10f, 1), piece(1, 50f, 50f, 1))
          val new = listOf(piece(0, 5f, 5f, 1), piece(1, 11f, 9f, 1), piece(2, 51f, 50f, 1))
          val s = empty.copy(removed = setOf(0), moved = mapOf(1 to 2), countOverrides = mapOf(1 to 3))
          val r = SessionEdits.remapEdits(s, old, new)
          assertEquals(setOf(1), r.removed)
          assertEquals(mapOf(2 to 2), r.moved)
          assertEquals(mapOf(2 to 3), r.countOverrides)
      }

      @Test fun remapEditsDropsEditsForVanishedPiecesAndKeepsManualIds() {
          val old = listOf(piece(0, 10f, 10f, 1))
          val s = empty.copy(removed = setOf(0), moved = mapOf(-1 to 2))
          val r = SessionEdits.remapEdits(s, old, emptyList())
          assertTrue(r.removed.isEmpty())
          assertEquals(mapOf(-1 to 2), r.moved)
      }
  }
  ```

- [ ] **Step 2: Run the tests to verify they fail**

  Run: `./gradlew :app:testDebugUnitTest --tests "app.piececounter.core.ResultsTest" --tests "app.piececounter.core.SessionEditsTest"`
  Expected: compilation FAILS, unresolved references `buildResults`, `SessionEdits`

- [ ] **Step 3: Write the implementation**

  `app/src/main/java/app/piececounter/core/Results.kt`:

  ```kotlin
  package app.piececounter.core

  import kotlin.math.max

  data class NumberedPiece(
      val piece: Piece,
      val typeId: Int,
      val count: Int,
      val first: Int,
      val flagged: Boolean,
  ) {
      val last: Int get() = first + count - 1
      val label: String get() = when {
          count == 1 -> "$first"
          flagged -> "$first–$last?"
          else -> "$first–$last"
      }
  }

  data class TypeResult(val type: PieceType, val pieces: List<NumberedPiece>) {
      val total: Int get() = pieces.sumOf { it.count }
      val status: TallyStatus get() = tally(total, type.expected)
  }

  /** Detected + added − removed, with moves and count overrides applied, numbered per type. */
  fun buildResults(session: Session, detected: List<Piece>): List<TypeResult> {
      val typeIds = session.types.map { it.id }.toSet()
      val all = (detected.filter { it.id !in session.removed } + session.added)
          .map { p -> p.copy(typeId = session.moved[p.id] ?: p.typeId) }
          .filter { it.typeId in typeIds }
      return session.types.map { type ->
          val mine = all.filter { it.typeId == type.id }
          val heights = mine.filter { !it.manual }.map { it.bounds.height }.ifEmpty { mine.map { it.bounds.height } }
          var next = 1
          val numbered = readingOrder(mine, 0.5f * median(heights)) { it.center }.map { p ->
              val override = session.countOverrides[p.id]
              val count = override ?: p.estimatedCount
              NumberedPiece(p, type.id, count, next, flagged = override == null && p.estimatedCount > 1)
                  .also { next += count }
          }
          TypeResult(type, numbered)
      }
  }

  fun hitTest(pieces: List<Piece>, p: Pt): Piece? =
      pieces.filter { it.bounds.contains(p) }.minByOrNull {
          val dx = it.center.x - p.x; val dy = it.center.y - p.y
          dx * dx + dy * dy
      }

  /** Median of each piece's longer side; 40 px when there is nothing to measure. */
  fun typicalSize(pieces: List<Piece>): Float =
      if (pieces.isEmpty()) 40f else median(pieces.map { max(it.bounds.width, it.bounds.height) })
  ```

  `app/src/main/java/app/piececounter/core/SessionEdits.kt`:

  ```kotlin
  package app.piececounter.core

  object SessionEdits {
      fun addType(s: Session, sample: Pt): Pair<Session, Int> {
          val id = (s.types.maxOfOrNull { it.id } ?: 0) + 1
          return s.copy(types = s.types + PieceType(id, "Type $id", listOf(sample))) to id
      }

      fun addSample(s: Session, typeId: Int, sample: Pt): Session =
          s.copy(types = s.types.map { if (it.id == typeId) it.copy(samples = it.samples + sample) else it })

      fun removeSample(s: Session, typeId: Int, index: Int): Session {
          val type = s.types.firstOrNull { it.id == typeId } ?: return s
          val remaining = type.samples.filterIndexed { i, _ -> i != index }
          if (remaining.isEmpty()) return removeType(s, typeId)
          return s.copy(types = s.types.map { if (it.id == typeId) it.copy(samples = remaining) else it })
      }

      fun removeType(s: Session, typeId: Int): Session = s.copy(
          types = s.types.filterNot { it.id == typeId },
          added = s.added.filterNot { it.typeId == typeId },
          moved = s.moved.filterValues { it != typeId },
      )

      fun rename(s: Session, typeId: Int, name: String): Session =
          s.copy(types = s.types.map { if (it.id == typeId) it.copy(name = name) else it })

      fun setExpected(s: Session, typeId: Int, expected: Int?): Session =
          s.copy(types = s.types.map { if (it.id == typeId) it.copy(expected = expected) else it })

      fun addPiece(s: Session, typeId: Int, at: Pt, size: Float): Session {
          val id = minOf(s.added.minOfOrNull { it.id } ?: 0, 0) - 1
          val h = size / 2
          val piece = Piece(id, at, Box(at.x - h, at.y - h, at.x + h, at.y + h), size * size,
              typeId = typeId, manual = true)
          return s.copy(added = s.added + piece)
      }

      fun removePiece(s: Session, id: Int): Session =
          if (id < 0) s.copy(added = s.added.filterNot { it.id == id }, moved = s.moved - id)
          else s.copy(removed = s.removed + id, moved = s.moved - id, countOverrides = s.countOverrides - id)

      fun movePiece(s: Session, id: Int, typeId: Int): Session = s.copy(moved = s.moved + (id to typeId))

      fun setCount(s: Session, id: Int, n: Int): Session = s.copy(countOverrides = s.countOverrides + (id to n))

      /** (typeId, sampleIndex) of the nearest sample within [radius], or null. */
      fun sampleNear(s: Session, p: Pt, radius: Float): Pair<Int, Int>? =
          s.types.flatMap { t -> t.samples.mapIndexed { i, sp -> Triple(t.id, i, sp) } }
              .map { (t, i, sp) -> Triple(t, i, (sp.x - p.x) * (sp.x - p.x) + (sp.y - p.y) * (sp.y - p.y)) }
              .filter { it.third <= radius * radius }
              .minByOrNull { it.third }
              ?.let { it.first to it.second }

      /** Re-points edits on detected pieces to whichever new piece contains the old piece's centre. */
      fun remapEdits(s: Session, old: List<Piece>, new: List<Piece>): Session {
          val oldById = old.associateBy { it.id }
          fun map(id: Int): Int? = if (id < 0) id else oldById[id]?.let { hitTest(new, it.center)?.id }
          return s.copy(
              removed = s.removed.mapNotNull(::map).toSet(),
              moved = s.moved.mapNotNull { (k, v) -> map(k)?.let { it to v } }.toMap(),
              countOverrides = s.countOverrides.mapNotNull { (k, v) -> map(k)?.let { it to v } }.toMap(),
          )
      }
  }
  ```

- [ ] **Step 4: Run all core tests to verify they pass**

  Run: `./gradlew :app:testDebugUnitTest --tests "app.piececounter.core.*"`
  Expected: PASS (all core tests, including the 12 Results and 9 SessionEdits tests)

- [ ] **Step 5: Commit**

  ```bash
  git add app/src/main/java/app/piececounter/core app/src/test/java/app/piececounter/core
  git commit -m "feat(core): add session edits, edit remapping and per-type results

  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
  ```

---

### Task 6: Screen ↔ image transform

**Files:**
- Create: `app/src/main/java/app/piececounter/ui/ImageTransform.kt`
- Test: `app/src/test/java/app/piececounter/ui/ImageTransformTest.kt`

**Interfaces:**
- Consumes: `Pt` (Task 2)
- Produces: `data class ImageTransform(scale: Float, offsetX: Float, offsetY: Float)` with `toScreen(p: Pt): Pt`, `toImage(x: Float, y: Float): Pt`, `zoom(factor, focusX, focusY, minScale, maxScale)`, `pan(dx, dy)`, and `companion fun fit(imageW, imageH, viewW, viewH)`

- [ ] **Step 1: Write the failing test**

  ```kotlin
  package app.piececounter.ui

  import app.piececounter.core.Pt
  import org.junit.Assert.assertEquals
  import org.junit.Test

  class ImageTransformTest {
      private fun assertPt(e: Pt, a: Pt) { assertEquals(e.x, a.x, 0.01f); assertEquals(e.y, a.y, 0.01f) }

      @Test fun fitCentresPortraitImageInLandscapeView() {
          val t = ImageTransform.fit(1000f, 2000f, 1000f, 1000f)
          assertEquals(0.5f, t.scale, 0f)
          assertEquals(250f, t.offsetX, 0f)
          assertEquals(0f, t.offsetY, 0f)
      }

      @Test fun toImageInvertsToScreen() {
          val t = ImageTransform(2.5f, 30f, -40f)
          val s = t.toScreen(Pt(123f, 456f))
          assertPt(Pt(123f, 456f), t.toImage(s.x, s.y))
      }

      @Test fun zoomKeepsFocusPointFixed() {
          val t = ImageTransform(1f, 10f, 20f)
          val before = t.toImage(300f, 400f)
          val z = t.zoom(2f, 300f, 400f, 0.5f, 8f)
          assertPt(before, z.toImage(300f, 400f))
          assertEquals(2f, z.scale, 0f)
      }

      @Test fun zoomIsClamped() {
          assertEquals(8f, ImageTransform(4f, 0f, 0f).zoom(10f, 0f, 0f, 0.5f, 8f).scale, 0f)
          assertEquals(0.5f, ImageTransform(1f, 0f, 0f).zoom(0.01f, 0f, 0f, 0.5f, 8f).scale, 0f)
      }

      @Test fun panMovesOffset() {
          val t = ImageTransform(1f, 0f, 0f).pan(5f, -3f)
          assertEquals(5f, t.offsetX, 0f); assertEquals(-3f, t.offsetY, 0f)
      }
  }
  ```

- [ ] **Step 2: Run the test to verify it fails**

  Run: `./gradlew :app:testDebugUnitTest --tests "app.piececounter.ui.ImageTransformTest"`
  Expected: compilation FAILS, unresolved reference `ImageTransform`

- [ ] **Step 3: Write the implementation**

  ```kotlin
  package app.piececounter.ui

  import app.piececounter.core.Pt
  import kotlin.math.min

  /** screen = image * scale + offset. The single place that maps between the two spaces. */
  data class ImageTransform(val scale: Float, val offsetX: Float, val offsetY: Float) {
      fun toScreen(p: Pt): Pt = Pt(p.x * scale + offsetX, p.y * scale + offsetY)

      fun toImage(x: Float, y: Float): Pt = Pt((x - offsetX) / scale, (y - offsetY) / scale)

      fun zoom(factor: Float, focusX: Float, focusY: Float, minScale: Float, maxScale: Float): ImageTransform {
          val s = (scale * factor).coerceIn(minScale, maxScale)
          val f = s / scale
          return ImageTransform(s, focusX - (focusX - offsetX) * f, focusY - (focusY - offsetY) * f)
      }

      fun pan(dx: Float, dy: Float): ImageTransform = copy(offsetX = offsetX + dx, offsetY = offsetY + dy)

      companion object {
          fun fit(imageW: Float, imageH: Float, viewW: Float, viewH: Float): ImageTransform {
              val s = min(viewW / imageW, viewH / imageH)
              return ImageTransform(s, (viewW - imageW * s) / 2f, (viewH - imageH * s) / 2f)
          }
      }
  }
  ```

- [ ] **Step 4: Run the test to verify it passes**

  Run: `./gradlew :app:testDebugUnitTest --tests "app.piececounter.ui.ImageTransformTest"`
  Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

  ```bash
  git add app/src/main/java/app/piececounter/ui/ImageTransform.kt app/src/test/java/app/piececounter/ui/ImageTransformTest.kt
  git commit -m "feat(ui): add screen/image coordinate transform

  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
  ```

---

### Task 7: Photo loading, image preparation, sampling (on-device tests)

**Precondition:** the S23 Ultra is connected over USB with USB debugging enabled. Check with `"$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe" devices`, which should list one device as `device`. If it doesn't, stop and ask the user to connect the phone.

**Files:**
- Create: `app/src/main/java/app/piececounter/detect/DetectorConfig.kt`
- Create: `app/src/main/java/app/piececounter/detect/PhotoLoader.kt`
- Create: `app/src/main/java/app/piececounter/detect/PieceDetector.kt` (`prepare`, `sampleAt`; `detect` is added in Task 8)
- Create: `app/src/androidTest/assets/golden/` (3 photos copied from `Test data/`)
- Test: `app/src/androidTest/java/app/piececounter/detect/DetectorTest.kt`

**Interfaces:**
- Consumes: `Lab`, `Pt`, `median` (Task 2)
- Produces:
  - `data class DetectorConfig(...)`, with the defaults below
  - `object PhotoLoader { fun load(open: () -> InputStream, longSide: Int = 2000): Bitmap }`
  - `class PreparedImage { val width: Int; val height: Int; fun release() }`
  - `class PieceDetector(config: DetectorConfig = DetectorConfig()) { fun prepare(bitmap: Bitmap): PreparedImage; fun sampleAt(img: PreparedImage, tap: Pt): List<Lab>? }`

- [ ] **Step 1: Copy the golden photos into test assets**

  ```bash
  mkdir -p app/src/androidTest/assets/golden
  cp "Test data/20261014_182938.jpg" "Test data/20261014_182953.jpg" "Test data/20261014_183235.jpg" app/src/androidTest/assets/golden/
  ```

- [ ] **Step 2: Write the failing test**

  `app/src/androidTest/java/app/piececounter/detect/DetectorTest.kt`:

  ```kotlin
  package app.piececounter.detect

  import androidx.test.ext.junit.runners.AndroidJUnit4
  import androidx.test.platform.app.InstrumentationRegistry
  import app.piececounter.core.Pt
  import org.junit.Assert.assertEquals
  import org.junit.Assert.assertNotNull
  import org.junit.Assert.assertNull
  import org.junit.Assert.assertTrue
  import org.junit.Before
  import org.junit.Test
  import org.junit.runner.RunWith
  import org.opencv.android.OpenCVLoader
  import kotlin.math.abs

  @RunWith(AndroidJUnit4::class)
  class DetectorTest {
      private val ctx = InstrumentationRegistry.getInstrumentation().context
      private val detector = PieceDetector()
      private fun loadGolden(name: String) = PhotoLoader.load({ ctx.assets.open("golden/$name") })

      @Before fun initOpenCv() { assertTrue(OpenCVLoader.initLocal()) }

      @Test fun portraitPhotoIsRotatedUprightAndScaled() {
          val b = loadGolden("20261014_182938.jpg")
          assertEquals(1126, b.width)
          assertEquals(2000, b.height)
      }

      @Test fun sampleOnGreyPieceGivesTwoNeutralCentroids() {
          val img = detector.prepare(loadGolden("20261014_182938.jpg"))
          val c = detector.sampleAt(img, Pt(715f, 550f))
          assertNotNull(c)
          assertEquals(2, c!!.size)
          c.forEach { assertTrue("a=${it.a}", abs(it.a) < 4f) }
          img.release()
      }

      @Test fun sampleOutsideImageIsNull() {
          val img = detector.prepare(loadGolden("20261014_182938.jpg"))
          assertNull(detector.sampleAt(img, Pt(-5f, 10f)))
          assertNull(detector.sampleAt(img, Pt(5000f, 10f)))
          img.release()
      }
  }
  ```

- [ ] **Step 3: Run the test to verify it fails**

  Run: `./gradlew :app:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=app.piececounter.detect.DetectorTest`
  Expected: compilation FAILS, unresolved references `PieceDetector`, `PhotoLoader`

- [ ] **Step 4: Write the implementation**

  `app/src/main/java/app/piececounter/detect/DetectorConfig.kt`:

  ```kotlin
  package app.piececounter.detect

  /** Every tunable from spec section 5, defaults validated by the 2026-10-14 spike. */
  data class DetectorConfig(
      val longSide: Int = 2000,
      val blurKernel: Double = 5.0,
      val borderFraction: Float = 0.06f,
      val borderSubsample: Int = 7,
      val clothClusters: Int = 6,
      val floodTolL: Double = 10.0,
      val floodTolA: Double = 6.0,
      val floodTolB: Double = 6.0,
      val minSamplePixels: Int = 30,
      val weightL: Float = 0.35f,
      val maxDistance: Float = 14f,
      val morphKernel: Double = 5.0,
      val medianFloorFraction: Float = 0.05f,
      val minAreaFraction: Float = 0.3f,
      val mergeRatio: Float = 1.7f,
      val maxBlobs: Int = 400,
      val maxPieceFraction: Float = 0.4f,
  )
  ```

  `app/src/main/java/app/piececounter/detect/PhotoLoader.kt`:

  ```kotlin
  package app.piececounter.detect

  import android.graphics.Bitmap
  import android.graphics.BitmapFactory
  import android.graphics.Matrix
  import androidx.exifinterface.media.ExifInterface
  import java.io.InputStream
  import kotlin.math.max
  import kotlin.math.min

  object PhotoLoader {
      /**
       * Decodes without ever holding the full-resolution image: subsamples by a power of two
       * while staying >= [longSide], applies EXIF rotation, then scales down to [longSide].
       * [open] is called three times (bounds, pixels, EXIF).
       */
      fun load(open: () -> InputStream, longSide: Int = 2000): Bitmap {
          val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
          open().use { BitmapFactory.decodeStream(it, null, bounds) }
          require(bounds.outWidth > 0 && bounds.outHeight > 0) { "Not an image" }

          var sample = 1
          while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= longSide) sample *= 2
          val opts = BitmapFactory.Options().apply {
              inSampleSize = sample
              inPreferredConfig = Bitmap.Config.ARGB_8888
          }
          val raw = open().use { BitmapFactory.decodeStream(it, null, opts) }
              ?: throw IllegalArgumentException("Not an image")
          val rotation = open().use { ExifInterface(it).rotationDegrees }

          val scale = min(1f, longSide.toFloat() / max(raw.width, raw.height))
          if (rotation == 0 && scale == 1f) return raw
          val m = Matrix().apply { postRotate(rotation.toFloat()); postScale(scale, scale) }
          return Bitmap.createBitmap(raw, 0, 0, raw.width, raw.height, m, true)
      }
  }
  ```

  `app/src/main/java/app/piececounter/detect/PieceDetector.kt`:

  ```kotlin
  package app.piececounter.detect

  import android.graphics.Bitmap
  import app.piececounter.core.Lab
  import app.piececounter.core.Pt
  import app.piececounter.core.median
  import org.opencv.android.Utils
  import org.opencv.core.Core
  import org.opencv.core.CvType
  import org.opencv.core.Mat
  import org.opencv.core.Point
  import org.opencv.core.Rect
  import org.opencv.core.Scalar
  import org.opencv.core.Size
  import org.opencv.core.TermCriteria
  import org.opencv.imgproc.Imgproc
  import kotlin.math.min

  /** A photo converted once to blurred Lab, plus the learned cloth colours. */
  class PreparedImage internal constructor(
      val width: Int,
      val height: Int,
      internal val lab: FloatArray,   // interleaved L,a,b per pixel, row-major
      internal val labMat: Mat,       // same data as CV_32FC3, used by flood fill
      internal val cloth: List<Lab>,
  ) {
      fun release() = labMat.release()
  }

  class PieceDetector(private val config: DetectorConfig = DetectorConfig()) {

      fun prepare(bitmap: Bitmap): PreparedImage {
          val rgba = Mat(); Utils.bitmapToMat(bitmap, rgba)
          val rgb = Mat(); Imgproc.cvtColor(rgba, rgb, Imgproc.COLOR_RGBA2RGB)
          val f = Mat(); rgb.convertTo(f, CvType.CV_32FC3, 1.0 / 255.0)
          val lab = Mat(); Imgproc.cvtColor(f, lab, Imgproc.COLOR_RGB2Lab)
          Imgproc.GaussianBlur(lab, lab, Size(config.blurKernel, config.blurKernel), 0.0)
          rgba.release(); rgb.release(); f.release()
          val w = lab.cols(); val h = lab.rows()
          val arr = FloatArray(w * h * 3); lab.get(0, 0, arr)
          return PreparedImage(w, h, arr, lab, clothCentroids(arr, w, h))
      }

      /** Spec 5 step 2: k-means over a subsampled border strip. */
      private fun clothCentroids(lab: FloatArray, w: Int, h: Int): List<Lab> {
          val b = (config.borderFraction * min(w, h)).toInt().coerceAtLeast(1)
          val picked = ArrayList<Float>()
          var counter = 0
          for (y in 0 until h) for (x in 0 until w) {
              if (y >= b && y < h - b && x >= b && x < w - b) continue
              if (counter++ % config.borderSubsample != 0) continue
              val i = (y * w + x) * 3
              picked.add(lab[i]); picked.add(lab[i + 1]); picked.add(lab[i + 2])
          }
          val data = Mat(picked.size / 3, 3, CvType.CV_32F)
          data.put(0, 0, picked.toFloatArray())
          val labels = Mat(); val centers = Mat()
          Core.kmeans(
              data, config.clothClusters, labels,
              TermCriteria(TermCriteria.EPS + TermCriteria.MAX_ITER, 30, 0.5),
              3, Core.KMEANS_PP_CENTERS, centers,
          )
          val out = (0 until centers.rows()).map { r ->
              val v = FloatArray(3); centers.get(r, 0, v); Lab(v[0], v[1], v[2])
          }
          data.release(); labels.release(); centers.release()
          return out
      }

      /**
       * Spec 5 step 3: flood-fill from the tap (fixed range) and return the lit-half and
       * shaded-half mean colours. Null when the tap is outside the image or the region is tiny.
       */
      fun sampleAt(img: PreparedImage, tap: Pt): List<Lab>? {
          val x = tap.x.toInt(); val y = tap.y.toInt()
          if (tap.x < 0f || tap.y < 0f || x >= img.width || y >= img.height) return null
          val w = img.width; val h = img.height
          val mask = Mat.zeros(h + 2, w + 2, CvType.CV_8UC1)
          val tol = Scalar(config.floodTolL, config.floodTolA, config.floodTolB)
          val flags = 4 or Imgproc.FLOODFILL_FIXED_RANGE or Imgproc.FLOODFILL_MASK_ONLY or (255 shl 8)
          Imgproc.floodFill(img.labMat, mask, Point(x.toDouble(), y.toDouble()), Scalar(0.0), Rect(), tol, tol, flags)
          val m = ByteArray((w + 2) * (h + 2)); mask.get(0, 0, m); mask.release()

          val px = ArrayList<Lab>()
          for (yy in 0 until h) for (xx in 0 until w) {
              if (m[(yy + 1) * (w + 2) + xx + 1] == 0.toByte()) continue
              val i = (yy * w + xx) * 3
              px.add(Lab(img.lab[i], img.lab[i + 1], img.lab[i + 2]))
          }
          if (px.size < config.minSamplePixels) return null
          val medL = median(px.map { it.l })
          return listOfNotNull(mean(px.filter { it.l >= medL }), mean(px.filter { it.l < medL }))
      }

      private fun mean(p: List<Lab>): Lab? {
          if (p.isEmpty()) return null
          var l = 0.0; var a = 0.0; var b = 0.0
          p.forEach { l += it.l; a += it.a; b += it.b }
          return Lab((l / p.size).toFloat(), (a / p.size).toFloat(), (b / p.size).toFloat())
      }
  }
  ```

- [ ] **Step 5: Run the test to verify it passes**

  Run: `./gradlew :app:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=app.piececounter.detect.DetectorTest`
  Expected: PASS (3 tests)

- [ ] **Step 6: Commit**

  ```bash
  git add app/src/main/java/app/piececounter/detect app/src/androidTest
  git commit -m "feat(detect): load photos upright, prepare Lab image, sample taps

  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
  ```

---

### Task 8: Piece detection and the golden-set test

**Files:**
- Modify: `app/src/main/java/app/piececounter/detect/PieceDetector.kt` (add `TypeModel`, `Detection`, `DetectionWarning`, `detect`)
- Create: `app/src/androidTest/assets/golden/golden.json`
- Test: `app/src/androidTest/java/app/piececounter/detect/GoldenSetTest.kt`

**Interfaces:**
- Consumes: `PreparedImage`, `PieceDetector.sampleAt` (Task 7); `Piece`, `Pt`, `Box`, `median` (Task 2)
- Produces:
  - `data class TypeModel(val typeId: Int, val centroids: List<Lab>)`
  - `enum class DetectionWarning { NoPieces, SurfaceTooSimilar }`
  - `class Detection(val pieces: List<Piece>, val warning: DetectionWarning?, val mask: Bitmap?)`
  - `fun PieceDetector.detect(img: PreparedImage, types: List<TypeModel>): Detection`. Detected piece ids are `0..n-1` in (centre y, centre x) order.

- [ ] **Step 1: Write the golden data and the failing test**

  `app/src/androidTest/assets/golden/golden.json` (tap positions are in 2000-px upright image coordinates, taken from the spike; `allowance` is the spike's baseline error, which the implementation must match or beat):

  ```json
  [
    {"file": "20261014_182938.jpg", "types": [
      {"name": "brown",  "taps": [[365, 300], [230, 550]],             "expected": 28, "allowance": 3},
      {"name": "grey",   "taps": [[715, 550]],                         "expected": 12, "allowance": 0},
      {"name": "red",    "taps": [[480, 970]],                         "expected": 18, "allowance": 0},
      {"name": "yellow", "taps": [[990, 1105], [1072, 1210]],          "expected": 10, "allowance": 1}
    ]},
    {"file": "20261014_182953.jpg", "types": [
      {"name": "brown",  "taps": [[995, 865], [578, 655], [350, 757]], "expected": 28, "allowance": 7},
      {"name": "grey",   "taps": [[717, 177]],                         "expected": 12, "allowance": 0},
      {"name": "red",    "taps": [[1660, 660]],                        "expected": 18, "allowance": 1},
      {"name": "yellow", "taps": [[1200, 75]],                         "expected": 10, "allowance": 0}
    ]},
    {"file": "20261014_183235.jpg", "types": [
      {"name": "red",    "taps": [[140, 700], [810, 490], [275, 830], [360, 690]], "expected": 12, "allowance": 0},
      {"name": "yellow", "taps": [[925, 560]],                         "expected": 12, "allowance": 1}
    ]}
  ]
  ```

  `app/src/androidTest/java/app/piececounter/detect/GoldenSetTest.kt`:

  ```kotlin
  package app.piececounter.detect

  import android.util.Log
  import androidx.test.ext.junit.runners.AndroidJUnit4
  import androidx.test.platform.app.InstrumentationRegistry
  import app.piececounter.core.Pt
  import org.json.JSONArray
  import org.junit.Assert.assertTrue
  import org.junit.Test
  import org.junit.runner.RunWith
  import org.opencv.android.OpenCVLoader
  import kotlin.math.abs

  @RunWith(AndroidJUnit4::class)
  class GoldenSetTest {
      @Test fun goldenPhotosCountWithinAllowance() {
          assertTrue(OpenCVLoader.initLocal())
          val ctx = InstrumentationRegistry.getInstrumentation().context
          val photos = JSONArray(ctx.assets.open("golden/golden.json").bufferedReader().readText())
          val detector = PieceDetector()
          val failures = mutableListOf<String>()

          for (i in 0 until photos.length()) {
              val photo = photos.getJSONObject(i)
              val file = photo.getString("file")
              val img = detector.prepare(PhotoLoader.load({ ctx.assets.open("golden/$file") }))
              val types = photo.getJSONArray("types")
              val models = (0 until types.length()).map { t ->
                  val taps = types.getJSONObject(t).getJSONArray("taps")
                  TypeModel(t, (0 until taps.length()).flatMap { k ->
                      val p = taps.getJSONArray(k)
                      detector.sampleAt(img, Pt(p.getDouble(0).toFloat(), p.getDouble(1).toFloat()))
                          ?: error("$file: tap $k of type $t sampled too few pixels")
                  })
              }
              val detection = detector.detect(img, models)
              for (t in 0 until types.length()) {
                  val spec = types.getJSONObject(t)
                  val found = detection.pieces.filter { it.typeId == t }.sumOf { it.estimatedCount }
                  val delta = found - spec.getInt("expected")
                  val line = "$file ${spec.getString("name")}: found $found, expected ${spec.getInt("expected")}, delta $delta"
                  Log.i("GoldenSet", line)
                  if (abs(delta) > spec.getInt("allowance")) failures += line
              }
              img.release()
          }
          assertTrue("Outside allowance:\n" + failures.joinToString("\n"), failures.isEmpty())
      }
  }
  ```

- [ ] **Step 2: Run the test to verify it fails**

  Run: `./gradlew :app:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=app.piececounter.detect.GoldenSetTest`
  Expected: compilation FAILS, unresolved references `TypeModel`, `detect`

- [ ] **Step 3: Add detection to `PieceDetector.kt`**

  Add these imports to the existing import block:

  ```kotlin
  import app.piececounter.core.Box
  import app.piececounter.core.Piece
  import org.opencv.core.MatOfPoint
  import kotlin.math.roundToInt
  ```

  Add these top-level declarations after the `PreparedImage` class:

  ```kotlin
  data class TypeModel(val typeId: Int, val centroids: List<Lab>)

  enum class DetectionWarning { NoPieces, SurfaceTooSimilar }

  class Detection(val pieces: List<Piece>, val warning: DetectionWarning?, val mask: Bitmap?)

  private const val FILLED = -1
  ```

  Add this method inside `class PieceDetector`:

  ```kotlin
  /** Spec 5 steps 4–9. */
  fun detect(img: PreparedImage, types: List<TypeModel>): Detection {
      val models = types.filter { it.centroids.isNotEmpty() }
      if (models.isEmpty()) return Detection(emptyList(), null, null)
      val w = img.width; val h = img.height; val n = w * h
      val wl = config.weightL

      // Step 4: piece vs cloth, nearest centroid (L down-weighted).
      val tc = models.flatMapIndexed { idx, m -> m.centroids.map { idx to it } }
      val tL = FloatArray(tc.size) { tc[it].second.l * wl }
      val tA = FloatArray(tc.size) { tc[it].second.a }
      val tB = FloatArray(tc.size) { tc[it].second.b }
      val tOwner = IntArray(tc.size) { tc[it].first }
      val cL = FloatArray(img.cloth.size) { img.cloth[it].l * wl }
      val cA = FloatArray(img.cloth.size) { img.cloth[it].a }
      val cB = FloatArray(img.cloth.size) { img.cloth[it].b }
      val maxD2 = config.maxDistance * config.maxDistance
      val owner = IntArray(n) { -1 }
      val maskBytes = ByteArray(n)
      var pieceCount = 0
      val lab = img.lab
      for (i in 0 until n) {
          val l = lab[3 * i] * wl; val a = lab[3 * i + 1]; val b = lab[3 * i + 2]
          var dBg = Float.MAX_VALUE
          for (k in cL.indices) {
              val dl = l - cL[k]; val da = a - cA[k]; val db = b - cB[k]
              val d = dl * dl + da * da + db * db
              if (d < dBg) dBg = d
          }
          var dT = Float.MAX_VALUE; var best = -1
          for (k in tL.indices) {
              val dl = l - tL[k]; val da = a - tA[k]; val db = b - tB[k]
              val d = dl * dl + da * da + db * db
              if (d < dT) { dT = d; best = tOwner[k] }
          }
          if (dT < dBg && dT < maxD2) { owner[i] = best; maskBytes[i] = 255.toByte(); pieceCount++ }
      }

      // Step 5: clean.
      val mask = Mat(h, w, CvType.CV_8UC1); mask.put(0, 0, maskBytes)
      val kernel = Imgproc.getStructuringElement(Imgproc.MORPH_ELLIPSE, Size(config.morphKernel, config.morphKernel))
      Imgproc.morphologyEx(mask, mask, Imgproc.MORPH_OPEN, kernel)
      Imgproc.morphologyEx(mask, mask, Imgproc.MORPH_CLOSE, kernel, Point(-1.0, -1.0), 2)

      // Step 6: blobs (external contours, interiors filled via the label image).
      val contours = mutableListOf<MatOfPoint>()
      val hierarchy = Mat()
      Imgproc.findContours(mask, contours, hierarchy, Imgproc.RETR_EXTERNAL, Imgproc.CHAIN_APPROX_SIMPLE)
      val labels = Mat.zeros(h, w, CvType.CV_32SC1)
      contours.indices.forEach { Imgproc.drawContours(labels, contours, it, Scalar((it + 1).toDouble()), FILLED) }
      val labelArr = IntArray(n); labels.get(0, 0, labelArr)

      // Step 7: type per blob by majority vote of its piece pixels.
      val votes = Array(contours.size) { IntArray(models.size) }
      for (i in 0 until n) {
          val lb = labelArr[i]
          if (lb > 0 && owner[i] >= 0) votes[lb - 1][owner[i]]++
      }
      class Blob(val typeIdx: Int, val center: Pt, val bounds: Box, val area: Float, val outline: List<Pt>)
      val blobs = contours.mapIndexedNotNull { idx, c ->
          val v = votes[idx]
          val t = v.indices.maxBy { v[it] }
          val mo = Imgproc.moments(c)
          if (v[t] == 0 || mo.m00 <= 0.0) return@mapIndexedNotNull null
          val r = Imgproc.boundingRect(c)
          Blob(
              t,
              Pt((mo.m10 / mo.m00).toFloat(), (mo.m01 / mo.m00).toFloat()),
              Box(r.x.toFloat(), r.y.toFloat(), (r.x + r.width).toFloat(), (r.y + r.height).toFloat()),
              Imgproc.contourArea(c).toFloat(),
              c.toArray().map { Pt(it.x.toFloat(), it.y.toFloat()) },
          )
      }

      // Steps 8–9: per-type noise filter and merged estimate.
      val kept = mutableListOf<Pair<Blob, Int>>()
      for (t in models.indices) {
          val mine = blobs.filter { it.typeIdx == t }
          if (mine.isEmpty()) continue
          val floor = config.medianFloorFraction * mine.maxOf { it.area }
          val med = median(mine.map { it.area }.filter { it >= floor })
          for (b in mine) {
              if (b.area < config.minAreaFraction * med) continue
              val ratio = b.area / med
              kept += b to (if (ratio >= config.mergeRatio) ratio.roundToInt() else 1)
          }
      }
      val pieces = kept
          .sortedWith(compareBy({ it.first.center.y }, { it.first.center.x }))
          .mapIndexed { id, (b, est) ->
              Piece(id, b.center, b.bounds, b.area, b.outline, models[b.typeIdx].typeId, est)
          }

      val warning = when {
          pieces.isEmpty() -> DetectionWarning.NoPieces
          contours.size > config.maxBlobs || pieceCount > config.maxPieceFraction * n -> DetectionWarning.SurfaceTooSimilar
          else -> null
      }

      // Debug mask preview (filled blobs).
      val preview = Mat.zeros(h, w, CvType.CV_8UC1)
      Imgproc.drawContours(preview, contours, -1, Scalar(255.0), FILLED)
      val maskBitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
      Utils.matToBitmap(preview, maskBitmap)

      listOf(mask, kernel, hierarchy, labels, preview).forEach { it.release() }
      contours.forEach { it.release() }
      return Detection(pieces, warning, maskBitmap)
  }
  ```

- [ ] **Step 4: Run the golden test**

  Run: `./gradlew :app:connectedDebugAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=app.piececounter.detect.GoldenSetTest`
  Expected: PASS. Read the per-type lines with `"$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe" logcat -d -s GoldenSet`.
  If any line is outside its allowance: **stop**, report all the `GoldenSet` lines to the user, and do not change `golden.json`.

- [ ] **Step 5: Run the whole instrumented suite**

  Run: `./gradlew :app:connectedDebugAndroidTest`
  Expected: PASS (DetectorTest + GoldenSetTest + the template's example test)

- [ ] **Step 6: Commit**

  ```bash
  git add app/src/main/java/app/piececounter/detect app/src/androidTest
  git commit -m "feat(detect): sample-driven piece detection with golden-set test

  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
  ```

---

### Task 9: ViewModel, app shell, start screen, camera and gallery

UI tasks (9–11) have no automated UI tests. Their logic lives in `core/`, which is already tested. Verification is a build plus the on-device check in each task.

**Files:**
- Create: `app/src/main/java/app/piececounter/ui/CounterViewModel.kt`
- Create: `app/src/main/java/app/piececounter/ui/Common.kt`
- Create: `app/src/main/java/app/piececounter/ui/StartScreen.kt`
- Create: `app/src/main/res/xml/file_paths.xml`
- Modify: `app/src/main/java/app/piececounter/MainActivity.kt` (replace the template's content)
- Modify: `app/src/main/AndroidManifest.xml` (add the FileProvider)

**Interfaces:**
- Consumes: everything in `core/` (Tasks 2–5), `ImageTransform` (Task 6), `PhotoLoader`, `PieceDetector`, `TypeModel`, `Detection`, `DetectionWarning` (Tasks 7–8)
- Produces, for Tasks 10–11:
  - `enum class Screen { Start, PickTypes, Results }`
  - `data class UiState(screen, session: Session?, image: ImageBitmap?, detection: Detection?, results: List<TypeResult>, swatches: Map<Int, Int>, busy, message: String?, selectedTypeId: Int?, showMask, showDots, menuPieceId: Int?, samplePromptAt: Pt?)`
  - `CounterViewModel` with `ui` and the methods `cameraTarget()`, `onCameraResult(Boolean)`, `onGalleryResult(Uri?)`, `onPickTap(Pt)`, `selectType(Int)`, `renameType(Int, String)`, `setExpected(Int, String)`, `deleteType(Int)`, `toggleMask()`, `toggleDots()`, `count()`, `back()`, `newPhoto()`, `messageShown()`, `onResultTap(Pt)`, `onResultLongPress(Pt)`, `addSampleFromResults(Int)`, `dismissMenus()`, `removePiece(Int)`, `movePiece(Int, Int)`, `setCount(Int, Int)`
  - In `Common.kt`: `ZoomableImage(image, modifier, onTap, onLongPress, overlay: DrawScope.(ImageTransform) -> Unit)`, `DrawScope.drawPhoto(image, t, alpha)`, `markerColor(index): Color`, `DrawScope.drawOutline(outline, t, color, dashed)`, `DrawScope.drawLabel(measurer, text, at, color, sizePx)`, `DrawScope.drawDot(at, color, radius)`, `rememberMessageSnackbar(message, onShown): SnackbarHostState`, `WarningBanner(warning, onRetake, onCountByHand, modifier)`

- [ ] **Step 1: Add the FileProvider**

  `app/src/main/res/xml/file_paths.xml`:

  ```xml
  <?xml version="1.0" encoding="utf-8"?>
  <paths>
      <cache-path name="photos" path="photos/" />
  </paths>
  ```

  In `app/src/main/AndroidManifest.xml`, inside `<application>`, after the `<activity>` element:

  ```xml
  <provider
      android:name="androidx.core.content.FileProvider"
      android:authorities="${applicationId}.files"
      android:exported="false"
      android:grantUriPermissions="true">
      <meta-data
          android:name="android.support.FILE_PROVIDER_PATHS"
          android:resource="@xml/file_paths" />
  </provider>
  ```

- [ ] **Step 2: Write the ViewModel**

  `app/src/main/java/app/piececounter/ui/CounterViewModel.kt`:

  ```kotlin
  package app.piececounter.ui

  import android.app.Application
  import android.net.Uri
  import androidx.compose.runtime.getValue
  import androidx.compose.runtime.mutableStateOf
  import androidx.compose.runtime.setValue
  import androidx.compose.ui.graphics.ImageBitmap
  import androidx.compose.ui.graphics.asImageBitmap
  import androidx.core.content.FileProvider
  import androidx.lifecycle.AndroidViewModel
  import androidx.lifecycle.SavedStateHandle
  import androidx.lifecycle.viewModelScope
  import app.piececounter.core.ColorMath
  import app.piececounter.core.Pt
  import app.piececounter.core.Session
  import app.piececounter.core.SessionEdits
  import app.piececounter.core.TypeResult
  import app.piececounter.core.buildResults
  import app.piececounter.core.hitTest
  import app.piececounter.core.parseExpected
  import app.piececounter.core.typicalSize
  import app.piececounter.detect.Detection
  import app.piececounter.detect.PhotoLoader
  import app.piececounter.detect.PieceDetector
  import app.piececounter.detect.PreparedImage
  import app.piececounter.detect.TypeModel
  import kotlinx.coroutines.Dispatchers
  import kotlinx.coroutines.Job
  import kotlinx.coroutines.launch
  import kotlinx.coroutines.withContext
  import kotlinx.serialization.Serializable
  import kotlinx.serialization.json.Json
  import java.io.File
  import java.io.FileInputStream

  @Serializable
  enum class Screen { Start, PickTypes, Results }

  @Serializable
  private data class Saved(val screen: Screen, val session: Session)

  data class UiState(
      val screen: Screen = Screen.Start,
      val session: Session? = null,
      val image: ImageBitmap? = null,
      val detection: Detection? = null,
      val results: List<TypeResult> = emptyList(),
      val swatches: Map<Int, Int> = emptyMap(),
      val busy: Boolean = false,
      val message: String? = null,
      val selectedTypeId: Int? = null,
      val showMask: Boolean = false,
      val showDots: Boolean = false,
      val menuPieceId: Int? = null,
      val samplePromptAt: Pt? = null,
  )

  private const val KEY = "session"
  private const val SAMPLE_HIT_RADIUS = 30f   // image px

  class CounterViewModel(app: Application, private val saved: SavedStateHandle) : AndroidViewModel(app) {
      private val detector = PieceDetector()
      private var prepared: PreparedImage? = null
      private var detectJob: Job? = null

      var ui by mutableStateOf(UiState())
          private set

      init {
          saved.get<String>(KEY)?.let { json ->
              val s = Json.decodeFromString<Saved>(json)
              viewModelScope.launch {
                  if (open(s.session.photoPath)) { setSession(s.session, s.screen); redetect() }
              }
          }
      }

      // ---- Start screen ----

      private fun photoFile() = File(getApplication<Application>().cacheDir, "photos/photo.jpg")

      fun cameraTarget(): Uri {
          val f = photoFile().also { it.parentFile?.mkdirs() }
          val app = getApplication<Application>()
          return FileProvider.getUriForFile(app, "${app.packageName}.files", f)
      }

      fun onCameraResult(success: Boolean) { if (success) startSession(photoFile().path) }

      fun onGalleryResult(uri: Uri?) {
          if (uri == null) return
          viewModelScope.launch {
              val ok = withContext(Dispatchers.IO) {
                  runCatching {
                      val input = getApplication<Application>().contentResolver.openInputStream(uri)
                          ?: error("no stream")
                      input.use { i -> photoFile().also { it.parentFile?.mkdirs() }.outputStream().use { i.copyTo(it) } }
                  }.isSuccess
              }
              if (ok) startSession(photoFile().path) else ui = ui.copy(message = "Couldn't open that photo — try another")
          }
      }

      private fun startSession(path: String) {
          viewModelScope.launch {
              if (open(path)) {
                  ui = ui.copy(detection = null, results = emptyList(), swatches = emptyMap(), selectedTypeId = null)
                  setSession(Session(path), Screen.PickTypes)
              }
          }
      }

      private suspend fun open(path: String): Boolean {
          ui = ui.copy(busy = true)
          val result = withContext(Dispatchers.Default) {
              runCatching {
                  val bmp = PhotoLoader.load({ FileInputStream(path) })
                  bmp to detector.prepare(bmp)
              }
          }
          ui = ui.copy(busy = false)
          return result.fold(
              onSuccess = { (bmp, img) ->
                  prepared?.release(); prepared = img
                  ui = ui.copy(image = bmp.asImageBitmap()); true
              },
              onFailure = { ui = ui.copy(message = "Couldn't open that photo — try another"); false },
          )
      }

      // ---- Session plumbing ----

      private fun setSession(s: Session, screen: Screen = ui.screen) {
          ui = ui.copy(
              session = s, screen = screen,
              results = ui.detection?.let { buildResults(s, it.pieces) } ?: emptyList(),
          )
          saved[KEY] = Json.encodeToString(Saved.serializer(), Saved(screen, s))
      }

      private inline fun edit(f: (Session) -> Session) { ui.session?.let { setSession(f(it)) } }

      private fun redetect() {
          val img = prepared ?: return
          val s = ui.session ?: return
          val oldPieces = ui.detection?.pieces
          detectJob?.cancel()
          detectJob = viewModelScope.launch {
              ui = ui.copy(busy = true)
              val (det, swatches) = withContext(Dispatchers.Default) {
                  val models = s.types.map { t ->
                      TypeModel(t.id, t.samples.flatMap { detector.sampleAt(img, it) ?: emptyList() })
                  }
                  detector.detect(img, models) to models.associate { m ->
                      m.typeId to (m.centroids.firstOrNull()?.let(ColorMath::labToSrgb) ?: 0xFF888888.toInt())
                  }
              }
              val current = ui.session ?: return@launch
              val remapped = if (oldPieces != null) SessionEdits.remapEdits(current, oldPieces, det.pieces) else current
              ui = ui.copy(detection = det, swatches = swatches, busy = false)
              setSession(remapped)
          }
      }

      // ---- Pick types screen ----

      fun onPickTap(p: Pt) {
          val s = ui.session ?: return
          val img = prepared ?: return
          SessionEdits.sampleNear(s, p, SAMPLE_HIT_RADIUS)?.let { (typeId, idx) ->
              setSession(SessionEdits.removeSample(s, typeId, idx)); redetect(); return
          }
          viewModelScope.launch {
              val ok = withContext(Dispatchers.Default) { detector.sampleAt(img, p) != null }
              if (!ok) { ui = ui.copy(message = "Tap the middle of a piece"); return@launch }
              val cur = ui.session ?: return@launch
              val sel = ui.selectedTypeId?.takeIf { id -> cur.types.any { it.id == id } }
              setSession(if (sel != null) SessionEdits.addSample(cur, sel, p) else SessionEdits.addType(cur, p).first)
              redetect()
          }
      }

      fun selectType(id: Int) { ui = ui.copy(selectedTypeId = if (ui.selectedTypeId == id) null else id) }
      fun renameType(id: Int, name: String) = edit { SessionEdits.rename(it, id, name) }
      fun setExpected(id: Int, text: String) = edit { SessionEdits.setExpected(it, id, parseExpected(text)) }

      fun deleteType(id: Int) {
          edit { SessionEdits.removeType(it, id) }
          if (ui.selectedTypeId == id) ui = ui.copy(selectedTypeId = null)
          redetect()
      }

      fun toggleMask() { ui = ui.copy(showMask = !ui.showMask) }
      fun toggleDots() { ui = ui.copy(showDots = !ui.showDots) }

      fun count() {
          val s = ui.session ?: return
          if (s.types.isNotEmpty()) setSession(s, Screen.Results)
      }

      fun back() {
          when (ui.screen) {
              Screen.Results -> ui.session?.let { setSession(it, Screen.PickTypes) }
              Screen.PickTypes -> newPhoto()
              Screen.Start -> Unit
          }
      }

      fun newPhoto() {
          detectJob?.cancel()
          prepared?.release(); prepared = null
          saved.remove<String>(KEY)
          ui = UiState()
      }

      fun messageShown() { ui = ui.copy(message = null) }

      // ---- Results screen ----

      private fun currentPieces() = ui.results.flatMap { r -> r.pieces.map { it.piece } }

      fun onResultTap(p: Pt) {
          val s = ui.session ?: return
          val all = currentPieces()
          hitTest(all, p)?.let { ui = ui.copy(menuPieceId = it.id); return }
          val typeId = ui.selectedTypeId?.takeIf { id -> s.types.any { it.id == id } } ?: s.types.firstOrNull()?.id ?: return
          val size = typicalSize(all.filter { it.typeId == typeId })
          edit { SessionEdits.addPiece(it, typeId, p, size) }
      }

      fun onResultLongPress(p: Pt) {
          if (hitTest(currentPieces(), p) == null) ui = ui.copy(samplePromptAt = p)
      }

      fun addSampleFromResults(typeId: Int) {
          val p = ui.samplePromptAt ?: return
          ui = ui.copy(samplePromptAt = null)
          edit { SessionEdits.addSample(it, typeId, p) }
          redetect()
      }

      fun dismissMenus() { ui = ui.copy(menuPieceId = null, samplePromptAt = null) }
      fun removePiece(id: Int) { edit { SessionEdits.removePiece(it, id) }; dismissMenus() }
      fun movePiece(id: Int, typeId: Int) { edit { SessionEdits.movePiece(it, id, typeId) }; dismissMenus() }
      fun setCount(id: Int, n: Int) { edit { SessionEdits.setCount(it, id, n) }; dismissMenus() }

      override fun onCleared() { prepared?.release() }
  }
  ```

- [ ] **Step 3: Write the shared UI pieces**

  `app/src/main/java/app/piececounter/ui/Common.kt`:

  ```kotlin
  package app.piececounter.ui

  import androidx.compose.foundation.Canvas
  import androidx.compose.foundation.gestures.detectTapGestures
  import androidx.compose.foundation.gestures.detectTransformGestures
  import androidx.compose.foundation.layout.Column
  import androidx.compose.foundation.layout.Row
  import androidx.compose.foundation.layout.fillMaxSize
  import androidx.compose.foundation.layout.fillMaxWidth
  import androidx.compose.foundation.layout.padding
  import androidx.compose.material3.MaterialTheme
  import androidx.compose.material3.SnackbarHostState
  import androidx.compose.material3.Surface
  import androidx.compose.material3.Text
  import androidx.compose.material3.TextButton
  import androidx.compose.runtime.Composable
  import androidx.compose.runtime.LaunchedEffect
  import androidx.compose.runtime.getValue
  import androidx.compose.runtime.mutableFloatStateOf
  import androidx.compose.runtime.mutableStateOf
  import androidx.compose.runtime.remember
  import androidx.compose.runtime.rememberUpdatedState
  import androidx.compose.runtime.setValue
  import androidx.compose.ui.Modifier
  import androidx.compose.ui.draw.clipToBounds
  import androidx.compose.ui.geometry.Offset
  import androidx.compose.ui.graphics.Color
  import androidx.compose.ui.graphics.ImageBitmap
  import androidx.compose.ui.graphics.Path
  import androidx.compose.ui.graphics.PathEffect
  import androidx.compose.ui.graphics.drawscope.DrawScope
  import androidx.compose.ui.graphics.drawscope.Stroke
  import androidx.compose.ui.input.pointer.pointerInput
  import androidx.compose.ui.layout.onSizeChanged
  import androidx.compose.ui.text.TextMeasurer
  import androidx.compose.ui.text.TextStyle
  import androidx.compose.ui.text.drawText
  import androidx.compose.ui.text.font.FontWeight
  import androidx.compose.ui.unit.IntOffset
  import androidx.compose.ui.unit.IntSize
  import androidx.compose.ui.unit.dp
  import app.piececounter.core.Pt
  import app.piececounter.detect.DetectionWarning
  import kotlin.math.roundToInt

  private val MarkerPalette = listOf(
      Color(0xFF00E5FF), Color(0xFFFF00FF), Color(0xFFFFEA00), Color(0xFF76FF03),
      Color(0xFFFF6D00), Color(0xFFFFFFFF), Color(0xFF2979FF), Color(0xFFFF1744),
  )

  /** High-contrast marker colour per type position (not the piece's own colour, which would vanish on the piece). */
  fun markerColor(index: Int): Color = MarkerPalette[index.coerceAtLeast(0) % MarkerPalette.size]

  @Composable
  fun ZoomableImage(
      image: ImageBitmap,
      modifier: Modifier = Modifier,
      onTap: (Pt) -> Unit,
      onLongPress: (Pt) -> Unit = {},
      overlay: DrawScope.(ImageTransform) -> Unit = {},
  ) {
      var transform by remember(image) { mutableStateOf<ImageTransform?>(null) }
      var fitScale by remember(image) { mutableFloatStateOf(1f) }
      val tap by rememberUpdatedState(onTap)
      val longPress by rememberUpdatedState(onLongPress)
      Canvas(
          modifier
              .fillMaxSize()
              .clipToBounds()
              .onSizeChanged { size ->
                  val fit = ImageTransform.fit(
                      image.width.toFloat(), image.height.toFloat(), size.width.toFloat(), size.height.toFloat(),
                  )
                  fitScale = fit.scale
                  if (transform == null) transform = fit
              }
              .pointerInput(image) {
                  detectTransformGestures { centroid, pan, zoom, _ ->
                      transform = transform?.zoom(zoom, centroid.x, centroid.y, fitScale, fitScale * 10f)?.pan(pan.x, pan.y)
                  }
              }
              .pointerInput(image) {
                  detectTapGestures(
                      onTap = { o -> transform?.let { tap(it.toImage(o.x, o.y)) } },
                      onLongPress = { o -> transform?.let { longPress(it.toImage(o.x, o.y)) } },
                  )
              },
      ) {
          val t = transform ?: return@Canvas
          drawPhoto(image, t)
          overlay(t)
      }
  }

  fun DrawScope.drawPhoto(image: ImageBitmap, t: ImageTransform, alpha: Float = 1f) {
      drawImage(
          image,
          dstOffset = IntOffset(t.offsetX.roundToInt(), t.offsetY.roundToInt()),
          dstSize = IntSize((image.width * t.scale).roundToInt(), (image.height * t.scale).roundToInt()),
          alpha = alpha,
      )
  }

  fun DrawScope.drawOutline(outline: List<Pt>, t: ImageTransform, color: Color, dashed: Boolean = false) {
      if (outline.size < 2) return
      val path = Path().apply {
          outline.forEachIndexed { i, p ->
              val s = t.toScreen(p)
              if (i == 0) moveTo(s.x, s.y) else lineTo(s.x, s.y)
          }
          close()
      }
      val effect = if (dashed) PathEffect.dashPathEffect(floatArrayOf(12f, 8f)) else null
      drawPath(path, color, style = Stroke(width = 2.dp.toPx(), pathEffect = effect))
  }

  fun DrawScope.drawLabel(measurer: TextMeasurer, text: String, at: Offset, color: Color, sizePx: Float) {
      val base = TextStyle(fontSize = sizePx.toSp(), fontWeight = FontWeight.Bold)
      val layout = measurer.measure(text, base)
      val topLeft = Offset(at.x - layout.size.width / 2f, at.y - layout.size.height / 2f)
      drawText(measurer, text, topLeft, base.copy(color = Color.Black, drawStyle = Stroke(width = sizePx / 5f)))
      drawText(measurer, text, topLeft, base.copy(color = color))
  }

  fun DrawScope.drawDot(at: Offset, color: Color, radius: Float) {
      drawCircle(Color.Black, radius * 1.35f, at)
      drawCircle(color, radius, at)
  }

  @Composable
  fun rememberMessageSnackbar(message: String?, onShown: () -> Unit): SnackbarHostState {
      val host = remember { SnackbarHostState() }
      LaunchedEffect(message) {
          if (message != null) { host.showSnackbar(message); onShown() }
      }
      return host
  }

  @Composable
  fun WarningBanner(
      warning: DetectionWarning?,
      onRetake: () -> Unit,
      onCountByHand: () -> Unit,
      modifier: Modifier = Modifier,
  ) {
      warning ?: return
      Surface(
          color = MaterialTheme.colorScheme.errorContainer,
          shape = MaterialTheme.shapes.medium,
          modifier = modifier.fillMaxWidth().padding(8.dp),
      ) {
          Column(Modifier.padding(12.dp)) {
              when (warning) {
                  DetectionWarning.NoPieces -> {
                      Text("No pieces found. Use a plainer surface with more contrast, or tap a piece again to add a sample.")
                      Row {
                          TextButton(onClick = onRetake) { Text("Retake") }
                          TextButton(onClick = onCountByHand) { Text("Count by hand") }
                      }
                  }
                  DetectionWarning.SurfaceTooSimilar ->
                      Text("The surface looks too similar to the pieces — results may be off")
              }
          }
      }
  }
  ```

- [ ] **Step 4: Write the start screen**

  `app/src/main/java/app/piececounter/ui/StartScreen.kt`:

  ```kotlin
  package app.piececounter.ui

  import androidx.activity.compose.rememberLauncherForActivityResult
  import androidx.activity.result.PickVisualMediaRequest
  import androidx.activity.result.contract.ActivityResultContracts
  import androidx.compose.foundation.layout.Arrangement
  import androidx.compose.foundation.layout.Column
  import androidx.compose.foundation.layout.Spacer
  import androidx.compose.foundation.layout.fillMaxSize
  import androidx.compose.foundation.layout.fillMaxWidth
  import androidx.compose.foundation.layout.height
  import androidx.compose.foundation.layout.padding
  import androidx.compose.material3.Button
  import androidx.compose.material3.CircularProgressIndicator
  import androidx.compose.material3.MaterialTheme
  import androidx.compose.material3.OutlinedButton
  import androidx.compose.material3.Scaffold
  import androidx.compose.material3.SnackbarHost
  import androidx.compose.material3.Text
  import androidx.compose.runtime.Composable
  import androidx.compose.ui.Alignment
  import androidx.compose.ui.Modifier
  import androidx.compose.ui.text.style.TextAlign
  import androidx.compose.ui.unit.dp

  @Composable
  fun StartScreen(vm: CounterViewModel) {
      val ui = vm.ui
      val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { vm.onCameraResult(it) }
      val gallery = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { vm.onGalleryResult(it) }
      val snack = rememberMessageSnackbar(ui.message, vm::messageShown)

      Scaffold(snackbarHost = { SnackbarHost(snack) }) { pad ->
          Column(
              Modifier.padding(pad).fillMaxSize().padding(24.dp),
              verticalArrangement = Arrangement.Center,
              horizontalAlignment = Alignment.CenterHorizontally,
          ) {
              Text("PieceCounter", style = MaterialTheme.typography.headlineMedium)
              Spacer(Modifier.height(32.dp))
              Button(onClick = { camera.launch(vm.cameraTarget()) }, enabled = !ui.busy, modifier = Modifier.fillMaxWidth()) {
                  Text("Take photo")
              }
              Spacer(Modifier.height(12.dp))
              OutlinedButton(
                  onClick = { gallery.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                  enabled = !ui.busy,
                  modifier = Modifier.fillMaxWidth(),
              ) { Text("Choose from gallery") }
              Spacer(Modifier.height(24.dp))
              Text(
                  "Plain or evenly patterned surface, pieces spread out, shoot from directly above.",
                  style = MaterialTheme.typography.bodyMedium,
                  textAlign = TextAlign.Center,
              )
              if (ui.busy) {
                  Spacer(Modifier.height(24.dp))
                  CircularProgressIndicator()
              }
          }
      }
  }
  ```

- [ ] **Step 5: Replace `MainActivity.kt`**

  The `PickTypes` and `Results` branches show an interim text until Tasks 10 and 11 replace them.

  ```kotlin
  package app.piececounter

  import android.os.Bundle
  import androidx.activity.ComponentActivity
  import androidx.activity.compose.BackHandler
  import androidx.activity.compose.setContent
  import androidx.activity.enableEdgeToEdge
  import androidx.compose.foundation.layout.Box
  import androidx.compose.foundation.layout.fillMaxSize
  import androidx.compose.foundation.layout.padding
  import androidx.compose.material3.Surface
  import androidx.compose.material3.Text
  import androidx.compose.runtime.Composable
  import androidx.compose.ui.Alignment
  import androidx.compose.ui.Modifier
  import androidx.compose.ui.unit.dp
  import androidx.lifecycle.viewmodel.compose.viewModel
  import app.piececounter.ui.CounterViewModel
  import app.piececounter.ui.Screen
  import app.piececounter.ui.StartScreen
  import app.piececounter.ui.theme.PieceCounterTheme
  import org.opencv.android.OpenCVLoader

  class MainActivity : ComponentActivity() {
      override fun onCreate(savedInstanceState: Bundle?) {
          super.onCreate(savedInstanceState)
          val openCvOk = OpenCVLoader.initLocal()
          enableEdgeToEdge()
          setContent {
              PieceCounterTheme {
                  Surface(Modifier.fillMaxSize()) {
                      if (openCvOk) AppRoot()
                      else Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
                          Text("The image-processing library failed to load. Please reinstall the app.")
                      }
                  }
              }
          }
      }
  }

  @Composable
  private fun AppRoot(vm: CounterViewModel = viewModel()) {
      BackHandler(enabled = vm.ui.screen != Screen.Start) { vm.back() }
      when (vm.ui.screen) {
          Screen.Start -> StartScreen(vm)
          Screen.PickTypes -> Text("Photo loaded (${vm.ui.image?.width}×${vm.ui.image?.height}) — pick-types screen comes in Task 10")
          Screen.Results -> Text("Results screen comes in Task 11")
      }
  }
  ```

- [ ] **Step 6: Build and run the unit tests**

  Run: `./gradlew :app:assembleDebug :app:testDebugUnitTest`
  Expected: `BUILD SUCCESSFUL`, all JVM tests pass

- [ ] **Step 7: Check on the device**

  Run: `./gradlew :app:installDebug`, then open PieceCounter on the phone. Check:
  - **Take photo** opens the Samsung camera. Take a photo of pieces held in portrait → the interim text shows `1126×2000` (or the equivalent for the phone's camera resolution, with the long side 2000 and the height larger than the width).
  - Cancelling the camera returns to the start screen with no message.
  - **Choose from gallery** → pick one of the test photos → the interim text appears.
  - The back button returns to the start screen.

- [ ] **Step 8: Commit**

  ```bash
  git add app/src/main
  git commit -m "feat(ui): view model, start screen, camera and gallery input

  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
  ```

---

### Task 10: Pick-types screen

**Files:**
- Create: `app/src/main/java/app/piececounter/ui/PickTypesScreen.kt`
- Modify: `app/src/main/java/app/piececounter/MainActivity.kt` (the `Screen.PickTypes` branch)

**Interfaces:**
- Consumes: `CounterViewModel`/`UiState` (Task 9), the `Common.kt` helpers (Task 9), `PieceType` (Task 2)
- Produces: `@Composable fun PickTypesScreen(vm: CounterViewModel)`

- [ ] **Step 1: Write the screen**

  ```kotlin
  package app.piececounter.ui

  import androidx.compose.foundation.BorderStroke
  import androidx.compose.foundation.background
  import androidx.compose.foundation.border
  import androidx.compose.foundation.layout.Arrangement
  import androidx.compose.foundation.layout.Box
  import androidx.compose.foundation.layout.Column
  import androidx.compose.foundation.layout.Row
  import androidx.compose.foundation.layout.fillMaxSize
  import androidx.compose.foundation.layout.fillMaxWidth
  import androidx.compose.foundation.layout.navigationBarsPadding
  import androidx.compose.foundation.layout.padding
  import androidx.compose.foundation.layout.size
  import androidx.compose.foundation.layout.width
  import androidx.compose.foundation.lazy.LazyRow
  import androidx.compose.foundation.lazy.itemsIndexed
  import androidx.compose.foundation.text.KeyboardOptions
  import androidx.compose.material3.Button
  import androidx.compose.material3.Card
  import androidx.compose.material3.ExperimentalMaterial3Api
  import androidx.compose.material3.LinearProgressIndicator
  import androidx.compose.material3.MaterialTheme
  import androidx.compose.material3.OutlinedTextField
  import androidx.compose.material3.Scaffold
  import androidx.compose.material3.SnackbarHost
  import androidx.compose.material3.Text
  import androidx.compose.material3.TextButton
  import androidx.compose.material3.TopAppBar
  import androidx.compose.runtime.Composable
  import androidx.compose.runtime.getValue
  import androidx.compose.runtime.mutableStateOf
  import androidx.compose.runtime.remember
  import androidx.compose.runtime.setValue
  import androidx.compose.ui.Alignment
  import androidx.compose.ui.Modifier
  import androidx.compose.ui.geometry.Offset
  import androidx.compose.ui.graphics.Color
  import androidx.compose.ui.graphics.asImageBitmap
  import androidx.compose.ui.text.input.KeyboardType
  import androidx.compose.ui.unit.dp
  import app.piececounter.core.PieceType

  @OptIn(ExperimentalMaterial3Api::class)
  @Composable
  fun PickTypesScreen(vm: CounterViewModel) {
      val ui = vm.ui
      val image = ui.image ?: return
      val session = ui.session ?: return
      val snack = rememberMessageSnackbar(ui.message, vm::messageShown)
      val maskImage = remember(ui.detection) { ui.detection?.mask?.asImageBitmap() }

      Scaffold(
          topBar = {
              TopAppBar(
                  title = { Text("Tap one piece of each type") },
                  actions = { TextButton(onClick = vm::toggleMask) { Text(if (ui.showMask) "Photo" else "Mask") } },
              )
          },
          snackbarHost = { SnackbarHost(snack) },
          bottomBar = {
              Column(Modifier.navigationBarsPadding().padding(8.dp)) {
                  LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                      itemsIndexed(session.types, key = { _, t -> t.id }) { i, t ->
                          TypeChip(
                              type = t, index = i, swatch = ui.swatches[t.id],
                              selected = ui.selectedTypeId == t.id,
                              onSelect = { vm.selectType(t.id) },
                              onRename = { vm.renameType(t.id, it) },
                              onExpected = { vm.setExpected(t.id, it) },
                              onDelete = { vm.deleteType(t.id) },
                          )
                      }
                  }
                  Text(
                      if (ui.selectedTypeId != null) "Taps add samples to the selected type · tap a sample dot to remove it"
                      else "Taps create a new type · select a type to add more samples to it",
                      style = MaterialTheme.typography.bodySmall,
                      modifier = Modifier.padding(vertical = 4.dp),
                  )
                  Button(
                      onClick = vm::count,
                      enabled = session.types.isNotEmpty() && !ui.busy,
                      modifier = Modifier.fillMaxWidth(),
                  ) { Text("Count") }
              }
          },
      ) { pad ->
          Box(Modifier.padding(pad).fillMaxSize()) {
              ZoomableImage(image, onTap = vm::onPickTap) { t ->
                  if (ui.showMask && maskImage != null) drawPhoto(maskImage, t, alpha = 0.7f)
                  ui.detection?.pieces?.forEach { p ->
                      val idx = session.types.indexOfFirst { it.id == p.typeId }
                      if (idx >= 0) drawOutline(p.outline, t, markerColor(idx))
                  }
                  session.types.forEachIndexed { i, type ->
                      type.samples.forEach { s ->
                          val o = t.toScreen(s)
                          drawDot(Offset(o.x, o.y), markerColor(i), 7.dp.toPx())
                      }
                  }
              }
              if (ui.busy) LinearProgressIndicator(Modifier.fillMaxWidth().align(Alignment.TopCenter))
              WarningBanner(
                  ui.detection?.warning?.takeIf { session.types.isNotEmpty() },
                  onRetake = vm::newPhoto,
                  onCountByHand = vm::count,
                  modifier = Modifier.align(Alignment.BottomCenter),
              )
          }
      }
  }

  @Composable
  private fun TypeChip(
      type: PieceType,
      index: Int,
      swatch: Int?,
      selected: Boolean,
      onSelect: () -> Unit,
      onRename: (String) -> Unit,
      onExpected: (String) -> Unit,
      onDelete: () -> Unit,
  ) {
      var expectedText by remember(type.id) { mutableStateOf(type.expected?.toString() ?: "") }
      Card(
          onClick = onSelect,
          border = if (selected) BorderStroke(3.dp, markerColor(index)) else null,
          modifier = Modifier.width(220.dp),
      ) {
          Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(8.dp)) {
              Box(
                  Modifier.size(28.dp)
                      .background(Color(swatch ?: 0xFF888888.toInt()))
                      .border(3.dp, markerColor(index)),
              )
              Column(Modifier.weight(1f).padding(horizontal = 8.dp)) {
                  OutlinedTextField(
                      value = type.name, onValueChange = onRename, singleLine = true,
                      label = { Text("Name") }, textStyle = MaterialTheme.typography.bodySmall,
                  )
                  OutlinedTextField(
                      value = expectedText,
                      onValueChange = { expectedText = it.filter(Char::isDigit).take(4); onExpected(expectedText) },
                      singleLine = true,
                      label = { Text("Expected") },
                      textStyle = MaterialTheme.typography.bodySmall,
                      keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                  )
              }
              TextButton(onClick = onDelete) { Text("✕") }
          }
      }
  }
  ```

- [ ] **Step 2: Wire it into `MainActivity.kt`**

  Replace the `Screen.PickTypes -> Text(...)` line with:

  ```kotlin
  Screen.PickTypes -> PickTypesScreen(vm)
  ```

  and add `import app.piececounter.ui.PickTypesScreen`.

- [ ] **Step 3: Build**

  Run: `./gradlew :app:assembleDebug :app:testDebugUnitTest`
  Expected: `BUILD SUCCESSFUL`

- [ ] **Step 4: Check on the device**

  Run `./gradlew :app:installDebug`. Copy `Test data/20261014_182953.jpg` to the phone's gallery first, e.g. `"$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe" push "Test data/20261014_182953.jpg" /sdcard/Pictures/`, and make sure it appears in the gallery. Then:
  - Choose that photo → tap a yellow piece → one chip appears, and yellow pieces get outlined within about 2 s.
  - Tap a grey octagon → a second chip; grey pieces are outlined and the stripes are not.
  - Select the brown chip after creating it, then tap a darker stick → more sticks get outlined.
  - Tap a sample dot → that sample is removed.
  - Tap the black margin outside the photo → "Tap the middle of a piece".
  - **Mask** shows the debug mask overlay.
  - Pinch-zoom and pan work, and taps still land on the piece under your finger.
  - Rotate the phone → the session survives.
  - **Count** shows the interim results text.

- [ ] **Step 5: Commit**

  ```bash
  git add app/src/main
  git commit -m "feat(ui): pick-types screen with live detection preview

  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
  ```

---

### Task 11: Results screen

**Files:**
- Create: `app/src/main/java/app/piececounter/ui/ResultsScreen.kt`
- Modify: `app/src/main/java/app/piececounter/MainActivity.kt` (the `Screen.Results` branch)

**Interfaces:**
- Consumes: `CounterViewModel`/`UiState` (Task 9), `Common.kt` helpers (Task 9), `TypeResult`, `NumberedPiece`, `legendText`, `median` (core)
- Produces: `@Composable fun ResultsScreen(vm: CounterViewModel)`

- [ ] **Step 1: Write the screen**

  ```kotlin
  package app.piececounter.ui

  import androidx.compose.foundation.background
  import androidx.compose.foundation.clickable
  import androidx.compose.foundation.layout.Box
  import androidx.compose.foundation.layout.Column
  import androidx.compose.foundation.layout.Row
  import androidx.compose.foundation.layout.Spacer
  import androidx.compose.foundation.layout.fillMaxSize
  import androidx.compose.foundation.layout.fillMaxWidth
  import androidx.compose.foundation.layout.padding
  import androidx.compose.foundation.layout.size
  import androidx.compose.foundation.layout.width
  import androidx.compose.material3.AlertDialog
  import androidx.compose.material3.ExperimentalMaterial3Api
  import androidx.compose.material3.MaterialTheme
  import androidx.compose.material3.Scaffold
  import androidx.compose.material3.SnackbarHost
  import androidx.compose.material3.Text
  import androidx.compose.material3.TextButton
  import androidx.compose.material3.TopAppBar
  import androidx.compose.runtime.Composable
  import androidx.compose.ui.Alignment
  import androidx.compose.ui.Modifier
  import androidx.compose.ui.geometry.Offset
  import androidx.compose.ui.graphics.Color
  import androidx.compose.ui.graphics.drawscope.Stroke
  import androidx.compose.ui.text.rememberTextMeasurer
  import androidx.compose.ui.unit.dp
  import app.piececounter.core.NumberedPiece
  import app.piececounter.core.PieceType
  import app.piececounter.core.TypeResult
  import app.piececounter.core.legendText
  import app.piececounter.core.median
  import app.piececounter.detect.DetectionWarning

  @OptIn(ExperimentalMaterial3Api::class)
  @Composable
  fun ResultsScreen(vm: CounterViewModel) {
      val ui = vm.ui
      val image = ui.image ?: return
      val session = ui.session ?: return
      val measurer = rememberTextMeasurer()
      val snack = rememberMessageSnackbar(ui.message, vm::messageShown)

      Scaffold(
          topBar = {
              TopAppBar(
                  title = { Text("Results") },
                  actions = {
                      TextButton(onClick = vm::toggleDots) { Text(if (ui.showDots) "Numbers" else "Dots") }
                      TextButton(onClick = vm::newPhoto) { Text("New photo") }
                  },
              )
          },
          snackbarHost = { SnackbarHost(snack) },
      ) { pad ->
          Column(Modifier.padding(pad).fillMaxSize()) {
              Legend(ui.results, session.types, ui.selectedTypeId, onSelect = vm::selectType)
              Box(Modifier.weight(1f).fillMaxWidth()) {
                  ZoomableImage(image, onTap = vm::onResultTap, onLongPress = vm::onResultLongPress) { t ->
                      ui.results.forEach { r ->
                          val color = markerColor(session.types.indexOfFirst { it.id == r.type.id })
                          val typicalH = median(r.pieces.filter { !it.piece.manual }.map { it.piece.bounds.height })
                          val labelPx = (typicalH * t.scale * 0.45f).coerceIn(11.dp.toPx(), 28.dp.toPx())
                          r.pieces.forEach { np ->
                              drawOutline(np.piece.outline, t, color, dashed = np.flagged)
                              val c = t.toScreen(np.piece.center)
                              val at = Offset(c.x, c.y)
                              if (np.piece.manual) drawCircle(color, labelPx * 0.9f, at, style = Stroke(2.dp.toPx()))
                              if (ui.showDots) drawDot(at, color, labelPx / 3f)
                              else drawLabel(measurer, np.label, at, color, labelPx)
                          }
                      }
                  }
                  WarningBanner(
                      ui.detection?.warning?.takeIf { it == DetectionWarning.SurfaceTooSimilar },
                      onRetake = vm::newPhoto, onCountByHand = {},
                      modifier = Modifier.align(Alignment.BottomCenter),
                  )
              }
          }
      }

      ui.menuPieceId?.let { id ->
          ui.results.flatMap { it.pieces }.firstOrNull { it.piece.id == id }?.let { np ->
              PieceMenu(
                  np, session.types,
                  onRemove = { vm.removePiece(id) },
                  onMove = { vm.movePiece(id, it) },
                  onSetCount = { vm.setCount(id, it) },
                  onDismiss = vm::dismissMenus,
              )
          }
      }
      ui.samplePromptAt?.let {
          AlertDialog(
              onDismissRequest = vm::dismissMenus,
              confirmButton = { TextButton(onClick = vm::dismissMenus) { Text("Cancel") } },
              title = { Text("Add as sample for…") },
              text = {
                  Column {
                      session.types.forEach { t ->
                          TextButton(onClick = { vm.addSampleFromResults(t.id) }) { Text(t.name) }
                      }
                  }
              },
          )
      }
  }

  @Composable
  private fun Legend(results: List<TypeResult>, types: List<PieceType>, selectedTypeId: Int?, onSelect: (Int) -> Unit) {
      Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp)) {
          results.forEach { r ->
              val idx = types.indexOfFirst { it.id == r.type.id }
              Row(
                  Modifier.fillMaxWidth()
                      .clickable { onSelect(r.type.id) }
                      .background(if (selectedTypeId == r.type.id) MaterialTheme.colorScheme.secondaryContainer else Color.Transparent)
                      .padding(6.dp),
                  verticalAlignment = Alignment.CenterVertically,
              ) {
                  Box(Modifier.size(16.dp).background(markerColor(idx)))
                  Spacer(Modifier.width(8.dp))
                  Text(legendText(r.type, r.total), style = MaterialTheme.typography.titleMedium)
              }
          }
          Text(
              "Tap a marker to fix it · tap empty space to add to the highlighted type · long-press a missed piece to add a sample",
              style = MaterialTheme.typography.bodySmall,
          )
      }
  }

  @Composable
  private fun PieceMenu(
      np: NumberedPiece,
      types: List<PieceType>,
      onRemove: () -> Unit,
      onMove: (Int) -> Unit,
      onSetCount: (Int) -> Unit,
      onDismiss: () -> Unit,
  ) {
      AlertDialog(
          onDismissRequest = onDismiss,
          confirmButton = { TextButton(onClick = onDismiss) { Text("Close") } },
          title = { Text("Piece ${np.label}") },
          text = {
              Column {
                  TextButton(onClick = onRemove) { Text("Remove") }
                  types.filter { it.id != np.typeId }.forEach { t ->
                      TextButton(onClick = { onMove(t.id) }) { Text("Move to ${t.name}") }
                  }
                  if (np.piece.estimatedCount > 1 || np.count > 1) {
                      Text("Pieces in this blob:", modifier = Modifier.padding(top = 8.dp))
                      Row {
                          (1..maxOf(4, np.piece.estimatedCount + 1)).forEach { n ->
                              TextButton(onClick = { onSetCount(n) }) { Text("$n") }
                          }
                      }
                  }
              }
          },
      )
  }
  ```

- [ ] **Step 2: Wire it into `MainActivity.kt`**

  Replace the `Screen.Results -> Text(...)` line with:

  ```kotlin
  Screen.Results -> ResultsScreen(vm)
  ```

  and add `import app.piececounter.ui.ResultsScreen`.

- [ ] **Step 3: Build**

  Run: `./gradlew :app:assembleDebug :app:testDebugUnitTest`
  Expected: `BUILD SUCCESSFUL`

- [ ] **Step 4: Commit**

  ```bash
  git add app/src/main
  git commit -m "feat(ui): results screen with numbering, legend and corrections

  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
  ```

---

### Task 12: On-device acceptance checklist

**Files:** none, unless a check fails. A fix goes to the file that owns the behaviour, with a test where the logic is in `core/`.

- [ ] **Step 1: Install a fresh build**

  Run: `./gradlew :app:connectedDebugAndroidTest :app:installDebug`
  Expected: all instrumented tests pass, and the app installs

- [ ] **Step 2: Walk the checklist with the user on the S23 Ultra** (spec section 9.3). Record pass or fail for each item:
  1. Camera flow: take photo → pick types → count → results.
  2. Gallery flow, using `20261014_182953.jpg`, with types and expected counts entered as in the golden set: the legend shows `found / expected` and ✅/❌.
  3. Numbers run 1..n per type, top-left first, row by row. The touching grey trio shows `2–4?` with a dashed outline.
  4. Tap a merged blob → *Pieces in this blob: 3* → the `?` disappears and the count stays the same.
  5. Tap a false piece (e.g. the tin) → *Remove* → the count drops by one.
  6. Tap a piece → *Move to …* → it is renumbered in the new type.
  7. Tap empty space → a manual circle marker is added to the selected type.
  8. Long-press a missed stick → *Add as sample for Brown* → it gets detected. The earlier removals and moves stay on the same pieces.
  9. Toggle **Dots** ↔ **Numbers**.
  10. Rotate the phone on each screen → nothing is lost.
  11. Background the app, open several other apps, come back → the session is restored. (A stricter check: *Developer options → Don't keep activities*, then switch apps and return.)
  12. **New photo** → back at the start screen with an empty session.

- [ ] **Step 3: Commit any fixes**

  ```bash
  git add -A
  git commit -m "fix: issues found during on-device acceptance

  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
  ```

  Skip this step if nothing failed.
