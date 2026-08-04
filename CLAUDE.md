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
value or show nothing. Real confidence on the synthetic field is ~40%, not 85–95%.

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
│   └── BTADetector.mlpackage      # bundled detector (Xcode compiles → .mlmodelc)
└── Features/
    ├── SampleList/  # Home screen — list + FAB to open new-sample sheet
    ├── DataInput/   # Patient data form → NavigationLink to Capture
    ├── Capture/     # Camera + BTA AI detection per field
    ├── Analysis/    # Manual BTA count review + grade selection
    └── Result/      # Final interpretation + save
```

## AI Model Integration
The model is **bundled and active** at `Bacilab/Resources/BTADetector.mlpackage` (22 MB, fp16).
Source: `https://github.com/indrikla/Oculab-ML` → `machine-learning/model-obb-12-nov-2024-yolo-8-s.pt`
(YOLOv8s-OBB, single class `AFB`, trained at 1024×1024). That repo ships **no** CoreML model,
and neither do the Oculab iOS repos — they call a backend over HTTP. The export was:

```bash
python3 -c "
from ultralytics import YOLO
YOLO('model-obb-12-nov-2024-yolo-8-s.pt').export(format='coreml', half=True, imgsz=1024)
"
```

### Why the decoding is hand-written — do not 'simplify' it
`nms=True` is silently ignored for OBB models (the export metadata records `'nms': False`).
The model therefore has **no NMS pipeline**, its output is a raw `(1, 6, 21504)` tensor, and
Vision cannot produce `VNRecognizedObjectObservation` for it. Reading `request.results as?
[VNRecognizedObjectObservation]` yields an empty array and every slide reports **Negatif** —
silently, with no error. `VisionAnalysisService` decodes the tensor itself:

- Channel layout per anchor: `cx, cy, w, h, score, angle` (pixels of the 1024 input, radians)
- NMS is ProbIoU, matrix-style: a box is dropped when *any* higher-scoring box overlaps it,
  including one already dropped — this mirrors ultralytics' `nms_rotated`, and greedy NMS
  gives a different count
- Thresholds `conf 0.25` / `iou 0.7` are the model's training defaults, **not clinically
  calibrated** — validate against manually-read slides before relying on them

Verified against ultralytics' own postprocess: identical geometry to 0.3 px, counts within
±2 (fp16 rounding at the confidence cutoff). `BTADetectorTests` guards this.

### Device-only concerns
The bundle ships `.mlmodelc`, not `.mlpackage` — Xcode compiles it. Load by that extension.
Camera photos carry rotation in EXIF, which `VNImageRequestHandler(cgImage:)` ignores, and
the 4:3 frame letterboxed into 1024×1024 shrinks bacilli below the ~13 px they were trained
at. `uprightCenteredSquare(of:)` handles both; neither is reproducible on the simulator.

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
