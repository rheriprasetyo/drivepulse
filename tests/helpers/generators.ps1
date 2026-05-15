<#
.SYNOPSIS
    DrivePulse — Random Data Generators for Property-Based Testing
.DESCRIPTION
    Provides generator functions for creating random test data used in
    property-based tests. Each generator produces randomized but structurally
    valid data for testing scanner, categorizer, and rules parsing modules.
.NOTES
    Minimum 100 iterations is the standard for property tests.
#>

# Import types so we can use New-ScanItem and other factory functions
. "$PSScriptRoot\..\..\src\scanner\types.ps1"

function New-RandomPath {
    <#
    .SYNOPSIS Generates random paths with environment variable placeholders
    .DESCRIPTION Creates paths using %TEMP%, %LOCALAPPDATA%, %APPDATA%, %USERPROFILE%
                 placeholders combined with random subfolder segments of varying depth.
    .OUTPUTS [string] A random path string with env var placeholder prefix
    #>
    $envVars = @('%TEMP%', '%LOCALAPPDATA%', '%APPDATA%', '%USERPROFILE%')
    $segments = @(
        'folder1', 'sub folder', 'cache', 'data', 'temp',
        'logs', 'backup', 'downloads', 'packages', 'node_modules',
        'AppData', 'Local', 'Roaming', '.cache', 'tmp'
    )

    $envVar = $envVars | Get-Random
    $depth = Get-Random -Minimum 1 -Maximum 4
    $subPath = ($segments | Get-Random -Count $depth) -join '\'
    return "$envVar\$subPath"
}

function New-RandomScanItem {
    <#
    .SYNOPSIS Generates random ScanItem objects
    .DESCRIPTION Creates ScanItem objects with random sizes (0 to 500GB),
                 random labels, and random paths using New-ScanItem from types.ps1.
    .PARAMETER MinSize Minimum size in bytes (default 0)
    .PARAMETER MaxSize Maximum size in bytes (default 500GB)
    .OUTPUTS [PSCustomObject] A DrivePulse.ScanItem object
    #>
    param(
        [long]$MinSize = 0,
        [long]$MaxSize = 500GB
    )

    $labels = @(
        'Cache Browser', 'File Sementara', 'Log Sistem',
        'Folder Unduhan', 'Paket NPM', 'Cache Windows Update',
        'Recycle Bin', 'Thumbnail Cache', 'Folder Besar',
        'Data Aplikasi', 'Backup Lama', 'Temp Files'
    )

    $size = Get-Random -Minimum $MinSize -Maximum ([Math]::Max($MinSize + 1, $MaxSize))
    $label = $labels | Get-Random
    $path = "C:\$([System.Guid]::NewGuid().ToString())"

    return New-ScanItem -Path $path -Label $label -SizeBytes $size
}

