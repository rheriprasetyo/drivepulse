<#
.SYNOPSIS
    DrivePulse — Staging Area Module
.DESCRIPTION
    Mengelola staging area sebagai zona penahanan sementara sebelum file
    dihapus permanen. File dipindahkan (move) ke staging area dengan
    struktur direktori asli dipertahankan menggunakan drive-encoded paths.
    Mendukung restore, auto-purge berdasarkan retention period, dan
    pencatatan audit untuk setiap aksi.
.NOTES
    Author: DrivePulse Team
    Version: 1.3
    Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7, 8.8, 9.1, 9.2, 9.3, 9.4, 9.5
#>

# Dot-source audit logger
$auditPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'audit\audit.ps1'
if (Test-Path $auditPath) {
    . $auditPath
}

$Script:StagingRoot = "$env:LOCALAPPDATA\DrivePulse\Staging"
$Script:DefaultRetentionDays = 7

function Get-StagingManifestPath {
    <#
    .SYNOPSIS
        Mengembalikan path ke staging-manifest.json.
    .OUTPUTS
        [string] Path absolut ke staging-manifest.json
    #>
    return Join-Path $Script:StagingRoot 'staging-manifest.json'
}

function Get-StagingManifest {
    <#
    .SYNOPSIS
        Membaca staging manifest dari disk.
    .OUTPUTS
        [PSCustomObject] Manifest object dengan property 'files'
    #>
    $manifestPath = Get-StagingManifestPath

    if (-not (Test-Path $manifestPath)) {
        return [PSCustomObject]@{ files = @() }
    }

    try {
        $content = Get-Content -Path $manifestPath -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($content)) {
            return [PSCustomObject]@{ files = @() }
        }
        $manifest = $content | ConvertFrom-Json
        if (-not $manifest.files) {
            $manifest | Add-Member -NotePropertyName 'files' -NotePropertyValue @() -Force
        }
        return $manifest
    }
    catch {
        Write-Warning "Gagal membaca staging manifest: $($_.Exception.Message)"
        return [PSCustomObject]@{ files = @() }
    }
}

function Save-StagingManifest {
    <#
    .SYNOPSIS
        Menyimpan staging manifest ke disk.
    .PARAMETER Manifest
        Object manifest yang akan disimpan
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Manifest
    )

    $manifestPath = Get-StagingManifestPath
    $manifestDir = Split-Path -Parent $manifestPath

    if (-not (Test-Path $manifestDir)) {
        New-Item -Path $manifestDir -ItemType Directory -Force | Out-Null
    }

    $json = $Manifest | ConvertTo-Json -Depth 10
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($manifestPath, $json, $utf8NoBom)
}

function ConvertTo-DriveEncodedPath {
    <#
    .SYNOPSIS
        Mengkonversi path absolut ke drive-encoded path untuk staging.
    .DESCRIPTION
        Contoh: C:\Users\file.txt -> C_drive\Users\file.txt
    .PARAMETER AbsolutePath
        Path absolut Windows
    .OUTPUTS
        [string] Drive-encoded relative path
    #>
    param(
        [Parameter(Mandatory)]
        [string]$AbsolutePath
    )

    # Ambil drive letter dan path relatif
    $driveLetter = $AbsolutePath.Substring(0, 1)
    # Skip "X:\" — ambil sisanya
    $relativePath = $AbsolutePath.Substring(3)

    return Join-Path "${driveLetter}_drive" $relativePath
}

function Get-StagedFilePath {
    <#
    .SYNOPSIS
        Menghitung path lengkap file di staging area.
    .PARAMETER OriginalPath
        Path asli file
    .OUTPUTS
        [string] Path lengkap di staging area
    #>
    param(
        [Parameter(Mandatory)]
        [string]$OriginalPath
    )

    $encodedPath = ConvertTo-DriveEncodedPath -AbsolutePath $OriginalPath
    return Join-Path $Script:StagingRoot $encodedPath
}

