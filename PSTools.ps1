# =========================================================
#  PSTools.ps1 — Personal Productivity CLI for PowerShell
#  Lokasi   : $HOME\PSTools\PSTools.ps1
#  Data     : $HOME\PSTools\data\
#
#  Cara pakai: dot-source file ini dari $PROFILE, contoh tambahkan
#  baris berikut di $PROFILE:
#
#      . "$HOME\PSTools\PSTools.ps1"
#
#  Commands:
#    todo      -> checklist tasks (multi-file via " - namafile")
#    note      -> catatan bebas dgn timestamp (multi-file juga)
#    bm        -> bookmark direktori, lompat cepat pakai nama
#    snippet   -> simpan & ambil potongan kode
#    pomo      -> pomodoro timer sederhana
#    trans     -> google translate cepat
#    uuid      -> generate GUID baru
#    pstools help -> lihat semua command
# =========================================================

$Global:PSToolsDataDir = Join-Path $HOME "PSTools\data"
if (-not (Test-Path $Global:PSToolsDataDir)) {
    New-Item -Path $Global:PSToolsDataDir -ItemType Directory -Force | Out-Null
}

# File TODO terakhir yang ditampilkan/digunakan
$Global:PSToolsLastTodoFile = "notes"

function Join-ArgsFrom {
    param($Arr, $StartIndex)
    if ($Arr.Count -le $StartIndex) { return "" }
    return ($Arr[$StartIndex..($Arr.Count - 1)] -join " ")
}

function pstools {
    Write-Host ""
    Write-Host "=== PSTools — Personal Productivity CLI ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "todo      checklist tasks           (todo help)"
    Write-Host "note      catatan bebas + timestamp  (note help)"
    Write-Host "bm        bookmark direktori         (bm help)"
    Write-Host "snippet   simpan/ambil kode          (snippet help)"
    Write-Host "pomo      pomodoro timer             (pomo help)"
    Write-Host ""
    Write-Host "trans     google translate cepat     (trans help)"
    Write-Host "uuid      generate GUID baru         (uuid help)"
    Write-Host ""
    Write-Host "Semua data tersimpan di: $Global:PSToolsDataDir"
    Write-Host ""
}

# =========================================================
#  TODO  (checklist tasks, multi-file)
# =========================================================

