<#
.SYNOPSIS
    DrivePulse — Cleaner Orchestrator Unit Tests
.DESCRIPTION
    Unit tests for the cleanup orchestrator module covering dry-run default mode,
    empty item list behavior, confirmation handling, cancellation with Bahasa Indonesia
    message, completion summary fields, and Safe-only item filtering.
    Validates: Requirements 1.1, 1.7, 2.2, 2.3, 2.4, 2.5, 3.3, 10.4
#>

Describe "Cleaner Orchestrator" {
    BeforeAll {
        . "$PSScriptRoot\..\..\src\cleaner\clean.ps1"
    }

    BeforeEach {
        # Mock dependencies to avoid filesystem operations
        Mock Backup-BeforeDelete {
            return [PSCustomObject]@{ Success = $true; BackupPath = "mock-backup"; Error = $null }
        }
        Mock Move-ToStaging {
            return [PSCustomObject]@{ Success = $true; StagedPath = "mock-staged"; Error = $null }
        }
        Mock Remove-ExpiredBackups { return [PSCustomObject]@{ PurgedCount = 0; PurgedSize = 0; Errors = @() } }
        Mock Remove-ExpiredStaged { return [PSCustomObject]@{ PurgedCount = 0; PurgedSize = 0; Errors = @() } }
        Mock Write-AuditEntry {}
    }

    Context "Default mode is dry-run (Req 1.1)" {
        It "Returns Status='dry-run' when called without -DryRun:false or -Force" {
            # Arrange
            $items = @(
                [PSCustomObject]@{ Path = 'C:\temp\file1.txt'; SizeBytes = 1024; Category = 'Safe' }
            )

            # Act
            $result = Start-SafeCleanup -Items $items

            # Assert
            $result.Status | Should -Be 'dry-run'
            $result.ItemsProcessed | Should -Be 0
        }

        It "Does not call Backup-BeforeDelete in dry-run mode" {
            # Arrange
            $items = @(
                [PSCustomObject]@{ Path = 'C:\temp\file1.txt'; SizeBytes = 2048; Category = 'Safe' }
            )

            # Act
            Start-SafeCleanup -Items $items | Out-Null

            # Assert
            Should -Invoke Backup-BeforeDelete -Times 0
        }

        It "Does not call Move-ToStaging in dry-run mode" {
            # Arrange
            $items = @(
                [PSCustomObject]@{ Path = 'C:\temp\file1.txt'; SizeBytes = 2048; Category = 'Safe' }
            )

            # Act
            Start-SafeCleanup -Items $items | Out-Null

            # Assert
            Should -Invoke Move-ToStaging -Times 0
        }
    }

    Context "Empty item list shows message, no prompt (Req 1.7, 2.5)" {
        It "Returns Status='empty' when all items are 'Check' category" {
            # Arrange: only Check items, no Safe items
            $items = @(
                [PSCustomObject]@{ Path = 'C:\temp\check1.txt'; SizeBytes = 500; Category = 'Check' },
                [PSCustomObject]@{ Path = 'C:\temp\check2.txt'; SizeBytes = 700; Category = 'Check' }
            )

            # Act
            $result = Start-SafeCleanup -Items $items -DryRun:$false -Force

            # Assert
            $result.Status | Should -Be 'empty'
            $result.ItemsProcessed | Should -Be 0
        }

        It "Does not prompt for confirmation when no Safe items exist" {
            # Arrange
            Mock Read-Host { throw "Read-Host should not be called" }
            $items = @(
                [PSCustomObject]@{ Path = 'C:\temp\check1.txt'; SizeBytes = 500; Category = 'Check' }
            )

            # Act - should not throw because Read-Host should not be called
            $result = Start-SafeCleanup -Items $items -DryRun:$false

            # Assert
            $result.Status | Should -Be 'empty'
        }

        It "Displays 'Tidak ada item yang memenuhi syarat' message" {
            # Arrange
            $items = @(
                [PSCustomObject]@{ Path = 'C:\temp\check1.txt'; SizeBytes = 500; Category = 'Check' }
            )

            # Act & Assert: capture Write-Host output
            $output = Start-SafeCleanup -Items $items -DryRun:$false -Force 6>&1
            $outputText = ($output | Out-String)
            $outputText | Should -BeLike "*Tidak ada item yang memenuhi syarat*"
        }
    }

    Context "Confirmation with 'y'/'Y' proceeds (Req 2.2)" {
        It "Proceeds with cleanup when user enters 'y'" {
            # Arrange
            Mock Read-Host { return 'y' }
            $items = @(
                [PSCustomObject]@{ Path = 'C:\temp\file1.txt'; SizeBytes = 1024; Category = 'Safe' }
            )

            # Act
            $result = Start-SafeCleanup -Items $items -DryRun:$false

            # Assert
            $result.Status | Should -Be 'completed'
            $result.ItemsProcessed | Should -Be 1
        }

        It "Proceeds with cleanup when user enters 'Y'" {
            # Arrange
            Mock Read-Host { return 'Y' }
            $items = @(
                [PSCustomObject]@{ Path = 'C:\temp\file1.txt'; SizeBytes = 1024; Category = 'Safe' }
            )

            # Act
            $result = Start-SafeCleanup -Items $items -DryRun:$false

            # Assert
            $result.Status | Should -Be 'completed'
            $result.ItemsProcessed | Should -Be 1
        }
    }

    Context "Non-'y' input aborts with Bahasa Indonesia message (Req 2.3, 2.4)" {
        It "Returns Status='cancelled' when user enters 'n'" {
            # Arrange
            Mock Read-Host { return 'n' }
            $items = @(
                [PSCustomObject]@{ Path = 'C:\temp\file1.txt'; SizeBytes = 1024; Category = 'Safe' }
            )

            # Act
            $result = Start-SafeCleanup -Items $items -DryRun:$false

            # Assert
            $result.Status | Should -Be 'cancelled'
            $result.ItemsProcessed | Should -Be 0
        }

        It "Returns Status='cancelled' when user enters empty string" {
            # Arrange
            Mock Read-Host { return '' }
            $items = @(
                [PSCustomObject]@{ Path = 'C:\temp\file1.txt'; SizeBytes = 1024; Category = 'Safe' }
            )

            # Act
            $result = Start-SafeCleanup -Items $items -DryRun:$false

            # Assert
            $result.Status | Should -Be 'cancelled'
        }

        It "Returns Status='cancelled' when user enters arbitrary text" {
            # Arrange
            Mock Read-Host { return 'maybe' }
            $items = @(
                [PSCustomObject]@{ Path = 'C:\temp\file1.txt'; SizeBytes = 1024; Category = 'Safe' }
            )

            # Act
            $result = Start-SafeCleanup -Items $items -DryRun:$false

            # Assert
            $result.Status | Should -Be 'cancelled'
        }

        It "Displays 'Pembersihan dibatalkan.' message on cancellation" {
            # Arrange
            Mock Read-Host { return 'n' }
            $items = @(
                [PSCustomObject]@{ Path = 'C:\temp\file1.txt'; SizeBytes = 1024; Category = 'Safe' }
            )

            # Act & Assert: capture Write-Host output
            $output = Start-SafeCleanup -Items $items -DryRun:$false 6>&1
            $outputText = ($output | Out-String)
            $outputText | Should -BeLike "*Pembersihan dibatalkan*"
        }
    }

    Context "Completion summary fields (Req 3.3)" {
        It "Returns result with SessionId, ItemsProcessed, SpaceFreed, ErrorCount, ElapsedSeconds" {
            # Arrange
            Mock Read-Host { return 'y' }
            $items = @(
                [PSCustomObject]@{ Path = 'C:\temp\file1.txt'; SizeBytes = 1024; Category = 'Safe' },
                [PSCustomObject]@{ Path = 'C:\temp\file2.txt'; SizeBytes = 2048; Category = 'Safe' }
            )

            # Act
            $result = Start-SafeCleanup -Items $items -DryRun:$false

            # Assert: all summary fields present
            $result.PSObject.Properties.Name | Should -Contain 'SessionId'
            $result.PSObject.Properties.Name | Should -Contain 'ItemsProcessed'
            $result.PSObject.Properties.Name | Should -Contain 'SpaceFreed'
            $result.PSObject.Properties.Name | Should -Contain 'ErrorCount'
            $result.PSObject.Properties.Name | Should -Contain 'ElapsedSeconds'

            # Assert: values are correct
            $result.SessionId | Should -Not -BeNullOrEmpty
            $result.ItemsProcessed | Should -Be 2
            $result.SpaceFreed | Should -Be 3072
            $result.ErrorCount | Should -Be 0
            $result.ElapsedSeconds | Should -BeGreaterOrEqual 0
        }

        It "SessionId follows YYYYMMDD-HHmmss-<6hex> format" {
            # Arrange
            Mock Read-Host { return 'y' }
            $items = @(
                [PSCustomObject]@{ Path = 'C:\temp\file1.txt'; SizeBytes = 512; Category = 'Safe' }
            )

            # Act
            $result = Start-SafeCleanup -Items $items -DryRun:$false

            # Assert: session ID matches expected format
            $result.SessionId | Should -Match '^\d{8}-\d{6}-[0-9a-f]{6}$'
        }
    }

    Context "Only 'Safe' items processed (Req 10.4)" {
        It "Processes only Safe items when given a mix of Safe and Check" {
            # Arrange
            Mock Read-Host { return 'y' }
            $items = @(
                [PSCustomObject]@{ Path = 'C:\temp\safe1.txt'; SizeBytes = 1000; Category = 'Safe' },
                [PSCustomObject]@{ Path = 'C:\temp\check1.txt'; SizeBytes = 2000; Category = 'Check' },
                [PSCustomObject]@{ Path = 'C:\temp\safe2.txt'; SizeBytes = 3000; Category = 'Safe' },
                [PSCustomObject]@{ Path = 'C:\temp\check2.txt'; SizeBytes = 4000; Category = 'Check' }
            )

            # Act
            $result = Start-SafeCleanup -Items $items -DryRun:$false

            # Assert: only 2 Safe items processed
            $result.ItemsProcessed | Should -Be 2
            $result.SpaceFreed | Should -Be 4000  # 1000 + 3000
        }

        It "Calls Backup-BeforeDelete only for Safe items" {
            # Arrange
            Mock Read-Host { return 'y' }
            $items = @(
                [PSCustomObject]@{ Path = 'C:\temp\safe1.txt'; SizeBytes = 100; Category = 'Safe' },
                [PSCustomObject]@{ Path = 'C:\temp\check1.txt'; SizeBytes = 200; Category = 'Check' },
                [PSCustomObject]@{ Path = 'C:\temp\safe2.txt'; SizeBytes = 300; Category = 'Safe' }
            )

            # Act
            Start-SafeCleanup -Items $items -DryRun:$false | Out-Null

            # Assert: Backup-BeforeDelete called exactly 2 times (for Safe items only)
            Should -Invoke Backup-BeforeDelete -Times 2
        }

        It "Calls Move-ToStaging only for Safe items" {
            # Arrange
            Mock Read-Host { return 'y' }
            $items = @(
                [PSCustomObject]@{ Path = 'C:\temp\safe1.txt'; SizeBytes = 100; Category = 'Safe' },
                [PSCustomObject]@{ Path = 'C:\temp\check1.txt'; SizeBytes = 200; Category = 'Check' }
            )

            # Act
            Start-SafeCleanup -Items $items -DryRun:$false | Out-Null

            # Assert: Move-ToStaging called exactly 1 time (for Safe item only)
            Should -Invoke Move-ToStaging -Times 1
        }

        It "Also processes items with 'Aman Dihapus' category as Safe" {
            # Arrange
            Mock Read-Host { return 'y' }
            $items = @(
                [PSCustomObject]@{ Path = 'C:\temp\aman1.txt'; SizeBytes = 500; Category = 'Aman Dihapus' },
                [PSCustomObject]@{ Path = 'C:\temp\check1.txt'; SizeBytes = 600; Category = 'Check' }
            )

            # Act
            $result = Start-SafeCleanup -Items $items -DryRun:$false

            # Assert
            $result.ItemsProcessed | Should -Be 1
            $result.SpaceFreed | Should -Be 500
        }
    }
}
