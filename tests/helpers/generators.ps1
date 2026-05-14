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
