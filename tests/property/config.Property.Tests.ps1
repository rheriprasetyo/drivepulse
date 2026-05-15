<#
.SYNOPSIS
    DrivePulse — Config Manager Property-Based Tests
.DESCRIPTION
    Property-based tests for config manager verifying:
    - Property 8: Invalid JSON Config Falls Back to Defaults
    - Property 9: Config Save/Load Round Trip
    - Property 10: Config Validation
    - Property 11: Whitelist Path Matching
    - Property 12: Invalid Path Entries Are Skipped
    - Property 13: Whitelist Priority Over Blacklist
    - Property 14: Effective Threshold Resolution
.NOTES
    Uses 100 iterations per property test.
    Uses generators from tests/helpers/generators.ps1
#>

Describe "Config Manager Property Tests" {
    BeforeAll {
        . "$PSScriptRoot\..\..\src\scanner\types.ps1"
        . "$PSScriptRoot\..\helpers\generators.ps1"
        . "$PSScriptRoot\..\..\src\config\config-manager.ps1"
        . "$PSScriptRoot\..\..\src\reporter\filter.ps1"
    }

    Context "Property 8: Invalid JSON Config Falls Back to Defaults" {
        It "Random invalid JSON strings produce default config" {
            $testDir = Join-Path $env:TEMP "drivepulse-config-test-$(Get-Random)"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null

            try {
                1..100 | ForEach-Object {
                    $invalidJson = New-RandomInvalidJson
                    $configPath = Join-Path $testDir 'config.json'
                    [System.IO.File]::WriteAllText($configPath, $invalidJson)

                    # Override script-level variables for testing
                    $script:ConfigDir = $testDir
                    $script:ConfigPath = $configPath

                    $result = Get-UserConfig

                    $result.Whitelist.Count | Should -Be 0
                    $result.Blacklist.Count | Should -Be 0
                    $result.LargeFolderGB | Should -Be 5
                }
            }
            finally {
                Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Property 9: Config Save/Load Round Trip" {
        It "Save then load produces identical config" {
            $testDir = Join-Path $env:TEMP "drivepulse-config-test-$(Get-Random)"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null

            try {
                $script:ConfigDir = $testDir
                $script:ConfigPath = Join-Path $testDir 'config.json'

                1..100 | ForEach-Object {
                    $config = New-RandomUserConfig

                    $saveResult = Save-UserConfig -Config $config
                    $saveResult.Success | Should -Be $true

                    $loaded = Get-UserConfig

                    $loaded.LargeFolderGB | Should -Be ([math]::Round($config.LargeFolderGB, 2))

                    # Whitelist: only valid paths are stored
                    $validWhitelist = @($config.Whitelist | Where-Object { $_ -match '^[A-Za-z]:\\' })
                    $loaded.Whitelist.Count | Should -Be $validWhitelist.Count

                    # Blacklist: only valid paths are stored
                    $validBlacklist = @($config.Blacklist | Where-Object { $_ -match '^[A-Za-z]:\\' })
                    $loaded.Blacklist.Count | Should -Be $validBlacklist.Count
                }
            }
            finally {
                Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Property 10: Config Validation" {
        It "Rejects configs with largeFolderGB outside 0.1-100" {
            1..100 | ForEach-Object {
                $invalidThreshold = New-RandomInvalidThreshold
                # Skip null and array values that can't be cast
                if ($null -eq $invalidThreshold -or $invalidThreshold -is [System.Array]) { return }

                $config = [PSCustomObject]@{
                    Whitelist = @()
                    Blacklist = @()
                    LargeFolderGB = $invalidThreshold
                }

                $result = Save-UserConfig -Config $config

                # Should fail for values outside range or non-numeric
                try {
                    $numVal = [double]$invalidThreshold
                    if ($numVal -lt 0.1 -or $numVal -gt 100) {
                        $result.Success | Should -Be $false
                    }
                }
                catch {
                    $result.Success | Should -Be $false
                }
            }
        }

        It "Rejects configs with whitelist > 100 entries" {
            $config = [PSCustomObject]@{
                Whitelist = @(1..101 | ForEach-Object { "C:\Path$_" })
                Blacklist = @()
                LargeFolderGB = 5
            }

            $result = Save-UserConfig -Config $config
            $result.Success | Should -Be $false
        }

        It "Rejects configs with blacklist > 50 entries" {
            $config = [PSCustomObject]@{
                Whitelist = @()
                Blacklist = @(1..51 | ForEach-Object { "C:\Path$_" })
                LargeFolderGB = 5
            }

            $result = Save-UserConfig -Config $config
            $result.Success | Should -Be $false
        }

        It "Rejects blacklist entries > 260 chars" {
            $longPath = "C:\" + ("A" * 258)
            $config = [PSCustomObject]@{
                Whitelist = @()
                Blacklist = @($longPath)
                LargeFolderGB = 5
            }

            $result = Save-UserConfig -Config $config
            $result.Success | Should -Be $false
        }

        It "Accepts valid configs" {
            $testDir = Join-Path $env:TEMP "drivepulse-config-test-$(Get-Random)"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null

            try {
                $script:ConfigDir = $testDir
                $script:ConfigPath = Join-Path $testDir 'config.json'

                1..50 | ForEach-Object {
                    $config = New-RandomUserConfig
                    $result = Save-UserConfig -Config $config
                    $result.Success | Should -Be $true
                }
            }
            finally {
                Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Property 11: Whitelist Path Matching" {
        It "Items are excluded iff path matches or is subdirectory of whitelist entry" {
            1..100 | ForEach-Object {
                $wlPath = 'C:\Users\Test\Documents'
                $whitelist = @($wlPath)

                # Item that matches exactly
                $exactMatch = [PSCustomObject]@{
                    PSTypeName = 'DrivePulse.CategorizedItem'
                    Path = 'C:\Users\Test\Documents'
                    Label = 'Exact'
                    SizeBytes = 1024
                    Category = 'Safe'
                    SideEffect = ''
                    Reason = ''
                    Recommendation = ''
                }

                # Item that is subdirectory
                $subDir = [PSCustomObject]@{
                    PSTypeName = 'DrivePulse.CategorizedItem'
                    Path = 'C:\Users\Test\Documents\SubFolder'
                    Label = 'SubDir'
                    SizeBytes = 2048
                    Category = 'Safe'
                    SideEffect = ''
                    Reason = ''
                    Recommendation = ''
                }

                # Item that does NOT match
                $noMatch = [PSCustomObject]@{
                    PSTypeName = 'DrivePulse.CategorizedItem'
                    Path = 'C:\Users\Test\Downloads'
                    Label = 'NoMatch'
                    SizeBytes = 4096
                    Category = 'Safe'
                    SideEffect = ''
                    Reason = ''
                    Recommendation = ''
                }

                $items = @($exactMatch, $subDir, $noMatch)
                $filtered = @(Invoke-WhitelistFilter -CategorizedItems $items -Whitelist $whitelist)

                $filtered.Count | Should -Be 1
                $filtered[0].Label | Should -Be 'NoMatch'
            }
        }

        It "Case-insensitive matching works" {
            $whitelist = @('C:\USERS\TEST')
            $item = [PSCustomObject]@{
                PSTypeName = 'DrivePulse.CategorizedItem'
                Path = 'c:\users\test'
                Label = 'CaseTest'
                SizeBytes = 1024
                Category = 'Safe'
                SideEffect = ''
                Reason = ''
                Recommendation = ''
            }

            $filtered = Invoke-WhitelistFilter -CategorizedItems @($item) -Whitelist $whitelist
            $filtered.Count | Should -Be 0
        }
    }

    Context "Property 12: Invalid Path Entries Are Skipped" {
        It "Invalid whitelist entries are skipped, valid entries processed" {
            1..100 | ForEach-Object {
                $validPath = New-RandomWindowsPath
                $invalidPath = New-RandomInvalidPath

                $whitelist = @($invalidPath, $validPath)

                $item = [PSCustomObject]@{
                    PSTypeName = 'DrivePulse.CategorizedItem'
                    Path = $validPath
                    Label = 'TestItem'
                    SizeBytes = 1024
                    Category = 'Safe'
                    SideEffect = ''
                    Reason = ''
                    Recommendation = ''
                }

                $otherItem = [PSCustomObject]@{
                    PSTypeName = 'DrivePulse.CategorizedItem'
                    Path = 'D:\Other\Path'
                    Label = 'OtherItem'
                    SizeBytes = 2048
                    Category = 'Safe'
                    SideEffect = ''
                    Reason = ''
                    Recommendation = ''
                }

                $filtered = @(Invoke-WhitelistFilter -CategorizedItems @($item, $otherItem) -Whitelist $whitelist)

                # The item matching validPath should be filtered out
                $filtered.Count | Should -Be 1
                $filtered[0].Label | Should -Be 'OtherItem'
            }
        }
    }

    Context "Property 13: Whitelist Priority Over Blacklist" {
        It "Path in both whitelist and blacklist is NOT added to cleanup" {
            1..100 | ForEach-Object {
                $sharedPath = New-RandomWindowsPath
                $whitelist = @($sharedPath)
                $blacklist = @($sharedPath)

                $items = @()
                $result = Invoke-BlacklistEnrich -CategorizedItems $items -Blacklist $blacklist -Whitelist $whitelist

                # The shared path should NOT be added because whitelist takes priority
                $matchingItems = @($result | Where-Object { $_.Path -eq $sharedPath })
                $matchingItems.Count | Should -Be 0
            }
        }
    }

    Context "Property 14: Effective Threshold Resolution" {
        It "Returns user config value when valid (0.1-100)" {
            1..100 | ForEach-Object {
                $validValue = [math]::Round((Get-Random -Minimum 1 -Maximum 1000) / 10, 2)
                if ($validValue -gt 100) { $validValue = 100 }
                if ($validValue -lt 0.1) { $validValue = 0.1 }

                $userConfig = [PSCustomObject]@{ LargeFolderGB = $validValue }
                $defaultRules = [PSCustomObject]@{ thresholds = [PSCustomObject]@{ largeFolderGB = 5 } }

                $result = Get-EffectiveThreshold -UserConfig $userConfig -DefaultRules $defaultRules
                $result | Should -Be $validValue
            }
        }

        It "Returns default when user config value is invalid" {
            1..100 | ForEach-Object {
                $invalidValue = New-RandomInvalidThreshold
                if ($null -eq $invalidValue) { return }
                if ($invalidValue -is [System.Array]) { return }

                try {
                    $numVal = [double]$invalidValue
                    if ($numVal -ge 0.1 -and $numVal -le 100) { return }
                } catch { }

                $userConfig = [PSCustomObject]@{ LargeFolderGB = $invalidValue }
                $defaultRules = [PSCustomObject]@{ thresholds = [PSCustomObject]@{ largeFolderGB = 7 } }

                $result = Get-EffectiveThreshold -UserConfig $userConfig -DefaultRules $defaultRules
                $result | Should -Be 7
            }
        }

        It "Is idempotent - same input produces same result" {
            1..50 | ForEach-Object {
                $config = New-RandomUserConfig
                $defaultRules = [PSCustomObject]@{ thresholds = [PSCustomObject]@{ largeFolderGB = 5 } }

                $result1 = Get-EffectiveThreshold -UserConfig $config -DefaultRules $defaultRules
                $result2 = Get-EffectiveThreshold -UserConfig $config -DefaultRules $defaultRules

                $result1 | Should -Be $result2
            }
        }
    }
}
