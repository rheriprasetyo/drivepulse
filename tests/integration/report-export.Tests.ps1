<#
.SYNOPSIS
    DrivePulse — Report Export Integration Tests
.DESCRIPTION
    Integration tests for the full report generation pipeline:
    - Full HTML report generation from mock scan data end-to-end
    - Full TXT report generation from mock scan data end-to-end
    - Config load -> filter -> report pipeline
#>

Describe "Report Export Integration Tests" {
    BeforeAll {
        . "$PSScriptRoot\..\..\src\scanner\types.ps1"
        . "$PSScriptRoot\..\helpers\generators.ps1"
        . "$PSScriptRoot\..\..\src\reporter\format-utils.ps1"
        . "$PSScriptRoot\..\..\src\reporter\filter.ps1"
        . "$PSScriptRoot\..\..\src\reporter\report.ps1"
        . "$PSScriptRoot\..\..\src\config\config-manager.ps1"
    }

    Context "Full HTML Report Generation" {
        It "Generates valid HTML report from mock scan data" {
            $tempDir = Join-Path $env:TEMP "drivepulse-integ-$(Get-Random)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

            try {
                $scan = [PSCustomObject]@{
                    PSTypeName = 'DrivePulse.ScanResult'
                    DriveLetter = 'C'
                    TotalBytes = [long]512GB
                    UsedBytes = [long]460GB
                    FreeBytes = [long]52GB
                    UsagePercent = 89.8
                    Items = @()
                    Errors = @()
                    ElapsedSeconds = 12.5
                }

                $items = @(
                    [PSCustomObject]@{
                        PSTypeName = 'DrivePulse.CategorizedItem'
                        Path = 'C:\Users\Heri\AppData\Local\Temp'
                        Label = 'File Sementara'
                        SizeBytes = [long]3.5GB
                        Category = 'Safe'
                        SideEffect = 'File akan dibuat ulang otomatis'
                        Reason = ''
                        Recommendation = ''
                    },
                    [PSCustomObject]@{
                        PSTypeName = 'DrivePulse.CategorizedItem'
                        Path = 'C:\Users\Heri\AppData\Local\Google\Chrome\Cache'
                        Label = 'Cache Browser'
                        SizeBytes = [long]1.2GB
                        Category = 'Safe'
                        SideEffect = 'Browser perlu rebuild cache'
                        Reason = ''
                        Recommendation = ''
                    },
                    [PSCustomObject]@{
                        PSTypeName = 'DrivePulse.CategorizedItem'
                        Path = 'C:\Users\Heri\Downloads'
                        Label = 'Downloads'
                        SizeBytes = [long]8.5GB
                        Category = 'Check'
                        SideEffect = ''
                        Reason = 'Mungkin berisi data penting'
                        Recommendation = 'Cek file terbesar, hapus installer lama'
                    },
                    [PSCustomObject]@{
                        PSTypeName = 'DrivePulse.CategorizedItem'
                        Path = 'C:\Users\Heri\AppData\Local\CapCut'
                        Label = 'CapCut Cache'
                        SizeBytes = [long]6.2GB
                        Category = 'Check'
                        SideEffect = ''
                        Reason = 'Folder aplikasi aktif'
                        Recommendation = 'Cek apakah ada project aktif'
                    }
                )

                $result = New-DriveReport -ScanResult $scan -CategorizedItems $items -Format 'HTML' -OutputPath $tempDir

                $result.Success | Should -Be $true
                Test-Path $result.FilePath | Should -Be $true

                $html = [System.IO.File]::ReadAllText($result.FilePath)

                # Verify placeholders replaced
                $html | Should -Not -Match '\{\{DATE\}\}'
                $html | Should -Not -Match '\{\{DRIVE\}\}'
                $html | Should -Not -Match '\{\{TOTAL_GB\}\}'
                $html | Should -Not -Match '\{\{USED_GB\}\}'
                $html | Should -Not -Match '\{\{USED_PCT\}\}'
                $html | Should -Not -Match '\{\{COLOR_CODE\}\}'
                $html | Should -Not -Match '\{\{SAFE_ITEMS\}\}'
                $html | Should -Not -Match '\{\{CHECK_ITEMS\}\}'
                $html | Should -Not -Match '\{\{RECOMMENDATIONS\}\}'

                # Verify content
                $html | Should -Match 'File Sementara'
                $html | Should -Match 'Cache Browser'
                $html | Should -Match 'Downloads'
                $html | Should -Match 'CapCut Cache'
                $html | Should -Match '#ffa502'  # Yellow for 89.8%
                $html | Should -Match '89\.8'

                # Verify self-contained
                $html | Should -Not -Match '<link\s+rel="stylesheet"'
                $html | Should -Not -Match '<script\s+src='
            }
            finally {
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Full TXT Report Generation" {
        It "Generates valid TXT report from mock scan data" {
            $tempDir = Join-Path $env:TEMP "drivepulse-integ-$(Get-Random)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

            try {
                $scan = [PSCustomObject]@{
                    PSTypeName = 'DrivePulse.ScanResult'
                    DriveLetter = 'D'
                    TotalBytes = [long]1TB
                    UsedBytes = [long]750GB
                    FreeBytes = [long]274GB
                    UsagePercent = 73.2
                    Items = @()
                    Errors = @()
                    ElapsedSeconds = 45.0
                }

                $items = @(
                    [PSCustomObject]@{
                        PSTypeName = 'DrivePulse.CategorizedItem'
                        Path = 'D:\Temp\OldLogs'
                        Label = 'Log Lama'
                        SizeBytes = [long]5GB
                        Category = 'Safe'
                        SideEffect = 'Log lama akan hilang'
                        Reason = ''
                        Recommendation = ''
                    },
                    [PSCustomObject]@{
                        PSTypeName = 'DrivePulse.CategorizedItem'
                        Path = 'D:\Games\Cache'
                        Label = 'Game Cache'
                        SizeBytes = [long]12GB
                        Category = 'Check'
                        SideEffect = ''
                        Reason = 'Ukuran melebihi threshold'
                        Recommendation = 'Pastikan game tidak sedang berjalan'
                    }
                )

                $result = New-DriveReport -ScanResult $scan -CategorizedItems $items -Format 'TXT' -OutputPath $tempDir

                $result.Success | Should -Be $true
                Test-Path $result.FilePath | Should -Be $true

                $content = [System.IO.File]::ReadAllText($result.FilePath)

                # Verify structure
                $content | Should -Match 'DrivePulse'
                $content | Should -Match 'D:'
                $content | Should -Match '73\.2%'
                $content | Should -Match 'Log Lama'
                $content | Should -Match 'Game Cache'
                $content | Should -Match 'Aman Dihapus'
                $content | Should -Match 'Perlu Dicek Manual'
                $content | Should -Match 'Ringkasan'

                # Verify encoding
                $bytes = [System.IO.File]::ReadAllBytes($result.FilePath)
                $bytes[0] | Should -Be 0xEF
                $bytes[1] | Should -Be 0xBB
                $bytes[2] | Should -Be 0xBF
            }
            finally {
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Config -> Filter -> Report Pipeline" {
        It "Full pipeline: config load, whitelist filter, blacklist enrich, report" {
            $tempDir = Join-Path $env:TEMP "drivepulse-integ-$(Get-Random)"
            $configDir = Join-Path $env:TEMP "drivepulse-config-integ-$(Get-Random)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null

            # Create a blacklist target directory
            $blacklistDir = Join-Path $tempDir 'blacklist-target'
            New-Item -ItemType Directory -Path $blacklistDir -Force | Out-Null

            try {
                # Setup config
                $script:ConfigDir = $configDir
                $script:ConfigPath = Join-Path $configDir 'config.json'

                $config = [PSCustomObject]@{
                    Whitelist = @('C:\Protected\Important')
                    Blacklist = @($blacklistDir)
                    LargeFolderGB = 3
                }
                Save-UserConfig -Config $config | Out-Null

                # Load config
                $loadedConfig = Get-UserConfig
                $loadedConfig.LargeFolderGB | Should -Be 3

                # Create scan items
                $scan = [PSCustomObject]@{
                    PSTypeName = 'DrivePulse.ScanResult'
                    DriveLetter = 'C'
                    TotalBytes = [long]256GB
                    UsedBytes = [long]200GB
                    FreeBytes = [long]56GB
                    UsagePercent = 78.1
                    Items = @()
                    Errors = @()
                    ElapsedSeconds = 8.0
                }

                $items = @(
                    [PSCustomObject]@{
                        PSTypeName = 'DrivePulse.CategorizedItem'
                        Path = 'C:\Protected\Important\SubDir'
                        Label = 'Protected Item'
                        SizeBytes = [long]2GB
                        Category = 'Safe'
                        SideEffect = 'test'
                        Reason = ''
                        Recommendation = ''
                    },
                    [PSCustomObject]@{
                        PSTypeName = 'DrivePulse.CategorizedItem'
                        Path = 'C:\Temp\Cache'
                        Label = 'Cache'
                        SizeBytes = [long]1GB
                        Category = 'Safe'
                        SideEffect = 'rebuild'
                        Reason = ''
                        Recommendation = ''
                    }
                )

                # Apply whitelist filter
                $filtered = @(Invoke-WhitelistFilter -CategorizedItems $items -Whitelist $loadedConfig.Whitelist)
                $filtered.Count | Should -Be 1
                $filtered[0].Label | Should -Be 'Cache'

                # Apply blacklist enrichment
                $enriched = Invoke-BlacklistEnrich -CategorizedItems $filtered -Blacklist $loadedConfig.Blacklist -Whitelist $loadedConfig.Whitelist
                $enriched.Count | Should -Be 2  # Cache + blacklist item

                # Generate report
                $result = New-DriveReport -ScanResult $scan -CategorizedItems $enriched -Format 'HTML' -OutputPath $tempDir
                $result.Success | Should -Be $true

                $html = [System.IO.File]::ReadAllText($result.FilePath)
                $html | Should -Match 'Cache'
                $html | Should -Match 'blacklist-target'
                $html | Should -Not -Match 'Protected Item'
            }
            finally {
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item $configDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