function todo {
    param(
        [Parameter(Position=0)]
        [string]$Command,

        [Parameter(Position=1, ValueFromRemainingArguments=$true)]
        [string[]]$Arguments
    )

    # Gunakan file TODO terakhir yang ditampilkan/digunakan
    $FileName = $Global:PSToolsLastTodoFile

    $dashIndex = -1
    if ($Arguments.Count -gt 0) {
        for ($i = 0; $i -lt $Arguments.Count; $i++) {
            if ($Arguments[$i] -eq "-") {
                $dashIndex = $i
                break
            }
        }
    }

    # Jika ada "- namafile", gunakan file tersebut
    if ($dashIndex -ge 0 -and ($dashIndex + 1) -lt $Arguments.Count) {
        $FileName = $Arguments[$dashIndex + 1]
        if ($dashIndex -gt 0) {
            $Arguments = $Arguments[0..($dashIndex - 1)]
        } else {
            $Arguments = @()
        }
    }

    # Simpan sebagai file TODO terakhir yang aktif
    $Global:PSToolsLastTodoFile = $FileName

    $FileName = $FileName -replace '\.md$', ''
    $file = Join-Path $Global:PSToolsDataDir "$FileName.md"

    if ([string]::IsNullOrWhiteSpace($Command) -or $Command -eq "help") {
        Write-Host ""
        Write-Host "TODO - Markdown Task Manager"
        Write-Host "================================"
        Write-Host ""
        Write-Host 'USAGE:'
        Write-Host '  todo add "task" - namafile'
        Write-Host '  todo list - namafile'
        Write-Host '  todo done 1 - namafile'
        Write-Host '  todo undone 1 - namafile'
        Write-Host '  todo remove 1 - namafile'
        Write-Host ""
        Write-Host "Data: $Global:PSToolsDataDir\<namafile>.md"
        Write-Host ""
        return
    }

    if (!(Test-Path $file)) {
        New-Item -Path $file -ItemType File -Force | Out-Null
    }

    switch ($Command) {

        "add" {
            $Text = ($Arguments -join " ").Trim()
            if ([string]::IsNullOrWhiteSpace($Text)) {
                Write-Host ""
                Write-Host 'Usage: todo add "task" - namafile'
                Write-Host ""
                return
            }
            Add-Content -Path $file -Value "- [ ] $Text"
            Write-Host ""
            Write-Host "Ditambahkan: $Text" -ForegroundColor Green
            Write-Host "File: $FileName.md"

            # Tampilkan kembali daftar TODO aktif
            todo list - $FileName
        }

        "list" {
            $lines = @(Get-Content $file)
            Write-Host ""
            Write-Host "$FileName.md"
            Write-Host "================================"
            if ($lines.Count -eq 0) {
                Write-Host "Belum ada task."
                Write-Host ""
                return
            }
            $i = 1
            foreach ($line in $lines) {
                if ($line -match '^- \[ \] (.*)$') {
                    Write-Host "$i. [ ] $($Matches[1])"
                } elseif ($line -match '^- \[x\] (.*)$') {
                    Write-Host "$i. [x] $($Matches[1])" -ForegroundColor Green
                } else {
                    Write-Host "$i.    $line"
                }
                $i++
            }
            Write-Host ""
        }

        "done" {
            if ($Arguments.Count -eq 0) {
                Write-Host "Usage: todo done <number> - namafile"; return
            }
            $number = 0
            if (![int]::TryParse($Arguments[0], [ref]$number)) {
                Write-Host "Nomor tidak valid."; return
            }
            $lines = [System.Collections.Generic.List[string]](@(Get-Content $file))
            if ($number -lt 1 -or $number -gt $lines.Count) {
                Write-Host "Task tidak ditemukan."; return
            }
            if ($lines[$number - 1] -match '^- \[ \]') {
                $lines[$number - 1] = $lines[$number - 1] -replace '^- \[ \]', '- [x]'
                $lines | Set-Content $file
                Write-Host "Task $number selesai." -ForegroundColor Green
                todo list - $FileName
            } else {
                Write-Host "Task sudah selesai atau bukan TODO."
            }
        }

        "undone" {
            if ($Arguments.Count -eq 0) {
                Write-Host "Usage: todo undone <number> - namafile"; return
            }
            $number = 0
            if (![int]::TryParse($Arguments[0], [ref]$number)) {
                Write-Host "Nomor tidak valid."; return
            }
            $lines = [System.Collections.Generic.List[string]](@(Get-Content $file))
            if ($number -lt 1 -or $number -gt $lines.Count) {
                Write-Host "Task tidak ditemukan."; return
            }
            if ($lines[$number - 1] -match '^- \[x\]') {
                $lines[$number - 1] = $lines[$number - 1] -replace '^- \[x\]', '- [ ]'
                $lines | Set-Content $file
                Write-Host "Task $number dikembalikan." -ForegroundColor Yellow
                todo list - $FileName
            }
        }

        "remove" {
            if ($Arguments.Count -eq 0) {
                Write-Host "Usage: todo remove <number> - namafile"; return
            }
            $number = 0
            if (![int]::TryParse($Arguments[0], [ref]$number)) {
                Write-Host "Nomor tidak valid."; return
            }
            $lines = [System.Collections.Generic.List[string]](@(Get-Content $file))
            if ($number -lt 1 -or $number -gt $lines.Count) {
                Write-Host "Task tidak ditemukan."; return
            }
            $task = $lines[$number - 1]
            $lines.RemoveAt($number - 1)
            $lines | Set-Content $file
            Write-Host "Dihapus: $task" -ForegroundColor Green
            todo list - $FileName
        }

        default {
            Write-Host "Unknown command: $Command. Run 'todo help'."
        }
    }
}

# =========================================================
#  NOTE  (catatan bebas + timestamp, multi-file, terpisah dari todo)
# =========================================================

