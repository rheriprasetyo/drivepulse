<#
.SYNOPSIS
    DrivePulse — Categorizer Property-Based Tests
.DESCRIPTION
    Property-based tests for the categorizer module verifying:
    - Property 4: Categorization Produces Valid Output with Correct Metadata
    - Property 3: Deep Scan Threshold Filtering
.NOTES
    Uses 20 iterations per property test for faster execution.
    Uses generators from tests/helpers/generators.ps1
#>

Describe "Categorizer Property Tests" {
    BeforeAll {
        . "$PSScriptRoot\..\..\src\scanner\categorize.ps1"
        . "$PSScriptRoot\..\helpers\generators.ps1"
    }

    Context "Property 4: Categorization Produces Valid Output with Correct Metadata" {
        <#
            **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5**
            For any valid ScanItem and rules, Get-ItemCategory returns a CategorizedItem
            with valid Category (Safe/Check/Unknown) and correct metadata fields per category.
        #>

        It "Returns CategorizedItem with Category=Safe and correct sideEffect when item matches a safe rule" {
            1..20 | ForEach-Object {
                # Generate a random scan item
                $item = New-RandomScanItem

                # Create rules where this item's path matches a safe rule
                $sideEffect = "Side effect iteration $_"
                $rules = @{
                    thresholds = @{ largeFolderGB = 5 }
                    categories = @{
                        safe = @{
                            items = @(@{
                                id = "test-safe-$_"
                                label = "Test Safe"
                                path = $item.Path
                                sideEffect = $sideEffect
                                requiresAdmin = $false
                            })
                        }
                        check = @{ items = @() }
                    }
                } | ConvertTo-Json -Depth 10 | ConvertFrom-Json

                $result = Get-ItemCategory -ScanItem $item -Rules $rules -IsAdmin $false

                # Assert: returns a valid CategorizedItem with Category=Safe
                $result | Should -Not -BeNullOrEmpty
                $result.Category | Should -Be ([ItemCategory]::Safe)
                $result.SideEffect | Should -Be $sideEffect
            }
        }

        It "Returns CategorizedItem with Category=Check and correct reason/recommendation when item matches a check rule" {
            1..20 | ForEach-Object {
                $item = New-RandomScanItem

                $reason = "Reason iteration $_"
                $recommendation = "Recommendation iteration $_"
                $rules = @{
                    thresholds = @{ largeFolderGB = 5 }
                    categories = @{
                        safe = @{ items = @() }
                        check = @{
                            items = @(@{
                                id = "test-check-$_"
                                label = "Test Check"
                                path = $item.Path
                                reason = $reason
                                recommendation = $recommendation
                            })
                        }
                    }
                } | ConvertTo-Json -Depth 10 | ConvertFrom-Json

                $result = Get-ItemCategory -ScanItem $item -Rules $rules -IsAdmin $false

                # Assert: returns a valid CategorizedItem with Category=Check
                $result | Should -Not -BeNullOrEmpty
                $result.Category | Should -Be ([ItemCategory]::Check)
                $result.Reason | Should -Be $reason
                $result.Recommendation | Should -Be $recommendation
            }
        }

        It "Returns Category=Check with generic reason for large unmatched items" {
            1..20 | ForEach-Object {
                # Create item with size >= threshold
                $thresholdGB = Get-Random -Minimum 1 -Maximum 5
                $thresholdBytes = [long]($thresholdGB * 1GB)
                $sizeBytes = $thresholdBytes + [long](Get-Random -Minimum 1 -Maximum 1000000)
                $item = New-ScanItem -Path "C:\$([System.Guid]::NewGuid())" -Label "Big Item $_" -SizeBytes $sizeBytes

                $rules = @{
                    thresholds = @{ largeFolderGB = $thresholdGB }
                    categories = @{
                        safe = @{ items = @() }
                        check = @{ items = @() }
                    }
                } | ConvertTo-Json -Depth 10 | ConvertFrom-Json

                $result = Get-ItemCategory -ScanItem $item -Rules $rules -IsAdmin $false

                # Assert: large unmatched item gets Category=Check with generic reason
                $result | Should -Not -BeNullOrEmpty
                $result.Category | Should -Be ([ItemCategory]::Check)
                $result.Reason | Should -Be "Folder besar tanpa aturan spesifik"
            }
        }

        It "Returns Category=Unknown for small unmatched items" {
            1..20 | ForEach-Object {
                # Create item with size < threshold
                $thresholdGB = Get-Random -Minimum 5 -Maximum 20
                $thresholdBytes = [long]($thresholdGB * 1GB)
                $sizeBytes = [long](Get-Random -Minimum 0 -Maximum ([int][Math]::Min($thresholdBytes - 1, [int]::MaxValue)))
                $item = New-ScanItem -Path "C:\$([System.Guid]::NewGuid())" -Label "Small Item $_" -SizeBytes $sizeBytes

                $rules = @{
                    thresholds = @{ largeFolderGB = $thresholdGB }
                    categories = @{
                        safe = @{ items = @() }
                        check = @{ items = @() }
                    }
                } | ConvertTo-Json -Depth 10 | ConvertFrom-Json

                $result = Get-ItemCategory -ScanItem $item -Rules $rules -IsAdmin $false

                # Assert: small unmatched item gets Category=Unknown
                $result | Should -Not -BeNullOrEmpty
                $result.Category | Should -Be ([ItemCategory]::Unknown)
            }
        }

        It "Sets RequiresAdmin=true when rule has requiresAdmin=true and IsAdmin is false" {
            1..20 | ForEach-Object {
                $item = New-RandomScanItem

                $rules = @{
                    thresholds = @{ largeFolderGB = 5 }
                    categories = @{
                        safe = @{
                            items = @(@{
                                id = "admin-$_"
                                label = "Admin Required"
                                path = $item.Path
                                sideEffect = "Needs admin"
                                requiresAdmin = $true
                            })
                        }
                        check = @{ items = @() }
                    }
                } | ConvertTo-Json -Depth 10 | ConvertFrom-Json

                $result = Get-ItemCategory -ScanItem $item -Rules $rules -IsAdmin $false

                # Assert: RequiresAdmin is true when rule requires admin and user is not admin
                $result | Should -Not -BeNullOrEmpty
                $result.Category | Should -Be ([ItemCategory]::Safe)
                $result.RequiresAdmin | Should -Be $true
            }
        }
    }

    Context "Property 3: Deep Scan Threshold Filtering" {
        <#
            **Validates: Requirements 2.3**
            For any set of items with varying sizes and positive threshold,
            only items >= threshold get categorized as Check (large unmatched).
            Items below threshold get Category=Unknown.
        #>

        It "Only items at or above threshold get categorized as Check; items below get Unknown" {
            1..20 | ForEach-Object {
                $thresholdGB = Get-Random -Minimum 1 -Maximum 10
                $thresholdBytes = [long]($thresholdGB * 1GB)

                # Generate random item with size between 0 and 20GB
                $sizeBytes = [long](Get-Random -Minimum 0 -Maximum ([long]20GB))
                $item = New-ScanItem -Path "C:\$([System.Guid]::NewGuid())" -Label "Item $_" -SizeBytes $sizeBytes

                # Rules with no matching safe/check entries — only threshold matters
                $rules = @{
                    thresholds = @{ largeFolderGB = $thresholdGB }
                    categories = @{
                        safe = @{ items = @() }
                        check = @{ items = @() }
                    }
                } | ConvertTo-Json -Depth 10 | ConvertFrom-Json

                $result = Get-ItemCategory -ScanItem $item -Rules $rules -IsAdmin $false

                # Assert: threshold filtering is correct
                if ($sizeBytes -ge $thresholdBytes) {
                    $result.Category | Should -Be ([ItemCategory]::Check)
                } else {
                    $result.Category | Should -Be ([ItemCategory]::Unknown)
                }
            }
        }
    }
}
