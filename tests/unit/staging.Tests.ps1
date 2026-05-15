<#
.SYNOPSIS
    DrivePulse — Staging Module Unit Tests
.DESCRIPTION
    Unit tests for the staging area module covering file conflict during restore,
    insufficient space handling, auto-purge after retention, invalid retention fallback,
    locked file handling during purge, and empty staging area behavior.
    Validates: Requirements 8.6, 8.7, 8.8, 9.2, 9.4, 9.5, 12.4
#>

Describe "Staging Module" {
    BeforeAll {
        . "$PSScriptRoot\..\..\src\staging\staging.ps1"
    }

    BeforeEach {
        # Create isolated temp directory for each test
        $script:testDir = Join-Path $env:TEMP "drivepulse-staging-test-$(Get-Random)"
        New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null

        # Override StagingRoot to use temp directory
        $Script:StagingRoot = Join-Path $script:testDir 'Staging'
        New-Item -ItemType Directory -Path $Script:StagingRoot -Force | Out-Null
    }

    AfterEach {
        Remove-Item $script:testDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context "Prompt on file conflict during restore (Req 8.6)" {
        It "Returns error when target file already exists and -Force is not specified" {
            # Arrange: stage a file, then create a conflicting file at the original path
            $sourceDir = Join-Path $script:testDir 'source'
            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            $sourceFile = Join-Path $sourceDir 'conflict.txt'
            Set-Content -Path $sourceFile -Value "original content"

            # Move file to staging
            $result = Move-ToStaging -SourcePath $sourceFile -SessionId "test-session-001"
            $result.Success | Should -Be $true

            # Create a conflicting file at the original path
            Set-Content -Path $sourceFile -Value "new conflicting content"

            # Act: attempt restore without -Force
            $restoreResult = Restore-FromStaging -OriginalPath $sourceFile

            # Assert: should fail with conflict error
            $restoreResult.Success | Should -Be $false
            $restoreResult.Error | Should -BeLike "*sudah ada*"
        }

        It "Succeeds when -Force is specified and target file exists" {
            # Arrange: stage a file, then create a conflicting file at the original path
            $sourceDir = Join-Path $script:testDir 'source'
            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            $sourceFile = Join-Path $sourceDir 'conflict-force.txt'
            Set-Content -Path $sourceFile -Value "original content"

            # Move file to staging
            $result = Move-ToStaging -SourcePath $sourceFile -SessionId "test-session-002"
            $result.Success | Should -Be $true

            # Create a conflicting file at the original path
            Set-Content -Path $sourceFile -Value "new conflicting content"

            # Act: restore with -Force
            $restoreResult = Restore-FromStaging -OriginalPath $sourceFile -Force

            # Assert: should succeed and overwrite
            $restoreResult.Success | Should -Be $true
            $restoreResult.RestoredPath | Should -Be $sourceFile
            Get-Content -Path $sourceFile | Should -Be "original content"
        }
    }

    Context "Skip on insufficient space (Req 8.8)" {
        It "Returns error when disk space is insufficient for staging" {
            # Arrange: create a source file
            $sourceDir = Join-Path $script:testDir 'source'
            New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
            $sourceFile = Join-Path $sourceDir 'largefile.dat'
            Set-Content -Path $sourceFile -Value "test content"

            # Mock Get-PSDrive to simulate insufficient space
            Mock Get-PSDrive {
                [PSCustomObject]@{
                    Name = 'C'
                    Free = 0  # Zero free space
                }
            }

            # Act
            $result = Move-ToStaging -SourcePath $sourceFile -SessionId "test-session-003"

            # Assert: should fail due to insufficient space
            $result.Success | Should -Be $false
            $result.Error | Should -BeLike "*Ruang disk tidak cukup*"

            # Original file should remain unmodified
            Test-Path $sourceFile | Should -Be $true
        }
    }

    Context "Auto-purge after retention period (Req 8.7, 9.2)" {
        It "Deletes staged files older than retention period" {
            # Arrange: create manifest with an expired entry
            $expiredTimestamp = (Get-Date).AddDays(-10).ToString('yyyy-MM-ddTHH:mm:sszzz')
            $recentTimestamp = (Get-Date).AddDays(-2).ToString('yyyy-MM-ddTHH:mm:sszzz')

            # Create staged files on disk
            $expiredStagedPath = Join-Path $Script:StagingRoot 'C_drive\temp\expired.txt'
            $recentStagedPath = Join-Path $Script:StagingRoot 'C_drive\temp\recent.txt'

            New-Item -ItemType Directory -Path (Split-Path $expiredStagedPath) -Force | Out-Null
            Set-Content -Path $expiredStagedPath -Value "expired content"
            Set-Content -Path $recentStagedPath -Value "recent content"

            # Create manifest with both entries
            $manifest = [PSCustomObject]@{
                files = @(
                    [PSCustomObject]@{
                        originalPath     = 'C:\temp\expired.txt'
                        stagedPath       = 'C_drive\temp\expired.txt'
                        sizeBytes        = 100
                        stagingTimestamp = $expiredTimestamp
                        sessionId        = 'session-old'
                    },
                    [PSCustomObject]@{
                        originalPath     = 'C:\temp\recent.txt'
                        stagedPath       = 'C_drive\temp\recent.txt'
                        sizeBytes        = 200
                        stagingTimestamp = $recentTimestamp
                        sessionId        = 'session-new'
                    }
                )
            }
            Save-StagingManifest -Manifest $manifest

            # Act: purge with 7-day retention
            $result = Remove-ExpiredStaged -RetentionDays 7

            # Assert: expired file purged, recent file retained
            $result.PurgedCount | Should -Be 1
            $result.PurgedSize | Should -Be 100
            $result.Errors.Count | Should -Be 0

            # Expired file should be gone from disk
            Test-Path $expiredStagedPath | Should -Be $false

            # Recent file should still exist
            Test-Path $recentStagedPath | Should -Be $true

            # Manifest should only contain the recent entry
            $updatedManifest = Get-StagingManifest
            $updatedManifest.files.Count | Should -Be 1
            $updatedManifest.files[0].originalPath | Should -Be 'C:\temp\recent.txt'
        }

        It "Purges all expired files when all are beyond retention" {
            # Arrange: all entries expired
            $expiredTimestamp1 = (Get-Date).AddDays(-15).ToString('yyyy-MM-ddTHH:mm:sszzz')
            $expiredTimestamp2 = (Get-Date).AddDays(-20).ToString('yyyy-MM-ddTHH:mm:sszzz')

            $stagedPath1 = Join-Path $Script:StagingRoot 'C_drive\temp\old1.txt'
            $stagedPath2 = Join-Path $Script:StagingRoot 'C_drive\temp\old2.txt'

            New-Item -ItemType Directory -Path (Split-Path $stagedPath1) -Force | Out-Null
            Set-Content -Path $stagedPath1 -Value "old1"
            Set-Content -Path $stagedPath2 -Value "old2"

            $manifest = [PSCustomObject]@{
                files = @(
                    [PSCustomObject]@{
                        originalPath     = 'C:\temp\old1.txt'
                        stagedPath       = 'C_drive\temp\old1.txt'
                        sizeBytes        = 50
                        stagingTimestamp = $expiredTimestamp1
                        sessionId        = 'session-a'
                    },
                    [PSCustomObject]@{
                        originalPath     = 'C:\temp\old2.txt'
                        stagedPath       = 'C_drive\temp\old2.txt'
                        sizeBytes        = 75
                        stagingTimestamp = $expiredTimestamp2
                        sessionId        = 'session-b'
                    }
                )
            }
            Save-StagingManifest -Manifest $manifest

            # Act
            $result = Remove-ExpiredStaged -RetentionDays 7

            # Assert
            $result.PurgedCount | Should -Be 2
            $result.PurgedSize | Should -Be 125
            Test-Path $stagedPath1 | Should -Be $false
            Test-Path $stagedPath2 | Should -Be $false
        }
    }

    Context "Invalid retention falls back to default 7 (Req 9.4)" {
        It "Returns 7 for retention value of 0" {
            $result = Resolve-RetentionDays -RetentionDays 0
            $result | Should -Be 7
        }

        It "Returns 7 for retention value of 91" {
            $result = Resolve-RetentionDays -RetentionDays 91
            $result | Should -Be 7
        }

        It "Returns 7 for non-numeric string 'abc'" {
            $result = Resolve-RetentionDays -RetentionDays 'abc'
            $result | Should -Be 7
        }

        It "Returns 7 for negative value -5" {
            $result = Resolve-RetentionDays -RetentionDays (-5)
            $result | Should -Be 7
        }

        It "Returns 7 for null value" {
            $result = Resolve-RetentionDays -RetentionDays $null
            $result | Should -Be 7
        }

        It "Returns valid value when within range (1-90)" {
            $result = Resolve-RetentionDays -RetentionDays 30
            $result | Should -Be 30
        }

        It "Returns 1 for minimum valid value" {
            $result = Resolve-RetentionDays -RetentionDays 1
            $result | Should -Be 1
        }

        It "Returns 90 for maximum valid value" {
            $result = Resolve-RetentionDays -RetentionDays 90
            $result | Should -Be 90
        }
    }

    Context "Skip and log on locked file during purge (Req 9.5)" {
        It "Continues processing when a file cannot be deleted and logs warning" {
            # Arrange: create manifest with an expired entry whose file is locked
            $expiredTimestamp = (Get-Date).AddDays(-10).ToString('yyyy-MM-ddTHH:mm:sszzz')

            $lockedStagedPath = Join-Path $Script:StagingRoot 'C_drive\temp\locked.txt'
            $normalStagedPath = Join-Path $Script:StagingRoot 'C_drive\temp\normal.txt'

            New-Item -ItemType Directory -Path (Split-Path $lockedStagedPath) -Force | Out-Null
            Set-Content -Path $lockedStagedPath -Value "locked content"
            Set-Content -Path $normalStagedPath -Value "normal content"

            $manifest = [PSCustomObject]@{
                files = @(
                    [PSCustomObject]@{
                        originalPath     = 'C:\temp\locked.txt'
                        stagedPath       = 'C_drive\temp\locked.txt'
                        sizeBytes        = 100
                        stagingTimestamp = $expiredTimestamp
                        sessionId        = 'session-lock'
                    },
                    [PSCustomObject]@{
                        originalPath     = 'C:\temp\normal.txt'
                        stagedPath       = 'C_drive\temp\normal.txt'
                        sizeBytes        = 200
                        stagingTimestamp = $expiredTimestamp
                        sessionId        = 'session-lock'
                    }
                )
            }
            Save-StagingManifest -Manifest $manifest

            # Lock the file by opening an exclusive stream
            $stream = [System.IO.File]::Open($lockedStagedPath, 'Open', 'ReadWrite', 'None')

            try {
                # Act: purge should skip locked file and continue
                $result = Remove-ExpiredStaged -RetentionDays 7

                # Assert: one purged (normal), one error (locked)
                $result.PurgedCount | Should -Be 1
                $result.PurgedSize | Should -Be 200
                $result.Errors.Count | Should -Be 1
                $result.Errors[0] | Should -BeLike "*locked.txt*"

                # Normal file should be deleted
                Test-Path $normalStagedPath | Should -Be $false

                # Locked file should still exist
                Test-Path $lockedStagedPath | Should -Be $true

                # Manifest should retain the locked file entry
                $updatedManifest = Get-StagingManifest
                $updatedManifest.files.Count | Should -Be 1
                $updatedManifest.files[0].originalPath | Should -Be 'C:\temp\locked.txt'
            }
            finally {
                $stream.Close()
                $stream.Dispose()
            }
        }
    }

    Context "Empty staging area behavior (Req 12.4)" {
        It "Get-StagedFiles returns empty array when no files are staged" {
            # Arrange: ensure empty manifest
            $manifest = [PSCustomObject]@{ files = @() }
            Save-StagingManifest -Manifest $manifest

            # Act
            $result = @(Get-StagedFiles)

            # Assert: should be an empty array (count 0)
            $result.Count | Should -Be 0
        }

        It "Get-StagedFiles returns empty array when manifest does not exist" {
            # Arrange: remove manifest file if it exists
            $manifestPath = Get-StagingManifestPath
            if (Test-Path $manifestPath) {
                Remove-Item $manifestPath -Force
            }

            # Act
            $result = Get-StagedFiles

            # Assert
            $result | Should -HaveCount 0
        }

        It "Remove-ExpiredStaged returns zero counts on empty staging area" {
            # Arrange: empty manifest
            $manifest = [PSCustomObject]@{ files = @() }
            Save-StagingManifest -Manifest $manifest

            # Act
            $result = Remove-ExpiredStaged -RetentionDays 7

            # Assert
            $result.PurgedCount | Should -Be 0
            $result.PurgedSize | Should -Be 0
            $result.Errors.Count | Should -Be 0
        }
    }
}