function New-RandomRulesJson {
    <#
    .SYNOPSIS Generates random valid rules file structures
    .DESCRIPTION Creates a valid rules JSON object with random thresholds,
                 random safe items, and random check items that conform to
                 the expected schema.
    .OUTPUTS [string] A valid JSON string representing a rules file
    #>
    $threshold = Get-Random -Minimum 1 -Maximum 20
    $criticalPct = Get-Random -Minimum 85 -Maximum 99
    $warningPct = Get-Random -Minimum 60 -Maximum ($criticalPct - 1)

    $safeCount = Get-Random -Minimum 1 -Maximum 6
    $checkCount = Get-Random -Minimum 1 -Maximum 6

    $envVars = @('%TEMP%', '%LOCALAPPDATA%', '%APPDATA%', '%USERPROFILE%')
    $safeFolders = @('cache', 'temp', 'logs', 'thumbnails', 'updates', 'crash-reports')
    $sideEffects = @(
        'Browser perlu rebuild cache',
        'File akan dibuat ulang otomatis',
        'Log lama akan hilang',
        'Thumbnail akan di-generate ulang',
        'Update cache akan diunduh ulang'
    )

    $safeItems = @()
    for ($i = 0; $i -lt $safeCount; $i++) {
        $envVar = $envVars | Get-Random
        $folder = $safeFolders | Get-Random
        $safeItems += @{
            id            = "safe-$i"
            label         = "Item Aman $i"
            path          = "$envVar\$folder"
            requiresAdmin = ($i % 3 -eq 0)
            sideEffect    = $sideEffects | Get-Random
        }
    }

    $checkReasons = @(
        'Mungkin berisi data penting',
        'Folder aplikasi aktif',
        'Perlu verifikasi manual',
        'Bisa berisi dokumen pengguna'
    )
    $checkRecommendations = @(
        'Periksa isi folder sebelum menghapus',
        'Pastikan aplikasi tidak sedang berjalan',
        'Backup terlebih dahulu',
        'Tanyakan pengguna sebelum menghapus'
    )

    $checkItems = @()
    for ($i = 0; $i -lt $checkCount; $i++) {
        $envVar = $envVars | Get-Random
        $checkItems += @{
            id             = "check-$i"
            label          = "Item Cek $i"
            path           = "$envVar\check-folder-$i"
            reason         = $checkReasons | Get-Random
            recommendation = $checkRecommendations | Get-Random
        }
    }

    $rules = @{
        '_schema'    = 'drivepulse-rules-v1'
        version      = '1.1.0'
        thresholds   = @{
            largeFolderGB   = $threshold
            criticalUsagePct = $criticalPct
            warningUsagePct  = $warningPct
        }
        categories   = @{
            safe  = @{
                description = 'Item yang aman dihapus'
                items       = $safeItems
            }
            check = @{
                description = 'Item yang perlu dicek manual'
                items       = $checkItems
            }
        }
        whitelist    = @('C:\Windows', 'C:\Program Files')
        blacklist    = @()
    }

    return ($rules | ConvertTo-Json -Depth 10)
}

function New-RandomInvalidJson {
    <#
    .SYNOPSIS Generates random invalid JSON strings
    .DESCRIPTION Creates strings that are NOT valid JSON using various strategies:
                 plain text, incomplete JSON, malformed structures, and random bytes.
    .OUTPUTS [string] An invalid JSON string
    #>
    $strategies = @(
        { "not json at all $(Get-Random)" },
        { "{incomplete: $(Get-Random)" },
        { '{"valid": "start", "but": }' },
        { "<<<random garbage $(Get-Random)>>>" },
        { '{' },
        { '[1, 2, 3' },
        { '{"key": "value"' },
        { "{'single': 'quotes'}" },
        {
            # Random bytes as string
            $bytes = 1..50 | ForEach-Object { Get-Random -Minimum 32 -Maximum 127 }
            [System.Text.Encoding]::ASCII.GetString([byte[]]$bytes)
        },
        { '' }
    )

    return (& ($strategies | Get-Random))
}

# ─── Report & Config Generators (v1.2) ──────────────────────

function New-RandomWindowsPath {
    <#
    .SYNOPSIS Generates random valid absolute Windows paths
    .DESCRIPTION Creates paths starting with a drive letter + :\ followed by
                 random folder segments of varying depth (1-5 levels).
    .OUTPUTS [string] A valid absolute Windows path
    #>
    $driveLetters = @('C', 'D', 'E', 'F', 'G')
    $segments = @(
        'Users', 'Documents', 'Projects', 'AppData', 'Local',
        'Programs', 'Temp', 'Downloads', 'Desktop', 'Pictures',
        'Videos', 'Music', 'Work', 'Dev', 'Tools', 'Backup',
        'OldStuff', 'Archive', 'Cache', 'Data'
    )

    $drive = $driveLetters | Get-Random
    $depth = Get-Random -Minimum 1 -Maximum 6
    $subPath = ($segments | Get-Random -Count $depth) -join '\'
    return "$drive`:\$subPath"
}

function New-RandomInvalidPath {
    <#
    .SYNOPSIS Generates random strings that are NOT valid absolute Windows paths
    .DESCRIPTION Creates strings that do not start with a drive letter followed by :\
                 including relative paths, UNC paths, Unix paths, empty strings, etc.
    .OUTPUTS [string] An invalid path string
    #>
    $strategies = @(
        { "relative\path\$(Get-Random)" },
        { "\\server\share\folder$(Get-Random)" },
        { "/unix/style/path/$(Get-Random)" },
        { "no-drive-letter\folder$(Get-Random)" },
        { "" },
        { " " },
        { "123:\invalid$(Get-Random)" },
        { "CC:\double-letter$(Get-Random)" },
        { "~\home\folder$(Get-Random)" },
        { "./current/dir/$(Get-Random)" },
        { "../parent/dir/$(Get-Random)" },
        { "http://not-a-path.com/$(Get-Random)" }
    )

    return (& ($strategies | Get-Random))
}

