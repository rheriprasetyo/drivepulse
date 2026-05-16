<#
.SYNOPSIS
    DrivePulse — Audit Logger Module
.DESCRIPTION
    Mencatat semua aksi (delete, backup, restore, stage, auto-purge, purge-failed,
    restore-skipped, clear-orphan) ke file audit log dalam format JSON single-line (JSONL).
    Mendukung append-only writes, flush-to-disk, rotasi log (10 MB), dan
    encoding UTF-8 tanpa BOM.
.NOTES
    Author: DrivePulse Team
    Version: 1.3
    Requirements: 7.1, 7.2, 7.8, 7.9, 7.10, 7.11, 13.1, 13.2, 13.3, 13.4, 13.5
#>

function Get-AuditLogPath {
    <#
    .SYNOPSIS
        Mengembalikan path absolut ke file audit log.
    .DESCRIPTION
        Menghitung path logs/audit.log relatif terhadap root aplikasi DrivePulse.
    .OUTPUTS
        [string] Path absolut ke logs/audit.log
    #>
    $projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    return Join-Path $projectRoot 'logs\audit.log'
}

function Initialize-AuditLog {
    <#
    .SYNOPSIS
        Membuat direktori dan file audit log jika belum ada.
    .DESCRIPTION
        Memastikan direktori logs/ dan file audit.log tersedia sebelum
        penulisan entry pertama. Menggunakan UTF-8 tanpa BOM.
    .OUTPUTS
        [bool] $true jika berhasil, $false jika gagal
    #>
    try {
        $logPath = Get-AuditLogPath
        $logDir = Split-Path -Parent $logPath

        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }

        if (-not (Test-Path $logPath)) {
            # Buat file kosong dengan UTF-8 tanpa BOM
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($logPath, '', $utf8NoBom)
        }

        return $true
    }
    catch {
        Write-Warning "Gagal menginisialisasi audit log: $($_.Exception.Message)"
        return $false
    }
}

function Write-AuditEntry {
    <#
    .SYNOPSIS
        Menulis satu entry audit ke file log.
    .DESCRIPTION
        Menulis entry JSON single-line ke audit.log dengan field:
        timestamp (ISO 8601), action, file, user.
        Mendukung rotasi log (10 MB), flush-to-disk, dan proper JSON escaping (RFC 8259).
    .PARAMETER Action
        Tipe aksi: delete, backup, restore, stage, auto-purge, purge-failed, restore-skipped, clear-orphan
    .PARAMETER FilePath
        Path absolut file yang terpengaruh
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('delete', 'backup', 'restore', 'stage', 'auto-purge', 'purge-failed', 'restore-skipped', 'clear-orphan')]
        [string]$Action,

        [Parameter(Mandatory)]
        [string]$FilePath
    )

    try {
        $logPath = Get-AuditLogPath

        # Pastikan file dan direktori ada
        if (-not (Test-Path $logPath)) {
            $initialized = Initialize-AuditLog
            if (-not $initialized) {
                return
            }
        }

        # Cek rotasi: jika file melebihi 10 MB, rotasi dulu
        $logFile = Get-Item $logPath -ErrorAction SilentlyContinue
        if ($logFile -and $logFile.Length -ge 10MB) {
            Invoke-AuditLogRotation -LogPath $logPath
        }

        # Buat entry JSON dengan proper escaping (RFC 8259)
        $timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'
        $currentUser = [System.Environment]::UserName

        $jsonLine = ConvertTo-AuditJson -Timestamp $timestamp -Action $Action -File $FilePath -User $currentUser

        # Append dengan CRLF line ending, UTF-8 tanpa BOM, flush-to-disk
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        $lineBytes = $utf8NoBom.GetBytes("$jsonLine`r`n")

        # Gunakan FileStream untuk append + flush
        $stream = New-Object System.IO.FileStream(
            $logPath,
            [System.IO.FileMode]::Append,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::Read
        )
        try {
            $stream.Write($lineBytes, 0, $lineBytes.Length)
            $stream.Flush($true)  # FlushToDisk = true
        }
        finally {
            $stream.Close()
            $stream.Dispose()
        }
    }
    catch {
        # Req 7.9: Jika gagal menulis, tampilkan warning tanpa memblokir operasi
        Write-Warning "Gagal menulis audit log: $($_.Exception.Message)"
    }
}

