<#
.SYNOPSIS
    DrivePulse — Backup Module Unit Tests
.DESCRIPTION
    Unit tests for the backup module (src/backup/backup.ps1):
    - Skip deletion on backup failure (Req 4.4)
    - Insufficient space notification (Req 4.6)
    - Restore recreates missing parent directories (Req 5.1)
    - Batch restore by session (Req 5.2)
    - Restore summary display (Req 5.3)
    - Prompt on file conflict during restore (Req 5.4)
    - Continue on restore failure (Req 5.5)
    - Error when backup purged (Req 5.6)
    - Invalid retention falls back to default 7 (Req 6.5)
    - Skip and log on purge file access error (Req 6.6)
.NOTES
    Requirements: 4.4, 4.6, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 6.5, 6.6
#>

BeforeAll {
    . "$PSScriptRoot\..\..\src\backup\backup.ps1"
}

Describe "Backup-BeforeDelete: Skip deletion on backup failure (Req 4.4)" {
    BeforeEach {
        $testRoot = Join-Path $TestDrive 'backup-root'
        New-Item -Path $testRoot -ItemType Directory -Force | Out-Null
        $Script:BackupRoot = $testRoot
    }

    It "Returns Success=false when source file does not exist" {
        $nonExistentPath = Join-Path $TestDrive 'nonexistent-file.txt'
        $sessionId = '20260515-100000-abc123'

        $result = Backup-BeforeDelete -SourcePath $nonExistentPath -SessionId $sessionId

        $result.Success | Should -Be $false
        $result.BackupPath | Should -BeNullOrEmpty
        $result.Error | Should -Match 'tidak ditemukan'
    }

    It "Returns Success=false with error message so caller can skip deletion" {
        $nonExistentPath = 'C:\NoSuchFolder\NoSuchFile.dat'
        $sessionId = '20260515-100000-abc123'

        $result = Backup-BeforeDelete -SourcePath $nonExistentPath -SessionId $sessionId

        $result.Success | Should -Be $false
        $result.Error | Should -Not -BeNullOrEmpty
    }
}

Describe "Test-BackupSpace: Insufficient space notification (Req 4.6)" {
    BeforeEach {
        $testRoot = Join-Path $TestDrive 'backup-root'
        New-Item -Path $testRoot -ItemType Directory -Force | Out-Null
        $Script:BackupRoot = $testRoot
    }

    It "Returns Sufficient=false when RequiredBytes exceeds available space" {
        # Mock Get-PSDrive to simulate low disk space
        Mock Get-PSDrive {
            return [PSCustomObject]@{
                Free = [long]1000
            }
        }

        $result = Test-BackupSpace -RequiredBytes 999999999999

        $result.Sufficient | Should -Be $false
        $result.RequiredBytes | Should -Be 999999999999
    }

    It "Returns Sufficient=true when RequiredBytes is within available space" {
        Mock Get-PSDrive {
            return [PSCustomObject]@{
                Free = [long]10000000000
            }
        }

        $result = Test-BackupSpace -RequiredBytes 1000

        $result.Sufficient | Should -Be $true
        $result.RequiredBytes | Should -Be 1000
        $result.AvailableBytes | Should -Be 10000000000
    }
}

