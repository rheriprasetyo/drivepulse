<#
.SYNOPSIS
    DrivePulse - Cleanup Execution Module (Orchestrator)
.DESCRIPTION
    Orkestrasi pembersihan file/folder yang dikategorikan aman.
    Alur: dry-run preview > konfirmasi > purge expired > stage > progress > summary.
    Default mode adalah DRY-RUN (tidak ada modifikasi filesystem).
    Hanya memproses item dengan kategori "Safe" atau "Aman Dihapus".
.NOTES
    Author: DrivePulse Team
    Version: 1.3
    Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 2.1, 2.2, 2.3, 2.4, 2.5, 3.1, 3.2, 3.3, 3.4, 3.5, 9.6, 10.4
#>

# Dot-source dependencies
$auditPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'audit\audit.ps1'
if (Test-Path $auditPath) {
    . $auditPath
}

$stagingModulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'staging\staging.ps1'
if (Test-Path $stagingModulePath) {
    . $stagingModulePath
}

# --- Helper Functions ---

function New-SessionId {
    <#
    .SYNOPSIS
        Menghasilkan session ID unik dengan format YYYYMMDD-HHmmss-<6 hex>.
    .OUTPUTS
        [string] Session ID unik
    #>
    $datePart = Get-Date -Format 'yyyyMMdd-HHmmss'
    $hexPart = -join ((1..6) | ForEach-Object { '{0:x}' -f (Get-Random -Minimum 0 -Maximum 16) })
    return "$datePart-$hexPart"
}

function Format-TruncatedPath {
    <#
    .SYNOPSIS
        Memotong path ke maksimum 60 karakter dengan "..." di akhir jika lebih panjang.
    .PARAMETER Path
        Path yang akan diformat
    .OUTPUTS
        [string] Path yang sudah dipotong
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if ($Path.Length -gt 60) {
        return $Path.Substring(0, 60) + '...'
    }
    return $Path
}

function Format-FileSize {
    <#
    .SYNOPSIS
        Mengkonversi ukuran bytes ke format yang mudah dibaca.
    .PARAMETER Bytes
        Ukuran dalam bytes
    .OUTPUTS
        [string] Ukuran dalam format human-readable (B, KB, MB, GB)
    #>
    param(
        [Parameter(Mandatory)]
        [long]$Bytes
    )

    if ($Bytes -ge 1GB) {
        return '{0:N2} GB' -f ($Bytes / 1GB)
    }
    elseif ($Bytes -ge 1MB) {
        return '{0:N2} MB' -f ($Bytes / 1MB)
    }
    elseif ($Bytes -ge 1KB) {
        return '{0:N2} KB' -f ($Bytes / 1KB)
    }
    else {
        return "$Bytes B"
    }
}

function Test-SafeCategory {
    <#
    .SYNOPSIS
        Memeriksa apakah item memiliki kategori "Safe" atau "Aman Dihapus".
    .PARAMETER Item
        Item yang akan diperiksa
    .OUTPUTS
        [bool] $true jika kategori aman
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Item
    )

    $category = $Item.Category
    return ($category -eq 'Safe' -or $category -eq 'Aman Dihapus')
}

# --- Core Functions ---

function Get-CleanupPreview {
    <#
    .SYNOPSIS
        Menghasilkan preview item yang akan dibersihkan.
    .DESCRIPTION
        Menghitung total item, total ukuran, dan detail per-item
        untuk ditampilkan sebelum eksekusi cleanup.
    .PARAMETER Items
        Array CategorizedItem objects dari scanner
    .OUTPUTS
        [PSCustomObject] PreviewResult dengan ItemCount, TotalSize, TotalSizeFormatted, ItemList
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject[]]$Items
    )

    $totalSize = [long]0
    $itemList = @()

    foreach ($item in $Items) {
        $sizeBytes = 0
        if ($item.PSObject.Properties['SizeBytes']) {
            $sizeBytes = $item.SizeBytes
        }
        elseif ($item.PSObject.Properties['Size']) {
            $sizeBytes = $item.Size
        }

        $totalSize += $sizeBytes

        $itemList += [PSCustomObject]@{
            Path          = $item.Path
            Size          = $sizeBytes
            SizeFormatted = Format-FileSize -Bytes $sizeBytes
            Category      = $item.Category
        }
    }

    return [PSCustomObject]@{
        ItemCount          = $Items.Count
        TotalSize          = $totalSize
        TotalSizeFormatted = Format-FileSize -Bytes $totalSize
        ItemList           = $itemList
    }
}

