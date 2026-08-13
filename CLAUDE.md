# Bacilab (ElectraLab) — Claude Code Instructions

## Project Overview
iOS app for BTA (Bakteri Tahan Asam / Acid-Fast Bacilli) microscope slide analysis at **Klinik Bunda**. The app guides a lab technician through a 4-screen flow: patient data entry → camera capture → manual BTA review → result/interpretation.

## Architecture
- **Language**: Swift, SwiftUI, iOS 17+
- **Pattern**: MVVM with explicit dependency injection (no Singletons)
- **State**: `@Observable` macro for ViewModels and `SampleDraft`; `@Bindable` to pass mutable observable objects through views
- **Navigation**: `NavigationStack` + `navigationDestination` inside a `.sheet`
- **DI container**: `AppDependencies` — created once in `ElectraLabApp`, passed explicitly (not via environment) through the navigation chain

## Critical Rules

### Dependency Injection — DO NOT use `@Environment(AppDependencies.self)`
Views inside the sheet's `NavigationStack` (DataInput → Capture → Analysis → Result) must receive dependencies via **explicit `let` properties**, not `@Environment`. Using `@Environment(AppDependencies.self)` inside a pushed view will crash at runtime.

Correct pattern:
```swift
struct CaptureView: View {
    let dependencies: AppDependencies
    // ...
}
```

`@Environment` is only safe at the root (`SampleListView`), which is directly under the `.environment(dependencies)` modifier.

### SampleDraft — shared mutable state across the 4-screen flow
`SampleDraft` is an `@Observable` class created once per session and passed by reference via `@Bindable`. All screens mutate the same instance. Never create a new `SampleDraft` mid-flow.

### Simulator safety
All camera code must be guarded with `#if targetEnvironment(simulator)`. `CaptureView` shows a
decorative radial gradient test pattern on simulator.

`CameraService.captureImage()` renders a **synthetic stained field** on simulator (seeded, so the
count is stable) rather than returning empty data. This is what lets the capture → detection path
be tested without hardware; it is compiled out of device builds, so a real slide never meets it.
Returning `Data()` here would make `analyze` be skipped and every field silently score 0.

