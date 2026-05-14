<#
.SYNOPSIS
    DrivePulse — CLI Formatting Unit Tests
.DESCRIPTION
    Unit tests for CLI module functions:
    - Format-Size with various byte values
    - Show-DriveStatus color logic
    - Show-MainMenu re-prompts on invalid input
    - All output text is in Bahasa Indonesia
.NOTES
    Requirements: 5.1, 5.3, 5.5, 8.1, 8.2
#>

BeforeAll {
    . "$PSScriptRoot\..\..\src\ui\cli.ps1"
}

Describe "Format-Size" {
    Context "Zero bytes" {
        It "Returns '0 MB' for 0 bytes" {
            $result = Format-Size -Bytes 0
            $result | Should -Be "0 MB"
        }
    }

    Context "Values less than 1 GB (show as MB)" {
        It "Returns correct MB for 500 MB" {
            $result = Format-Size -Bytes ([long](500 * 1048576))
            $result | Should -Be "500 MB"
        }

        It "Returns correct MB for 1 MB" {
            $result = Format-Size -Bytes 1048576
            $result | Should -Be "1 MB"
        }

        It "Returns correct MB for 999 MB" {
            $result = Format-Size -Bytes ([long](999 * 1048576))
            $result | Should -Be "999 MB"
        }

        It "Returns correct MB for small values (100 KB)" {
            $result = Format-Size -Bytes 102400
            # 102400 / 1048576 ≈ 0.098 → rounds to 0
            $result | Should -Be "0 MB"
        }
    }

    Context "Values at or above 1 GB (show as GB)" {
        It "Returns '1 GB' for exactly 1 GB" {
            $result = Format-Size -Bytes 1073741824
            $result | Should -Be "1 GB"
        }

        It "Returns correct GB for 2.5 GB" {
            $result = Format-Size -Bytes ([long](2.5 * 1073741824))
            $result | Should -Be "2.5 GB"
        }

        It "Returns correct GB for 100 GB" {
            $result = Format-Size -Bytes ([long](100 * 1073741824))
            $result | Should -Be "100 GB"
        }

        It "Returns correct GB for 10.3 GB" {
            $bytes = [long](10.3 * 1073741824)
            $result = Format-Size -Bytes $bytes
            $result | Should -Be "10.3 GB"
        }
    }
}

Describe "Show-DriveStatus" {
    Context "Color logic based on usage percentage" {
        It "Uses Red color when usage >= 90%" {
            $scanResult = [PSCustomObject]@{
                PSTypeName   = 'DrivePulse.ScanResult'
                UsagePercent = 95
                TotalBytes   = [long]100GB
                UsedBytes    = [long]95GB
                FreeBytes    = [long]5GB
                DriveLetter  = "C"
            }

            # Use InModuleScope-like approach: capture via script variable
            $script:capturedColors = [System.Collections.ArrayList]::new()
            Mock Write-Host {
                param([string]$Object, [string]$ForegroundColor, [switch]$NoNewline)
                if ($ForegroundColor) {
                    [void]$script:capturedColors.Add($ForegroundColor)
                }
            }

            Show-DriveStatus -ScanResult $scanResult

            $script:capturedColors | Should -Contain "Red"
        }

        It "Uses Yellow color when usage >= 75% and < 90%" {
            $scanResult = [PSCustomObject]@{
                PSTypeName   = 'DrivePulse.ScanResult'
                UsagePercent = 80
                TotalBytes   = [long]100GB
                UsedBytes    = [long]80GB
                FreeBytes    = [long]20GB
                DriveLetter  = "C"
            }

            $script:capturedColors = [System.Collections.ArrayList]::new()
            Mock Write-Host {
                param([string]$Object, [string]$ForegroundColor, [switch]$NoNewline)
                if ($ForegroundColor) {
                    [void]$script:capturedColors.Add($ForegroundColor)
                }
            }

            Show-DriveStatus -ScanResult $scanResult

            $script:capturedColors | Should -Contain "Yellow"
        }

        It "Uses Green color when usage < 75%" {
            $scanResult = [PSCustomObject]@{
                PSTypeName   = 'DrivePulse.ScanResult'
                UsagePercent = 50
                TotalBytes   = [long]100GB
                UsedBytes    = [long]50GB
                FreeBytes    = [long]50GB
                DriveLetter  = "C"
            }

            $script:capturedColors = [System.Collections.ArrayList]::new()
            Mock Write-Host {
                param([string]$Object, [string]$ForegroundColor, [switch]$NoNewline)
                if ($ForegroundColor) {
                    [void]$script:capturedColors.Add($ForegroundColor)
                }
            }

            Show-DriveStatus -ScanResult $scanResult

            $script:capturedColors | Should -Contain "Green"
        }
    }
}

Describe "Show-MainMenu" {
    Context "Invalid input handling" {
        It "Re-prompts on invalid input then exits on '4'" {
            $script:callCount = 0
            Mock Read-Host {
                $script:callCount++
                if ($script:callCount -eq 1) { return "invalid" }
                if ($script:callCount -eq 2) { return "99" }
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

        It "Exits gracefully when user selects '4' (Keluar)" {
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

Describe "Bahasa Indonesia Output" {
    Context "All user-facing text is in Bahasa Indonesia" {
        It "Menu options contain Bahasa Indonesia text" {
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
        }

        It "Help text (Bantuan) is in Bahasa Indonesia" {
            $script:helpCallCount = 0
            Mock Read-Host {
                $script:helpCallCount++
                if ($script:helpCallCount -eq 1) { return "3" }  # Bantuan
                if ($script:helpCallCount -eq 2) { return "" }   # Press Enter
                return "4"  # Keluar
            }

            $script:capturedOutput = [System.Collections.ArrayList]::new()
            Mock Write-Host {
                param([string]$Object, [string]$ForegroundColor, [switch]$NoNewline)
                if ($Object) { [void]$script:capturedOutput.Add($Object) }
            }

            Show-MainMenu

            $allOutput = $script:capturedOutput -join "`n"
            $allOutput | Should -Match 'Cara Pakai'
            $allOutput | Should -Match 'DrivePulse'
        }

        It "Error messages are in Bahasa Indonesia" {
            $script:errCallCount = 0
            Mock Read-Host {
                $script:errCallCount++
                if ($script:errCallCount -eq 1) { return "xyz" }
                return "4"
            }

            $script:capturedOutput = [System.Collections.ArrayList]::new()
            Mock Write-Host {
                param([string]$Object, [string]$ForegroundColor, [switch]$NoNewline)
                if ($Object) { [void]$script:capturedOutput.Add($Object) }
            }

            Show-MainMenu

            $allOutput = $script:capturedOutput -join "`n"
            $allOutput | Should -Match 'tidak valid|Silakan pilih'
        }
    }
}
