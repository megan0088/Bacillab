# Structure Tidy, Architecture Doc, and Three Single-Model Branches

**Date:** 2026-08-19
**Status:** approved

## Goal

Leave the codebase in a state a new programmer can pick up unaided, then split it into three
single-model branches — one per team member — from a base that will never be tidied again.

## Why the order matters

Two pieces, strictly sequenced:

- **A — Structure tidy + `ARCHITECTURE.md`**, done on `flow-redesign`, then merged to `main`.
- **B — Three single-model branches**, cut from `main` *after* A lands.

**Each piece gets its own implementation plan.** Piece A is planned and executed first; Piece B is
planned only once A has merged into `main`, because its starting point does not exist until then.

B must not start before A is merged. Moving files is the change most likely to produce merge
conflicts, and the branches diverge **permanently** (see Piece B), so the merge into `main` is the
last moment anything can be fixed once for everybody. Tidying after the split means doing it three
times, by hand, in three diverging trees.

`main` itself keeps the current detector arrangement unchanged: ResNet grades, YOLO11 rides along
for comparison, YOLOv8 stays switched off.

---

## Piece A — Structure tidy and architecture doc

### The placement rule

One question, two answers, decidable by looking at the file:

> **Does it know anything about BTA?** No → `Core/DesignSystem`. Yes → next question.
> **Is it used by more than one feature?** Yes → `DesignSystem/Organisms`. No → `Features/<Feature>/Components/`.

This replaces "is it an atom or a molecule?", which frequently has no correct answer and consumes
review time. Both halves of this rule can be checked; neither is a matter of taste.

### Target design-system layout

```
Core/DesignSystem/
├── Tokens/      Colors, Typography, GradeTint, DetectorStyle
├── Atoms/       Skeleton (Line/Block/Circle/Pill), Badge, Swatch
├── Molecules/   Card, InfoRow, SectionHeader, LabeledField
└── Organisms/   (deliberately empty)
```

`GradeTint` and `DetectorStyle` sit in `Tokens/` despite knowing the domain: both are colour
decisions, not views. `Organisms/` starts empty — nothing currently qualifies, and filling it now
would mean inventing a requirement.

### Files that move

| From | To |
|---|---|
| `Core/DesignSystem/Colors.swift` | `Tokens/Colors.swift` |
| `Core/DesignSystem/Typography.swift` | `Tokens/Typography.swift` |
| `Core/DesignSystem/GradeTint.swift` | `Tokens/GradeTint.swift` |
| `Features/Review/Components/DetectorStyle.swift` | `Tokens/DetectorStyle.swift` |
| `Core/DesignSystem/Skeleton.swift` | `Atoms/Skeleton.swift` |

### Components extracted because they already repeat

Extraction is justified by measured repetition, not by taste:

- **`Card`** — `RoundedRectangle(cornerRadius:)` over `Color(.systemBackground)` appears in
  **6 feature files**. This is the clearest duplication in the UI.
- **`InfoRow`** — label left, value right; currently `ResultSheetView.infoRow`.
- **`SectionHeader`** — currently `PatientDataView.sectionHeader`.
- **`LabeledField`** — `PatientDataView`'s `formField` and `dateField`, which differ only in the
  control they wrap.
- **`Badge`** — the status/grade pill drawn by `HomeView`, and the chip shape the result sheet uses.
- **`Swatch`** — `DetectorLegend`'s dashed line sample.

### View splits

**The rename below happens first**, so these components land in `Features/Home/Components/`, not
`Features/SampleList/Components/`.

Four view files carry more than one responsibility. Each keeps composition and hands its parts to
components in its own feature folder:

| File | Lines now | Split into |
|---|---|---|
| `ReviewView` | 415 | view + `ReviewHeader`, `GradePicker`, `FieldCountRow` |
| `ResultSheetView` | 352 | view + `GradeBox`, `PatientSection`, `NotesSection` |
| `HomeView` (renamed, below) | 253 | view + `HistoryRow`, `NewAnalysisCard`, `SearchBar` |
| `ScanView` | 243 | view + `Viewfinder`, `ShutterBar` |

Existing feature components (`FieldCanvas`, `FieldPager`, `CountKeypad`, `DetectorLegend`,
`CameraPreviewView`) stay where they are: each is used by exactly one feature.

### Rename: `SampleList` → `Home`

`Features/SampleList/` → `Features/Home/`, `SampleListView` → `HomeView`, `SampleListViewModel` →
`HomeViewModel`, and the 5 references across `ElectraLabApp` and the test suite. The `Sample` type this
was named after no longer exists, so the name now sends a new reader looking for something that
is not there.