function New-RandomScanResult {
    <#
    .SYNOPSIS Generates random ScanResult objects with valid byte ranges
    .DESCRIPTION Creates DrivePulse.ScanResult objects with TotalBytes 0-2TB,
                 UsedBytes 0-TotalBytes, computed FreeBytes and UsagePercent.
    .OUTPUTS [PSCustomObject] A DrivePulse.ScanResult object
    #>
    $driveLetters = @('C', 'D', 'E', 'F', 'G')
    $drive = $driveLetters | Get-Random

    # TotalBytes: 1GB to 2TB range (avoid 0 to prevent division by zero)
    $totalBytes = [long](Get-Random -Minimum 1073741824 -Maximum 2199023255552)
    # UsedBytes: 0 to TotalBytes
    $usedBytes = [long](Get-Random -Minimum 0 -Maximum $totalBytes)
    $freeBytes = $totalBytes - $usedBytes
    $usagePercent = [math]::Round(($usedBytes / $totalBytes) * 100, 2)

    $elapsed = [math]::Round((Get-Random -Minimum 1 -Maximum 300) + (Get-Random -Minimum 0 -Maximum 100) / 100, 2)

    return [PSCustomObject]@{
        PSTypeName     = 'DrivePulse.ScanResult'
        DriveLetter    = $drive
        TotalBytes     = $totalBytes
        UsedBytes      = $usedBytes
        FreeBytes      = $freeBytes
        UsagePercent   = $usagePercent
        Items          = @()
        Errors         = @()
        ElapsedSeconds = $elapsed
    }
}

function New-RandomCategorizedItems {
    <#
    .SYNOPSIS Generates random array of CategorizedItem objects
    .DESCRIPTION Creates an array of DrivePulse.CategorizedItem objects with
                 random Safe and Check categories, valid paths, sizes, and
                 Bahasa Indonesia text fields.
    .PARAMETER Count Number of items to generate (default: random 1-20)
    .OUTPUTS [PSCustomObject[]] Array of DrivePulse.CategorizedItem objects
    #>
    param(
        [int]$Count = (Get-Random -Minimum 1 -Maximum 21)
    )

    $safeLabels = @(
        'Cache Browser', 'File Sementara', 'Log Sistem',
        'Thumbnail Cache', 'Windows Update Cache', 'npm Cache',
        'Recycle Bin', 'Crash Reports', 'Temp Files', 'Old Logs'
    )
    $checkLabels = @(
        'Downloads', 'CapCut Cache', 'Folder Besar',
        'Data Aplikasi', 'Backup Lama', 'Game Cache',
        'Docker Images', 'VM Snapshots', 'Old Projects', 'Media Files'
    )
    $sideEffects = @(
        'Browser perlu rebuild cache',
        'File akan dibuat ulang otomatis',
        'Log lama akan hilang',
        'Thumbnail akan di-generate ulang',
        'Update cache akan diunduh ulang',
        'Aplikasi perlu restart'
    )
    $reasons = @(
        'Mungkin berisi data penting',
        'Folder aplikasi aktif',
        'Perlu verifikasi manual',
        'Bisa berisi dokumen pengguna',
        'Ukuran melebihi threshold'
    )
    $recommendations = @(
        'Cek file terbesar, hapus installer lama',
        'Cek apakah ada project aktif',
        'Backup terlebih dahulu',
        'Periksa isi folder sebelum menghapus',
        'Pastikan aplikasi tidak sedang berjalan',
        'Hapus file yang lebih dari 30 hari'
    )

    $items = @()
    for ($i = 0; $i -lt $Count; $i++) {
        $category = @('Safe', 'Check') | Get-Random
        $path = New-RandomWindowsPath
        $sizeBytes = [long](Get-Random -Minimum 1024 -Maximum 107374182400)  # 1KB to 100GB

        if ($category -eq 'Safe') {
            $items += [PSCustomObject]@{
                PSTypeName     = 'DrivePulse.CategorizedItem'
                Path           = $path
                Label          = $safeLabels | Get-Random
                SizeBytes      = $sizeBytes
                Category       = 'Safe'
                SideEffect     = $sideEffects | Get-Random
                Reason         = ''
                Recommendation = ''
            }
        }
        else {
            $items += [PSCustomObject]@{
                PSTypeName     = 'DrivePulse.CategorizedItem'
                Path           = $path
                Label          = $checkLabels | Get-Random
                SizeBytes      = $sizeBytes
                Category       = 'Check'
                SideEffect     = ''
                Reason         = $reasons | Get-Random
                Recommendation = $recommendations | Get-Random
            }
        }
    }

    return $items
}

