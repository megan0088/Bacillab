# Architecture

This is the orientation document for a new team member joining Electra Lab's iOS app. It covers
what the app does, how the code is laid out, how dependencies and data flow through it, and a
handful of decisions that look arbitrary until you know what they cost.

For the rules an AI assistant must not break while editing this codebase — the DI crash, the
grading model's export format, the demo-seeding contract, and more — see `CLAUDE.md`. That
document is organised around what must not go wrong; this one is organised around orientation. It
goes deeper on several points this document only summarises, and is referenced by section below
rather than repeated.

## 1. What this is

An iOS app for reading BTA (Bakteri Tahan Asam / acid-fast bacilli) sputum smear slides at
**Electra Lab**. A lab technician walks through four screens:

1. **Patient data** — enter patient and sample details before scanning starts.
2. **Scan** — capture microscope fields through the camera (or import them from the photo
   library), 20 fields per batch, blind to any BTA count.
3. **Review** — the only screen where a clinical decision is made: per-field count, grade, notes,
   deleting a bad field, and publishing.
4. **Published result sheet** — the read-only report, also reachable later by tapping a session in
   the history list.

## 2. Where code goes

```
Bacilab/
├── App/
│   ├── ElectraLabApp.swift        # @main entry, creates AppDependencies, shows the splash
│   ├── AppDependencies.swift      # DI container (@Observable)
│   └── DemoMode.swift             # compile-time exhibition switches (see §5)
├── Core/
│   ├── DesignSystem/
│   │   ├── Atoms/                 # Badge, Skeleton, Swatch — smallest reusable views
│   │   ├── Molecules/             # Card, InfoRow, LabeledField, SectionHeader
│   │   ├── Organisms/             # empty today — see the placement rule below
│   │   └── Tokens/                # Colors, Typography, DetectorStyle, GradeCopy, GradeTint
│   ├── Domain/
│   │   ├── Entities/
│   │   │   ├── ExamSession.swift    # @Observable session; derives totalBTA/examinedFieldCount, never stores them
│   │   │   ├── FieldRecord.swift    # One scanned field: image ref, per-model readings, manual correction
│   │   │   ├── PatientInfo.swift    # Patient data captured before scanning
│   │   │   └── AnalysisResult.swift # BTAGrade with IUATLD grading logic
│   │   └── Protocols/             # CameraServiceProtocol, AnalysisServiceProtocol, SessionStoreProtocol
│   ├── Services/
│   │   ├── CameraService.swift         # AVCaptureSession + AVCapturePhotoOutput, simulator-safe
│   │   ├── FieldFraming.swift          # Byte-identical crop shared by every detector
│   │   ├── ResNetAnalysisService.swift # BTADetector.onnx via ONNX Runtime — the grading model
│   │   ├── YOLOAnalysisService.swift   # BTADetector.mlmodelc (YOLOv8s-OBB) — switched off, comparison only
│   │   ├── YOLO11AnalysisService.swift # YOLO11 CoreML — comparison only
│   │   ├── MultiDetectorService.swift  # Runs the enabled detectors serially over identical bytes
│   │   ├── SessionStore.swift          # Reads/writes ExamSession + field images under Application Support
│   │   ├── FieldAnalysisQueue.swift    # Serial background analysis while scanning continues
│   │   ├── FocusMetric.swift           # Sharpness/blur warning, never blocks capture
│   │   └── Diagnostics.swift           # os.Logger + stderr logging for device debugging
│   └── Extensions/
│       └── PreviewHelpers.swift   # ExamSession.previewHeavy / .previewNegative / .previewRunning
├── Resources/
│   ├── BTADetector.onnx           # bundled grading detector, run via ONNX Runtime
│   ├── BTADetector.mlpackage      # YOLOv8s-OBB, compiled to .mlmodelc — currently unused (see below)
│   ├── BTADetectorV11.mlpackage   # YOLO11, compiled to .mlmodelc
│   └── DemoFields/                # 20 tiles used to seed the exhibition demo session
└── Features/
    ├── Home/          # History list + FAB for a new session (+ Components/: HistoryRow, NewAnalysisCard, SearchBar)
    ├── PatientData/    # Patient data form → NavigationLink to Scan
    ├── Scan/           # Scan session (+ Components/: CameraPreviewView, Viewfinder, ShutterBar)
    ├── Review/         # The only screen that decides (+ Components/: ReviewHeader, GradePicker, FieldCountRow, FieldCanvas, FieldPager, CountKeypad, DetectorLegend)
    ├── ResultSheet/    # Read-only published result (+ Components/: GradeBox, PatientSection, NotesSection)
    └── Splash/         # Launch splash shown while the demo session seeds
```

New code follows one placement rule, applied as a decision rather than a guess:

> Does it know anything about BTA? No → `Core/DesignSystem`. Yes → is it used by more than one
> feature? Yes → `DesignSystem/Organisms`. No → `Features/<Feature>/Components/`.