### `ARCHITECTURE.md`

At the repository root, written for people — distinct from `CLAUDE.md`, which is written for the
assistant and is organised around what it must not get wrong.

Contents:

1. What the app is, and the four-screen flow.
2. The folder map, and the placement rule above.
3. Dependency injection: why `@Environment(AppDependencies.self)` crashes in a pushed view, and
   the explicit-`let` pattern that replaces it.
4. How a field travels: capture → disk → analysis queue → review → published sheet.
5. **Decisions that must not be changed without reading why**, each with its consequence:
   the WHO/IUATLD field-count gates; never fabricating a clinical figure; a failed capture never
   counting as a field; the overlay drawing on the analysed frame; `DemoMode.hidesProvisionalMarks`
   being an exhibition switch that must be `false` before real use.

### Testing for Piece A

This piece changes no behaviour, so the existing suite is the specification: it must pass
unchanged, apart from renames. Every extracted component keeps or gains a `#Preview`.

---

## Piece B — Three single-model branches

Cut from `main` after Piece A merges.

| Branch | Model kept | Grading detector |
|---|---|---|
| `branch-ega` | YOLOv8 — `Resources/BTADetector.mlpackage` | YOLOv8 |
| `branch-jesslyn` | YOLO11 — `Resources/BTADetectorV11.mlpackage` | YOLO11 |
| `branch-mge` | ResNet — `Resources/BTADetector.onnx` | ResNet |

Xcode compiles a bundled `.mlpackage` into `.mlmodelc`, which is what the CoreML services load at
runtime; the `.mlpackage` is what lives in the repository and what a branch deletes.

### What each branch removes

The two other detector services, their bundled model files, and the comparison scaffolding:
`MultiDetectorService`, `DetectorLegend`, `DetectorStyle`, `DetectorSelection`, and the tests
belonging to the removed models.

`AppDependencies` wires the surviving service directly instead of through `MultiDetectorService`.

### What each branch must keep

- **`DetectorKind` keeps all three cases.** It is the storage key in `manifest.json`. Reducing the
  enum makes sessions recorded on another branch — or on `main` — fail to decode, and
  `SessionStore` skips manifests it cannot decode, so those sessions disappear from the list rather
  than erroring.
- **`FieldRecord.analysis` keeps `readings` as an array**, holding a single element. Same reason:
  the on-disk shape stays common across all four trees.

### The grading detector is a real change, not a deletion

`FieldAnalysisQueue` currently hardcodes `primary: .resnet`. On `branch-ega` and `branch-jesslyn`
that becomes `.yolo` and `.yolo11` — which promotes a model to deciding a clinical result.

### Accuracy: the first task on two of the three branches

The recorded figures — AP50 0.835, precision 0.79, recall 0.76, count MAE 1.32 — belong to
**ResNet alone**, measured on fold 4's held-out validation split. YOLO11 and YOLOv8 have only ever
been comparison passengers; neither has been validated against anything.

So on `branch-mge` those numbers still hold. On `branch-ega` and `branch-jesslyn` **no accuracy
figure may be quoted at all** until the surviving model is validated against the same 253 fold-4
validation images, reporting precision, recall and count MAE. That validation is the **first**
task on those two branches, not a later one: everything built on top of an unmeasured grading
model is built on an unknown.

### Testing for Piece B

Each branch keeps the tests for its own model and the whole domain/grading suite, which is
detector-independent. The removed models' tests are deleted rather than disabled — these branches
are not coming back together.

---

## Global constraints

- Swift, SwiftUI, `@Observable`/`@Bindable`, `async`/`await`. No Combine.
- Explicit dependency injection; `@Environment(AppDependencies.self)` only at the root view.
- Xcode synchronized file groups: **never edit `project.pbxproj`** — moving a file is enough.
- Every View file carries at least one `#Preview`.
- UI copy in English. Type scale 34 / 22 / 17 / 13, SF Pro, no `design: .rounded`.
- `BTAGrade.rawValue` is both UI text and the storage key in `manifest.json`; renaming a case
  breaks every session on disk.

## Non-goals

- Extracting the design system into a Swift Package. Only three files are genuinely domain-free;
  with one consumer that is relocation, not reuse. Keeping the domain-free layer domain-free means
  extraction stays a folder move if a second app ever appears.
- Merging the three branches back together. They diverge permanently by decision.
- Fixing the analysis memory ceiling, which is being traced separately.
