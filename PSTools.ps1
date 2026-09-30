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

# Editor untuk 'todo open'
$Global:PSToolsTodoEditor = "vim"

# File state POMO
$Global:PSToolsPomoStateFile = Join-Path $Global:PSToolsDataDir "pomodoro.json"

# File history POMO
$Global:PSToolsPomoHistoryFile = Join-Path $Global:PSToolsDataDir "pomodoro-history.json"


# =========================================================
#  HELPER
# =========================================================

function Show-TodoProgress {
    param(
        [int]$Total,
        [int]$Done,
        [int]$Width = 30
    )

    if ($Total -le 0) {
        return
    }

    $percent = [int][math]::Round(
        ($Done / $Total) * 100
    )

    $filled = [int][math]::Round(
        ($percent / 100) * $Width
    )

    if ($filled -gt $Width) {
        $filled = $Width
    }

    if ($filled -lt 0) {
        $filled = 0
    }

    $empty = $Width - $filled

    $bar =
        ("█" * $filled) +
        ("░" * $empty)

    Write-Host (
        "Progress: {0} {1,3}% ({2}/{3})" -f
        $bar,
        $percent,
        $Done,
        $Total
    ) -ForegroundColor Cyan
}


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


function Format-MarkdownText {
    param(
        [string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return $Text
    }

    $esc = [char]27

    # Render basic Markdown emphasis without changing the stored task text.
    $Text = [regex]::Replace(
        $Text,
        '\*\*\*(.+?)\*\*\*',
        "${esc}[1m${esc}[3m`$1${esc}[22m${esc}[23m"
    )
    $Text = [regex]::Replace(
        $Text,
        '\*\*(.+?)\*\*',
        "${esc}[1m`$1${esc}[22m"
    )
    $Text = [regex]::Replace(
        $Text,
        '(?<!\*)\*([^*]+?)\*(?!\*)',
        "${esc}[3m`$1${esc}[23m"
    )

    return $Text
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

function Get-TodoItems {
    param(
        [string[]]$Lines
    )

    $items = [System.Collections.Generic.List[object]]::new()
    $stack = [System.Collections.Generic.List[object]]::new()
    $topLevelCount = 0

    for ($lineIndex = 0; $lineIndex -lt $Lines.Count; $lineIndex++) {
        $line = $Lines[$lineIndex]

        if ($line -notmatch '^(\s*)- \[([ xX])\] (.*)$') {
            continue
        }

        $indentText = $Matches[1]
        $statusText = $Matches[2]
        $taskText = $Matches[3]
        $indent = $indentText.Length

        while (
            $stack.Count -gt 0 -and
            $stack[$stack.Count - 1].Indent -ge $indent
        ) {
            $stack.RemoveAt($stack.Count - 1)
        }

        $parent = if ($stack.Count -gt 0) {
            $stack[$stack.Count - 1]
        }
        else {
            $null
        }

        if ($null -eq $parent) {
            $topLevelCount++
            $parts = @($topLevelCount)
        }
        else {
            $parts = @($parent.Parts + @($parent.Children.Count + 1))
        }

        $item = [pscustomobject]@{
            LineIndex        = $lineIndex
            Indent           = $indent
            Depth            = $stack.Count
            Parts            = $parts
            Number           = ($parts -join '.')
            Done             = $statusText -match '[xX]'
            Text             = $taskText
            Parent           = $parent
            Children         = @()
        }

        if ($null -ne $parent) {
            $parent.Children = @($parent.Children) + @($item)
        }

        $items.Add($item)
        $stack.Add($item)
    }

    return @($items)
}

function Get-TodoItemDescendants {
    param(
        [object]$Item,
        [object[]]$Items
    )

    return @(
        $Items | Where-Object {
            $current = $_.Parent
            $isDescendant = $false

            while ($null -ne $current) {
                if ($current.LineIndex -eq $Item.LineIndex) {
                    $isDescendant = $true
                    break
                }

                $current = $current.Parent
            }

            $isDescendant
        }
    )
}

function Get-TodoItemAncestors {
    param(
        [object]$Item
    )

    $ancestors = [System.Collections.Generic.List[object]]::new()
    $current = $Item.Parent

    while ($null -ne $current) {
        $ancestors.Insert(0, $current)
        $current = $current.Parent
    }

    return @($ancestors)
}

function Set-TodoItemStatus {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [object]$Item,
        [bool]$Done
    )

    $replacement = if ($Done) { '- [x]' } else { '- [ ]' }

    $Lines[$Item.LineIndex] = $Lines[$Item.LineIndex] -replace `
        '^(\s*)- \[[ xX]\]', `
        "`$1$replacement"

    $Item.Done = $Done
}

function Get-TodoTitle {
    param(
        [string]$Path
    )

    if (!(Test-Path $Path)) {
        return ""
    }

    $lines = @(Get-Content $Path)

    foreach ($line in $lines) {
        if ($line -match '^\s*#{1,6}\s+(.+?)\s*$') {
            return $matches[1]
        }
    }

    return ""
}


function Set-TodoTitle {
    param(
        [string]$Path,
        [string]$Title
    )

    if ([string]::IsNullOrWhiteSpace($Title)) {
        return
    }

    $Title = $Title.Trim()
    $lines = [System.Collections.Generic.List[string]](
        @(Get-Content $Path)
    )

    $headingIndex = -1

    for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
        if ($lines[$lineIndex] -match '^\s*#{1,6}\s+') {
            $headingIndex = $lineIndex
            break
        }
    }

    if ($headingIndex -ge 0) {
        $lines[$headingIndex] = "# $Title"
    }
    else {
        $lines.Insert(0, "")
        $lines.Insert(0, "# $Title")
    }

    $lines | Set-Content `
        $Path `
        -Encoding UTF8
}


