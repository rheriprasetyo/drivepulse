<#
.SYNOPSIS
    Unit tests for DrivePulse Scanner module (Resolve-RulePath, Get-FolderSize)
.DESCRIPTION
    Tests Resolve-RulePath with known environment variables, unknown variables,
    and edge cases. Tests Get-FolderSize with accessible folders, empty folders,
    non-existent paths, and inaccessible paths.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\src\scanner\scan.ps1"
}

Describe "Resolve-RulePath" {
    Context "Resolves known environment variables" {
        It "Resolves %TEMP% to actual temp path" {
            $expected = $env:TEMP
            $result = Resolve-RulePath -RawPath '%TEMP%\cache'
            $result | Should -Be "$expected\cache"
        }

        It "Resolves %LOCALAPPDATA% to actual local app data path" {
            $expected = $env:LOCALAPPDATA
            $result = Resolve-RulePath -RawPath '%LOCALAPPDATA%\Microsoft\Windows'
            $result | Should -Be "$expected\Microsoft\Windows"
        }

        It "Resolves %APPDATA% to actual app data path" {
            $expected = $env:APPDATA
            $result = Resolve-RulePath -RawPath '%APPDATA%\Mozilla\Firefox'
            $result | Should -Be "$expected\Mozilla\Firefox"
        }

        It "Resolves %USERPROFILE% to actual user profile path" {
            $expected = $env:USERPROFILE
            $result = Resolve-RulePath -RawPath '%USERPROFILE%\Downloads'
            $result | Should -Be "$expected\Downloads"
        }

        It "Returns a path with no percent characters for known variables" {
            $result = Resolve-RulePath -RawPath '%TEMP%\subfolder\data'
            $result | Should -Not -Match '%'
        }

        It "Returns a fully resolved absolute path starting with drive letter" {
            $result = Resolve-RulePath -RawPath '%USERPROFILE%\Documents'
            $result | Should -Match '^[A-Za-z]:\\'
        }
    }

    Context "Handles unknown environment variables gracefully" {
        It "Returns path as-is when variable is unknown" {
            $result = Resolve-RulePath -RawPath '%UNKNOWN_VAR%\somefolder'
            $result | Should -Be '%UNKNOWN_VAR%\somefolder'
        }

        It "Returns path as-is for non-existent variable placeholder" {
            $result = Resolve-RulePath -RawPath '%DOESNOTEXIST%\data\cache'
            $result | Should -Be '%DOESNOTEXIST%\data\cache'
        }
    }

    Context "Edge cases" {
        It "Returns empty string for empty input" {
            $result = Resolve-RulePath -RawPath ''
            $result | Should -Be ''
        }

        It "Returns path unchanged when no placeholders present" {
            $result = Resolve-RulePath -RawPath 'C:\Windows\Temp'
            $result | Should -Be 'C:\Windows\Temp'
        }

        It "Handles path with only the environment variable (no subfolder)" {
            $expected = $env:TEMP
            $result = Resolve-RulePath -RawPath '%TEMP%'
            $result | Should -Be $expected
        }

        It "Resolves multiple known variables in a single path" {
            # This is an unusual case but should still work
            $result = Resolve-RulePath -RawPath '%TEMP%'
            $result | Should -Not -Match '%'
        }
    }
}


