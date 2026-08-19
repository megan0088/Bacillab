# Piece A — Structure Tidy and Architecture Doc

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganise the design system, split the four oversized views, and write `ARCHITECTURE.md`, so a new programmer can find and place code unaided — and so the three single-model branches (Piece B) are cut from a base that never needs tidying again.

**Architecture:** A design system in four layers (`Tokens`, `Atoms`, `Molecules`, `Organisms`) holding only what is shared, with feature-owned components staying in their feature. Placement is decided by one rule: does it know about BTA, and is it used by more than one feature. No behaviour changes — the existing suite is the specification.

**Beyond the spec:** Task 2 (`GradeCopy`) and the `SessionBadge` half of Task 6 were not in the spec's file list. Both come from a defect found while reading the code for this plan: the same grade renders as `"1+"` in Review, `"Positive 1+"` in history and `"Positive (1+)"` on the result sheet, and the logic deciding whether a grade may be shown as final lives inside a private View method no test can reach. Both are squarely the tidy this piece exists to do, and both are testable, so they are planned here rather than deferred.

**A note on move steps:** where a task moves existing code, the step gives the member's name and its line range rather than reproducing the body. Re-typing several hundred lines across four view splits would invite transcription drift in exactly the code that must not change behaviour; the source is the authority and `git mv` plus a named member is the precise instruction.

**Tech Stack:** Swift, SwiftUI, `@Observable`/`@Bindable`, swift-testing (`import Testing`, `@Test`, `#expect`), Xcode synchronized file groups.

## Global Constraints

- **Never edit `Bacilab.xcodeproj/project.pbxproj`.** Xcode synchronized file groups add files under `Bacilab/` and `BacilabTests/` to their targets automatically; moving a file with `git mv` is sufficient.
- No Combine. `async`/`await` throughout.
- No `@Environment(AppDependencies.self)` inside sheet-pushed views — dependencies arrive as explicit `let` properties. `@Environment` is safe only in the root view.
- Every View file carries at least one `#Preview` block.
- Custom colours are always written `Color.appPrimary`, never `.appPrimary`.
- Type scale is exactly 34 / 22 / 17 / 13 via `Font.appTitle` / `.appHeading` / `.appBody` / `.appCaption`, SF Pro. Never `design: .rounded`, and never a fifth size — apply `.weight(...)` at the call site instead.
- UI copy is in English. Test names in `BacilabTests` are in Indonesian; match the surrounding file.
- **`BTAGrade.rawValue` is the storage key in `manifest.json`.** Never change a case's raw value: `SessionStore` skips manifests it cannot decode, so every saved session would silently vanish from the list rather than raise an error.
- **Line numbers in this plan are as of the plan being written, before any task ran.** Earlier tasks edit the same files, so by the time you reach a later task the numbers will have moved. Always locate a member by its name (`private var gradeBox`, `private func infoRow`) and treat the line number as a hint about where to start looking.
- Behaviour must not change. Any test that needs its expectations edited (beyond a rename) means something broke — stop and report it.

**Full test command** (used by every task):

```bash
xcodebuild test -project Bacilab.xcodeproj -scheme Bacilab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO 2>&1 \
  | grep -E "error:|✘|TEST SUCCEEDED|TEST FAILED"
```

Expected on success: `** TEST SUCCEEDED **`.

---

## File Structure

**Created**

| File | Responsibility |
|---|---|
| `Bacilab/Core/DesignSystem/Tokens/GradeCopy.swift` | `BTAGrade.displayName` and `.criterion` — the single source of grade wording |
| `Bacilab/Core/DesignSystem/Atoms/Badge.swift` | Pill-shaped label with a tint |
| `Bacilab/Core/DesignSystem/Atoms/Swatch.swift` | Short dashed line sample in a colour |
| `Bacilab/Core/DesignSystem/Molecules/Card.swift` | The rounded surface every screen groups content in |
| `Bacilab/Core/DesignSystem/Molecules/SectionHeader.swift` | Bold section title, optionally tinted |
| `Bacilab/Core/DesignSystem/Molecules/InfoRow.swift` | Label left, value right |
| `Bacilab/Core/DesignSystem/Molecules/LabeledField.swift` | Bordered text field and date row used by the patient form |
| `Bacilab/Features/Home/SessionBadge.swift` | Testable text+tint for a history row's badge |
| `Bacilab/Features/Home/Components/HistoryRow.swift` | One session row |
| `Bacilab/Features/Home/Components/NewAnalysisCard.swift` | The blue "New Analysis" banner |
| `Bacilab/Features/Home/Components/SearchBar.swift` | Bottom search field |
| `Bacilab/Features/Scan/Components/Viewfinder.swift` | Circular preview + focus badge |
| `Bacilab/Features/Scan/Components/ShutterBar.swift` | Shutter, import, stop controls |
| `Bacilab/Features/ResultSheet/Components/GradeBox.swift` | Grade, chip, chevron, derivation |
| `Bacilab/Features/ResultSheet/Components/PatientSection.swift` | Patient information card |
| `Bacilab/Features/ResultSheet/Components/NotesSection.swift` | Editable notes card |
| `Bacilab/Features/Review/Components/ReviewHeader.swift` | Analysis progress line |
| `Bacilab/Features/Review/Components/GradePicker.swift` | Grade band chips + shortfall notice |
| `Bacilab/Features/Review/Components/FieldCountRow.swift` | Count button + confidence line |
| `BacilabTests/GradeCopyTests.swift` | Grade wording and raw-value guards |
| `BacilabTests/SessionBadgeTests.swift` | Badge text and tint |
| `ARCHITECTURE.md` | Human-facing orientation document |

**Moved**

`Colors.swift`, `Typography.swift`, `GradeTint.swift` → `Core/DesignSystem/Tokens/`.
`Skeleton.swift` → `Core/DesignSystem/Atoms/`.
`Features/Review/Components/DetectorStyle.swift` → `Core/DesignSystem/Tokens/`.
`Features/SampleList/` → `Features/Home/` (`SampleListView` → `HomeView`, `SampleListViewModel` → `HomeViewModel`).

