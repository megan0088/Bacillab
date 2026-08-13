# Pipeline Deteksi BTA — Bacilab

Dokumen ini menjelaskan perjalanan satu lapang pandang, dari lensa okuler sampai menjadi
angka yang dibaca analis. Ditulis untuk merapikan alur yang tumbuh bertahap saat tiga model
ditambahkan satu per satu.

Status per 10 Agustus 2026. **Belum ada satu pun angka di sini yang divalidasi terhadap slide
Klinik Bunda.**

---

## 1. Gambaran satu lapang

```
                      ┌──────────────┐
   Kamera / Galeri ──►│ FieldFraming │──► persegi tegak, terpusat
                      └──────────────┘         │
                                               │  piksel yang SAMA untuk semua model
                    ┌──────────────────────────┼──────────────────────────┐
                    ▼                          ▼                          ▼
          ┌──────────────────┐      ┌──────────────────┐      ┌──────────────────┐
          │ ResNet (ONNX RT) │      │ YOLOv8-OBB (ML)  │      │ YOLO11 e2e (ML)  │
          │  1200–1600 px    │      │     1024 px      │      │      640 px      │
          └────────┬─────────┘      └────────┬─────────┘      └────────┬─────────┘
                   │ boxes+skor              │ boxes+skor              │ boxes+skor
                   └──────────────┬──────────┴─────────────────────────┘
                                  ▼
                       ┌─────────────────────┐
                       │ MultiDetectorService│  ← paralel, urutan distabilkan
                       └──────────┬──────────┘
                                  │ AnalysisResult
                   ┌──────────────┴───────────────┐
                   ▼                              ▼
        btaCount / grade                    readings[] (semua model)
        HANYA dari gradingDetector          untuk kolom + kotak overlay
                   │                              │
                   ▼                              ▼
            SampleDraft.manualBTACount    SampleDraft.detectorCounts[kind]
            (bisa disunting analis)       (murni angka mesin, per model)
```

**Aturan yang tidak boleh dilanggar:** hanya `selection.gradingDetector` yang boleh menjadi
`btaCount` dan `grade`. Merata-ratakan model menghasilkan angka yang tidak pernah diproduksi
model mana pun.

---

## 2. Framing — satu-satunya sumber piksel

`Core/Services/FieldFraming.swift`

Semua model menerima **byte yang identik**. Ini bukan soal kerapian: kalau tiap service
memotong fotonya sendiri, selisih hitungan jadi campuran antara beda model dan beda framing,
dan tidak ada cara memisahkannya.

| Langkah | Alasan |
|---|---|
| Redraw tegak | Foto `AVCapturePhotoOutput` menyimpan rotasi di EXIF; `CGImage` telanjang membuangnya |
| Potong persegi terpusat | Preview `resizeAspectFill` = persegi ini, jadi kotak overlay ternormalisasi terhadapnya |

Potongan persegi tidak merugikan skala: ResNet mengubah ukuran ke sisi pendek 1200, dan frame
4:3 maupun potongan perseginya sama-sama menyentuh batas itu di sisi pendek.

---

## 3. Ketiga model

| | ResNet | YOLOv8-OBB | YOLO11 |
|---|---|---|---|
| Berkas | `BTADetector.onnx` 79 MB | `BTADetector.mlpackage` 22 MB | `BTADetectorV11.mlpackage` 9,3 MB |
| Runtime | ONNX Runtime 1.24.2 | CoreML + Vision | CoreML + Vision |
| Arsitektur | Faster R-CNN ResNet50-FPN | YOLOv8s-OBB | YOLO11 Detect, `end2end` |
| Input | 1200×1200 (min 1200 / maks 1600) | 1024×1024 | 640×640 |
| Output | `boxes/labels/scores`, NMS di dalam graf | `(1, 6, 21504)` mentah | `(1, 300, 6)` |
| Kotak | axis-aligned | **oriented** (punya sudut) | axis-aligned |
| NMS | di dalam graf ONNX | **ProbIoU, ditulis tangan** | **tidak ada — kepala one-to-one** |
| Ambang | 0,70 (terkalibrasi fold 4) | 0,25 (default training) | 0,25 (default ultralytics) |
| Kecepatan | ~0,6 s (M5 CPU) | milidetik | milidetik |

### Yang paling mudah salah

- **YOLO11 tidak boleh di-NMS.** `end2end: True` berarti kepalanya sudah one-to-one.
  Menjalankan NMS akan menghapus basil bertetangga yang sah.
- **YOLOv8-OBB wajib di-NMS sendiri.** Ekspornya mencatat `nms: False`, jadi Vision tidak bisa
  menghasilkan `VNRecognizedObjectObservation`; membacanya sebagai itu memberi array kosong dan
  **setiap slide dilaporkan Negatif tanpa error**.
