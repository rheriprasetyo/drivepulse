<#
.SYNOPSIS
    DrivePulse — Cleanup Flow Integration Tests
.DESCRIPTION
    Integration tests for the full cleanup flow:
    - Full cycle: create temp files → build categorized items → Start-SafeCleanup -Force →
      verify backup in BackupRoot → verify files staged in StagingRoot → verify originals gone
    - Retention purge: create old backup/staging entries → start session → verify purge
.NOTES
    Requirements: 1.1, 1.2, 1.5, 4.1, 8.1, 6.2, 9.2
#>

BeforeAll {
    . "$PSScriptRoot\..\..\src\cleaner\clean.ps1"
}

Describe "Integration: Full Cleanup Cycle" -Tag "Integration" {
    BeforeEach {
        # Override BackupRoot and StagingRoot to use temp directories for isolation
        $script:OriginalBackupRoot = $Script:BackupRoot
        $script:OriginalStagingRoot = $Script:StagingRoot

        $Script:BackupRoot = Join-Path $TestDrive "IntBackupRoot"
        $Script:StagingRoot = Join-Path $TestDrive "IntStagingRoot"

        New-Item -Path $Script:BackupRoot -ItemType Directory -Force | Out-Null
        New-Item -Path $Script:StagingRoot -ItemType Directory -Force | Out-Null

        # Create source files to be cleaned
        $script:sourceDir = Join-Path $TestDrive "SourceFiles"
        New-Item -Path $script:sourceDir -ItemType Directory -Force | Out-Null
    }

    AfterEach {
        $Script:BackupRoot = $script:OriginalBackupRoot
        $Script:StagingRoot = $script:OriginalStagingRoot
    }

    Context "Scan → Preview → Confirm → Backup → Stage → Verify" {
        It "Full cleanup cycle backs up files, stages them, and removes originals" {
            # Arrange: Create temp files with known content
            $file1 = Join-Path $script:sourceDir "cache1.tmp"
            $file2 = Join-Path $script:sourceDir "cache2.tmp"
            $file3 = Join-Path $script:sourceDir "logs\old.log"

            $content1 = [byte[]](1..100 | ForEach-Object { Get-Random -Minimum 0 -Maximum 256 })
            $content2 = [byte[]](1..200 | ForEach-Object { Get-Random -Minimum 0 -Maximum 256 })
            $content3 = [byte[]](1..50 | ForEach-Object { Get-Random -Minimum 0 -Maximum 256 })

            [System.IO.File]::WriteAllBytes($file1, $content1)
            [System.IO.File]::WriteAllBytes($file2, $content2)
            New-Item -Path (Split-Path $file3) -ItemType Directory -Force | Out-Null
            [System.IO.File]::WriteAllBytes($file3, $content3)

            # Build categorized items array (simulating scanner output)
            $items = @(
                [PSCustomObject]@{ Path = $file1; SizeBytes = $content1.Length; Category = 'Safe' }
                [PSCustomObject]@{ Path = $file2; SizeBytes = $content2.Length; Category = 'Safe' }
                [PSCustomObject]@{ Path = $file3; SizeBytes = $content3.Length; Category = 'Safe' }
            )

            # Act: Run cleanup with -Force (skips confirmation prompt)
            $result = Start-SafeCleanup -Items $items -Force

            # Assert: Cleanup completed successfully
            $result.Status | Should -Be 'completed'
            $result.ItemsProcessed | Should -Be 3
            $result.ErrorCount | Should -Be 0
            $result.SessionId | Should -Not -BeNullOrEmpty

            # Assert: Original files no longer exist
            Test-Path $file1 | Should -BeFalse
            Test-Path $file2 | Should -BeFalse
            Test-Path $file3 | Should -BeFalse

            # Assert: Files are backed up in BackupRoot
            $sessionBackupDir = Join-Path $Script:BackupRoot $result.SessionId
            Test-Path $sessionBackupDir | Should -BeTrue

            # Verify backup manifest exists
            $manifestPath = Join-Path $sessionBackupDir "backup-manifest.json"
            Test-Path $manifestPath | Should -BeTrue

            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
            $manifest.files.Count | Should -Be 3
            $manifest.sessionId | Should -Be $result.SessionId

            # Assert: Files are staged in StagingRoot
            $stagingManifestPath = Join-Path $Script:StagingRoot "staging-manifest.json"
            Test-Path $stagingManifestPath | Should -BeTrue

            $stagingManifest = Get-Content $stagingManifestPath -Raw | ConvertFrom-Json
            $stagingManifest.files.Count | Should -Be 3

            # Verify staged files exist on disk
            foreach ($entry in $stagingManifest.files) {
                $stagedFullPath = Join-Path $Script:StagingRoot $entry.stagedPath
                Test-Path $stagedFullPath | Should -BeTrue
            }
        }

        It "Cleanup with -Force reports correct space freed" {
            # Arrange: Create files with known sizes
            $file1 = Join-Path $script:sourceDir "sized1.bin"
            $file2 = Join-Path $script:sourceDir "sized2.bin"

            $content1 = [byte[]](New-Object byte[] 1024)  # 1 KB
            $content2 = [byte[]](New-Object byte[] 2048)  # 2 KB

            [System.IO.File]::WriteAllBytes($file1, $content1)
            [System.IO.File]::WriteAllBytes($file2, $content2)

            $items = @(
                [PSCustomObject]@{ Path = $file1; SizeBytes = 1024; Category = 'Safe' }
                [PSCustomObject]@{ Path = $file2; SizeBytes = 2048; Category = 'Safe' }
            )

            # Act
            $result = Start-SafeCleanup -Items $items -Force

            # Assert: Space freed matches sum of file sizes
            $result.SpaceFreed | Should -Be 3072
            $result.ItemsProcessed | Should -Be 2
        }

        It "Only processes Safe category items, skips Check items" {
            # Arrange: Mix of Safe and Check items
            $safeFile = Join-Path $script:sourceDir "safe-file.tmp"
            $checkFile = Join-Path $script:sourceDir "check-file.dat"

            $safeContent = [byte[]](1..50 | ForEach-Object { Get-Random -Minimum 0 -Maximum 256 })
            $checkContent = [byte[]](1..75 | ForEach-Object { Get-Random -Minimum 0 -Maximum 256 })

            [System.IO.File]::WriteAllBytes($safeFile, $safeContent)
            [System.IO.File]::WriteAllBytes($checkFile, $checkContent)

            $items = @(
                [PSCustomObject]@{ Path = $safeFile; SizeBytes = $safeContent.Length; Category = 'Safe' }
                [PSCustomObject]@{ Path = $checkFile; SizeBytes = $checkContent.Length; Category = 'Check' }
            )

            # Act
            $result = Start-SafeCleanup -Items $items -Force

            # Assert: Only Safe item processed
            $result.ItemsProcessed | Should -Be 1

            # Assert: Safe file is gone
            Test-Path $safeFile | Should -BeFalse

            # Assert: Check file is untouched
            Test-Path $checkFile | Should -BeTrue
            $remainingContent = [System.IO.File]::ReadAllBytes($checkFile)
            [System.Convert]::ToBase64String($remainingContent) | Should -Be ([System.Convert]::ToBase64String($checkContent))
        }
    }

    Context "Dry-run mode does not modify files" {
        It "DryRun mode previews without modifying any files" {
            # Arrange
            $file1 = Join-Path $script:sourceDir "dryrun-file.tmp"
            $content1 = [byte[]](1..30 | ForEach-Object { Get-Random -Minimum 0 -Maximum 256 })
            [System.IO.File]::WriteAllBytes($file1, $content1)

            $items = @(
                [PSCustomObject]@{ Path = $file1; SizeBytes = $content1.Length; Category = 'Safe' }
            )

            # Act: Run in dry-run mode (default)
            $result = Start-SafeCleanup -Items $items -DryRun

            # Assert: Status is dry-run
            $result.Status | Should -Be 'dry-run'
            $result.ItemsProcessed | Should -Be 0

            # Assert: File still exists and is unmodified
            Test-Path $file1 | Should -BeTrue
            $afterContent = [System.IO.File]::ReadAllBytes($file1)
            [System.Convert]::ToBase64String($afterContent) | Should -Be ([System.Convert]::ToBase64String($content1))

            # Assert: No backup or staging created
            $backupItems = Get-ChildItem -Path $Script:BackupRoot -Recurse -File -ErrorAction SilentlyContinue
            $backupItems | Should -BeNullOrEmpty

            $stagingManifestPath = Join-Path $Script:StagingRoot "staging-manifest.json"
            Test-Path $stagingManifestPath | Should -BeFalse
        }
    }

    Context "Empty items list" {
        It "Returns empty status when no Safe items are provided" {
            $items = @(
                [PSCustomObject]@{ Path = "C:\fake\file.tmp"; SizeBytes = 100; Category = 'Check' }
            )

            $result = Start-SafeCleanup -Items $items -Force

            $result.Status | Should -Be 'empty'
            $result.ItemsProcessed | Should -Be 0
        }
    }
}

