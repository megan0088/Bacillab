# Bacilab (ElectraLab) — Claude Code Instructions

## Project Overview
iOS app for BTA (Bakteri Tahan Asam / Acid-Fast Bacilli) microscope slide analysis at **Electra Lab**. The app guides a lab technician through: patient data → scan session (20 fields per batch) → per-field review → published result sheet. Every clinical decision — per-field count, grade, notes, publish — belongs to the review screen alone.

## Architecture
- **Language**: Swift, SwiftUI, iOS 17+
- **Pattern**: MVVM with explicit dependency injection (no Singletons)
- **State**: `@Observable` macro for ViewModels and `ExamSession`; `@Bindable` to pass mutable observable objects through views
- **Navigation**: `NavigationStack` + `navigationDestination` inside a `.sheet`
- **DI container**: `AppDependencies` — created once in `ElectraLabApp`, passed explicitly (not via environment) through the navigation chain

## Critical Rules

### Dependency Injection — DO NOT use `@Environment(AppDependencies.self)`
Views inside the sheet's `NavigationStack` (PatientData → Scan → Review → ResultSheet) must receive dependencies via **explicit `let` properties**, not `@Environment`. Using `@Environment(AppDependencies.self)` inside a pushed view will crash at runtime.

Correct pattern:
```swift
struct ScanView: View {
    let dependencies: AppDependencies
    // ...
}
```

`@Environment` is only safe at the root (`SampleListView`), which is directly under the `.environment(dependencies)` modifier.

### ExamSession — one source of truth, no stored counts
`ExamSession` is `@Observable`, created once per examination and passed by reference. **No count
is stored.** `totalBTA` and `examinedFieldCount` are recomputed from `fields` on every read, so
the count that drives the grade cannot drift from the fields it came from. The old model kept
`manualBTACount` beside the field list; the two could disagree, and the stored one is what
reached the patient's report.

`chosenGrade` is optional: `nil` means nobody has decided yet, so `reportedGrade` falls back to
`suggestedGrade`. That optional replaces the old `hasManualGrade` flag.

### Simulator safety
All camera code must be guarded with `#if targetEnvironment(simulator)`. `ScanView` shows a
decorative radial gradient test pattern on simulator.

`CameraService.captureImage()` renders a **synthetic stained field** on simulator (seeded, so the
count is stable) rather than returning empty data. This is what lets the capture → detection path
be tested without hardware; it is compiled out of device builds, so a real slide never meets it.
Returning `Data()` here would make `analyze` be skipped and every field silently score 0.

