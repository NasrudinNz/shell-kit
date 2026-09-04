# =========================================================
#  PSTools.ps1 — Personal Productivity CLI for PowerShell
#  Lokasi   : $HOME\PSTools\PSTools.ps1
#  Data     : $HOME\PSTools\data\
#
#  Cara pakai: dot-source file ini dari $PROFILE:
#
#      . "$HOME\PSTools\PSTools.ps1"
#
#  Commands:
#    todo      -> checklist tasks (multi-file)
#    note      -> catatan bebas dengan timestamp
#    bm        -> bookmark direktori
#    snippet   -> simpan & ambil potongan kode
#    pomo      -> Pomodoro + TODO time tracking
#    trans     -> Google Translate cepat
#    uuid      -> generate GUID baru
#    pstools   -> tampilkan help
#
#  POMO:
#    pomo start       -> mulai sesi focus
#    pomo end         -> selesai + tampilkan statistik
#    pomo status      -> status sesi aktif
#    pomo stats       -> statistik hari ini
#    pomo reset       -> hapus histori POMO
#
#  Integrasi TODO:
#    Saat POMO aktif, operasi TODO otomatis dicatat.
#
# =========================================================


# =========================================================
#  GLOBAL CONFIG
# =========================================================

$Global:PSToolsDataDir = Join-Path $HOME "PSTools\data"

if (-not (Test-Path $Global:PSToolsDataDir)) {
    New-Item -Path $Global:PSToolsDataDir -ItemType Directory -Force | Out-Null
}

# File TODO terakhir yang aktif
$Global:PSToolsLastTodoFile = "notes"

# File state POMO
$Global:PSToolsPomoStateFile = Join-Path $Global:PSToolsDataDir "pomodoro.json"

# File history POMO
$Global:PSToolsPomoHistoryFile = Join-Path $Global:PSToolsDataDir "pomodoro-history.json"


# =========================================================
#  HELPER
# =========================================================

function Join-ArgsFrom {
    param($Arr, $StartIndex)

    if ($null -eq $Arr -or $Arr.Count -le $StartIndex) {
        return ""
    }

    return ($Arr[$StartIndex..($Arr.Count - 1)] -join " ")
}


function Format-Duration {
    param(
        [long]$Seconds
    )

    if ($Seconds -lt 0) {
        $Seconds = 0
    }

    $hours = [int][math]::Floor($Seconds / 3600)
    $minutes = [int][math]::Floor(($Seconds % 3600) / 60)
    $secs = [int]($Seconds % 60)

    if ($hours -gt 0) {
        return "{0}h {1:D2}m {2:D2}s" -f $hours, $minutes, $secs
    }

    if ($minutes -gt 0) {
        return "{0}m {1:D2}s" -f $minutes, $secs
    }

    return "{0}s" -f $secs
}


function Format-ShortDuration {
    param(
        [long]$Seconds
    )

    if ($Seconds -lt 0) {
        $Seconds = 0
    }

    $hours = [int][math]::Floor($Seconds / 3600)
    $minutes = [int][math]::Floor(($Seconds % 3600) / 60)
    $secs = [int]($Seconds % 60)

    if ($hours -gt 0) {
        return "{0}h {1:D2}m {2:D2}s" -f $hours, $minutes, $secs
    }

    if ($minutes -gt 0) {
        return "{0}m {1:D2}s" -f $minutes, $secs
    }

    return "{0}s" -f $secs
}


# =========================================================
#  POMO INTERNAL FUNCTIONS
# =========================================================

