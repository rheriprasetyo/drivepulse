<#
.SYNOPSIS
    DrivePulse — Backup Menu Unit Tests
.DESCRIPTION
    Unit tests for the Show-BackupMenu function in CLI:
    - Empty backup state displays message
    - Backups grouped by session
    - Restore summary display
    - Error handling (conflict, permissions, space)
    - All text in Bahasa Indonesia
.NOTES
    Requirements: 11.1, 11.2, 11.3, 11.4, 11.5, 11.6, 11.7
#>

BeforeAll {
    . "$PSScriptRoot\..\..\src\ui\cli.ps1"
}

Describe "Show-BackupMenu: Empty State" {
    It "Displays 'Tidak ada backup yang tersedia' when no backups exist (Req 11.4)" {
        Mock Get-AvailableBackups { return @() }

        $script:capturedOutput = [System.Collections.ArrayList]::new()
        Mock Write-Host {
            param([string]$Object, [string]$ForegroundColor, [switch]$NoNewline)
            if ($Object) { [void]$script:capturedOutput.Add($Object) }
        }

        Show-BackupMenu

        $allOutput = $script:capturedOutput -join "`n"
        $allOutput | Should -Match 'Tidak ada backup yang tersedia'
    }
}

Describe "Show-BackupMenu: Listing Backups" {
    It "Groups backups by session and displays file details (Req 11.1)" {
        $mockBackups = @(
            [PSCustomObject]@{
                SessionId    = '20260515-143022-a1b2c3'
                OriginalPath = 'C:\Users\Test\file1.tmp'
                BackupPath   = '20260515-143022-a1b2c3\C_drive\Users\Test\file1.tmp'
                SizeBytes    = 1048576
                Timestamp    = '2026-05-15T14:30:23+07:00'
                CreatedAt    = '2026-05-15T14:30:22+07:00'
            },
            [PSCustomObject]@{
                SessionId    = '20260515-143022-a1b2c3'
                OriginalPath = 'C:\Users\Test\file2.tmp'
                BackupPath   = '20260515-143022-a1b2c3\C_drive\Users\Test\file2.tmp'
                SizeBytes    = 2097152
                Timestamp    = '2026-05-15T14:30:24+07:00'
                CreatedAt    = '2026-05-15T14:30:22+07:00'
            }
        )

        Mock Get-AvailableBackups { return $mockBackups }
        Mock Read-Host { return 'K' }

        $script:capturedOutput = [System.Collections.ArrayList]::new()
        Mock Write-Host {
            param([string]$Object, [string]$ForegroundColor, [switch]$NoNewline)
            if ($Object) { [void]$script:capturedOutput.Add($Object) }
        }

        Show-BackupMenu

        $allOutput = $script:capturedOutput -join "`n"
        $allOutput | Should -Match 'Session 1'
        $allOutput | Should -Match '20260515-143022-a1b2c3'
        $allOutput | Should -Match 'file1\.tmp'
        $allOutput | Should -Match 'file2\.tmp'
        $allOutput | Should -Match '\[1\]'
        $allOutput | Should -Match '\[2\]'
    }
}

Describe "Show-BackupMenu: Restore Individual File" {
    It "Restores a specific file by number and shows summary (Req 11.2, 11.6)" {
        $mockBackups = @(
            [PSCustomObject]@{
                SessionId    = '20260515-143022-a1b2c3'
                OriginalPath = 'C:\Users\Test\file1.tmp'
                BackupPath   = '20260515-143022-a1b2c3\C_drive\Users\Test\file1.tmp'
                SizeBytes    = 1048576
                Timestamp    = '2026-05-15T14:30:23+07:00'
                CreatedAt    = '2026-05-15T14:30:22+07:00'
            }
        )

        Mock Get-AvailableBackups { return $mockBackups }
        Mock Read-Host { return '1' }
        Mock Restore-FromBackup {
            return [PSCustomObject]@{
                Success       = $true
                RestoredCount = 1
                FailedCount   = 0
                TotalSize     = [long]1048576
                Errors        = @()
            }
        }

        $script:capturedOutput = [System.Collections.ArrayList]::new()
        Mock Write-Host {
            param([string]$Object, [string]$ForegroundColor, [switch]$NoNewline)
            if ($Object) { [void]$script:capturedOutput.Add($Object) }
        }

        Show-BackupMenu

        $allOutput = $script:capturedOutput -join "`n"
        $allOutput | Should -Match 'Berhasil: 1 file'
        $allOutput | Should -Match 'MB|KB'
    }
}