---

### Task 1: Design-system folders, and move what already belongs there

**Files:**
- Move: `Bacilab/Core/DesignSystem/{Colors,Typography,GradeTint}.swift` → `Bacilab/Core/DesignSystem/Tokens/`
- Move: `Bacilab/Core/DesignSystem/Skeleton.swift` → `Bacilab/Core/DesignSystem/Atoms/`
- Move: `Bacilab/Features/Review/Components/DetectorStyle.swift` → `Bacilab/Core/DesignSystem/Tokens/`

**Interfaces:**
- Consumes: nothing.
- Produces: the four folders `Tokens/`, `Atoms/`, `Molecules/`, `Organisms/` that every later task files into. No type names or signatures change — these are pure moves, so every existing call site keeps compiling untouched.

- [ ] **Step 1: Create the four folders and move the files**

Swift has no per-folder namespacing, so a move changes no import and no call site.

```bash
cd Bacilab/Core/DesignSystem
mkdir -p Tokens Atoms Molecules Organisms
git mv Colors.swift Typography.swift GradeTint.swift Tokens/
git mv Skeleton.swift Atoms/
cd ../../..
git mv Bacilab/Features/Review/Components/DetectorStyle.swift \
       Bacilab/Core/DesignSystem/Tokens/DetectorStyle.swift
```

- [ ] **Step 2: Keep `Organisms/` from being dropped by git**

Git does not track empty directories, and the folder is deliberately empty for now.

```bash
cat > Bacilab/Core/DesignSystem/Organisms/README.md <<'EOF'
# Organisms

Components that **know about BTA** and are used by **more than one feature**.

Deliberately empty. Nothing in the app currently qualifies: every domain-aware component
(`FieldCanvas`, `FieldPager`, `CountKeypad`, `DetectorLegend`, `CameraPreviewView`) is used by
exactly one feature and lives with that feature. Filling this folder before something qualifies
would mean inventing a requirement.
EOF
```

- [ ] **Step 3: Build and run the full suite**

Run the full test command from Global Constraints.
Expected: `** TEST SUCCEEDED **`. Nothing should need editing — if the build fails, a file was moved outside `Bacilab/` or `project.pbxproj` was touched.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: four design-system layers, and move what already belongs there

Swift has no per-folder namespacing, so these moves change no call site.
DetectorStyle comes up from Features/Review because it is a colour
decision shared with anything that draws a detector's boxes.

Organisms/ is deliberately empty and says so: every domain-aware
component is used by exactly one feature today."
```

---

### Task 2: One name per grade

The same grade is currently rendered three different ways: `ResultSheetView.label(for:)` returns `"Positive (1+)"`, `SampleListView.badge(for:)` returns `"Positive 1+"`, and `ReviewView` prints `grade.rawValue`, which is `"1+"`. One slide therefore shows three different names depending on the screen.

`rawValue` cannot absorb this, because it is the storage key in `manifest.json`.

**Files:**
- Create: `Bacilab/Core/DesignSystem/Tokens/GradeCopy.swift`
- Create: `BacilabTests/GradeCopyTests.swift`
- Modify: `Bacilab/Features/ResultSheet/ResultSheetView.swift` (delete `criterion(for:)` at lines 30–39 and `label(for:)` at lines 40–49; point `gradeLabel` and `gradeCriterion` at the new properties)
- Modify: `Bacilab/Features/SampleList/SampleListView.swift` (the `name` switch at lines 178–186)
- Modify: `Bacilab/Features/Review/ReviewView.swift` (lines 265, 297, 327)

**Interfaces:**
- Consumes: `BTAGrade` from `Core/Domain/Entities/AnalysisResult.swift`, cases `negative`, `scanty`, `plus1`, `plus2`, `plus3`, with raw values `"Negative"`, `"Scanty"`, `"1+"`, `"2+"`, `"3+"`.
- Produces: `BTAGrade.displayName: String` and `BTAGrade.criterion: String`. Every later task and every screen uses `displayName` for grade wording — never `rawValue`, never a local switch.

- [ ] **Step 1: Write the failing tests**

Create `BacilabTests/GradeCopyTests.swift`:

```swift
import Testing
@testable import Bacilab

/// Satu grade harus punya satu nama di seluruh app. Sebelumnya ada tiga: "1+" di Review,
/// "Positive 1+" di riwayat, "Positive (1+)" di lembar hasil — untuk slide yang sama.
struct GradeCopyTests {

    @Test("Setiap grade punya satu nama tampilan")
    func displayNames() {
        #expect(BTAGrade.negative.displayName == "Negative")
        #expect(BTAGrade.scanty.displayName == "Scanty")
        #expect(BTAGrade.plus1.displayName == "Positive 1+")
        #expect(BTAGrade.plus2.displayName == "Positive 2+")
        #expect(BTAGrade.plus3.displayName == "Positive 3+")
    }

    /// `rawValue` adalah kunci penyimpanan di manifest.json. Kalau ini berubah, setiap sesi
    /// yang sudah tersimpan gagal di-decode — dan SessionStore melewatkan manifest yang tidak
    /// bisa dibaca, jadi sesi itu hilang dari daftar, bukan memunculkan error.
    @Test("rawValue tidak ikut berubah bersama nama tampilan")
    func rawValuesUnchanged() {
        #expect(BTAGrade.negative.rawValue == "Negative")
        #expect(BTAGrade.scanty.rawValue == "Scanty")
        #expect(BTAGrade.plus1.rawValue == "1+")
        #expect(BTAGrade.plus2.rawValue == "2+")
        #expect(BTAGrade.plus3.rawValue == "3+")
    }