function Get-PomoState {

    if (!(Test-Path $Global:PSToolsPomoStateFile)) {
        return $null
    }

    try {
        $raw = Get-Content $Global:PSToolsPomoStateFile -Raw -Encoding UTF8

        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $null
        }

        return ($raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}


function Save-PomoState {
    param(
        $State
    )

    $State | ConvertTo-Json -Depth 10 | Set-Content `
        -Path $Global:PSToolsPomoStateFile `
        -Encoding UTF8
}


function Remove-PomoState {

    if (Test-Path $Global:PSToolsPomoStateFile) {
        Remove-Item $Global:PSToolsPomoStateFile -Force
    }
}


function Get-PomoHistory {

    if (!(Test-Path $Global:PSToolsPomoHistoryFile)) {
        return @()
    }

    try {
        $raw = Get-Content $Global:PSToolsPomoHistoryFile -Raw -Encoding UTF8

        if ([string]::IsNullOrWhiteSpace($raw)) {
            return @()
        }

        $data = $raw | ConvertFrom-Json

        if ($null -eq $data) {
            return @()
        }

        return @($data)
    }
    catch {
        return @()
    }
}


function Save-PomoHistory {
    param(
        [array]$History
    )

    @($History) |
        ConvertTo-Json -Depth 10 |
        Set-Content -Path $Global:PSToolsPomoHistoryFile -Encoding UTF8
}


function Add-PomoHistory {
    param(
        $Session
    )

    $history = @(Get-PomoHistory)

    $history += $Session

    Save-PomoHistory $history
}


function Get-PomoCurrentTask {

    $state = Get-PomoState

    if ($null -eq $state) {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($state.CurrentTask)) {
        return $null
    }

    return $state.CurrentTask
}


function Set-PomoCurrentTask {
    param(
        [string]$FileName,
        [string]$Task
    )

    $state = Get-PomoState

    if ($null -eq $state) {
        return
    }

    # Jika task yang sama, tidak perlu membuat segment baru.
    if (
        $state.CurrentFile -eq $FileName -and
        $state.CurrentTask -eq $Task
    ) {
        return
    }

    # Tutup segment task sebelumnya
    Complete-PomoTaskSegment

    $state = Get-PomoState

    if ($null -eq $state) {
        return
    }

    $state.CurrentFile = $FileName
    $state.CurrentTask = $Task
    $state.CurrentTaskStarted = (Get-Date).ToString("o")

    Save-PomoState $state
}


function Complete-PomoTaskSegment {

    $state = Get-PomoState

    if ($null -eq $state) {
        return
    }

    if ([string]::IsNullOrWhiteSpace($state.CurrentTask)) {
        return
    }

    if ([string]::IsNullOrWhiteSpace($state.CurrentTaskStarted)) {
        return
    }

    try {
        $started = [datetime]$state.CurrentTaskStarted
        $ended = Get-Date

        $seconds = [long][math]::Floor(
            ($ended - $started).TotalSeconds
        )

        if ($seconds -lt 0) {
            $seconds = 0
        }

        # Ambil session object
        $session = $state.Session

        if ($null -eq $session.Tasks) {
            $session.Tasks = @()
        }

        $tasks = @($session.Tasks)

        $existing = $null

        foreach ($task in $tasks) {

            if (
                $task.File -eq $state.CurrentFile -and
                $task.Task -eq $state.CurrentTask
            ) {
                $existing = $task
                break
            }
        }

        if ($null -eq $existing) {

            $tasks += [PSCustomObject]@{
                File     = $state.CurrentFile
                Task     = $state.CurrentTask
                Seconds  = $seconds
                Segments = 1
            }

        }
        else {

            $existing.Seconds =
                [long]$existing.Seconds + $seconds

            $existing.Segments =
                [int]$existing.Segments + 1
        }

        $session.Tasks = @($tasks)

        $state.Session = $session

        $state.CurrentFile = ""
        $state.CurrentTask = ""
        $state.CurrentTaskStarted = ""

        Save-PomoState $state
    }
    catch {
        # Jangan sampai error tracking mengganggu TODO
    }
}


function Register-PomoTodoActivity {
    param(
        [string]$FileName,
        [string]$Task
    )

    $state = Get-PomoState

    if ($null -eq $state) {
        return
    }

    if (-not $state.Active) {
        return
    }

    if ([string]::IsNullOrWhiteSpace($Task)) {
        return
    }

    Set-PomoCurrentTask `
        -FileName $FileName `
        -Task $Task
}


function Show-PomoStatistics {
    param(
        [switch]$TodayOnly
    )

    $history = @(Get-PomoHistory)

    if ($TodayOnly) {

        $today = (Get-Date).Date

        $history = @(
            $history | Where-Object {

                try {
                    ([datetime]$_.Date).Date -eq $today
                }
                catch {
                    $false
                }
            }
        )
    }

    Write-Host ""
    Write-Host "POMODORO STATISTICS" -ForegroundColor Cyan
    Write-Host "════════════════════════════════════════"

    if ($TodayOnly) {
        Write-Host "Today"
    }

    Write-Host "────────────────────────────────────────"

    if ($history.Count -eq 0) {

        Write-Host "Belum ada data POMO."

        Write-Host ""
        return
    }

    $taskStats = @{}
    $totalFocus = 0

    foreach ($session in $history) {

        $sessionSeconds = 0

        if ($null -ne $session.DurationSeconds) {
            $sessionSeconds = [long]$session.DurationSeconds
        }

        $totalFocus += $sessionSeconds

        if ($null -ne $session.Tasks) {

            foreach ($task in @($session.Tasks)) {

                if ([string]::IsNullOrWhiteSpace($task.Task)) {
                    continue
                }

                $key = "$($task.File)|$($task.Task)"

                if (!$taskStats.ContainsKey($key)) {

                    $taskStats[$key] = [PSCustomObject]@{
                        File    = $task.File
                        Task    = $task.Task
                        Seconds = 0
                    }
                }

                $taskStats[$key].Seconds += [long]$task.Seconds
            }
        }
    }

    # Urutkan task berdasarkan durasi terbesar
    $sortedTasks = @(
        $taskStats.Values |
        Sort-Object Seconds -Descending
    )

    foreach ($task in $sortedTasks) {

        $taskText = $task.Task

        # Maksimal supaya output tetap rapi
        if ($taskText.Length -gt 45) {
            $taskText = $taskText.Substring(0, 42) + "..."
        }

        Write-Host (
            "{0,-30} {1,10}" -f
            $taskText,
            (Format-ShortDuration $task.Seconds)
        )
    }

    Write-Host ""

    Write-Host (
        "{0,-30} {1,10}" -f
        "Total Focus",
        (Format-Duration $totalFocus)
    )

    Write-Host (
        "{0,-30} {1,10}" -f
        "Sessions",
        $history.Count
    )

    Write-Host ""
}


function Show-PomoSessionStatistics {
    param(
        $Session
    )

    Write-Host ""
    Write-Host "POMODORO STATISTICS" -ForegroundColor Cyan
    Write-Host "════════════════════════════════════════"
    Write-Host ""
    Write-Host "Today"
    Write-Host "────────────────────────────────────────"

    if ($null -ne $Session.Tasks) {

        foreach ($task in @(
            $Session.Tasks |
            Sort-Object Seconds -Descending
        )) {

            $taskText = $task.Task

            if ($taskText.Length -gt 45) {
                $taskText = $taskText.Substring(0, 42) + "..."
            }

            Write-Host (
                "{0,-30} {1,10}" -f
                $taskText,
                (Format-ShortDuration $task.Seconds)
            )
        }
    }

    Write-Host ""

    Write-Host (
        "{0,-30} {1,10}" -f
        "Total Focus",
        (Format-Duration ([long]$Session.DurationSeconds))
    )

    Write-Host (
        "{0,-30} {1,10}" -f
        "Sessions",
        1
    )

    Write-Host ""
}


# =========================================================
#  PSTOOLS HELP
# =========================================================

function pstools {

    Write-Host ""
    Write-Host "=== PSTools — Personal Productivity CLI ===" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "todo      checklist tasks           (todo help)"
    Write-Host "note      catatan bebas + timestamp  (note help)"
    Write-Host "bm        bookmark direktori         (bm help)"
    Write-Host "snippet   simpan/ambil kode          (snippet help)"
    Write-Host "pomo      Pomodoro + TODO tracking   (pomo help)"
    Write-Host ""
    Write-Host "trans     google translate cepat     (trans help)"
    Write-Host "uuid      generate GUID baru         (uuid help)"
    Write-Host ""

    Write-Host "Semua data tersimpan di:"
    Write-Host "$Global:PSToolsDataDir"

    Write-Host ""
}


# =========================================================
#  TODO
# =========================================================

function todo {

    param(
        [Parameter(Position=0)]
        [string]$Command,

        [Parameter(Position=1, ValueFromRemainingArguments=$true)]
        [string[]]$Arguments
    )

    $FileName = $Global:PSToolsLastTodoFile

    # Cari separator "-"
    $dashIndex = -1

    if ($Arguments.Count -gt 0) {

        for ($i = 0; $i -lt $Arguments.Count; $i++) {

            if ($Arguments[$i] -eq "-") {

                $dashIndex = $i
                break
            }
        }
    }

    # Ambil nama file
    if (
        $dashIndex -ge 0 -and
        ($dashIndex + 1) -lt $Arguments.Count
    ) {

        $FileName = $Arguments[$dashIndex + 1]

        if ($dashIndex -gt 0) {
            $Arguments = $Arguments[0..($dashIndex - 1)]
        }
        else {
            $Arguments = @()
        }
    }

    $FileName = $FileName -replace '\.md$', ''

    $Global:PSToolsLastTodoFile = $FileName

    $file = Join-Path `
        $Global:PSToolsDataDir `
        "$FileName.md"


    # -----------------------------------------------------
    # HELP
    # -----------------------------------------------------

    if (
        [string]::IsNullOrWhiteSpace($Command) -or
        $Command -eq "help"
    ) {

        Write-Host ""
        Write-Host "TODO - Markdown Task Manager"
        Write-Host "================================"
        Write-Host ""
        Write-Host "USAGE:"
        Write-Host '  todo add "task" - namafile'
        Write-Host '  todo list - namafile'
        Write-Host '  todo done 1 - namafile'
        Write-Host '  todo undone 1 - namafile'
        Write-Host '  todo remove 1 - namafile'
        Write-Host '  todo files'
        Write-Host ""
        Write-Host "Saat POMO aktif, aktivitas TODO otomatis dicatat."
        Write-Host ""
        Write-Host "Data: $Global:PSToolsDataDir\<namafile>.md"
        Write-Host ""

        return
    }


    # -----------------------------------------------------
    # TODO FILES
    # -----------------------------------------------------

    if ($Command -eq "files") {

        $todoFiles = @(
            Get-ChildItem `
                -Path $Global:PSToolsDataDir `
                -Filter "*.md" `
                -File |
            Where-Object {
                $_.Name -notin @(
                    "bookmarks.md",
                    "snippets.md"
                )
            }
        )

        Write-Host ""
        Write-Host "=== TODO FILES ===" -ForegroundColor Cyan
        Write-Host ""

        if ($todoFiles.Count -eq 0) {

            Write-Host "Belum ada file TODO."
            Write-Host ""

            return
        }

        foreach ($todoFile in $todoFiles) {

            $lines = @(Get-Content $todoFile.FullName)

            $tasks = @(
                $lines |
                Where-Object {
                    $_ -match '^- \[[ xX]\] '
                }
            )

            if ($tasks.Count -eq 0) {
                continue
            }

            $done = @(
                $tasks |
                Where-Object {
                    $_ -match '^- \[[xX]\] '
                }
            ).Count

            $undone = $tasks.Count - $done

            Write-Host ""
            Write-Host "[$($todoFile.BaseName)]" -ForegroundColor Yellow

            Write-Host (
                "Total: {0} | Done: {1} | Undone: {2}" -f
                $tasks.Count,
                $done,
                $undone
            )

            Write-Host "────────────────────────────────────────"

            $taskNo = 1

            foreach ($line in $lines) {

                if ($line -match '^- \[ \] (.*)$') {

                    Write-Host (
                        "{0,3}. [ ] {1}" -f
                        $taskNo,
                        $Matches[1]
                    )

                    $taskNo++
                }
                elseif ($line -match '^- \[[xX]\] (.*)$') {

                    Write-Host (
                        "{0,3}. [x] {1}" -f
                        $taskNo,
                        $Matches[1]
                    ) -ForegroundColor Green

                    $taskNo++
                }
            }
        }

        Write-Host ""

        return
    }


    # -----------------------------------------------------
    # CREATE FILE
    # -----------------------------------------------------

    if (!(Test-Path $file)) {

        New-Item `
            -Path $file `
            -ItemType File `
            -Force |
            Out-Null
    }


    # -----------------------------------------------------
    # ADD
    # -----------------------------------------------------

    switch ($Command) {

        "add" {

            $Text = ($Arguments -join " ").Trim()

            if ([string]::IsNullOrWhiteSpace($Text)) {

                Write-Host ""
                Write-Host 'Usage: todo add "task" - namafile'
                Write-Host ""

                return
            }

            Add-Content `
                -Path $file `
                -Value "- [ ] $Text"


            # POMO:
            # Task baru menjadi task aktif.
            Register-PomoTodoActivity `
                -FileName $FileName `
                -Task $Text


            Write-Host ""
            Write-Host "Ditambahkan: $Text" -ForegroundColor Green
            Write-Host "File: $FileName.md"

            todo list - $FileName
        }


        # -------------------------------------------------
        # LIST
        # -------------------------------------------------

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
                }
                elseif ($line -match '^- \[[xX]\] (.*)$') {

                    Write-Host "$i. [x] $($Matches[1])" `
                        -ForegroundColor Green
                }
                else {

                    Write-Host "$i.    $line"
                }

                $i++
            }

            Write-Host ""
        }


        # -------------------------------------------------
        # DONE
        # -------------------------------------------------

        "done" {

            if ($Arguments.Count -eq 0) {

                Write-Host "Usage: todo done <number> - namafile"

                return
            }

            $number = 0

            if (![int]::TryParse(
                $Arguments[0],
                [ref]$number
            )) {

                Write-Host "Nomor tidak valid."

                return
            }

            $lines = [System.Collections.Generic.List[string]](
                @(Get-Content $file)
            )

            if (
                $number -lt 1 -or
                $number -gt $lines.Count
            ) {

                Write-Host "Task tidak ditemukan."

                return
            }


            if ($lines[$number - 1] -match '^- \[ \] (.*)$') {

                $taskText = $Matches[1]

                $lines[$number - 1] =
                    $lines[$number - 1] -replace `
                    '^- \[ \]', `
                    '- [x]'

                $lines | Set-Content `
                    $file `
                    -Encoding UTF8


                # POMO:
                Register-PomoTodoActivity `
                    -FileName $FileName `
                    -Task $taskText


                Write-Host `
                    "Task $number selesai." `
                    -ForegroundColor Green

                todo list - $FileName
            }
            else {

                Write-Host `
                    "Task sudah selesai atau bukan TODO."
            }
        }


        # -------------------------------------------------
        # UNDONE
        # -------------------------------------------------

        "undone" {

            if ($Arguments.Count -eq 0) {

                Write-Host "Usage: todo undone <number> - namafile"

                return
            }

            $number = 0

            if (![int]::TryParse(
                $Arguments[0],
                [ref]$number
            )) {

                Write-Host "Nomor tidak valid."

                return
            }

            $lines = [System.Collections.Generic.List[string]](
                @(Get-Content $file)
            )

            if (
                $number -lt 1 -or
                $number -gt $lines.Count
            ) {

                Write-Host "Task tidak ditemukan."

                return
            }


            if ($lines[$number - 1] -match '^- \[[xX]\] (.*)$') {

                $taskText = $Matches[1]

                $lines[$number - 1] =
                    $lines[$number - 1] -replace `
                    '^- \[[xX]\]', `
                    '- [ ]'

                $lines | Set-Content `
                    $file `
                    -Encoding UTF8


                Register-PomoTodoActivity `
                    -FileName $FileName `
                    -Task $taskText


                Write-Host `
                    "Task $number dikembalikan." `
                    -ForegroundColor Yellow

                todo list - $FileName
            }
        }


        # -------------------------------------------------
        # REMOVE
        # -------------------------------------------------

        "remove" {

            if ($Arguments.Count -eq 0) {

                Write-Host "Usage: todo remove <number> - namafile"

                return
            }

            $number = 0

            if (![int]::TryParse(
                $Arguments[0],
                [ref]$number
            )) {

                Write-Host "Nomor tidak valid."

                return
            }

            $lines = [System.Collections.Generic.List[string]](
                @(Get-Content $file)
            )

            if (
                $number -lt 1 -or
                $number -gt $lines.Count
            ) {

                Write-Host "Task tidak ditemukan."

                return
            }


            $task = $lines[$number - 1]

            $taskText = ""

            if ($task -match '^- \[[ xX]\] (.*)$') {
                $taskText = $Matches[1]
            }


            # Jika task yang sedang aktif dihapus,
            # tutup tracking-nya terlebih dahulu.
            $state = Get-PomoState

            if (
                $null -ne $state -and
                $state.Active -and
                $state.CurrentFile -eq $FileName -and
                $state.CurrentTask -eq $taskText
            ) {

                Complete-PomoTaskSegment
            }


            $lines.RemoveAt($number - 1)

            $lines | Set-Content `
                $file `
                -Encoding UTF8


            Write-Host `
                "Dihapus: $task" `
                -ForegroundColor Green

            todo list - $FileName
        }


        default {

            Write-Host `
                "Unknown command: $Command. Run 'todo help'."
        }
    }
}


# =========================================================
#  NOTE
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

            if ($Arguments[$i] -eq "-") {

                $dashIndex = $i
                break
            }
        }

        if (
            $dashIndex -ge 0 -and
            ($dashIndex + 1) -lt $Arguments.Count
        ) {

            $FileName = $Arguments[$dashIndex + 1]

            if ($dashIndex -gt 0) {

                $Arguments =
                    $Arguments[0..($dashIndex - 1)]
            }
            else {

                $Arguments = @()
            }
        }
    }

    $FileName = $FileName -replace '\.md$', ''

    $file = Join-Path `
        $Global:PSToolsDataDir `
        "$FileName.md"


    if (
        [string]::IsNullOrWhiteSpace($Command) -or
        $Command -eq "help"
    ) {

        Write-Host ""
        Write-Host "NOTE - Catatan bebas dengan timestamp"
        Write-Host "================================"
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

        Set-Content `
            -Path $file `
            -Value "# Notes`n" `
            -Encoding UTF8
    }


    function Get-NoteEntries($Path) {

        $raw = Get-Content `
            -Path $Path `
            -Raw `
            -Encoding UTF8

        if ([string]::IsNullOrWhiteSpace($raw)) {
            return @()
        }

        $blocks =
            $raw -split "(?m)^---\s*$"

        $notes = @()

        foreach ($b in $blocks) {

            $t = $b.Trim()

            if (
                $t -match `
                '(?s)## \[(.+?)\]\s+(.+?)\r?\n(.*)$'
            ) {

                $notes += [PSCustomObject]@{
                    Timestamp = $matches[1]
                    Title     = $matches[2]
                    Content   = $matches[3].Trim()
                }
            }
        }

        return @($notes)
    }


    function Save-NoteEntries($Path, $Notes) {

        $content = @(
            "# Notes",
            ""
        )

        foreach ($n in $Notes) {

            $content +=
                "## [$($n.Timestamp)] $($n.Title)"

            $content += $n.Content
            $content += ""
            $content += "---"
            $content += ""
        }

        Set-Content `
            -Path $Path `
            -Value $content `
            -Encoding UTF8
    }


    switch ($Command) {

        "add" {

            if (
                $Arguments.Count -eq 0 -or
                [string]::IsNullOrWhiteSpace($Arguments[0])
            ) {

                Write-Host `
                    'Usage: note add "judul" "isi" - namafile'

                return
            }

            $title = $Arguments[0]
            $body = Join-ArgsFrom $Arguments 1

            $notes = @(Get-NoteEntries $file)

            $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

            $existingIdx = -1

            for ($i = 0; $i -lt $notes.Count; $i++) {

                if (
                    $notes[$i].Title.Trim().ToLower() `
                    -eq `
                    $title.Trim().ToLower()
                ) {

                    $existingIdx = $i
                    break
                }
            }


            if ($existingIdx -ge 0) {

                $notes[$existingIdx].Content =
                    "$($notes[$existingIdx].Content)`n`n**[$ts]** $body"

                Save-NoteEntries $file $notes

                Write-Host `
                    "Note '$title' digabung ke entry yang sudah ada." `
                    -ForegroundColor Green

                Write-Host "File: $FileName.md"
            }
            else {

                $notes += [PSCustomObject]@{
                    Timestamp = $ts
                    Title     = $title
                    Content   = "**[$ts]** $body"
                }

                Save-NoteEntries $file $notes

                Write-Host `
                    "Note ditambahkan: $title" `
                    -ForegroundColor Green

                Write-Host "File: $FileName.md"
            }
        }


        "list" {

            $notes = @(Get-NoteEntries $file)

            if ($notes.Count -eq 0) {

                Write-Host "Belum ada note."

                return
            }

            Write-Host ""
            Write-Host "$FileName.md"
            Write-Host "================================"

            for ($i = 0; $i -lt $notes.Count; $i++) {

                Write-Host (
                    "{0}. [{1}] {2}" -f
                    ($i + 1),
                    $notes[$i].Timestamp,
                    $notes[$i].Title
                )
            }

            Write-Host ""
        }


        "view" {

            if ($Arguments.Count -eq 0) {

                Write-Host `
                    "Usage: note view <number> - namafile"

                return
            }

            $notes = @(Get-NoteEntries $file)

            $idx = [int]$Arguments[0] - 1

            if (
                $idx -lt 0 -or
                $idx -ge $notes.Count
            ) {

                Write-Host "Nomor tidak valid."

                return
            }

            Write-Host ""
            Write-Host `
                "=== $($notes[$idx].Title) ===" `
                -ForegroundColor Cyan

            Write-Host ""

            $contentLines =
                $notes[$idx].Content -split "`r?`n"

            foreach ($line in $contentLines) {

                if (
                    $line -match `
                    '^\*\*\[(.+?)\]\*\*\s*(.*)$'
                ) {

                    Write-Host `
                        -NoNewline `
                        "[$($matches[1])] " `
                        -ForegroundColor Cyan

                    Write-Host `
                        $matches[2] `
                        -ForegroundColor White
                }
                elseif ([string]::IsNullOrWhiteSpace($line)) {

                    Write-Host ""
                }
                else {

                    Write-Host `
                        -NoNewline `
                        "[$($notes[$idx].Timestamp)] " `
                        -ForegroundColor Cyan

                    Write-Host `
                        $line `
                        -ForegroundColor White
                }
            }

            Write-Host ""
        }


        "rm" {

            if ($Arguments.Count -eq 0) {

                Write-Host `
                    "Usage: note rm <number> - namafile"

                return
            }

            $notes = @(Get-NoteEntries $file)

            $idx = [int]$Arguments[0] - 1

            if (
                $idx -lt 0 -or
                $idx -ge $notes.Count
            ) {

                Write-Host "Nomor tidak valid."

                return
            }

            $removed = $notes[$idx].Title

            $newNotes = @()

            for ($i = 0; $i -lt $notes.Count; $i++) {

                if ($i -ne $idx) {
                    $newNotes += $notes[$i]
                }
            }

            Save-NoteEntries $file $newNotes

            Write-Host `
                "Note dihapus: $removed" `
                -ForegroundColor Green
        }


        default {

            Write-Host `
                "Unknown command: $Command. Run 'note help'."
        }
    }
}