function New-RandomUserConfig {
    <#
    .SYNOPSIS Generates random valid UserConfig objects
    .DESCRIPTION Creates config objects with valid whitelist (0-100 entries),
                 blacklist (0-50 entries, each ≤260 chars), and largeFolderGB (0.1-100).
    .OUTPUTS [PSCustomObject] A valid UserConfig object
    #>
    $whitelistCount = Get-Random -Minimum 0 -Maximum 11  # 0-10 for practical testing
    $blacklistCount = Get-Random -Minimum 0 -Maximum 6   # 0-5 for practical testing

    $whitelist = @()
    for ($i = 0; $i -lt $whitelistCount; $i++) {
        $whitelist += New-RandomWindowsPath
    }

    $blacklist = @()
    for ($i = 0; $i -lt $blacklistCount; $i++) {
        $blacklist += New-RandomWindowsPath
    }

    # largeFolderGB: 0.1 to 100, up to 2 decimal places
    $largeFolderGB = [math]::Round((Get-Random -Minimum 1 -Maximum 1000) / 10, 2)
    if ($largeFolderGB -gt 100) { $largeFolderGB = 100 }
    if ($largeFolderGB -lt 0.1) { $largeFolderGB = 0.1 }

    return [PSCustomObject]@{
        Whitelist     = $whitelist
        Blacklist     = $blacklist
        LargeFolderGB = $largeFolderGB
    }
}

function New-RandomInvalidThreshold {
    <#
    .SYNOPSIS Generates random invalid largeFolderGB values
    .DESCRIPTION Creates values that are NOT valid thresholds: outside 0.1-100 range,
                 non-numeric types, negative numbers, extremely large values, etc.
    .OUTPUTS A random invalid threshold value (various types)
    #>
    $strategies = @(
        { 0 },
        { 0.05 },
        { -1 },
        { -(Get-Random -Minimum 1 -Maximum 1000) },
        { 100.01 },
        { Get-Random -Minimum 101 -Maximum 10000 },
        { "not a number" },
        { "abc" },
        { $null },
        { @(1, 2, 3) },
        { 0.09 },
        { 999999 }
    )

    return (& ($strategies | Get-Random))
}

# ─── Backup Module Generators (v1.3) ────────────────────────

function New-RandomSessionId {
    <#
    .SYNOPSIS Generates random session IDs in format YYYYMMDD-HHmmss-<6 hex>
    .DESCRIPTION Creates valid session IDs using random dates within the past year,
                 random times, and 6 random hex characters.
    .OUTPUTS [string] A valid session ID string
    #>
    $daysAgo = Get-Random -Minimum 0 -Maximum 365
    $date = (Get-Date).AddDays(-$daysAgo)
    $hour = Get-Random -Minimum 0 -Maximum 24
    $minute = Get-Random -Minimum 0 -Maximum 60
    $second = Get-Random -Minimum 0 -Maximum 60
    $date = $date.Date.AddHours($hour).AddMinutes($minute).AddSeconds($second)

    $hexChars = '0123456789abcdef'
    $hex = -join (1..6 | ForEach-Object { $hexChars[(Get-Random -Minimum 0 -Maximum 16)] })

    return $date.ToString('yyyyMMdd-HHmmss') + "-$hex"
}

