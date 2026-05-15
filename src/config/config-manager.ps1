<#
.SYNOPSIS
    DrivePulse — User Configuration Manager
.DESCRIPTION
    Manages reading and writing of user preferences (whitelist, blacklist,
    large folder threshold) stored in %LOCALAPPDATA%\DrivePulse\config.json.
    Provides validation, default creation, and threshold resolution.
.NOTES
    Author: DrivePulse Team
    Version: 1.2
#>

# ─── Constants ──────────────────────────────────────────────

$script:ConfigDir = Join-Path $env:LOCALAPPDATA 'DrivePulse'
$script:ConfigPath = Join-Path $script:ConfigDir 'config.json'
$script:DefaultConfig = [PSCustomObject]@{
    Whitelist            = @()
    Blacklist            = @()
    LargeFolderGB        = 5
    BackupRetentionDays  = 7
    StagingRetentionDays = 7
}

# ─── Functions ──────────────────────────────────────────────

function Test-ValidWindowsPath {
    <#
    .SYNOPSIS Validates that a path is an absolute Windows path
    .DESCRIPTION Returns $true if the path starts with a drive letter followed by :\
    .PARAMETER Path The path string to validate
    .OUTPUTS [bool]
    #>
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    # Must start with a drive letter (A-Z) followed by :\
    return $Path -match '^[A-Za-z]:\\'
}

function Get-UserConfig {
    <#
    .SYNOPSIS Reads user configuration from disk
    .DESCRIPTION Reads %LOCALAPPDATA%\DrivePulse\config.json, creates default
                 config if missing, warns on invalid JSON and falls back to defaults.
    .OUTPUTS [PSCustomObject] with Whitelist, Blacklist, LargeFolderGB properties
    #>

    # Ensure config directory exists
    if (-not (Test-Path $script:ConfigDir)) {
        New-Item -ItemType Directory -Path $script:ConfigDir -Force | Out-Null
    }

    # If config file doesn't exist, create with defaults
    if (-not (Test-Path $script:ConfigPath)) {
        $defaultJson = @{
            whitelist            = @()
            blacklist            = @()
            largeFolderGB        = 5
            backupRetentionDays  = 7
            stagingRetentionDays = 7
        } | ConvertTo-Json -Depth 5
        # Write with UTF-8 encoding and 2-space indentation
        [System.IO.File]::WriteAllText($script:ConfigPath, $defaultJson, [System.Text.UTF8Encoding]::new($false))
        return [PSCustomObject]@{
            Whitelist            = @()
            Blacklist            = @()
            LargeFolderGB        = 5
            BackupRetentionDays  = 7
            StagingRetentionDays = 7
        }
    }

    # Read and parse config file
    try {
        $content = [System.IO.File]::ReadAllText($script:ConfigPath, [System.Text.UTF8Encoding]::new($false))
        $parsed = $content | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Warning "⚠️ File konfigurasi rusak. Menggunakan pengaturan default."
        return [PSCustomObject]@{
            Whitelist            = @()
            Blacklist            = @()
            LargeFolderGB        = 5
            BackupRetentionDays  = 7
            StagingRetentionDays = 7
        }
    }

    # Extract and validate fields
    $whitelist = @()
    if ($null -ne $parsed.whitelist -and $parsed.whitelist -is [System.Array]) {
        $whitelist = @($parsed.whitelist | Where-Object { Test-ValidWindowsPath $_ })
    }
    elseif ($null -ne $parsed.whitelist -and $parsed.whitelist -is [string]) {
        if (Test-ValidWindowsPath $parsed.whitelist) {
            $whitelist = @($parsed.whitelist)
        }
    }

    $blacklist = @()
    if ($null -ne $parsed.blacklist -and $parsed.blacklist -is [System.Array]) {
        $blacklist = @($parsed.blacklist | Where-Object { Test-ValidWindowsPath $_ })
    }
    elseif ($null -ne $parsed.blacklist -and $parsed.blacklist -is [string]) {
        if (Test-ValidWindowsPath $parsed.blacklist) {
            $blacklist = @($parsed.blacklist)
        }
    }

    # Validate largeFolderGB
    $largeFolderGB = 5
    if ($null -ne $parsed.largeFolderGB) {
        $value = $parsed.largeFolderGB
        if ($value -is [double] -or $value -is [int] -or $value -is [long] -or $value -is [decimal]) {
            $numValue = [double]$value
            if ($numValue -ge 0.1 -and $numValue -le 100) {
                $largeFolderGB = [math]::Round($numValue, 2)
            }
            else {
                Write-Warning "⚠️ Nilai largeFolderGB tidak valid ($value). Menggunakan default: 5 GB."
            }
        }
        else {
            Write-Warning "⚠️ Nilai largeFolderGB tidak valid ($value). Menggunakan default: 5 GB."
        }
    }

    # Validate backupRetentionDays (1-90, default 7)
    $backupRetentionDays = 7
    if ($null -ne $parsed.backupRetentionDays) {
        $value = $parsed.backupRetentionDays
        if ($value -is [int] -or $value -is [long] -or ($value -is [double] -and $value -eq [math]::Floor($value))) {
            $intValue = [int]$value
            if ($intValue -ge 1 -and $intValue -le 90) {
                $backupRetentionDays = $intValue
            }
            else {
                Write-Warning "⚠️ Nilai backupRetentionDays tidak valid ($value). Harus antara 1-90 hari. Menggunakan default: 7 hari."
            }
        }
        else {
            Write-Warning "⚠️ Nilai backupRetentionDays tidak valid ($value). Harus berupa bilangan bulat 1-90. Menggunakan default: 7 hari."
        }
    }

    # Validate stagingRetentionDays (1-90, default 7)
    $stagingRetentionDays = 7
    if ($null -ne $parsed.stagingRetentionDays) {
        $value = $parsed.stagingRetentionDays
        if ($value -is [int] -or $value -is [long] -or ($value -is [double] -and $value -eq [math]::Floor($value))) {
            $intValue = [int]$value
            if ($intValue -ge 1 -and $intValue -le 90) {
                $stagingRetentionDays = $intValue
            }
            else {
                Write-Warning "⚠️ Nilai stagingRetentionDays tidak valid ($value). Harus antara 1-90 hari. Menggunakan default: 7 hari."
            }
        }
        else {
            Write-Warning "⚠️ Nilai stagingRetentionDays tidak valid ($value). Harus berupa bilangan bulat 1-90. Menggunakan default: 7 hari."
        }
    }

    return [PSCustomObject]@{
        Whitelist            = $whitelist
        Blacklist            = $blacklist
        LargeFolderGB        = $largeFolderGB
        BackupRetentionDays  = $backupRetentionDays
        StagingRetentionDays = $stagingRetentionDays
    }
}