# =========================================================
#  BM
# =========================================================

function bm {

    param(
        [Parameter(Position=0)]
        [string]$Command,

        [Parameter(Position=1, ValueFromRemainingArguments=$true)]
        [string[]]$Arguments
    )

    $file = Join-Path `
        $Global:PSToolsDataDir `
        "bookmarks.md"

    if (!(Test-Path $file)) {

        Set-Content `
            -Path $file `
            -Value "# Bookmarks`n" `
            -Encoding UTF8
    }


    function Get-Bookmarks {

        $lines = Get-Content `
            -Path $file `
            -Encoding UTF8

        $bms = @{}

        foreach ($l in $lines) {

            if ($l -match '^- (\S+) = (.+)$') {

                $bms[$matches[1]] = $matches[2]
            }
        }

        return $bms
    }


    function Save-Bookmarks($bms) {

        $content = @(
            "# Bookmarks",
            ""
        )

        foreach ($k in $bms.Keys | Sort-Object) {

            $content +=
                "- $k = $($bms[$k])"
        }

        Set-Content `
            -Path $file `
            -Value $content `
            -Encoding UTF8
    }


    if (
        [string]::IsNullOrWhiteSpace($Command) -or
        $Command -eq "help"
    ) {

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

            if ($Arguments.Count -eq 0) {

                Write-Host `
                    "Usage: bm add <nama> [path]"

                return
            }

            $name = $Arguments[0]

            $path =
                if ($Arguments.Count -gt 1) {
                    Join-ArgsFrom $Arguments 1
                }
                else {
                    (Get-Location).Path
                }

            $bms[$name] = $path

            Save-Bookmarks $bms

            Write-Host `
                "Bookmark '$name' -> $path" `
                -ForegroundColor Green
        }


        "go" {

            if ($Arguments.Count -eq 0) {

                Write-Host "Usage: bm go <nama>"

                return
            }

            $name = $Arguments[0]

            if ($bms.ContainsKey($name)) {

                if (Test-Path $bms[$name]) {

                    Set-Location $bms[$name]
                }
                else {

                    Write-Host `
                        "Path sudah tidak ada: $($bms[$name])" `
                        -ForegroundColor Red
                }
            }
            else {

                Write-Host `
                    "Bookmark '$name' tidak ditemukan." `
                    -ForegroundColor Red
            }
        }


        "list" {

            if ($bms.Count -eq 0) {

                Write-Host "Belum ada bookmark."

                return
            }

            Write-Host ""
            Write-Host "=== BOOKMARKS ==="

            foreach ($k in $bms.Keys | Sort-Object) {

                Write-Host `
                    "  $k -> $($bms[$k])"
            }

            Write-Host ""
        }


        "rm" {

            if ($Arguments.Count -eq 0) {

                Write-Host "Usage: bm rm <nama>"

                return
            }

            $name = $Arguments[0]

            if ($bms.ContainsKey($name)) {

                $bms.Remove($name)

                Save-Bookmarks $bms

                Write-Host `
                    "Bookmark '$name' dihapus." `
                    -ForegroundColor Green
            }
            else {

                Write-Host `
                    "Bookmark '$name' tidak ditemukan." `
                    -ForegroundColor Red
            }
        }


        default {

            Write-Host `
                "Unknown command: $Command. Run 'bm help'."
        }
    }
}


# =========================================================
#  SNIPPET
# =========================================================

function snippet {

    param(
        [Parameter(Position=0)]
        [string]$Command,

        [Parameter(Position=1, ValueFromRemainingArguments=$true)]
        [string[]]$Arguments
    )

    $file = Join-Path `
        $Global:PSToolsDataDir `
        "snippets.md"

    if (!(Test-Path $file)) {

        Set-Content `
            -Path $file `
            -Value "# Snippets`n" `
            -Encoding UTF8
    }


    function Get-Snippets {

        $raw = Get-Content `
            -Path $file `
            -Raw `
            -Encoding UTF8

        if ([string]::IsNullOrWhiteSpace($raw)) {
            return @()
        }

        $blocks =
            $raw -split "(?m)^---\s*$"

        $items = @()

        foreach ($b in $blocks) {

            $t = $b.Trim()

            if (
                $t -match `
                '(?s)## (\S+) \((.+?)\)\r?\n```.*?\r?\n(.*?)\r?\n```'
            ) {

                $items += [PSCustomObject]@{
                    Name = $matches[1]
                    Lang = $matches[2]
                    Code = $matches[3]
                }
            }
        }

        return @($items)
    }


    function Save-Snippets($items) {

        $content = @(
            "# Snippets",
            ""
        )

        foreach ($s in $items) {

            $content +=
                "## $($s.Name) ($($s.Lang))"

            $content += '```' + $s.Lang
            $content += $s.Code
            $content += '```'
            $content += ""
            $content += "---"
            $content += ""
        }

        Set-Content `
            -Path $file `
            -Value $content `
            -Encoding UTF8
    }


    if (
        [string]::IsNullOrWhiteSpace($Command) -or
        $Command -eq "help"
    ) {

        Write-Host ""
        Write-Host "SNIPPET - Code Snippet Manager"
        Write-Host "================================"
        Write-Host "  1. Copy kode yang mau disimpan (Ctrl+C)"
        Write-Host "  2. snippet save <nama> <bahasa>"
        Write-Host "  snippet list"
        Write-Host "  snippet get <nama>"
        Write-Host "  snippet rm <nama>"
        Write-Host ""

        return
    }


    $items = @(Get-Snippets)


    switch ($Command) {

        "save" {

            if ($Arguments.Count -lt 2) {

                Write-Host `
                    "Usage: snippet save <nama> <bahasa>"

                return
            }

            $name = $Arguments[0]
            $lang = $Arguments[1]

            $code = Get-Clipboard -Raw

            if ([string]::IsNullOrWhiteSpace($code)) {

                Write-Host `
                    "Clipboard kosong, copy kode dulu sebelum save." `
                    -ForegroundColor Red

                return
            }

            $items =
                @($items | Where-Object {
                    $_.Name -ne $name
                })

            $items += [PSCustomObject]@{
                Name = $name
                Lang = $lang
                Code = $code.TrimEnd()
            }

            Save-Snippets $items

            Write-Host `
                "Snippet '$name' ($lang) disimpan." `
                -ForegroundColor Green
        }


        "list" {

            if ($items.Count -eq 0) {

                Write-Host "Belum ada snippet."

                return
            }

            Write-Host ""
            Write-Host "=== SNIPPETS ==="

            foreach ($s in $items) {

                Write-Host `
                    "  $($s.Name) [$($s.Lang)]"
            }

            Write-Host ""
        }


        "get" {

            if ($Arguments.Count -eq 0) {

                Write-Host "Usage: snippet get <nama>"

                return
            }

            $found =
                $items |
                Where-Object {
                    $_.Name -eq $Arguments[0]
                }

            if (-not $found) {

                Write-Host `
                    "Snippet '$($Arguments[0])' tidak ditemukan." `
                    -ForegroundColor Red

                return
            }

            Write-Host ""
            Write-Host `
                "=== $($found.Name) ($($found.Lang)) ===" `
                -ForegroundColor Cyan

            Write-Host $found.Code
            Write-Host ""

            $found.Code | Set-Clipboard

            Write-Host `
                "(disalin ke clipboard)" `
                -ForegroundColor DarkGray
        }


        "rm" {

            if ($Arguments.Count -eq 0) {

                Write-Host "Usage: snippet rm <nama>"

                return
            }

            $exists =
                $items |
                Where-Object {
                    $_.Name -eq $Arguments[0]
                }

            if (-not $exists) {

                Write-Host `
                    "Snippet '$($Arguments[0])' tidak ditemukan." `
                    -ForegroundColor Red

                return
            }

            $items =
                @($items | Where-Object {
                    $_.Name -ne $Arguments[0]
                })

            Save-Snippets $items

            Write-Host `
                "Snippet '$($Arguments[0])' dihapus." `
                -ForegroundColor Green
        }


        default {

            Write-Host `
                "Unknown command: $Command. Run 'snippet help'."
        }
    }
}