- **ResNet tidak bisa ke CoreML.** Alur kontrolnya bergantung data (top-k proposal, panjang NMS
  bervariasi). `torch.jit.trace` membekukan hitungan satu sampel jadi konstanta dan
  mengembalikan angka itu untuk semua slide, diam-diam. Karena itu ONNX.
- **Hanya ambang 0,70 milik ResNet yang pernah dicari secara empiris.** Dua yang lain memakai
  default training. Sebagian selisih antar model adalah selisih ambang, bukan selisih model.

---

## 4. Akumulasi hitungan

`Core/Domain/Entities/SampleDraft.swift`

```
detectorCounts[.resnet] += bacaan ResNet     ← arsip per model, tidak pernah disunting
detectorCounts[.yolo]   += bacaan YOLOv8
detectorCounts[.yolo11] += bacaan YOLO11

manualBTACount          += bacaan gradingDetector   ← angka rekam medis, bisa disunting
countSource              = gradingDetector
```

Satu akumulator per model, bukan satu akumulator yang dilabeli ulang saat tampil. Dulu
berpindah model membuat kolom berganti nama sementara isinya milik model sebelumnya — dan
angka itu menentukan grade serta yang tersimpan ke `Sample`.

`reconcileCountSource(with:)` mengalihkan angka rekam medis saat model berganti, dan **membuang
penyesuaian manual ±** dengan sengaja: penyesuaian itu dibuat terhadap bacaan model lain atas
lapang lain. Fungsi ini tinggal di `SampleDraft`, bukan di `onChange` milik View — ia invarian
data, dan kalau ditaruh di View ia hanya berlaku selama layar itu tampil.

Bacaan yang `failure != nil` **tidak** masuk sebagai nol. Nol berarti "tidak melihat apa-apa";
gagal berarti "tidak sempat melihat".

---

## 5. Tampilan

- **Preview persegi, bukan lingkaran.** Persegi itu persis wilayah yang dianalisis. Masker
  lingkaran dulu menyembunyikan ~21% area yang dihitung.
- **Frame dibekukan setelah analisis** (`analyzedImage`). Kotak ternormalisasi terhadap piksel
  itu; di atas preview hidup ia menempel pada basil yang sudah bergerak. Ketuk untuk kembali
  ke live.
- **Kotak semua model digambar bersamaan**, satu `ForEach` datar dengan id `"YOLO11-3"`. Tiap
  model punya warna **dan** pola garis sendiri — warna saja tidak cukup untuk tiga kategori.
- **Baris `#if DEBUG`** di bawah tiap kolom menampilkan `N kotak · T detik`, memisahkan "model
  tidak menemukan apa-apa" dari "penggambarannya rusak". Tidak ikut build rilis.

---

## 6. Sumber input

`FieldSource` — `.camera` atau `.gallery`, **menetap**. Slide yang dibaca separuh dari okuler
dan separuh dari foto impor adalah dua akuisisi berbeda yang digabung jadi satu hitungan, dan
tidak ada apa pun di hilir yang menunjukkan itu terjadi. Kamera dimatikan saat mode galeri.

---

## 7. Diagnosis di perangkat

`Core/Services/Diagnostics.swift` — `Diag` menulis ke `os.Logger` **dan** stderr saat Debug,
karena `devicectl … --console` hanya merelai stdout/stderr. Instrumentasi yang hanya memakai
`Logger` menghasilkan console kosong dan terbaca seperti "kodenya tidak pernah jalan".

```bash
xcrun devicectl device process launch --console --device <id> com.eganugraha.Bacilab
```

`log collect` dari perangkat memerlukan root.

---

## 8. Yang belum dikerjakan

1. **Tidak ada validasi klinis sama sekali.** Metrik ResNet (AP50 0,835 / MAE 1,32) berasal dari
   fold terbaik dari lima, dipilih berdasarkan metrik validasinya sendiri; rata-rata 5 fold
   (AP50 0,72 / MAE 1,81) lebih jujur.
2. **Simulator tidak bisa menguji YOLO11.** Ia menilai seluruh probe sintetis di bawah 0,25 dan
   mengembalikan 0 — verdict jujur, bukan cacat (`YOLO11RawTensorTests` memastikan decoder
   sepakat dengan tensor mentah baris per baris). Hanya slide asli yang bisa menilainya.
3. **Ambang belum disamakan.** Membandingkan 0,25 lawan 0,70 adalah membandingkan model
   *beserta* ambangnya.
4. **Kecepatan di perangkat belum diukur**, baru diekstrapolasi dari M5 CPU.
5. **Belum ada yang di-commit.** `BTADetector.onnx` 79 MB masih untracked; git-lfs belum
   terpasang dan batas keras GitHub 100 MB per berkas.
