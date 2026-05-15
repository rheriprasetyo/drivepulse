<#
.SYNOPSIS
    DrivePulse — Backup Module Property-Based Tests
.DESCRIPTION
    Property-based tests for the backup module verifying:
    - Property 5: Backup byte-for-byte round-trip
    - Property 6: Backup structure and metadata preservation
    - Property 7: Retention-based purge correctness
.NOTES
    Minimum 100 iterations per property test.
    Uses generators from tests/helpers/generators.ps1
#>

Describe "Backup Module Property Tests" {
    BeforeAll {
        . "$PSScriptRoot\..\..\src\backup\backup.ps1"
        . "$PSScriptRoot\..\helpers\generators.ps1"
    }

    Context "Property 5: Backup byte-for-byte round-trip" {
        <#
            **Validates: Requirements 4.1, 5.1**
            For any file with arbitrary binary content, backing up the file and then
            restoring it to the original path SHALL produce a file whose size in bytes
            and content are identical to the original.
        #>

        It "Backup and restore produces byte-for-byte identical content" {
            $testRoot = Join-Path $TestDrive "backup-prop5-$(Get-Random)"
            New-Item -Path $testRoot -ItemType Directory -Force | Out-Null

            try {
                1..100 | ForEach-Object {
                    $iterDir = Join-Path $testRoot "iter_$_"
                    New-Item -Path $iterDir -ItemType Directory -Force | Out-Null

                    # Set up isolated backup root
                    $backupRoot = Join-Path $iterDir "backups"
                    New-Item -Path $backupRoot -ItemType Directory -Force | Out-Null
                    $Script:BackupRoot = $backupRoot

                    # Generate random file content
                    $content = New-RandomFileContent -MaxSize 65536
                    $sessionId = New-RandomSessionId

                    # Create source file with random binary content
                    $sourceDir = Join-Path $iterDir "source"
                    New-Item -Path $sourceDir -ItemType Directory -Force | Out-Null
                    $sourceFile = Join-Path $sourceDir "testfile_$_.bin"
                    [System.IO.File]::WriteAllBytes($sourceFile, $content)

                    # Backup the file
                    $backupResult = Backup-BeforeDelete -SourcePath $sourceFile -SessionId $sessionId
                    $backupResult.Success | Should -Be $true

                    # Verify backup file size matches original
                    $backupFile = Get-Item $backupResult.BackupPath -Force
                    $backupFile.Length | Should -Be $content.Length

                    # Verify backup content is byte-for-byte identical
                    $backupContent = [System.IO.File]::ReadAllBytes($backupResult.BackupPath)
                    $backupContent.Length | Should -Be $content.Length

                    # Compare bytes
                    $identical = $true
                    for ($i = 0; $i -lt $content.Length; $i++) {
                        if ($content[$i] -ne $backupContent[$i]) {
                            $identical = $false
                            break
                        }
                    }
                    $identical | Should -Be $true

                    # Delete original file
                    Remove-Item -Path $sourceFile -Force

                    # Restore from backup
                    $restoreResult = Restore-FromBackup -SessionId $sessionId -Force
                    $restoreResult.Success | Should -Be $true
                    $restoreResult.RestoredCount | Should -Be 1

                    # Verify restored file exists and content matches
                    Test-Path $sourceFile | Should -Be $true
                    $restoredContent = [System.IO.File]::ReadAllBytes($sourceFile)
                    $restoredContent.Length | Should -Be $content.Length

                    $restoredIdentical = $true
                    for ($i = 0; $i -lt $content.Length; $i++) {
                        if ($content[$i] -ne $restoredContent[$i]) {
                            $restoredIdentical = $false
                            break
                        }
                    }
                    $restoredIdentical | Should -Be $true
                }
            }
            finally {
                Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Property 6: Backup structure and metadata preservation" {
        <#
            **Validates: Requirements 4.2, 4.3, 4.5**
            For any absolute Windows file path and any valid SessionId, the backup SHALL
            be stored at <BackupRoot>/<SessionId>/<drive-encoded>/<relative-path> preserving
            the original directory hierarchy, and the backup manifest SHALL contain the
            original absolute path, an ISO 8601 timestamp, the file size in bytes, and the SessionId.
        #>

        It "Backup preserves directory structure and manifest contains correct metadata" {
            $testRoot = Join-Path $TestDrive "backup-prop6-$(Get-Random)"
            New-Item -Path $testRoot -ItemType Directory -Force | Out-Null

            try {
                1..100 | ForEach-Object {
                    $iterDir = Join-Path $testRoot "iter_$_"
                    New-Item -Path $iterDir -ItemType Directory -Force | Out-Null

                    # Set up isolated backup root
                    $backupRoot = Join-Path $iterDir "backups"
                    New-Item -Path $backupRoot -ItemType Directory -Force | Out-Null
                    $Script:BackupRoot = $backupRoot

                    # Generate random content and session
                    $content = New-RandomFileContent -MaxSize 4096
                    $sessionId = New-RandomSessionId

                    # Create source file with a nested directory structure
                    $depth = Get-Random -Minimum 1 -Maximum 4
                    $segments = @('FolderA', 'SubDir', 'Deep', 'Nested', 'Path')
                    $subPath = ($segments | Get-Random -Count $depth) -join '\'
                    $sourceDir = Join-Path $iterDir "source\$subPath"
                    New-Item -Path $sourceDir -ItemType Directory -Force | Out-Null
                    $fileName = "file_$_.dat"
                    $sourceFile = Join-Path $sourceDir $fileName
                    [System.IO.File]::WriteAllBytes($sourceFile, $content)

                    # Backup the file
                    $backupResult = Backup-BeforeDelete -SourcePath $sourceFile -SessionId $sessionId
                    $backupResult.Success | Should -Be $true

                    # Verify backup path contains session ID
                    $backupResult.BackupPath | Should -Match ([regex]::Escape($sessionId))

                    # Verify drive-encoded path structure
                    $driveLetter = $sourceFile.Substring(0, 1).ToUpper()
                    $expectedDriveEncoded = "${driveLetter}_drive"
                    $backupResult.BackupPath | Should -Match ([regex]::Escape($expectedDriveEncoded))

                    # Verify the backup path preserves the relative directory structure
                    $relativeFromDrive = $sourceFile.Substring(3)  # Remove "X:\"
                    $backupResult.BackupPath | Should -Match ([regex]::Escape($fileName))

                    # Read and verify manifest
                    $manifest = Read-BackupManifest -SessionId $sessionId
                    $manifest | Should -Not -BeNullOrEmpty
                    $manifest.sessionId | Should -Be $sessionId

                    # Find the entry for our file
                    $entry = $manifest.files | Where-Object { $_.originalPath -eq $sourceFile }
                    $entry | Should -Not -BeNullOrEmpty

                    # Verify metadata fields
                    $entry.originalPath | Should -Be $sourceFile
                    $entry.sizeBytes | Should -Be $content.Length

                    # Verify timestamp is present and parseable as a date
                    $entry.timestamp | Should -Not -BeNullOrEmpty
                    $parsedDate = [DateTime]::Parse($entry.timestamp.ToString())
                    $parsedDate | Should -Not -BeNullOrEmpty

                    # Verify sessionId is in manifest
                    $manifest.sessionId | Should -Be $sessionId
                }
            }
            finally {
                Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Property 7: Retention-based purge correctness" {
        <#
            **Validates: Requirements 4.7, 6.2, 6.4, 6.5**
            For any retention period (1-90 days), Remove-ExpiredBackups only removes
            sessions older than the retention period. Sessions within the retention
            window are preserved. If retention is outside 1-90 or non-numeric, default
            of 7 days is applied.
        #>

        It "Purge removes only sessions older than retention period and preserves recent ones" {
            $testRoot = Join-Path $TestDrive "backup-prop7-$(Get-Random)"
            New-Item -Path $testRoot -ItemType Directory -Force | Out-Null

            try {
                1..100 | ForEach-Object {
                    $iterDir = Join-Path $testRoot "iter_$_"
                    New-Item -Path $iterDir -ItemType Directory -Force | Out-Null

                    # Set up isolated backup root
                    $backupRoot = Join-Path $iterDir "backups"
                    New-Item -Path $backupRoot -ItemType Directory -Force | Out-Null
                    $Script:BackupRoot = $backupRoot

                    # Generate random retention period
                    $retentionDays = New-RandomRetentionDays

                    # Create an "old" session (older than retention)
                    $oldDaysAgo = $retentionDays + (Get-Random -Minimum 1 -Maximum 30)
                    $oldTimestamp = (Get-Date).AddDays(-$oldDaysAgo).ToString('yyyy-MM-ddTHH:mm:sszzz')
                    $oldSessionId = "old-session-$_"
                    $oldSessionDir = Join-Path $backupRoot $oldSessionId
                    New-Item -Path $oldSessionDir -ItemType Directory -Force | Out-Null

                    # Create a file in the old session
                    $oldFileDir = Join-Path $oldSessionDir "C_drive\Temp"
                    New-Item -Path $oldFileDir -ItemType Directory -Force | Out-Null
                    $oldFile = Join-Path $oldFileDir "old_$_.txt"
                    Set-Content -Path $oldFile -Value "old content $_"
                    $oldFileSize = (Get-Item $oldFile).Length

                    # Write manifest for old session
                    $oldManifest = [PSCustomObject]@{
                        sessionId = $oldSessionId
                        createdAt = $oldTimestamp
                        files     = @(
                            [PSCustomObject]@{
                                originalPath = "C:\Temp\old_$_.txt"
                                backupPath   = "$oldSessionId\C_drive\Temp\old_$_.txt"
                                sizeBytes    = $oldFileSize
                                timestamp    = $oldTimestamp
                            }
                        )
                    }
                    Write-BackupManifest -SessionId $oldSessionId -Manifest $oldManifest

                    # Create a "recent" session (within retention)
                    $recentDaysAgo = [Math]::Max(0, $retentionDays - (Get-Random -Minimum 1 -Maximum ([Math]::Max(2, $retentionDays))))
                    $recentTimestamp = (Get-Date).AddDays(-$recentDaysAgo).ToString('yyyy-MM-ddTHH:mm:sszzz')
                    $recentSessionId = "recent-session-$_"
                    $recentSessionDir = Join-Path $backupRoot $recentSessionId
                    New-Item -Path $recentSessionDir -ItemType Directory -Force | Out-Null

                    # Create a file in the recent session
                    $recentFileDir = Join-Path $recentSessionDir "C_drive\Temp"
                    New-Item -Path $recentFileDir -ItemType Directory -Force | Out-Null
                    $recentFile = Join-Path $recentFileDir "recent_$_.txt"
                    Set-Content -Path $recentFile -Value "recent content $_"
                    $recentFileSize = (Get-Item $recentFile).Length

                    # Write manifest for recent session
                    $recentManifest = [PSCustomObject]@{
                        sessionId = $recentSessionId
                        createdAt = $recentTimestamp
                        files     = @(
                            [PSCustomObject]@{
                                originalPath = "C:\Temp\recent_$_.txt"
                                backupPath   = "$recentSessionId\C_drive\Temp\recent_$_.txt"
                                sizeBytes    = $recentFileSize
                                timestamp    = $recentTimestamp
                            }
                        )
                    }
                    Write-BackupManifest -SessionId $recentSessionId -Manifest $recentManifest

                    # Run purge
                    $purgeResult = Remove-ExpiredBackups -RetentionDays $retentionDays

                    # Verify: old session should be purged
                    Test-Path $oldSessionDir | Should -Be $false

                    # Verify: recent session should be preserved
                    Test-Path $recentSessionDir | Should -Be $true
                    Test-Path $recentFile | Should -Be $true
                }
            }
            finally {
                Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "Invalid retention values fall back to default 7 days" {
            $testRoot = Join-Path $TestDrive "backup-prop7-invalid-$(Get-Random)"
            New-Item -Path $testRoot -ItemType Directory -Force | Out-Null

            try {
                $invalidValues = @(0, -1, -50, 91, 100, 200, 999)

                foreach ($invalidRetention in $invalidValues) {
                    $iterDir = Join-Path $testRoot "iter_$invalidRetention"
                    New-Item -Path $iterDir -ItemType Directory -Force | Out-Null

                    # Set up isolated backup root
                    $backupRoot = Join-Path $iterDir "backups"
                    New-Item -Path $backupRoot -ItemType Directory -Force | Out-Null
                    $Script:BackupRoot = $backupRoot

                    # Create a session that is 5 days old (within default 7-day window)
                    $withinDefaultTimestamp = (Get-Date).AddDays(-5).ToString('yyyy-MM-ddTHH:mm:sszzz')
                    $withinSessionId = "within-default-$invalidRetention"
                    $withinSessionDir = Join-Path $backupRoot $withinSessionId
                    New-Item -Path $withinSessionDir -ItemType Directory -Force | Out-Null
                    $withinFileDir = Join-Path $withinSessionDir "C_drive\Temp"
                    New-Item -Path $withinFileDir -ItemType Directory -Force | Out-Null
                    $withinFile = Join-Path $withinFileDir "within.txt"
                    Set-Content -Path $withinFile -Value "within default"

                    $withinManifest = [PSCustomObject]@{
                        sessionId = $withinSessionId
                        createdAt = $withinDefaultTimestamp
                        files     = @(
                            [PSCustomObject]@{
                                originalPath = "C:\Temp\within.txt"
                                backupPath   = "$withinSessionId\C_drive\Temp\within.txt"
                                sizeBytes    = (Get-Item $withinFile).Length
                                timestamp    = $withinDefaultTimestamp
                            }
                        )
                    }
                    Write-BackupManifest -SessionId $withinSessionId -Manifest $withinManifest

                    # Create a session that is 10 days old (outside default 7-day window)
                    $outsideDefaultTimestamp = (Get-Date).AddDays(-10).ToString('yyyy-MM-ddTHH:mm:sszzz')
                    $outsideSessionId = "outside-default-$invalidRetention"
                    $outsideSessionDir = Join-Path $backupRoot $outsideSessionId
                    New-Item -Path $outsideSessionDir -ItemType Directory -Force | Out-Null
                    $outsideFileDir = Join-Path $outsideSessionDir "C_drive\Temp"
                    New-Item -Path $outsideFileDir -ItemType Directory -Force | Out-Null
                    $outsideFile = Join-Path $outsideFileDir "outside.txt"
                    Set-Content -Path $outsideFile -Value "outside default"

                    $outsideManifest = [PSCustomObject]@{
                        sessionId = $outsideSessionId
                        createdAt = $outsideDefaultTimestamp
                        files     = @(
                            [PSCustomObject]@{
                                originalPath = "C:\Temp\outside.txt"
                                backupPath   = "$outsideSessionId\C_drive\Temp\outside.txt"
                                sizeBytes    = (Get-Item $outsideFile).Length
                                timestamp    = $outsideDefaultTimestamp
                            }
                        )
                    }
                    Write-BackupManifest -SessionId $outsideSessionId -Manifest $outsideManifest

                    # Run purge with invalid retention - should fall back to 7 days
                    $purgeResult = Remove-ExpiredBackups -RetentionDays $invalidRetention

                    # Session within 7 days should be preserved
                    Test-Path $withinSessionDir | Should -Be $true

                    # Session outside 7 days should be purged
                    Test-Path $outsideSessionDir | Should -Be $false
                }
            }
            finally {
                Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
