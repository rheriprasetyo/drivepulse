<#
.SYNOPSIS
    DrivePulse — Format Utilities (Shared Module)
.DESCRIPTION
    Shared formatting functions used by both CLI display and report generation.
    Provides consistent size formatting, percentage formatting, and color coding.
.NOTES
    Author: DrivePulse Team
    Version: 1.2
#>

function Format-Size {
    <#
    .SYNOPSIS Formats bytes to human-readable GB or MB
    .PARAMETER Bytes Size in bytes
    .OUTPUTS [string] Formatted size string (e.g., "2.5 GB" or "350 MB")
    #>
    param([long]$Bytes)

    if ($Bytes -ge 1073741824) {
        # >= 1 GB: show as X.X GB (1 decimal place)
        $gb = [math]::Round($Bytes / 1073741824, 1)
        return "$gb GB"
    }
    else {
        # < 1 GB: show as X MB (no decimal, rounded)
        $mb = [math]::Round($Bytes / 1048576)
        return "$mb MB"
    }
}

function Format-SizeDetailed {
    <#
    .SYNOPSIS Formats bytes to human-readable KB/MB/GB with 2 decimal places
    .DESCRIPTION Used in HTML reports for more precise size display
    .PARAMETER Bytes Size in bytes
    .OUTPUTS [string] Formatted size string (e.g., "2.50 GB", "350.25 MB", "512.00 KB")
    #>
    param([long]$Bytes)

    if ($Bytes -ge 1073741824) {
        # >= 1 GB: show as X.XX GB
        $gb = [math]::Round($Bytes / 1073741824, 2)
        return "{0:F2} GB" -f $gb
    }
    elseif ($Bytes -ge 1048576) {
        # >= 1 MB and < 1 GB: show as X.XX MB
        $mb = [math]::Round($Bytes / 1048576, 2)
        return "{0:F2} MB" -f $mb
    }
    else {
        # < 1 MB: show as X.XX KB
        $kb = [math]::Round($Bytes / 1024, 2)
        return "{0:F2} KB" -f $kb
    }
}

function Format-Percent {
    <#
    .SYNOPSIS Formats a numeric value as a percentage string
    .PARAMETER Value The percentage value (e.g., 75.3)
    .OUTPUTS [string] Formatted percentage string (e.g., "75.3%")
    #>
    param([double]$Value)

    $rounded = [math]::Round($Value, 1)
    return "{0:F1}%" -f $rounded
}

function Get-ColorCode {
    <#
    .SYNOPSIS Returns hex color code based on drive usage percentage
    .DESCRIPTION Color coding: red (>90%), yellow (75-90%), green (<75%)
    .PARAMETER UsagePercent The drive usage percentage (0-100)
    .OUTPUTS [string] Hex color code (e.g., "#ff4757")
    #>
    param([double]$UsagePercent)

    if ($UsagePercent -gt 90) {
        return "#ff4757"
    }
    elseif ($UsagePercent -ge 75) {
        return "#ffa502"
    }
    else {
        return "#2ed573"
    }
}