function Resolve-RetentionDays {
    <#
    .SYNOPSIS
        Memvalidasi dan mengembalikan retention days yang valid.
    .PARAMETER RetentionDays
        Nilai retention days yang akan divalidasi
    .OUTPUTS
        [int] Retention days yang valid (1-90, default 7)
    #>
    param(
        [object]$RetentionDays
    )

    if ($null -eq $RetentionDays) {
        return $Script:DefaultRetentionDays
    }

    $parsed = 0
    if (-not [int]::TryParse($RetentionDays.ToString(), [ref]$parsed)) {
        Write-Warning "Nilai retention tidak valid: '$RetentionDays'. Menggunakan default $($Script:DefaultRetentionDays) hari."
        return $Script:DefaultRetentionDays
    }

    if ($parsed -lt 1 -or $parsed -gt 90) {
        Write-Warning "Retention days harus antara 1-90. Nilai '$parsed' tidak valid. Menggunakan default $($Script:DefaultRetentionDays) hari."
        return $Script:DefaultRetentionDays
    }

    return $parsed
}

function Move-ToStaging {
    <#
    .SYNOPSIS
        Memindahkan file ke staging area.
    .DESCRIPTION
        Memindahkan file dari lokasi asli ke staging area dengan
        mempertahankan struktur direktori menggunakan drive-encoded paths.
        Mencatat metadata ke staging-manifest.json dan menulis audit log.
    .PARAMETER SourcePath
        Path absolut file yang akan dipindahkan
    .PARAMETER SessionId
        ID sesi cleanup yang sedang berjalan
    .OUTPUTS
        [PSCustomObject] @{ Success; StagedPath; Error }
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$SessionId
    )

    try {
        # Validasi file sumber ada
        if (-not (Test-Path $SourcePath)) {
            return [PSCustomObject]@{
                Success    = $false
                StagedPath = $null
                Error      = "File tidak ditemukan: $SourcePath"
            }
        }

        # Dapatkan info file
        $fileInfo = Get-Item -Path $SourcePath -Force
        $fileSize = $fileInfo.Length

        # Hitung path tujuan di staging
        $stagedPath = Get-StagedFilePath -OriginalPath $SourcePath
        $stagedDir = Split-Path -Parent $stagedPath

        # Cek ruang disk yang tersedia
        $stagingDrive = (Split-Path -Qualifier $Script:StagingRoot)
        if ($stagingDrive) {
            $driveInfo = Get-PSDrive -Name $stagingDrive.TrimEnd(':') -ErrorAction SilentlyContinue
            if ($driveInfo -and $driveInfo.Free -lt $fileSize) {
                return [PSCustomObject]@{
                    Success    = $false
                    StagedPath = $null
                    Error      = "Ruang disk tidak cukup untuk memindahkan file ke staging area."
                }
            }
        }

        # Buat direktori tujuan jika belum ada
        if (-not (Test-Path $stagedDir)) {
            New-Item -Path $stagedDir -ItemType Directory -Force | Out-Null
        }

        # Pindahkan file (move, bukan copy)
        Move-Item -Path $SourcePath -Destination $stagedPath -Force

        # Catat metadata ke manifest
        $timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'
        $manifest = Get-StagingManifest

        $entry = [PSCustomObject]@{
            originalPath     = $SourcePath
            stagedPath       = (ConvertTo-DriveEncodedPath -AbsolutePath $SourcePath)
            sizeBytes        = $fileSize
            stagingTimestamp = $timestamp
            sessionId        = $SessionId
        }

        $filesList = [System.Collections.ArrayList]@()
        if ($manifest.files) {
            foreach ($f in $manifest.files) {
                [void]$filesList.Add($f)
            }
        }
        [void]$filesList.Add($entry)
        $manifest.files = $filesList.ToArray()

        Save-StagingManifest -Manifest $manifest

        # Catat ke audit log
        if (Get-Command Write-AuditEntry -ErrorAction SilentlyContinue) {
            Write-AuditEntry -Action 'stage' -FilePath $SourcePath
        }

        return [PSCustomObject]@{
            Success    = $true
            StagedPath = $stagedPath
            Error      = $null
        }
    }
    catch {
        return [PSCustomObject]@{
            Success    = $false
            StagedPath = $null
            Error      = $_.Exception.Message
        }
    }
}

