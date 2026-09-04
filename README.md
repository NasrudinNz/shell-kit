# PSTools — Personal Productivity CLI for PowerShell

Satu file, banyak perintah. PSTools adalah kumpulan fungsi PowerShell pribadi yang digabung menjadi satu `PSTools.ps1`, siap di-dot-source dari `$PROFILE` agar semua perintahnya bisa dipakai dari folder manapun di terminal.

Semua data disimpan di folder tetap **`$HOME\PSTools\data\`** (bukan relatif ke folder yang sedang aktif), jadi kamu bisa memakai perintah ini dari mana saja tanpa khawatir datanya tersebar.

## Fitur

| Perintah   | Fungsi                                                        |
|------------|---------------------------------------------------------------|
| `pstools`  | Tampilkan daftar semua perintah (menu utama)                  |
| `todo`     | Checklist task bergaya Markdown (mendukung multi-file)       |
| `note`     | Catatan bebas dengan timestamp (mendukung multi-file)         |
| `bm`       | Bookmark direktori, lompat cepat antar folder                 |
| `snippet`  | Simpan & ambil potongan kode (diambil dari clipboard)         |
| `pomo`     | Pomodoro / timer fokus sederhana                              |
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
Multi-file: tambahkan `- namafile` di akhir perintah untuk memakai file terpisah (default: `notes.md`).

```powershell
todo add "Belajar PowerShell"          # Tambah task
todo list                              # Lihat semua task
todo done 1                            # Tandai task #1 selesai
todo undone 1                          # Kembalikan task #1
todo remove 1                          # Hapus task #1

# Pakai file terpisah
todo add "Siapkan demo" - proyek
todo list - proyek
todo done 1 - proyek
```
- Data: `data\notes.md` (atau `data\proyek.md`)

### 📝 Note — Catatan Bebas dengan Timestamp
Multi-file juga, default: `quicknotes.md`.

```powershell
note add "judul" "isi catatan"         # Tambah note baru
note list                              # Lihat daftar note
note view 1                            # Lihat isi note #1
note rm 1                              # Hapus note #1

# Pakai file terpisah
note add "Ide rapat" "Catat target Q3" - rapat
note list - rapat
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
```
- Data: `data\snippets.md`

### ⏱️ Pomo — Timer Pomodoro
```powershell
pomo start [menit]   # Fokus, default 25 menit
pomo break [menit]   # Istirahat, default 5 menit
pomo 15              # Fokus langsung 15 menit
```
- Tekan `Ctrl+C` untuk berhenti lebih awal.

### 🔧 Utilitas Lainnya

```powershell
trans "Halo"                    # id → en (default)
trans "Halo" en id              # en → id
trans "Halo" id ja              # id → jepang

uuid            # Generate 1 GUID baru
```

---

## Struktur Folder

```
PSTools/
├── PSTools.ps1     # Semua fungsi & perintah
├── README.md       # Dokumentasi ini
└── data/           # Data pribadi (TIDAK ikut di-upload, di-.gitignore)
    ├── notes.md
    ├── quicknotes.md
    ├── bookmarks.md
    ├── snippets.md
    └── ...
```

## Catatan Keamanan

- Folder `data\` berisi data **pribadi** kamu dan sudah diabaikan via `.gitignore` — jangan paksa di-upload ke repo public.
- Fungsi yang memuat **kredensial / informasi sensitif** (misal `db` dan `ssh@`) **tidak** disertakan di `PSTools.ps1` ini. Sebaiknya simpan fungsi-fungsi semacam itu langsung di `$PROFILE` masing-masing agar tidak ikut ter-upload ke repo public.

## Lisensi

