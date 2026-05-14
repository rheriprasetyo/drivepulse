<#
.SYNOPSIS
    DrivePulse — Full Scan Integration Tests
.DESCRIPTION
    Integration tests for the complete scan flow:
    - Quick Scan with mock directory structure
    - Deep Scan with threshold filtering
    - Rules file loading from actual config/default-rules.json
    - End-to-end: scan → categorize → verify output structure
.NOTES
    Requirements: 1.1, 2.1, 3.1, 9.4, 10.1
#>

BeforeAll {
    . "$PSScriptRoot\..\..\src\scanner\scan.ps1"
    . "$PSScriptRoot\..\..\src\scanner\categorize.ps1"
}

Describe "Integration: Quick Scan Flow" {
    BeforeAll {
        # Create mock directory structure in TestDrive
        $script:safeFolder = Join-Path $TestDrive "safe-cache"
        $script:checkFolder = Join-Path $TestDrive "check-downloads"
        New-Item -Path $script:safeFolder -ItemType Directory -Force | Out-Null
        New-Item -Path $script:checkFolder -ItemType Directory -Force | Out-Null

        # Create files with known sizes
        [byte[]]$safeBytes = New-Object byte[] 5120
        [byte[]]$checkBytes = New-Object byte[] 10240
        [System.IO.File]::WriteAllBytes("$($script:safeFolder)\cache.tmp", $safeBytes)
        [System.IO.File]::WriteAllBytes("$($script:checkFolder)\installer.exe", $checkBytes)

        # Build rules JSON referencing TestDrive folders
        $script:rulesObj = @{
            '_schema'  = 'drivepulse-rules-v1'
            version    = '1.0.0'
            thresholds = @{
                largeFolderGB    = 5
                criticalUsagePct = 90
                warningUsagePct  = 75
            }
            categories = @{
                safe  = @{
                    description = 'Aman dihapus'
                    items       = @(
                        @{
                            id         = 'test-safe'
                            label      = 'Cache Sementara'
                            path       = $script:safeFolder
                            sideEffect = 'Cache akan dibuat ulang'
                            requiresAdmin = $false
                        }
                    )
                }
                check = @{
                    description = 'Perlu dicek'
                    items       = @(
                        @{
                            id             = 'test-check'
                            label          = 'Folder Unduhan'
                            path           = $script:checkFolder
                            reason         = 'Mungkin ada file penting'
                            recommendation = 'Cek file terbesar'
                        }
                    )
                }
            }
            whitelist  = @()
            blacklist  = @()
        }

        $script:rulesFile = Join-Path $TestDrive "integration-rules.json"
        $script:rulesObj | ConvertTo-Json -Depth 10 | Set-Content -Path $script:rulesFile -Encoding UTF8
    }

    It "Quick Scan returns ScanResult with correct items" {
        $result = Start-DriveScan -Mode Quick -RulesFile $script:rulesFile

        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.TypeNames | Should -Contain 'DrivePulse.ScanResult'
        $result.Mode | Should -Be ([ScanMode]::Quick)
        $result.Items.Count | Should -Be 2
    }

    It "Quick Scan items have correct sizes" {
        $result = Start-DriveScan -Mode Quick -RulesFile $script:rulesFile

        $safeItem = $result.Items | Where-Object { $_.Path -eq $script:safeFolder }
        $safeItem.SizeBytes | Should -Be 5120

        $checkItem = $result.Items | Where-Object { $_.Path -eq $script:checkFolder }
        $checkItem.SizeBytes | Should -Be 10240
    }

    It "Quick Scan populates drive info" {
        $result = Start-DriveScan -Mode Quick -RulesFile $script:rulesFile

        $result.UsedBytes | Should -BeGreaterOrEqual 0
        $result.FreeBytes | Should -BeGreaterOrEqual 0
        $result.TotalBytes | Should -BeGreaterThan 0
        $result.UsagePercent | Should -BeGreaterOrEqual 0
        $result.UsagePercent | Should -BeLessOrEqual 100
    }

    It "Quick Scan records elapsed time" {
        $result = Start-DriveScan -Mode Quick -RulesFile $script:rulesFile

        $result.ElapsedSeconds | Should -BeGreaterOrEqual 0
    }
}