function Restore-FromStaging {
    <#
    .SYNOPSIS
        Mengembalikan file dari staging area ke lokasi asli.
    .DESCRIPTION
        Memindahkan file dari staging area kembali ke path aslinya.
        Membuat direktori parent jika belum ada. Menghapus entry dari manifest.
    .PARAMETER OriginalPath
        Path asli file yang akan di-restore
    .PARAMETER Force
        Jika diset, akan menimpa file yang sudah ada di lokasi asli
    .OUTPUTS
        [PSCustomObject] @{ Success; RestoredPath; Error }
    #>
    param(
        [Parameter(Mandatory)]
        [string]$OriginalPath,

        [switch]$Force
    )

    try {
        $manifest = Get-StagingManifest

        # Cari entry di manifest
        $entry = $manifest.files | Where-Object { $_.originalPath -eq $OriginalPath } | Select-Object -First 1

        if (-not $entry) {
            return [PSCustomObject]@{
                Success      = $false
                RestoredPath = $null
                Error        = "File tidak ditemukan di staging area: $OriginalPath"
            }
        }

        # Hitung path file di staging
        $stagedFullPath = Join-Path $Script:StagingRoot $entry.stagedPath

        if (-not (Test-Path $stagedFullPath)) {
            return [PSCustomObject]@{
                Success      = $false
                RestoredPath = $null
                Error        = "File staging tidak ditemukan di disk: $stagedFullPath"
            }
        }

        # Cek apakah file sudah ada di lokasi asli
        if ((Test-Path $OriginalPath) -and -not $Force) {
            return [PSCustomObject]@{
                Success      = $false
                RestoredPath = $null
                Error        = "File sudah ada di lokasi asli: $OriginalPath. Gunakan -Force untuk menimpa."
            }
        }

        # Buat direktori parent jika belum ada
        $parentDir = Split-Path -Parent $OriginalPath
        if (-not (Test-Path $parentDir)) {
            New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
        }

        # Pindahkan file kembali ke lokasi asli
        Move-Item -Path $stagedFullPath -Destination $OriginalPath -Force

        # Hapus entry dari manifest
        $manifest.files = @($manifest.files | Where-Object { $_.originalPath -ne $OriginalPath })
        Save-StagingManifest -Manifest $manifest

        # Catat ke audit log
        if (Get-Command Write-AuditEntry -ErrorAction SilentlyContinue) {
            Write-AuditEntry -Action 'restore' -FilePath $OriginalPath
        }

        return [PSCustomObject]@{
            Success      = $true
            RestoredPath = $OriginalPath
            Error        = $null
        }
    }
    catch {
        return [PSCustomObject]@{
            Success      = $false
            RestoredPath = $null
            Error        = $_.Exception.Message
        }
    }
}

function Get-StagedFiles {
    <#
    .SYNOPSIS
        Mengembalikan daftar file yang ada di staging area.
    .DESCRIPTION
        Membaca staging manifest dan mengembalikan semua entry
        yang diurutkan berdasarkan staging timestamp secara descending
        (terbaru di atas).
    .OUTPUTS
        [PSCustomObject[]] Array of staged file metadata, sorted by stagingTimestamp descending
    #>

    $manifest = Get-StagingManifest

    if (-not $manifest.files -or $manifest.files.Count -eq 0) {
        return @()
    }

    # Sort by stagingTimestamp descending (terbaru di atas)
    $sorted = $manifest.files | Sort-Object -Property stagingTimestamp -Descending

    return @($sorted)
}