Describe "Show-BackupMenu: Restore Session" {
    It "Restores all files from a session using S<number> (Req 11.3, 11.6)" {
        $mockBackups = @(
            [PSCustomObject]@{
                SessionId    = '20260515-143022-a1b2c3'
                OriginalPath = 'C:\Users\Test\file1.tmp'
                BackupPath   = '20260515-143022-a1b2c3\C_drive\Users\Test\file1.tmp'
                SizeBytes    = 1048576
                Timestamp    = '2026-05-15T14:30:23+07:00'
                CreatedAt    = '2026-05-15T14:30:22+07:00'
            },
            [PSCustomObject]@{
                SessionId    = '20260515-143022-a1b2c3'
                OriginalPath = 'C:\Users\Test\file2.tmp'
                BackupPath   = '20260515-143022-a1b2c3\C_drive\Users\Test\file2.tmp'
                SizeBytes    = 2097152
                Timestamp    = '2026-05-15T14:30:24+07:00'
                CreatedAt    = '2026-05-15T14:30:22+07:00'
            }
        )

        Mock Get-AvailableBackups { return $mockBackups }
        Mock Read-Host { return 'S1' }
        Mock Restore-FromBackup {
            return [PSCustomObject]@{
                Success       = $true
                RestoredCount = 2
                FailedCount   = 0
                TotalSize     = [long]3145728
                Errors        = @()
            }
        }

        $script:capturedOutput = [System.Collections.ArrayList]::new()
        Mock Write-Host {
            param([string]$Object, [string]$ForegroundColor, [switch]$NoNewline)
            if ($Object) { [void]$script:capturedOutput.Add($Object) }
        }

        Show-BackupMenu

        $allOutput = $script:capturedOutput -join "`n"
        $allOutput | Should -Match 'Berhasil: 2 file'
    }
}

