<#
.SYNOPSIS
    DrivePulse — Main Scanner Module
.DESCRIPTION
    Scan drive C: dan deteksi folder terbesar.
    Mendukung Quick Scan (top-level) dan Deep Scan (recursive).
.NOTES
    Author: DrivePulse Team
    Version: 1.1
#>

# Import types
. "$PSScriptRoot\types.ps1"

function Resolve-RulePath {
    <#
    .SYNOPSIS Resolves environment variables in a path string
    .DESCRIPTION Replaces known environment variable placeholders (%TEMP%, %LOCALAPPDATA%,
                 %APPDATA%, %USERPROFILE%) with their actual values, then attempts to resolve
                 any remaining %VAR% patterns via [System.Environment]::GetEnvironmentVariable.
                 Unknown/unset environment variables are left as-is in the path.
    .PARAMETER RawPath Path with %VAR% placeholders
    .OUTPUTS [string] Resolved absolute path
    #>
    param([string]$RawPath)

    # Map of known environment variable placeholders to their env var names
    $knownVars = @{
        '%TEMP%'         = 'TEMP'
        '%LOCALAPPDATA%' = 'LOCALAPPDATA'
        '%APPDATA%'      = 'APPDATA'
        '%USERPROFILE%'  = 'USERPROFILE'
    }

    $resolved = $RawPath

    # First pass: resolve the known/common variables
    foreach ($placeholder in $knownVars.Keys) {
        if ($resolved -like "*$placeholder*") {
            $envValue = [System.Environment]::GetEnvironmentVariable($knownVars[$placeholder])
            if ($envValue) {
                $resolved = $resolved -replace [regex]::Escape($placeholder), $envValue
            }
        }
    }

    # Second pass: attempt to resolve any remaining %VAR% patterns
    $pattern = '%([^%]+)%'
    $resolved = [regex]::Replace($resolved, $pattern, {
        param($match)
        $varName = $match.Groups[1].Value
        $envValue = [System.Environment]::GetEnvironmentVariable($varName)
        if ($envValue) {
            return $envValue
        }
        # Unknown/unset variable — leave placeholder as-is
        return $match.Value
    })

    return $resolved
}

function Get-FolderSize {
    <#
    .SYNOPSIS Calculates total size of a folder (recursive)
    .PARAMETER Path Folder path to measure
    .OUTPUTS [long] Total size in bytes, or -1 if inaccessible
    #>
    param([string]$Path)

    # Return -1 if the folder does not exist
    if (-not (Test-Path -LiteralPath $Path)) {
        return [long]-1
    }

    try {
        $files = Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue
        
        if ($null -eq $files -or @($files).Count -eq 0) {
            return [long]0
        }

        $measurement = $files | Measure-Object -Property Length -Sum

        if ($null -eq $measurement -or $null -eq $measurement.Sum) {
            return [long]0
        }

        return [long]$measurement.Sum
    }
    catch [System.UnauthorizedAccessException] {
        return [long]-1
    }
    catch {
        return [long]-1
    }
}