function Save-UserConfig {
    <#
    .SYNOPSIS Saves user configuration to disk
    .DESCRIPTION Validates constraints and writes UTF-8 JSON with 2-space indentation.
    .PARAMETER Config PSCustomObject with Whitelist, Blacklist, LargeFolderGB
    .OUTPUTS [PSCustomObject] with Success and Error properties
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )

    # Validate largeFolderGB
    $largeFolderGB = $Config.LargeFolderGB
    if ($null -eq $largeFolderGB) {
        return [PSCustomObject]@{ Success = $false; Error = "largeFolderGB tidak boleh null." }
    }
    try {
        $numValue = [double]$largeFolderGB
    }
    catch {
        return [PSCustomObject]@{ Success = $false; Error = "largeFolderGB harus berupa angka." }
    }
    if ($numValue -lt 0.1 -or $numValue -gt 100) {
        return [PSCustomObject]@{ Success = $false; Error = "largeFolderGB harus antara 0.1 dan 100." }
    }

    # Validate whitelist
    $whitelist = @()
    if ($null -ne $Config.Whitelist) {
        if ($Config.Whitelist -is [System.Array]) {
            $whitelist = @($Config.Whitelist)
        }
        else {
            $whitelist = @($Config.Whitelist)
        }
    }
    if ($whitelist.Count -gt 100) {
        return [PSCustomObject]@{ Success = $false; Error = "Whitelist tidak boleh lebih dari 100 entri." }
    }

    # Validate blacklist
    $blacklist = @()
    if ($null -ne $Config.Blacklist) {
        if ($Config.Blacklist -is [System.Array]) {
            $blacklist = @($Config.Blacklist)
        }
        else {
            $blacklist = @($Config.Blacklist)
        }
    }
    if ($blacklist.Count -gt 50) {
        return [PSCustomObject]@{ Success = $false; Error = "Blacklist tidak boleh lebih dari 50 entri." }
    }

    # Validate each blacklist entry length
    foreach ($entry in $blacklist) {
        if ($null -ne $entry -and $entry.Length -gt 260) {
            return [PSCustomObject]@{ Success = $false; Error = "Entri blacklist tidak boleh lebih dari 260 karakter." }
        }
    }

    # Filter valid paths for storage
    $validWhitelist = @($whitelist | Where-Object { Test-ValidWindowsPath $_ })
    $validBlacklist = @($blacklist | Where-Object { Test-ValidWindowsPath $_ })

    # Ensure config directory exists
    if (-not (Test-Path $script:ConfigDir)) {
        try {
            New-Item -ItemType Directory -Path $script:ConfigDir -Force | Out-Null
        }
        catch {
            return [PSCustomObject]@{ Success = $false; Error = "❌ Gagal menyimpan konfigurasi: akses ditolak." }
        }
    }

    # Build JSON object with 2-space indentation
    $configObj = [ordered]@{
        whitelist            = $validWhitelist
        blacklist            = $validBlacklist
        largeFolderGB        = [math]::Round($numValue, 2)
        backupRetentionDays  = 7
        stagingRetentionDays = 7
    }

    # Include retention days if provided and valid
    if ($null -ne $Config.BackupRetentionDays) {
        try {
            $brd = [int]$Config.BackupRetentionDays
            if ($brd -ge 1 -and $brd -le 90) {
                $configObj.backupRetentionDays = $brd
            }
        }
        catch { }
    }
    if ($null -ne $Config.StagingRetentionDays) {
        try {
            $srd = [int]$Config.StagingRetentionDays
            if ($srd -ge 1 -and $srd -le 90) {
                $configObj.stagingRetentionDays = $srd
            }
        }
        catch { }
    }

    try {
        $json = $configObj | ConvertTo-Json -Depth 5
        # Ensure 2-space indentation (PowerShell default may vary)
        $json = $json -replace "`t", '  '
        [System.IO.File]::WriteAllText($script:ConfigPath, $json, [System.Text.UTF8Encoding]::new($false))
    }
    catch [System.UnauthorizedAccessException] {
        return [PSCustomObject]@{ Success = $false; Error = "❌ Gagal menyimpan konfigurasi: akses ditolak." }
    }
    catch [System.IO.IOException] {
        if ($_.Exception.Message -match 'disk|space|full') {
            return [PSCustomObject]@{ Success = $false; Error = "❌ Gagal menyimpan konfigurasi: disk penuh." }
        }
        return [PSCustomObject]@{ Success = $false; Error = "❌ Gagal menyimpan konfigurasi: $($_.Exception.Message)" }
    }
    catch {
        return [PSCustomObject]@{ Success = $false; Error = "❌ Gagal menyimpan konfigurasi: $($_.Exception.Message)" }
    }

    return [PSCustomObject]@{ Success = $true; Error = $null }
}