function Confirm-TodoParentOperation {
    param(
        [object]$Item,
        [object[]]$Items,
        [string]$Action
    )

    $answer = Read-Host (
        "Parent {0} memiliki {1} child. {2} parent dan semua child? (y/N)" -f `
        $Item.Number,
        (Get-TodoItemDescendants -Item $Item -Items $Items).Count,
        $Action
    )

    return $answer -match '^(y|yes|ya)$'
}


function todo {

    param(
        [Parameter(Position=0)]
        [string]$Command,

        [Parameter(Position=1, ValueFromRemainingArguments=$true)]
        [string[]]$TodoArguments,

        [switch]$All,

        [Alias('t')]
        [string]$Title
    )


    $FileName = $Global:PSToolsLastTodoFile
    $showAll = $All.IsPresent

    if ($Command -eq "list" -and $null -ne $TodoArguments) {
        $allArgument = @($TodoArguments | Where-Object { $_ -eq "-a" -or $_ -eq "--all" })

        if ($allArgument.Count -gt 0) {
            $showAll = $true
            $TodoArguments = @($TodoArguments | Where-Object { $_ -ne "-a" -and $_ -ne "--all" })
        }
    }

    $titleArgument = $Title

    # Judul juga bisa ditulis sebagai satu token: -t=judul / --title=judul
    if (
        [string]::IsNullOrWhiteSpace($titleArgument) -and
        $null -ne $TodoArguments
    ) {

        $argumentsWithoutTitle = [System.Collections.Generic.List[string]]::new()

        foreach ($currentArgument in $TodoArguments) {

            if ($currentArgument -match '^-{1,2}t(?:itle)?=(.+)$') {
                $titleArgument = $matches[1]
                continue
            }

            $argumentsWithoutTitle.Add($currentArgument)
        }

        $TodoArguments = @($argumentsWithoutTitle)
    }

    # Judul juga bisa posisional (argumen terakhir) untuk add & add-child:
    #   todo add "task" namafile "judul"
    # Jumlah argumen harus persis, supaya teks task yang panjang & tanpa tanda
    # kutip tidak salah dipotong menjadi namafile + judul.
    $argumentsForPositionalTitle = switch ($Command) {
        "add"       { 3 }
        "add-child" { 4 }
        default     { 0 }
    }

    if (
        [string]::IsNullOrWhiteSpace($titleArgument) -and
        $argumentsForPositionalTitle -gt 0 -and
        $TodoArguments.Count -eq $argumentsForPositionalTitle
    ) {

        $fileCandidate = $TodoArguments[$TodoArguments.Count - 2]

        # Nama file harus tampak seperti nama file (tanpa spasi, tanpa '-' di depan)
        if ($fileCandidate -match '^[\w][\w.-]*$') {

            $titleArgument = $TodoArguments[$TodoArguments.Count - 1]
            $TodoArguments = @($TodoArguments[0..($TodoArguments.Count - 2)])
        }
    }

    # Nama file adalah argumen terakhir jika subperintah menerimanya.
    $minimumArgumentsForFile = switch ($Command) {
        "list"      { 1 }
        "done"      { 2 }
        "undone"    { 2 }
        "remove"    { 2 }
        "add"       { 2 }
        "add-child" { 3 }
        "open"      { 1 }
        "title"     { 1 }
        default     { 0 }
    }

    # todo title namafile "judul baru"
    if (
        $Command -eq "title" -and
        $TodoArguments.Count -ge 2
    ) {

        $FileName = $TodoArguments[0]

        if ([string]::IsNullOrWhiteSpace($titleArgument)) {
            $titleArgument = $TodoArguments[1]
        }

        $TodoArguments = @()
    }

    if (
        $minimumArgumentsForFile -gt 0 -and
        $TodoArguments.Count -ge $minimumArgumentsForFile
    ) {

        $FileName = $TodoArguments[$TodoArguments.Count - 1]

        if ($TodoArguments.Count -gt 1) {
            $TodoArguments = @($TodoArguments[0..($TodoArguments.Count - 2)])
        }
        else {
            $TodoArguments = @()
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
        Write-Host '  todo add "task" namafile'
        Write-Host '  todo add "task" namafile "judul"'
        Write-Host '  todo add "task" namafile -t "judul"'
        Write-Host '  todo add-child 1 "subtask" namafile'
        Write-Host '  todo list namafile'
        Write-Host '  todo list -a'
        Write-Host '  todo done 1 atau 1.1 namafile'
        Write-Host '  todo undone 1 atau 1.1 namafile'
        Write-Host '  todo remove 1 atau 1.1 namafile'
        Write-Host '  todo open namafile'
        Write-Host '  todo files'
        Write-Host '  todo title namafile "judul"'
        Write-Host ""
        Write-Host "JUDUL:"
        Write-Host '  Disimpan sebagai heading "# judul" di atas file.'
        Write-Host '  Posisional (hanya add/add-child) atau flag -t / --title.'
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

            $tasks = @(Get-TodoItems -Lines $lines)

            if ($tasks.Count -eq 0) {
                continue
            }

            $done = @(
                $tasks |
                Where-Object {
                    $_.Done
                }
            ).Count

            $undone = $tasks.Count - $done

            Write-Host ""
            Write-Host "[$($todoFile.BaseName)]" -ForegroundColor Yellow

            $fileTitle = Get-TodoTitle $todoFile.FullName

            if (
                ![string]::IsNullOrWhiteSpace($fileTitle)
            ) {
                Write-Host "  $fileTitle" -ForegroundColor DarkGray
            }

            Write-Host (
                "Total: {0} | Done: {1} | Undone: {2}" -f
                $tasks.Count,
                $done,
                $undone
            )

            Write-Host "────────────────────────────────────────"

            foreach ($item in $tasks) {
                $prefix = ('    ' * $item.Depth)
                $status = if ($item.Done) { 'x' } else { ' ' }
                $text = "{0}. [{1}] {2}" -f
                    $item.Number,
                    $status,
                    (Format-MarkdownText $item.Text)

                if ($item.Done) {
                    Write-Host "$prefix$text" -ForegroundColor Green
                }
                else {
                    Write-Host "$prefix$text"
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
    # SET TITLE
    # -----------------------------------------------------

    if (![string]::IsNullOrWhiteSpace($titleArgument)) {
        Set-TodoTitle -Path $file -Title $titleArgument
    }


    # -----------------------------------------------------
    # ADD
    # -----------------------------------------------------

    switch ($Command) {

        "add" {

            $Text = ($TodoArguments -join " ").Trim()

            if ([string]::IsNullOrWhiteSpace($Text)) {

                Write-Host ""
                Write-Host 'Usage: todo add "task" namafile'
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

            todo list $FileName
        }


        # -------------------------------------------------
        # ADD-CHILD
        # -------------------------------------------------

        "add-child" {

            if ($TodoArguments.Count -lt 2) {

                Write-Host ""
                Write-Host 'Usage: todo add-child <number> "task" namafile'
                Write-Host ""

                return
            }

            $number = $TodoArguments[0].Trim()

            if ($number -notmatch '^\d+(\.\d+)*$') {

                Write-Host "Nomor tidak valid."

                return
            }

            $Text = (Join-ArgsFrom $TodoArguments 1).Trim()

            if ([string]::IsNullOrWhiteSpace($Text)) {

                Write-Host ""
                Write-Host 'Usage: todo add-child <number> "task" namafile'
                Write-Host ""

                return
            }

            $lines = [System.Collections.Generic.List[string]](
                @(Get-Content $file)
            )

            $items = @(Get-TodoItems -Lines @($lines))
            $target = $items | Where-Object { $_.Number -eq $number } | Select-Object -First 1

            if ($null -eq $target) {

                Write-Host "Task tidak ditemukan."

                return
            }

            $descendants = @(Get-TodoItemDescendants -Item $target -Items $items)

            if ($descendants.Count -gt 0) {

                $insertIndex = (
                    $descendants |
                    Measure-Object -Property LineIndex -Maximum
                ).Maximum + 1
            }
            else {

                $insertIndex = $target.LineIndex + 1
            }

            $childIndent = ' ' * ($target.Indent + 2)

            $lines.Insert($insertIndex, "$childIndent- [ ] $Text")

            $lines | Set-Content `
                $file `
                -Encoding UTF8


            # POMO:
            # Child baru menjadi task aktif.
            Register-PomoTodoActivity `
                -FileName $FileName `
                -Task $Text


            Write-Host ""
            Write-Host "Ditambahkan child ke $number`: $Text" -ForegroundColor Green
            Write-Host "File: $FileName.md"

            todo list $FileName
        }


        # -------------------------------------------------
        # LIST
        # -------------------------------------------------

        "list" {

            if ($showAll) {
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
                    } |
                    Sort-Object Name
                )

                Write-Host ""
                Write-Host "SEMUA TODO" -ForegroundColor Cyan
                Write-Host "================================"

                $globalTotal = 0
                $globalDone = 0
                $emptyFiles = [System.Collections.Generic.List[object]]::new()
                $activeFiles = [System.Collections.Generic.List[object]]::new()
                $completedFiles = [System.Collections.Generic.List[object]]::new()

                foreach ($todoFile in $todoFiles) {
                    $todoLines = @(Get-Content $todoFile.FullName)
                    $todoTasks = @(Get-TodoItems -Lines $todoLines)

                    if ($todoTasks.Count -eq 0) {
                        $emptyFiles.Add($todoFile)
                        continue
                    }

                    $fileDone = @($todoTasks | Where-Object { $_.Done }).Count
                    $globalTotal += $todoTasks.Count
                    $globalDone += $fileDone

                    $fileSummary = [pscustomobject]@{
                        Name  = $todoFile.BaseName
                        Title = (Get-TodoTitle $todoFile.FullName)
                        Total = $todoTasks.Count
                        Done  = $fileDone
                    }

                    if ($fileDone -eq $todoTasks.Count) {
                        $completedFiles.Add($fileSummary)
                    }
                    else {
                        $activeFiles.Add($fileSummary)
                    }
                }

                foreach ($fileGroup in @(
                    [pscustomobject]@{ Title = "TODO BERJALAN"; Files = $activeFiles; Color = "Yellow" }
                    [pscustomobject]@{ Title = "TODO SELESAI (100%)"; Files = $completedFiles; Color = "Green" }
                )) {
                    if ($fileGroup.Files.Count -eq 0) {
                        continue
                    }

                    Write-Host ""
                    Write-Host $fileGroup.Title -ForegroundColor $fileGroup.Color
                    Write-Host "--------------------------------"

                    foreach ($fileSummary in $fileGroup.Files) {
                        Write-Host ""
                        Write-Host $fileSummary.Name -ForegroundColor $fileGroup.Color
                        if (
                            ![string]::IsNullOrWhiteSpace(
                                $fileSummary.Title
                            )
                        ) {
                            Write-Host (
                                "  {0}" -f $fileSummary.Title
                            ) -ForegroundColor DarkGray
                        }
                        Write-Host (
                            "Total: {0} | Done: {1} | Undone: {2}" -f
                            $fileSummary.Total,
                            $fileSummary.Done,
                            ($fileSummary.Total - $fileSummary.Done)
                        )
                        if ($fileSummary.Done -lt $fileSummary.Total) {
                            Show-TodoProgress `
                                -Total $fileSummary.Total `
                                -Done $fileSummary.Done
                        }
                    }
                }

                Write-Host ""
                Write-Host "TOTAL GABUNGAN" -ForegroundColor Cyan
                Write-Host "--------------------------------"

                if ($globalTotal -gt 0) {
                    Write-Host (
                        "Total: {0} | Done: {1} | Undone: {2}" -f
                        $globalTotal,
                        $globalDone,
                        ($globalTotal - $globalDone)
                    )
                    Show-TodoProgress -Total $globalTotal -Done $globalDone
                }
                else {
                    Write-Host "Belum ada task pada file TODO."
                }

                if ($emptyFiles.Count -gt 0) {
                    Write-Host ""
                    Write-Host "FILE KOSONG / TANPA CHECKLIST" -ForegroundColor DarkGray
                    foreach ($emptyFile in $emptyFiles) {
                        Write-Host "- $($emptyFile.BaseName).md" -ForegroundColor DarkGray
                    }
                }

                Write-Host ""
                return
            }

            $lines = @(Get-Content $file)
            $fileTitle = Get-TodoTitle $file

            Write-Host ""
            if ([string]::IsNullOrWhiteSpace($fileTitle)) {
                Write-Host "$FileName.md"
            }
            else {
                Write-Host "$FileName.md" -ForegroundColor DarkGray
                Write-Host $fileTitle -ForegroundColor Yellow
            }
            Write-Host "================================"

            # Hitung TODO termasuk child checklist.
            $tasks = @(Get-TodoItems -Lines $lines)

            $total = $tasks.Count

            if ($total -eq 0) {

                Write-Host "Belum ada task."
                Write-Host ""

                return
            }

            $done = @($tasks | Where-Object { $_.Done }).Count


            # Progress
            if ($total -gt 0) {

                Show-TodoProgress `
                    -Total $total `
                    -Done $done
            }

            Write-Host "--------------------------------"

            foreach ($item in $tasks) {
                $prefix = ('    ' * $item.Depth)
                $status = if ($item.Done) { 'x' } else { ' ' }
                $text = "{0}. [{1}] {2}" -f `
                    $item.Number, `
                    $status, `
                    (Format-MarkdownText $item.Text)

                if ($item.Done) {
                    Write-Host "$prefix$text" -ForegroundColor Green
                }
                else {
                    Write-Host "$prefix$text"
                }
            }

            Write-Host ""
        }


        # -------------------------------------------------
        # DONE
        # -------------------------------------------------

        "done" {

            if ($TodoArguments.Count -eq 0) {

                Write-Host "Usage: todo done <number> namafile"

                return
            }

            $number = $TodoArguments[0].Trim()

            if ($number -notmatch '^\d+(\.\d+)*$') {

                Write-Host "Nomor tidak valid."

                return
            }

            $lines = [System.Collections.Generic.List[string]](
                @(Get-Content $file)
            )

            $items = @(Get-TodoItems -Lines @($lines))
            $target = $items | Where-Object { $_.Number -eq $number } | Select-Object -First 1

            if ($null -eq $target) {

                Write-Host "Task tidak ditemukan."

                return
            }

            $descendants = @(Get-TodoItemDescendants -Item $target -Items $items)

            if (
                $target.Done -and
                @($descendants | Where-Object { !$_.Done }).Count -eq 0
            ) {
                Write-Host "Task sudah selesai."
                return
            }

            if ($descendants.Count -gt 0) {
                if (!(Confirm-TodoParentOperation -Item $target -Items $items -Action "Selesaikan")) {
                    Write-Host "Dibatalkan."
                    return
                }
            }

            $taskText = $target.Text

            foreach ($item in @($target) + $descendants) {
                Set-TodoItemStatus -Lines $lines -Item $item -Done $true
            }

            $ancestors = @(Get-TodoItemAncestors -Item $target)

            for ($ancestorIndex = $ancestors.Count - 1; $ancestorIndex -ge 0; $ancestorIndex--) {
                $ancestor = $ancestors[$ancestorIndex]

                if (@($ancestor.Children | Where-Object { !$_.Done }).Count -eq 0) {
                    Set-TodoItemStatus -Lines $lines -Item $ancestor -Done $true
                }
            }

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

            todo list $FileName
        }


        # -------------------------------------------------
        # UNDONE
        # -------------------------------------------------

        "undone" {

            if ($TodoArguments.Count -eq 0) {

                Write-Host "Usage: todo undone <number> namafile"

                return
            }

            $number = $TodoArguments[0].Trim()

            if ($number -notmatch '^\d+(\.\d+)*$') {

                Write-Host "Nomor tidak valid."

                return
            }

            $lines = [System.Collections.Generic.List[string]](
                @(Get-Content $file)
            )

            $items = @(Get-TodoItems -Lines @($lines))
            $target = $items | Where-Object { $_.Number -eq $number } | Select-Object -First 1

            if ($null -eq $target) {

                Write-Host "Task tidak ditemukan."

                return
            }

            $descendants = @(Get-TodoItemDescendants -Item $target -Items $items)

            if (
                !$target.Done -and
                @($descendants | Where-Object { $_.Done }).Count -eq 0
            ) {
                Write-Host "Task belum selesai."
                return
            }

            if ($descendants.Count -gt 0) {
                if (!(Confirm-TodoParentOperation -Item $target -Items $items -Action "Kembalikan ke belum selesai")) {
                    Write-Host "Dibatalkan."
                    return
                }
            }

            $taskText = $target.Text

            foreach ($item in @($target) + $descendants) {
                Set-TodoItemStatus -Lines $lines -Item $item -Done $false
            }

            foreach ($ancestor in @(Get-TodoItemAncestors -Item $target)) {
                Set-TodoItemStatus -Lines $lines -Item $ancestor -Done $false
            }

            $lines | Set-Content `
                $file `
                -Encoding UTF8

            Register-PomoTodoActivity `
                -FileName $FileName `
                -Task $taskText


            Write-Host `
                "Task $number dikembalikan." `
                -ForegroundColor Yellow

            todo list $FileName
        }


        # -------------------------------------------------
        # REMOVE
        # -------------------------------------------------

        "remove" {

            if ($TodoArguments.Count -eq 0) {

                Write-Host "Usage: todo remove <number> namafile"

                return
            }

            $number = $TodoArguments[0].Trim()

            if ($number -notmatch '^\d+(\.\d+)*$') {

                Write-Host "Nomor tidak valid."

                return
            }

            $lines = [System.Collections.Generic.List[string]](
                @(Get-Content $file)
            )

            $items = @(Get-TodoItems -Lines @($lines))
            $target = $items | Where-Object { $_.Number -eq $number } | Select-Object -First 1

            if ($null -eq $target) {

                Write-Host "Task tidak ditemukan."

                return
            }


            $task = $lines[$target.LineIndex]
            $taskText = $target.Text
            $descendants = @(Get-TodoItemDescendants -Item $target -Items $items)


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


            $lineIndexes = @(
                @($target) + $descendants |
                    ForEach-Object { $_.LineIndex } |
                    Sort-Object -Descending
            )

            foreach ($lineIndex in $lineIndexes) {
                $lines.RemoveAt($lineIndex)
            }

            $lines | Set-Content `
                $file `
                -Encoding UTF8


            Write-Host `
                "Dihapus: $task" `
                -ForegroundColor Green

            todo list $FileName
        }


        # -------------------------------------------------
        # OPEN
        # -------------------------------------------------

        "open" {

            $editor = if (
                ![string]::IsNullOrWhiteSpace($Global:PSToolsTodoEditor)
            ) {
                $Global:PSToolsTodoEditor
            }
            else {
                "vim"
            }

            $editorCommand = Get-Command $editor -ErrorAction SilentlyContinue

            if ($null -eq $editorCommand) {
                Write-Host ""
                Write-Host "Editor '$editor' tidak ditemukan." -ForegroundColor Yellow
                Write-Host 'Set editor lain dengan: $Global:PSToolsTodoEditor = "kode"'
                Write-Host ""
                return
            }

            Write-Host ""
            Write-Host "Membuka $FileName.md di $editor..." -ForegroundColor Cyan
            Write-Host ""

            & $editorCommand $file
        }


        # -------------------------------------------------
        # TITLE
        # -------------------------------------------------

        "title" {

            $currentTitle = Get-TodoTitle $file

            if ([string]::IsNullOrWhiteSpace($titleArgument)) {

                Write-Host ""

                if (
                    [string]::IsNullOrWhiteSpace(
                        $currentTitle
                    )
                ) {
                    Write-Host `
                        "$FileName.md belum punya judul." `
                        -ForegroundColor Yellow

                    Write-Host (
                        'Set dengan: todo title {0} "judul"' -f
                        $FileName
                    )
                }
                else {
                    Write-Host `
                        "$FileName.md" `
                        -ForegroundColor DarkGray

                    Write-Host $currentTitle -ForegroundColor Yellow
                }

                Write-Host ""

                return
            }

            Set-TodoTitle -Path $file -Title $titleArgument

            Write-Host ""
            Write-Host `
                "Judul $FileName.md disetel: $titleArgument" `
                -ForegroundColor Green
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

    # Nama file adalah argumen terakhir jika subperintah menerimanya.
    $minimumArgumentsForFile = switch ($Command) {
        "list"  { 1 }
        "view"  { 2 }
        "rm"    { 2 }
        "add"   { 3 }
        default { 0 }
    }

    if ($Arguments.Count -ge $minimumArgumentsForFile) {
        $FileName = $Arguments[$Arguments.Count - 1]

        if ($Arguments.Count -gt 1) {
            $Arguments = @($Arguments[0..($Arguments.Count - 2)])
        }
        else {
            $Arguments = @()
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
        Write-Host 'note add "judul" "isi catatan" namafile'
        Write-Host 'note list namafile'
        Write-Host 'note view 1 namafile'
        Write-Host 'note rm 1 namafile'
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
                    'Usage: note add "judul" "isi" namafile'

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
                    "Usage: note view <number> namafile"

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
                    "Usage: note rm <number> namafile"

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
        Write-Host "  todo list notes"
        Write-Host "  todo done 1 notes"
        Write-Host "  todo list project"
        Write-Host "  todo done 2 project"
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