    @Test("Setiap grade punya kriteria WHO/IUATLD yang terisi")
    func everyGradeHasACriterion() {
        for grade in BTAGrade.allCases {
            #expect(!grade.criterion.isEmpty, "\(grade.rawValue) tidak punya kriteria")
        }
    }

    /// Negatif dan Scanty menuntut 100 lapang penuh; kriterianya harus menyebut itu, karena
    /// kalimat inilah yang dibaca orang saat memutuskan apakah hasil boleh dilaporkan.
    @Test("Kriteria menyebut jumlah lapang untuk grade yang menuntut 100")
    func criterionMentionsFieldCount() {
        #expect(BTAGrade.negative.criterion.contains("100"))
        #expect(BTAGrade.scanty.criterion.contains("100"))
    }
}
```

- [ ] **Step 2: Run the tests and watch them fail**

Run the full test command.
Expected: FAIL — `value of type 'BTAGrade' has no member 'displayName'`.

- [ ] **Step 3: Write the implementation**

Create `Bacilab/Core/DesignSystem/Tokens/GradeCopy.swift`:

```swift
import Foundation

/// The words used for a grade, in one place.
///
/// This exists because `BTAGrade.rawValue` cannot be the display name: it is the key each grade
/// is stored under in `manifest.json`, so changing it to read better on screen would make every
/// saved session fail to decode — and `SessionStore` skips manifests it cannot read, so those
/// sessions disappear from the list rather than raising anything.
///
/// Before this, three screens each solved that privately and disagreed: the result sheet said
/// "Positive (1+)", the history said "Positive 1+", and Review printed the raw "1+". One slide,
/// three names, depending on where you looked.
extension BTAGrade {

    /// The grade as a reader should see it. Never render `rawValue` in the UI.
    var displayName: String {
        switch self {
        case .negative: return "Negative"
        case .scanty:   return "Scanty"
        case .plus1:    return "Positive 1+"
        case .plus2:    return "Positive 2+"
        case .plus3:    return "Positive 3+"
        }
    }

    /// The WHO/IUATLD definition of the band — a definition, not a report of what was seen.
    ///
    /// Negative and Scanty name the full 100 fields on purpose: that is the number which decides
    /// whether the reading may be reported at all, and it is the figure someone needs in front of
    /// them at the moment they decide.
    var criterion: String {
        switch self {
        case .negative: return "No BTA in 100 fields of view"
        case .scanty:   return "1–9 BTA in 100 fields of view; repeat examination advised"
        case .plus1:    return "10–99 BTA in 100 fields of view"
        case .plus2:    return "1–10 BTA per field, across at least 50 fields"
        case .plus3:    return "More than 10 BTA per field, across at least 20 fields"
        }
    }
}
```

- [ ] **Step 4: Run the tests and watch them pass**

Run the full test command.
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Point all three screens at it**

In `Bacilab/Features/ResultSheet/ResultSheetView.swift`, delete the static `criterion(for:)` and `label(for:)` methods, and replace the two computed properties that called them:

```swift
    private var gradeLabel: String { grade.displayName }

    private var gradeCriterion: String { grade.criterion }
```

In `Bacilab/Features/SampleList/SampleListView.swift`, replace the whole `name` switch inside `badge(for:)` with:

```swift
        let name = session.reportedGrade.displayName
```

In `Bacilab/Features/Review/ReviewView.swift`, replace three renderings of `rawValue` with `displayName`:
- line 265: `statCell(label: "Model Suggests", value: session.suggestedGrade.displayName)`
- line 297: `Text(grade.displayName)`
- line 327: `"\(session.reportedGrade.displayName) needs \(session.reportedGrade.minimumFields) "`

Leave every other `rawValue` alone — those are storage keys and log lines, not UI.

- [ ] **Step 6: Run the full suite**

Run the full test command.
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor: one name per grade

The same grade rendered three ways: 'Positive (1+)' on the result sheet,
'Positive 1+' in history, and the raw '1+' in Review — one slide, three
names depending on the screen.

rawValue could not absorb this: it is the storage key in manifest.json,
and SessionStore skips manifests it cannot decode, so a rename there
would make saved sessions vanish from the list rather than error. Hence
a separate displayName, with a test pinning the raw values so a later
edit cannot quietly take that path."
```

---

### Task 3: `Card` molecule

`RoundedRectangle(cornerRadius:)` over `Color(.systemBackground)` appears in six feature files. `ResultSheetView` already has a private `card` helper (lines 276–284); this promotes it.

**Files:**
- Create: `Bacilab/Core/DesignSystem/Molecules/Card.swift`
- Modify: `Bacilab/Features/ResultSheet/ResultSheetView.swift` (delete the private `card` at lines 276–284; call sites keep working unchanged)

**Interfaces:**
- Consumes: nothing beyond SwiftUI.
- Produces: `Card { ... }` — a `View` taking a `@ViewBuilder` closure. Default corner radius 16, padding 16, `VStack(alignment: .leading, spacing: 12)`, full width, leading-aligned. Later tasks compose screens from it.

- [ ] **Step 1: Write the component**

Create `Bacilab/Core/DesignSystem/Molecules/Card.swift`:

```swift
import SwiftUI

/// The rounded surface every screen groups related content in.
///
/// Extracted because the same background was written out in six feature files, which is how two
/// cards end up with different corner radii on adjacent screens without anyone deciding that.
///
/// The defaults are the shape the result sheet already used; `spacing` is exposed because the
/// review screen packs its rows tighter, and that is a layout choice rather than a different
/// kind of surface.
struct Card<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview("Card") {
    Card {
        Text("Result").font(.appBody.weight(.bold))
        Text("Positive 2+").font(.appTitle)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
```

- [ ] **Step 2: Adopt it in `ResultSheetView`**

Delete the private `card<Content:>` helper (lines 276–284). Replace each `card { ... }` call with `Card { ... }` — the closure bodies are unchanged.

- [ ] **Step 3: Run the full suite**

