# Rancangan Ulang Flow Bacilab (Electra Lab)

**Tanggal:** 2026-08-12
**Status:** disetujui untuk masuk rencana implementasi

## 1. Masalah

Flow yang ada adalah wizard 4 layar linear (Data Pasien → Capture → Review → Interpretation),
sementara pekerjaan sebenarnya adalah satu sesi panjang yang harus bisa dijeda, dikoreksi, dan
diaudit. Ketidakcocokan itu memunculkan tabrakan berikut:

- **Grade punya tiga pemilik.** Pills grade ada di `CaptureView` dan `AnalysisView`; keduanya
  memanggil `selectGrade()` yang menyalakan `hasManualGrade` secara permanen. Satu tap saat
  capture mematikan grading otomatis untuk sisa sesi, tanpa jalan kembali.
- **Riwayat lapang tidak pernah tampil.** `SampleDraft.capturedFields` sudah menyimpan setiap
  lapang lengkap dengan gambar, readings per model, sumber, dan timestamp. Tidak ada satu pun
  layar yang merendernya.
- **Layar Interpretation kosong secara fungsi.** Ia mengulang angka yang sudah dilihat dua kali,
  lalu buntu — tidak ada jalan keluar setelah tombol Simpan berubah jadi "Tersimpan".

Selain itu ada dua cacat yang berdiri sendiri:

- **Denominator auto-scan salah.** `CaptureViewModel` menaikkan `capturedFieldCount` hanya ketika
  `btaCount > 0`, sementara capture manual menaikkannya selalu. Lapang kosong tidak pernah
  tercatat di mode auto, sehingga **grade Negatif secara struktural tidak bisa dicapai**.
- **Auto Scan hilang setelah lapang pertama.** `shutterButton` hanya dirender pada cabang
  `capturedFieldCount == 0`.

## 2. Bentuk baru

```
Beranda
 ├─ sesi "Berjalan"  ─────────────► lanjutkan Sesi Scan
 ├─ sesi terbit ─────────────────► Lembar Hasil (read-only)
 └─ Analisis Baru ─► Data Pasien ─► Sesi Scan ─► Review ─►[Terbitkan]─► Lembar Hasil
                                        ▲                     │
                                        └── "Lanjut Scan" ◄────┘
                                            (grade butuh lebih banyak lapang)
```

Aturan pokok: **satu keputusan, satu pemilik.**

| Keputusan | Pemilik | Sengaja absen di |
|---|---|---|
| Identitas pasien | Data Pasien | — |
| Apa yang dihitung sebagai lapang | Sesi Scan | Review tidak bisa menambah lapang |
| Berapa BTA di tiap lapang | Review | Sesi Scan |
| Grade | Review | Sesi Scan, Lembar Hasil |
| Catatan lab | Review | Lembar Hasil |
| Final / terbit | Review | Lembar Hasil read-only |

Kunci yang menghapus ketiga tabrakan: **Sesi Scan buta terhadap BTA.** Ia hanya menghasilkan
lapang — tidak ada hitungan, grade, confidence, picker model, maupun kolom perbandingan di sana.

## 3. Ritme kerja yang diasumsikan

Teknisi menempel di mikroskop sampai lapang cukup, tanpa banyak melihat layar. Setelah selesai
barulah ia duduk, memeriksa hasil AI per lapang, mengoreksi, dan memutuskan grade. Inilah alasan
review berhak jadi fase terpisah dan alasan sesi boleh sangat minim.

## 4. Model data

Perubahan terbesar: **hitungan tidak disimpan, tapi diturunkan dari lapang.**

```swift
@Observable final class ExamSession {
    var patient: PatientInfo
    private(set) var fields: [FieldRecord]
    var chosenGrade: BTAGrade?          // nil sampai Review memutuskan
    var notes: String
    var status: SessionStatus           // .scanning / .reviewing / .published
}

struct FieldRecord: Identifiable {
    let id: UUID
    let index: Int                      // urutan scan; jadi label pager "LP n"
    let imagePath: URL                  // berkas di disk, resolusi analisis
    var analysis: FieldAnalysis?        // nil = masih dalam antrean
    var correctedCount: Int?            // dari keypad; nil = pakai hitungan model
    var isExcluded: Bool                // dibuang dari pembilang dan penyebut
}

struct FieldAnalysis {
    let readings: [DetectorReading]     // per model; tipe yang sudah ada
    let primary: DetectorKind           // .resnet
}

struct PatientInfo {
    var medicalRecordNumber: String     // MRN
    var nationalID: String              // NIK
    var name: String
    var dateOfBirth: Date
    var address: String
    var phone: String
    var examinationDate: Date
    var sampleCollectedAt: Date
}
```

Seluruh angka menjadi turunan, bukan state:

