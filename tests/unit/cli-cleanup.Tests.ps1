<#
.SYNOPSIS
    DrivePulse — CLI Cleanup Menu Unit Tests
.DESCRIPTION
    Unit tests for the [5] Bersihkan menu option:
    - No scan result: displays message and returns to menu
    - With scan result: displays categorized items and reclaimable space
    - All text in Bahasa Indonesia
.NOTES
    Requirements: 10.1, 10.2, 10.3, 10.4, 10.5, 10.6
#>

BeforeAll {
    . "$PSScriptRoot\..\..\src\ui\cli.ps1"
}

Describe "Unit: Cleanup Menu Option [5] Bersihkan" {
    Context "No scan result available (Req 10.2)" {
        It "Displays 'Belum ada hasil scan' message when no scan has been performed" {
            # Select cleanup (5), then exit (8)
            $script:inputCount = 0
            Mock Read-Host {
                $script:inputCount++
                if ($script:inputCount -eq 1) { return "5" }
                return "8"
            }

            $script:capturedOutput = [System.Collections.ArrayList]::new()
            Mock Write-Host {
                param([string]$Object, [string]$ForegroundColor, [switch]$NoNewline)
                if ($Object) { [void]$script:capturedOutput.Add($Object) }
            }

            Show-MainMenu

            $allOutput = $script:capturedOutput -join "`n"
            $allOutput | Should -Match 'Belum ada hasil scan'
            $allOutput | Should -Match 'Lakukan scan terlebih dahulu'
        }
    }

    Context "With scan result available (Req 10.1, 10.3)" {
        It "Displays categorized items and reclaimable space summary" {
            # Mock scan and categorize to produce results, then select cleanup
            $rulesObj = @{
                thresholds = @{ largeFolderGB = 5; criticalUsagePct = 90; warningUsagePct = 75 }
                categories = @{
                    safe  = @{ description = 'Safe'; items = @(@{ id = 'ts'; label = 'Test Safe'; path = 'C:\temp\test'; sideEffect = 'None'; requiresAdmin = $false }) }
                    check = @{ description = 'Check'; items = @(@{ id = 'tc'; label = 'Test Check'; path = 'C:\data\big'; reason = 'Folder besar'; recommendation = 'Cek isi'; requiresAdmin = $false }) }
                }
            }
            Mock Initialize-Rules { return ($rulesObj | ConvertTo-Json -Depth 10 | ConvertFrom-Json) }

            Mock Start-DriveScan {
                $item1 = New-ScanItem -Path "C:\temp\test" -Label "Test Safe" -SizeBytes 5120
                $item2 = New-ScanItem -Path "C:\data\big" -Label "Test Check" -SizeBytes 10240
                return New-ScanResult -Mode Quick -DriveLetter "C" -UsedBytes ([long]50GB) -FreeBytes ([long]50GB) -Items @($item1, $item2) -Errors @() -ElapsedSeconds 0.3
            }

            # Mock Start-SafeCleanup to avoid actual cleanup execution
            Mock Start-SafeCleanup { return [PSCustomObject]@{ Status = 'dry-run'; ItemsProcessed = 0 } }

            # Flow: Quick Scan (1) -> post-scan Enter -> Cleanup (5) -> Exit (8)
            $script:inputCount = 0
            Mock Read-Host {
                $script:inputCount++
                if ($script:inputCount -eq 1) { return "1" }   # Quick Scan
                if ($script:inputCount -eq 2) { return "" }    # Post-scan Enter
                if ($script:inputCount -eq 3) { return "5" }   # Bersihkan
                return "8"                                      # Keluar
            }

            $script:capturedOutput = [System.Collections.ArrayList]::new()
            Mock Write-Host {
                param([string]$Object, [string]$ForegroundColor, [switch]$NoNewline)
                if ($Object) { [void]$script:capturedOutput.Add($Object) }
            }

            Show-MainMenu

            $allOutput = $script:capturedOutput -join "`n"

            # Should display categorized sections (Req 10.3)
            $allOutput | Should -Match 'Aman Dihapus'
            $allOutput | Should -Match 'Perlu Dicek Manual'

            # Should display reclaimable space summary (Req 10.3)
            $allOutput | Should -Match 'Ringkasan Ruang'
            $allOutput | Should -Match 'Bisa diklaim kembali'

            # Should invoke Start-SafeCleanup (Req 10.1, 10.4)
            Should -Invoke Start-SafeCleanup -Times 1
        }
    }

    Context "Menu text in Bahasa Indonesia (Req 10.6)" {
        It "Cleanup menu option text is in Bahasa Indonesia" {
            Mock Read-Host { return "8" }

            $script:capturedOutput = [System.Collections.ArrayList]::new()
            Mock Write-Host {
                param([string]$Object, [string]$ForegroundColor, [switch]$NoNewline)
                if ($Object) { [void]$script:capturedOutput.Add($Object) }
            }

            Show-MainMenu

            $allOutput = $script:capturedOutput -join "`n"
            $allOutput | Should -Match 'Bersihkan'
            $allOutput | Should -Match 'Cleanup file yang aman'
        }
    }
}