function note {
    param(
        [Parameter(Position=0)]
        [string]$Command,

        [Parameter(Position=1, ValueFromRemainingArguments=$true)]
        [string[]]$Arguments
    )

    $FileName = "quicknotes"

    if ($Arguments.Count -gt 0) {
        $dashIndex = -1
        for ($i = 0; $i -lt $Arguments.Count; $i++) {
            if ($Arguments[$i] -eq "-") { $dashIndex = $i; break }
        }
        if ($dashIndex -ge 0 -and ($dashIndex + 1) -lt $Arguments.Count) {
            $FileName = $Arguments[$dashIndex + 1]
            $Arguments = if ($dashIndex -gt 0) { $Arguments[0..($dashIndex - 1)] } else { @() }
        }
    }

    $FileName = $FileName -replace '\.md$', ''
    $file = Join-Path $Global:PSToolsDataDir "$FileName.md"

    if ([string]::IsNullOrWhiteSpace($Command) -or $Command -eq "help") {
        Write-Host ""
        Write-Host "NOTE - Catatan bebas dengan timestamp"
        Write-Host "================================"
        Write-Host 'todo add "task"' -ForegroundColor DarkGray
        Write-Host 'note add "judul" "isi catatan" - namafile'
        Write-Host 'note list - namafile'
        Write-Host 'note view 1 - namafile'
        Write-Host 'note rm 1 - namafile'
        Write-Host ""
        Write-Host "Default file: quicknotes.md"
        Write-Host ""
        return
    }

    if (!(Test-Path $file)) {
        Set-Content -Path $file -Value "# Notes`n" -Encoding UTF8
    }

    function Get-NoteEntries($Path) {
        $raw = Get-Content -Path $Path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
        $blocks = $raw -split "(?m)^---\s*$"
        $notes = @()
        foreach ($b in $blocks) {
            $t = $b.Trim()
            if ($t -match '(?s)## \[(.+?)\]\s+(.+?)\r?\n(.*)$') {
                $notes += [PSCustomObject]@{
                    Timestamp = $matches[1]; Title = $matches[2]; Content = $matches[3].Trim()
                }
            }
        }
        return @($notes)
    }

    function Save-NoteEntries($Path, $Notes) {
        $content = @("# Notes", "")
        foreach ($n in $Notes) {
            $content += "## [$($n.Timestamp)] $($n.Title)"
            $content += $n.Content
            $content += ""
            $content += "---"
            $content += ""
        }
        Set-Content -Path $Path -Value $content -Encoding UTF8
    }

    switch ($Command) {

        "add" {
            if ($Arguments.Count -eq 0 -or [string]::IsNullOrWhiteSpace($Arguments[0])) {
                Write-Host 'Usage: note add "judul" "isi" - namafile'; return
            }
            $title = $Arguments[0]
            $body  = Join-ArgsFrom $Arguments 1
            $notes = @(Get-NoteEntries $file)
            $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

            $existingIdx = -1
            for ($i = 0; $i -lt $notes.Count; $i++) {
                if ($notes[$i].Title.Trim().ToLower() -eq $title.Trim().ToLower()) {
                    $existingIdx = $i
                    break
                }
            }

            if ($existingIdx -ge 0) {
                $notes[$existingIdx].Content = "$($notes[$existingIdx].Content)`n`n**[$ts]** $body"
                Save-NoteEntries $file $notes
                Write-Host "Note '$title' digabung ke entry yang sudah ada." -ForegroundColor Green
                Write-Host "File: $FileName.md"
            } else {
                $notes += [PSCustomObject]@{ Timestamp = $ts; Title = $title; Content = "**[$ts]** $body" }
                Save-NoteEntries $file $notes
                Write-Host "Note ditambahkan: $title" -ForegroundColor Green
                Write-Host "File: $FileName.md"
            }
        }

        "list" {
            $notes = @(Get-NoteEntries $file)
            if ($notes.Count -eq 0) { Write-Host "Belum ada note."; return }
            Write-Host ""
            Write-Host "$FileName.md"
            Write-Host "================================"
            for ($i = 0; $i -lt $notes.Count; $i++) {
                Write-Host ("{0}. [{1}] {2}" -f ($i+1), $notes[$i].Timestamp, $notes[$i].Title)
            }
            Write-Host ""
        }

        "view" {
            if ($Arguments.Count -eq 0) { Write-Host "Usage: note view <number> - namafile"; return }
            $notes = @(Get-NoteEntries $file)
            $idx = [int]$Arguments[0] - 1
            if ($idx -lt 0 -or $idx -ge $notes.Count) { Write-Host "Nomor tidak valid."; return }
            Write-Host ""
            Write-Host "=== $($notes[$idx].Title) ===" -ForegroundColor Cyan
            Write-Host ""

            $contentLines = $notes[$idx].Content -split "`r?`n"
            foreach ($line in $contentLines) {
                if ($line -match '^\*\*\[(.+?)\]\*\*\s*(.*)$') {
                    Write-Host -NoNewline "[$($matches[1])] " -ForegroundColor Cyan
                    Write-Host $matches[2] -ForegroundColor White
                }
                elseif ([string]::IsNullOrWhiteSpace($line)) {
                    Write-Host ""
                }
                else {
                    # baris lama tanpa prefix timestamp (data sebelum fitur ini ada)
                    Write-Host -NoNewline "[$($notes[$idx].Timestamp)] " -ForegroundColor Cyan
                    Write-Host $line -ForegroundColor White
                }
            }
            Write-Host ""
        }

        "rm" {
            if ($Arguments.Count -eq 0) { Write-Host "Usage: note rm <number> - namafile"; return }
            $notes = @(Get-NoteEntries $file)
            $idx = [int]$Arguments[0] - 1
            if ($idx -lt 0 -or $idx -ge $notes.Count) { Write-Host "Nomor tidak valid."; return }
            $removed = $notes[$idx].Title
            $newNotes = @()
            for ($i = 0; $i -lt $notes.Count; $i++) { if ($i -ne $idx) { $newNotes += $notes[$i] } }
            Save-NoteEntries $file $newNotes
            Write-Host "Note dihapus: $removed" -ForegroundColor Green
        }

        default {
            Write-Host "Unknown command: $Command. Run 'note help'."
        }
    }
}

