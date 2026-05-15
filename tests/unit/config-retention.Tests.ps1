<#
.SYNOPSIS
    DrivePulse — Config Manager Retention Period Unit Tests
.DESCRIPTION
    Unit tests for backupRetentionDays and stagingRetentionDays configuration
    fields added to the config manager.
    Validates: Requirements 6.4, 6.5, 9.4
#>

Describe "Config Manager - Retention Period Settings" {
    BeforeAll {
        . "$PSScriptRoot\..\..\src\config\config-manager.ps1"
    }

    BeforeEach {
        $script:testDir = Join-Path $env:TEMP "drivepulse-config-retention-test-$(Get-Random)"
        New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null
        $script:ConfigDir = $script:testDir
        $script:ConfigPath = Join-Path $script:testDir 'config.json'
    }

    AfterEach {
        Remove-Item $script:testDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context "Default values" {
        It "Returns default 7 for backupRetentionDays when config file does not exist" {
            $config = Get-UserConfig
            $config.BackupRetentionDays | Should -Be 7
        }

        It "Returns default 7 for stagingRetentionDays when config file does not exist" {
            $config = Get-UserConfig
            $config.StagingRetentionDays | Should -Be 7
        }

        It "Returns default 7 when retention fields are not present in config JSON" {
            $json = '{"whitelist":[],"blacklist":[],"largeFolderGB":5}'
            [System.IO.File]::WriteAllText($script:ConfigPath, $json)

            $config = Get-UserConfig
            $config.BackupRetentionDays | Should -Be 7
            $config.StagingRetentionDays | Should -Be 7
        }
    }

    Context "Valid retention values (Req 6.4, 9.4)" {
        It "Accepts backupRetentionDays = 1 (minimum)" {
            $json = '{"whitelist":[],"blacklist":[],"largeFolderGB":5,"backupRetentionDays":1,"stagingRetentionDays":7}'
            [System.IO.File]::WriteAllText($script:ConfigPath, $json)

            $config = Get-UserConfig
            $config.BackupRetentionDays | Should -Be 1
        }

        It "Accepts backupRetentionDays = 90 (maximum)" {
            $json = '{"whitelist":[],"blacklist":[],"largeFolderGB":5,"backupRetentionDays":90,"stagingRetentionDays":7}'
            [System.IO.File]::WriteAllText($script:ConfigPath, $json)

            $config = Get-UserConfig
            $config.BackupRetentionDays | Should -Be 90
        }

        It "Accepts stagingRetentionDays = 1 (minimum)" {
            $json = '{"whitelist":[],"blacklist":[],"largeFolderGB":5,"backupRetentionDays":7,"stagingRetentionDays":1}'
            [System.IO.File]::WriteAllText($script:ConfigPath, $json)

            $config = Get-UserConfig
            $config.StagingRetentionDays | Should -Be 1
        }

        It "Accepts stagingRetentionDays = 90 (maximum)" {
            $json = '{"whitelist":[],"blacklist":[],"largeFolderGB":5,"backupRetentionDays":7,"stagingRetentionDays":90}'
            [System.IO.File]::WriteAllText($script:ConfigPath, $json)

            $config = Get-UserConfig
            $config.StagingRetentionDays | Should -Be 90
        }

        It "Accepts mid-range value 30" {
            $json = '{"whitelist":[],"blacklist":[],"largeFolderGB":5,"backupRetentionDays":30,"stagingRetentionDays":45}'
            [System.IO.File]::WriteAllText($script:ConfigPath, $json)

            $config = Get-UserConfig
            $config.BackupRetentionDays | Should -Be 30
            $config.StagingRetentionDays | Should -Be 45
        }
    }

    Context "Invalid retention values fall back to default 7 (Req 6.5, 9.4)" {
        It "Falls back to 7 when backupRetentionDays = 0" {
            $json = '{"whitelist":[],"blacklist":[],"largeFolderGB":5,"backupRetentionDays":0,"stagingRetentionDays":7}'
            [System.IO.File]::WriteAllText($script:ConfigPath, $json)

            $config = Get-UserConfig
            $config.BackupRetentionDays | Should -Be 7
        }

        It "Falls back to 7 when backupRetentionDays = 91" {
            $json = '{"whitelist":[],"blacklist":[],"largeFolderGB":5,"backupRetentionDays":91,"stagingRetentionDays":7}'
            [System.IO.File]::WriteAllText($script:ConfigPath, $json)

            $config = Get-UserConfig
            $config.BackupRetentionDays | Should -Be 7
        }

        It "Falls back to 7 when stagingRetentionDays = -5" {
            $json = '{"whitelist":[],"blacklist":[],"largeFolderGB":5,"backupRetentionDays":7,"stagingRetentionDays":-5}'
            [System.IO.File]::WriteAllText($script:ConfigPath, $json)

            $config = Get-UserConfig
            $config.StagingRetentionDays | Should -Be 7
        }

        It "Falls back to 7 when stagingRetentionDays = 100" {
            $json = '{"whitelist":[],"blacklist":[],"largeFolderGB":5,"backupRetentionDays":7,"stagingRetentionDays":100}'
            [System.IO.File]::WriteAllText($script:ConfigPath, $json)

            $config = Get-UserConfig
            $config.StagingRetentionDays | Should -Be 7
        }

        It "Falls back to 7 when value is a string" {
            $json = '{"whitelist":[],"blacklist":[],"largeFolderGB":5,"backupRetentionDays":"abc","stagingRetentionDays":"xyz"}'
            [System.IO.File]::WriteAllText($script:ConfigPath, $json)

            $config = Get-UserConfig
            $config.BackupRetentionDays | Should -Be 7
            $config.StagingRetentionDays | Should -Be 7
        }

        It "Falls back to 7 when value is a decimal (non-integer)" {
            $json = '{"whitelist":[],"blacklist":[],"largeFolderGB":5,"backupRetentionDays":7.5,"stagingRetentionDays":14.9}'
            [System.IO.File]::WriteAllText($script:ConfigPath, $json)

            $config = Get-UserConfig
            $config.BackupRetentionDays | Should -Be 7
            $config.StagingRetentionDays | Should -Be 7
        }
    }

    Context "Warning display on invalid configuration (Req 6.5)" {
        It "Displays warning when backupRetentionDays is out of range" {
            $json = '{"whitelist":[],"blacklist":[],"largeFolderGB":5,"backupRetentionDays":200,"stagingRetentionDays":7}'
            [System.IO.File]::WriteAllText($script:ConfigPath, $json)

            $output = Get-UserConfig 3>&1
            $warnings = @($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
            $warnings.Count | Should -BeGreaterThan 0
            $warnings[0].Message | Should -BeLike '*backupRetentionDays*'
        }

        It "Displays warning when stagingRetentionDays is non-numeric" {
            $json = '{"whitelist":[],"blacklist":[],"largeFolderGB":5,"backupRetentionDays":7,"stagingRetentionDays":"invalid"}'
            [System.IO.File]::WriteAllText($script:ConfigPath, $json)

            $output = Get-UserConfig 3>&1
            $warnings = @($output | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
            $warnings.Count | Should -BeGreaterThan 0
            $warnings[0].Message | Should -BeLike '*stagingRetentionDays*'
        }
    }

    Context "Save-UserConfig preserves retention fields" {
        It "Saves and loads backupRetentionDays correctly" {
            $config = [PSCustomObject]@{
                Whitelist            = @()
                Blacklist            = @()
                LargeFolderGB        = 5
                BackupRetentionDays  = 30
                StagingRetentionDays = 14
            }

            $result = Save-UserConfig -Config $config
            $result.Success | Should -Be $true

            $loaded = Get-UserConfig
            $loaded.BackupRetentionDays | Should -Be 30
            $loaded.StagingRetentionDays | Should -Be 14
        }

        It "Saves default 7 when retention fields are not provided" {
            $config = [PSCustomObject]@{
                Whitelist     = @()
                Blacklist     = @()
                LargeFolderGB = 5
            }

            $result = Save-UserConfig -Config $config
            $result.Success | Should -Be $true

            $loaded = Get-UserConfig
            $loaded.BackupRetentionDays | Should -Be 7
            $loaded.StagingRetentionDays | Should -Be 7
        }

        It "Saves default 7 when retention fields have invalid values" {
            $config = [PSCustomObject]@{
                Whitelist            = @()
                Blacklist            = @()
                LargeFolderGB        = 5
                BackupRetentionDays  = 999
                StagingRetentionDays = -10
            }

            $result = Save-UserConfig -Config $config
            $result.Success | Should -Be $true

            $loaded = Get-UserConfig
            $loaded.BackupRetentionDays | Should -Be 7
            $loaded.StagingRetentionDays | Should -Be 7
        }
    }
}