function ConvertTo-AuditJson {
    <#
    .SYNOPSIS
        Mengkonversi field audit entry ke JSON string dengan proper escaping.
    .DESCRIPTION
        Melakukan serialisasi manual sesuai RFC 8259 untuk memastikan
        backslash, double quote, dan control characters di-escape dengan benar.
    .PARAMETER Timestamp
        Timestamp ISO 8601
    .PARAMETER Action
        Tipe aksi
    .PARAMETER File
        Path file (akan di-escape)
    .PARAMETER User
        Username Windows
    .OUTPUTS
        [string] Single-line JSON string
    #>
    param(
        [Parameter(Mandatory)][string]$Timestamp,
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$File,
        [Parameter(Mandatory)][string]$User
    )

    $escapedTimestamp = ConvertTo-JsonEscapedString $Timestamp
    $escapedAction = ConvertTo-JsonEscapedString $Action
    $escapedFile = ConvertTo-JsonEscapedString $File
    $escapedUser = ConvertTo-JsonEscapedString $User

    return "{`"timestamp`":`"$escapedTimestamp`",`"action`":`"$escapedAction`",`"file`":`"$escapedFile`",`"user`":`"$escapedUser`"}"
}

function ConvertTo-JsonEscapedString {
    <#
    .SYNOPSIS
        Escape string sesuai RFC 8259 (JSON specification).
    .DESCRIPTION
        Meng-escape karakter khusus JSON: backslash, double quote,
        dan control characters (U+0000 sampai U+001F).
    .PARAMETER Value
        String yang akan di-escape
    .OUTPUTS
        [string] String yang sudah di-escape untuk JSON
    #>
    param(
        [Parameter(Mandatory)][string]$Value
    )

    $result = New-Object System.Text.StringBuilder($Value.Length)

    foreach ($char in $Value.ToCharArray()) {
        $code = [int]$char
        switch ($char) {
            '"'  { [void]$result.Append('\"') }
            '\'  { [void]$result.Append('\\') }
            '/'  { [void]$result.Append($char) }  # Forward slash tidak wajib di-escape
            default {
                if ($code -lt 0x20) {
                    # Control characters
                    switch ($code) {
                        0x08 { [void]$result.Append('\b') }
                        0x09 { [void]$result.Append('\t') }
                        0x0A { [void]$result.Append('\n') }
                        0x0C { [void]$result.Append('\f') }
                        0x0D { [void]$result.Append('\r') }
                        default {
                            [void]$result.Append('\u{0:X4}' -f $code)
                        }
                    }
                }
                else {
                    [void]$result.Append($char)
                }
            }
        }
    }

    return $result.ToString()
}

function Invoke-AuditLogRotation {
    <#
    .SYNOPSIS
        Melakukan rotasi file audit log.
    .DESCRIPTION
        Rename file audit.log yang sudah melebihi 10 MB dengan suffix timestamp,
        lalu buat file baru yang kosong.
    .PARAMETER LogPath
        Path ke file audit.log yang akan dirotasi
    #>
    param(
        [Parameter(Mandatory)][string]$LogPath
    )

    try {
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $logDir = Split-Path -Parent $LogPath
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($LogPath)
        $extension = [System.IO.Path]::GetExtension($LogPath)
        $rotatedName = "${baseName}-${timestamp}${extension}"
        $rotatedPath = Join-Path $logDir $rotatedName

        # Rename file lama
        Rename-Item -Path $LogPath -NewName $rotatedName -Force

        # Buat file baru kosong dengan UTF-8 tanpa BOM
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($LogPath, '', $utf8NoBom)
    }
    catch {
        Write-Warning "Gagal merotasi audit log: $($_.Exception.Message)"
    }
}