### Grading is gated by field count — WHO/IUATLD
`BTAGrade.minimumFields`: 3+ needs 20 fields, 2+ needs 50, and 1+/Scanty/**Negatif need the full
100**. The asymmetry is deliberate: a heavy smear declares itself quickly, but calling a slide
negative is the reading that, if wrong, sends an infectious patient home untreated. Below the
threshold the UI marks the grade `SEMENTARA` — never present it as a conclusion.

### Never fabricate clinical figures
`confidenceBadge` once fell back to `Int.random(in: 85...95)` when no confidence was available.
Anything shown next to a grade or count is read as a diagnostic figure — show the detector's own
value or show nothing.

Note that the reported confidence is now the mean score of surviving detections, and the graph
already discards everything below 0.70 — so it cannot read lower than 70% no matter how weak
the field is. It says how sure the model is about the bacilli **it kept**, not how confident
anyone should be in the count. Do not present it as the latter.

### A capture that fails must not count as a field
`capturedFieldCount` increments only on the success path. Counting a failed capture inflates the
denominator in `BTAGrade.grade(for:across:)` and drags the grade down. Likewise, once the analyst
picks a grade by hand (`SampleDraft.selectGrade`), `hasManualGrade` stops further captures from
overwriting that judgement.

## File Structure
```
Bacilab/Bacilab/
├── App/
│   ├── ElectraLabApp.swift        # @main entry, creates AppDependencies
│   └── AppDependencies.swift      # DI container (@Observable)
├── Core/
│   ├── DesignSystem/
│   │   ├── Colors.swift           # Color.appPrimary etc. (use Color.appX, not .appX)
│   │   ├── Typography.swift       # Font.appTitle, .appBody etc.
│   │   └── Skeleton.swift         # SkeletonLine, SkeletonBlock, SkeletonCircle, SkeletonPill + .skeletonShimmer()
│   ├── Domain/
│   │   ├── Entities/
│   │   │   ├── Sample.swift       # Final saved struct; Sample.build(from: draft)
│   │   │   ├── SampleDraft.swift  # Mutable @Observable class for the capture flow
│   │   │   └── AnalysisResult.swift # BTAGrade with IUATLD grading logic
│   │   └── Protocols/             # CameraServiceProtocol, AnalysisServiceProtocol, SampleRepositoryProtocol
│   ├── Services/
│   │   ├── CameraService.swift    # AVCaptureSession + AVCapturePhotoOutput, simulator-safe
│   │   ├── VisionAnalysisService.swift  # CoreML + hand-written YOLO-OBB decoding
│   │   └── SampleRepository.swift # In-memory store
│   └── Extensions/
│       └── PreviewHelpers.swift   # Sample.previews, SampleDraft.preview
├── Resources/
│   └── BTADetector.onnx           # bundled detector, run via ONNX Runtime (79 MB)
└── Features/
    ├── SampleList/  # Home screen — list + FAB to open new-sample sheet
    ├── DataInput/   # Patient data form → NavigationLink to Capture
    ├── Capture/     # Camera + BTA AI detection per field
    ├── Analysis/    # Manual BTA count review + grade selection
    └── Result/      # Final interpretation + save
```

## Two detectors, compared on the same field
Both models ship and both read every field when the analyst picks "Keduanya":

| | |
|---|---|
| `ResNetAnalysisService` | `BTADetector.onnx`, Faster R-CNN, ONNX Runtime. Default grading model. |
| `YOLOAnalysisService` | `BTADetector.mlmodelc`, YOLOv8s-OBB, CoreML. The previous detector. |
| `DualDetectorService` | Runs the selection, concurrently, over identical bytes. |

`FieldFraming` exists so both get **byte-identical** input. Duplicate the crop into either
service and any difference in counts becomes part framing and part model, inseparably.

**The grade follows `selection.gradingDetector` and nothing else.** Averaging two models
produces a count neither one made. Choosing `.yolo` really does hand the grade to YOLO — its
`conf 0.25` was never clinically calibrated, so the UI must always name the model on screen.

### Counts are filed per model — never one accumulator relabelled
`SampleDraft.detectorCounts` / `detectorFields` are keyed by `DetectorKind`. There used to be
a single `manualBTACount` paired with a `comparisonBTACount`, and which model each belonged to
depended on what was selected when the column was drawn. Switching from "Keduanya" to YOLO
relabelled ResNet's accumulated fields as YOLO's: the heading changed, the number did not —
and that number drives the grade and is what `Sample.build` saves.

`reconcileCountSource(with:)` re-points the count of record when the model changes, dropping
manual +/- adjustments on purpose: they were made against a different model's reading of
different fields. It lives on `SampleDraft`, **not** in a view's `onChange` — it is an
invariant of the data, and wired to a view it only holds while that screen is on display.

### The overlay must draw on the frame that was analysed
`CaptureViewModel.analyzedImage` freezes the centred square the models received, and the
viewfinder shows it instead of the live feed until `resumeLivePreview()`. Boxes are normalised
against those pixels; over a live preview they sit on bacilli that have already moved.

Boxes from both models are flattened into one `ForEach` with ids like `"YOLO-3"`. Both models
number their boxes from 0, so a nested `ForEach` per reading lets the inner ids collide.

The preview is a **square, not a circle**: `resizeAspectFill` means that square is exactly
`FieldFraming`'s crop, so everything shown is analysed and everything analysed is shown. The
old circular mask hid ~21% of the analysed area — bacilli could be counted where the analyst
could not see them.

### Diagnosing a device-only detection bug
`Diag` logs to `os.Logger` **and** stderr in Debug, because `devicectl … --console` relays only
stdout/stderr — instrumentation written with `Logger` alone produces a silent console and reads
as "the code never ran". The comparison columns also carry a `#if DEBUG` line showing
`N kotak · T s` per model, which separates "the model found nothing" from "the drawing is
broken"; those look identical on screen. `log collect` from a device needs root.

## AI Model Integration
The model is **bundled and active** at `Bacilab/Resources/BTADetector.onnx` (79 MB), run
through **ONNX Runtime**, not CoreML. It is fold 4 of a local 5-fold cross-validation run
(`~/Downloads/runs/`): a **torchvision `fasterrcnn_resnet50_fpn`**, 2 classes
(background + `AFB`), trained on `01-uganda-shah-voc/tuberculosis-phonecamera`.

The training repo is not in this project, so the architecture is reconstructed in the export
script from things that are observable — checkpoint tensor shapes and `fold4/config.yaml`:

| | |
|---|---|
| Heads | `TwoMLPHead` fc6/fc7, `RPNHead` conv_depth=1 (v1, not v2) |
| Anchors | 3/location: sizes `(40,),(52,),(64,),(78,),(96,)` × ratios `0.5, 1.0, 2.0` |
| Transform | `min_size=1200, max_size=1600` |
| Calibrated | `box_score_thresh=0.70`, `box_nms_thresh=0.50` |

`rpn.head.cls_logits.weight` is `(3, 256, 1, 1)`, which is what pins the five anchor sizes to
one-per-FPN-level rather than all five on every level. The reconstruction loads with
`strict=True` against all 295 tensors — if any of it were wrong, that load would fail.

### Why it is ONNX and not CoreML — do not 'port it to CoreML'
Faster R-CNN has data-dependent control flow: score filtering, top-k proposal selection, and
an NMS whose output length varies per image. `torch.jit.trace` bakes one sample's counts in
as constants, so the converted model returns **that same count for every slide** — silently,
with no error, exactly the failure mode the old YOLO-OBB export had in reverse.
`torch.jit.script` preserves the control flow but coremltools cannot convert the result.

ONNX keeps the whole pipeline — transform, RPN, ROIAlign, NMS — inside the graph. Swift hands
over raw pixels and reads boxes back; there is no hand-written decoding any more.

**The thresholds are compiled into the graph**, deliberately: there is no Swift-side knob, so
what ships always matches what was measured. Changing them means re-exporting.

### Export and validation
`export_onnx.py` → `make_fp16.py` (both in the session scratchpad, not the repo).

fp16 conversion is **weights-only**: large initializers are stored as fp16 and Cast back to
fp32, so the graph keeps fp32 types end to end and ORT constant-folds the Casts at load.
onnxconverter-common's full-graph fp16 pass does not work here — it breaks type bindings in
the traced `/transform/` and `/rpn/` subgraphs and its cast-cleanup crashes outright. The
weights-only route halves the file with activations still in fp32.

Size is not cosmetic: fp32 is 158 MB, over **GitHub's 100 MB hard limit**, and git-lfs is not
installed. 79 MB is what makes the model committable at all.

Validated against PyTorch on five fields at four resolutions — counts identical every time
(`[53, 5, 29, 79, 0]`), max box drift 1.08 px, max score drift 0.0017. The varying counts are
the point: they are what proves no constant got baked in.

### Accuracy — read this before quoting a number
Fold 4's own validation split: AP50 0.835, precision 0.79, recall 0.76, count MAE 1.32. It is
the **best of the five folds**, and picking the best fold by validation metrics is optimistic.
The 5-fold mean is AP50 0.72 / count MAE 1.81, which is the more honest expectation. None of
it has been checked against slides read at Klinik Bunda.

### Device-only concerns
Roughly 0.6 s per field on an M5 CPU, so expect a few seconds on device — `analyze` runs on a
private `DispatchQueue`, never the cooperative pool. ORT's CoreML execution provider exists
and may help, but the validation above was run on CPU, so CPU is what ships.

Camera photos carry rotation in EXIF, which a bare `CGImage` drops.
`uprightCenteredSquare(of:)` fixes that and crops to the square the overlay draws into. The
crop costs nothing in detection scale: the transform resizes to min side 1200, and a 4:3 frame
hits that limit on its short side just as a square crop of it does.

## IUATLD BTA Grading
Grading is computed via `BTAGrade.grade(for: totalBTA, across: fields)`:
| Grade   | Criteria (per 100 fields) |
|---------|---------------------------|
| Negatif | 0 BTA                     |
| Scanty  | 1–9 BTA                   |
| 1+      | 10–99 BTA                 |
| 2+      | 100–1000 BTA              |
| 3+      | >1000 BTA                 |

## Coding Conventions
- `foregroundStyle(Color.appPrimary)` — always explicit `Color.` prefix for custom colors
- No `@Environment(AppDependencies.self)` inside sheet-pushed views (see Critical Rules)
- No Combine — use `async/await` throughout
- Every View file must have at least one `#Preview` block
- `@State private var viewModel: ViewModel` initialized via `_viewModel = State(initialValue: ...)`
- Do not use `.environment(deps)` as a substitute for explicit injection in the capture flow

## Localization
UI text is in **Bahasa Indonesia**. Keep all user-facing strings in Indonesian.