function Start-DriveScan {
    <#
    .SYNOPSIS Scans drive C: in Quick or Deep mode
    .PARAMETER Mode   Quick (top-level + known junk) or Deep (recursive)
    .PARAMETER DriveLetter Target drive letter (default "C")
    .PARAMETER RulesFile Path to rules JSON (for known locations in Quick mode)
    .PARAMETER ProgressCallback Optional scriptblock called to report progress
    .OUTPUTS DrivePulse.ScanResult
    #>
    param(
        [ValidateSet("Quick", "Deep")]
        [string]$Mode = "Quick",

        [string]$DriveLetter = "C",

        [string]$RulesFile = "$PSScriptRoot\..\..\config\default-rules.json",

        [scriptblock]$ProgressCallback = $null
    )

    # Start timing
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $items = @()
    $errors = @()

    if ($Mode -eq "Quick") {
        # ─── Quick Scan Mode ────────────────────────────────────────────

        # Load rules file
        $rulesContent = Get-Content -Path $RulesFile -Raw -Encoding UTF8
        $rules = $rulesContent | ConvertFrom-Json

        # Extract all paths from categories.safe.items and categories.check.items
        $ruleEntries = @()
        foreach ($item in $rules.categories.safe.items) {
            $ruleEntries += @{ Path = $item.path; Label = $item.label }
        }
        foreach ($item in $rules.categories.check.items) {
            # Skip wildcard entries (e.g., "large-folders" with path "*")
            if ($item.path -ne '*') {
                $ruleEntries += @{ Path = $item.path; Label = $item.label }
            }
        }

        $totalEntries = $ruleEntries.Count
        $currentIndex = 0

        foreach ($entry in $ruleEntries) {
            $currentIndex++

            # Resolve environment variables in the path
            $resolvedPath = Resolve-RulePath -RawPath $entry.Path

            # Report progress if callback provided
            if ($ProgressCallback) {
                & $ProgressCallback $resolvedPath $currentIndex $totalEntries
            }

            # Skip paths that don't exist
            if (-not (Test-Path -LiteralPath $resolvedPath)) {
                continue
            }

            # Measure folder size
            $size = Get-FolderSize -Path $resolvedPath

            if ($size -eq -1) {
                # Inaccessible folder — record error and create item with IsAccessible=$false
                $errors += New-ScanError -Path $resolvedPath -Message "Akses ditolak: tidak dapat membaca folder"
                $items += New-ScanItem -Path $resolvedPath -Label $entry.Label -SizeBytes 0 -IsAccessible $false
            }
            else {
                # Accessible folder — create normal scan item
                $items += New-ScanItem -Path $resolvedPath -Label $entry.Label -SizeBytes $size -IsAccessible $true
            }
        }
    }
    else {
        # ─── Deep Scan Mode ─────────────────────────────────────────────

        # Get drive info
        $drive = Get-PSDrive -Name $DriveLetter
        $usedBytes = [long]$drive.Used
        $freeBytes = [long]$drive.Free

        # Load rules file and extract thresholds.largeFolderGB value
        $rulesContent = Get-Content -Path $RulesFile -Raw -Encoding UTF8
        $rules = $rulesContent | ConvertFrom-Json
        $thresholdGB = $rules.thresholds.largeFolderGB
        $thresholdBytes = [long]($thresholdGB * 1GB)

        # Get top-level directories of the drive root
        $driveRoot = "${DriveLetter}:\"
        $topLevelDirs = @()
        try {
            $topLevelDirs = @(Get-ChildItem -LiteralPath $driveRoot -Directory -Force -ErrorAction SilentlyContinue)
        }
        catch {
            # If we can't enumerate the root, return empty result
        }

        $totalTopLevel = $topLevelDirs.Count
        $currentTopIndex = 0

        # For each top-level directory, recursively enumerate subfolders
        foreach ($topDir in $topLevelDirs) {
            $currentTopIndex++

            # Report progress for the top-level directory
            if ($ProgressCallback) {
                $percent = [math]::Round(($currentTopIndex / [math]::Max($totalTopLevel, 1)) * 100)
                & $ProgressCallback $topDir.FullName $percent
            }

            # Calculate size of the top-level directory itself
            $topDirSize = Get-FolderSize -Path $topDir.FullName
            if ($topDirSize -eq -1) {
                # Access denied on top-level directory
                $errors += New-ScanError -Path $topDir.FullName -Message "Akses ditolak: $($topDir.FullName)"
            }
            else {
                if ($topDirSize -ge $thresholdBytes) {
                    $items += New-ScanItem -Path $topDir.FullName -Label $topDir.Name -SizeBytes $topDirSize -IsAccessible $true
                }
            }

            # Recursively enumerate subfolders
            try {
                $subFolders = @(Get-ChildItem -LiteralPath $topDir.FullName -Directory -Recurse -Force -ErrorAction SilentlyContinue 2>&1)

                foreach ($folderItem in $subFolders) {
                    if ($folderItem -is [System.Management.Automation.ErrorRecord]) {
                        # Handle access denied errors from recursive enumeration
                        if ($folderItem.Exception -is [System.UnauthorizedAccessException]) {
                            $errorPath = if ($folderItem.TargetObject) { $folderItem.TargetObject.ToString() } else { $folderItem.Exception.Message }
                            $errors += New-ScanError -Path $errorPath -Message "Akses ditolak: $errorPath"
                        }
                        continue
                    }

                    if ($folderItem -isnot [System.IO.DirectoryInfo]) {
                        continue
                    }

                    # Report progress for subfolder
                    if ($ProgressCallback) {
                        $percent = [math]::Round(($currentTopIndex / [math]::Max($totalTopLevel, 1)) * 100)
                        & $ProgressCallback $folderItem.FullName $percent
                    }

                    # Calculate folder size
                    $folderSize = Get-FolderSize -Path $folderItem.FullName
                    if ($folderSize -eq -1) {
                        # Access denied
                        $errors += New-ScanError -Path $folderItem.FullName -Message "Akses ditolak: $($folderItem.FullName)"
                    }
                    elseif ($folderSize -ge $thresholdBytes) {
                        $items += New-ScanItem -Path $folderItem.FullName -Label $folderItem.Name -SizeBytes $folderSize -IsAccessible $true
                    }
                }
            }
            catch [System.UnauthorizedAccessException] {
                $errors += New-ScanError -Path $topDir.FullName -Message "Akses ditolak saat enumerasi: $($topDir.FullName)"
            }
            catch {
                $errors += New-ScanError -Path $topDir.FullName -Message "Error saat enumerasi: $($_.Exception.Message)"
            }
        }

        # Stop timer
        $stopwatch.Stop()
        $elapsedSeconds = $stopwatch.Elapsed.TotalSeconds

        # Return ScanResult
        return New-ScanResult `
            -Mode ([ScanMode]::Deep) `
            -DriveLetter $DriveLetter `
            -UsedBytes $usedBytes `
            -FreeBytes $freeBytes `
            -Items $items `
            -Errors $errors `
            -ElapsedSeconds $elapsedSeconds
    }

    # Get drive info (for Quick mode path)
    $drive = Get-PSDrive -Name $DriveLetter
    $usedBytes = [long]$drive.Used
    $freeBytes = [long]$drive.Free

    # Stop timer
    $stopwatch.Stop()
    $elapsedSeconds = $stopwatch.Elapsed.TotalSeconds

    # Return ScanResult
    return New-ScanResult `
        -Mode ([ScanMode]::$Mode) `
        -DriveLetter $DriveLetter `
        -UsedBytes $usedBytes `
        -FreeBytes $freeBytes `
        -Items $items `
        -Errors $errors `
        -ElapsedSeconds $elapsedSeconds
}


