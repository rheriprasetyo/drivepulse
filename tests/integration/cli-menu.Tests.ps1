<#
.SYNOPSIS
    DrivePulse — CLI Menu Integration Tests
.DESCRIPTION
    Integration tests for the CLI menu module:
    - Menu navigation with mocked Read-Host
    - Invalid input handling and re-prompt behavior
    - Dry-run label appears in output
    - Bahasa Indonesia text in all user-facing output
.NOTES
    Requirements: 4.1, 4.3, 5.1, 5.2, 5.4, 5.5
#>

BeforeAll {
    . "$PSScriptRoot\..\..\src\ui\cli.ps1"
}

Describe "Integration: Menu Navigation" {
    Context "Quick Scan selection" {
        It "Selecting '1' triggers Quick Scan flow and shows results" {
            # Create a minimal rules file for the scan
            $testFolder = Join-Path $TestDrive "test-safe"
            New-Item -Path $testFolder -ItemType Directory -Force | Out-Null
            [byte[]]$bytes = New-Object byte[] 2048
            [System.IO.File]::WriteAllBytes("$testFolder\file.tmp", $bytes)

            $rulesObj = @{
                thresholds = @{ largeFolderGB = 5; criticalUsagePct = 90; warningUsagePct = 75 }
                categories = @{
                    safe  = @{ description = 'Safe'; items = @(@{ id = 'ts'; label = 'Test Safe'; path = $testFolder; sideEffect = 'None'; requiresAdmin = $false }) }
                    check = @{ description = 'Check'; items = @() }
                }
            }

            # Mock Initialize-Rules to use our test rules
            Mock Initialize-Rules { return ($rulesObj | ConvertTo-Json -Depth 10 | ConvertFrom-Json) }

            # Mock Start-DriveScan to return a controlled result
            Mock Start-DriveScan {
                $item = New-ScanItem -Path $testFolder -Label "Test Safe" -SizeBytes 2048
                return New-ScanResult -Mode Quick -DriveLetter "C" -UsedBytes ([long]50GB) -FreeBytes ([long]50GB) -Items @($item) -Errors @() -ElapsedSeconds 0.5
            }

            # Mock Read-Host: select Quick Scan, then press Enter, then Exit
            $script:navCount = 0
            Mock Read-Host {
                $script:navCount++
                if ($script:navCount -eq 1) { return "1" }
                if ($script:navCount -eq 2) { return "" }
                return "4"
            }

            $script:capturedOutput = [System.Collections.ArrayList]::new()
            Mock Write-Host {
                param([string]$Object, [string]$ForegroundColor, [switch]$NoNewline)
                if ($Object) { [void]$script:capturedOutput.Add($Object) }
            }

            Show-MainMenu

            $allOutput = $script:capturedOutput -join "`n"
            $allOutput | Should -Match 'Quick Scan|Memulai'
        }
    }

    Context "Deep Scan selection" {
        It "Selecting '2' triggers Deep Scan flow" {
            $rulesObj = @{
                thresholds = @{ largeFolderGB = 5; criticalUsagePct = 90; warningUsagePct = 75 }
                categories = @{
                    safe  = @{ description = 'Safe'; items = @() }
                    check = @{ description = 'Check'; items = @() }
                }
            }
            Mock Initialize-Rules { return ($rulesObj | ConvertTo-Json -Depth 10 | ConvertFrom-Json) }

            Mock Start-DriveScan {
                return New-ScanResult -Mode Deep -DriveLetter "C" -UsedBytes ([long]50GB) -FreeBytes ([long]50GB) -Items @() -Errors @() -ElapsedSeconds 2.0
            }

            $script:deepNavCount = 0
            Mock Read-Host {
                $script:deepNavCount++
                if ($script:deepNavCount -eq 1) { return "2" }
                if ($script:deepNavCount -eq 2) { return "" }
                return "4"
            }

            $script:capturedOutput = [System.Collections.ArrayList]::new()
            Mock Write-Host {
                param([string]$Object, [string]$ForegroundColor, [switch]$NoNewline)
                if ($Object) { [void]$script:capturedOutput.Add($Object) }
            }

            Show-MainMenu

            $allOutput = $script:capturedOutput -join "`n"
            $allOutput | Should -Match 'Deep Scan|Memulai'
        }
    }

    Context "Help selection" {
        It "Selecting '3' shows help text" {
            $script:helpNavCount = 0
            Mock Read-Host {
                $script:helpNavCount++
                if ($script:helpNavCount -eq 1) { return "3" }
                if ($script:helpNavCount -eq 2) { return "" }
                return "4"
            }

            $script:capturedOutput = [System.Collections.ArrayList]::new()
            Mock Write-Host {
                param([string]$Object, [string]$ForegroundColor, [switch]$NoNewline)
                if ($Object) { [void]$script:capturedOutput.Add($Object) }
            }

            Show-MainMenu

            $allOutput = $script:capturedOutput -join "`n"
            $allOutput | Should -Match 'Bantuan'
            $allOutput | Should -Match 'Cara Pakai'
        }
    }

    Context "Exit selection" {
        It "Selecting '4' exits gracefully with goodbye message" {
            Mock Read-Host { return "4" }

            $script:capturedOutput = [System.Collections.ArrayList]::new()
            Mock Write-Host {
                param([string]$Object, [string]$ForegroundColor, [switch]$NoNewline)
                if ($Object) { [void]$script:capturedOutput.Add($Object) }
            }

            Show-MainMenu

            $allOutput = $script:capturedOutput -join "`n"
            $allOutput | Should -Match 'Terima kasih|Sampai jumpa'
        }
    }
}