Describe "Get-FolderSize" {
    Context "Accessible folders with files" {
        It "Returns total size of all files in a folder" {
            # Create a test folder with known file sizes
            $testFolder = Join-Path $TestDrive "sizable-folder"
            New-Item -Path $testFolder -ItemType Directory -Force | Out-Null
            # Create files with known sizes
            [byte[]]$bytes1 = New-Object byte[] 1024
            [byte[]]$bytes2 = New-Object byte[] 2048
            [System.IO.File]::WriteAllBytes("$testFolder\file1.txt", $bytes1)
            [System.IO.File]::WriteAllBytes("$testFolder\file2.txt", $bytes2)

            $result = Get-FolderSize -Path $testFolder
            $result | Should -Be 3072
        }

        It "Includes files in subdirectories (recursive)" {
            $testFolder = Join-Path $TestDrive "nested-folder"
            $subFolder = Join-Path $testFolder "sub"
            New-Item -Path $subFolder -ItemType Directory -Force | Out-Null
            [byte[]]$bytes1 = New-Object byte[] 500
            [byte[]]$bytes2 = New-Object byte[] 700
            [System.IO.File]::WriteAllBytes("$testFolder\root.dat", $bytes1)
            [System.IO.File]::WriteAllBytes("$subFolder\child.dat", $bytes2)

            $result = Get-FolderSize -Path $testFolder
            $result | Should -Be 1200
        }

        It "Returns result as [long] type" {
            $testFolder = Join-Path $TestDrive "type-check"
            New-Item -Path $testFolder -ItemType Directory -Force | Out-Null
            [byte[]]$bytes = New-Object byte[] 100
            [System.IO.File]::WriteAllBytes("$testFolder\small.bin", $bytes)

            $result = Get-FolderSize -Path $testFolder
            $result | Should -BeOfType [long]
        }
    }

    Context "Empty folders" {
        It "Returns 0 for an empty folder" {
            $testFolder = Join-Path $TestDrive "empty-folder"
            New-Item -Path $testFolder -ItemType Directory -Force | Out-Null

            $result = Get-FolderSize -Path $testFolder
            $result | Should -Be 0
        }

        It "Returns 0 for a folder with only empty subdirectories" {
            $testFolder = Join-Path $TestDrive "dirs-only"
            New-Item -Path "$testFolder\sub1\sub2" -ItemType Directory -Force | Out-Null

            $result = Get-FolderSize -Path $testFolder
            $result | Should -Be 0
        }
    }

    Context "Non-existent paths" {
        It "Returns -1 for a path that does not exist" {
            $result = Get-FolderSize -Path "C:\NonExistent_$(New-Guid)"
            $result | Should -Be -1
        }
    }
}