Describe "Restore-FromBackup: Recreates missing parent directories (Req 5.1)" {
    BeforeEach {
        $testRoot = Join-Path $TestDrive 'backup-root'
        New-Item -Path $testRoot -ItemType Directory -Force | Out-Null
        $Script:BackupRoot = $testRoot

        # Create a backup session with a file
        $sessionId = '20260515-100000-abc123'
        $sessionDir = Join-Path $testRoot $sessionId
        New-Item -Path $sessionDir -ItemType Directory -Force | Out-Null

        # Create a backup file in drive-encoded structure
        $backupFileDir = Join-Path $sessionDir 'C_drive\Users\TestUser\DeepFolder\SubFolder'
        New-Item -Path $backupFileDir -ItemType Directory -Force | Out-Null
        $backupFilePath = Join-Path $backupFileDir 'testfile.txt'
        $contentBytes = [System.Text.Encoding]::UTF8.GetBytes('test content')
        [System.IO.File]::WriteAllBytes($backupFilePath, $contentBytes)

        # Create manifest
        $originalPath = Join-Path $TestDrive 'restore-target\DeepFolder\SubFolder\testfile.txt'
        $manifest = [PSCustomObject]@{
            sessionId = $sessionId
            createdAt = '2026-05-15T10:00:00+07:00'
            files     = @(
                [PSCustomObject]@{
                    originalPath = $originalPath
                    backupPath   = "$sessionId\C_drive\Users\TestUser\DeepFolder\SubFolder\testfile.txt"
                    sizeBytes    = $contentBytes.Length
                    timestamp    = '2026-05-15T10:00:01+07:00'
                }
            )
        }
        $manifestPath = Join-Path $sessionDir 'backup-manifest.json'
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -Path $manifestPath

        $script:testOriginalPath = $originalPath
        $script:testSessionId = $sessionId
    }

    It "Creates parent directories that do not exist during restore" {
        # Ensure the target parent directory does NOT exist
        $parentDir = Split-Path -Parent $script:testOriginalPath
        if (Test-Path $parentDir) { Remove-Item -Path $parentDir -Recurse -Force }

        $result = Restore-FromBackup -SessionId $script:testSessionId -Force

        $parentDir | Should -Exist
        $result.RestoredCount | Should -Be 1
    }
}

Describe "Restore-FromBackup: Batch restore by session (Req 5.2)" {
    BeforeEach {
        $testRoot = Join-Path $TestDrive 'backup-root'
        New-Item -Path $testRoot -ItemType Directory -Force | Out-Null
        $Script:BackupRoot = $testRoot

        $sessionId = '20260515-110000-def456'
        $sessionDir = Join-Path $testRoot $sessionId
        New-Item -Path $sessionDir -ItemType Directory -Force | Out-Null

        # Create two backup files using byte arrays for exact size control
        $backupDir1 = Join-Path $sessionDir 'C_drive\Users\Test'
        New-Item -Path $backupDir1 -ItemType Directory -Force | Out-Null
        $bytes1 = [System.Text.Encoding]::UTF8.GetBytes('content1')
        [System.IO.File]::WriteAllBytes((Join-Path $backupDir1 'file1.txt'), $bytes1)
        $bytes2 = [System.Text.Encoding]::UTF8.GetBytes('content2')
        [System.IO.File]::WriteAllBytes((Join-Path $backupDir1 'file2.txt'), $bytes2)

        $restoreDir = Join-Path $TestDrive 'restore-batch'

        $manifest = [PSCustomObject]@{
            sessionId = $sessionId
            createdAt = '2026-05-15T11:00:00+07:00'
            files     = @(
                [PSCustomObject]@{
                    originalPath = (Join-Path $restoreDir 'file1.txt')
                    backupPath   = "$sessionId\C_drive\Users\Test\file1.txt"
                    sizeBytes    = $bytes1.Length
                    timestamp    = '2026-05-15T11:00:01+07:00'
                },
                [PSCustomObject]@{
                    originalPath = (Join-Path $restoreDir 'file2.txt')
                    backupPath   = "$sessionId\C_drive\Users\Test\file2.txt"
                    sizeBytes    = $bytes2.Length
                    timestamp    = '2026-05-15T11:00:02+07:00'
                }
            )
        }
        $manifestPath = Join-Path $sessionDir 'backup-manifest.json'
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -Path $manifestPath

        $script:testSessionId = $sessionId
        $script:testRestoreDir = $restoreDir
    }

    It "Restores all files from a session when -SessionId is provided" {
        $result = Restore-FromBackup -SessionId $script:testSessionId -Force

        $result.RestoredCount | Should -Be 2
        (Join-Path $script:testRestoreDir 'file1.txt') | Should -Exist
        (Join-Path $script:testRestoreDir 'file2.txt') | Should -Exist
    }
}

