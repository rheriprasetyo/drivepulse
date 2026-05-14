<#
.SYNOPSIS
    DrivePulse — Type Definitions
.DESCRIPTION
    Shared data structures and enumerations used across all DrivePulse modules.
    Defines ScanMode and ItemCategory enums, plus factory functions for
    ScanItem, CategorizedItem, ScanResult, and ScanError objects.
.NOTES
    Author: DrivePulse Team
    Version: 1.1
#>

# ─── Enumerations ───────────────────────────────────────────

enum ScanMode {
    Quick
    Deep
}

enum ItemCategory {
    Safe
    Check
    Unknown
}

# ─── Data Structures (PSCustomObject factories) ─────────────

function New-ScanItem {
    <#
    .SYNOPSIS Creates a scan result item
    .PARAMETER Path     Resolved file system path
    .PARAMETER Label    Human-readable label (Bahasa Indonesia)
    .PARAMETER SizeBytes Total size in bytes
    .PARAMETER IsAccessible Whether the path was readable
    #>
    param(
        [string]$Path,
        [string]$Label,
        [long]$SizeBytes,
        [bool]$IsAccessible = $true
    )
    [PSCustomObject]@{
        PSTypeName   = 'DrivePulse.ScanItem'
        Path         = $Path
        Label        = $Label
        SizeBytes    = $SizeBytes
        IsAccessible = $IsAccessible
    }
}

function New-CategorizedItem {
    <#
    .SYNOPSIS Creates a categorized result item
    .PARAMETER ScanItem      The original scan item
    .PARAMETER Category      Safe | Check | Unknown
    .PARAMETER SideEffect    Side effect description (safe items)
    .PARAMETER Reason        Reason for manual check (check items)
    .PARAMETER Recommendation Recommendation text (check items)
    .PARAMETER RequiresAdmin Whether admin rights needed
    #>
    param(
        [PSCustomObject]$ScanItem,
        [ItemCategory]$Category,
        [string]$SideEffect = "",
        [string]$Reason = "",
        [string]$Recommendation = "",
        [bool]$RequiresAdmin = $false
    )
    [PSCustomObject]@{
        PSTypeName     = 'DrivePulse.CategorizedItem'
        Path           = $ScanItem.Path
        Label          = $ScanItem.Label
        SizeBytes      = $ScanItem.SizeBytes
        Category       = $Category
        SideEffect     = $SideEffect
        Reason         = $Reason
        Recommendation = $Recommendation
        RequiresAdmin  = $RequiresAdmin
    }
}

function New-ScanResult {
    <#
    .SYNOPSIS Creates the top-level scan result container
    .PARAMETER Mode         Quick or Deep scan mode
    .PARAMETER DriveLetter  Target drive letter
    .PARAMETER UsedBytes    Used space in bytes
    .PARAMETER FreeBytes    Free space in bytes
    .PARAMETER Items        Array of ScanItem objects
    .PARAMETER Errors       Array of ScanError objects
    .PARAMETER ElapsedSeconds Time taken for the scan
    #>
    param(
        [ScanMode]$Mode,
        [string]$DriveLetter,
        [long]$UsedBytes,
        [long]$FreeBytes,
        [PSCustomObject[]]$Items,
        [PSCustomObject[]]$Errors,
        [double]$ElapsedSeconds
    )
    [PSCustomObject]@{
        PSTypeName     = 'DrivePulse.ScanResult'
        Mode           = $Mode
        DriveLetter    = $DriveLetter
        UsedBytes      = $UsedBytes
        FreeBytes      = $FreeBytes
        TotalBytes     = $UsedBytes + $FreeBytes
        UsagePercent   = [math]::Round(($UsedBytes / ($UsedBytes + $FreeBytes)) * 100, 1)
        Items          = $Items
        Errors         = $Errors
        ElapsedSeconds = $ElapsedSeconds
        Timestamp      = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    }
}

function New-ScanError {
    <#
    .SYNOPSIS Creates an error record for skipped folders
    .PARAMETER Path    Path of the inaccessible folder
    .PARAMETER Message Error message describing the issue
    #>
    param(
        [string]$Path,
        [string]$Message
    )
    [PSCustomObject]@{
        PSTypeName = 'DrivePulse.ScanError'
        Path       = $Path
        Message    = $Message
        Timestamp  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    }
}