function Show-CleanupProgress {
    <#
    .SYNOPSIS
        Menampilkan progress pembersihan item saat ini.
    .DESCRIPTION
        Menampilkan path yang dipotong (60 karakter + "..."), persentase,
        dan ruang yang sudah dibebaskan secara kumulatif.
    .PARAMETER CurrentPath
        Path item yang sedang diproses
    .PARAMETER CurrentIndex
        Index item saat ini (0-based)
    .PARAMETER TotalItems
        Total jumlah item yang akan diproses
    .PARAMETER SpaceFreedSoFar
        Total ruang yang sudah dibebaskan (bytes)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$CurrentPath,

        [Parameter(Mandatory)]
        [int]$CurrentIndex,

        [Parameter(Mandatory)]
        [int]$TotalItems,

        [Parameter(Mandatory)]
        [long]$SpaceFreedSoFar
    )

    $truncatedPath = Format-TruncatedPath -Path $CurrentPath
    $percentage = [Math]::Floor(($CurrentIndex + 1) / $TotalItems * 100)
    $freedFormatted = Format-FileSize -Bytes $SpaceFreedSoFar

    Write-Host "  [$percentage%] $truncatedPath - Dibebaskan: $freedFormatted" -ForegroundColor Cyan
}

function Start-SafeCleanup {
    <#
    .SYNOPSIS
        Menjalankan proses pembersihan yang aman.
    .DESCRIPTION
        Orkestrasi lengkap: dry-run preview > konfirmasi > purge expired >
        stage > progress > summary.
        Default mode adalah DRY-RUN (tidak ada modifikasi filesystem).
        Hanya memproses item dengan kategori "Safe" atau "Aman Dihapus".
    .PARAMETER Items
        Array CategorizedItem objects dari scanner
    .PARAMETER DryRun
        Mode dry-run (default). Tidak ada modifikasi filesystem.
    .PARAMETER Force
        Skip konfirmasi (untuk scripting)
    .PARAMETER SessionId
        ID session opsional. Jika tidak diberikan, akan di-generate otomatis.
    .OUTPUTS
        [PSCustomObject] CleanupResult
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject[]]$Items,

        [switch]$DryRun,

        [switch]$Force,

        [string]$SessionId
    )

    # Default: DRY-RUN mode jika tidak ada switch eksplisit
    # Jika -Force diberikan, eksekusi langsung (skip dry-run dan konfirmasi)
    # Jika -DryRun:$false diberikan secara eksplisit, masuk mode eksekusi dengan konfirmasi
    # Jika tidak ada parameter, default ke DryRun
    $isDryRun = $true
    if ($Force) {
        $isDryRun = $false
    }
    elseif ($PSBoundParameters.ContainsKey('DryRun')) {
        $isDryRun = $DryRun.IsPresent
    }

    # Filter hanya item "Safe" / "Aman Dihapus" (Req 10.4)
    $safeItems = @($Items | Where-Object { Test-SafeCategory -Item $_ })

    # Cek jika tidak ada item (Req 1.7, 2.5)
    if ($safeItems.Count -eq 0) {
        Write-Host "`n  Tidak ada item yang memenuhi syarat untuk dibersihkan." -ForegroundColor Yellow
        return [PSCustomObject]@{
            SessionId      = $null
            ItemsProcessed = 0
            SpaceFreed     = [long]0
            Errors         = @()
            ErrorCount     = 0
            ElapsedSeconds = 0
            Status         = 'empty'
        }
    }

    # Preview (Req 1.2, 1.4, 2.1)
    $preview = Get-CleanupPreview -Items $safeItems

    Write-Host "`n  === Pratinjau Pembersihan ===" -ForegroundColor Green
    Write-Host "  Total item  : $($preview.ItemCount)" -ForegroundColor White
    Write-Host "  Total ukuran: $($preview.TotalSizeFormatted) ($($preview.TotalSize) bytes)" -ForegroundColor White
    Write-Host ""

    # Tampilkan detail per-item dengan nomor (maks 1000) (Req 1.2)
    $displayCount = [Math]::Min($preview.ItemList.Count, 1000)
    for ($i = 0; $i -lt $displayCount; $i++) {
        $item = $preview.ItemList[$i]
        $truncPath = Format-TruncatedPath -Path $item.Path
        $num = $i + 1
        $line = "    [$num] $truncPath - $($item.SizeFormatted) [$($item.Category)]"
        Write-Host $line -ForegroundColor Gray
    }

    if ($preview.ItemList.Count -gt 1000) {
        $remaining = $preview.ItemList.Count - 1000
        Write-Host "    ... dan $remaining item lainnya" -ForegroundColor DarkGray
    }

    Write-Host ""

    # DRY-RUN: preview dulu, lalu tanya konfirmasi (Req 1.5)
    if ($isDryRun) {
        Write-Host "  Mode: DRY-RUN - tidak ada file yang dimodifikasi." -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Pilihan:" -ForegroundColor Yellow
        Write-Host "    [a] Bersihkan semua item" -ForegroundColor White
        Write-Host "    [s] Pilih item tertentu (masukkan nomor, pisah koma)" -ForegroundColor White
        Write-Host "    [n] Batal" -ForegroundColor White
        Write-Host ""
        $confirmation = Read-Host "  Ketik pilihan (a/s/n)"

        if ($confirmation -eq 'a' -or $confirmation -eq 'A' -or $confirmation -eq 'y' -or $confirmation -eq 'Y') {
            # Lanjutkan dengan semua item
            Write-Host "  Beralih ke mode eksekusi (semua item)..." -ForegroundColor Green
            $isDryRun = $false
        }
        elseif ($confirmation -eq 's' -or $confirmation -eq 'S') {
            # User memilih item tertentu
            Write-Host ""
            $selection = Read-Host "  Masukkan nomor item (pisah koma, contoh: 1,3,5)"

            # Parse nomor yang dipilih
            $selectedIndices = @()
            foreach ($part in ($selection -split ',')) {
                $trimmed = $part.Trim()
                $num = 0
                if ([int]::TryParse($trimmed, [ref]$num)) {
                    if ($num -ge 1 -and $num -le $safeItems.Count) {
                        $selectedIndices += ($num - 1)  # Convert ke 0-based index
                    }
                    else {
                        Write-Warning "  Nomor '$num' di luar jangkauan (1-$($safeItems.Count)), dilewati."
                    }
                }
            }

            if ($selectedIndices.Count -eq 0) {
                Write-Host "`n  Tidak ada item valid yang dipilih. Pembersihan dibatalkan." -ForegroundColor Yellow
                return [PSCustomObject]@{
                    SessionId      = $null
                    ItemsProcessed = 0
                    SpaceFreed     = [long]0
                    Errors         = @()
                    ErrorCount     = 0
                    ElapsedSeconds = 0
                    Status         = 'cancelled'
                }
            }

            # Filter safeItems berdasarkan pilihan user
            $safeItems = @($selectedIndices | ForEach-Object { $safeItems[$_] })

            # Recalculate preview untuk item terpilih
            $preview = Get-CleanupPreview -Items $safeItems

            Write-Host ""
            Write-Host "  Item terpilih: $($safeItems.Count) ($($preview.TotalSizeFormatted))" -ForegroundColor Green
            Write-Host "  Beralih ke mode eksekusi..." -ForegroundColor Green
            $isDryRun = $false
        }
        else {
            Write-Host "`n  Pembersihan dibatalkan." -ForegroundColor Yellow
            return [PSCustomObject]@{
                SessionId      = $null
                ItemsProcessed = 0
                SpaceFreed     = [long]0
                Errors         = @()
                ErrorCount     = 0
                ElapsedSeconds = 0
                Status         = 'dry-run'
                Preview        = $preview
            }
        }
    }
    # Konfirmasi hanya jika BUKAN dari dry-run flow (langsung eksekusi tanpa dry-run)
    # dan bukan -Force (Req 2.2, 2.3, 2.4)
    elseif (-not $Force) {
        Write-Host "  Pilihan:" -ForegroundColor Yellow
        Write-Host "    [a] Bersihkan semua item" -ForegroundColor White
        Write-Host "    [s] Pilih item tertentu (masukkan nomor, pisah koma)" -ForegroundColor White
        Write-Host "    [n] Batal" -ForegroundColor White
        Write-Host ""
        $confirmation = Read-Host "  Ketik pilihan (a/s/n)"

        if ($confirmation -eq 'a' -or $confirmation -eq 'A' -or $confirmation -eq 'y' -or $confirmation -eq 'Y') {
            # Lanjutkan dengan semua item
            Write-Host "  Melanjutkan pembersihan semua item..." -ForegroundColor Green
        }
        elseif ($confirmation -eq 's' -or $confirmation -eq 'S') {
            Write-Host ""
            $selection = Read-Host "  Masukkan nomor item (pisah koma, contoh: 1,3,5)"

            $selectedIndices = @()
            foreach ($part in ($selection -split ',')) {
                $trimmed = $part.Trim()
                $num = 0
                if ([int]::TryParse($trimmed, [ref]$num)) {
                    if ($num -ge 1 -and $num -le $safeItems.Count) {
                        $selectedIndices += ($num - 1)
                    }
                    else {
                        Write-Warning "  Nomor '$num' di luar jangkauan (1-$($safeItems.Count)), dilewati."
                    }
                }
            }

            if ($selectedIndices.Count -eq 0) {
                Write-Host "`n  Tidak ada item valid yang dipilih. Pembersihan dibatalkan." -ForegroundColor Yellow
                return [PSCustomObject]@{
                    SessionId      = $null
                    ItemsProcessed = 0
                    SpaceFreed     = [long]0
                    Errors         = @()
                    ErrorCount     = 0
                    ElapsedSeconds = 0
                    Status         = 'cancelled'
                }
            }

            $safeItems = @($selectedIndices | ForEach-Object { $safeItems[$_] })
            $preview = Get-CleanupPreview -Items $safeItems

            Write-Host ""
            Write-Host "  Item terpilih: $($safeItems.Count) ($($preview.TotalSizeFormatted))" -ForegroundColor Green
        }
        else {
            Write-Host "`n  Pembersihan dibatalkan." -ForegroundColor Yellow
            return [PSCustomObject]@{
                SessionId      = $null
                ItemsProcessed = 0
                SpaceFreed     = [long]0
                Errors         = @()
                ErrorCount     = 0
                ElapsedSeconds = 0
                Status         = 'cancelled'
            }
        }
    }

    # Generate Session ID (Req 9.6)
    if (-not $SessionId) {
        $SessionId = New-SessionId
    }

    Write-Host "`n  Memulai pembersihan (Session: $SessionId)..." -ForegroundColor Green

    # Purge expired staging (Req 9.2)
    Write-Host "  Membersihkan staging yang kedaluwarsa..." -ForegroundColor DarkGray
    try {
        if (Get-Command Remove-ExpiredStaged -ErrorAction SilentlyContinue) {
            Remove-ExpiredStaged | Out-Null
        }
    }
    catch {
        Write-Warning "  Gagal membersihkan staging kedaluwarsa: $($_.Exception.Message)"
    }

    # Proses setiap item: stage > progress (Req 3.1, 3.2, 3.4, 3.5)
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $itemsProcessed = 0
    $spaceFreed = [long]0
    $errors = @()

    Write-Host ""

    for ($i = 0; $i -lt $safeItems.Count; $i++) {
        $currentItem = $safeItems[$i]
        $itemPath = $currentItem.Path
        $itemSize = [long]0
        if ($currentItem.PSObject.Properties['SizeBytes']) {
            $itemSize = $currentItem.SizeBytes
        }
        elseif ($currentItem.PSObject.Properties['Size']) {
            $itemSize = $currentItem.Size
        }

        try {
            # 1. Stage file (move to staging area)
            if (Get-Command Move-ToStaging -ErrorAction SilentlyContinue) {
                $stageResult = Move-ToStaging -SourcePath $itemPath -SessionId $SessionId
                if (-not $stageResult.Success) {
                    $errors += "Staging gagal untuk '$itemPath': $($stageResult.Error)"
                    Write-Warning "  Melewati item (staging gagal): $itemPath"
                    continue
                }
            }

            # 2. Item berhasil diproses
            $itemsProcessed++
            $spaceFreed += $itemSize

            # 3. Tampilkan progress (Req 3.1, 3.2, 3.5)
            Show-CleanupProgress -CurrentPath $itemPath -CurrentIndex $i -TotalItems $safeItems.Count -SpaceFreedSoFar $spaceFreed
        }
        catch {
            # Skip-and-continue: catat error, lanjutkan ke item berikutnya (Req 3.4)
            $errorMsg = "Error pada '$itemPath': $($_.Exception.Message)"
            $errors += $errorMsg
            Write-Warning "  $errorMsg"

            # Log ke audit jika tersedia
            try {
                if (Get-Command Write-AuditEntry -ErrorAction SilentlyContinue) {
                    Write-AuditEntry -Action 'purge-failed' -FilePath $itemPath
                }
            }
            catch {
                # Non-blocking: audit failure tidak menghentikan proses
            }
        }
    }

    $stopwatch.Stop()
    $elapsedSeconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 2)

    # Summary (Req 3.3)
    Write-Host ""
    Write-Host "  === Ringkasan Pembersihan ===" -ForegroundColor Green
    Write-Host "  Session       : $SessionId" -ForegroundColor White
    Write-Host "  Item diproses : $itemsProcessed" -ForegroundColor White
    $freedDisplay = Format-FileSize -Bytes $spaceFreed
    Write-Host "  Ruang bebas   : $freedDisplay" -ForegroundColor White
    $errorColor = 'White'
    if ($errors.Count -gt 0) { $errorColor = 'Red' }
    Write-Host "  Error         : $($errors.Count)" -ForegroundColor $errorColor
    Write-Host "  Waktu         : $elapsedSeconds detik" -ForegroundColor White

    $expiryDate = (Get-Date).AddDays(7).ToString("dd MMMM yyyy")
    Write-Host ""
    Write-Host "  [!] FILE ADA DI PENYIMPANAN (STAGING) SELAMA 7 HARI" -ForegroundColor Yellow
    Write-Host "     Lewat menu [6] Penyimpanan kamu bisa:" -ForegroundColor White
    Write-Host "       [v] Restore file kalo nyesal" -ForegroundColor Gray
    Write-Host "       [x] Hapus permanen kalo udah yakin" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  [i] File akan otomatis terhapus permanen: $expiryDate" -ForegroundColor Cyan
    Write-Host ""

    return [PSCustomObject]@{
        SessionId      = $SessionId
        ItemsProcessed = $itemsProcessed
        SpaceFreed     = $spaceFreed
        Errors         = $errors
        ErrorCount     = $errors.Count
        ElapsedSeconds = $elapsedSeconds
        Status         = 'completed'
    }
}
