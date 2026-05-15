<#
.SYNOPSIS
    DrivePulse — Audit Logger Property-Based Tests
.DESCRIPTION
    Property-based tests for the audit logger module verifying:
    - Property 8: Audit log entry round-trip serialization
    - Property 9: Audit log append-only invariant
    - Property 10: Audit log rotation threshold
.NOTES
    Uses 100 iterations for Properties 8 and 9, 20 iterations for Property 10
    (due to I/O cost of creating 10 MB files).
    Uses generators from tests/helpers/generators.ps1
#>

Describe "Audit Logger Property Tests" -Tag "Feature: safety-cleanup" {
    BeforeAll {
        . "$PSScriptRoot\..\..\src\audit\audit.ps1"
        . "$PSScriptRoot\..\helpers\generators.ps1"
    }

    Context "Property 8: Audit log entry round-trip serialization" -Tag "Property 8: round-trip serialization" {
        <#
            **Validates: Requirements 7.2, 13.1, 13.3, 13.5**
            For any valid action and file path containing special characters
            (backslash, quotes, unicode, control chars), Write-AuditEntry produces
            a valid JSON line that can be parsed back, and all fields match the
            original input.
        #>

        It "Write-AuditEntry produces valid JSON that round-trips all fields correctly" {
            1..100 | ForEach-Object {
                # Arrange: generate random audit entry
                $entry = New-RandomAuditEntry
                $logFile = Join-Path $TestDrive "roundtrip-$_.log"

                # Create empty log file
                $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
                [System.IO.File]::WriteAllText($logFile, '', $utf8NoBom)

                # Override Get-AuditLogPath in the current scope
                function Get-AuditLogPath { return $logFile }

                # Act: write the audit entry
                Write-AuditEntry -Action $entry.Action -FilePath $entry.FilePath

                # Assert: file should have content
                $content = [System.IO.File]::ReadAllText($logFile, $utf8NoBom)
                $lines = @($content -split "`r`n" | Where-Object { $_ -ne '' })
                $lines.Count | Should -Be 1 -Because "iteration $_ should produce exactly one JSON line"

                # Parse the JSON line
                $parsed = $lines[0] | ConvertFrom-Json

                # Verify all fields round-trip correctly
                $parsed.action | Should -Be $entry.Action -Because "action should round-trip (iteration $_)"
                $parsed.file | Should -Be $entry.FilePath -Because "file path should round-trip (iteration $_)"
                $parsed.timestamp | Should -Not -BeNullOrEmpty -Because "timestamp should be present (iteration $_)"
                $parsed.user | Should -Not -BeNullOrEmpty -Because "user should be present (iteration $_)"

                # Verify timestamp is valid ISO 8601
                $parsedDate = [DateTimeOffset]::Parse($parsed.timestamp)
                $parsedDate | Should -Not -BeNullOrEmpty -Because "timestamp should be valid ISO 8601 (iteration $_)"

                # Verify user matches current user
                $parsed.user | Should -Be ([System.Environment]::UserName) -Because "user should match current user (iteration $_)"
            }
        }
    }

    Context "Property 9: Audit log append-only invariant" -Tag "Property 9: append-only invariant" {
        <#
            **Validates: Requirements 7.1, 13.2**
            Writing N entries results in exactly N lines in the log file.
            Previous lines are never modified.
        #>

        It "Writing N entries produces exactly N lines and previous lines are unchanged" {
            1..100 | ForEach-Object {
                # Arrange: pick a random N between 2 and 10
                $n = Get-Random -Minimum 2 -Maximum 11
                $logFile = Join-Path $TestDrive "append-only-$_.log"

                # Override Get-AuditLogPath in the current scope
                function Get-AuditLogPath { return $logFile }

                # Create empty log file
                $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
                [System.IO.File]::WriteAllText($logFile, '', $utf8NoBom)

                $previousLines = @()

                # Act: write N entries, checking invariant after each
                for ($i = 1; $i -le $n; $i++) {
                    $entry = New-RandomAuditEntry
                    Write-AuditEntry -Action $entry.Action -FilePath $entry.FilePath

                    # Read all lines
                    $content = [System.IO.File]::ReadAllText($logFile, $utf8NoBom)
                    $currentLines = @($content -split "`r`n" | Where-Object { $_ -ne '' })

                    # Assert: exactly i lines after i-th write
                    $currentLines.Count | Should -Be $i -Because "after write $i of $n, should have $i lines (iteration $_)"

                    # Assert: previous lines unchanged
                    for ($j = 0; $j -lt $previousLines.Count; $j++) {
                        $currentLines[$j] | Should -Be $previousLines[$j] -Because "line $j should be unchanged after write $i (iteration $_)"
                    }

                    $previousLines = $currentLines
                }
            }
        }
    }

    Context "Property 10: Audit log rotation threshold" -Tag "Property 10: rotation threshold" {
        <#
            **Validates: Requirements 7.11**
            When the log file exceeds 10 MB, rotation occurs — the old file is
            renamed with timestamp suffix, and a new empty file is created containing
            only the newly written entry.
        #>

        It "Log file at or above 10 MB triggers rotation with new file containing only the new entry" {
            # Use 20 iterations due to I/O cost of creating 10 MB files
            1..20 | ForEach-Object {
                # Arrange: create a log file that is at or above 10 MB
                $logDir = Join-Path $TestDrive "rotation-$_"
                New-Item -Path $logDir -ItemType Directory -Force | Out-Null
                $logFile = Join-Path $logDir 'audit.log'

                # Override Get-AuditLogPath in the current scope
                function Get-AuditLogPath { return $logFile }

                # Create a file that is just over 10 MB using efficient byte writing
                $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
                $stream = New-Object System.IO.FileStream($logFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
                try {
                    # Write a block of padding to reach 10 MB quickly
                    $paddingLine = '{"timestamp":"2024-01-01T00:00:00+07:00","action":"backup","file":"C:\\pad.txt","user":"test"}' + "`r`n"
                    $paddingBytes = $utf8NoBom.GetBytes($paddingLine)
                    # Write in larger chunks for speed
                    $chunkSize = 1000
                    $chunk = New-Object byte[] ($paddingBytes.Length * $chunkSize)
                    for ($c = 0; $c -lt $chunkSize; $c++) {
                        [Array]::Copy($paddingBytes, 0, $chunk, $c * $paddingBytes.Length, $paddingBytes.Length)
                    }
                    while ($stream.Length -lt 10MB) {
                        $stream.Write($chunk, 0, $chunk.Length)
                    }
                }
                finally {
                    $stream.Close()
                    $stream.Dispose()
                }

                # Verify file is >= 10 MB
                $originalSize = (Get-Item $logFile).Length
                $originalSize | Should -BeGreaterOrEqual 10MB -Because "setup: file should be >= 10 MB (iteration $_)"

                # Act: write a new entry
                $entry = New-RandomAuditEntry
                Write-AuditEntry -Action $entry.Action -FilePath $entry.FilePath

                # Assert: rotation occurred
                # 1. The original log file should now be small (contains only the new entry)
                $newLogSize = (Get-Item $logFile).Length
                $newLogSize | Should -BeLessThan 10MB -Because "new log file should be small after rotation (iteration $_)"

                # 2. A rotated file with timestamp suffix should exist
                $rotatedFiles = @(Get-ChildItem -Path $logDir -Filter 'audit-*.log')
                $rotatedFiles.Count | Should -BeGreaterOrEqual 1 -Because "rotated file should exist (iteration $_)"

                # 3. The new log file should contain exactly one valid JSON line (the new entry)
                $newContent = [System.IO.File]::ReadAllText($logFile, $utf8NoBom)
                $newLines = @($newContent -split "`r`n" | Where-Object { $_ -ne '' })
                $newLines.Count | Should -Be 1 -Because "new log should have exactly 1 entry after rotation (iteration $_)"

                # 4. The new entry should parse correctly and match our input
                $parsed = $newLines[0] | ConvertFrom-Json
                $parsed.action | Should -Be $entry.Action -Because "rotated new entry action should match (iteration $_)"
                $parsed.file | Should -Be $entry.FilePath -Because "rotated new entry file should match (iteration $_)"

                # Cleanup for next iteration
                Remove-Item -Path $logDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
