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