Run the full test command.
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: extract the Card molecule

The same rounded surface was written out in six feature files, which is
how neighbouring screens drift to different corner radii without anyone
deciding to."
```

---

### Task 4: `SectionHeader` and `InfoRow` molecules

Two screens each grew their own section heading: `ResultSheetView.sectionHeading(_:tinted:)` (lines 285–291) and `PatientDataView.sectionHeader(_:)` (lines 65–70).

**Files:**
- Create: `Bacilab/Core/DesignSystem/Molecules/SectionHeader.swift`
- Create: `Bacilab/Core/DesignSystem/Molecules/InfoRow.swift`
- Modify: `Bacilab/Features/ResultSheet/ResultSheetView.swift` (delete `sectionHeading` lines 285–291 and `infoRow` lines 292–307)
- Modify: `Bacilab/Features/PatientData/PatientDataView.swift` (delete `sectionHeader` lines 65–70)

**Interfaces:**
- Consumes: `Font.appBody` from `Tokens/Typography.swift`.
- Produces: `SectionHeader(_ title: String, tinted: Bool = false)` and `InfoRow(_ label: String, _ value: String)`. Tasks 9 and 11 build the patient and result sections from both.

- [ ] **Step 1: Write both components**

Create `Bacilab/Core/DesignSystem/Molecules/SectionHeader.swift`:

```swift
import SwiftUI

/// A section title. `tinted` marks the accent-coloured headings the result sheet and the patient
/// form use to open a group; plain is for headings inside one.
///
/// Two screens had each grown their own version of this, one called `sectionHeading` and one
/// `sectionHeader`, differing only in whether the tint was a parameter.
struct SectionHeader: View {
    let title: String
    var tinted: Bool = false

    init(_ title: String, tinted: Bool = false) {
        self.title = title
        self.tinted = tinted
    }

    var body: some View {
        Text(title)
            .font(.appBody.weight(.bold))
            .foregroundStyle(tinted ? Color.accentColor : .primary)
    }
}

#Preview("SectionHeader") {
    VStack(alignment: .leading, spacing: 12) {
        SectionHeader("Patient Information", tinted: true)
        SectionHeader("Total Fields Read")
    }
    .padding()
}
```

Create `Bacilab/Core/DesignSystem/Molecules/InfoRow.swift`:

```swift
import SwiftUI

