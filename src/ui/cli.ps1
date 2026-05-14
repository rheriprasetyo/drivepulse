<#
.SYNOPSIS
    DrivePulse — CLI Menu Interaktif
.DESCRIPTION
    Menu interaktif untuk user yang jalanin DrivePulse dari terminal.
    Navigasi pakai angka, output berwarna, Bahasa Indonesia.
.NOTES
    Author: DrivePulse Team
    Version: 1.1
#>

# Import modules
. "$PSScriptRoot\..\scanner\scan.ps1"
. "$PSScriptRoot\..\scanner\categorize.ps1"

# ─── Formatting Functions ───────────────────────────────────

function Format-Size {
    <#
    .SYNOPSIS Formats bytes to human-readable GB or MB
    .PARAMETER Bytes Size in bytes
    .OUTPUTS [string] Formatted size string (e.g., "2.5 GB" or "350 MB")
    #>
    param([long]$Bytes)

    if ($Bytes -ge 1073741824) {
        # >= 1 GB: show as X.X GB (1 decimal place)
        $gb = [math]::Round($Bytes / 1073741824, 1)
        return "$gb GB"
    }
    else {
        # < 1 GB: show as X MB (no decimal, rounded)
        $mb = [math]::Round($Bytes / 1048576)
        return "$mb MB"
    }
}

# ─── Drive Status Display ──────────────────────────────────

function Show-DriveStatus {
    <#
    .SYNOPSIS Displays drive usage bar and statistics
    .PARAMETER ScanResult The DrivePulse.ScanResult object
    #>
    param([PSCustomObject]$ScanResult)

    $usagePercent = $ScanResult.UsagePercent
    $totalGB = [math]::Round($ScanResult.TotalBytes / 1073741824, 1)
    $usedGB = [math]::Round($ScanResult.UsedBytes / 1073741824, 1)
    $freeGB = [math]::Round($ScanResult.FreeBytes / 1073741824, 1)

    # Determine color based on usage percentage
    if ($usagePercent -ge 90) {
        $barColor = "Red"
    }
    elseif ($usagePercent -ge 75) {
        $barColor = "Yellow"
    }
    else {
        $barColor = "Green"
    }

    # Build visual usage bar (30 characters wide)
    $barWidth = 30
    $filledCount = [math]::Round(($usagePercent / 100) * $barWidth)
    if ($filledCount -gt $barWidth) { $filledCount = $barWidth }
    $emptyCount = $barWidth - $filledCount

    $filledBar = [string]::new([char]0x2588, $filledCount)
    $emptyBar = [string]::new([char]0x2591, $emptyCount)

    # Display header
    Write-Host ""
    Write-Host "  Drive $($ScanResult.DriveLetter): Status" -ForegroundColor White

    # Display usage bar with color coding
    Write-Host -NoNewline "  ["
    Write-Host -NoNewline $filledBar -ForegroundColor $barColor
    Write-Host -NoNewline $emptyBar -ForegroundColor DarkGray
    Write-Host "] $usagePercent%"

    # Display statistics in Bahasa Indonesia
    Write-Host "  Total   : $totalGB GB" -ForegroundColor White
    Write-Host "  Terpakai: $usedGB GB" -ForegroundColor $barColor
    Write-Host "  Tersedia: $freeGB GB" -ForegroundColor Green
    Write-Host ""
}

# ─── Scan Results Display (Task 6.2) ──────────────────────