Describe "Integration: Invalid Input Handling" {
    It "Shows error message for non-numeric input" {
        $script:invalidCount = 0
        Mock Read-Host {
            $script:invalidCount++
            if ($script:invalidCount -eq 1) { return "abc" }
            return "4"
        }

        $script:capturedOutput = [System.Collections.ArrayList]::new()
        Mock Write-Host {
            param([string]$Object, [string]$ForegroundColor, [switch]$NoNewline)
            if ($Object) { [void]$script:capturedOutput.Add($Object) }
        }

        Show-MainMenu

        $allOutput = $script:capturedOutput -join "`n"
        $allOutput | Should -Match 'tidak valid'
    }

    It "Shows error message for out-of-range number" {
        $script:oorCount = 0
        Mock Read-Host {
            $script:oorCount++
            if ($script:oorCount -eq 1) { return "9" }
            return "4"
        }

        $script:capturedOutput = [System.Collections.ArrayList]::new()
        Mock Write-Host {
            param([string]$Object, [string]$ForegroundColor, [switch]$NoNewline)
            if ($Object) { [void]$script:capturedOutput.Add($Object) }
        }

        Show-MainMenu

        $allOutput = $script:capturedOutput -join "`n"
        $allOutput | Should -Match 'tidak valid'
    }

    It "Re-displays menu after invalid input" {
        $script:reCount = 0
        Mock Read-Host {
            $script:reCount++
            if ($script:reCount -eq 1) { return "invalid" }
            return "4"
        }

        $script:capturedOutput = [System.Collections.ArrayList]::new()
        Mock Write-Host {
            param([string]$Object, [string]$ForegroundColor, [switch]$NoNewline)
            if ($Object) { [void]$script:capturedOutput.Add($Object) }
        }

        Show-MainMenu

        $allOutput = $script:capturedOutput -join "`n"
        # Menu should appear at least twice (initial + after invalid input)
        $menuMatches = [regex]::Matches($allOutput, 'DrivePulse v1\.1')
        $menuMatches.Count | Should -BeGreaterOrEqual 2
    }
}