Describe "Restore-FromBackup: Restore summary display (Req 5.3)" {
    BeforeEach {
        $testRoot = Join-Path $TestDrive 'backup-root'
        New-Item -Path $testRoot -ItemType Directory -Force | Out-Null
        $Script:BackupRoot = $testRoot

        $sessionId = '20260515-120000-ghi789'
        $sessionDir = Join-Path $testRoot $sessionId
        New-Item -Path $sessionDir -ItemType Directory -Force | Out-Null

        $backupDir = Join-Path $sessionDir 'C_drive\Users\Test'
        New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
        $goodBytes = [System.Text.Encoding]::UTF8.GetBytes('good content here')
        [System.IO.File]::WriteAllBytes((Join-Path $backupDir 'good.txt'), $goodBytes)

        $restoreDir = Join-Path $TestDrive 'restore-summary'

        $manifest = [PSCustomObject]@{
            sessionId = $sessionId
            createdAt = '2026-05-15T12:00:00+07:00'
            files     = @(
                [PSCustomObject]@{
                    originalPath = (Join-Path $restoreDir 'good.txt')
                    backupPath   = "$sessionId\C_drive\Users\Test\good.txt"
                    sizeBytes    = $goodBytes.Length
                    timestamp    = '2026-05-15T12:00:01+07:00'
                },
                [PSCustomObject]@{
                    originalPath = (Join-Path $restoreDir 'missing.txt')
                    backupPath   = "$sessionId\C_drive\Users\Test\missing.txt"
                    sizeBytes    = 10
                    timestamp    = '2026-05-15T12:00:02+07:00'
                }
            )
        }
        $manifestPath = Join-Path $sessionDir 'backup-manifest.json'
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -Path $manifestPath

        $script:testSessionId = $sessionId
        $script:testGoodSize = $goodBytes.Length
    }

    It "Returns RestoredCount, FailedCount, and TotalSize in result" {
        $result = Restore-FromBackup -SessionId $script:testSessionId -Force

        $result.RestoredCount | Should -Be 1
        $result.FailedCount | Should -Be 1
        $result.TotalSize | Should -BeOfType [long]
        $result.TotalSize | Should -Be $script:testGoodSize
        $result.Errors | Should -Not -BeNullOrEmpty
    }
}

Describe "Restore-FromBackup: Prompt on file conflict (Req 5.4)" {
    BeforeEach {
        $testRoot = Join-Path $TestDrive 'backup-root'
        New-Item -Path $testRoot -ItemType Directory -Force | Out-Null
        $Script:BackupRoot = $testRoot

        $sessionId = '20260515-130000-jkl012'
        $sessionDir = Join-Path $testRoot $sessionId
        New-Item -Path $sessionDir -ItemType Directory -Force | Out-Null

        $backupDir = Join-Path $sessionDir 'C_drive\Users\Test'
        New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
        $backupBytes = [System.Text.Encoding]::UTF8.GetBytes('backup version')
        [System.IO.File]::WriteAllBytes((Join-Path $backupDir 'conflict.txt'), $backupBytes)

        $restoreDir = Join-Path $TestDrive 'restore-conflict'
        New-Item -Path $restoreDir -ItemType Directory -Force | Out-Null
        # Create existing file at target location
        Set-Content -Path (Join-Path $restoreDir 'conflict.txt') -Value 'existing version'

        $manifest = [PSCustomObject]@{
            sessionId = $sessionId
            createdAt = '2026-05-15T13:00:00+07:00'
            files     = @(
                [PSCustomObject]@{
                    originalPath = (Join-Path $restoreDir 'conflict.txt')
                    backupPath   = "$sessionId\C_drive\Users\Test\conflict.txt"
                    sizeBytes    = $backupBytes.Length
                    timestamp    = '2026-05-15T13:00:01+07:00'
                }
            )
        }
        $manifestPath = Join-Path $sessionDir 'backup-manifest.json'
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -Path $manifestPath

        $script:testSessionId = $sessionId
        $script:testRestoreDir = $restoreDir
    }

    It "Fails restore without -Force when target file already exists" {
        $result = Restore-FromBackup -SessionId $script:testSessionId

        $result.FailedCount | Should -Be 1
        $result.RestoredCount | Should -Be 0
        $result.Errors[0] | Should -Match 'sudah ada'
        # Original file should remain unchanged
        Get-Content (Join-Path $script:testRestoreDir 'conflict.txt') | Should -Be 'existing version'
    }

    It "Overwrites existing file when -Force is specified" {
        $result = Restore-FromBackup -SessionId $script:testSessionId -Force

        $result.RestoredCount | Should -Be 1
        $result.FailedCount | Should -Be 0
    }
}