function Remove-ExpiredStaged {
    <#
    .SYNOPSIS
        Menghapus file staging yang sudah melewati retention period.
    .DESCRIPTION
        Menghapus secara permanen file-file di staging area yang
        staging timestamp-nya sudah melebihi retention period.
        Mencatat setiap penghapusan ke audit log dengan action "auto-purge".
    .PARAMETER RetentionDays
        Jumlah hari retention (1-90, default 7)
    .OUTPUTS
        [PSCustomObject] @{ PurgedCount; PurgedSize; Errors }
    #>
    param(
        [int]$RetentionDays = 7
    )

    $validRetention = Resolve-RetentionDays -RetentionDays $RetentionDays
    $cutoffDate = (Get-Date).AddDays(-$validRetention)

    $manifest = Get-StagingManifest
    $purgedCount = 0
    $purgedSize = [long]0
    $errors = @()
    $remainingFiles = [System.Collections.ArrayList]@()

    if (-not $manifest.files -or $manifest.files.Count -eq 0) {
        return [PSCustomObject]@{
            PurgedCount = 0
            PurgedSize  = [long]0
            Errors      = @()
        }
    }

    foreach ($entry in $manifest.files) {
        $entryTimestamp = [DateTime]::Parse($entry.stagingTimestamp)

        if ($entryTimestamp -lt $cutoffDate) {
            # Entry sudah expired — hapus permanen
            $stagedFullPath = Join-Path $Script:StagingRoot $entry.stagedPath

            try {
                if (Test-Path $stagedFullPath) {
                    Remove-Item -Path $stagedFullPath -Force -ErrorAction Stop
                }

                $purgedCount++
                $purgedSize += $entry.sizeBytes

                # Catat ke audit log
                if (Get-Command Write-AuditEntry -ErrorAction SilentlyContinue) {
                    Write-AuditEntry -Action 'auto-purge' -FilePath $entry.originalPath
                }
            }
            catch {
                # Req 9.5: Skip file yang locked/permission error, log warning, lanjutkan
                $errorMsg = "Gagal menghapus staged file '$($entry.originalPath)': $($_.Exception.Message)"
                $errors += $errorMsg
                Write-Warning $errorMsg

                # Log ke audit sebagai purge-failed
                if (Get-Command Write-AuditEntry -ErrorAction SilentlyContinue) {
                    Write-AuditEntry -Action 'purge-failed' -FilePath $entry.originalPath
                }

                # Tetap simpan entry yang gagal dihapus
                [void]$remainingFiles.Add($entry)
            }
        }
        else {
            # Entry masih dalam retention window — pertahankan
            [void]$remainingFiles.Add($entry)
        }
    }

    # Update manifest
    $manifest.files = $remainingFiles.ToArray()
    Save-StagingManifest -Manifest $manifest

    return [PSCustomObject]@{
        PurgedCount = $purgedCount
        PurgedSize  = $purgedSize
        Errors      = $errors
    }
}

function Remove-StagedFile {
    <#
    .SYNOPSIS
        Menghapus file tertentu dari staging area secara permanen.
    .DESCRIPTION
        Menghapus file dari staging area dan menghapus entry-nya dari manifest.
        Digunakan ketika user ingin menghapus file staging secara manual.
    .PARAMETER OriginalPath
        Path asli file yang akan dihapus dari staging
    .OUTPUTS
        [PSCustomObject] @{ Success; Error }
    #>
    param(
        [Parameter(Mandatory)]
        [string]$OriginalPath
    )

    try {
        $manifest = Get-StagingManifest

        # Cari entry di manifest
        $entry = $manifest.files | Where-Object { $_.originalPath -eq $OriginalPath } | Select-Object -First 1

        if (-not $entry) {
            return [PSCustomObject]@{
                Success = $false
                Error   = "File tidak ditemukan di staging area: $OriginalPath"
            }
        }

        # Hapus file dari disk
        $stagedFullPath = Join-Path $Script:StagingRoot $entry.stagedPath

        if (Test-Path $stagedFullPath) {
            Remove-Item -Path $stagedFullPath -Force -ErrorAction Stop
        }

        # Hapus entry dari manifest
        $manifest.files = @($manifest.files | Where-Object { $_.originalPath -ne $OriginalPath })
        Save-StagingManifest -Manifest $manifest

        # Catat ke audit log
        if (Get-Command Write-AuditEntry -ErrorAction SilentlyContinue) {
            Write-AuditEntry -Action 'delete' -FilePath $OriginalPath
        }

        return [PSCustomObject]@{
            Success = $true
            Error   = $null
        }
    }
    catch {
        return [PSCustomObject]@{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}
