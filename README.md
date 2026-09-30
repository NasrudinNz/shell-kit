# PSTools — Personal Productivity CLI for PowerShell

Satu file, banyak perintah. PSTools adalah kumpulan fungsi PowerShell pribadi yang digabung menjadi satu `PSTools.ps1`, siap di-dot-source dari `$PROFILE` agar semua perintahnya bisa dipakai dari folder manapun di terminal.

Semua data disimpan di folder tetap **`$HOME\PSTools\data\`** (bukan relatif ke folder yang sedang aktif), jadi kamu bisa memakai perintah ini dari mana saja tanpa khawatir datanya tersebar.

## Fitur

| Perintah   | Fungsi                                                        |
|------------|---------------------------------------------------------------|
| `pstools`  | Tampilkan daftar semua perintah (menu utama)                  |
| `todo`     | Checklist task bergaya Markdown (nested + judul, multi-file)   |
| `note`     | Catatan bebas dengan timestamp (mendukung multi-file)         |
| `bm`       | Bookmark direktori, lompat cepat antar folder                 |
| `snippet`  | Simpan & ambil potongan kode (diambil dari clipboard)         |
| `pomo`     | Pomodoro + time tracking aktivitas TODO                       |
| `trans`    | Terjemahan cepat via Google Translate (default id → en)       |
| `uuid`     | Generate GUID baru                                            |

## Persyaratan

- Windows dengan **PowerShell 5.1+** atau **PowerShell 7+** (disarankan)
- Tidak ada dependency / modul tambahan yang perlu di-install

## Instalasi

1. **Clone / simpan repo** — letakkan folder `PSTools` di `$HOME` (misal `C:\Users\<kamu>\PSTools`).

2. **Dot-source dari `$PROFILE`** — buka profile PowerShell:
   ```powershell
   notepad $PROFILE
   ```
   Tambahkan baris berikut:
   ```powershell
   . "$HOME\PSTools\PSTools.ps1"
   ```
   Simpan, lalu reload profile agar aktif:
   ```powershell
   . $PROFILE
   ```

3. **Coba** — ketik `pstools` untuk melihat menu utama.

> Folder `data\` dibuat otomatis saat pertama kali `PSTools.ps1` di-load.

---

## Petunjuk Penggunaan

### 📋 Menu utama
```powershell
pstools
```
Menampilkan ringkasan semua perintah yang tersedia.

### ✅ Todo — Checklist Task
Multi-file: nama file adalah **argumen terakhir** dari perintah (tanpa pemisah `-`), default: `notes`.

```powershell
todo add "Belajar PowerShell"            # Tambah task
todo add-child 1 "Baca dokumentasi"      # Tambah subtask di bawah task #1
todo list                                # Lihat task + progress file aktif
todo list -a                             # Ringkasan semua file TODO + total gabungan
todo files                               # Ringkasan + isi semua file TODO
todo done 1                              # Tandai task #1 selesai
todo done 1.2                            # Tandai subtask #1.2 selesai
todo undone 1                            # Kembalikan task #1 (berserta semua child)
todo remove 1                            # Hapus task #1 (berserta semua child)
todo open                                # Edit file TODO aktif manual di editor
todo help                                # Help bawaan

# Pakai file terpisah (nama file di akhir)
todo add "Siapkan demo" proyek
todo list proyek
todo done 1 proyek
```

- Nested checklist didukung: penomoran bertingkat `1`, `1.1`, `1.1.2` mengikuti indentasi di file Markdown.
- `todo done` / `undone` / `remove` pada sebuah parent juga impacting seluruh child-nya, dan meminta konfirmasi (`y` / `yes` / `ya`) bila parent punya child.
- `todo done` menandai parent sebagai selesai otomatis bila semua child-nya sudah selesai.
- `todo list` menampilkan progress bar + persentase; `todo list -a` mengelompokkan file menjadi `TODO BERJALAN` / `TODO SELESAI (100%)` plus total gabungan, dan mencantumkan file kosong terpisah.
- Emphasys Markdown (`**tebal**`, `*miring*`, `***tebal miring***`) dirender di terminal tanpa mengubah isi file.
- File TODO terakhir yang dipakai disimpan di `$Global:PSToolsLastTodoFile` (default `notes`).
- Data: `data\<namafile>.md`
- Editor `todo open` bisa diganti: `$Global:PSToolsTodoEditor = "kode"` (default `vim`)

#### 🏷️ Judul file TODO
Setiap file TODO boleh punya judul, disimpan sebagai heading `# judul` di baris paling atas file dan ditampilkan di `todo list` / `todo files` / `todo list -a`.

```powershell
todo add "Belajar PowerShell" notes "PowerShell Learning"   # posisional
todo add "Belajar PowerShell" notes -t "PowerShell Learning" # flag -t / --title
todo add "Task baru" proyek --title="Proyek Klien"           # satu token

todo title notes                                            # lihat judul
todo title notes "PowerShell Learning 2026"                  # set / ganti judul
```

- Judul otomatis dibuat saat pertama kali diberikan, dan diganti (bukan diduplikasi) kalau sudah ada.
- Bentuk **posisional** hanya aktif untuk `add` / `add-child` dan hanya bila jumlah argumen tepat (teks task satu token). Kalau teks task panjang dan tidak diapit tanda kutip, pakai flag `-t "judul"` supaya tidak salah dipotong menjadi nama file.
- Nama file pada bentuk posisional harus tanpa spasi dan tidak diawali `-`.