Describe "Integration: Deep Scan with Threshold Filtering" {
    BeforeAll {
        # Create folders with varying sizes
        $script:bigFolder = Join-Path $TestDrive "big-project"
        $script:smallFolder = Join-Path $TestDrive "tiny-folder"
        New-Item -Path $script:bigFolder -ItemType Directory -Force | Out-Null
        New-Item -Path $script:smallFolder -ItemType Directory -Force | Out-Null

        # Big folder: 3KB
        [byte[]]$bigBytes = New-Object byte[] 3072
        [System.IO.File]::WriteAllBytes("$($script:bigFolder)\data.bin", $bigBytes)

        # Small folder: 100 bytes
        [byte[]]$smallBytes = New-Object byte[] 100
        [System.IO.File]::WriteAllBytes("$($script:smallFolder)\tiny.txt", $smallBytes)

        # Rules with very small threshold (0.000001 GB ≈ 1073 bytes)
        $script:deepRulesObj = @{
            '_schema'  = 'drivepulse-rules-v1'
            version    = '1.0.0'
            thresholds = @{
                largeFolderGB    = 0.000001
                criticalUsagePct = 90
                warningUsagePct  = 75
            }
            categories = @{
                safe  = @{ description = 'Safe'; items = @() }
                check = @{ description = 'Check'; items = @() }
            }
            whitelist  = @()
            blacklist  = @()
        }

        $script:deepRulesFile = Join-Path $TestDrive "deep-integration-rules.json"
        $script:deepRulesObj | ConvertTo-Json -Depth 10 | Set-Content -Path $script:deepRulesFile -Encoding UTF8
    }

    BeforeEach {
        $testDriveLetter = (Get-Item $TestDrive).PSDrive.Name
        $bigFolder = $script:bigFolder
        $smallFolder = $script:smallFolder
        $bigDirInfo = Get-Item -LiteralPath $bigFolder
        $smallDirInfo = Get-Item -LiteralPath $smallFolder

        Mock Get-PSDrive {
            [PSCustomObject]@{
                Name = $testDriveLetter
                Used = [long]50GB
                Free = [long]100GB
            }
        }

        Mock Get-FolderSize {
            param([string]$Path)
            if ($Path -eq $bigFolder) { return [long]3072 }
            if ($Path -eq $smallFolder) { return [long]100 }
            return [long]0
        }

        Mock Get-ChildItem -ParameterFilter { $Directory -eq $true -and -not $Recurse } -MockWith {
            return @($bigDirInfo, $smallDirInfo)
        }

        Mock Get-ChildItem -ParameterFilter { $Directory -eq $true -and $Recurse -eq $true } -MockWith {
            return @()
        }
    }

    It "Deep Scan only includes folders above threshold" {
        $testDriveLetter = (Get-Item $TestDrive).PSDrive.Name

        $result = Start-DriveScan -Mode Deep -DriveLetter $testDriveLetter -RulesFile $script:deepRulesFile

        # Threshold is ~1073 bytes. Big folder (3072) should be included, small (100) should not.
        $bigItem = $result.Items | Where-Object { $_.Path -eq $script:bigFolder }
        $bigItem | Should -Not -BeNullOrEmpty

        $smallItem = $result.Items | Where-Object { $_.Path -eq $script:smallFolder }
        $smallItem | Should -BeNullOrEmpty
    }

    It "Deep Scan returns correct mode" {
        $testDriveLetter = (Get-Item $TestDrive).PSDrive.Name

        $result = Start-DriveScan -Mode Deep -DriveLetter $testDriveLetter -RulesFile $script:deepRulesFile

        $result.Mode | Should -Be ([ScanMode]::Deep)
    }
}

Describe "Integration: Rules File Loading" {
    It "Loads actual config/default-rules.json successfully" {
        $actualRulesFile = "$PSScriptRoot\..\..\config\default-rules.json"

        $rules = Initialize-Rules -RulesFile $actualRulesFile

        $rules | Should -Not -BeNullOrEmpty
        $rules.thresholds | Should -Not -BeNullOrEmpty
        $rules.thresholds.largeFolderGB | Should -BeGreaterThan 0
        $rules.categories | Should -Not -BeNullOrEmpty
        $rules.categories.safe.items.Count | Should -BeGreaterThan 0
        $rules.categories.check.items.Count | Should -BeGreaterThan 0
    }

    It "Rules file has expected schema fields" {
        $actualRulesFile = "$PSScriptRoot\..\..\config\default-rules.json"

        $rules = Initialize-Rules -RulesFile $actualRulesFile

        $rules.thresholds.criticalUsagePct | Should -BeGreaterThan 0
        $rules.thresholds.warningUsagePct | Should -BeGreaterThan 0
        $rules.categories.safe.description | Should -Not -BeNullOrEmpty
        $rules.categories.check.description | Should -Not -BeNullOrEmpty
    }
}