### Sessions live on disk
`SessionStore` writes one directory per session under Application Support: `manifest.json` plus
`field-NNN.jpg` at analysis resolution (max side 1600 — the model's own `max_size`). The manifest
is rewritten after every recorded or analysed field, so a session survives the app being killed.
`FieldRecord.imageFileName` is relative, never an absolute URL: iOS container paths change
between installs.

### Fields can come from the photo library, and say so
`ScanView` offers **Import Photo** beside the shutter. Without it the live camera is the only
image source, so detection cannot be exercised at all unless a microscope is clamped to the
phone — which is what makes the app testable off a rig.

Camera and gallery share one path (`ScanViewModel.record`): same framing, same write-then-append
order, same queue. Duplicating that pipeline would make any difference between an imported field
and a captured one part framing and part source, with no way to separate them. The focus check
runs for the camera only — telling someone an imported photo is "out of focus" is advice about an
eyepiece nobody is looking through.

Each field records its `FieldSource`, and `ExamSession.importedFieldCount` surfaces the mix: a
slide read partly through the eyepiece and partly from imported images is two acquisitions pooled
into one grade, and a reader of the result sheet has no other way to tell.

### Unanalysed fields are re-queued on entering Review
`ReviewViewModel.analysePendingFields()` enqueues every field whose `analysis` is still nil.
Two situations arrive looking identical — a session resumed after the app was killed mid-queue,
and a seeded demo session that was never analysed. In both the images are on disk and the models
are idle, but the queue only ever receives what `ScanViewModel` captures live, so without this
those fields stay `pending` forever and sit outside both the numerator and the denominator.

### Demo seeding — images only, never readings
`DemoSeeder` fills an **empty** history with one 20-field session from tiles bundled in
`Resources/DemoFields/`, so an exhibition build has something to show. `ElectraLabApp` opts in via
`SampleListViewModel(seedsDemoData: true)`; the default is off so tests get exactly what they set up.

It seeds **images, not counts.** The source tiles ship with ground-truth annotations, and planting
those would make a session look instantly analysed while putting numbers on screen that no model
produced. The seeded fields arrive unanalysed and the real models count them.

The tiles come from the detector's own **test** split (`AI TBC/output/TestingData`) — never the
training split, which the model memorised. Even so this flatters it: same source, same phone-camera
dataset, so a demo shows the model at its best rather than its behaviour on this lab's slides.
Patient names are prefixed `DEMO —` so nobody mistakes seeded data for a record.

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

Review displays it as "Model yakin N% atas basil yang ia tandai" ("The model is N% confident in
the bacilli it flagged") — not as a confidence figure for the result. The ONNX graph discards
detections below 0.70, so the number can never read below 70%.

### Every scanned field counts — including empty ones
`ScanViewModel.captureField` appends a field whenever the image is written to disk, whether or
not any bacilli are found. Auto-scan used to increment only when `btaCount > 0`, so empty fields
never entered the denominator and **grade Negatif was structurally unreachable**.

A capture that fails still appends nothing: the field is recorded only after its image is safely
on disk, so a full disk cannot leave a field whose picture does not exist.

Because every frame counts, a stationary slide is counted repeatedly. The per-100 ratio survives
that (BTA and fields rise together), but `examinedFieldCount` can reach a threshold without that
many distinct fields being seen. Review's **delete-field** is what corrects it.

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
│   │   │   ├── ExamSession.swift    # @Observable session; derives totalBTA/examinedFieldCount, never stores them
│   │   │   ├── FieldRecord.swift    # One scanned field: image ref, per-model readings, manual correction
│   │   │   ├── PatientInfo.swift    # Patient data captured before scanning
│   │   │   └── AnalysisResult.swift # BTAGrade with IUATLD grading logic
│   │   └── Protocols/             # CameraServiceProtocol, AnalysisServiceProtocol, SessionStoreProtocol
│   ├── Services/
│   │   ├── CameraService.swift         # AVCaptureSession + AVCapturePhotoOutput, simulator-safe
│   │   ├── FieldFraming.swift          # Byte-identical crop shared by all three detectors
│   │   ├── ResNetAnalysisService.swift # BTADetector.onnx via ONNX Runtime — grading model
│   │   ├── YOLOAnalysisService.swift   # BTADetector.mlmodelc (YOLOv8s-OBB) — comparison only
│   │   ├── YOLO11AnalysisService.swift # YOLO11 CoreML — comparison only
│   │   ├── MultiDetectorService.swift  # Runs all three detectors concurrently over identical bytes
│   │   ├── SessionStore.swift          # Reads/writes ExamSession + field images under Application Support
│   │   ├── FieldAnalysisQueue.swift    # Serial background analysis while scanning continues
│   │   ├── FocusMetric.swift           # Sharpness/blur warning, never blocks capture
│   │   └── Diagnostics.swift           # os.Logger + stderr logging for device debugging
│   └── Extensions/
│       └── PreviewHelpers.swift   # ExamSession.previewHeavy / .previewNegative / .previewRunning
├── Resources/
│   └── BTADetector.onnx           # bundled detector, run via ONNX Runtime (79 MB)
└── Features/
    ├── SampleList/   # Home screen — history of sessions; FAB starts a new one
    ├── PatientData/  # Patient data form → NavigationLink to Scan
    ├── Scan/         # Scan session, 20 fields/batch, blind to BTA (+ Components/CameraPreviewView.swift)
    ├── Review/       # Per-field count, grade, notes, delete-field, publish — the only screen that decides
    │                 #   (+ Components/: DetectorStyle, FieldCanvas, FieldPager, CountKeypad)
    └── ResultSheet/  # Read-only published result; also reached by tapping a sample in history
```

## Detectors, compared on the same field
Every field is read by every **enabled** model; only one of them ever grades:

| | |
|---|---|
| `ResNetAnalysisService` | `BTADetector.onnx`, Faster R-CNN, ONNX Runtime. The grading model. |
| `YOLOAnalysisService` | `BTADetector.mlmodelc`, YOLOv8s-OBB, CoreML. **Currently switched off** — see below. |
| `YOLO11AnalysisService` | YOLO11 end-to-end, CoreML. Comparison only. |
| `MultiDetectorService` | Runs the enabled models concurrently, over identical bytes. |

### YOLOv8 is switched off, not removed
Only ResNet and YOLO11 currently ship. `MultiDetectorService`'s default detector dictionary has
the `.yolo` entry commented out; `DetectorKind.yolo`, `YOLOAnalysisService` and the bundled
`BTADetector.mlmodelc` are all untouched. `analyze` filters on `detectors[$0] != nil`, so an
absent entry is simply not run and nothing else needs to know — and sessions already saved with
YOLOv8 readings still decode. Turning it back on is uncommenting one line.

Six tests that assume YOLOv8 participates carry `.disabled("YOLOv8 dimatikan …")` rather than
being deleted, so they still compile against the current API and come back with the model.

`FieldFraming` exists so every model gets **byte-identical** input. Duplicate the crop into any
service and any difference in counts becomes part framing and part model, inseparably.

**ResNet is unconditionally the grading detector — `FieldAnalysisQueue` hardcodes it.** There is
no analyst picker any more: `DetectorSelection` / `gradingDetector` are still declared in
`AnalysisResult.swift` and referenced from `MultiDetectorService`, but every field is analysed
with `.all` and `primary: .resnet`. YOLO and YOLO11 ride along only to be shown beside ResNet's
count in Review — averaging the three would produce a count none of them made, so neither ever
becomes the number of record.

### Every field's readings are stored once, on that field — nothing left to relabel
`FieldRecord.analysis` (a `FieldAnalysis`) is set once by `FieldAnalysisQueue` and carries all
three `DetectorReading`s plus the frozen `primary` detector for that field. There is no
session-wide accumulator keyed by model that could drift: the old model kept a single
`manualBTACount` beside a `comparisonBTACount`, and which model each belonged to depended on
what was selected when the column was drawn — switching models relabelled one detector's
accumulated fields as another's without changing the number underneath. That accumulator, and
the `reconcileCountSource(with:)` that patched around it, do not exist any more; each field's
own readings can't be reassigned to a different model after the fact.

### The overlay must draw on the frame that was analysed
`FieldCanvas` draws over the field's own stored image (`ReviewViewModel.imageData(for:)`, read
back from `SessionStore`), never a live preview — boxes are normalised against the exact pixels
`FieldFraming` handed the models, so a box still sits on the same bacillus whether reviewed
seconds or hours after capture.

Boxes from all three models are flattened into one `ForEach`, with ids like `"ResNet-0"`,
`"YOLOv8-3"`, `"YOLO11-2"` (`FieldCanvas.Marker.id`). Every model numbers its own boxes from 0,
so a nested `ForEach` per reading would let the inner ids collide.

The canvas is a **square, with a dashed circle drawn on top only as an eyepiece guide — never a
mask**: the square is exactly `FieldFraming`'s crop, so everything shown is analysed and
everything analysed is shown. A circular *mask* would hide ~21% of the analysed area — bacilli
could be counted where the analyst cannot see them; the dashed circle here is decoration, not a
clip.

### Diagnosing a device-only detection bug
`Diag` logs to `os.Logger` **and** stderr in Debug, because `devicectl … --console` relays only
stdout/stderr — instrumentation written with `Logger` alone produces a silent console and reads
as "the code never ran". `log collect` from a device needs root.

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
it has been checked against slides read at Electra Lab.

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
UI text is in **English**. Keep all user-facing strings in English — including error messages
from `CameraError` and `AnalysisError`, which surface in alerts.

This reversed an earlier rule: the app's copy was Bahasa Indonesia until the 2026-08-18 sweep.
Test names in `BacilabTests` are still Indonesian; they are not user-facing and were left alone.

`BTAGrade.rawValue` doubles as UI text **and** as the storage key in `manifest.json`. Renaming a
case breaks every session already on disk — `SessionStore` skips manifests it cannot decode, so
they vanish from the list rather than crashing. Acceptable pre-release; if real readings ever
exist, split the display name from the raw value before touching these.