`DesignSystem/Organisms` is empty today. That is a fact about the app, not an oversight: nothing
yet is both BTA-aware and shared across more than one feature. `DetectorStyle` and `GradeCopy`,
for example, are BTA-aware and shared, but they are pure token/formatting logic with no view
body, so they live in `DesignSystem/Tokens` rather than `Organisms`, which is reserved for shared
*views*.

## 3. Dependency injection

`AppDependencies` is created once, in `ElectraLabApp.swift`, and handed down as an explicit `let`
through the navigation chain — `PatientDataView`, `ScanView`, `ReviewView`, `ResultSheetView` (and
anything else pushed inside the sheet's `NavigationStack`) all declare `let dependencies:
AppDependencies` and receive it from their caller.

**`@Environment(AppDependencies.self)` crashes at runtime inside any of those pushed views.** It
is safe in exactly one place: `HomeView`, which sits directly under the `.environment(dependencies)`
modifier applied in `ElectraLabApp.swift`. Every other screen is one or more pushes away from that
modifier, so the environment value isn't there to read.

If you're adding a new screen to the flow, copy the pattern from an existing one — `let
dependencies: AppDependencies` as a stored property, passed in at the call site — rather than
reaching for `@Environment`.

## 4. How a field travels

1. The technician captures a frame from the camera, or imports one from the photo library — both
   paths converge on the same code (`ScanViewModel.record`), so an imported field and a captured
   one are framed, written, and queued identically.
2. `FieldFraming` crops it to the identical square every detector receives, correcting EXIF
   rotation as it goes.
3. `SessionStore` writes the JPEG to disk under Application Support, and the field is appended to
   `ExamSession` only once that write succeeds.
4. `FieldAnalysisQueue` picks it up and analyses it serially in the background, so scanning isn't
   blocked waiting on the model.
5. Review shows the field with its detections drawn on it, and lets the technician correct the
   count or delete the field outright.
6. Publishing freezes the reading: whatever grade and counts are on screen at that point become
   the report.

## 5. Decisions not to change without reading why

**WHO/IUATLD field gates.** `BTAGrade.minimumFields`: 3+ needs 20 fields, 2+ needs 50, and
1+/Scanty/Negative need the full 100. The asymmetry is deliberate — a heavy smear declares itself
quickly, but calling a slide negative is the reading that, if wrong, sends an infectious patient
home untreated. Below the threshold, the UI marks the grade provisional rather than presenting it
as a conclusion.

**Never fabricate a clinical figure.** A confidence badge once fell back to a random 85–95% when
no real confidence was available. Anything shown beside a grade or a count is read as a
diagnostic figure — show the detector's own value, or show nothing.

**A failed capture is not a field.** `ScanViewModel.record` appends a field to `ExamSession` only
after its image is written to disk. Counting a capture that never produced a usable image would
inflate the denominator in `BTAGrade.grade(for:across:)` and drag a real grade down.

**Every scanned field counts, including empty ones.** Auto-scan used to increment only when the
model found bacilli, which made grade Negative structurally unreachable — a negative slide would
never fill its denominator. `record` now appends a field whenever its image lands on disk,
whether or not anything was detected in it.

**The circular field of view is enforced on both sides, deliberately.** `FieldCanvas` clips the
review image to a circle, matching what the microscope eyepiece actually shows — and
`MultiDetectorService` drops any detection whose centre falls outside that same inscribed circle
before it ever reaches the UI or the count. Both sides move together on purpose: masking the
*display* alone would still let the model count bacilli in the roughly 21% of the square that sits
outside the circle — marks the analyst is shown as absent but that were quietly counted anyway.
The cost is real and stated in the code where this happens
(`MultiDetectorService.restrictedToFieldOfView`): about a fifth of each captured square is
discarded, so a slide needs proportionally more fields to satisfy the WHO/IUATLD gates above.

**`BTAGrade.rawValue` is the storage key in `manifest.json`.** Use `BTAGrade.displayName` (in
`Core/DesignSystem/Tokens/GradeCopy.swift`) for anything shown on screen — never render
`rawValue` directly. Renaming a `BTAGrade` case changes its storage key, and `SessionStore` skips
manifests it cannot decode rather than crashing, so a renamed case makes every session already
saved under the old case silently vanish from history.

**`DemoMode.hidesProvisionalMarks` is an exhibition switch.** With it on, a Negative read from 20
fields looks identical on screen to one read from the full 100 that WHO/IUATLD actually require.
It hides the *marks*, not the gate — `BTAGrade.minimumFields` still computes the same either way —
but it must be `false` before the app is used on a real slide. See `App/DemoMode.swift` for the
full reasoning.

## 6. Running it

```bash
xcodebuild test -project Bacilab.xcodeproj -scheme Bacilab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO 2>&1 \
  | grep -E "error:|✘|TEST SUCCEEDED|TEST FAILED"
```

Expect `** TEST SUCCEEDED **`.

`Bacilab.xcodeproj/project.pbxproj` uses Xcode's synchronized file groups: adding, moving, or
removing a file under `Bacilab/` is picked up automatically, and the project file is never edited
by hand.