/// Label on the left, value on the right — the shape a printed lab report uses.
///
/// An empty value renders as an em dash rather than as blank space, so a missing field reads as
/// "nothing was recorded" instead of looking like a layout fault.
struct InfoRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.appBody.weight(.semibold))
            Spacer(minLength: 12)
            Text(value.isEmpty ? "—" : value)
                .font(.appBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview("InfoRow") {
    VStack(spacing: 10) {
        InfoRow("MRN", "RM 240724-001")
        InfoRow("Address", "")
    }
    .padding()
}
```

- [ ] **Step 2: Adopt them**

In `ResultSheetView`, delete `sectionHeading` and `infoRow`, then replace call sites: `sectionHeading("Result", tinted: true)` → `SectionHeader("Result", tinted: true)`, and `infoRow("MRN", value)` → `InfoRow("MRN", value)`.

In `PatientDataView`, delete `sectionHeader`, then replace `sectionHeader("Patient Information")` → `SectionHeader("Patient Information", tinted: true)`. The patient form's headings were already accent-coloured, so `tinted: true` preserves them exactly.

- [ ] **Step 3: Run the full suite**

Run the full test command.
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: extract SectionHeader and InfoRow

Two screens had each grown their own section heading, differing only in
whether the tint was a parameter."
```

---

### Task 5: `LabeledField` molecule

**Files:**
- Create: `Bacilab/Core/DesignSystem/Molecules/LabeledField.swift`
- Modify: `Bacilab/Features/PatientData/PatientDataView.swift` (delete `formField` lines 71–79 and `dateField` lines 83–101)

**Interfaces:**
- Consumes: nothing beyond SwiftUI.
- Produces: `LabeledField(placeholder:text:)` and `LabeledDateField(label:date:components:)`, both `View`s. Only `PatientDataView` uses these today; they sit in `Molecules` because they know nothing about BTA and are the obvious building block for any second form.

- [ ] **Step 1: Write the component**

Create `Bacilab/Core/DesignSystem/Molecules/LabeledField.swift`:

```swift
import SwiftUI

/// A bordered text field whose name lives in the placeholder, matching the hi-fi.
struct LabeledField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .padding(14)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
    }
}

/// The same row for a date. A date picker has no placeholder to carry its name, so the name stays
/// a leading label — which is also how the hi-fi draws these.
struct LabeledDateField: View {
    let label: String
    @Binding var date: Date
    var components: DatePickerComponents = .date

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            DatePicker("", selection: $date, displayedComponents: components)
                .labelsHidden()
        }
        .padding(14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }
}

#Preview("LabeledField") {
    @Previewable @State var text = ""
    @Previewable @State var date = Date()
    return VStack(spacing: 12) {
        LabeledField(placeholder: "Patient Name", text: $text)
        LabeledDateField(label: "Date of Birth", date: $date)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
```

- [ ] **Step 2: Adopt them in `PatientDataView`**

Delete `formField` and `dateField`. Replace call sites, keeping the same order and labels:

```swift
                LabeledField(placeholder: "Medical Record Number (MRN)",
                             text: $session.patient.medicalRecordNumber)
                LabeledField(placeholder: "NIK", text: $session.patient.nationalID)
                LabeledField(placeholder: "Patient Name", text: $session.patient.name)
                LabeledDateField(label: "Date of Birth", date: $session.patient.dateOfBirth)
                LabeledField(placeholder: "Address", text: $session.patient.address)
                LabeledField(placeholder: "Phone Number", text: $session.patient.phone)
```

and for the two under Test Information:

```swift
                LabeledDateField(label: "Examination Date", date: $session.patient.examinationDate)
                LabeledDateField(label: "Sample Collection Time",
                                 date: $session.patient.sampleCollectedAt,
                                 components: [.date, .hourAndMinute])
```

- [ ] **Step 3: Run the full suite**

Run the full test command.
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: extract LabeledField and LabeledDateField"
```

---

### Task 6: `Badge` atom and testable `SessionBadge`

`SampleListView.badge(for:)` (lines 173–199) decides a history row's text and colour, including whether a grade may be shown as final. It is private to a View, so none of that is currently reachable by a test.

**Files:**
- Create: `Bacilab/Core/DesignSystem/Atoms/Badge.swift`
- Create: `Bacilab/Features/SampleList/SessionBadge.swift` (moved to `Features/Home/` in Task 8)
- Create: `BacilabTests/SessionBadgeTests.swift`
- Modify: `Bacilab/Features/SampleList/SampleListView.swift` (delete `badge(for:)` lines 173–199; `row(for:)` uses `SessionBadge` instead)

**Interfaces:**
- Consumes: `BTAGrade.displayName` and `BTAGrade.tint` (Tasks 1–2), `ExamSession.status`, `.reportedGrade`, `.isGradeConfirmed`, `DemoMode.hidesProvisionalMarks`.
- Produces: `Badge(text:tint:)` (a `View`) and `SessionBadge(session:)` with `let text: String` and `let tint: Color`. Task 9's `HistoryRow` consumes both.

- [ ] **Step 1: Write the failing tests**

Create `BacilabTests/SessionBadgeTests.swift`:

```swift
import SwiftUI
import Testing
@testable import Bacilab

/// Badge riwayat memutuskan apakah sebuah grade boleh tampil sebagai kesimpulan. Sebelumnya
/// logika itu privat di dalam sebuah View, jadi tidak ada test yang bisa menyentuhnya.
struct SessionBadgeTests {

    /// Sesi dengan `fields` lapang, tiap lapang `bta` basil, sudah terbit.
    private func published(fields: Int, bta: Int) -> ExamSession {
        let session = ExamSession()
        for _ in 0..<fields {
            let field = session.appendField(imageFileName: "f.jpg")
            session.setAnalysis(
                FieldAnalysis(
                    readings: [DetectorReading(detector: .resnet, btaCount: bta,
                                               confidence: 0.8, elapsed: 0.4)],
                    primary: .resnet),
                for: field.id)
        }
        session.status = .published
        return session
    }

    @Test("Sesi yang belum terbit tampil sebagai In progress")
    func unpublishedReadsAsInProgress() {
        let badge = SessionBadge(session: ExamSession())
        #expect(badge.text == "In progress")
    }

    @Test("Sesi terbit memakai nama tampilan grade, bukan rawValue")
    func publishedUsesDisplayName() {
        // 20 lapang × 15 basil = 1500 per 100 lapang -> 3+, dan 3+ final pada 20 lapang.
        let badge = SessionBadge(session: published(fields: 20, bta: 15))
        #expect(badge.text == "Positive 3+")
    }

    @Test("Grade final memakai warna grade-nya sendiri")
    func confirmedGradeUsesItsOwnTint() {
        let badge = SessionBadge(session: published(fields: 20, bta: 15))
        #expect(badge.tint == BTAGrade.plus3.tint)
    }
}
```

- [ ] **Step 2: Run the tests and watch them fail**

Run the full test command.
Expected: FAIL — `cannot find 'SessionBadge' in scope`.

- [ ] **Step 3: Write the atom**

Create `Bacilab/Core/DesignSystem/Atoms/Badge.swift`:

```swift
import SwiftUI

/// A pill carrying a short status or grade, tinted by severity.
///
/// The background is the tint at low opacity rather than a separate colour, so a new tint needs
/// one decision instead of two that can drift apart.
struct Badge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.appCaption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }
}

#Preview("Badge") {
    VStack(spacing: 8) {
        Badge(text: "Positive 3+", tint: BTAGrade.plus3.tint)
        Badge(text: "Negative", tint: BTAGrade.negative.tint)
        Badge(text: "In progress", tint: .orange)
    }
    .padding()
}
```

- [ ] **Step 4: Write the decision, separated from the drawing**

Create `Bacilab/Features/SampleList/SessionBadge.swift`:

```swift
import SwiftUI

/// What a history row's badge says about a session, and in what colour.
///
/// Separated from the view because this is a clinical decision, not styling: it decides whether a
/// grade may appear as a conclusion. Below the WHO/IUATLD field minimum it is not one, and the
/// list is where people scan to see what a slide said — so it must not read as final while the
/// result sheet marks the same session provisional.
///
/// The sharpest case is a session whose fields all failed analysis: nothing was read,
/// `suggestedGrade` falls back to Negative, and without the confirmation check the row would show
/// a plain green "Negative" for a slide nobody looked at.
struct SessionBadge {
    let text: String
    let tint: Color

