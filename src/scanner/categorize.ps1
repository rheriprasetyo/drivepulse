<#
.SYNOPSIS
    DrivePulse — Kategorisasi Module
.DESCRIPTION
    Kategorikan folder/file hasil scan menjadi:
    - Aman dihapus (safe)
    - Perlu dicek manual (check)
    Berdasarkan rules di config/default-rules.json
.NOTES
    Author: DrivePulse Team
    Version: 1.1
#>

# Import types
. "$PSScriptRoot\types.ps1"

function Initialize-Rules {
    <#
    .SYNOPSIS Loads and validates the rules file
    .PARAMETER RulesFile Path to default-rules.json
    .OUTPUTS [PSCustomObject] Parsed rules object
    .THROWS Terminates with error message if file missing or invalid JSON
    #>
    param([string]$RulesFile)

    # Check if rules file exists
    if (-not (Test-Path $RulesFile)) {
        Write-Host "❌ File aturan tidak ditemukan: $RulesFile" -ForegroundColor Red
        exit 1
    }

    # Read and parse JSON
    try {
        $content = Get-Content $RulesFile -Raw -Encoding UTF8
        $rules = $content | ConvertFrom-Json
    } catch {
        Write-Host "❌ File aturan rusak (JSON tidak valid)." -ForegroundColor Red
        Write-Host "   Detail: $($_.Exception.Message)" -ForegroundColor Gray
        exit 1
    }

    # Validate required structure
    if (-not $rules.thresholds -or -not $rules.categories) {
        Write-Host "❌ Struktur file aturan tidak lengkap." -ForegroundColor Red
        exit 1
    }

    return $rules
}

function Get-ItemCategory {
    <#
    .SYNOPSIS Categorizes a single scan item against loaded rules
    .PARAMETER ScanItem A DrivePulse.ScanItem object
    .PARAMETER Rules Parsed rules object from Initialize-Rules
    .PARAMETER IsAdmin Whether script is running elevated
    .OUTPUTS DrivePulse.CategorizedItem
    #>
    param(
        [PSCustomObject]$ScanItem,
        [PSCustomObject]$Rules,
        [bool]$IsAdmin = $false
    )

    # 1. Normalize item path for case-insensitive comparison
    $itemPathNormalized = $ScanItem.Path.ToLower()

    # 2. Get the large folder threshold from rules
    $thresholdBytes = [long]($Rules.thresholds.largeFolderGB * 1GB)

    # 3. Search safe items for a path match
    foreach ($safeRule in $Rules.categories.safe.items) {
        # Resolve environment variables in the rule path
        $rulePath = [System.Environment]::ExpandEnvironmentVariables($safeRule.path)
        $rulePathNormalized = $rulePath.ToLower()

        if ($itemPathNormalized -eq $rulePathNormalized) {
            # Determine if admin is required
            $needsAdmin = $false
            if ($safeRule.requiresAdmin -eq $true -and -not $IsAdmin) {
                $needsAdmin = $true
            }

            return New-CategorizedItem `
                -ScanItem $ScanItem `
                -Category ([ItemCategory]::Safe) `
                -SideEffect $safeRule.sideEffect `
                -RequiresAdmin $needsAdmin
        }
    }

    # 4. Search check items for a path match (skip wildcard entries)
    foreach ($checkRule in $Rules.categories.check.items) {
        # Skip wildcard entries (path = "*")
        if ($checkRule.path -eq '*') {
            continue
        }

        # Resolve environment variables in the rule path
        $rulePath = [System.Environment]::ExpandEnvironmentVariables($checkRule.path)
        $rulePathNormalized = $rulePath.ToLower()

        if ($itemPathNormalized -eq $rulePathNormalized) {
            # Determine if admin is required
            $needsAdmin = $false
            if ($checkRule.requiresAdmin -eq $true -and -not $IsAdmin) {
                $needsAdmin = $true
            }

            return New-CategorizedItem `
                -ScanItem $ScanItem `
                -Category ([ItemCategory]::Check) `
                -Reason $checkRule.reason `
                -Recommendation $checkRule.recommendation `
                -RequiresAdmin $needsAdmin
        }
    }

    # 5. No match found — categorize based on size threshold
    if ($ScanItem.SizeBytes -ge $thresholdBytes) {
        return New-CategorizedItem `
            -ScanItem $ScanItem `
            -Category ([ItemCategory]::Check) `
            -Reason "Folder besar tanpa aturan spesifik"
    }

    # 6. No match and below threshold — Unknown
    return New-CategorizedItem `
        -ScanItem $ScanItem `
        -Category ([ItemCategory]::Unknown)
}

function Get-AllCategories {
    <#
    .SYNOPSIS Categorizes all items in a scan result
    .PARAMETER ScanResult A DrivePulse.ScanResult object
    .PARAMETER Rules Parsed rules object
    .PARAMETER IsAdmin Whether script is running elevated
    .OUTPUTS DrivePulse.CategorizedItem[]
    #>
    param(
        [PSCustomObject]$ScanResult,
        [PSCustomObject]$Rules,
        [bool]$IsAdmin = $false
    )

    $results = @()

    foreach ($item in $ScanResult.Items) {
        $categorized = Get-ItemCategory -ScanItem $item -Rules $Rules -IsAdmin $IsAdmin
        if ($null -ne $categorized) {
            $results += $categorized
        }
    }

    return $results
}
