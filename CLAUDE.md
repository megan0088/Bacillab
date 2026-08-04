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
All camera code must be guarded with `#if targetEnvironment(simulator)`. The `CameraService` returns `Data()` on simulator. `CaptureView` shows a decorative radial gradient test pattern on simulator.

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
│   │   ├── CameraService.swift    # AVCaptureSession, simulator-safe
│   │   ├── VisionAnalysisService.swift  # CoreML + Vision BTA detection
│   │   └── SampleRepository.swift # In-memory store
│   └── Extensions/
│       └── PreviewHelpers.swift   # Sample.previews, SampleDraft.preview
└── Features/
    ├── SampleList/  # Home screen — list + FAB to open new-sample sheet
    ├── DataInput/   # Patient data form → NavigationLink to Capture
    ├── Capture/     # Camera + BTA AI detection per field
    ├── Analysis/    # Manual BTA count review + grade selection
    └── Result/      # Final interpretation + save
```

## AI Model Integration
- Model source: `https://github.com/indrikla/Oculab-ML` — YOLOv8-small OBB (Oriented Bounding Box), file: `machine-learning/model-obb-12-nov-2024-yolo-8-s.pt`
- `VisionAnalysisService` expects a CoreML model named **`BTADetector.mlpackage`** in the app bundle
- To activate: export the `.pt` to CoreML, then add to Xcode target:
  ```bash
  python3 -c "
  from ultralytics import YOLO
  model = YOLO('machine-learning/model-obb-12-nov-2024-yolo-8-s.pt')
  model.export(format='coreml', nms=True)
  "
  ```
- Until the model is added, the service returns a zero-count stub — the app works normally without it

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