# =========================================================
#  POMO
#
#  POMO sekarang TIDAK memblokir PowerShell.
#
#  pomo start
#       |
#       +-- user bebas menggunakan todo
#       |
#       +-- TODO activity otomatis menjadi task aktif
#       |
#  pomo end
#       |
#       +-- tutup task terakhir
#       +-- simpan session
#       +-- tampilkan statistics
#
# =========================================================

function pomo {

    param(
        [Parameter(Position=0)]
        [string]$Command,

        [Parameter(Position=1)]
        [int]$Minutes
    )


    # -----------------------------------------------------
    # HELP
    # -----------------------------------------------------

    if (
        [string]::IsNullOrWhiteSpace($Command) -or
        $Command -eq "help"
    ) {

        Write-Host ""
        Write-Host "POMO - Pomodoro + TODO Time Tracking"
        Write-Host "======================================"
        Write-Host ""
        Write-Host "  pomo start       mulai sesi focus"
        Write-Host "  pomo end         selesai + tampilkan statistik"
        Write-Host "  pomo status      lihat sesi aktif"
        Write-Host "  pomo stats       statistik hari ini"
        Write-Host "  pomo reset       hapus seluruh histori"
        Write-Host ""
        Write-Host "Saat POMO aktif, operasi TODO otomatis dicatat."
        Write-Host ""
        Write-Host "Contoh:"
        Write-Host "  pomo start"
        Write-Host "  todo list - notes"
        Write-Host "  todo done 1 - notes"
        Write-Host "  todo list - project"
        Write-Host "  todo done 2 - project"
        Write-Host "  pomo end"
        Write-Host ""

        return
    }


    # -----------------------------------------------------
    # START
    # -----------------------------------------------------

    if ($Command -eq "start") {

        $existing = Get-PomoState

        if (
            $null -ne $existing -and
            $existing.Active
        ) {

            $started = [datetime]$existing.Started

            $elapsed = [long][math]::Floor(
                ((Get-Date) - $started).TotalSeconds
            )

            Write-Host ""
            Write-Host "POMO masih aktif." `
                -ForegroundColor Yellow

            Write-Host (
                "Started : {0}" -f
                $started.ToString("HH:mm:ss")
            )

            Write-Host (
                "Elapsed : {0}" -f
                (Format-Duration $elapsed)
            )

            if (
                -not [string]::IsNullOrWhiteSpace(
                    $existing.CurrentTask
                )
            ) {

                Write-Host (
                    "Task    : {0}" -f
                    $existing.CurrentTask
                )
            }

            Write-Host ""

            return
        }


        $now = Get-Date

        $session = [PSCustomObject]@{
            Id              = [guid]::NewGuid().ToString()
            Date            = $now.ToString("yyyy-MM-dd")
            Started         = $now.ToString("o")
            Ended           = ""
            DurationSeconds = 0
            Tasks           = @()
        }


        $state = [PSCustomObject]@{
            Active            = $true
            Started           = $now.ToString("o")
            CurrentFile       = ""
            CurrentTask       = ""
            CurrentTaskStarted = ""
            Session           = $session
        }


        Save-PomoState $state


        Write-Host ""
        Write-Host "POMO STARTED" `
            -ForegroundColor Green

        Write-Host "────────────────────────────────────────"

        Write-Host (
            "Started : {0}" -f
            $now.ToString("HH:mm:ss")
        )

        Write-Host ""
        Write-Host "Sekarang bebas menggunakan TODO."
        Write-Host "Aktivitas TODO akan dicatat otomatis."

        Write-Host ""
    }


    # -----------------------------------------------------
    # END
    # -----------------------------------------------------

    elseif ($Command -eq "end") {

        $state = Get-PomoState

        if (
            $null -eq $state -or
            !$state.Active
        ) {

            Write-Host ""
            Write-Host `
                "Tidak ada sesi POMO aktif." `
                -ForegroundColor Yellow

            Write-Host ""

            return
        }


        # Tutup task terakhir
        Complete-PomoTaskSegment

        $state = Get-PomoState

        if ($null -eq $state) {
            return
        }


        $started = [datetime]$state.Started
        $ended = Get-Date

        $duration = [long][math]::Floor(
            ($ended - $started).TotalSeconds
        )

        if ($duration -lt 0) {
            $duration = 0
        }


        $session = $state.Session

        $session.Ended =
            $ended.ToString("o")

        $session.DurationSeconds =
            $duration


        # Simpan histori
        Add-PomoHistory $session

        # Hapus state aktif
        Remove-PomoState


        # Beep
        try {
            [console]::beep(800, 250)
            Start-Sleep -Milliseconds 100
            [console]::beep(1000, 350)
        }
        catch {
        }


        Write-Host ""
        Write-Host "POMO ENDED" `
            -ForegroundColor Green

        Write-Host (
            "Duration : {0}" -f
            (Format-Duration $duration)
        )

        #Show-PomoSessionStatistics $session

        # Tampilkan statistik seluruh hari
        Show-PomoStatistics -TodayOnly
    }


    # -----------------------------------------------------
    # STATUS
    # -----------------------------------------------------

    elseif ($Command -eq "status") {

        $state = Get-PomoState

        if (
            $null -eq $state -or
            !$state.Active
        ) {

            Write-Host ""
            Write-Host "POMO tidak aktif."
            Write-Host ""

            return
        }


        $started = [datetime]$state.Started

        $elapsed = [long][math]::Floor(
            ((Get-Date) - $started).TotalSeconds
        )


        Write-Host ""
        Write-Host "POMO STATUS" `
            -ForegroundColor Cyan

        Write-Host "────────────────────────────────────────"

        Write-Host (
            "Started : {0}" -f
            $started.ToString("HH:mm:ss")
        )

        Write-Host (
            "Elapsed : {0}" -f
            (Format-Duration $elapsed)
        )


        if (
            ![string]::IsNullOrWhiteSpace(
                $state.CurrentTask
            )
        ) {

            Write-Host (
                "File    : {0}.md" -f
                $state.CurrentFile
            )

            Write-Host (
                "Task    : {0}" -f
                $state.CurrentTask
            )

            if (
                ![string]::IsNullOrWhiteSpace(
                    $state.CurrentTaskStarted
                )
            ) {

                $taskStarted =
                    [datetime]$state.CurrentTaskStarted

                $taskElapsed =
                    [long][math]::Floor(
                        ((Get-Date) - $taskStarted).TotalSeconds
                    )

                Write-Host (
                    "Task Time: {0}" -f
                    (Format-Duration $taskElapsed)
                )
            }
        }
        else {

            Write-Host "Task    : belum ada TODO yang aktif."
        }

        Write-Host ""
    }


    # -----------------------------------------------------
    # STATS
    # -----------------------------------------------------

    elseif ($Command -eq "stats") {

        Show-PomoStatistics -TodayOnly
    }


    # -----------------------------------------------------
    # RESET
    # -----------------------------------------------------

    elseif ($Command -eq "reset") {

        Write-Host ""
        Write-Host `
            "PERINGATAN: seluruh histori POMO akan dihapus." `
            -ForegroundColor Yellow

        $answer =
            Read-Host "Ketik YES untuk melanjutkan"

        if ($answer -eq "YES") {

            if (Test-Path $Global:PSToolsPomoHistoryFile) {

                Remove-Item `
                    $Global:PSToolsPomoHistoryFile `
                    -Force
            }

            Write-Host `
                "Histori POMO dihapus." `
                -ForegroundColor Green
        }
        else {

            Write-Host "Dibatalkan."
        }

        Write-Host ""
    }


    # -----------------------------------------------------
    # UNKNOWN
    # -----------------------------------------------------

    else {

        Write-Host ""
        Write-Host `
            "Unknown POMO command: $Command" `
            -ForegroundColor Red

        Write-Host `
            "Gunakan: pomo help"

        Write-Host ""
    }
}


# =========================================================
#  TRANSLATE
# =========================================================

function Translate-Text {

    param(
        [string]$text,
        [string]$from = "id",
        [string]$to = "en"
    )


    if (
        [string]::IsNullOrWhiteSpace($text) -or
        $text -eq "help"
    ) {

        Write-Host ""
        Write-Host "TRANS - Google Translate cepat"
        Write-Host "================================"
        Write-Host '  trans "teks"              id -> en'
        Write-Host '  trans "teks" en id        en -> id'
        Write-Host '  trans "teks" id ja        id -> Jepang'
        Write-Host ""

        return
    }


    $url =
        "https://translate.googleapis.com/translate_a/single" +
        "?client=gtx" +
        "&sl=$from" +
        "&tl=$to" +
        "&dt=t" +
        "&q=$([uri]::EscapeDataString($text))"


    try {

        $response =
            Invoke-RestMethod `
                -Uri $url `
                -Method Get `
                -Headers @{
                    "User-Agent" = "Mozilla/5.0"
                }


        if (
            $response -and
            $response[0] -and
            $response[0][0]
        ) {

            $translation =
                $response[0][0][0]

            Write-Host `
                "Translation ($from -> $to): $translation" `
                -ForegroundColor Green
        }
        else {

            Write-Host `
                "Translation failed!" `
                -ForegroundColor Red
        }
    }
    catch {

        Write-Host `
            "Translation error: $($_.Exception.Message)" `
            -ForegroundColor Red
    }
}


Set-Alias trans Translate-Text


# =========================================================
#  UUID
# =========================================================

function getUUID {

    param(
        [string]$arg
    )


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