Describe "Restore-FromBackup: Continue on restore failure (Req 5.5)" {
    BeforeEach {
        $testRoot = Join-Path $TestDrive 'backup-root'
        New-Item -Path $testRoot -ItemType Directory -Force | Out-Null
        $Script:BackupRoot = $testRoot

        $sessionId = '20260515-140000-mno345'
        $sessionDir = Join-Path $testRoot $sessionId
        New-Item -Path $sessionDir -ItemType Directory -Force | Out-Null

        $backupDir = Join-Path $sessionDir 'C_drive\Users\Test'
        New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
        # Only create one of the two backup files (second is "missing"/purged)
        $existsBytes = [System.Text.Encoding]::UTF8.GetBytes('I exist')
        [System.IO.File]::WriteAllBytes((Join-Path $backupDir 'exists.txt'), $existsBytes)

        $restoreDir = Join-Path $TestDrive 'restore-continue'

        $manifest = [PSCustomObject]@{
            sessionId = $sessionId
            createdAt = '2026-05-15T14:00:00+07:00'
            files     = @(
                [PSCustomObject]@{
                    originalPath = (Join-Path $restoreDir 'missing-backup.txt')
                    backupPath   = "$sessionId\C_drive\Users\Test\missing-backup.txt"
                    sizeBytes    = 5
                    timestamp    = '2026-05-15T14:00:01+07:00'
                },
                [PSCustomObject]@{
                    originalPath = (Join-Path $restoreDir 'exists.txt')
                    backupPath   = "$sessionId\C_drive\Users\Test\exists.txt"
                    sizeBytes    = $existsBytes.Length
                    timestamp    = '2026-05-15T14:00:02+07:00'
                }
            )
        }
        $manifestPath = Join-Path $sessionDir 'backup-manifest.json'
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -Path $manifestPath

        $script:testSessionId = $sessionId
        $script:testRestoreDir = $restoreDir
    }

    It "Continues restoring remaining files when one file fails" {
        $result = Restore-FromBackup -SessionId $script:testSessionId -Force

        $result.RestoredCount | Should -Be 1
        $result.FailedCount | Should -Be 1
        (Join-Path $script:testRestoreDir 'exists.txt') | Should -Exist
    }
}

Describe "Restore-FromBackup: Error when backup purged (Req 5.6)" {
    BeforeEach {
        $testRoot = Join-Path $TestDrive 'backup-root'
        New-Item -Path $testRoot -ItemType Directory -Force | Out-Null
        $Script:BackupRoot = $testRoot
    }

    It "Returns error when session manifest does not exist (backup purged)" {
        $result = Restore-FromBackup -SessionId 'purged-session-id'

        $result.Success | Should -Be $false
        $result.RestoredCount | Should -Be 0
        $result.Errors[0] | Should -Match 'tidak ditemukan|sudah dihapus'
    }

    It "Reports error for individual file whose backup file has been purged" {
        # Create session with manifest but no actual backup file
        $sessionId = '20260515-150000-pqr678'
        $sessionDir = Join-Path $testRoot $sessionId
        New-Item -Path $sessionDir -ItemType Directory -Force | Out-Null

        $restoreDir = Join-Path $TestDrive 'restore-purged'

        $manifest = [PSCustomObject]@{
            sessionId = $sessionId
            createdAt = '2026-05-15T15:00:00+07:00'
            files     = @(
                [PSCustomObject]@{
                    originalPath = (Join-Path $restoreDir 'purged-file.txt')
                    backupPath   = "$sessionId\C_drive\Users\Test\purged-file.txt"
                    sizeBytes    = 100
                    timestamp    = '2026-05-15T15:00:01+07:00'
                }
            )
        }
        $manifestPath = Join-Path $sessionDir 'backup-manifest.json'
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -Path $manifestPath

        $result = Restore-FromBackup -SessionId $sessionId -Force

        $result.FailedCount | Should -Be 1
        $result.Errors[0] | Should -Match 'dihapus.*retensi'
    }
}

Describe "Get-ValidRetentionDays: Invalid retention falls back to default 7 (Req 6.5)" {
    It "Returns 7 for null input" {
        Get-ValidRetentionDays -RetentionDays $null | Should -Be 7
    }

    It "Returns 7 for zero" {
        Get-ValidRetentionDays -RetentionDays 0 | Should -Be 7
    }

    It "Returns 7 for negative value" {
        Get-ValidRetentionDays -RetentionDays -5 | Should -Be 7
    }

    It "Returns 7 for value above 90" {
        Get-ValidRetentionDays -RetentionDays 100 | Should -Be 7
    }

    It "Returns 7 for non-numeric string" {
        Get-ValidRetentionDays -RetentionDays 'abc' | Should -Be 7
    }

    It "Returns valid value within range 1-90" {
        Get-ValidRetentionDays -RetentionDays 30 | Should -Be 30
    }

    It "Returns 1 for minimum valid value" {
        Get-ValidRetentionDays -RetentionDays 1 | Should -Be 1
    }

    It "Returns 90 for maximum valid value" {
        Get-ValidRetentionDays -RetentionDays 90 | Should -Be 90
    }
}