```swift
var countedFields: [FieldRecord]    // tidak excluded DAN punya hitungan
var examinedFieldCount: Int         // countedFields.count — penyebut grading
var totalBTA: Int                   // Σ countedFields.effectiveCount
var suggestedGrade: BTAGrade        // BTAGrade.grade(for: totalBTA, across: examinedFieldCount)
var reportedGrade: BTAGrade         // chosenGrade ?? suggestedGrade
var isGradeConfirmed: Bool          // examinedFieldCount >= reportedGrade.minimumFields
var fieldsRemainingForGrade: Int    // max(0, reportedGrade.minimumFields - examinedFieldCount)
```

```swift
extension FieldRecord {
    /// Hitungan yang berlaku untuk lapang ini, atau nil kalau belum ada.
    /// Optional dengan sengaja: lapang tanpa hitungan bukan lapang bernilai nol.
    var effectiveCount: Int? {
        if let correctedCount { return correctedCount }
        guard let analysis else { return nil }
        return analysis.reading(analysis.primary)?.btaCount
    }
}
```

Penamaan sengaja dibedakan dari kode lama: `examinedFieldCount` adalah **berapa lapang sudah
dibaca** (penyebut grading), sedangkan `SampleDraft.totalFieldCount` yang lama berarti **target**
(100). Target sekarang jadi konstanta terpisah `ExamSession.batchTarget = 20` dan tidak pernah
ikut perhitungan grading — ia hanya mengisi teks "n of 20" di layar scan.

### Yang dihapus

`SampleDraft.manualBTACount`, `detectorCounts`, `detectorFields`, `countSource`, `adoptCount`,
`reconcileCountSource`, `hasManualGrade`, dan field warisan `patientID` / `sampleType` /
`collectedAt` / `doctorName` / `accessionNumber`.

Seluruh kelas bug yang didokumentasikan panjang di CLAUDE.md — akumulator tunggal yang dilabeli
ulang ketika model berganti — hilang secara struktural, bukan dijaga oleh disiplin. Dengan satu
sumber kebenaran (array `fields`), tidak ada akumulator kedua yang bisa menyimpang.

`hasManualGrade` tidak diperlukan lagi karena `chosenGrade` yang optional sudah membedakan
"belum diputuskan" dari "diputuskan manusia", dan grade hanya bisa diset dari satu layar.

## 5. Persistensi

- **Gambar**: berkas JPEG di Application Support, `sessions/<session-id>/field-007.jpg`, pada
  **resolusi analisis** (sisi pendek ≥ 1200, sesuai `min_size` transform Faster R-CNN). Thumbnail
  640 px seperti `freeze()` sekarang tidak cukup — analisis berjalan belakangan dari berkas ini.
- **Metadata**: satu manifest JSON per sesi, ditulis ulang setiap kali sebuah lapang selesai
  direkam atau dianalisis.
- `SampleRepository` yang sekarang in-memory diganti implementasi yang membaca/menulis direktori
  tersebut. JSON, bukan SwiftData — paling sedikit mesin untuk kebutuhan sesederhana ini.
- Sesi yang belum terbit muncul di beranda berstatus **Berjalan**, bisa dilanjutkan atau dibuang.

Status yang ditampilkan beranda diturunkan dari `ExamSession.status`, bukan dari ada-tidaknya
hasil analisis:

| `ExamSession.status` | Tampil di beranda | Tap membawa ke |
|---|---|---|
| `.scanning`, `.reviewing` | Berjalan | Sesi Scan / Review, dilanjutkan |
| `.published` + grade Negatif | Negatif | Lembar Hasil |
| `.published` + grade lain | Positif | Lembar Hasil |

Ini menggantikan `SampleStatus` yang sekarang, yang menurunkan status dari `analysisResult` dan
karenanya **tidak pernah bisa menghasilkan Pending** — `Sample.build` selalu mengisi
`analysisResult`, sehingga chip filter "Pending" di beranda selalu kosong.

Perkiraan ukuran: 20 lapang pada resolusi analisis ≈ puluhan MB per sesi.

## 6. Sesi Scan

- Auto-scan mengambil frame tiap ~1,5 detik. **Setiap frame terhitung sebagai satu lapang**,
  termasuk yang tidak berisi BTA. Ini memperbaiki cacat denominator yang membuat Negatif mustahil.
- Target batch **20 lapang**, dan 20 adalah batch pertama — bukan plafon (lihat §8).
- Viewfinder **kotak** dengan lingkaran tipis sebagai panduan okuler. Kotak itu persis crop
  `FieldFraming` yang diterima model, jadi semua yang ditampilkan dianalisis dan semua yang
  dianalisis ditampilkan. Masker lingkaran menutupi π/4 ≈ 78,5% luas kotak, menyisakan **21,5%**
  area yang tetap dihitung tapi tidak pernah terlihat.