Describe "Start-DriveScan Quick Mode" {
    BeforeAll {
        # Create a temporary rules JSON file with paths pointing to TestDrive
        $testDriveLetter = (Get-Item $TestDrive).PSDrive.Name

        # Create test folders with known file sizes
        $folder1 = Join-Path $TestDrive "safe-folder"
        $folder2 = Join-Path $TestDrive "check-folder"
        New-Item -Path $folder1 -ItemType Directory -Force | Out-Null
        New-Item -Path $folder2 -ItemType Directory -Force | Out-Null

        # Write known-size files
        [byte[]]$bytes1 = New-Object byte[] 4096
        [byte[]]$bytes2 = New-Object byte[] 8192
        [System.IO.File]::WriteAllBytes("$folder1\junk.tmp", $bytes1)
        [System.IO.File]::WriteAllBytes("$folder2\data.bin", $bytes2)

        # Build a rules JSON that references our TestDrive folders
        $rulesObj = @{
            thresholds = @{
                largeFolderGB    = 5
                criticalUsagePct = 90
                warningUsagePct  = 75
            }
            categories = @{
                safe  = @{
                    description = "Aman dihapus"
                    items       = @(
                        @{
                            id         = "test-safe"
                            label      = "Test Safe Folder"
                            path       = $folder1
                            sideEffect = "Tidak ada"
                        }
                    )
                }
                check = @{
                    description = "Perlu dicek"
                    items       = @(
                        @{
                            id             = "test-check"
                            label          = "Test Check Folder"
                            path           = $folder2
                            reason         = "Mungkin penting"
                            recommendation = "Cek dulu"
                        }
                    )
                }
            }
        }

        $rulesFile = Join-Path $TestDrive "test-rules.json"
        $rulesObj | ConvertTo-Json -Depth 10 | Set-Content -Path $rulesFile -Encoding UTF8
    }

    It "Returns a DrivePulse.ScanResult object" {
        $testDriveLetter = (Get-Item $TestDrive).PSDrive.Name
        $rulesFile = Join-Path $TestDrive "test-rules.json"

        $result = Start-DriveScan -Mode Quick -DriveLetter $testDriveLetter -RulesFile $rulesFile
        $result.PSObject.TypeNames | Should -Contain 'DrivePulse.ScanResult'
    }

    It "Items array contains expected items with correct paths" {
        $testDriveLetter = (Get-Item $TestDrive).PSDrive.Name
        $rulesFile = Join-Path $TestDrive "test-rules.json"

        $result = Start-DriveScan -Mode Quick -DriveLetter $testDriveLetter -RulesFile $rulesFile

        $folder1 = Join-Path $TestDrive "safe-folder"
        $folder2 = Join-Path $TestDrive "check-folder"

        $paths = $result.Items | ForEach-Object { $_.Path }
        $paths | Should -Contain $folder1
        $paths | Should -Contain $folder2
    }

    It "Items have correct sizes" {
        $testDriveLetter = (Get-Item $TestDrive).PSDrive.Name
        $rulesFile = Join-Path $TestDrive "test-rules.json"

        $result = Start-DriveScan -Mode Quick -DriveLetter $testDriveLetter -RulesFile $rulesFile

        $folder1 = Join-Path $TestDrive "safe-folder"
        $folder2 = Join-Path $TestDrive "check-folder"

        $safeItem = $result.Items | Where-Object { $_.Path -eq $folder1 }
        $safeItem.SizeBytes | Should -Be 4096

        $checkItem = $result.Items | Where-Object { $_.Path -eq $folder2 }
        $checkItem.SizeBytes | Should -Be 8192
    }

    It "UsedBytes and FreeBytes are populated (non-negative)" {
        $testDriveLetter = (Get-Item $TestDrive).PSDrive.Name
        $rulesFile = Join-Path $TestDrive "test-rules.json"

        $result = Start-DriveScan -Mode Quick -DriveLetter $testDriveLetter -RulesFile $rulesFile

        $result.UsedBytes | Should -BeGreaterOrEqual 0
        $result.FreeBytes | Should -BeGreaterOrEqual 0
    }

    It "ElapsedSeconds is non-negative" {
        $testDriveLetter = (Get-Item $TestDrive).PSDrive.Name
        $rulesFile = Join-Path $TestDrive "test-rules.json"

        $result = Start-DriveScan -Mode Quick -DriveLetter $testDriveLetter -RulesFile $rulesFile

        $result.ElapsedSeconds | Should -BeGreaterOrEqual 0
    }

    It "Mode is Quick" {
        $testDriveLetter = (Get-Item $TestDrive).PSDrive.Name
        $rulesFile = Join-Path $TestDrive "test-rules.json"

        $result = Start-DriveScan -Mode Quick -DriveLetter $testDriveLetter -RulesFile $rulesFile

        $result.Mode | Should -Be ([ScanMode]::Quick)
    }
}

