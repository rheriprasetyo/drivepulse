BeforeAll {
    . "$PSScriptRoot\..\..\src\audit\audit.ps1"
}

Describe "Initialize-AuditLog" {
    Context "File creation when missing (Req 7.8)" {
        It "Creates the audit log file when it does not exist" {
            # Override Get-AuditLogPath to use a temp location
            $tempDir = Join-Path $TestDrive "logs"
            $tempLog = Join-Path $tempDir "audit.log"

            Mock Get-AuditLogPath { return $tempLog }

            # Ensure nothing exists
            if (Test-Path $tempLog) { Remove-Item $tempLog -Force }
            if (Test-Path $tempDir) { Remove-Item $tempDir -Force -Recurse }

            $result = Initialize-AuditLog

            $result | Should -Be $true
            Test-Path $tempLog | Should -Be $true
        }
    }

    Context "Directory creation when missing (Req 7.8)" {
        It "Creates the logs directory when it does not exist" {
            $tempDir = Join-Path $TestDrive "newdir" "sublogs"
            $tempLog = Join-Path $tempDir "audit.log"

            Mock Get-AuditLogPath { return $tempLog }

            # Ensure directory does not exist
            if (Test-Path $tempDir) { Remove-Item $tempDir -Force -Recurse }

            $result = Initialize-AuditLog

            $result | Should -Be $true
            Test-Path $tempDir | Should -Be $true
            Test-Path $tempLog | Should -Be $true
        }
    }
}

Describe "Write-AuditEntry" {
    Context "Warning on write failure without blocking (Req 7.9)" {
        It "Emits a warning but does not throw when log file is inaccessible" {
            $tempDir = Join-Path $TestDrive "locked-logs"
            $tempLog = Join-Path $tempDir "audit.log"

            # Create the directory and file
            New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
            New-Item -Path $tempLog -ItemType File -Force | Out-Null

            # Lock the file by opening it exclusively
            $lockStream = [System.IO.File]::Open(
                $tempLog,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None
            )

            try {
                Mock Get-AuditLogPath { return $tempLog }

                # Should emit a warning, not throw
                $warnings = @()
                Write-AuditEntry -Action 'backup' -FilePath 'C:\test\file.txt' -WarningVariable warnings 3>&1 | ForEach-Object {
                    $warnings += $_
                }

                # The key assertion: no exception was thrown (we reached this line)
                $true | Should -Be $true

                # Verify a warning was emitted
                $warnings.Count | Should -BeGreaterThan 0
            }
            finally {
                $lockStream.Close()
                $lockStream.Dispose()
            }
        }
    }

    Context "UTF-8 without BOM encoding (Req 13.4)" {
        It "Creates log file without BOM bytes (0xEF 0xBB 0xBF)" {
            $tempDir = Join-Path $TestDrive "utf8-logs"
            $tempLog = Join-Path $tempDir "audit.log"

            # Ensure clean state
            if (Test-Path $tempDir) { Remove-Item $tempDir -Force -Recurse }

            Mock Get-AuditLogPath { return $tempLog }

            Initialize-AuditLog
            Write-AuditEntry -Action 'stage' -FilePath 'C:\Users\Test\file.txt'

            # Read raw bytes from the file
            $bytes = [System.IO.File]::ReadAllBytes($tempLog)

            # Check that the first 3 bytes are NOT the UTF-8 BOM
            if ($bytes.Length -ge 3) {
                $hasBom = ($bytes[0] -eq 0xEF) -and ($bytes[1] -eq 0xBB) -and ($bytes[2] -eq 0xBF)
                $hasBom | Should -Be $false
            }

            # Verify content is valid UTF-8 text
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            $content = $utf8NoBom.GetString($bytes)
            $content | Should -Not -BeNullOrEmpty
        }
    }

    Context "Flush to disk before returning (Req 7.10)" {
        It "Data is immediately readable from file after Write-AuditEntry returns" {
            $tempDir = Join-Path $TestDrive "flush-logs"
            $tempLog = Join-Path $tempDir "audit.log"

            # Ensure clean state
            if (Test-Path $tempDir) { Remove-Item $tempDir -Force -Recurse }

            Mock Get-AuditLogPath { return $tempLog }

            Initialize-AuditLog

            # Write an entry
            Write-AuditEntry -Action 'delete' -FilePath 'C:\Users\Test\important.doc'

            # Immediately read the file - data should be present (no buffering)
            $content = [System.IO.File]::ReadAllText($tempLog, [System.Text.UTF8Encoding]::new($false))
            $content | Should -Not -BeNullOrEmpty

            # Parse the JSON line to verify it's complete and valid
            $lines = $content.Split("`r`n", [System.StringSplitOptions]::RemoveEmptyEntries)
            $lines.Count | Should -Be 1

            $entry = $lines[0] | ConvertFrom-Json
            $entry.action | Should -Be 'delete'
            $entry.file | Should -Be 'C:\Users\Test\important.doc'
            $entry.timestamp | Should -Not -BeNullOrEmpty
            $entry.user | Should -Not -BeNullOrEmpty
        }
    }
}
