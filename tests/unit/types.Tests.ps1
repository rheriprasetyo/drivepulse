<#
.SYNOPSIS
    Unit tests for DrivePulse type factory functions
.DESCRIPTION
    Tests New-ScanItem, New-CategorizedItem, New-ScanResult, and New-ScanError
    factory functions for correct PSTypeName, required fields, and computed values.
#>

BeforeAll {
    . "$PSScriptRoot\..\helpers\generators.ps1"
}

Describe "New-ScanItem" {
    Context "Returns object with correct PSTypeName and all required fields" {
        It "Has PSTypeName 'DrivePulse.ScanItem'" {
            $item = New-ScanItem -Path 'C:\Temp\cache' -Label 'Cache Browser' -SizeBytes 1024
            $item.PSObject.TypeNames | Should -Contain 'DrivePulse.ScanItem'
        }

        It "Contains Path, Label, SizeBytes, and IsAccessible fields" {
            $item = New-ScanItem -Path 'C:\Users\test\Downloads' -Label 'Folder Unduhan' -SizeBytes 5000000
            $item.Path | Should -Be 'C:\Users\test\Downloads'
            $item.Label | Should -Be 'Folder Unduhan'
            $item.SizeBytes | Should -Be 5000000
            $item.IsAccessible | Should -BeTrue
        }

        It "Defaults IsAccessible to true when not specified" {
            $item = New-ScanItem -Path 'C:\Data' -Label 'Data' -SizeBytes 100
            $item.IsAccessible | Should -BeTrue
        }

        It "Allows IsAccessible to be set to false" {
            $item = New-ScanItem -Path 'C:\Restricted' -Label 'Restricted' -SizeBytes 0 -IsAccessible $false
            $item.IsAccessible | Should -BeFalse
        }

        It "Handles zero-byte size" {
            $item = New-ScanItem -Path 'C:\Empty' -Label 'Empty Folder' -SizeBytes 0
            $item.SizeBytes | Should -Be 0
        }

        It "Handles large byte values" {
            $item = New-ScanItem -Path 'C:\Large' -Label 'Large Folder' -SizeBytes 500GB
            $item.SizeBytes | Should -Be 500GB
        }
    }
}

Describe "New-CategorizedItem" {
    Context "Returns object with correct PSTypeName and category metadata" {
        BeforeAll {
            $script:scanItem = New-ScanItem -Path 'C:\Temp\cache' -Label 'Cache Browser' -SizeBytes 2048000
        }

        It "Has PSTypeName 'DrivePulse.CategorizedItem'" {
            $result = New-CategorizedItem -ScanItem $script:scanItem -Category ([ItemCategory]::Safe)
            $result.PSObject.TypeNames | Should -Contain 'DrivePulse.CategorizedItem'
        }

        It "Copies Path, Label, and SizeBytes from ScanItem" {
            $result = New-CategorizedItem -ScanItem $script:scanItem -Category ([ItemCategory]::Safe)
            $result.Path | Should -Be 'C:\Temp\cache'
            $result.Label | Should -Be 'Cache Browser'
            $result.SizeBytes | Should -Be 2048000
        }

        It "Sets Category to Safe" {
            $result = New-CategorizedItem -ScanItem $script:scanItem -Category ([ItemCategory]::Safe)
            $result.Category | Should -Be ([ItemCategory]::Safe)
        }

        It "Sets Category to Check" {
            $result = New-CategorizedItem -ScanItem $script:scanItem -Category ([ItemCategory]::Check)
            $result.Category | Should -Be ([ItemCategory]::Check)
        }

        It "Sets Category to Unknown" {
            $result = New-CategorizedItem -ScanItem $script:scanItem -Category ([ItemCategory]::Unknown)
            $result.Category | Should -Be ([ItemCategory]::Unknown)
        }

        It "Includes SideEffect for Safe items" {
            $result = New-CategorizedItem -ScanItem $script:scanItem -Category ([ItemCategory]::Safe) -SideEffect 'Browser perlu rebuild cache'
            $result.SideEffect | Should -Be 'Browser perlu rebuild cache'
        }

        It "Includes Reason and Recommendation for Check items" {
            $result = New-CategorizedItem -ScanItem $script:scanItem -Category ([ItemCategory]::Check) -Reason 'Mungkin berisi data penting' -Recommendation 'Periksa isi folder'
            $result.Reason | Should -Be 'Mungkin berisi data penting'
            $result.Recommendation | Should -Be 'Periksa isi folder'
        }

        It "Defaults RequiresAdmin to false" {
            $result = New-CategorizedItem -ScanItem $script:scanItem -Category ([ItemCategory]::Safe)
            $result.RequiresAdmin | Should -BeFalse
        }

        It "Allows RequiresAdmin to be set to true" {
            $result = New-CategorizedItem -ScanItem $script:scanItem -Category ([ItemCategory]::Check) -RequiresAdmin $true
            $result.RequiresAdmin | Should -BeTrue
        }
    }
}