### 📝 Note — Catatan Bebas dengan Timestamp
Multi-file juga (nama file di akhir), default: `quicknotes.md`.

```powershell
note add "judul" "isi catatan"         # Tambah note baru
note list                              # Lihat daftar note
note view 1                            # Lihat isi note #1
note rm 1                              # Hapus note #1
note help

# Pakai file terpisah
note add "Ide rapat" "Catat target Q3" rapat
note list rapat
note view 1 rapat
note rm 1 rapat
```
- Menambah note dengan judul yang sama akan **menggabungkan** isinya (dengan timestamp baru), bukan membuat duplikat.
- Data: `data\quicknotes.md`

### 📌 BM — Bookmark Direktori
Lompat cepat ke folder yang sering dikunjungi.

```powershell
bm add proyek                          # Simpan folder saat ini sebagai "proyek"
bm add doks C:\Users\kamu\Documents   # Simpan path tertentu
bm go proyek                           # Pindah ke folder yang di-bookmark
bm list                                # Lihat semua bookmark
bm rm proyek                           # Hapus bookmark
bm help
```
- Data: `data\bookmarks.md`

### 💾 Snippet — Pengelola Potongan Kode
Simpan kode dari clipboard & ambil lagi saat dibutuhkan.

```powershell
# 1. Copy dulu kode yang mau disimpan (Ctrl+C)
# 2. Simpan dengan nama & bahasa:
snippet save myfunction python         # Simpan isi clipboard
snippet list                           # Lihat semua snippet
snippet get myfunction                 # Tampilkan + salin ke clipboard
snippet rm myfunction                  # Hapus snippet
snippet help
```
- `snippet save` dengan nama yang sama akan menimpa snippet lama.
- Data: `data\snippets.md`

### ⏱️ Pomo — Pomodoro + Time Tracking TODO
Pomo **tidak memblokir** PowerShell. Kamu tetap bebas menjalankan perintah lain, dan aktivitas TODO otomatis dicatat per task.

```powershell
pomo start     # Mulai sesi fokus
pomo status    # Sesi aktif: waktu mulai, elapsed, task aktif
pomo end       # Tutup sesi + tampilkan statistik hari ini
pomo stats     # Statistik POMO hari ini saja
pomo reset     # Hapus seluruh histori (perlu konfirmasi YES)
pomo help
```

Contoh alur:
```powershell
pomo start
todo list notes
todo done 1 notes          # task ini jadi task aktif
todo add-child 1 "rapikan" notes
todo done 1.1 notes
pomo end
```

- Setiap operasi `todo add` / `add-child` / `done` / `undone` saat POMO aktif menutup segment task sebelumnya dan membuka segment baru, sehingga waktu per task terakumulasi (per task + per segment).
- Task yang dihapus lewat `todo remove` akan menutup segment-nya terlebih dulu.
- `pomo end` menyimpan sesi ke histori lalu menampilkan statistik hari ini: durasi per task, total focus, dan jumlah sesi.
- Data: `data\pomodoro.json` (state sesi aktif) & `data\pomodoro-history.json` (histori).

### 🔧 Utilitas Lainnya

```powershell
trans "Halo"                    # id → en (default)
trans "Halo" en id              # en → id
trans "Halo" id ja              # id → Jepang
trans help

uuid                            # Generate 1 GUID baru
uuid help
```

> `trans` memakai endpoint publik Google Translate, jadi butuh koneksi internet.

---

## Konfigurasi

Semua konfigurasi memakai variabel global, bisa diubah di `$PROFILE` **setelah** baris dot-source.

| Variabel                        | Default              | Keterangan                                  |
|---------------------------------|----------------------|---------------------------------------------|
| `$Global:PSToolsDataDir`        | `$HOME\PSTools\data` | Lokasi seluruh data PSTools                 |
| `$Global:PSToolsLastTodoFile`   | `notes`              | File TODO terakhir yang dipakai             |
| `$Global:PSToolsTodoEditor`     | `vim`                | Editor untuk `todo open`                    |
| `$Global:PSToolsPomoStateFile`  | `data\pomodoro.json` | State sesi POMO yang sedang aktif           |
| `$Global:PSToolsPomoHistoryFile`| `data\pomodoro-history.json` | Histori sesi POMO                 |

---

## Struktur Folder

```
PSTools/
├── PSTools.ps1     # Semua fungsi & perintah
├── README.md       # Dokumentasi ini
└── data/           # Data pribadi (TIDAK ikut di-upload, di-.gitignore)
    ├── notes.md            # file TODO default (bisa diganti, diawali # judul)
    ├── quicknotes.md       # file NOTE default (bisa diganti)
    ├── bookmarks.md
    ├── snippets.md
    ├── pomodoro.json       # state sesi POMO aktif
    ├── pomodoro-history.json
    └── ...
```

## Catatan Keamanan

- Folder `data\` berisi data **pribadi** kamu dan sudah diabaikan via `.gitignore` — jangan paksa di-upload ke repo public.
- Fungsi yang memuat **kredensial / informasi sensitif** (misal `db` dan `ssh@`) **tidak** disertakan di `PSTools.ps1` ini. Sebaiknya simpan fungsi-fungsi semacam itu langsung di `$PROFILE` masing-masing agar tidak ikut ter-upload ke repo public.

## Lisensi