Describe "Integration: Retention Purge" -Tag "Integration" {
    BeforeEach {
        # Override BackupRoot and StagingRoot to use temp directories for isolation
        $script:OriginalBackupRoot = $Script:BackupRoot
        $script:OriginalStagingRoot = $Script:StagingRoot

        $Script:BackupRoot = Join-Path $TestDrive "PurgeBackupRoot"
        $Script:StagingRoot = Join-Path $TestDrive "PurgeStagingRoot"

        New-Item -Path $Script:BackupRoot -ItemType Directory -Force | Out-Null
        New-Item -Path $Script:StagingRoot -ItemType Directory -Force | Out-Null

        # Create source directory for new files
        $script:sourceDir = Join-Path $TestDrive "PurgeSourceFiles"
        New-Item -Path $script:sourceDir -ItemType Directory -Force | Out-Null
    }

    AfterEach {
        $Script:BackupRoot = $script:OriginalBackupRoot
        $Script:StagingRoot = $script:OriginalStagingRoot
    }

    Context "Expired backup entries are purged at session start" {
        It "Old backup entries (older than 7 days) are purged when a new cleanup session starts" {
            # Arrange: Create an old backup session manually (simulating 10 days ago)
            $oldSessionId = "20260101-100000-old001"
            $oldSessionDir = Join-Path $Script:BackupRoot $oldSessionId
            New-Item -Path $oldSessionDir -ItemType Directory -Force | Out-Null

            # Create a fake backed-up file
            $oldBackupFile = Join-Path $oldSessionDir "C_drive\temp\old-cache.tmp"
            New-Item -Path (Split-Path $oldBackupFile) -ItemType Directory -Force | Out-Null
            [System.IO.File]::WriteAllBytes($oldBackupFile, ([byte[]](1..20)))

            # Create manifest with old timestamp (10 days ago)
            $oldTimestamp = (Get-Date).AddDays(-10).ToString('yyyy-MM-ddTHH:mm:sszzz')
            $oldManifest = @{
                sessionId = $oldSessionId
                createdAt = $oldTimestamp
                files     = @(
                    @{
                        originalPath = "C:\temp\old-cache.tmp"
                        backupPath   = "$oldSessionId\C_drive\temp\old-cache.tmp"
                        sizeBytes    = 20
                        timestamp    = $oldTimestamp
                    }
                )
            }
            $manifestPath = Join-Path $oldSessionDir "backup-manifest.json"
            $oldManifest | ConvertTo-Json -Depth 10 | Set-Content -Path $manifestPath -Encoding UTF8

            # Verify old backup exists before cleanup
            Test-Path $oldBackupFile | Should -BeTrue

            # Arrange: Create a new file to clean (triggers a new session)
            $newFile = Join-Path $script:sourceDir "new-file.tmp"
            [System.IO.File]::WriteAllBytes($newFile, ([byte[]](1..10)))

            $items = @(
                [PSCustomObject]@{ Path = $newFile; SizeBytes = 10; Category = 'Safe' }
            )

            # Act: Start a new cleanup session (which triggers Remove-ExpiredBackups)
            $result = Start-SafeCleanup -Items $items -Force

            # Assert: New cleanup completed
            $result.Status | Should -Be 'completed'
            $result.ItemsProcessed | Should -Be 1

            # Assert: Old backup session was purged
            Test-Path $oldBackupFile | Should -BeFalse
            Test-Path $oldSessionDir | Should -BeFalse
        }

        It "Recent backup entries (within 7 days) are NOT purged" {
            # Arrange: Create a recent backup session (2 days ago)
            $recentSessionId = "20260501-100000-rec001"
            $recentSessionDir = Join-Path $Script:BackupRoot $recentSessionId
            New-Item -Path $recentSessionDir -ItemType Directory -Force | Out-Null

            $recentBackupFile = Join-Path $recentSessionDir "C_drive\temp\recent-cache.tmp"
            New-Item -Path (Split-Path $recentBackupFile) -ItemType Directory -Force | Out-Null
            [System.IO.File]::WriteAllBytes($recentBackupFile, ([byte[]](1..30)))

            $recentTimestamp = (Get-Date).AddDays(-2).ToString('yyyy-MM-ddTHH:mm:sszzz')
            $recentManifest = @{
                sessionId = $recentSessionId
                createdAt = $recentTimestamp
                files     = @(
                    @{
                        originalPath = "C:\temp\recent-cache.tmp"
                        backupPath   = "$recentSessionId\C_drive\temp\recent-cache.tmp"
                        sizeBytes    = 30
                        timestamp    = $recentTimestamp
                    }
                )
            }
            $manifestPath = Join-Path $recentSessionDir "backup-manifest.json"
            $recentManifest | ConvertTo-Json -Depth 10 | Set-Content -Path $manifestPath -Encoding UTF8

            # Arrange: Create a new file to clean
            $newFile = Join-Path $script:sourceDir "trigger-file.tmp"
            [System.IO.File]::WriteAllBytes($newFile, ([byte[]](1..10)))

            $items = @(
                [PSCustomObject]@{ Path = $newFile; SizeBytes = 10; Category = 'Safe' }
            )

            # Act
            $result = Start-SafeCleanup -Items $items -Force

            # Assert: Recent backup is still there
            Test-Path $recentBackupFile | Should -BeTrue
            Test-Path $recentSessionDir | Should -BeTrue
        }
    }

    Context "Expired staging entries are purged at session start" {
        It "Old staged files (older than 7 days) are purged when a new cleanup session starts" {
            # Arrange: Create an old staged file manually
            $oldStagedRelPath = "C_drive\temp\old-staged.tmp"
            $oldStagedFullPath = Join-Path $Script:StagingRoot $oldStagedRelPath
            New-Item -Path (Split-Path $oldStagedFullPath) -ItemType Directory -Force | Out-Null
            [System.IO.File]::WriteAllBytes($oldStagedFullPath, ([byte[]](1..25)))

            # Create staging manifest with old timestamp (10 days ago)
            $oldTimestamp = (Get-Date).AddDays(-10).ToString('yyyy-MM-ddTHH:mm:sszzz')
            $stagingManifest = @{
                files = @(
                    @{
                        originalPath     = "C:\temp\old-staged.tmp"
                        stagedPath       = $oldStagedRelPath
                        sizeBytes        = 25
                        stagingTimestamp = $oldTimestamp
                        sessionId        = "20260101-090000-old002"
                    }
                )
            }
            $stagingManifestPath = Join-Path $Script:StagingRoot "staging-manifest.json"
            $stagingManifest | ConvertTo-Json -Depth 10 | Set-Content -Path $stagingManifestPath -Encoding UTF8

            # Verify old staged file exists
            Test-Path $oldStagedFullPath | Should -BeTrue

            # Arrange: Create a new file to trigger cleanup session
            $newFile = Join-Path $script:sourceDir "new-trigger.tmp"
            [System.IO.File]::WriteAllBytes($newFile, ([byte[]](1..15)))

            $items = @(
                [PSCustomObject]@{ Path = $newFile; SizeBytes = 15; Category = 'Safe' }
            )

            # Act: Start cleanup (triggers Remove-ExpiredStaged)
            $result = Start-SafeCleanup -Items $items -Force

            # Assert: Cleanup completed
            $result.Status | Should -Be 'completed'

            # Assert: Old staged file was purged
            Test-Path $oldStagedFullPath | Should -BeFalse

            # Assert: Staging manifest no longer contains the old entry
            $updatedManifest = Get-Content $stagingManifestPath -Raw | ConvertFrom-Json
            $oldEntry = $updatedManifest.files | Where-Object { $_.originalPath -eq "C:\temp\old-staged.tmp" }
            $oldEntry | Should -BeNullOrEmpty
        }

        It "Recent staged files (within 7 days) are NOT purged" {
            # Arrange: Create a recent staged file (3 days ago)
            $recentStagedRelPath = "C_drive\temp\recent-staged.tmp"
            $recentStagedFullPath = Join-Path $Script:StagingRoot $recentStagedRelPath
            New-Item -Path (Split-Path $recentStagedFullPath) -ItemType Directory -Force | Out-Null
            [System.IO.File]::WriteAllBytes($recentStagedFullPath, ([byte[]](1..40)))

            $recentTimestamp = (Get-Date).AddDays(-3).ToString('yyyy-MM-ddTHH:mm:sszzz')
            $stagingManifest = @{
                files = @(
                    @{
                        originalPath     = "C:\temp\recent-staged.tmp"
                        stagedPath       = $recentStagedRelPath
                        sizeBytes        = 40
                        stagingTimestamp = $recentTimestamp
                        sessionId        = "20260501-090000-rec002"
                    }
                )
            }
            $stagingManifestPath = Join-Path $Script:StagingRoot "staging-manifest.json"
            $stagingManifest | ConvertTo-Json -Depth 10 | Set-Content -Path $stagingManifestPath -Encoding UTF8

            # Arrange: Create a new file to trigger cleanup
            $newFile = Join-Path $script:sourceDir "trigger2.tmp"
            [System.IO.File]::WriteAllBytes($newFile, ([byte[]](1..10)))

            $items = @(
                [PSCustomObject]@{ Path = $newFile; SizeBytes = 10; Category = 'Safe' }
            )

            # Act
            $result = Start-SafeCleanup -Items $items -Force

            # Assert: Recent staged file is still there
            Test-Path $recentStagedFullPath | Should -BeTrue

            # Assert: Manifest still contains the recent entry
            $updatedManifest = Get-Content $stagingManifestPath -Raw | ConvertFrom-Json
            $recentEntry = $updatedManifest.files | Where-Object { $_.originalPath -eq "C:\temp\recent-staged.tmp" }
            $recentEntry | Should -Not -BeNullOrEmpty
        }
    }
}