# =========================================================
#  BM  (bookmark direktori — lompat cepat dari folder manapun)
# =========================================================

function bm {
    param(
        [Parameter(Position=0)] [string]$Command,
        [Parameter(Position=1, ValueFromRemainingArguments=$true)] [string[]]$Arguments
    )

    $file = Join-Path $Global:PSToolsDataDir "bookmarks.md"
    if (!(Test-Path $file)) { Set-Content -Path $file -Value "# Bookmarks`n" -Encoding UTF8 }

    function Get-Bookmarks {
        $lines = Get-Content -Path $file -Encoding UTF8
        $bms = @{}
        foreach ($l in $lines) {
            if ($l -match '^- (\S+) = (.+)$') { $bms[$matches[1]] = $matches[2] }
        }
        return $bms
    }

    function Save-Bookmarks($bms) {
        $content = @("# Bookmarks", "")
        foreach ($k in $bms.Keys | Sort-Object) { $content += "- $k = $($bms[$k])" }
        Set-Content -Path $file -Value $content -Encoding UTF8
    }

    if ([string]::IsNullOrWhiteSpace($Command) -or $Command -eq "help") {
        Write-Host ""
        Write-Host "BM - Bookmark Direktori"
        Write-Host "================================"
        Write-Host "  bm add <nama>            simpan folder saat ini"
        Write-Host "  bm add <nama> <path>     simpan path tertentu"
        Write-Host "  bm go <nama>             pindah ke folder tsb"
        Write-Host "  bm list                  lihat semua bookmark"
        Write-Host "  bm rm <nama>             hapus bookmark"
        Write-Host ""
        return
    }

    $bms = Get-Bookmarks

    switch ($Command) {
        "add" {
            if ($Arguments.Count -eq 0) { Write-Host "Usage: bm add <nama> [path]"; return }
            $name = $Arguments[0]
            $path = if ($Arguments.Count -gt 1) { Join-ArgsFrom $Arguments 1 } else { (Get-Location).Path }
            $bms[$name] = $path
            Save-Bookmarks $bms
            Write-Host "Bookmark '$name' -> $path" -ForegroundColor Green
        }
        "go" {
            if ($Arguments.Count -eq 0) { Write-Host "Usage: bm go <nama>"; return }
            $name = $Arguments[0]
            if ($bms.ContainsKey($name)) {
                if (Test-Path $bms[$name]) {
                    Set-Location $bms[$name]
                } else {
                    Write-Host "Path sudah tidak ada: $($bms[$name])" -ForegroundColor Red
                }
            } else {
                Write-Host "Bookmark '$name' tidak ditemukan." -ForegroundColor Red
            }
        }
        "list" {
            if ($bms.Count -eq 0) { Write-Host "Belum ada bookmark."; return }
            Write-Host ""
            Write-Host "=== BOOKMARKS ==="
            foreach ($k in $bms.Keys | Sort-Object) { Write-Host "  $k -> $($bms[$k])" }
            Write-Host ""
        }
        "rm" {
            if ($Arguments.Count -eq 0) { Write-Host "Usage: bm rm <nama>"; return }
            $name = $Arguments[0]
            if ($bms.ContainsKey($name)) {
                $bms.Remove($name)
                Save-Bookmarks $bms
                Write-Host "Bookmark '$name' dihapus." -ForegroundColor Green
            } else {
                Write-Host "Bookmark '$name' tidak ditemukan." -ForegroundColor Red
            }
        }
        default { Write-Host "Unknown command: $Command. Run 'bm help'." }
    }
}

