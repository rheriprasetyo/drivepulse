<#
.SYNOPSIS
    DrivePulse — Report Generator Module
.DESCRIPTION
    Generate report dari hasil scan dalam format HTML atau TXT.
    Supports color-coded drive status, categorized item tables,
    and recommendations in Bahasa Indonesia.
.NOTES
    Author: DrivePulse Team
    Version: 1.2
#>

# Dot-source dependencies
. "$PSScriptRoot\format-utils.ps1"
. "$PSScriptRoot\filter.ps1"

# Load System.Web for HtmlEncode
Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue

function New-HtmlReport {
    <#
    .SYNOPSIS Generates an HTML report from scan results
    .DESCRIPTION Reads template.html and replaces all placeholders with actual
                 scan data. Produces a self-contained HTML file.
    .PARAMETER ScanResult DrivePulse.ScanResult object
    .PARAMETER CategorizedItems Array of DrivePulse.CategorizedItem objects
    .PARAMETER OutputPath Directory to save the report
    .OUTPUTS [string] Full path to the generated HTML file
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$ScanResult,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [PSCustomObject[]]$CategorizedItems,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    # Read template
    $templatePath = Join-Path $PSScriptRoot 'template.html'
    $html = [System.IO.File]::ReadAllText($templatePath, [System.Text.UTF8Encoding]::new($false))

    # Replace basic placeholders
    $date = Get-Date -Format 'yyyy-MM-dd'
    $totalGB = [math]::Round($ScanResult.TotalBytes / 1073741824, 2)
    $usedGB = [math]::Round($ScanResult.UsedBytes / 1073741824, 2)
    $usedPct = [math]::Round($ScanResult.UsagePercent, 1)
    $colorCode = Get-ColorCode -UsagePercent $ScanResult.UsagePercent

    $html = $html -replace '\{\{DATE\}\}', $date
    $html = $html -replace '\{\{DRIVE\}\}', $ScanResult.DriveLetter
    $html = $html -replace '\{\{TOTAL_GB\}\}', $totalGB.ToString('F2')
    $html = $html -replace '\{\{USED_GB\}\}', $usedGB.ToString('F2')
    $html = $html -replace '\{\{USED_PCT\}\}', $usedPct.ToString('F1')
    $html = $html -replace '\{\{VERSION\}\}', '1.2'
    $html = $html -replace '\{\{COLOR_CODE\}\}', $colorCode

    # Build Safe items table
    $safeItems = @($CategorizedItems | Where-Object { $_.Category -eq 'Safe' })
    if ($safeItems.Count -eq 0) {
        $safeHtml = '<p class="empty-message">Tidak ada item dalam kategori ini.</p>'
    }
    else {
        $safeHtml = '<table><thead><tr><th>Nama</th><th>Ukuran</th><th>Efek Samping</th></tr></thead><tbody>'
        foreach ($item in $safeItems) {
            $size = Format-SizeDetailed -Bytes $item.SizeBytes
            $label = [System.Web.HttpUtility]::HtmlEncode($item.Label)
            $sideEffect = [System.Web.HttpUtility]::HtmlEncode($item.SideEffect)
            $safeHtml += "<tr><td>$label</td><td class=`"size-cell`">$size</td><td>$sideEffect</td></tr>"
        }
        $safeHtml += '</tbody></table>'
    }
    $html = $html -replace '\{\{SAFE_ITEMS\}\}', $safeHtml

    # Build Check items table
    $checkItems = @($CategorizedItems | Where-Object { $_.Category -eq 'Check' })
    if ($checkItems.Count -eq 0) {
        $checkHtml = '<p class="empty-message">Tidak ada item dalam kategori ini.</p>'
    }
    else {
        $checkHtml = '<table><thead><tr><th>Nama</th><th>Ukuran</th><th>Alasan</th><th>Rekomendasi</th></tr></thead><tbody>'
        foreach ($item in $checkItems) {
            $size = Format-SizeDetailed -Bytes $item.SizeBytes
            $label = [System.Web.HttpUtility]::HtmlEncode($item.Label)
            $reason = [System.Web.HttpUtility]::HtmlEncode($item.Reason)
            $recommendation = [System.Web.HttpUtility]::HtmlEncode($item.Recommendation)
            $checkHtml += "<tr><td>$label</td><td class=`"size-cell`">$size</td><td>$reason</td><td>$recommendation</td></tr>"
        }
        $checkHtml += '</tbody></table>'
    }
    $html = $html -replace '\{\{CHECK_ITEMS\}\}', $checkHtml

    # Build recommendations section (deduplicated)
    if ($checkItems.Count -eq 0) {
        $recsHtml = '<p class="empty-message">Tidak ada rekomendasi.</p>'
    }
    else {
        $uniqueRecs = @($checkItems | ForEach-Object { $_.Recommendation } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        if ($uniqueRecs.Count -eq 0) {
            $recsHtml = '<p class="empty-message">Tidak ada rekomendasi.</p>'
        }
        else {
            $recsHtml = '<ul class="recommendations-list">'
            foreach ($rec in $uniqueRecs) {
                $encodedRec = [System.Web.HttpUtility]::HtmlEncode($rec)
                $recsHtml += "<li>$encodedRec</li>"
            }
            $recsHtml += '</ul>'
        }
    }
    $html = $html -replace '\{\{RECOMMENDATIONS\}\}', $recsHtml

    # Save file
    $filename = "DrivePulse-Report-$date.html"
    $filePath = Join-Path $OutputPath $filename
    [System.IO.File]::WriteAllText($filePath, $html, [System.Text.UTF8Encoding]::new($false))

    return $filePath
}

function New-TxtReport {
    <#
    .SYNOPSIS Generates a plain text report from scan results
    .DESCRIPTION Builds a structured TXT report with header, categorized items
                 sorted by size, and summary totals. Uses UTF-8 BOM + CRLF.
    .PARAMETER ScanResult DrivePulse.ScanResult object
    .PARAMETER CategorizedItems Array of DrivePulse.CategorizedItem objects
    .PARAMETER OutputPath Directory to save the report
    .OUTPUTS [string] Full path to the generated TXT file
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$ScanResult,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [PSCustomObject[]]$CategorizedItems,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    $crlf = "`r`n"
    $separator = [string]::new([char]0x2550, 43)
    $thinSep = [string]::new([char]0x2500, 37)

    $date = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $totalFormatted = Format-Size -Bytes $ScanResult.TotalBytes
    $usedFormatted = Format-Size -Bytes $ScanResult.UsedBytes
    $freeFormatted = Format-Size -Bytes $ScanResult.FreeBytes
    $usagePct = [math]::Round($ScanResult.UsagePercent, 1)
    $usagePctStr = "$usagePct" + '%'

    # Build report
    $lines = @()
    $lines += $separator
    $lines += '  DrivePulse ' + [char]0x2014 + ' Laporan Analisis Drive'
    $lines += "  Tanggal: $date"
    $lines += $separator
    $lines += ''
    $lines += 'Status Drive'
    $lines += "  Drive    : $($ScanResult.DriveLetter):"
    $lines += "  Total    : $totalFormatted"
    $lines += "  Terpakai : $usedFormatted ($usagePctStr)"
    $lines += "  Tersedia : $freeFormatted"
    $lines += ''

    # Safe items section
    $safeItems = @($CategorizedItems | Where-Object { $_.Category -eq 'Safe' } | Sort-Object -Property SizeBytes -Descending)
    $lines += 'Aman Dihapus'
    $lines += "  $thinSep"

    if ($safeItems.Count -eq 0) {
        $lines += '  Tidak ada item dalam kategori ini'
    }
    else {
        foreach ($item in $safeItems) {
            $size = Format-Size -Bytes $item.SizeBytes
            $padding = ' ' * [Math]::Max(1, 30 - $item.Label.Length)
            $lines += "  $($item.Label)$padding$size"
        }
    }

    $safeTotalBytes = ($safeItems | Measure-Object -Property SizeBytes -Sum).Sum
    if ($null -eq $safeTotalBytes) { $safeTotalBytes = 0 }
    $safeTotalFormatted = Format-Size -Bytes $safeTotalBytes

    $lines += "  $thinSep"
    $lines += "  Total bisa diklaim: $safeTotalFormatted"
    $lines += ''

    # Check items section
    $checkItems = @($CategorizedItems | Where-Object { $_.Category -eq 'Check' } | Sort-Object -Property SizeBytes -Descending)
    $lines += 'Perlu Dicek Manual'
    $lines += "  $thinSep"

    if ($checkItems.Count -eq 0) {
        $lines += '  Tidak ada item dalam kategori ini'
    }
    else {
        foreach ($item in $checkItems) {
            $size = Format-Size -Bytes $item.SizeBytes
            $padding = ' ' * [Math]::Max(1, 20 - $item.Label.Length)
            $lines += "  $($item.Label)$padding$size   [$($item.Recommendation)]"
        }
    }

    $checkTotalBytes = ($checkItems | Measure-Object -Property SizeBytes -Sum).Sum
    if ($null -eq $checkTotalBytes) { $checkTotalBytes = 0 }
    $checkTotalFormatted = Format-Size -Bytes $checkTotalBytes

    $lines += "  $thinSep"
    $lines += "  Total perlu review: $checkTotalFormatted"
    $lines += ''

    # Summary section
    $lines += 'Ringkasan'
    $lines += "  Bisa diklaim kembali : $safeTotalFormatted"
    $lines += "  Perlu review manual  : $checkTotalFormatted"
    $lines += ''
    $lines += $separator
    $lines += '  Generated by DrivePulse v1.2'
    $lines += $separator

    # Join with CRLF
    $content = $lines -join $crlf
    $content += $crlf

    # Save with UTF-8 BOM + CRLF
    $filename = 'DrivePulse-Report-' + (Get-Date -Format 'yyyy-MM-dd') + '.txt'
    $filePath = Join-Path $OutputPath $filename
    $utf8Bom = [System.Text.UTF8Encoding]::new($true)
    [System.IO.File]::WriteAllText($filePath, $content, $utf8Bom)

    return $filePath
}

function New-DriveReport {
    <#
    .SYNOPSIS Main entry point for report generation
    .DESCRIPTION Validates parameters, delegates to HTML or TXT generator,
                 and returns a result object with success/failure info.
    .PARAMETER ScanResult DrivePulse.ScanResult object
    .PARAMETER CategorizedItems Array of DrivePulse.CategorizedItem objects
    .PARAMETER Format Report format: "HTML" or "TXT"
    .PARAMETER OutputPath Directory to save the report
    .OUTPUTS [PSCustomObject] DrivePulse.ReportResult with Success, FilePath, Format, Error
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$ScanResult,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [PSCustomObject[]]$CategorizedItems,

        [ValidateSet("HTML", "TXT")]
        [string]$Format = "HTML",

        [string]$OutputPath = "$env:USERPROFILE\Desktop"
    )

    # Validate OutputPath exists
    if (-not (Test-Path $OutputPath)) {
        return [PSCustomObject]@{
            PSTypeName = 'DrivePulse.ReportResult'
            Success    = $false
            FilePath   = $null
            Format     = $Format
            Error      = "Lokasi output tidak ditemukan: $OutputPath"
        }
    }

    # Validate OutputPath is writable
    try {
        $testFile = Join-Path $OutputPath ('.drivepulse-write-test-' + [System.Guid]::NewGuid().ToString('N'))
        [System.IO.File]::WriteAllText($testFile, 'test')
        Remove-Item $testFile -Force -ErrorAction SilentlyContinue
    }
    catch [System.UnauthorizedAccessException] {
        return [PSCustomObject]@{
            PSTypeName = 'DrivePulse.ReportResult'
            Success    = $false
            FilePath   = $null
            Format     = $Format
            Error      = "Tidak bisa menulis ke lokasi: $OutputPath. Akses ditolak."
        }
    }
    catch {
        return [PSCustomObject]@{
            PSTypeName = 'DrivePulse.ReportResult'
            Success    = $false
            FilePath   = $null
            Format     = $Format
            Error      = "Tidak bisa menulis ke lokasi: $OutputPath. $($_.Exception.Message)"
        }
    }

    # Generate report
    try {
        $filePath = $null
        if ($Format -eq 'HTML') {
            $filePath = New-HtmlReport -ScanResult $ScanResult -CategorizedItems $CategorizedItems -OutputPath $OutputPath
        }
        else {
            $filePath = New-TxtReport -ScanResult $ScanResult -CategorizedItems $CategorizedItems -OutputPath $OutputPath
        }

        return [PSCustomObject]@{
            PSTypeName = 'DrivePulse.ReportResult'
            Success    = $true
            FilePath   = $filePath
            Format     = $Format
            Error      = $null
        }
    }
    catch [System.IO.IOException] {
        # Clean up partial file if any
        $date = Get-Date -Format 'yyyy-MM-dd'
        $ext = if ($Format -eq 'HTML') { 'html' } else { 'txt' }
        $partialFile = Join-Path $OutputPath "DrivePulse-Report-$date.$ext"
        if (Test-Path $partialFile) {
            Remove-Item $partialFile -Force -ErrorAction SilentlyContinue
        }

        if ($_.Exception.Message -match 'disk|space|full') {
            return [PSCustomObject]@{
                PSTypeName = 'DrivePulse.ReportResult'
                Success    = $false
                FilePath   = $null
                Format     = $Format
                Error      = 'Disk penuh, tidak bisa menyimpan laporan.'
            }
        }

        return [PSCustomObject]@{
            PSTypeName = 'DrivePulse.ReportResult'
            Success    = $false
            FilePath   = $null
            Format     = $Format
            Error      = "Gagal membuat laporan: $($_.Exception.Message)"
        }
    }
    catch {
        # Clean up partial file if any
        $date = Get-Date -Format 'yyyy-MM-dd'
        $ext = if ($Format -eq 'HTML') { 'html' } else { 'txt' }
        $partialFile = Join-Path $OutputPath "DrivePulse-Report-$date.$ext"
        if (Test-Path $partialFile) {
            Remove-Item $partialFile -Force -ErrorAction SilentlyContinue
        }

        return [PSCustomObject]@{
            PSTypeName = 'DrivePulse.ReportResult'
            Success    = $false
            FilePath   = $null
            Format     = $Format
            Error      = "Gagal membuat laporan: $($_.Exception.Message)"
        }
    }
}