function New-RandomFileContent {
    <#
    .SYNOPSIS Generates random byte arrays of varying sizes
    .DESCRIPTION Creates random binary content ranging from 1 byte to 1 MB.
                 Uses logarithmic distribution to cover small and large sizes.
    .PARAMETER MaxSize Maximum size in bytes (default 1MB)
    .OUTPUTS [byte[]] Random byte array
    #>
    param(
        [int]$MaxSize = 1048576
    )

    # Use logarithmic distribution for size variety
    $logMin = 0  # 2^0 = 1 byte
    $logMax = [Math]::Log($MaxSize, 2)
    $logSize = (Get-Random -Minimum ($logMin * 100) -Maximum ([int]($logMax * 100))) / 100
    $size = [Math]::Max(1, [int][Math]::Pow(2, $logSize))
    if ($size -gt $MaxSize) { $size = $MaxSize }

    $bytes = [byte[]]::new($size)
    $rng = [System.Random]::new()
    $rng.NextBytes($bytes)
    return , $bytes
}

function New-RandomRetentionDays {
    <#
    .SYNOPSIS Generates random retention day values (1-90)
    .DESCRIPTION Creates random integers in the valid retention range of 1 to 90 days.
    .OUTPUTS [int] A valid retention days value
    #>
    return Get-Random -Minimum 1 -Maximum 91
}

function New-RandomTimestamp {
    <#
    .SYNOPSIS Generates random ISO 8601 timestamps
    .DESCRIPTION Creates random timestamps spanning from 180 days in the past
                 to the current time, formatted in ISO 8601 with timezone offset.
    .PARAMETER DaysBack Maximum days in the past (default 180)
    .OUTPUTS [string] An ISO 8601 formatted timestamp string
    #>
    param(
        [int]$DaysBack = 180
    )

    $secondsBack = Get-Random -Minimum 0 -Maximum ($DaysBack * 86400)
    $timestamp = (Get-Date).AddSeconds(-$secondsBack)
    return $timestamp.ToString('yyyy-MM-ddTHH:mm:sszzz')
}

# ─── Audit Logger Generators (v1.3 Safety & Cleanup) ──────────────────────

function New-RandomAuditEntry {
    <#
    .SYNOPSIS Generates random audit entry parameters for property-based testing
    .DESCRIPTION Creates random combinations of valid action strings and Windows file
                 paths containing special characters (backslashes, spaces, unicode,
                 quotes, control characters) suitable for testing audit log serialization.
    .OUTPUTS [PSCustomObject] with Action and FilePath properties
    #>
    $actions = @('delete', 'backup', 'restore', 'stage', 'auto-purge', 'purge-failed')

    # Special character segments for path generation
    $specialSegments = @(
        'normal folder',
        'folder with spaces',
        'folder"with"quotes',
        "folder`twith`ttabs",
        'unicode_ñoño_日本語',
        'émojis_café_naïve',
        'path (with) parens',
        'dots...in...name',
        'ampersand & percent %',
        'brackets [1] {2}',
        'single''quote',
        'hash#tag',
        'dollar$sign',
        'at@symbol',
        'exclaim!mark',
        'tilde~path',
        'caret^char',
        'plus+minus-equal=',
        'semicolon;colon:',
        'comma,separated'
    )

    $driveLetters = @('C', 'D')
    $action = $actions | Get-Random
    $drive = $driveLetters | Get-Random

    # Build a path with 2-4 segments, mixing normal and special
    $depth = Get-Random -Minimum 2 -Maximum 5
    $pathSegments = @()
    for ($i = 0; $i -lt $depth; $i++) {
        $pathSegments += $specialSegments | Get-Random
    }

    # Append a filename with special chars
    $fileNames = @(
        'file.txt',
        'data "backup".log',
        'report (final).csv',
        'résumé.docx',
        'file with spaces.tmp',
        'log_2024-01-01.json',
        'café_naïve.dat'
    )
    $fileName = $fileNames | Get-Random

    # Build path using string concatenation to avoid Join-Path drive validation
    $filePath = "$drive`:\$($pathSegments -join '\')\$fileName"

    return [PSCustomObject]@{
        Action   = $action
        FilePath = $filePath
    }
}


# ─── Staging & Session Generators (v1.3) ──────────────────────

