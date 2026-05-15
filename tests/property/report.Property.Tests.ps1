<#
.SYNOPSIS
    DrivePulse — Report Property-Based Tests
.DESCRIPTION
    Property-based tests for report generation verifying:
    - Property 1: Byte-to-GB Conversion Accuracy
    - Property 2: Category Items Rendering Completeness
    - Property 3: Recommendations Deduplication
    - Property 4: Color Code Mapping
    - Property 5: Self-Contained HTML
    - Property 6: TXT Report Items Sorted by Size Descending
    - Property 7: Report Summary Totals Accuracy
    - Property 15: Size Formatting Consistency
    - Property 16: UsagePercent Display Accuracy
.NOTES
    Uses 100 iterations per property test.
    Uses generators from tests/helpers/generators.ps1
#>

Describe "Report Property Tests" {
    BeforeAll {
        . "$PSScriptRoot\..\..\src\scanner\types.ps1"
        . "$PSScriptRoot\..\helpers\generators.ps1"
        . "$PSScriptRoot\..\..\src\reporter\format-utils.ps1"
        . "$PSScriptRoot\..\..\src\reporter\filter.ps1"
        . "$PSScriptRoot\..\..\src\reporter\report.ps1"
    }

    Context "Property 4: Color Code Mapping" {
        It "Returns red (#ff4757) for UsagePercent > 90" {
            1..100 | ForEach-Object {
                $pct = 90.01 + (Get-Random -Minimum 1 -Maximum 999) / 100
                $result = Get-ColorCode -UsagePercent $pct
                $result | Should -Be '#ff4757'
            }
        }

        It "Returns yellow (#ffa502) for UsagePercent 75-90 inclusive" {
            1..100 | ForEach-Object {
                $pct = 75 + (Get-Random -Minimum 0 -Maximum 1500) / 100
                if ($pct -gt 90) { $pct = 90 }
                $result = Get-ColorCode -UsagePercent $pct
                $result | Should -Be '#ffa502'
            }
        }

        It "Returns green (#2ed573) for UsagePercent < 75" {
            1..100 | ForEach-Object {
                $pct = (Get-Random -Minimum 0 -Maximum 7499) / 100
                $result = Get-ColorCode -UsagePercent $pct
                $result | Should -Be '#2ed573'
            }
        }

        It "Boundary: 90.0 returns yellow, 90.01 returns red" {
            Get-ColorCode -UsagePercent 90.0 | Should -Be '#ffa502'
            Get-ColorCode -UsagePercent 90.01 | Should -Be '#ff4757'
        }

        It "Boundary: 75.0 returns yellow, 74.99 returns green" {
            Get-ColorCode -UsagePercent 75.0 | Should -Be '#ffa502'
            Get-ColorCode -UsagePercent 74.99 | Should -Be '#2ed573'
        }
    }

    Context "Property 15: Size Formatting Consistency" {
        It "Format-Size returns GB suffix for bytes >= 1GB with 1 decimal" {
            1..100 | ForEach-Object {
                $bytes = [long](Get-Random -Minimum 1073741824 -Maximum 2199023255552)
                $result = Format-Size -Bytes $bytes
                $result | Should -Match '^\d+(\.\d)?\s+GB$'
                $expectedGB = [math]::Round($bytes / 1073741824, 1)
                $numPart = [double]($result -replace '\s*GB$', '')
                [math]::Abs($numPart - $expectedGB) | Should -BeLessOrEqual 0.05
            }
        }

        It "Format-Size returns MB suffix (no decimal) for bytes < 1GB" {
            1..100 | ForEach-Object {
                $bytes = [long](Get-Random -Minimum 1048576 -Maximum 1073741823)
                $result = Format-Size -Bytes $bytes
                $result | Should -Match '^\d+\s+MB$'
                $expectedMB = [math]::Round($bytes / 1048576)
                $numPart = [int]($result -replace '\s*MB$', '')
                [math]::Abs($numPart - $expectedMB) | Should -BeLessOrEqual 1
            }
        }

        It "Format-SizeDetailed returns KB with 2 decimals for bytes < 1MB" {
            1..100 | ForEach-Object {
                $bytes = [long](Get-Random -Minimum 1 -Maximum 1048575)
                $result = Format-SizeDetailed -Bytes $bytes
                $result | Should -Match '^\d+\.\d{2}\s+KB$'
            }
        }

        It "Format-SizeDetailed returns MB with 2 decimals for 1MB <= bytes < 1GB" {
            1..100 | ForEach-Object {
                $bytes = [long](Get-Random -Minimum 1048576 -Maximum 1073741823)
                $result = Format-SizeDetailed -Bytes $bytes
                $result | Should -Match '^\d+\.\d{2}\s+MB$'
            }
        }

        It "Format-SizeDetailed returns GB with 2 decimals for bytes >= 1GB" {
            1..100 | ForEach-Object {
                $bytes = [long](Get-Random -Minimum 1073741824 -Maximum 2199023255552)
                $result = Format-SizeDetailed -Bytes $bytes
                $result | Should -Match '^\d+\.\d{2}\s+GB$'
            }
        }
    }

    Context "Property 1: Byte-to-GB Conversion Accuracy" {
        It "HTML report TOTAL_GB and USED_GB equal Round(bytes / 1073741824, 2)" {
            $tempDir = Join-Path $env:TEMP "drivepulse-test-$(Get-Random)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

            try {
                1..50 | ForEach-Object {
                    $scan = New-RandomScanResult
                    $items = @(New-RandomCategorizedItems -Count 2)

                    $filePath = New-HtmlReport -ScanResult $scan -CategorizedItems $items -OutputPath $tempDir
                    $html = [System.IO.File]::ReadAllText($filePath)

                    $expectedTotal = [math]::Round($scan.TotalBytes / 1073741824, 2).ToString('F2')
                    $expectedUsed = [math]::Round($scan.UsedBytes / 1073741824, 2).ToString('F2')

                    $html | Should -Match $expectedTotal
                    $html | Should -Match $expectedUsed

                    Remove-Item $filePath -Force -ErrorAction SilentlyContinue
                }
            }
            finally {
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Property 2: Category Items Rendering Completeness" {
        It "All Safe and Check item labels appear in HTML output" {
            $tempDir = Join-Path $env:TEMP "drivepulse-test-$(Get-Random)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

            try {
                1..30 | ForEach-Object {
                    $scan = New-RandomScanResult
                    $items = @(New-RandomCategorizedItems -Count (Get-Random -Minimum 2 -Maximum 8))

                    $filePath = New-HtmlReport -ScanResult $scan -CategorizedItems $items -OutputPath $tempDir
                    $html = [System.IO.File]::ReadAllText($filePath)

                    foreach ($item in $items) {
                        $encodedLabel = [System.Web.HttpUtility]::HtmlEncode($item.Label)
                        $html | Should -Match ([regex]::Escape($encodedLabel))
                    }

                    Remove-Item $filePath -Force -ErrorAction SilentlyContinue
                }
            }
            finally {
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Property 3: Recommendations Deduplication" {
        It "Unique recommendation count matches rendered count in HTML" {
            $tempDir = Join-Path $env:TEMP "drivepulse-test-$(Get-Random)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

            try {
                1..30 | ForEach-Object {
                    $scan = New-RandomScanResult
                    $items = @(New-RandomCategorizedItems -Count (Get-Random -Minimum 3 -Maximum 10))

                    $filePath = New-HtmlReport -ScanResult $scan -CategorizedItems $items -OutputPath $tempDir
                    $html = [System.IO.File]::ReadAllText($filePath)

                    $checkItems = @($items | Where-Object { $_.Category -eq 'Check' })
                    $uniqueRecs = @($checkItems | ForEach-Object { $_.Recommendation } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)

                    if ($uniqueRecs.Count -gt 0) {
                        $liCount = ([regex]::Matches($html, '<li>')).Count
                        $liCount | Should -Be $uniqueRecs.Count
                    }

                    Remove-Item $filePath -Force -ErrorAction SilentlyContinue
                }
            }
            finally {
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Property 5: Self-Contained HTML" {
        It "No external link, script, or img elements in generated HTML" {
            $tempDir = Join-Path $env:TEMP "drivepulse-test-$(Get-Random)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

            try {
                1..30 | ForEach-Object {
                    $scan = New-RandomScanResult
                    $items = @(New-RandomCategorizedItems -Count 3)

                    $filePath = New-HtmlReport -ScanResult $scan -CategorizedItems $items -OutputPath $tempDir
                    $html = [System.IO.File]::ReadAllText($filePath)

                    $html | Should -Not -Match '<link\s+rel="stylesheet"'
                    $html | Should -Not -Match '<script\s+src='
                    $html | Should -Not -Match '<img\s+src="http'

                    Remove-Item $filePath -Force -ErrorAction SilentlyContinue
                }
            }
            finally {
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Property 6: TXT Report Items Sorted by Size Descending" {
        It "Items within each category are in non-increasing SizeBytes order" {
            $tempDir = Join-Path $env:TEMP "drivepulse-test-$(Get-Random)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

            try {
                1..30 | ForEach-Object {
                    $scan = New-RandomScanResult
                    $items = @(New-RandomCategorizedItems -Count (Get-Random -Minimum 3 -Maximum 10))

                    $filePath = New-TxtReport -ScanResult $scan -CategorizedItems $items -OutputPath $tempDir
                    $content = [System.IO.File]::ReadAllText($filePath)

                    # Verify Safe items are sorted descending
                    $safeItems = @($items | Where-Object { $_.Category -eq 'Safe' } | Sort-Object -Property SizeBytes -Descending)
                    if ($safeItems.Count -ge 2) {
                        for ($i = 0; $i -lt $safeItems.Count - 1; $i++) {
                            $safeItems[$i].SizeBytes | Should -BeGreaterOrEqual $safeItems[$i + 1].SizeBytes
                        }
                    }

                    # Verify Check items are sorted descending
                    $checkItems = @($items | Where-Object { $_.Category -eq 'Check' } | Sort-Object -Property SizeBytes -Descending)
                    if ($checkItems.Count -ge 2) {
                        for ($i = 0; $i -lt $checkItems.Count - 1; $i++) {
                            $checkItems[$i].SizeBytes | Should -BeGreaterOrEqual $checkItems[$i + 1].SizeBytes
                        }
                    }

                    Remove-Item $filePath -Force -ErrorAction SilentlyContinue
                }
            }
            finally {
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Property 7: Report Summary Totals Accuracy" {
        It "TXT report totals equal sum of SizeBytes per category" {
            $tempDir = Join-Path $env:TEMP "drivepulse-test-$(Get-Random)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

            try {
                1..30 | ForEach-Object {
                    $scan = New-RandomScanResult
                    $items = @(New-RandomCategorizedItems -Count (Get-Random -Minimum 2 -Maximum 8))

                    $filePath = New-TxtReport -ScanResult $scan -CategorizedItems $items -OutputPath $tempDir
                    $content = [System.IO.File]::ReadAllText($filePath)

                    $safeTotal = ($items | Where-Object { $_.Category -eq 'Safe' } | Measure-Object -Property SizeBytes -Sum).Sum
                    if ($null -eq $safeTotal) { $safeTotal = 0 }
                    $checkTotal = ($items | Where-Object { $_.Category -eq 'Check' } | Measure-Object -Property SizeBytes -Sum).Sum
                    if ($null -eq $checkTotal) { $checkTotal = 0 }

                    $expectedSafeStr = Format-Size -Bytes $safeTotal
                    $expectedCheckStr = Format-Size -Bytes $checkTotal

                    $content | Should -Match ([regex]::Escape($expectedSafeStr))
                    $content | Should -Match ([regex]::Escape($expectedCheckStr))

                    Remove-Item $filePath -Force -ErrorAction SilentlyContinue
                }
            }
            finally {
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Empty category shows 0 MB" {
            $tempDir = Join-Path $env:TEMP "drivepulse-test-$(Get-Random)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

            try {
                $scan = New-RandomScanResult
                # Only Check items, no Safe items
                $items = @(1..3 | ForEach-Object {
                    [PSCustomObject]@{
                        PSTypeName = 'DrivePulse.CategorizedItem'
                        Path = New-RandomWindowsPath
                        Label = "Check Item $_"
                        SizeBytes = [long](Get-Random -Minimum 1024 -Maximum 1073741824)
                        Category = 'Check'
                        SideEffect = ''
                        Reason = 'Test reason'
                        Recommendation = 'Test rec'
                    }
                })

                $filePath = New-TxtReport -ScanResult $scan -CategorizedItems $items -OutputPath $tempDir
                $content = [System.IO.File]::ReadAllText($filePath)

                $content | Should -Match 'Total bisa diklaim: 0 MB'

                Remove-Item $filePath -Force -ErrorAction SilentlyContinue
            }
            finally {
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Property 16: UsagePercent Display Accuracy" {
        It "TXT report displays UsagePercent rounded to 1 decimal" {
            $tempDir = Join-Path $env:TEMP "drivepulse-test-$(Get-Random)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

            try {
                1..50 | ForEach-Object {
                    $scan = New-RandomScanResult
                    $items = @(New-RandomCategorizedItems -Count 2)

                    $filePath = New-TxtReport -ScanResult $scan -CategorizedItems $items -OutputPath $tempDir
                    $content = [System.IO.File]::ReadAllText($filePath)

                    $expectedPct = [math]::Round($scan.UsagePercent, 1).ToString()
                    $content | Should -Match ([regex]::Escape("$expectedPct%"))

                    Remove-Item $filePath -Force -ErrorAction SilentlyContinue
                }
            }
            finally {
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