- **Pemeriksaan fokus live** dihitung dari ketajaman frame, bukan dari detektor — murah, bisa tiap
  frame. `focusCheckBadge` yang ada sekarang selalu menampilkan "Focus Check ✓" tanpa memeriksa
  apa pun.
- Yang tampil di layar hanya: viewfinder, hitungan lapang, peringatan fokus, kontrol scan, Selesai.

### Konsekuensi yang diterima

Kalau preparat diam, lapang yang sama terhitung berkali-kali. Rasio per-100 tidak melenceng
(BTA dan lapang naik bersama), tapi `examinedFieldCount` bisa menyentuh ambang tanpa sejumlah itu
lapang berbeda pernah dilihat — sehingga gerbang `isGradeConfirmed` menyala palsu. Peredamnya
adalah kemampuan **menghapus lapang** di Review: duplikat terlihat sebagai gambar yang mirip dan
bisa dibuang, dan penyebut ikut terkoreksi. Deteksi geser otomatis ditolak karena ambangnya
menuntut kalibrasi baru yang belum tentu terbayar.

## 7. Antrean analisis

```
Sesi:    frame → crop FieldFraming → tulis JPEG → append FieldRecord → enqueue
                                                        ↓ (latar, serial)
Antrean: satu lapang → semua model atas byte identik → FieldAnalysis kembali ke sesi
```

- Antrean **serial**, satu lapang pada satu waktu, pada `DispatchQueue` privat yang sudah dipakai
  ORT — bukan cooperative pool. Serial karena paralel akan menggilas CPU dan memicu throttling
  termal di tengah sesi.
- Scan tidak pernah menunggu model. Saat teknisi menekan "Selesai", sebagian besar lapang sudah
  dianalisis; sisanya diselesaikan sambil Review terbuka.
- Review menampilkan sisa antrean ("menganalisis 14/20"). Lapang yang belum selesai tampil dengan
  indikator memuat, **bukan angka 0**.
- Semua model membaca berkas yang identik, jadi perbandingan antar model adil tanpa usaha
  tambahan — itulah alasan `FieldFraming` ada.

Konsekuensi: confidence tidak bisa tampil live di layar kamera seperti pada hi-fi. Ia menyusul
di Review.

## 8. Aturan klinis

Grading tetap `BTAGrade.grade(for:across:)` dan gerbang `BTAGrade.minimumFields` tidak berubah:

| Grade | Kriteria per 100 lapang | Lapang minimum |
|---|---|---|
| Negatif | 0 BTA | 100 |
| Scanty | 1–9 BTA | 100 |
| 1+ | 10–99 BTA | 100 |
| 2+ | 100–1000 BTA | 50 |
| 3+ | >1000 BTA | 20 |

Asimetrinya disengaja: smear berat mengumumkan dirinya cepat, sedangkan menyebut slide Negatif
atau Scanty adalah pembacaan yang, kalau salah, memulangkan pasien menular tanpa pengobatan.

**Karena batch pertama 20 lapang, hanya 3+ yang langsung sah.** Ketika grade yang dipilih menuntut
lebih banyak lapang daripada yang sudah discan:

- Hasil **tetap bisa diterbitkan**, tapi bercap **SEMENTARA**.
- Lembar hasil menyebut kekurangannya secara eksplisit: "Scanty perlu 100 lapang — kurang 80".
- Tombol **Lanjut Scan** membawa kembali ke Sesi Scan dan menambah lapang ke sesi yang sama.

Menerbitkan tetap diperbolehkan (bukan diblokir) supaya teknisi tidak terjebak ketika preparat
sudah tidak ada di tangan; jalan pintas yang lahir dari blokir lebih berbahaya daripada cap
SEMENTARA yang jujur.

## 9. Layar

| Layar | Isi | Sengaja tidak ada |
|---|---|---|
| **Beranda** | Electra Lab, Analisis Baru, riwayat, pencarian, filter status termasuk **Berjalan** | tombol "Lihat semua" yang aksinya kosong |
| **Data Pasien** | MRN, NIK, Nama, Tgl Lahir, Alamat, Telepon, Tgl Pemeriksaan, Waktu Pengambilan Sampel | nama dokter, no. akses |
| **Sesi Scan** | viewfinder kotak + panduan lingkaran, "n of 20", peringatan fokus live, mulai/stop auto-scan, Selesai | hitungan BTA, grade, confidence, picker model, kolom perbandingan |
| **Review** | pager LP bernomor dengan penanda perlu-verifikasi, gambar + box tiap model, keypad numerik untuk mengedit hitungan lapang, hapus lapang, pilih grade, catatan lab, Terbitkan | menambah lapang |
| **Lembar Hasil** | read-only: data pasien, grade + "Analisis AI ≠ diagnosis medis", statistik, catatan | tombol simpan |