Describe "Remove-ExpiredBackups: Skip and log on purge file access error (Req 6.6)" {
    BeforeEach {
        $testRoot = Join-Path $TestDrive 'backup-root'
        New-Item -Path $testRoot -ItemType Directory -Force | Out-Null
        $Script:BackupRoot = $testRoot

        # Create an expired session (old timestamp)
        $sessionId = '20240101-100000-old111'
        $sessionDir = Join-Path $testRoot $sessionId
        New-Item -Path $sessionDir -ItemType Directory -Force | Out-Null

        $backupDir = Join-Path $sessionDir 'C_drive\Users\Test'
        New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
        $normalBytes = [System.Text.Encoding]::UTF8.GetBytes('normal content')
        [System.IO.File]::WriteAllBytes((Join-Path $backupDir 'normal.txt'), $normalBytes)

        $manifest = [PSCustomObject]@{
            sessionId = $sessionId
            createdAt = '2024-01-01T10:00:00+07:00'
            files     = @(
                [PSCustomObject]@{
                    originalPath = 'C:\Users\Test\normal.txt'
                    backupPath   = "$sessionId\C_drive\Users\Test\normal.txt"
                    sizeBytes    = $normalBytes.Length
                    timestamp    = '2024-01-01T10:00:02+07:00'
                }
            )
        }
        $manifestPath = Join-Path $sessionDir 'backup-manifest.json'
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -Path $manifestPath

        $script:testSessionId = $sessionId
    }

    It "Purges expired backups and returns purge count" {
        Mock Write-AuditEntry {}

        $result = Remove-ExpiredBackups -RetentionDays 7

        $result.PurgedCount | Should -BeGreaterOrEqual 1
        $result.PurgedSize | Should -BeGreaterThan 0
    }

    It "Reports errors array when files cannot be deleted" {
        # Lock a file by opening it with exclusive access to simulate access error
        $sessionId2 = '20230601-100000-err222'
        $sessionDir2 = Join-Path $testRoot $sessionId2
        New-Item -Path $sessionDir2 -ItemType Directory -Force | Out-Null

        $backupDir2 = Join-Path $sessionDir2 'C_drive\Users\Test'
        New-Item -Path $backupDir2 -ItemType Directory -Force | Out-Null
        $lockedFilePath = Join-Path $backupDir2 'locked-file.txt'
        $lockedBytes = [System.Text.Encoding]::UTF8.GetBytes('locked content')
        [System.IO.File]::WriteAllBytes($lockedFilePath, $lockedBytes)

        $manifest2 = [PSCustomObject]@{
            sessionId = $sessionId2
            createdAt = '2023-06-01T10:00:00+07:00'
            files     = @(
                [PSCustomObject]@{
                    originalPath = 'C:\Users\Test\locked-file.txt'
                    backupPath   = "$sessionId2\C_drive\Users\Test\locked-file.txt"
                    sizeBytes    = $lockedBytes.Length
                    timestamp    = '2023-06-01T10:00:01+07:00'
                }
            )
        }
        $manifestPath2 = Join-Path $sessionDir2 'backup-manifest.json'
        $manifest2 | ConvertTo-Json -Depth 10 | Set-Content -Path $manifestPath2

        Mock Write-AuditEntry {}

        # Lock the file with exclusive access
        $fileStream = [System.IO.File]::Open($lockedFilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        try {
            $result = Remove-ExpiredBackups -RetentionDays 7

            # The function should complete without throwing
            $result | Should -Not -BeNullOrEmpty
            # Errors array should contain the access error
            $result.Errors.Count | Should -BeGreaterOrEqual 1
            $result.Errors[0] | Should -Match 'Gagal'
        }
        finally {
            $fileStream.Close()
            $fileStream.Dispose()
        }
    }
}