function Get-EffectiveThreshold {
    <#
    .SYNOPSIS Resolves the effective large folder threshold
    .DESCRIPTION Returns largeFolderGB from user config if valid (0.1-100),
                 otherwise returns the default from default-rules.json.
    .PARAMETER UserConfig PSCustomObject from Get-UserConfig
    .PARAMETER DefaultRules PSCustomObject parsed from default-rules.json
    .OUTPUTS [double] The effective threshold in GB
    #>
    param(
        [PSCustomObject]$UserConfig,
        [PSCustomObject]$DefaultRules
    )

    # Get default threshold from rules
    $defaultThreshold = 5
    if ($null -ne $DefaultRules -and $null -ne $DefaultRules.thresholds -and $null -ne $DefaultRules.thresholds.largeFolderGB) {
        $defaultThreshold = [double]$DefaultRules.thresholds.largeFolderGB
    }

    # If no user config or no largeFolderGB field, use default
    if ($null -eq $UserConfig) {
        return $defaultThreshold
    }

    $value = $UserConfig.LargeFolderGB
    if ($null -eq $value) {
        return $defaultThreshold
    }

    # Validate the user config value
    try {
        $numValue = [double]$value
    }
    catch {
        Write-Warning "⚠️ Nilai largeFolderGB tidak valid ($value). Menggunakan default: $defaultThreshold GB."
        return $defaultThreshold
    }

    if ($numValue -ge 0.1 -and $numValue -le 100) {
        return $numValue
    }

    Write-Warning "⚠️ Nilai largeFolderGB tidak valid ($value). Menggunakan default: $defaultThreshold GB."
    return $defaultThreshold
}
