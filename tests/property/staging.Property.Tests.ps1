<#
.SYNOPSIS
    DrivePulse — Staging Module Property-Based Tests
.DESCRIPTION
    Property-based tests for the staging module verifying:
    - Property 11: Staging moves files preserving structure
    - Property 12: Staged files list sort order
    - Property 13: Staging restore round-trip
.NOTES
    Minimum 100 iterations per property test.
    Uses generators from tests/helpers/generators.ps1
#>

Describe "Staging Module Property Tests" {
    BeforeAll {
        . "$PSScriptRoot\..\helpers\generators.ps1"
        . "$PSScriptRoot\..\..\src\staging\staging.ps1"
    }

    Context "Property 11: Staging moves files preserving structure" {
        <#
            **Validates: Requirements 8.1, 8.2, 8.3**
            For any file, Move-ToStaging moves it to the staging area with
            drive-encoded path structure. The original file no longer exists.
            The staged file has the same content.
        #>

        BeforeAll {
            $Script:TestStagingRoot = Join-Path $env:TEMP "drivepulse-staging-prop11-$(Get-Random)"
        }

        AfterAll {
            Remove-Item $Script:TestStagingRoot -Recurse -Force -ErrorAction SilentlyContinue
        }

        It "Move-ToStaging moves file to staging area preserving structure and content" {
            1..100 | ForEach-Object {
                # Setup isolated staging root per iteration
                $iterRoot = Join-Path $Script:TestStagingRoot "iter_$_"
                New-Item -Path $iterRoot -ItemType Directory -Force | Out-Null
                $Script:StagingRoot = $iterRoot

                # Generate random file data
                $stagedFile = New-RandomStagedFile

                # Create a real temp file with the random content
                $tempDir = Join-Path $iterRoot "source"
                $sourceFile = Join-Path $tempDir "testfile_$_.dat"
                New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
                [System.IO.File]::WriteAllBytes($sourceFile, $stagedFile.Content)

                # Act: Move to staging
                $result = Move-ToStaging -SourcePath $sourceFile -SessionId $stagedFile.SessionId

                # Assert: Operation succeeded
                $result.Success | Should -Be $true

                # Assert: Original file no longer exists
                Test-Path $sourceFile | Should -Be $false

                # Assert: Staged file exists at drive-encoded path
                $result.StagedPath | Should -Not -BeNullOrEmpty
                Test-Path $result.StagedPath | Should -Be $true

                # Assert: Content is identical
                $stagedContent = [System.IO.File]::ReadAllBytes($result.StagedPath)
                $stagedContent.Length | Should -Be $stagedFile.Content.Length
                [System.Convert]::ToBase64String($stagedContent) | Should -Be ([System.Convert]::ToBase64String($stagedFile.Content))

                # Assert: Path structure is preserved (drive-encoded)
                $driveLetter = $sourceFile.Substring(0, 1)
                $result.StagedPath | Should -BeLike "*${driveLetter}_drive*"

                # Assert: Manifest contains metadata
                $manifest = Get-StagingManifest
                $entry = $manifest.files | Where-Object { $_.originalPath -eq $sourceFile }
                $entry | Should -Not -BeNullOrEmpty
                $entry.originalPath | Should -Be $sourceFile
                $entry.sizeBytes | Should -Be $stagedFile.Content.Length
                $entry.stagingTimestamp | Should -Not -BeNullOrEmpty
                $entry.sessionId | Should -Be $stagedFile.SessionId
            }
        }
    }

    Context "Property 12: Staged files list sort order" {
        <#
            **Validates: Requirements 8.4**
            Get-StagedFiles always returns entries sorted by stagingTimestamp
            descending (newest first). For any N files staged at different times,
            the order is always newest-to-oldest.
        #>

        BeforeAll {
            $Script:TestStagingRoot = Join-Path $env:TEMP "drivepulse-staging-prop12-$(Get-Random)"
        }

        AfterAll {
            Remove-Item $Script:TestStagingRoot -Recurse -Force -ErrorAction SilentlyContinue
        }

        It "Get-StagedFiles returns entries sorted by stagingTimestamp descending" {
            1..100 | ForEach-Object {
                # Setup isolated staging root per iteration
                $iterRoot = Join-Path $Script:TestStagingRoot "iter_$_"
                New-Item -Path $iterRoot -ItemType Directory -Force | Out-Null
                $Script:StagingRoot = $iterRoot

                # Generate N random files (between 2 and 6)
                $fileCount = Get-Random -Minimum 2 -Maximum 7
                $timestamps = @()

                for ($i = 0; $i -lt $fileCount; $i++) {
                    # Create source file
                    $sourceDir = Join-Path $iterRoot "source_$i"
                    New-Item -Path $sourceDir -ItemType Directory -Force | Out-Null
                    $sourceFile = Join-Path $sourceDir "file_$i.dat"
                    $content = New-RandomFileContent -MinSize 10 -MaxSize 256
                    [System.IO.File]::WriteAllBytes($sourceFile, $content)

                    $sessionId = New-RandomSessionId

                    # Move to staging
                    $result = Move-ToStaging -SourcePath $sourceFile -SessionId $sessionId
                    $result.Success | Should -Be $true

                    # Introduce a small delay or manually set different timestamps
                    # To ensure distinct timestamps, we'll modify the manifest directly
                    Start-Sleep -Milliseconds 50
                }

                # Get staged files
                $stagedFiles = @(Get-StagedFiles)

                # Assert: count matches
                $stagedFiles.Count | Should -Be $fileCount

                # Assert: sorted by stagingTimestamp descending
                for ($i = 0; $i -lt ($stagedFiles.Count - 1); $i++) {
                    $current = [DateTime]::Parse($stagedFiles[$i].stagingTimestamp)
                    $next = [DateTime]::Parse($stagedFiles[$i + 1].stagingTimestamp)
                    $current | Should -BeGreaterOrEqual $next
                }
            }
        }
    }

    Context "Property 13: Staging restore round-trip" {
        <#
            **Validates: Requirements 8.5**
            For any file moved to staging, Restore-FromStaging returns it to
            the original path with identical content. After restore, the file
            is removed from the staging manifest.
        #>

        BeforeAll {
            $Script:TestStagingRoot = Join-Path $env:TEMP "drivepulse-staging-prop13-$(Get-Random)"
        }

        AfterAll {
            Remove-Item $Script:TestStagingRoot -Recurse -Force -ErrorAction SilentlyContinue
        }

        It "Restore-FromStaging returns file to original path with identical content and removes from manifest" {
            1..100 | ForEach-Object {
                # Setup isolated staging root per iteration
                $iterRoot = Join-Path $Script:TestStagingRoot "iter_$_"
                New-Item -Path $iterRoot -ItemType Directory -Force | Out-Null
                $Script:StagingRoot = $iterRoot

                # Generate random file
                $stagedFile = New-RandomStagedFile
                $content = $stagedFile.Content

                # Create source file
                $sourceDir = Join-Path $iterRoot "original"
                $sourceFile = Join-Path $sourceDir "testfile_$_.dat"
                New-Item -Path $sourceDir -ItemType Directory -Force | Out-Null
                [System.IO.File]::WriteAllBytes($sourceFile, $content)

                # Stage the file
                $stageResult = Move-ToStaging -SourcePath $sourceFile -SessionId $stagedFile.SessionId
                $stageResult.Success | Should -Be $true

                # Assert: original is gone
                Test-Path $sourceFile | Should -Be $false

                # Act: Restore from staging
                $restoreResult = Restore-FromStaging -OriginalPath $sourceFile
                $restoreResult.Success | Should -Be $true

                # Assert: File is back at original path
                Test-Path $sourceFile | Should -Be $true

                # Assert: Content is identical
                $restoredContent = [System.IO.File]::ReadAllBytes($sourceFile)
                $restoredContent.Length | Should -Be $content.Length
                [System.Convert]::ToBase64String($restoredContent) | Should -Be ([System.Convert]::ToBase64String($content))

                # Assert: File is removed from staging manifest
                $manifest = Get-StagingManifest
                $entry = $manifest.files | Where-Object { $_.originalPath -eq $sourceFile }
                $entry | Should -BeNullOrEmpty

                # Assert: File no longer exists in staging area
                $stagedPath = $stageResult.StagedPath
                Test-Path $stagedPath | Should -Be $false
            }
        }
    }
}