Lembar Hasil adalah **layar yang sama** dengan yang dibuka ketika menekan sampel di beranda. Ini
menghapus peran ganda `ResultView` sekarang, yang menampilkan tombol "Simpan Hasil" bahkan ketika
sedang membuka riwayat lama.

Nama fasilitas di seluruh UI: **Electra Lab**.

## 10. Penanganan error

- **Izin kamera ditolak** → alert dengan tautan ke Pengaturan (perilaku sekarang dipertahankan).
- **Capture gagal** → lapang tidak dicatat sama sekali. Menghitung capture gagal akan menggelembungkan
  penyebut dan menyeret grade turun.
- **Analisis satu lapang gagal** → lapang ditandai "perlu dihitung manual" dan **dikeluarkan dari
  pembilang maupun penyebut** sampai analis mengisinya lewat keypad. Tidak pernah dinilai 0
  diam-diam: model yang rusak akan terlihat seperti model yang tidak melihat apa-apa.
- **Terbit sementara masih ada lapang tanpa hitungan** → peringatan yang menyebut lapang mana.
- **Gagal menulis ke disk** → scan dihentikan dan disampaikan, bukan diteruskan diam-diam.
- **App terbunuh saat scan** → sesi dipulihkan dari manifest JSON; lapang yang sudah tertulis tetap ada.

## 11. Testing

Tes detektor yang ada (`BTADetectorTests`, `YOLO11DetectorTests`, `YOLO11RawTensorTests`,
`YOLOInputSizeTests`, `DualDetectorTests`) tidak disentuh — rancangan ini tidak mengubah decoding
maupun model. `CaptureFlowTests` ditulis ulang karena `manualBTACount` hilang. `OverlayTests`
menyesuaikan ke sumber box yang baru.

Tes baru:

- Setiap frame terhitung sebagai lapang, termasuk yang 0 BTA — **ini cacat utamanya**.
- `totalBTA` dan `examinedFieldCount` benar setelah koreksi keypad.
- Lapang yang di-exclude hilang dari pembilang **dan** penyebut.
- Lapang gagal-analisis tidak menyumbang 0 ke keduanya.
- Gerbang SEMENTARA menyala untuk tiap grade yang di bawah `minimumFields`, dan padam tepat di ambangnya.
- `reportedGrade` mengikuti `chosenGrade` bila ada, dan `suggestedGrade` bila tidak.
- Sesi pulih utuh dari manifest (round-trip tulis → baca).

## 12. Urutan implementasi

1. **Model data + persistensi + turunan**, tanpa UI. Termasuk pembongkaran `SampleDraft`.
2. **Sesi Scan + antrean analisis latar.**
3. **Review** — pager, keypad, hapus lapang, pilih grade.
4. **Lembar Hasil + beranda** — termasuk status Berjalan dan penghapusan peran ganda `ResultView`.

## 13. Asumsi dan yang belum diputuskan

- **Field wajib di Data Pasien**: diasumsikan Nama dan MRN wajib, sisanya opsional. Belum
  dikonfirmasi ke tim.
- **Penanda oranye pada pager hi-fi** diasumsikan berarti "perlu verifikasi manual". Kalau ia
  berarti hal lain, bagian triase Review perlu ditinjau ulang.
- **Ambang "low confidence"** belum ditentukan. Perlu hati-hati: grafik ONNX sudah membuang
  deteksi di bawah 0,70, sehingga confidence yang dilaporkan tidak pernah bisa terbaca di bawah
  70% betapapun lemahnya sebuah lapang. Angka itu menyatakan seberapa yakin model terhadap basil
  yang **ia simpan**, bukan seberapa yakin siapa pun terhadap hitungannya.
- **Waktu analisis di device belum diukur.** Angka ~0,6 detik per lapang berasal dari M5 CPU.
  Anggaran waktu di §7 adalah perkiraan dan harus diukur sebelum interval auto-scan dikunci.
- **Ekspor / cetak lembar hasil** tidak termasuk dalam lingkup ini.
- **Akurasi model** belum pernah divalidasi terhadap slide yang dibaca di lapangan. Fold 4
  melaporkan AP50 0,835 pada split validasinya sendiri, tapi rata-rata 5 fold adalah AP50 0,72 /
  count MAE 1,81 — itu ekspektasi yang lebih jujur.

## 14. Perubahan dokumen lain

`CLAUDE.md` perlu diperbarui setelah implementasi: nama fasilitas (Klinik Bunda → Electra Lab),
struktur file, hilangnya `SampleDraft` beserta aturan `reconcileCountSource`, dan aturan baru
bahwa setiap frame terhitung sebagai lapang.