# =========================================================
#  SNIPPET  (simpan & ambil potongan kode, isi dari clipboard)
# =========================================================

function snippet {
    param(
        [Parameter(Position=0)] [string]$Command,
        [Parameter(Position=1, ValueFromRemainingArguments=$true)] [string[]]$Arguments
    )

    $file = Join-Path $Global:PSToolsDataDir "snippets.md"
    if (!(Test-Path $file)) { Set-Content -Path $file -Value "# Snippets`n" -Encoding UTF8 }

    function Get-Snippets {
        $raw = Get-Content -Path $file -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
        $blocks = $raw -split "(?m)^---\s*$"
        $items = @()
        foreach ($b in $blocks) {
            $t = $b.Trim()
            if ($t -match '(?s)## (\S+) \((.+?)\)\r?\n```.*?\r?\n(.*?)\r?\n```') {
                $items += [PSCustomObject]@{ Name = $matches[1]; Lang = $matches[2]; Code = $matches[3] }
            }
        }
        return @($items)
    }

    function Save-Snippets($items) {
        $content = @("# Snippets", "")
        foreach ($s in $items) {
            $content += "## $($s.Name) ($($s.Lang))"
            $content += '```' + $s.Lang
            $content += $s.Code
            $content += '```'
            $content += ""
            $content += "---"
            $content += ""
        }
        Set-Content -Path $file -Value $content -Encoding UTF8
    }

    if ([string]::IsNullOrWhiteSpace($Command) -or $Command -eq "help") {
        Write-Host ""
        Write-Host "SNIPPET - Code Snippet Manager"
        Write-Host "================================"
        Write-Host "  1. Copy kode yang mau disimpan (Ctrl+C)"
        Write-Host "  2. snippet save <nama> <bahasa>   -> simpan isi clipboard"
        Write-Host "  snippet list                       lihat semua snippet"
        Write-Host "  snippet get <nama>                 tampilkan + copy ke clipboard"
        Write-Host "  snippet rm <nama>                  hapus snippet"
        Write-Host ""
        return
    }

    $items = @(Get-Snippets)

    switch ($Command) {
        "save" {
            if ($Arguments.Count -lt 2) { Write-Host "Usage: snippet save <nama> <bahasa>"; return }
            $name = $Arguments[0]
            $lang = $Arguments[1]
            $code = Get-Clipboard -Raw
            if ([string]::IsNullOrWhiteSpace($code)) {
                Write-Host "Clipboard kosong, copy kode dulu sebelum save." -ForegroundColor Red
                return
            }
            $items = @($items | Where-Object { $_.Name -ne $name })
            $items += [PSCustomObject]@{ Name = $name; Lang = $lang; Code = $code.TrimEnd() }
            Save-Snippets $items
            Write-Host "Snippet '$name' ($lang) disimpan." -ForegroundColor Green
        }
        "list" {
            if ($items.Count -eq 0) { Write-Host "Belum ada snippet."; return }
            Write-Host ""
            Write-Host "=== SNIPPETS ==="
            foreach ($s in $items) { Write-Host "  $($s.Name)  [$($s.Lang)]" }
            Write-Host ""
        }
        "get" {
            if ($Arguments.Count -eq 0) { Write-Host "Usage: snippet get <nama>"; return }
            $found = $items | Where-Object { $_.Name -eq $Arguments[0] }
            if (-not $found) { Write-Host "Snippet '$($Arguments[0])' tidak ditemukan." -ForegroundColor Red; return }
            Write-Host ""
            Write-Host "=== $($found.Name) ($($found.Lang)) ===" -ForegroundColor Cyan
            Write-Host $found.Code
            Write-Host ""
            $found.Code | Set-Clipboard
            Write-Host "(disalin ke clipboard)" -ForegroundColor DarkGray
        }
        "rm" {
            if ($Arguments.Count -eq 0) { Write-Host "Usage: snippet rm <nama>"; return }
            $exists = $items | Where-Object { $_.Name -eq $Arguments[0] }
            if (-not $exists) { Write-Host "Snippet '$($Arguments[0])' tidak ditemukan." -ForegroundColor Red; return }
            $items = @($items | Where-Object { $_.Name -ne $Arguments[0] })
            Save-Snippets $items
            Write-Host "Snippet '$($Arguments[0])' dihapus." -ForegroundColor Green
        }
        default { Write-Host "Unknown command: $Command. Run 'snippet help'." }
    }
}