function New-RandomSessionId {
    <#
    .SYNOPSIS Generates random valid session IDs
    .DESCRIPTION Creates session IDs in the format YYYYMMDD-HHmmss-<6 hex chars>
    .OUTPUTS [string] A valid session ID string
    #>
    $year = Get-Random -Minimum 2024 -Maximum 2027
    $month = (Get-Random -Minimum 1 -Maximum 13).ToString('D2')
    $day = (Get-Random -Minimum 1 -Maximum 29).ToString('D2')
    $hour = (Get-Random -Minimum 0 -Maximum 24).ToString('D2')
    $minute = (Get-Random -Minimum 0 -Maximum 60).ToString('D2')
    $second = (Get-Random -Minimum 0 -Maximum 60).ToString('D2')
    $hex = -join ((1..6) | ForEach-Object { '{0:x}' -f (Get-Random -Minimum 0 -Maximum 16) })

    return "$year$month$day-$hour$minute$second-$hex"
}

function New-RandomFileContent {
    <#
    .SYNOPSIS Generates random binary content of varying sizes
    .DESCRIPTION Creates random byte arrays suitable for writing to test files.
    .PARAMETER MinSize Minimum size in bytes (default 1)
    .PARAMETER MaxSize Maximum size in bytes (default 4096)
    .OUTPUTS [byte[]] Random byte array
    #>
    param(
        [int]$MinSize = 1,
        [int]$MaxSize = 4096
    )

    $size = Get-Random -Minimum $MinSize -Maximum ($MaxSize + 1)
    $bytes = New-Object byte[] $size
    (New-Object System.Random).NextBytes($bytes)
    return $bytes
}

function New-RandomBackupManifest {
    <#
    .SYNOPSIS Generates random backup manifest objects for property testing
    .DESCRIPTION Creates a complete backup manifest with random session ID,
                 creation timestamp, and a random number of file entries with
                 valid paths, sizes, and timestamps.
    .PARAMETER FileCount Number of files in the manifest (default: random 1-10)
    .OUTPUTS [PSCustomObject] A backup manifest object with sessionId, createdAt, and files array
    #>
    param(
        [int]$FileCount = (Get-Random -Minimum 1 -Maximum 11)
    )

    $sessionId = New-RandomSessionId
    $createdAt = New-RandomTimestamp -DaysBack 30

    $files = @()
    for ($i = 0; $i -lt $FileCount; $i++) {
        $originalPath = New-RandomWindowsPath
        $fileName = "file_$(Get-Random).dat"
        $originalPath = "$originalPath\$fileName"

        # Build backup path: sessionId\drive-encoded\relative-path
        $driveLetter = $originalPath.Substring(0, 1)
        $relativePath = $originalPath.Substring(3)  # Skip "C:\"
        $backupPath = "$sessionId\${driveLetter}_drive\$relativePath"

        $sizeBytes = [long](Get-Random -Minimum 1024 -Maximum 107374182400)
        $timestamp = New-RandomTimestamp -DaysBack 30

        $files += [PSCustomObject]@{
            originalPath = $originalPath
            backupPath   = $backupPath
            sizeBytes    = $sizeBytes
            timestamp    = $timestamp
        }
    }

    return [PSCustomObject]@{
        sessionId = $sessionId
        createdAt = $createdAt
        files     = $files
    }
}

function New-RandomStagedFile {
    <#
    .SYNOPSIS Generates random staged file metadata and content for property testing
    .DESCRIPTION Creates a hashtable with random file path, content, and session ID
                 suitable for staging property tests. Paths are valid Windows absolute
                 paths with various safe characters.
    .OUTPUTS [hashtable] @{ Path; FileName; Content; SessionId }
    #>
    $driveLetters = @('C', 'D', 'E')
    $segments = @(
        'Users', 'Documents', 'Projects', 'AppData', 'Local',
        'Temp', 'Downloads', 'Desktop', 'Work', 'Data',
        'Cache', 'Logs', 'Archive', 'Tools', 'Backup'
    )
    $extensions = @('.txt', '.log', '.dat', '.tmp', '.cache', '.bak', '.json', '.xml')

    $drive = $driveLetters | Get-Random
    $depth = Get-Random -Minimum 1 -Maximum 5
    $subPath = ($segments | Get-Random -Count $depth) -join '\'
    $fileName = "file_$(Get-Random)$($extensions | Get-Random)"
    $fullPath = "$drive`:\$subPath\$fileName"

    $content = New-RandomFileContent -MinSize 10 -MaxSize 2048
    $sessionId = New-RandomSessionId

    return @{
        Path      = $fullPath
        FileName  = $fileName
        Content   = $content
        SessionId = $sessionId
    }
}