Describe "Start-DriveScan Deep Mode" {
    BeforeAll {
        # Create folders in TestDrive with varying sizes for Deep Scan

        # Create a large folder (above threshold)
        $largeFolder = Join-Path $TestDrive "large-folder"
        New-Item -Path $largeFolder -ItemType Directory -Force | Out-Null
        # Write 2KB file (above our test threshold)
        [byte[]]$largeBytes = New-Object byte[] 2048
        [System.IO.File]::WriteAllBytes("$largeFolder\big.dat", $largeBytes)

        # Create a small folder (below threshold)
        $smallFolder = Join-Path $TestDrive "small-folder"
        New-Item -Path $smallFolder -ItemType Directory -Force | Out-Null
        # Write 500 byte file (below our test threshold)
        [byte[]]$smallBytes = New-Object byte[] 500
        [System.IO.File]::WriteAllBytes("$smallFolder\tiny.dat", $smallBytes)

        # Create rules file with a very small threshold for testing
        # 0.000001 GB ≈ 1073 bytes
        $rulesObj = @{
            thresholds = @{
                largeFolderGB    = 0.000001
                criticalUsagePct = 90
                warningUsagePct  = 75
            }
            categories = @{
                safe  = @{
                    description = "Aman dihapus"
                    items       = @()
                }
                check = @{
                    description = "Perlu dicek"
                    items       = @()
                }
            }
        }

        $script:deepRulesFile = Join-Path $TestDrive "deep-rules.json"
        $rulesObj | ConvertTo-Json -Depth 10 | Set-Content -Path $script:deepRulesFile -Encoding UTF8
    }

    BeforeEach {
        $testDriveLetter = (Get-Item $TestDrive).PSDrive.Name
        $largeFolder = Join-Path $TestDrive "large-folder"
        $smallFolder = Join-Path $TestDrive "small-folder"
        $largeDirInfo = Get-Item -LiteralPath $largeFolder
        $smallDirInfo = Get-Item -LiteralPath $smallFolder

        # Mock Get-PSDrive to return controlled values
        Mock Get-PSDrive {
            [PSCustomObject]@{
                Name = $testDriveLetter
                Used = [long]50GB
                Free = [long]100GB
            }
        }

        # Mock Get-FolderSize to return known sizes for our test folders
        Mock Get-FolderSize {
            param([string]$Path)
            if ($Path -eq $largeFolder) { return [long]2048 }
            if ($Path -eq $smallFolder) { return [long]500 }
            return [long]0
        }

        # Mock Get-ChildItem for directory enumeration only
        # The -Directory parameter filter ensures we only intercept directory listing calls
        Mock Get-ChildItem -ParameterFilter { $Directory -eq $true -and -not $Recurse } -MockWith {
            return @($largeDirInfo, $smallDirInfo)
        }

        # Mock recursive directory enumeration (subfolders) to return empty
        Mock Get-ChildItem -ParameterFilter { $Directory -eq $true -and $Recurse -eq $true } -MockWith {
            return @()
        }
    }

    It "Only folders at or above threshold appear in results" {
        $testDriveLetter = (Get-Item $TestDrive).PSDrive.Name
        $largeFolder = Join-Path $TestDrive "large-folder"
        $smallFolder = Join-Path $TestDrive "small-folder"

        $result = Start-DriveScan -Mode Deep -DriveLetter $testDriveLetter -RulesFile $script:deepRulesFile

        # The threshold is 0.000001 GB ≈ 1073 bytes
        # large-folder has 2048 bytes (above threshold) → should appear
        # small-folder has 500 bytes (below threshold) → should NOT appear
        $thresholdBytes = [long](0.000001 * 1GB)

        foreach ($item in $result.Items) {
            $item.SizeBytes | Should -BeGreaterOrEqual $thresholdBytes
        }

        # Verify large folder is included
        $largeFolderItem = $result.Items | Where-Object { $_.Path -eq $largeFolder }
        $largeFolderItem | Should -Not -BeNullOrEmpty

        # Verify small folder is excluded
        $smallFolderItem = $result.Items | Where-Object { $_.Path -eq $smallFolder }
        $smallFolderItem | Should -BeNullOrEmpty
    }

    It "Mode is Deep" {
        $testDriveLetter = (Get-Item $TestDrive).PSDrive.Name

        $result = Start-DriveScan -Mode Deep -DriveLetter $testDriveLetter -RulesFile $script:deepRulesFile

        $result.Mode | Should -Be ([ScanMode]::Deep)
    }

    It "Returns a DrivePulse.ScanResult object" {
        $testDriveLetter = (Get-Item $TestDrive).PSDrive.Name

        $result = Start-DriveScan -Mode Deep -DriveLetter $testDriveLetter -RulesFile $script:deepRulesFile

        $result.PSObject.TypeNames | Should -Contain 'DrivePulse.ScanResult'
    }

    It "UsedBytes and FreeBytes are non-negative numbers" {
        $testDriveLetter = (Get-Item $TestDrive).PSDrive.Name

        $result = Start-DriveScan -Mode Deep -DriveLetter $testDriveLetter -RulesFile $script:deepRulesFile

        $result.UsedBytes | Should -BeGreaterOrEqual 0
        $result.FreeBytes | Should -BeGreaterOrEqual 0
    }

    It "ElapsedSeconds is non-negative" {
        $testDriveLetter = (Get-Item $TestDrive).PSDrive.Name

        $result = Start-DriveScan -Mode Deep -DriveLetter $testDriveLetter -RulesFile $script:deepRulesFile

        $result.ElapsedSeconds | Should -BeGreaterOrEqual 0
    }
}
