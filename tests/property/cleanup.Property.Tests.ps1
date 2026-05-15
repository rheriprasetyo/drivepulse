<#
.SYNOPSIS
    DrivePulse — Cleaner Orchestrator Property-Based Tests
.DESCRIPTION
    Property-based tests for the cleaner orchestrator verifying:
    - Property 1: Dry-run filesystem invariance
    - Property 2: Preview completeness and correctness
    - Property 3: Progress tracking correctness
    - Property 4: Error resilience — skip and continue
    - Property 14: Safe-only cleanup filter
.NOTES
    Minimum 100 iterations for properties 1, 2, 14.
    Minimum 50 iterations for properties 3, 4 (I/O cost).
    Uses generators from tests/helpers/generators.ps1
#>

Describe "Cleaner Orchestrator Property Tests" {
    BeforeAll {
        . "$PSScriptRoot\..\helpers\generators.ps1"
        . "$PSScriptRoot\..\..\src\cleaner\clean.ps1"
    }

    Context "Property 1: Dry-run filesystem invariance" {
        <#
            **Validates: Requirements 1.3, 1.6, 2.3**
            In dry-run mode, no files are created, modified, or deleted.
            The filesystem state before and after Start-SafeCleanup -DryRun is identical.
        #>

        BeforeAll {
            $Script:TestRoot = Join-Path $env:TEMP "drivepulse-cleanup-prop1-$(Get-Random)"
            New-Item -Path $Script:TestRoot -ItemType Directory -Force | Out-Null
        }

        AfterAll {
            Remove-Item $Script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }

        It "Start-SafeCleanup -DryRun does not modify any files on the filesystem" {
            1..100 | ForEach-Object {
                $iterDir = Join-Path $Script:TestRoot "iter_$_"
                New-Item -Path $iterDir -ItemType Directory -Force | Out-Null

                # Generate random number of files (1-5)
                $fileCount = Get-Random -Minimum 1 -Maximum 6
                $items = @()
                $fileStates = @{}

                for ($i = 0; $i -lt $fileCount; $i++) {
                    $filePath = Join-Path $iterDir "file_$i.dat"
                    $content = New-RandomFileContent -MinSize 10 -MaxSize 512
                    [System.IO.File]::WriteAllBytes($filePath, $content)

                    # Record file state before dry-run
                    $fileStates[$filePath] = @{
                        Exists  = $true
                        Size    = $content.Length
                        Content = [System.Convert]::ToBase64String($content)
                    }

                    # Create CategorizedItem pointing to this file
                    $category = @('Safe', 'Aman Dihapus') | Get-Random
                    $items += [PSCustomObject]@{
                        Path      = $filePath
                        Label     = "Test Item $i"
                        SizeBytes = $content.Length
                        Category  = $category
                    }
                }

                # Record directory state before dry-run
                $dirFilesBefore = @(Get-ChildItem -Path $iterDir -Recurse -File | ForEach-Object { $_.FullName }) | Sort-Object

                # Act: Run in dry-run mode
                $result = Start-SafeCleanup -Items $items -DryRun

                # Assert: Status is dry-run
                $result.Status | Should -Be 'dry-run'

                # Assert: No items were processed
                $result.ItemsProcessed | Should -Be 0
                $result.SpaceFreed | Should -Be 0

                # Assert: All files still exist with identical content
                foreach ($filePath in $fileStates.Keys) {
                    Test-Path $filePath | Should -Be $true
                    $currentContent = [System.IO.File]::ReadAllBytes($filePath)
                    $currentContent.Length | Should -Be $fileStates[$filePath].Size
                    [System.Convert]::ToBase64String($currentContent) | Should -Be $fileStates[$filePath].Content
                }

                # Assert: No new files were created
                $dirFilesAfter = @(Get-ChildItem -Path $iterDir -Recurse -File | ForEach-Object { $_.FullName }) | Sort-Object
                $dirFilesAfter.Count | Should -Be $dirFilesBefore.Count
                for ($i = 0; $i -lt $dirFilesBefore.Count; $i++) {
                    $dirFilesAfter[$i] | Should -Be $dirFilesBefore[$i]
                }
            }
        }
    }

    Context "Property 2: Preview completeness and correctness" {
        <#
            **Validates: Requirements 1.2, 1.4, 2.1**
            Get-CleanupPreview returns ItemCount equal to the number of input items,
            TotalSize equal to the sum of all item sizes, and ItemList contains all items.
        #>

        It "Get-CleanupPreview returns correct ItemCount, TotalSize, and ItemList for any input" {
            1..100 | ForEach-Object {
                # Generate random items (1-20)
                $itemCount = Get-Random -Minimum 1 -Maximum 21
                $items = @()
                $expectedTotalSize = [long]0

                for ($i = 0; $i -lt $itemCount; $i++) {
                    $sizeBytes = [long](Get-Random -Minimum 0 -Maximum 107374182400)
                    $path = New-RandomWindowsPath
                    $category = @('Safe', 'Check', 'Aman Dihapus') | Get-Random

                    $items += [PSCustomObject]@{
                        Path      = "$path\file_$i.dat"
                        Label     = "Item $i"
                        SizeBytes = $sizeBytes
                        Category  = $category
                    }
                    $expectedTotalSize += $sizeBytes
                }

                # Act
                $preview = Get-CleanupPreview -Items $items

                # Assert: ItemCount equals input array length
                $preview.ItemCount | Should -Be $itemCount

                # Assert: TotalSize equals sum of all SizeBytes
                $preview.TotalSize | Should -Be $expectedTotalSize

                # Assert: ItemList contains all items
                $preview.ItemList.Count | Should -Be $itemCount

                # Assert: Each item's path, size, and category appear in preview
                for ($i = 0; $i -lt $itemCount; $i++) {
                    $previewItem = $preview.ItemList[$i]
                    $previewItem.Path | Should -Be $items[$i].Path
                    $previewItem.Size | Should -Be $items[$i].SizeBytes
                    $previewItem.Category | Should -Be $items[$i].Category
                }
            }
        }
    }

    Context "Property 3: Progress tracking correctness" {
        <#
            **Validates: Requirements 3.1, 3.2, 3.5**
            Show-CleanupProgress displays percentage that increases monotonically
            from 0% to 100%. After processing item at index I (0-based), the
            displayed percentage equals floor((I+1) / N * 100).
        #>

        It "Show-CleanupProgress displays correct percentage and truncated path for any item sequence" {
            1..50 | ForEach-Object {
                # Generate random item count (2-15)
                $totalItems = Get-Random -Minimum 2 -Maximum 16
                $items = @()
                $cumulativeSize = [long]0
                $previousPercentage = -1

                for ($i = 0; $i -lt $totalItems; $i++) {
                    $sizeBytes = [long](Get-Random -Minimum 1024 -Maximum 1073741824)
                    # Generate paths of varying lengths (some > 60 chars)
                    $pathLength = Get-Random -Minimum 20 -Maximum 100
                    $path = "C:\$('x' * ($pathLength - 3))"

                    $items += [PSCustomObject]@{
                        Path      = $path
                        SizeBytes = $sizeBytes
                    }
                }

                # Verify progress for each item
                for ($i = 0; $i -lt $totalItems; $i++) {
                    $cumulativeSize += $items[$i].SizeBytes

                    # Calculate expected percentage
                    $expectedPercentage = [Math]::Floor(($i + 1) / $totalItems * 100)

                    # Capture Write-Host output using 6>&1 redirection
                    $output = Show-CleanupProgress -CurrentPath $items[$i].Path `
                        -CurrentIndex $i `
                        -TotalItems $totalItems `
                        -SpaceFreedSoFar $cumulativeSize 6>&1

                    $outputStr = $output | Out-String

                    # Assert: percentage is in the output
                    $outputStr | Should -Match "\[$expectedPercentage%\]"

                    # Assert: percentage increases monotonically
                    $expectedPercentage | Should -BeGreaterOrEqual $previousPercentage
                    $previousPercentage = $expectedPercentage

                    # Assert: path truncation (if > 60 chars, should end with "...")
                    if ($items[$i].Path.Length -gt 60) {
                        $outputStr | Should -Match '\.\.\.'
                    }
                }

                # Assert: final percentage is 100%
                $previousPercentage | Should -Be 100
            }
        }
    }

    Context "Property 4: Error resilience — skip and continue" {
        <#
            **Validates: Requirements 3.4, 4.4, 5.5**
            When individual items fail during cleanup, the process continues
            with remaining items. ErrorCount in the result matches the number
            of failed items.
        #>

        BeforeAll {
            $Script:TestRoot = Join-Path $env:TEMP "drivepulse-cleanup-prop4-$(Get-Random)"
            New-Item -Path $Script:TestRoot -ItemType Directory -Force | Out-Null
        }

        AfterAll {
            Remove-Item $Script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }

        It "Start-SafeCleanup continues processing after item failures and reports correct ErrorCount" {
            1..50 | ForEach-Object {
                $iterDir = Join-Path $Script:TestRoot "iter_$_"
                New-Item -Path $iterDir -ItemType Directory -Force | Out-Null

                # Generate random items (3-8)
                $itemCount = Get-Random -Minimum 3 -Maximum 9
                $items = @()
                $failIndices = @()

                # Randomly select which items will fail (at least 1, at most half)
                $failCount = Get-Random -Minimum 1 -Maximum ([Math]::Max(2, [Math]::Floor($itemCount / 2) + 1))
                $failIndices = @(0..($itemCount - 1) | Get-Random -Count $failCount)

                for ($i = 0; $i -lt $itemCount; $i++) {
                    $filePath = Join-Path $iterDir "file_$i.dat"
                    $content = New-RandomFileContent -MinSize 10 -MaxSize 256
                    [System.IO.File]::WriteAllBytes($filePath, $content)

                    $items += [PSCustomObject]@{
                        Path      = $filePath
                        Label     = "Item $i"
                        SizeBytes = $content.Length
                        Category  = 'Safe'
                    }
                }

                # Mock Backup-BeforeDelete to fail for specific indices
                $Script:CallIndex = 0
                $Script:FailIndicesForMock = $failIndices
                Mock Backup-BeforeDelete {
                    $idx = $Script:CallIndex
                    $Script:CallIndex++
                    if ($idx -in $Script:FailIndicesForMock) {
                        return [PSCustomObject]@{ Success = $false; BackupPath = ''; Error = "Simulated failure for item $idx" }
                    }
                    return [PSCustomObject]@{ Success = $true; BackupPath = "backup_$idx"; Error = '' }
                }

                Mock Move-ToStaging {
                    return [PSCustomObject]@{ Success = $true; StagedPath = "staged_path"; Error = '' }
                }

                Mock Remove-ExpiredBackups { }
                Mock Remove-ExpiredStaged { }
                Mock Write-AuditEntry { }

                # Act: Run cleanup with Force (skip confirmation)
                $result = Start-SafeCleanup -Items $items -Force

                # Assert: Operation completed
                $result.Status | Should -Be 'completed'

                # Assert: ErrorCount matches number of failed items
                $result.ErrorCount | Should -Be $failCount

                # Assert: Items processed = total - failed
                $expectedProcessed = $itemCount - $failCount
                $result.ItemsProcessed | Should -Be $expectedProcessed

                # Assert: Errors array has correct count
                $result.Errors.Count | Should -Be $failCount

                # Reset call index
                $Script:CallIndex = 0
            }
        }
    }

    Context "Property 14: Safe-only cleanup filter" {
        <#
            **Validates: Requirements 10.4**
            Start-SafeCleanup only processes items with Category "Safe" or "Aman Dihapus".
            Items with Category "Check" are never processed.
        #>

        BeforeAll {
            $Script:TestRoot = Join-Path $env:TEMP "drivepulse-cleanup-prop14-$(Get-Random)"
            New-Item -Path $Script:TestRoot -ItemType Directory -Force | Out-Null
        }

        AfterAll {
            Remove-Item $Script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }

        It "Start-SafeCleanup only processes Safe/Aman Dihapus items, never Check items" {
            1..100 | ForEach-Object {
                $iterDir = Join-Path $Script:TestRoot "iter_$_"
                New-Item -Path $iterDir -ItemType Directory -Force | Out-Null

                # Generate mix of Safe, Aman Dihapus, and Check items
                $itemCount = Get-Random -Minimum 2 -Maximum 11
                $items = @()
                $safeCount = 0
                $checkPaths = @()

                for ($i = 0; $i -lt $itemCount; $i++) {
                    $filePath = Join-Path $iterDir "file_$i.dat"
                    $content = New-RandomFileContent -MinSize 10 -MaxSize 256
                    [System.IO.File]::WriteAllBytes($filePath, $content)

                    $category = @('Safe', 'Aman Dihapus', 'Check') | Get-Random

                    $items += [PSCustomObject]@{
                        Path      = $filePath
                        Label     = "Item $i"
                        SizeBytes = $content.Length
                        Category  = $category
                    }

                    if ($category -eq 'Safe' -or $category -eq 'Aman Dihapus') {
                        $safeCount++
                    }
                    else {
                        $checkPaths += $filePath
                    }
                }

                # Track which paths were processed by Backup-BeforeDelete
                $Script:ProcessedPaths = @()
                Mock Backup-BeforeDelete {
                    $Script:ProcessedPaths += $SourcePath
                    return [PSCustomObject]@{ Success = $true; BackupPath = "backup"; Error = '' }
                }

                Mock Move-ToStaging {
                    return [PSCustomObject]@{ Success = $true; StagedPath = "staged"; Error = '' }
                }

                Mock Remove-ExpiredBackups { }
                Mock Remove-ExpiredStaged { }
                Mock Write-AuditEntry { }

                # Act: Run cleanup with Force
                $result = Start-SafeCleanup -Items $items -Force

                # Assert: Only safe items were processed
                if ($safeCount -eq 0) {
                    $result.Status | Should -Be 'empty'
                    $result.ItemsProcessed | Should -Be 0
                }
                else {
                    $result.Status | Should -Be 'completed'
                    $result.ItemsProcessed | Should -Be $safeCount
                }

                # Assert: No Check items were processed
                foreach ($checkPath in $checkPaths) {
                    $Script:ProcessedPaths | Should -Not -Contain $checkPath
                }

                # Assert: Check item files remain untouched on disk
                foreach ($checkPath in $checkPaths) {
                    Test-Path $checkPath | Should -Be $true
                }

                # Reset
                $Script:ProcessedPaths = @()
            }
        }
    }
}