Describe "Integration: End-to-End Scan → Categorize → Verify" {
    BeforeAll {
        # Create a complete mock environment
        $script:e2eFolder1 = Join-Path $TestDrive "e2e-safe"
        $script:e2eFolder2 = Join-Path $TestDrive "e2e-check"
        $script:e2eFolder3 = Join-Path $TestDrive "e2e-unknown"
        New-Item -Path $script:e2eFolder1 -ItemType Directory -Force | Out-Null
        New-Item -Path $script:e2eFolder2 -ItemType Directory -Force | Out-Null
        New-Item -Path $script:e2eFolder3 -ItemType Directory -Force | Out-Null

        [byte[]]$bytes1 = New-Object byte[] 2048
        [byte[]]$bytes2 = New-Object byte[] 4096
        [byte[]]$bytes3 = New-Object byte[] 512
        [System.IO.File]::WriteAllBytes("$($script:e2eFolder1)\file.tmp", $bytes1)
        [System.IO.File]::WriteAllBytes("$($script:e2eFolder2)\file.dat", $bytes2)
        [System.IO.File]::WriteAllBytes("$($script:e2eFolder3)\file.txt", $bytes3)

        # Rules: folder1 = safe, folder2 = check, folder3 = not in rules (unknown, below threshold)
        $script:e2eRules = @{
            '_schema'  = 'drivepulse-rules-v1'
            version    = '1.0.0'
            thresholds = @{
                largeFolderGB    = 5
                criticalUsagePct = 90
                warningUsagePct  = 75
            }
            categories = @{
                safe  = @{
                    description = 'Aman'
                    items       = @(
                        @{
                            id         = 'e2e-safe'
                            label      = 'E2E Safe'
                            path       = $script:e2eFolder1
                            sideEffect = 'Tidak ada efek'
                            requiresAdmin = $false
                        }
                    )
                }
                check = @{
                    description = 'Cek'
                    items       = @(
                        @{
                            id             = 'e2e-check'
                            label          = 'E2E Check'
                            path           = $script:e2eFolder2
                            reason         = 'Perlu verifikasi'
                            recommendation = 'Cek dulu'
                        }
                    )
                }
            }
            whitelist  = @()
            blacklist  = @()
        }

        $script:e2eRulesFile = Join-Path $TestDrive "e2e-rules.json"
        $script:e2eRules | ConvertTo-Json -Depth 10 | Set-Content -Path $script:e2eRulesFile -Encoding UTF8
    }

    It "Full flow: scan → categorize produces correct categories" {
        # Step 1: Scan
        $scanResult = Start-DriveScan -Mode Quick -RulesFile $script:e2eRulesFile

        $scanResult | Should -Not -BeNullOrEmpty
        $scanResult.Items.Count | Should -BeGreaterOrEqual 2

        # Step 2: Load rules
        $rules = Initialize-Rules -RulesFile $script:e2eRulesFile

        # Step 3: Categorize
        $categorized = Get-AllCategories -ScanResult $scanResult -Rules $rules -IsAdmin $false

        $categorized | Should -Not -BeNullOrEmpty

        # Verify safe item
        $safeItem = $categorized | Where-Object { $_.Path -eq $script:e2eFolder1 }
        $safeItem | Should -Not -BeNullOrEmpty
        $safeItem.Category | Should -Be ([ItemCategory]::Safe)
        $safeItem.SideEffect | Should -Be 'Tidak ada efek'

        # Verify check item
        $checkItem = $categorized | Where-Object { $_.Path -eq $script:e2eFolder2 }
        $checkItem | Should -Not -BeNullOrEmpty
        $checkItem.Category | Should -Be ([ItemCategory]::Check)
        $checkItem.Reason | Should -Be 'Perlu verifikasi'
    }

    It "CategorizedItem objects have correct PSTypeName" {
        $scanResult = Start-DriveScan -Mode Quick -RulesFile $script:e2eRulesFile
        $rules = Initialize-Rules -RulesFile $script:e2eRulesFile
        $categorized = Get-AllCategories -ScanResult $scanResult -Rules $rules -IsAdmin $false

        foreach ($item in $categorized) {
            $item.PSObject.TypeNames | Should -Contain 'DrivePulse.CategorizedItem'
        }
    }

    It "ScanResult items have correct PSTypeName" {
        $scanResult = Start-DriveScan -Mode Quick -RulesFile $script:e2eRulesFile

        foreach ($item in $scanResult.Items) {
            $item.PSObject.TypeNames | Should -Contain 'DrivePulse.ScanItem'
        }
    }
}