function Show-ScanResults {
    <#
    .SYNOPSIS Displays categorized scan results with colors
    .DESCRIPTION Groups items into "Aman Dihapus" (green) and "Perlu Dicek Manual" (yellow)
                 sections. Shows label, size, and metadata per item. Displays summary totals.
    .PARAMETER ScanResult The DrivePulse.ScanResult object
    .PARAMETER CategorizedItems Array of DrivePulse.CategorizedItem
    #>
    param(
        [PSCustomObject]$ScanResult,
        [PSCustomObject[]]$CategorizedItems
    )

    # Dry-Run label (Requirement 4.1, 4.3)
    Write-Host ""
    Write-Host "  [MODE: DRY-RUN — tidak ada file yang dihapus]" -ForegroundColor Cyan
    Write-Host ""

    # Separate items by category
    $safeItems = @($CategorizedItems | Where-Object { $_.Category -eq [ItemCategory]::Safe })
    $checkItems = @($CategorizedItems | Where-Object { $_.Category -eq [ItemCategory]::Check })

    # Section: Aman Dihapus (Safe) — green (Requirement 8.3, 8.4)
    Write-Host "  === Aman Dihapus ===" -ForegroundColor Green
    Write-Host ""

    if ($safeItems.Count -eq 0) {
        Write-Host "    Tidak ada item yang aman dihapus." -ForegroundColor Gray
    }
    else {
        foreach ($safeItem in $safeItems) {
            $sizeStr = Format-Size $safeItem.SizeBytes
            Write-Host "    $($safeItem.Label)" -ForegroundColor Green -NoNewline
            Write-Host " — $sizeStr" -ForegroundColor White
            if ($safeItem.SideEffect) {
                Write-Host "      Efek samping: $($safeItem.SideEffect)" -ForegroundColor Gray
            }
        }
    }

    Write-Host ""

    # Section: Perlu Dicek Manual (Check) — yellow (Requirement 8.3, 8.5)
    Write-Host "  === Perlu Dicek Manual ===" -ForegroundColor Yellow
    Write-Host ""

    if ($checkItems.Count -eq 0) {
        Write-Host "    Tidak ada item yang perlu dicek manual." -ForegroundColor Gray
    }
    else {
        foreach ($checkItem in $checkItems) {
            $sizeStr = Format-Size $checkItem.SizeBytes
            Write-Host "    $($checkItem.Label)" -ForegroundColor Yellow -NoNewline
            Write-Host " — $sizeStr" -ForegroundColor White
            if ($checkItem.Reason) {
                Write-Host "      Alasan: $($checkItem.Reason)" -ForegroundColor Gray
            }
            if ($checkItem.Recommendation) {
                Write-Host "      Saran: $($checkItem.Recommendation)" -ForegroundColor Gray
            }
        }
    }

    Write-Host ""

    # Summary totals (Requirement 8.6)
    $totalSafeBytes = ($safeItems | Measure-Object -Property SizeBytes -Sum).Sum
    if (-not $totalSafeBytes) { $totalSafeBytes = 0 }
    $totalCheckBytes = ($checkItems | Measure-Object -Property SizeBytes -Sum).Sum
    if (-not $totalCheckBytes) { $totalCheckBytes = 0 }

    Write-Host "  --- Ringkasan ---" -ForegroundColor White
    Write-Host "    Bisa diklaim kembali : $(Format-Size $totalSafeBytes)" -ForegroundColor Green
    Write-Host "    Perlu review manual  : $(Format-Size $totalCheckBytes)" -ForegroundColor Yellow
    Write-Host ""
}

# ─── Error Summary Display (Task 6.2) ─────────────────────

function Show-ErrorSummary {
    <#
    .SYNOPSIS Shows count of skipped folders, offers to show full list
    .DESCRIPTION Displays how many folders were skipped due to access denied errors.
                 Offers user the option to see the full list of skipped paths.
    .PARAMETER Errors Array of DrivePulse.ScanError objects
    #>
    param([PSCustomObject[]]$Errors)

    # Return early if no errors (Requirement 6.3)
    if (-not $Errors -or $Errors.Count -eq 0) {
        return
    }

    # Display count of skipped folders
    Write-Host ""
    Write-Host "  ⚠️ $($Errors.Count) folder dilewati karena akses ditolak" -ForegroundColor Yellow
    Write-Host ""

    # Offer to show full list on user request (Requirement 6.3)
    $response = Read-Host "  Mau lihat daftar lengkapnya? (y/n)"

    if ($response -eq 'y' -or $response -eq 'Y') {
        Write-Host ""
        Write-Host "  Folder yang dilewati:" -ForegroundColor Yellow
        foreach ($errItem in $Errors) {
            Write-Host "    - $($errItem.Path)" -ForegroundColor Gray
            if ($errItem.Message) {
                Write-Host "      $($errItem.Message)" -ForegroundColor DarkGray
            }
        }
        Write-Host ""
    }
}

# ─── Progress Display (Task 6.3) ──────────────────────────