Describe "Show-BackupMenu: Error Handling" {
    It "Displays conflict error message in Bahasa Indonesia (Req 11.7)" {
        $mockBackups = @(
            [PSCustomObject]@{
                SessionId    = '20260515-143022-a1b2c3'
                OriginalPath = 'C:\Users\Test\file1.tmp'
                BackupPath   = '20260515-143022-a1b2c3\C_drive\Users\Test\file1.tmp'
                SizeBytes    = 1048576
                Timestamp    = '2026-05-15T14:30:23+07:00'
                CreatedAt    = '2026-05-15T14:30:22+07:00'
            }
        )

        Mock Get-AvailableBackups { return $mockBackups }
        Mock Read-Host { return '1' }
        Mock Restore-FromBackup {
            return [PSCustomObject]@{
                Success       = $false
                RestoredCount = 0
                FailedCount   = 1
                TotalSize     = [long]0
                Errors        = @("File sudah ada di lokasi asli (gunakan -Force untuk overwrite): C:\Users\Test\file1.tmp")
            }
        }

        $script:capturedOutput = [System.Collections.ArrayList]::new()
        Mock Write-Host {
            param([string]$Object, [string]$ForegroundColor, [switch]$NoNewline)
            if ($Object) { [void]$script:capturedOutput.Add($Object) }
        }

        Show-BackupMenu

        $allOutput = $script:capturedOutput -join "`n"
        $allOutput | Should -Match 'Konflik.*sudah ada'
    }

    It "Displays permission error message in Bahasa Indonesia (Req 11.7)" {
        $mockBackups = @(
            [PSCustomObject]@{
                SessionId    = '20260515-143022-a1b2c3'
                OriginalPath = 'C:\Users\Test\file1.tmp'
                BackupPath   = '20260515-143022-a1b2c3\C_drive\Users\Test\file1.tmp'
                SizeBytes    = 1048576
                Timestamp    = '2026-05-15T14:30:23+07:00'
                CreatedAt    = '2026-05-15T14:30:22+07:00'
            }
        )

        Mock Get-AvailableBackups { return $mockBackups }
        Mock Read-Host { return '1' }
        Mock Restore-FromBackup {
            return [PSCustomObject]@{
                Success       = $false
                RestoredCount = 0
                FailedCount   = 1
                TotalSize     = [long]0
                Errors        = @("Akses ditolak: permission denied untuk C:\Users\Test\file1.tmp")
            }
        }

        $script:capturedOutput = [System.Collections.ArrayList]::new()
        Mock Write-Host {
            param([string]$Object, [string]$ForegroundColor, [switch]$NoNewline)
            if ($Object) { [void]$script:capturedOutput.Add($Object) }
        }

        Show-BackupMenu

        $allOutput = $script:capturedOutput -join "`n"
        $allOutput | Should -Match 'Izin akses ditolak'
    }

    It "Displays space error message in Bahasa Indonesia (Req 11.7)" {
        $mockBackups = @(
            [PSCustomObject]@{
                SessionId    = '20260515-143022-a1b2c3'
                OriginalPath = 'C:\Users\Test\file1.tmp'
                BackupPath   = '20260515-143022-a1b2c3\C_drive\Users\Test\file1.tmp'
                SizeBytes    = 1048576
                Timestamp    = '2026-05-15T14:30:23+07:00'
                CreatedAt    = '2026-05-15T14:30:22+07:00'
            }
        )

        Mock Get-AvailableBackups { return $mockBackups }
        Mock Read-Host { return '1' }
        Mock Restore-FromBackup {
            return [PSCustomObject]@{
                Success       = $false
                RestoredCount = 0
                FailedCount   = 1
                TotalSize     = [long]0
                Errors        = @("Ruang disk tidak mencukupi untuk restore")
            }
        }

        $script:capturedOutput = [System.Collections.ArrayList]::new()
        Mock Write-Host {
            param([string]$Object, [string]$ForegroundColor, [switch]$NoNewline)
            if ($Object) { [void]$script:capturedOutput.Add($Object) }
        }

        Show-BackupMenu

        $allOutput = $script:capturedOutput -join "`n"
        $allOutput | Should -Match 'Ruang disk tidak mencukupi'
    }
}

Describe "Show-BackupMenu: Bahasa Indonesia" {
    It "All backup menu text is in Bahasa Indonesia (Req 11.5)" {
        Mock Get-AvailableBackups { return @() }

        $script:capturedOutput = [System.Collections.ArrayList]::new()
        Mock Write-Host {
            param([string]$Object, [string]$ForegroundColor, [switch]$NoNewline)
            if ($Object) { [void]$script:capturedOutput.Add($Object) }
        }

        Show-BackupMenu

        $allOutput = $script:capturedOutput -join "`n"
        $allOutput | Should -Match 'Kelola Backup'
        $allOutput | Should -Match 'Tidak ada backup yang tersedia'
    }
}

Describe "Format-BackupSize" {
    It "Formats bytes correctly" {
        Format-BackupSize -Bytes 500 | Should -Be "500 B"
    }

    It "Formats KB correctly" {
        Format-BackupSize -Bytes 2048 | Should -Be "2.00 KB"
    }

    It "Formats MB correctly" {
        Format-BackupSize -Bytes 1048576 | Should -Be "1.00 MB"
    }

    It "Formats GB correctly" {
        Format-BackupSize -Bytes 1073741824 | Should -Be "1.00 GB"
    }
}