# =========================================================
#  POMO  (pomodoro timer sederhana, tanpa dependency tambahan)
# =========================================================

function pomo {
    param(
        [Parameter(Position=0)] [string]$Command,
        [Parameter(Position=1)] [int]$Minutes
    )

    if ($Command -eq "help") {
        Write-Host ""
        Write-Host "POMO - Pomodoro Timer"
        Write-Host "================================"
        Write-Host "  pomo start [menit]   default 25 menit (fokus)"
        Write-Host "  pomo break [menit]   default 5 menit (istirahat)"
        Write-Host "  Ctrl+C untuk stop lebih awal"
        Write-Host ""
        return
    }

    $label = "Fokus"
    $mins = 25

    if ($Command -eq "break") { $label = "Istirahat"; $mins = 5 }
    if ($Minutes -gt 0) { $mins = $Minutes }
    if ($Command -ne "start" -and $Command -ne "break") { $mins = if ($Command -match '^\d+$') { [int]$Command } else { 25 } }

    $totalSeconds = $mins * 60
    Write-Host ""
    Write-Host "$label dimulai: $mins menit. Ctrl+C untuk berhenti." -ForegroundColor Cyan

    for ($s = $totalSeconds; $s -ge 0; $s--) {
        $m = [int][math]::Floor($s / 60)
        $sec = [int]($s % 60)
        Write-Host -NoNewline ("`r{0:D2}:{1:D2} tersisa   " -f $m, $sec)
        Start-Sleep -Seconds 1
    }

    Write-Host ""
    Write-Host "$label selesai!" -ForegroundColor Green
    1..3 | ForEach-Object { [console]::beep(800, 300); Start-Sleep -Milliseconds 150 }
}

# =========================================================
#  UTILITY LAIN — dipindah dari $PROFILE, sekarang punya help
# =========================================================

function Translate-Text {
    param(
        [string]$text,
        [string]$from = "id",
        [string]$to = "en"
    )

    if ([string]::IsNullOrWhiteSpace($text) -or $text -eq "help") {
        Write-Host ""
        Write-Host "TRANS - Google Translate cepat"
        Write-Host "================================"
        Write-Host '  trans "teks"              id -> en (default)'
        Write-Host '  trans "teks" en id        en -> id'
        Write-Host '  trans "teks" id ja        id -> jepang'
        Write-Host ""
        return
    }

    $url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=$from&tl=$to&dt=t&q=$([uri]::EscapeDataString($text))"
    $response = Invoke-RestMethod -Uri $url -Method Get -Headers @{"User-Agent"="Mozilla/5.0"}

    if ($response -and $response[0] -and $response[0][0]) {
        $translation = $response[0][0][0]
        Write-Host "Translation ($from -> $to): $translation" -ForegroundColor Green
    } else {
        Write-Host "Translation failed!" -ForegroundColor Red
    }
}

Set-Alias trans Translate-Text

function getUUID {
    param([string]$arg)

    if ($arg -eq "help") {
        Write-Host ""
        Write-Host "UUID - Generate GUID baru"
        Write-Host "================================"
        Write-Host "  uuid       tampilkan 1 GUID baru"
        Write-Host ""
        return
    }

    [guid]::NewGuid()
}

Set-Alias uuid getUUID