function Show-Progress {
    <#
    .SYNOPSIS Displays scan progress (current folder + percentage)
    .PARAMETER CurrentPath Folder currently being scanned
    .PARAMETER PercentComplete Estimated completion (0-100)
    .PARAMETER Mode Quick or Deep (affects display style)
    #>
    param(
        [string]$CurrentPath,
        [int]$PercentComplete,
        [string]$Mode = "Quick"
    )

    if ($Mode -eq "Quick") {
        # Quick Scan: display name of current location being scanned
        $displayPath = $CurrentPath
        if ($displayPath.Length -gt 60) {
            $displayPath = $displayPath.Substring(0, 57) + "..."
        }
        # Overwrite current line using carriage return
        Write-Host "`r                                                                              " -NoNewline
        Write-Host "`rMemeriksa: $displayPath" -NoNewline -ForegroundColor Cyan
    }
    else {
        # Deep Scan: display text-based progress bar with percentage and folder path
        $barWidth = 20
        $filledCount = [math]::Floor($PercentComplete / (100 / $barWidth))
        if ($filledCount -gt $barWidth) { $filledCount = $barWidth }
        if ($filledCount -lt 0) { $filledCount = 0 }
        $emptyCount = $barWidth - $filledCount

        $filledBar = "#" * $filledCount
        $emptyBar = "-" * $emptyCount
        $progressBar = "[$filledBar$emptyBar]"

        # Truncate path for display
        $displayPath = $CurrentPath
        if ($displayPath.Length -gt 40) {
            $displayPath = $displayPath.Substring(0, 37) + "..."
        }

        # Overwrite current line using carriage return
        Write-Host "`r                                                                              " -NoNewline
        Write-Host "`r$progressBar $PercentComplete% - $displayPath" -NoNewline -ForegroundColor Cyan
    }
}

function Show-ElapsedTime {
    <#
    .SYNOPSIS Displays total elapsed scan time
    .PARAMETER ElapsedSeconds Time taken for the scan in seconds
    #>
    param(
        [double]$ElapsedSeconds
    )

    # Clear the progress line and move to new line
    Write-Host "`r                                                                              " -NoNewline
    Write-Host ""
    $rounded = [math]::Round($ElapsedSeconds, 1)
    Write-Host "Waktu scan: $rounded detik" -ForegroundColor Green
}

# ─── Admin Info Message (Task 6.4 / Requirement 6.4) ──────

function Show-AdminInfoMessage {
    <#
    .SYNOPSIS Displays a one-time informational message when not running as admin
    .DESCRIPTION Shows a friendly Bahasa Indonesia message explaining that some folders
                 may not be accessible without administrator privileges.
    #>
    Write-Host ""
    Write-Host "  Info: Kamu menjalankan DrivePulse tanpa hak Administrator." -ForegroundColor Cyan
    Write-Host "        Beberapa folder mungkin tidak bisa diakses. Jalankan sebagai Admin untuk hasil lebih lengkap." -ForegroundColor Cyan
    Write-Host ""
}

# ─── Main Menu (Task 6.4) ─────────────────────────────────

