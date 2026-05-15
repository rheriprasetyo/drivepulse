<#
.SYNOPSIS
    DrivePulse — Restore Flow Integration Tests
.DESCRIPTION
    Integration tests for the restore flow:
    - Backup restore cycle: backup → delete original → restore from backup → verify content
    - Staging restore cycle: stage → restore from staging → verify content
.NOTES
    Requirements: 5.1, 5.2, 8.5
#>

BeforeAll {
    . "$PSScriptRoot\..\..\src\audit\audit.ps1"
    . "$PSScriptRoot\..\..\src\backup\backup.ps1"
    . "$PSScriptRoot\..\..\src\staging\staging.ps1"
}

Describe "Integration: Backup Restore Cycle" {
    BeforeAll {
        # Override BackupRoot to use temp directory for isolation
        $script:OriginalBackupRoot = $Script:BackupRoot
        $Script:BackupRoot = Join-Path $TestDrive "BackupRoot"
        New-Item -Path $Script:BackupRoot -ItemType Directory -Force | Out-Null
    }

    AfterAll {
        $Script:BackupRoot = $script:OriginalBackupRoot
    }

    Context "Single file backup and restore" {
        BeforeAll {
            $script:sessionId = "20260101-120000-abc123"

            # Create a temp file with known content
            $script:sourceDir = Join-Path $TestDrive "SourceFiles"
            New-Item -Path $script:sourceDir -ItemType Directory -Force | Out-Null
            $script:sourceFile = Join-Path $script:sourceDir "testfile.dat"

            # Write random binary content
            $script:originalContent = [byte[]](1..256 | ForEach-Object { Get-Random -Minimum 0 -Maximum 256 })
            [System.IO.File]::WriteAllBytes($script:sourceFile, $script:originalContent)
        }

        It "Backup creates a copy and restore returns identical content" {
            # Step 1: Backup the file
            $backupResult = Backup-BeforeDelete -SourcePath $script:sourceFile -SessionId $script:sessionId

            $backupResult.Success | Should -BeTrue
            $backupResult.BackupPath | Should -Not -BeNullOrEmpty
            Test-Path $backupResult.BackupPath | Should -BeTrue

            # Step 2: Delete the original file
            Remove-Item -Path $script:sourceFile -Force
            Test-Path $script:sourceFile | Should -BeFalse

            # Step 3: Restore from backup
            $restoreResult = Restore-FromBackup -SessionId $script:sessionId -Force

            $restoreResult.Success | Should -BeTrue
            $restoreResult.RestoredCount | Should -Be 1
            $restoreResult.FailedCount | Should -Be 0

            # Step 4: Verify restored file exists and content is identical
            Test-Path $script:sourceFile | Should -BeTrue
            $restoredContent = [System.IO.File]::ReadAllBytes($script:sourceFile)
            $restoredContent.Length | Should -Be $script:originalContent.Length
            [System.Convert]::ToBase64String($restoredContent) | Should -Be ([System.Convert]::ToBase64String($script:originalContent))
        }
    }

    Context "Restore recreates missing parent directories" {
        BeforeAll {
            $script:sessionId2 = "20260101-130000-def456"

            # Create a deeply nested file
            $script:nestedDir = Join-Path $TestDrive "Deep\Nested\Path\SubDir"
            New-Item -Path $script:nestedDir -ItemType Directory -Force | Out-Null
            $script:nestedFile = Join-Path $script:nestedDir "nested.txt"
            $script:nestedContent = [byte[]](10..50 | ForEach-Object { Get-Random -Minimum 0 -Maximum 256 })
            [System.IO.File]::WriteAllBytes($script:nestedFile, $script:nestedContent)
        }

        It "Restore recreates parent directories when they are missing" {
            # Step 1: Backup
            $backupResult = Backup-BeforeDelete -SourcePath $script:nestedFile -SessionId $script:sessionId2
            $backupResult.Success | Should -BeTrue

            # Step 2: Delete the entire parent directory tree
            $deepRoot = Join-Path $TestDrive "Deep"
            Remove-Item -Path $deepRoot -Recurse -Force
            Test-Path $script:nestedDir | Should -BeFalse

            # Step 3: Restore
            $restoreResult = Restore-FromBackup -SessionId $script:sessionId2 -Force
            $restoreResult.Success | Should -BeTrue
            $restoreResult.RestoredCount | Should -Be 1

            # Step 4: Verify parent directories were recreated
            Test-Path $script:nestedDir | Should -BeTrue
            Test-Path $script:nestedFile | Should -BeTrue

            # Step 5: Verify content
            $restoredContent = [System.IO.File]::ReadAllBytes($script:nestedFile)
            [System.Convert]::ToBase64String($restoredContent) | Should -Be ([System.Convert]::ToBase64String($script:nestedContent))
        }
    }

    Context "Batch restore by session with multiple files" {
        BeforeAll {
            $script:sessionId3 = "20260101-140000-ghi789"

            # Create multiple files in the same session
            $script:batchDir = Join-Path $TestDrive "BatchFiles"
            New-Item -Path $script:batchDir -ItemType Directory -Force | Out-Null

            $script:batchFiles = @()
            $script:batchContents = @()

            for ($i = 1; $i -le 3; $i++) {
                $filePath = Join-Path $script:batchDir "file$i.bin"
                $content = [byte[]](1..($i * 100) | ForEach-Object { Get-Random -Minimum 0 -Maximum 256 })
                [System.IO.File]::WriteAllBytes($filePath, $content)
                $script:batchFiles += $filePath
                $script:batchContents += , $content
            }
        }

        It "Batch restore restores all files from a session" {
            # Step 1: Backup all files in the same session
            foreach ($file in $script:batchFiles) {
                $result = Backup-BeforeDelete -SourcePath $file -SessionId $script:sessionId3
                $result.Success | Should -BeTrue
            }

            # Step 2: Delete all original files
            foreach ($file in $script:batchFiles) {
                Remove-Item -Path $file -Force
                Test-Path $file | Should -BeFalse
            }

            # Step 3: Batch restore by session
            $restoreResult = Restore-FromBackup -SessionId $script:sessionId3 -Force

            $restoreResult.Success | Should -BeTrue
            $restoreResult.RestoredCount | Should -Be 3
            $restoreResult.FailedCount | Should -Be 0

            # Step 4: Verify all files restored with correct content
            for ($i = 0; $i -lt $script:batchFiles.Count; $i++) {
                Test-Path $script:batchFiles[$i] | Should -BeTrue
                $restoredContent = [System.IO.File]::ReadAllBytes($script:batchFiles[$i])
                [System.Convert]::ToBase64String($restoredContent) | Should -Be ([System.Convert]::ToBase64String($script:batchContents[$i]))
            }
        }
    }
}

