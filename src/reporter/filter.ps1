<#
.SYNOPSIS
    DrivePulse — Whitelist/Blacklist Filter Module
.DESCRIPTION
    Provides filtering functions to apply user-configured whitelist and blacklist
    rules to categorized scan items. Whitelist removes Safe items from cleanup
    recommendations; blacklist adds custom folders as Safe items for deletion.
.NOTES
    Author: DrivePulse Team
    Version: 1.2
#>

function Invoke-WhitelistFilter {
    <#
    .SYNOPSIS Filters out Safe items that match whitelist entries
    .DESCRIPTION Removes CategorizedItem objects with Category=Safe whose Path
                 matches a whitelist entry (case-insensitive). A match is defined
                 as the item path being equal to or a subdirectory of a whitelist entry.
    .PARAMETER CategorizedItems Array of CategorizedItem objects
    .PARAMETER Whitelist Array of absolute Windows paths to protect
    .OUTPUTS [PSCustomObject[]] Filtered array with whitelisted Safe items removed
    #>
    param(
        [PSCustomObject[]]$CategorizedItems,
        [string[]]$Whitelist
    )

    # If no whitelist or no items, return as-is
    if ($null -eq $Whitelist -or $Whitelist.Count -eq 0) {
        return $CategorizedItems
    }
    if ($null -eq $CategorizedItems -or $CategorizedItems.Count -eq 0) {
        return @()
    }

    # Filter to only valid whitelist entries (must start with drive letter + :\)
    $validWhitelist = @($Whitelist | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and $_ -match '^[A-Za-z]:\\'
    })

    if ($validWhitelist.Count -eq 0) {
        return $CategorizedItems
    }

    # Normalize whitelist entries: ensure trailing backslash for subdirectory matching
    $normalizedWhitelist = @($validWhitelist | ForEach-Object {
        $_.TrimEnd('\')
    })

    $result = @()
    foreach ($item in $CategorizedItems) {
        # Only filter Safe category items
        if ($item.Category -eq 'Safe') {
            $isWhitelisted = $false
            $itemPath = if ($null -ne $item.Path) { $item.Path.TrimEnd('\') } else { '' }

            foreach ($wlEntry in $normalizedWhitelist) {
                # Case-insensitive: exact match or subdirectory match
                if ($itemPath -ieq $wlEntry) {
                    $isWhitelisted = $true
                    break
                }
                # Subdirectory check: item path starts with whitelist entry + backslash
                if ($itemPath -like "$wlEntry\*") {
                    $isWhitelisted = $true
                    break
                }
            }

            if (-not $isWhitelisted) {
                $result += $item
            }
        }
        else {
            # Non-Safe items pass through unchanged
            $result += $item
        }
    }

    return $result
}

function Invoke-BlacklistEnrich {
    <#
    .SYNOPSIS Adds blacklist folders as Safe items for cleanup
    .DESCRIPTION For each blacklist entry that exists on the filesystem and is not
                 in the whitelist, adds a CategorizedItem with Category=Safe to the
                 items array. Whitelist takes priority over blacklist.
    .PARAMETER CategorizedItems Array of CategorizedItem objects
    .PARAMETER Blacklist Array of absolute Windows paths to always recommend for deletion
    .PARAMETER Whitelist Array of absolute Windows paths that take priority (protected)
    .OUTPUTS [PSCustomObject[]] Enriched array with blacklist items added
    #>
    param(
        [PSCustomObject[]]$CategorizedItems,
        [string[]]$Blacklist,
        [string[]]$Whitelist
    )

    # Start with existing items
    $result = @()
    if ($null -ne $CategorizedItems) {
        $result = @($CategorizedItems)
    }

    # If no blacklist, return as-is
    if ($null -eq $Blacklist -or $Blacklist.Count -eq 0) {
        return $result
    }

    # Filter to only valid blacklist entries (must start with drive letter + :\)
    $validBlacklist = @($Blacklist | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and $_ -match '^[A-Za-z]:\\'
    })

    # Normalize whitelist for priority check
    $normalizedWhitelist = @()
    if ($null -ne $Whitelist -and $Whitelist.Count -gt 0) {
        $normalizedWhitelist = @($Whitelist | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_) -and $_ -match '^[A-Za-z]:\\'
        } | ForEach-Object { $_.TrimEnd('\') })
    }

    foreach ($blEntry in $validBlacklist) {
        $normalizedBl = $blEntry.TrimEnd('\')

        # Whitelist takes priority: skip if path is in whitelist or is subdirectory of whitelist
        $isProtected = $false
        foreach ($wlEntry in $normalizedWhitelist) {
            if ($normalizedBl -ieq $wlEntry) {
                $isProtected = $true
                break
            }
            # Also check if blacklist entry is a subdirectory of whitelist entry
            if ($normalizedBl -like "$wlEntry\*") {
                $isProtected = $true
                break
            }
        }

        if ($isProtected) {
            continue
        }

        # Skip non-existent paths silently
        if (-not (Test-Path $blEntry)) {
            continue
        }

        # Get folder size
        $folderSize = 0
        try {
            $folderSize = (Get-ChildItem -Path $blEntry -Recurse -File -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            if ($null -eq $folderSize) { $folderSize = 0 }
        }
        catch {
            $folderSize = 0
        }

        # Extract folder name from path for Label
        $folderName = Split-Path -Path $blEntry -Leaf

        # Add as Safe item
        $blacklistItem = [PSCustomObject]@{
            PSTypeName     = 'DrivePulse.CategorizedItem'
            Path           = $blEntry
            Label          = $folderName
            SizeBytes      = [long]$folderSize
            Category       = 'Safe'
            SideEffect     = 'User-defined blacklist item'
            Reason         = ''
            Recommendation = 'Folder ditandai oleh user untuk dihapus'
        }

        $result += $blacklistItem
    }

    return $result
}