    init(session: ExamSession) {
        guard session.status == .published else {
            text = "In progress"
            tint = .orange
            return
        }

        let name = session.reportedGrade.displayName

        guard session.isGradeConfirmed || DemoMode.hidesProvisionalMarks else {
            text = "\(name) · Provisional"
            tint = .orange
            return
        }

        text = name
        tint = session.reportedGrade.tint
    }
}
```

- [ ] **Step 5: Run the tests and watch them pass**

Run the full test command.
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Adopt in the view**

In `SampleListView`, delete `badge(for:)`. In `row(for:)`, replace the first line and the badge rendering:

```swift
    private func row(for session: ExamSession) -> some View {
        let badge = SessionBadge(session: session)
```

and wherever the row drew the pill by hand, use `Badge(text: badge.text, tint: badge.tint)`.

- [ ] **Step 7: Run the full suite**

Run the full test command.
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor: Badge atom, and make the history badge testable

badge(for:) decided whether a grade may show as a conclusion, from
inside a private View method no test could reach. SessionBadge separates
that decision from the drawing, and it now has tests."
```

---

### Task 7: `Swatch` atom

**Files:**
- Create: `Bacilab/Core/DesignSystem/Atoms/Swatch.swift`
- Modify: `Bacilab/Features/Review/Components/DetectorLegend.swift` (delete the private `swatch(for:)`)

**Interfaces:**
- Consumes: nothing beyond SwiftUI.
- Produces: `Swatch(tint: Color, dash: [CGFloat])` — a 26×10 dashed line sample.

- [ ] **Step 1: Write the atom**

Create `Bacilab/Core/DesignSystem/Atoms/Swatch.swift`:

```swift
import SwiftUI

/// A short line drawn in a tint and dash pattern, used to name what a pattern means.
///
/// It repeats the stroke rather than showing a plain colour chip on purpose: a chip would be
/// indistinguishable in a black-and-white screenshot and for a colour-blind reader, which is the
/// same reason the patterns exist on the boxes it is explaining.
struct Swatch: View {
    let tint: Color
    var dash: [CGFloat] = []

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 5))
            path.addLine(to: CGPoint(x: 26, y: 5))
        }
        .stroke(tint, style: StrokeStyle(lineWidth: 2.5, dash: dash))
        .frame(width: 26, height: 10)
    }
}

#Preview("Swatch") {
    VStack(alignment: .leading, spacing: 8) {
        Swatch(tint: .red)
        Swatch(tint: .yellow, dash: [1.5, 2.5])
    }
    .padding()
    .background(.black)
}
```

- [ ] **Step 2: Adopt it**

In `DetectorLegend`, delete the private `swatch(for:)` and call:

```swift
                    Swatch(tint: DetectorStyle.tint(for: reading.detector),
                           dash: DetectorStyle.dash(for: reading.detector))
```

- [ ] **Step 3: Run the full suite**

Run the full test command.
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: extract the Swatch atom"
```

---

### Task 8: Rename `SampleList` to `Home`

The `Sample` type this was named after no longer exists, so the name sends a new reader looking for something that is not there.

**Files:**
- Move: `Bacilab/Features/SampleList/` → `Bacilab/Features/Home/`
- Rename: `SampleListView.swift` → `HomeView.swift`, `SampleListViewModel.swift` → `HomeViewModel.swift`
- Modify: `Bacilab/App/ElectraLabApp.swift`
- Modify: `BacilabTests/SessionListViewModelTests.swift` and any other test referencing the old names (5 references in total across the app and tests)

**Interfaces:**
- Consumes: `SessionBadge` from Task 6, which moves with the folder.
- Produces: `HomeView` and `HomeViewModel`. `HomeViewModel` keeps the same initialiser: `HomeViewModel(sessionStore:seedsDemoData:)`.

- [ ] **Step 1: Move and rename the files**

```bash
git mv Bacilab/Features/SampleList Bacilab/Features/Home
git mv Bacilab/Features/Home/SampleListView.swift Bacilab/Features/Home/HomeView.swift
git mv Bacilab/Features/Home/SampleListViewModel.swift Bacilab/Features/Home/HomeViewModel.swift
```

- [ ] **Step 2: Rename the types across the project**

```bash
grep -rl "SampleListView\|SampleListViewModel" Bacilab BacilabTests BacilabUITests --include="*.swift" \
  | xargs sed -i '' 's/SampleListViewModel/HomeViewModel/g; s/SampleListView/HomeView/g'
```

Then read `Bacilab/Features/Home/HomeView.swift` and `ElectraLabApp.swift` and fix any comment left reading awkwardly — `sed` rewrites prose as readily as code.

- [ ] **Step 3: Run the full suite**

Run the full test command.
Expected: `** TEST SUCCEEDED **`. If the build fails on a missing type, a reference outside the three source roots was missed.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: rename SampleList to Home

The Sample type this was named after no longer exists, so the name sent
a new reader looking for something that is not there."
```

---

### Task 9: Split `HomeView`

**Files:**
- Create: `Bacilab/Features/Home/Components/HistoryRow.swift`
- Create: `Bacilab/Features/Home/Components/NewAnalysisCard.swift`
- Create: `Bacilab/Features/Home/Components/SearchBar.swift`
- Modify: `Bacilab/Features/Home/HomeView.swift` (currently 253 lines: `banner` 82–107, `searchBar` 108–130, `row(for:)` 200–248)

**Interfaces:**
- Consumes: `SessionBadge` and `Badge` (Task 6), `ExamSession`.
- Produces: `HistoryRow(session:)`, `NewAnalysisCard(action:)`, `SearchBar(text:)`. Nothing later depends on these.

- [ ] **Step 1: Move `row(for:)` into `HistoryRow`**

Create `Bacilab/Features/Home/Components/HistoryRow.swift` holding a `HistoryRow: View` with `let session: ExamSession`. Move the body of `HomeView.row(for:)` (lines 200–248) into its `body`, replacing the local `badge` constant with `SessionBadge(session: session)`. Add:

```swift
#Preview("HistoryRow") {
    let session = ExamSession()
    session.patient.name = "Ahmad Rizki"
    session.patient.medicalRecordNumber = "RM 240724-001"
    return HistoryRow(session: session)
        .padding()
        .background(.black)
}
```

- [ ] **Step 2: Move `banner` into `NewAnalysisCard`**

Create `NewAnalysisCard.swift` with `let action: () -> Void`. Move the body of `HomeView.banner` (lines 82–107) into it, replacing whatever it did on tap with `action()`. Give it a `#Preview` that passes `{}`.

- [ ] **Step 3: Move `searchBar` into `SearchBar`**

Create `SearchBar.swift` with `@Binding var text: String`. Move the body of `HomeView.searchBar` (lines 108–130) into it. Preview with `@Previewable @State`.

- [ ] **Step 4: Rewire `HomeView`**

Delete the three private members and call the components. The `.safeAreaInset(edge: .bottom)` that hosts the search bar stays in `HomeView` — it positions the bar, and position is the parent's business.

- [ ] **Step 5: Run the full suite**

Run the full test command.
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: split HomeView into HistoryRow, NewAnalysisCard and SearchBar"
```

---

### Task 10: Split `ScanView`

**Files:**
- Create: `Bacilab/Features/Scan/Components/Viewfinder.swift`
- Create: `Bacilab/Features/Scan/Components/ShutterBar.swift`
- Modify: `Bacilab/Features/Scan/ScanView.swift` (currently 243 lines: `viewfinder(side:)` 132–155, `focusBadge` 156–169, `controls` 170–230)

**Interfaces:**
- Consumes: `ScanViewModel`, `CameraPreviewView`.
- Produces: `Viewfinder(side:viewModel:)` and `ShutterBar(viewModel:)`.

- [ ] **Step 1: Move the viewfinder and its focus badge**

Create `Viewfinder.swift` holding `Viewfinder: View` with `let side: CGFloat` and `let viewModel: ScanViewModel`. Move `viewfinder(side:)` and `focusBadge` into it — the badge is drawn over the preview and belongs with it.

Keep the simulator guard exactly as it is: all camera code stays inside `#if targetEnvironment(simulator)` / `#else`, and the simulator branch keeps drawing the radial-gradient test pattern.

- [ ] **Step 2: Move the controls**

Create `ShutterBar.swift` with `let viewModel: ScanViewModel`, holding the body of `controls` (lines 170–230), including the `PhotosPicker` import button.

- [ ] **Step 3: Rewire `ScanView` and give both a `#Preview`**

`ScanView` keeps the `GeometryReader` that computes `side`, and the `batchCeiling` and `fieldCounter` members. Each new file gets a `#Preview` building a `ScanViewModel` the same way `ScanView`'s existing previews do.

- [ ] **Step 4: Run the full suite**

Run the full test command.
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: split ScanView into Viewfinder and ShutterBar"
```

---

### Task 11: Split `ResultSheetView`

**Files:**
- Create: `Bacilab/Features/ResultSheet/Components/GradeBox.swift`
- Create: `Bacilab/Features/ResultSheet/Components/PatientSection.swift`
- Create: `Bacilab/Features/ResultSheet/Components/NotesSection.swift`
- Modify: `Bacilab/Features/ResultSheet/ResultSheetView.swift` (currently 352 lines: `patientCard` 81–94, `gradeBox` 130–179, `gradeDerivation` 180–237, `derivationRow` 238–252, `notesCard` 253–275)

**Interfaces:**
- Consumes: `Card`, `SectionHeader`, `InfoRow` (Tasks 3–4), `BTAGrade.displayName` / `.criterion` / `.tint` (Tasks 1–2), `ExamSession`.
- Produces: `GradeBox(session:)`, `PatientSection(patient:)`, `NotesSection(session:onCommit:)`.

- [ ] **Step 1: Move the grade box and its derivation**

Create `GradeBox.swift` with `@Bindable var session: ExamSession` and its own `@State private var isExpanded = false`. Move `gradeBox`, `gradeDerivation` and `derivationRow` into it.

Two behaviours must survive the move exactly, because both are what stop a shortfall reading from looking final:
- the `PROVISIONAL` chip stays gated on `!session.isGradeConfirmed, !DemoMode.hidesProvisionalMarks`;
- the "Fields required" derivation row keeps showing the plain requirement when `DemoMode.hidesProvisionalMarks` is on, and the met/short verdict when it is off.

The grade pickers inside the derivation keep calling `session.chooseGrade(band)` — an analyst re-deciding an extrapolated grade is ordinary practice, and this is where they do it.

- [ ] **Step 2: Move the patient card**

Create `PatientSection.swift` with `let patient: PatientInfo`, holding `patientCard` (lines 81–94) built from `Card`, `SectionHeader` and `InfoRow`. It takes `PatientInfo` rather than the session because it reads nothing else — the narrower input is what keeps it obviously read-only.

- [ ] **Step 3: Move the notes card**

Create `NotesSection.swift` with `@Bindable var session: ExamSession` and `let onCommit: () -> Void`, holding `notesCard` (lines 253–275). `ResultSheetView` passes its existing `persist` as `onCommit`, so saving stays the parent's job.

- [ ] **Step 4: Rewire `ResultSheetView` and add previews**

`ResultSheetView` keeps `body`, `resultCard`, `meanConfidence`, `persist()` and `formatted(_:)`. Give each new component a `#Preview`; `GradeBox` needs two — one confirmed, one below the field gate — because that difference is the whole point of the component.

- [ ] **Step 5: Run the full suite**

Run the full test command.
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: split ResultSheetView into GradeBox, PatientSection and NotesSection"
```

---

### Task 12: Split `ReviewView`

The largest file at 415 lines.

**Files:**
- Create: `Bacilab/Features/Review/Components/ReviewHeader.swift`
- Create: `Bacilab/Features/Review/Components/GradePicker.swift`
- Create: `Bacilab/Features/Review/Components/FieldCountRow.swift`
- Modify: `Bacilab/Features/Review/ReviewView.swift` (`analysisProgress` 94–109, `fieldCountRow` 135–164, `countLabel` 167–180, `confidenceLine` 181–217, `gradeSection` 286–319, `provisionalNotice` 320–351)

**Interfaces:**
- Consumes: `ReviewViewModel`, `ExamSession`, `BTAGrade.displayName` (Task 2).
- Produces: `ReviewHeader(viewModel:)`, `GradePicker(session:viewModel:onContinueScanning:)`, `FieldCountRow(viewModel:onEdit:)`.

- [ ] **Step 1: Move the progress line**

Create `ReviewHeader.swift` with `let viewModel: ReviewViewModel`, holding `analysisProgress` (lines 94–109).

- [ ] **Step 2: Move the count row**

Create `FieldCountRow.swift` with `let viewModel: ReviewViewModel` and `let onEdit: () -> Void`, holding `fieldCountRow`, `countLabel`, `confidenceLine` and the `lowConfidencePercent` constant.

The confidence wording must move verbatim. It says how sure the model is about the bacilli **it kept** — the ONNX graph discards everything below 0.70, so the figure can never read under 70% however weak the field is. It is not a confidence figure for the result, and must not be reworded into one.

- [ ] **Step 3: Move the grade picker and its shortfall notice**

Create `GradePicker.swift` with `@Bindable var session: ExamSession`, `let viewModel: ReviewViewModel` and `let onContinueScanning: () -> Void`, holding `gradeSection` and `provisionalNotice`.

Both gates must survive exactly: the notice appears only when `!session.isGradeConfirmed`, the warning text inside it is additionally gated on `!DemoMode.hidesProvisionalMarks`, and the **Continue Scanning** button is **not** gated — hiding the shortfall and the way to fix it would leave the analyst no route to a grade that is actually confirmed. The button calls `onContinueScanning`, which is where `ReviewView` sets `session.status = .scanning` and dismisses.

- [ ] **Step 4: Rewire `ReviewView` and add previews**

`ReviewView` keeps `body`, `fieldCanvas`, `detectorLegend`, `fieldActions`, `totalsSection`, `statCell`, `notesSection`, `publishButton` and `publish()`. Each new component gets a `#Preview` built like the existing "Review – 6 lapang" preview.

- [ ] **Step 5: Run the full suite**

Run the full test command.
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: split ReviewView into ReviewHeader, GradePicker and FieldCountRow"
```

---

### Task 13: `ARCHITECTURE.md`

**Files:**
- Create: `ARCHITECTURE.md` (repository root)

**Interfaces:**
- Consumes: the final structure produced by Tasks 1–12.
- Produces: nothing code depends on.

- [ ] **Step 1: Verify the structure before describing it**

A document that describes a layout the repository does not have is worse than none. Capture the real tree first and write from it:

```bash
find Bacilab -name "*.swift" | sort
```

- [ ] **Step 2: Write the document**

Create `ARCHITECTURE.md` covering, in this order:

1. **What this is** — an iOS app for reading BTA (acid-fast bacilli) sputum smear slides at Electra Lab, and the four screens: patient data → scan → review → published result sheet.
2. **Where code goes** — the folder map, then the placement rule as the decision it is:
   > Does it know anything about BTA? No → `Core/DesignSystem`. Yes → is it used by more than one feature? Yes → `DesignSystem/Organisms`. No → `Features/<Feature>/Components/`.
   Note that `Organisms/` is empty today and that this is a fact about the app, not an oversight.
3. **Dependency injection** — `AppDependencies` is created once in `ElectraLabApp` and passed as an explicit `let` down the navigation chain. `@Environment(AppDependencies.self)` **crashes at runtime** inside a view pushed within the sheet's `NavigationStack`; it is safe only in `HomeView`, which sits directly under the `.environment(dependencies)` modifier.
4. **How a field travels** — camera or photo library → `FieldFraming` crops the identical square → `SessionStore` writes the JPEG to disk → the field is appended → `FieldAnalysisQueue` analyses it serially in the background → Review shows and corrects it → publishing freezes the reading.
5. **Decisions not to change without reading why**, each with its consequence:
   - **WHO/IUATLD field gates.** 3+ needs 20 fields, 2+ needs 50, and 1+/Scanty/Negative need the full 100. The asymmetry is deliberate: calling a slide negative is the reading that, if wrong, sends an infectious patient home untreated.
   - **Never fabricate a clinical figure.** A confidence badge once fell back to a random 85–95% when none was available. Anything shown beside a grade or a count is read as diagnostic.
   - **A failed capture is not a field.** Counting one inflates the denominator and drags the grade down.
   - **Every scanned field counts, including empty ones.** Auto-scan once incremented only when bacilli were found, which made grade Negative structurally unreachable.
   - **The overlay draws on the frame that was analysed**, never a live preview, and the canvas is a square with a dashed circle drawn only as a guide — a circular *mask* would hide about 21% of the analysed area, letting bacilli be counted where the analyst cannot see them.
   - **`BTAGrade.rawValue` is the storage key in `manifest.json`.** Use `displayName` for anything on screen; renaming a case makes saved sessions vanish from the list, because `SessionStore` skips manifests it cannot decode.
   - **`DemoMode.hidesProvisionalMarks` is an exhibition switch.** With it on, a Negative read from 20 fields looks identical on screen to one read from the full 100. It must be `false` before the app meets a real slide.
6. **Running it** — the test command from this plan's Global Constraints, and the note that Xcode synchronized file groups mean `project.pbxproj` is never edited by hand.

- [ ] **Step 3: Check every path the document names**

For each file or folder path mentioned, confirm it exists. A stale path is the fastest way for a new reader to stop trusting the document.

- [ ] **Step 4: Commit**

```bash
git add ARCHITECTURE.md
git commit -m "docs: ARCHITECTURE.md for people

CLAUDE.md is organised around what the assistant must not get wrong.
This is the orientation a new team member needs: the flow, where code
goes and why, and the decisions that look arbitrary until you read the
consequence attached to each."
```

---

## Done when

- `xcodebuild test` reports `** TEST SUCCEEDED **` with no test expectation edited beyond renames.
- No file over ~250 lines in `Features/`.
- `grep -rn "design: .rounded" Bacilab --include="*.swift"` returns nothing.
- `grep -rn "\.rawValue" Bacilab/Features --include="*.swift"` returns only storage keys and log lines — no grade name rendered from `rawValue`.
- `ARCHITECTURE.md` exists and every path it names resolves.
- `flow-redesign` merges to `main`, which is the starting point Piece B is cut from.
