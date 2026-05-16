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

function Remove-LongPathItem {
    <#
    .SYNOPSIS
        Menghapus file/folder yang mendukung long path (>260 karakter).
    .DESCRIPTION
        Menggunakan Robocopy dengan empty folder trick untuk menghapus
        folder dengan path sangat panjang yang tidak bisa ditangani
        oleh Remove-Item biasa. Fallback ke Remove-Item jika Robocopy gagal.
    .PARAMETER Path
        Path absolut file/folder yang akan dihapus
    .OUTPUTS
        [bool] $true jika berhasil, throw exception jika gagal
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $true
    }

    $isDirectory = (Get-Item -LiteralPath $Path -Force).PSIsContainer

    if ($isDirectory) {
        # Coba Remove-Item dulu (cepat untuk folder kecil/path pendek)
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -Confirm:$false -ErrorAction Stop
            return $true
        }
        catch {
            # Jika gagal (biasanya karena long path), gunakan Robocopy trick
        }

        # Robocopy trick: mirror empty folder ke target, lalu hapus keduanya
        $emptyDir = Join-Path $env:TEMP "DrivePulse_empty_$([System.Guid]::NewGuid().ToString('N'))"
        try {
            New-Item -Path $emptyDir -ItemType Directory -Force | Out-Null

            # /MIR mirrors empty folder ke target = menghapus semua isi target
            # /R:1 /W:1 = retry 1x, wait 1 detik
            $robocopyArgs = @($emptyDir, $Path, '/MIR', '/R:1', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS', '/NC', '/NS', '/NP')
            $proc = Start-Process -FilePath 'robocopy.exe' -ArgumentList $robocopyArgs -NoNewWindow -Wait -PassThru

            # Robocopy exit code < 8 = sukses (0-7 normal, 8+ error)
            if ($proc.ExitCode -lt 8) {
                # Folder sekarang kosong, hapus folder itu sendiri
                Remove-Item -LiteralPath $Path -Force -Confirm:$false -ErrorAction SilentlyContinue
                return $true
            }
            else {
                throw "Robocopy gagal dengan exit code $($proc.ExitCode)"
            }
        }
        finally {
            # Bersihkan empty dir
            if (Test-Path $emptyDir) {
                Remove-Item -Path $emptyDir -Force -Confirm:$false -ErrorAction SilentlyContinue
            }
        }
    }
    else {
        # File biasa — gunakan LiteralPath untuk handle karakter spesial
        Remove-Item -LiteralPath $Path -Force -Confirm:$false -ErrorAction Stop
        return $true
    }
}

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

        # Pindahkan file/folder (move, bukan copy)
        # Untuk folder: pindahkan isi folder, bukan folder itu sendiri
        # (beberapa folder sistem seperti $Recycle.Bin tidak bisa dipindahkan)
        if ($fileInfo.PSIsContainer) {
            # Folder: buat folder tujuan dan pindahkan isinya
            if (-not (Test-Path $stagedPath)) {
                New-Item -Path $stagedPath -ItemType Directory -Force | Out-Null
            }

            $childItems = Get-ChildItem -Path $SourcePath -Force -ErrorAction SilentlyContinue
            $moveErrors = @()

            foreach ($child in $childItems) {
                try {
                    Move-Item -Path $child.FullName -Destination $stagedPath -Force -ErrorAction Stop
                }
                catch {
                    $moveErrors += $child.FullName
                }
            }

            # Jika semua child gagal dipindahkan, anggap gagal
            if ($childItems -and $moveErrors.Count -eq $childItems.Count) {
                # Bersihkan folder staging yang sudah dibuat
                if (Test-Path $stagedPath) {
                    Remove-Item -Path $stagedPath -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
                }
                return [PSCustomObject]@{
                    Success    = $false
                    StagedPath = $null
                    Error      = "Akses ditolak: tidak bisa memindahkan isi folder '$SourcePath'. Jalankan sebagai Administrator."
                }
            }
        }
        else {
            # File biasa: langsung move
            Move-Item -Path $SourcePath -Destination $stagedPath -Force -ErrorAction Stop
        }

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

        # Deduplikasi: hapus entry lama dengan originalPath yang sama sebelum menambah entry baru
        $filesList = [System.Collections.ArrayList]@()
        if ($manifest.files) {
            foreach ($f in $manifest.files) {
                if ($f.originalPath -ne $SourcePath) {
                    [void]$filesList.Add($f)
                }
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
            # File sudah ada di lokasi asli — hapus file staging dan entry dari manifest
            # agar staging area tetap bersih
            try {
                Remove-LongPathItem -Path $stagedFullPath | Out-Null
            }
            catch {
                # Non-blocking: lanjutkan bersihkan manifest meskipun hapus file gagal
                Write-Warning "Gagal menghapus file staging: $($_.Exception.Message)"
            }

            # Hapus entry dari manifest
            $manifest.files = @($manifest.files | Where-Object { $_.originalPath -ne $OriginalPath })
            Save-StagingManifest -Manifest $manifest

            # Catat ke audit log
            if (Get-Command Write-AuditEntry -ErrorAction SilentlyContinue) {
                Write-AuditEntry -Action 'restore-skipped' -FilePath $OriginalPath
            }

            return [PSCustomObject]@{
                Success      = $true
                RestoredPath = $OriginalPath
                Error        = "File sudah ada di lokasi asli. Entry staging dibersihkan."
            }
        }

        # Buat direktori parent jika belum ada
        $parentDir = Split-Path -Parent $OriginalPath
        if (-not (Test-Path $parentDir)) {
            New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
        }

        # Pindahkan file kembali ke lokasi asli
        Move-Item -Path $stagedFullPath -Destination $OriginalPath -Force -Confirm:$false

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
                    Remove-LongPathItem -Path $stagedFullPath | Out-Null
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

function Clear-OrphanedStaged {
    <#
    .SYNOPSIS
        Membersihkan entry staging yang orphan.
    .DESCRIPTION
        Mendeteksi dan menghapus entry di staging manifest di mana:
        1. File asli sudah ada kembali di lokasi semula (orphan karena file sudah di-restore manual atau dibuat ulang)
        2. File staging sudah tidak ada di disk (entry tanpa backing file)
        Menghapus file staging dari disk (jika masih ada) dan menghapus entry dari manifest.
        Mencatat setiap pembersihan ke audit log dengan action "clear-orphan".
    .OUTPUTS
        [PSCustomObject] @{ ClearedCount; ClearedPaths; Errors }
    #>

    $manifest = Get-StagingManifest
    $clearedCount = 0
    $clearedPaths = @()
    $errors = @()
    $remainingFiles = [System.Collections.ArrayList]@()

    if (-not $manifest.files -or $manifest.files.Count -eq 0) {
        return [PSCustomObject]@{
            ClearedCount = 0
            ClearedPaths = @()
            Errors       = @()
        }
    }

    # Deduplikasi: track originalPath yang sudah diproses
    $seenPaths = @{}

    foreach ($entry in $manifest.files) {
        $originalPath = $entry.originalPath
        $stagedFullPath = Join-Path $Script:StagingRoot $entry.stagedPath

        # Skip duplikat — hanya pertahankan entry terbaru (manifest dibaca secara urut)
        if ($seenPaths.ContainsKey($originalPath)) {
            # Entry duplikat — hapus file staging jika ada
            if (Test-Path $stagedFullPath) {
                try {
                    Remove-LongPathItem -Path $stagedFullPath | Out-Null
                }
                catch {
                    $errors += "Gagal menghapus duplikat staged file '$originalPath': $($_.Exception.Message)"
                }
            }
            $clearedCount++
            $clearedPaths += $originalPath
            continue
        }
        $seenPaths[$originalPath] = $true

        $isOrphan = $false

        # Cek 1: File asli sudah ada di lokasi semula
        if (Test-Path $originalPath) {
            $isOrphan = $true
        }

        # Cek 2: File staging tidak ada di disk
        if (-not (Test-Path $stagedFullPath)) {
            $isOrphan = $true
        }

        if ($isOrphan) {
            # Hapus file staging dari disk jika masih ada
            if (Test-Path $stagedFullPath) {
                try {
                    Remove-LongPathItem -Path $stagedFullPath | Out-Null
                }
                catch {
                    $errorMsg = "Gagal menghapus orphan staged file '$originalPath': $($_.Exception.Message)"
                    $errors += $errorMsg
                    Write-Warning $errorMsg
                    # Tetap simpan entry jika gagal hapus file
                    [void]$remainingFiles.Add($entry)
                    continue
                }
            }

            $clearedCount++
            $clearedPaths += $originalPath

            # Catat ke audit log
            if (Get-Command Write-AuditEntry -ErrorAction SilentlyContinue) {
                Write-AuditEntry -Action 'clear-orphan' -FilePath $originalPath
            }
        }
        else {
            [void]$remainingFiles.Add($entry)
        }
    }

    # Update manifest
    $manifest.files = $remainingFiles.ToArray()
    Save-StagingManifest -Manifest $manifest

    return [PSCustomObject]@{
        ClearedCount = $clearedCount
        ClearedPaths = $clearedPaths
        Errors       = $errors
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
            Remove-LongPathItem -Path $stagedFullPath | Out-Null
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