function Show-MainMenu {
    <#
    .SYNOPSIS Displays the main menu and handles user selection
    .DESCRIPTION Interactive menu loop with options for Quick Scan, Deep Scan,
                 Bantuan (Help), and Keluar (Exit). All text in Bahasa Indonesia.
    #>

    # Determine admin status
    $isAdmin = $false
    try {
        $isAdmin = ([Security.Principal.WindowsPrincipal] `
            [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        $isAdmin = $false
    }

    # Rules file path (src/ui/../../config/default-rules.json = project root/config/default-rules.json)
    $rulesFile = "$PSScriptRoot\..\..\config\default-rules.json"

    do {
        # Display banner/header
        Write-Host ""
        Write-Host "  +======================================+" -ForegroundColor Cyan
        Write-Host "  |         DrivePulse v1.1              |" -ForegroundColor Cyan
        Write-Host "  |   Pembersih Drive Cerdas untuk PC    |" -ForegroundColor Cyan
        Write-Host "  +======================================+" -ForegroundColor Cyan
        Write-Host ""

        # Display menu options
        Write-Host "  [1] Quick Scan  -- Scan cepat lokasi umum" -ForegroundColor White
        Write-Host "  [2] Deep Scan   -- Scan mendalam seluruh drive" -ForegroundColor White
        Write-Host "  [3] Bantuan     -- Cara pakai DrivePulse" -ForegroundColor White
        Write-Host "  [4] Keluar      -- Tutup aplikasi" -ForegroundColor White
        Write-Host ""

        # Read user input
        $choice = Read-Host "  Pilih menu (1-4)"

        switch ($choice) {
            "1" {
                # Quick Scan
                Write-Host ""
                Write-Host "  Memulai Quick Scan..." -ForegroundColor Green
                Write-Host ""

                # Initialize rules
                $rules = Initialize-Rules -RulesFile $rulesFile

                # Define progress callback for Quick Scan
                $progressCb = {
                    param($currentPath, $currentIndex, $totalEntries)
                    $percent = [math]::Round(($currentIndex / [math]::Max($totalEntries, 1)) * 100)
                    Show-Progress -CurrentPath $currentPath -PercentComplete $percent -Mode "Quick"
                }

                # Run scan
                $scanResult = Start-DriveScan -Mode Quick -ProgressCallback $progressCb

                # Show elapsed time
                Show-ElapsedTime -ElapsedSeconds $scanResult.ElapsedSeconds

                # Show drive status
                Show-DriveStatus -ScanResult $scanResult

                # Categorize results
                $categorized = Get-AllCategories -ScanResult $scanResult -Rules $rules -IsAdmin $isAdmin

                # Show scan results
                Show-ScanResults -ScanResult $scanResult -CategorizedItems $categorized

                # Show error summary if any
                Show-ErrorSummary -Errors $scanResult.Errors

                # Wait for user to press Enter
                Write-Host ""
                Read-Host "  Tekan Enter untuk kembali ke menu"
            }
            "2" {
                # Deep Scan
                Write-Host ""
                Write-Host "  Memulai Deep Scan... (ini bisa memakan waktu beberapa menit)" -ForegroundColor Green
                Write-Host ""

                # Initialize rules
                $rules = Initialize-Rules -RulesFile $rulesFile

                # Define progress callback for Deep Scan
                $progressCb = {
                    param($currentPath, $percent)
                    Show-Progress -CurrentPath $currentPath -PercentComplete $percent -Mode "Deep"
                }

                # Run scan
                $scanResult = Start-DriveScan -Mode Deep -ProgressCallback $progressCb

                # Show elapsed time
                Show-ElapsedTime -ElapsedSeconds $scanResult.ElapsedSeconds

                # Show drive status
                Show-DriveStatus -ScanResult $scanResult

                # Categorize results
                $categorized = Get-AllCategories -ScanResult $scanResult -Rules $rules -IsAdmin $isAdmin

                # Show scan results
                Show-ScanResults -ScanResult $scanResult -CategorizedItems $categorized

                # Show error summary if any
                Show-ErrorSummary -Errors $scanResult.Errors

                # Wait for user to press Enter
                Write-Host ""
                Read-Host "  Tekan Enter untuk kembali ke menu"
            }
            "3" {
                # Bantuan (Help)
                Write-Host ""
                Write-Host "  +======================================+" -ForegroundColor Cyan
                Write-Host "  |           Bantuan DrivePulse         |" -ForegroundColor Cyan
                Write-Host "  +======================================+" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "  Apa itu DrivePulse?" -ForegroundColor White
                Write-Host "    DrivePulse adalah alat untuk menganalisis penggunaan" -ForegroundColor Gray
                Write-Host "    disk kamu dan menemukan file/folder yang bisa dihapus" -ForegroundColor Gray
                Write-Host "    dengan aman untuk menghemat ruang penyimpanan." -ForegroundColor Gray
                Write-Host ""
                Write-Host "  Cara Pakai:" -ForegroundColor White
                Write-Host "    1. Pilih Quick Scan untuk scan cepat lokasi umum" -ForegroundColor Gray
                Write-Host "       (cache browser, temp files, dll)" -ForegroundColor Gray
                Write-Host "    2. Pilih Deep Scan untuk scan mendalam seluruh drive" -ForegroundColor Gray
                Write-Host "       (menemukan folder besar tersembunyi)" -ForegroundColor Gray
                Write-Host ""
                Write-Host "  Kategori Hasil:" -ForegroundColor White
                Write-Host "    Hijau (Aman Dihapus)  : File yang bisa dihapus tanpa risiko" -ForegroundColor Green
                Write-Host "    Kuning (Perlu Dicek)  : File yang perlu kamu cek dulu" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "  Catatan Penting:" -ForegroundColor White
                Write-Host "    - DrivePulse TIDAK menghapus file apapun (mode dry-run)" -ForegroundColor Gray
                Write-Host "    - Jalankan sebagai Administrator untuk hasil lebih lengkap" -ForegroundColor Gray
                Write-Host "    - Hasil scan berdasarkan aturan di config/default-rules.json" -ForegroundColor Gray
                Write-Host ""

                # Wait for user to press Enter
                Read-Host "  Tekan Enter untuk kembali ke menu"
            }
            "4" {
                # Keluar (Exit)
                Write-Host ""
                Write-Host "  Terima kasih sudah pakai DrivePulse! Sampai jumpa." -ForegroundColor Green
                Write-Host ""
                return
            }
            default {
                # Invalid input
                Write-Host ""
                Write-Host "  Pilihan tidak valid. Silakan pilih 1-4." -ForegroundColor Red
                Write-Host ""
            }
        }
    } while ($true)
}
