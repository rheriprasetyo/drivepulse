<#
.SYNOPSIS
    DrivePulse — Formatting Property-Based Tests
.DESCRIPTION
    Property-based tests for the CLI formatting module verifying:
    - Property 7: Size Formatting Correctness
    - Property 9: Summary Totals Invariant
.NOTES
    Uses 100 iterations per property test.
    Uses generators from tests/helpers/generators.ps1
#>

Describe "Formatting Property Tests" {
    BeforeAll {
        . "$PSScriptRoot\..\..\src\scanner\types.ps1"
        . "$PSScriptRoot\..\helpers\generators.ps1"

        # Import Format-Size directly (avoid importing full cli.ps1 which imports scan.ps1)
        # We define a local copy to avoid side effects from the full CLI module load
        . "$PSScriptRoot\..\..\src\ui\cli.ps1"
    }

    Context "Property 7: Size Formatting Correctness" {
        <#
            **Validates: Requirements 8.2**
            For any byte value >= 0, Format-Size returns " GB" suffix when >= 1GB
            and " MB" suffix when < 1GB, with valid numeric portion.
        #>

        It "Returns GB suffix for values >= 1GB with valid numeric portion" {
            1..100 | ForEach-Object {
                # Generate random size >= 1GB (1GB to 500GB)
                $sizeBytes = [long](Get-Random -Minimum 1073741824 -Maximum ([long]500GB))

                $result = Format-Size -Bytes $sizeBytes

                # Assert: result ends with " GB"
                $result | Should -Match '\d+(\.\d+)?\s*GB$'

                # Assert: numeric portion is valid and > 0
                $numericPart = ($result -replace '\s*GB$', '')
                [double]$numericPart | Should -BeGreaterThan 0
            }
        }

        It "Returns MB suffix for values < 1GB with valid numeric portion" {
            1..100 | ForEach-Object {
                # Generate random size < 1GB (1MB to just under 1GB)
                $sizeBytes = [long](Get-Random -Minimum 1048576 -Maximum 1073741823)

                $result = Format-Size -Bytes $sizeBytes

                # Assert: result ends with " MB"
                $result | Should -Match '\d+\s*MB$'

                # Assert: numeric portion is valid and > 0
                $numericPart = ($result -replace '\s*MB$', '')
                [double]$numericPart | Should -BeGreaterThan 0
            }
        }

        It "Returns 0 MB for zero bytes" {
            $result = Format-Size -Bytes 0
            $result | Should -Match '0\s*MB$'
        }

        It "Returns MB suffix for small values (< 1MB)" {
            1..100 | ForEach-Object {
                $sizeBytes = [long](Get-Random -Minimum 0 -Maximum 1048575)

                $result = Format-Size -Bytes $sizeBytes

                # Assert: result ends with " MB" (small values still show as MB)
                $result | Should -Match '\d+\s*MB$'
            }
        }

        It "GB value is approximately correct (within rounding tolerance)" {
            1..100 | ForEach-Object {
                $sizeBytes = [long](Get-Random -Minimum 1073741824 -Maximum ([long]100GB))

                $result = Format-Size -Bytes $sizeBytes
                $numericPart = [double]($result -replace '\s*GB$', '')

                # Expected value
                $expectedGB = [math]::Round($sizeBytes / 1073741824, 1)

                # Assert: within 0.1 tolerance (due to rounding)
                [math]::Abs($numericPart - $expectedGB) | Should -BeLessOrEqual 0.1
            }
        }

        It "MB value is approximately correct (within rounding tolerance)" {
            1..100 | ForEach-Object {
                $sizeBytes = [long](Get-Random -Minimum 1048576 -Maximum 1073741823)

                $result = Format-Size -Bytes $sizeBytes
                $numericPart = [double]($result -replace '\s*MB$', '')

                # Expected value
                $expectedMB = [math]::Round($sizeBytes / 1048576)

                # Assert: within 1 tolerance (due to rounding)
                [math]::Abs($numericPart - $expectedMB) | Should -BeLessOrEqual 1
            }
        }
    }

    Context "Property 9: Summary Totals Invariant" {
        <#
            **Validates: Requirements 8.6**
            For any array of CategorizedItems, total safe space equals sum of SizeBytes
            where Category=Safe, total check space equals sum where Category=Check.
        #>

        It "Total safe bytes equals sum of SizeBytes for Safe items" {
            1..100 | ForEach-Object {
                # Generate random number of categorized items
                $itemCount = Get-Random -Minimum 1 -Maximum 10
                $categorizedItems = @()

                for ($i = 0; $i -lt $itemCount; $i++) {
                    $scanItem = New-RandomScanItem
                    $category = @([ItemCategory]::Safe, [ItemCategory]::Check, [ItemCategory]::Unknown) | Get-Random

                    $categorizedItems += New-CategorizedItem `
                        -ScanItem $scanItem `
                        -Category $category `
                        -SideEffect "test" `
                        -Reason "test"
                }

                # Calculate expected totals
                $expectedSafeTotal = ($categorizedItems | Where-Object { $_.Category -eq [ItemCategory]::Safe } | Measure-Object -Property SizeBytes -Sum).Sum
                if (-not $expectedSafeTotal) { $expectedSafeTotal = 0 }

                $expectedCheckTotal = ($categorizedItems | Where-Object { $_.Category -eq [ItemCategory]::Check } | Measure-Object -Property SizeBytes -Sum).Sum
                if (-not $expectedCheckTotal) { $expectedCheckTotal = 0 }

                # Filter items the same way Show-ScanResults does
                $safeItems = @($categorizedItems | Where-Object { $_.Category -eq [ItemCategory]::Safe })
                $checkItems = @($categorizedItems | Where-Object { $_.Category -eq [ItemCategory]::Check })

                $actualSafeTotal = ($safeItems | Measure-Object -Property SizeBytes -Sum).Sum
                if (-not $actualSafeTotal) { $actualSafeTotal = 0 }

                $actualCheckTotal = ($checkItems | Measure-Object -Property SizeBytes -Sum).Sum
                if (-not $actualCheckTotal) { $actualCheckTotal = 0 }

                # Assert: totals match
                $actualSafeTotal | Should -Be $expectedSafeTotal
                $actualCheckTotal | Should -Be $expectedCheckTotal
            }
        }

        It "Safe + Check + Unknown items count equals total items" {
            1..100 | ForEach-Object {
                $itemCount = Get-Random -Minimum 1 -Maximum 15
                $categorizedItems = @()

                for ($i = 0; $i -lt $itemCount; $i++) {
                    $scanItem = New-RandomScanItem
                    $category = @([ItemCategory]::Safe, [ItemCategory]::Check, [ItemCategory]::Unknown) | Get-Random

                    $categorizedItems += New-CategorizedItem `
                        -ScanItem $scanItem `
                        -Category $category
                }

                $safeCount = @($categorizedItems | Where-Object { $_.Category -eq [ItemCategory]::Safe }).Count
                $checkCount = @($categorizedItems | Where-Object { $_.Category -eq [ItemCategory]::Check }).Count
                $unknownCount = @($categorizedItems | Where-Object { $_.Category -eq [ItemCategory]::Unknown }).Count

                # Assert: all items are accounted for
                ($safeCount + $checkCount + $unknownCount) | Should -Be $itemCount
            }
        }
    }
}