Describe "New-ScanResult" {
    Context "Correctly computes TotalBytes and UsagePercent" {
        It "Computes TotalBytes as UsedBytes + FreeBytes" {
            $result = New-ScanResult -Mode ([ScanMode]::Quick) -DriveLetter 'C' `
                -UsedBytes 80GB -FreeBytes 20GB `
                -Items @() -Errors @() -ElapsedSeconds 2.5
            $result.TotalBytes | Should -Be (80GB + 20GB)
        }

        It "Computes UsagePercent correctly (80%)" {
            $result = New-ScanResult -Mode ([ScanMode]::Quick) -DriveLetter 'C' `
                -UsedBytes 80GB -FreeBytes 20GB `
                -Items @() -Errors @() -ElapsedSeconds 2.5
            $result.UsagePercent | Should -Be 80.0
        }

        It "Computes UsagePercent correctly (50%)" {
            $result = New-ScanResult -Mode ([ScanMode]::Deep) -DriveLetter 'D' `
                -UsedBytes 250GB -FreeBytes 250GB `
                -Items @() -Errors @() -ElapsedSeconds 10.0
            $result.UsagePercent | Should -Be 50.0
        }

        It "Rounds UsagePercent to 1 decimal place" {
            # 1/3 = 33.333...% should round to 33.3
            $result = New-ScanResult -Mode ([ScanMode]::Quick) -DriveLetter 'C' `
                -UsedBytes 1 -FreeBytes 2 `
                -Items @() -Errors @() -ElapsedSeconds 1.0
            $result.UsagePercent | Should -Be 33.3
        }

        It "Has PSTypeName 'DrivePulse.ScanResult'" {
            $result = New-ScanResult -Mode ([ScanMode]::Quick) -DriveLetter 'C' `
                -UsedBytes 100GB -FreeBytes 50GB `
                -Items @() -Errors @() -ElapsedSeconds 5.0
            $result.PSObject.TypeNames | Should -Contain 'DrivePulse.ScanResult'
        }

        It "Contains Mode, DriveLetter, and ElapsedSeconds" {
            $result = New-ScanResult -Mode ([ScanMode]::Deep) -DriveLetter 'D' `
                -UsedBytes 100GB -FreeBytes 50GB `
                -Items @() -Errors @() -ElapsedSeconds 15.3
            $result.Mode | Should -Be ([ScanMode]::Deep)
            $result.DriveLetter | Should -Be 'D'
            $result.ElapsedSeconds | Should -Be 15.3
        }

        It "Contains Items and Errors arrays" {
            $items = @(
                (New-ScanItem -Path 'C:\Temp' -Label 'Temp' -SizeBytes 1024)
            )
            $errors = @(
                (New-ScanError -Path 'C:\Restricted' -Message 'Access Denied')
            )
            $result = New-ScanResult -Mode ([ScanMode]::Quick) -DriveLetter 'C' `
                -UsedBytes 100GB -FreeBytes 50GB `
                -Items $items -Errors $errors -ElapsedSeconds 3.0
            $result.Items.Count | Should -Be 1
            $result.Errors.Count | Should -Be 1
        }

        It "Contains a Timestamp in expected format" {
            $result = New-ScanResult -Mode ([ScanMode]::Quick) -DriveLetter 'C' `
                -UsedBytes 100GB -FreeBytes 50GB `
                -Items @() -Errors @() -ElapsedSeconds 1.0
            $result.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
        }
    }
}

Describe "New-ScanError" {
    Context "Returns object with Path, Message, and Timestamp" {
        It "Has PSTypeName 'DrivePulse.ScanError'" {
            $error = New-ScanError -Path 'C:\System Volume Information' -Message 'Access Denied'
            $error.PSObject.TypeNames | Should -Contain 'DrivePulse.ScanError'
        }

        It "Contains the correct Path" {
            $error = New-ScanError -Path 'C:\$Recycle.Bin' -Message 'Permission denied'
            $error.Path | Should -Be 'C:\$Recycle.Bin'
        }

        It "Contains the correct Message" {
            $error = New-ScanError -Path 'C:\Restricted' -Message 'UnauthorizedAccessException'
            $error.Message | Should -Be 'UnauthorizedAccessException'
        }

        It "Contains a Timestamp in expected format" {
            $error = New-ScanError -Path 'C:\Test' -Message 'Error'
            $error.Timestamp | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
        }

        It "Timestamp is close to current time" {
            $before = Get-Date
            $error = New-ScanError -Path 'C:\Test' -Message 'Error'
            $after = Get-Date
            $ts = [datetime]::ParseExact($error.Timestamp, 'yyyy-MM-dd HH:mm:ss', $null)
            $ts | Should -BeGreaterOrEqual $before.AddSeconds(-1)
            $ts | Should -BeLessOrEqual $after.AddSeconds(1)
        }
    }
}