Describe "Integration: Dry-Run Label" {
    It "DRY-RUN label appears in scan output" {
        $rulesObj = @{
            thresholds = @{ largeFolderGB = 5; criticalUsagePct = 90; warningUsagePct = 75 }
            categories = @{
                safe  = @{ description = 'Safe'; items = @() }
                check = @{ description = 'Check'; items = @() }
            }
        }
        Mock Initialize-Rules { return ($rulesObj | ConvertTo-Json -Depth 10 | ConvertFrom-Json) }

        Mock Start-DriveScan {
            return New-ScanResult -Mode Quick -DriveLetter "C" -UsedBytes ([long]50GB) -FreeBytes ([long]50GB) -Items @() -Errors @() -ElapsedSeconds 0.3
        }

        $script:dryRunCount = 0
        Mock Read-Host {
            $script:dryRunCount++
            if ($script:dryRunCount -eq 1) { return "1" }
            if ($script:dryRunCount -eq 2) { return "" }
            return "4"
        }

        $script:capturedOutput = [System.Collections.ArrayList]::new()
        Mock Write-Host {
            param([string]$Object, [string]$ForegroundColor, [switch]$NoNewline)
            if ($Object) { [void]$script:capturedOutput.Add($Object) }
        }

        Show-MainMenu

        $allOutput = $script:capturedOutput -join "`n"
        $allOutput | Should -Match 'DRY-RUN'
        $allOutput | Should -Match 'tidak ada file yang dihapus'
    }
}

Describe "Integration: Bahasa Indonesia Output" {
    It "All menu text is in Bahasa Indonesia" {
        Mock Read-Host { return "4" }

        $script:capturedOutput = [System.Collections.ArrayList]::new()
        Mock Write-Host {
            param([string]$Object, [string]$ForegroundColor, [switch]$NoNewline)
            if ($Object) { [void]$script:capturedOutput.Add($Object) }
        }

        Show-MainMenu

        $allOutput = $script:capturedOutput -join "`n"
        $allOutput | Should -Match 'Bantuan'
        $allOutput | Should -Match 'Keluar'
        $allOutput | Should -Match 'Tutup aplikasi'
        $allOutput | Should -Match 'Scan cepat|Quick Scan'
    }

    It "Scan results text is in Bahasa Indonesia" {
        $rulesObj = @{
            thresholds = @{ largeFolderGB = 5; criticalUsagePct = 90; warningUsagePct = 75 }
            categories = @{
                safe  = @{ description = 'Safe'; items = @() }
                check = @{ description = 'Check'; items = @() }
            }
        }
        Mock Initialize-Rules { return ($rulesObj | ConvertTo-Json -Depth 10 | ConvertFrom-Json) }

        $item = New-ScanItem -Path "C:\test" -Label "Test Item" -SizeBytes 1024
        Mock Start-DriveScan {
            return New-ScanResult -Mode Quick -DriveLetter "C" -UsedBytes ([long]50GB) -FreeBytes ([long]50GB) -Items @($item) -Errors @() -ElapsedSeconds 0.2
        }

        $script:bahasaCount = 0
        Mock Read-Host {
            $script:bahasaCount++
            if ($script:bahasaCount -eq 1) { return "1" }
            if ($script:bahasaCount -eq 2) { return "" }
            return "4"
        }

        $script:capturedOutput = [System.Collections.ArrayList]::new()
        Mock Write-Host {
            param([string]$Object, [string]$ForegroundColor, [switch]$NoNewline)
            if ($Object) { [void]$script:capturedOutput.Add($Object) }
        }

        Show-MainMenu

        $allOutput = $script:capturedOutput -join "`n"
        $allOutput | Should -Match 'Aman Dihapus|Perlu Dicek Manual'
        $allOutput | Should -Match 'Ringkasan|Bisa diklaim'
    }

    It "No English-only user-facing strings in menu flow" {
        Mock Read-Host { return "4" }

        $script:capturedOutput = [System.Collections.ArrayList]::new()
        Mock Write-Host {
            param([string]$Object, [string]$ForegroundColor, [switch]$NoNewline)
            if ($Object) { [void]$script:capturedOutput.Add($Object) }
        }

        Show-MainMenu

        $allOutput = $script:capturedOutput -join "`n"
        $allOutput | Should -Not -Match '\bPress Enter\b'
        $allOutput | Should -Not -Match '\bInvalid choice\b'
        $allOutput | Should -Not -Match '\bSelect option\b'
    }
}