Describe "Integration: Staging Restore Cycle" {
    BeforeAll {
        # Override StagingRoot to use temp directory for isolation
        $script:OriginalStagingRoot = $Script:StagingRoot
        $Script:StagingRoot = Join-Path $TestDrive "StagingRoot"
        New-Item -Path $Script:StagingRoot -ItemType Directory -Force | Out-Null
    }

    AfterAll {
        $Script:StagingRoot = $script:OriginalStagingRoot
    }

    Context "Single file stage and restore" {
        BeforeAll {
            $script:stagingSessionId = "20260101-150000-stg001"

            # Create a temp file with known content
            $script:stageSrcDir = Join-Path $TestDrive "StageSrc"
            New-Item -Path $script:stageSrcDir -ItemType Directory -Force | Out-Null
            $script:stageFile = Join-Path $script:stageSrcDir "staged-file.dat"

            $script:stageContent = [byte[]](50..150 | ForEach-Object { Get-Random -Minimum 0 -Maximum 256 })
            [System.IO.File]::WriteAllBytes($script:stageFile, $script:stageContent)
        }

        It "Stage moves file away and restore returns it with identical content" {
            # Step 1: Stage the file (moves it to staging area)
            $stageResult = Move-ToStaging -SourcePath $script:stageFile -SessionId $script:stagingSessionId

            $stageResult.Success | Should -BeTrue
            $stageResult.StagedPath | Should -Not -BeNullOrEmpty

            # Step 2: Verify original is gone
            Test-Path $script:stageFile | Should -BeFalse

            # Step 3: Verify file exists in staging area
            Test-Path $stageResult.StagedPath | Should -BeTrue

            # Step 4: Restore from staging
            $restoreResult = Restore-FromStaging -OriginalPath $script:stageFile

            $restoreResult.Success | Should -BeTrue
            $restoreResult.RestoredPath | Should -Be $script:stageFile

            # Step 5: Verify restored file exists with identical content
            Test-Path $script:stageFile | Should -BeTrue
            $restoredContent = [System.IO.File]::ReadAllBytes($script:stageFile)
            $restoredContent.Length | Should -Be $script:stageContent.Length
            [System.Convert]::ToBase64String($restoredContent) | Should -Be ([System.Convert]::ToBase64String($script:stageContent))
        }

        It "Staged file is removed from staging area after restore" {
            # Re-create the file for a fresh test
            [System.IO.File]::WriteAllBytes($script:stageFile, $script:stageContent)

            $sessionId2 = "20260101-150001-stg002"

            # Stage it
            $stageResult = Move-ToStaging -SourcePath $script:stageFile -SessionId $sessionId2
            $stageResult.Success | Should -BeTrue
            $stagedPath = $stageResult.StagedPath

            # Restore it
            $restoreResult = Restore-FromStaging -OriginalPath $script:stageFile
            $restoreResult.Success | Should -BeTrue

            # Verify staged file no longer exists in staging area
            Test-Path $stagedPath | Should -BeFalse
        }

        It "File is removed from staging manifest after restore" {
            # Re-create the file for a fresh test
            [System.IO.File]::WriteAllBytes($script:stageFile, $script:stageContent)

            $sessionId3 = "20260101-150002-stg003"

            # Stage it
            $stageResult = Move-ToStaging -SourcePath $script:stageFile -SessionId $sessionId3
            $stageResult.Success | Should -BeTrue

            # Verify it appears in manifest before restore
            $manifestBefore = Get-StagingManifest
            $entryBefore = $manifestBefore.files | Where-Object { $_.originalPath -eq $script:stageFile }
            $entryBefore | Should -Not -BeNullOrEmpty

            # Restore it
            $restoreResult = Restore-FromStaging -OriginalPath $script:stageFile
            $restoreResult.Success | Should -BeTrue

            # Verify it is removed from manifest after restore
            $manifestAfter = Get-StagingManifest
            $entryAfter = $manifestAfter.files | Where-Object { $_.originalPath -eq $script:stageFile }
            $entryAfter | Should -BeNullOrEmpty
        }
    }

    Context "Staging restore recreates missing parent directories" {
        BeforeAll {
            $script:stageNestedDir = Join-Path $TestDrive "StageNested\Sub\Dir"
            New-Item -Path $script:stageNestedDir -ItemType Directory -Force | Out-Null
            $script:stageNestedFile = Join-Path $script:stageNestedDir "deep-file.bin"
            $script:stageNestedContent = [byte[]](1..64 | ForEach-Object { Get-Random -Minimum 0 -Maximum 256 })
            [System.IO.File]::WriteAllBytes($script:stageNestedFile, $script:stageNestedContent)
        }

        It "Restore from staging recreates parent directories" {
            $sessionId = "20260101-160000-stg004"

            # Stage the file
            $stageResult = Move-ToStaging -SourcePath $script:stageNestedFile -SessionId $sessionId
            $stageResult.Success | Should -BeTrue

            # Delete the entire parent tree
            $stageNestedRoot = Join-Path $TestDrive "StageNested"
            Remove-Item -Path $stageNestedRoot -Recurse -Force
            Test-Path $script:stageNestedDir | Should -BeFalse

            # Restore
            $restoreResult = Restore-FromStaging -OriginalPath $script:stageNestedFile
            $restoreResult.Success | Should -BeTrue

            # Verify directories recreated and content intact
            Test-Path $script:stageNestedDir | Should -BeTrue
            Test-Path $script:stageNestedFile | Should -BeTrue
            $restoredContent = [System.IO.File]::ReadAllBytes($script:stageNestedFile)
            [System.Convert]::ToBase64String($restoredContent) | Should -Be ([System.Convert]::ToBase64String($script:stageNestedContent))
        }
    }
}
