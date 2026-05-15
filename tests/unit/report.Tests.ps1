<#
.SYNOPSIS
    DrivePulse — Report Generator Unit Tests
.DESCRIPTION
    Unit tests for report generation error handling:
    - Error returned for non-existent OutputPath
    - No partial file created on failure
    - Correct filename pattern for HTML and TXT
    - TXT file uses UTF-8 BOM + CRLF encoding
#>

Describe "Report Generator Unit Tests" {
    BeforeAll {
        . "$PSScriptRoot\..\..\src\scanner\types.ps1"
        . "$PSScriptRoot\..\helpers\generators.ps1"
        . "$PSScriptRoot\..\..\src\reporter\format-utils.ps1"
        . "$PSScriptRoot\..\..\src\reporter\filter.ps1"
        . "$PSScriptRoot\..\..\src\reporter\report.ps1"

        $script:TestScanResult = [PSCustomObject]@{
            PSTypeName = 'DrivePulse.ScanResult'
            DriveLetter = 'C'
            TotalBytes = [long]500GB
            UsedBytes = [long]400GB
            FreeBytes = [long]100GB
            UsagePercent = 80.0
            Items = @()
            Errors = @()
            ElapsedSeconds = 5.2
        }

        $script:TestItems = @(
            [PSCustomObject]@{
                PSTypeName = 'DrivePulse.CategorizedItem'
                Path = 'C:\Temp\Cache'
                Label = 'Browser Cache'
                SizeBytes = [long]2GB
                Category = 'Safe'
                SideEffect = 'Browser rebuild cache'
                Reason = ''
                Recommendation = ''
            },
            [PSCustomObject]@{
                PSTypeName = 'DrivePulse.CategorizedItem'
                Path = 'C:\Users\Downloads'
                Label = 'Downloads'
                SizeBytes = [long]5GB
                Category = 'Check'
                SideEffect = ''
                Reason = 'Mungkin berisi data penting'
                Recommendation = 'Cek file terbesar'
            }
        )
    }

    Context "Error Handling" {
        It "Returns error for non-existent OutputPath" {
            $result = New-DriveReport -ScanResult $script:TestScanResult -CategorizedItems $script:TestItems -Format 'HTML' -OutputPath 'Z:\NonExistent\Path'

            $result.Success | Should -Be $false
            $result.Error | Should -Match 'Lokasi output tidak ditemukan'
            $result.FilePath | Should -BeNullOrEmpty
        }

        It "No partial file created on failure (non-existent path)" {
            $fakePath = "C:\NonExistent_$(Get-Random)\SubDir"
            $result = New-DriveReport -ScanResult $script:TestScanResult -CategorizedItems $script:TestItems -Format 'HTML' -OutputPath $fakePath

            $result.Success | Should -Be $false
            $date = Get-Date -Format 'yyyy-MM-dd'
            $possibleFile = Join-Path $fakePath "DrivePulse-Report-$date.html"
            Test-Path $possibleFile | Should -Be $false
        }
    }

    Context "Filename Pattern" {
        It "HTML report saves with correct filename pattern" {
            $tempDir = Join-Path $env:TEMP "drivepulse-test-$(Get-Random)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

            try {
                $result = New-DriveReport -ScanResult $script:TestScanResult -CategorizedItems $script:TestItems -Format 'HTML' -OutputPath $tempDir

                $result.Success | Should -Be $true
                $result.FilePath | Should -Match 'DrivePulse-Report-\d{4}-\d{2}-\d{2}\.html$'
                $result.Format | Should -Be 'HTML'
                Test-Path $result.FilePath | Should -Be $true
            }
            finally {
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "TXT report saves with correct filename pattern" {
            $tempDir = Join-Path $env:TEMP "drivepulse-test-$(Get-Random)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

            try {
                $result = New-DriveReport -ScanResult $script:TestScanResult -CategorizedItems $script:TestItems -Format 'TXT' -OutputPath $tempDir

                $result.Success | Should -Be $true
                $result.FilePath | Should -Match 'DrivePulse-Report-\d{4}-\d{2}-\d{2}\.txt$'
                $result.Format | Should -Be 'TXT'
                Test-Path $result.FilePath | Should -Be $true
            }
            finally {
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "TXT Encoding" {
        It "TXT file uses UTF-8 BOM + CRLF encoding" {
            $tempDir = Join-Path $env:TEMP "drivepulse-test-$(Get-Random)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

            try {
                $result = New-DriveReport -ScanResult $script:TestScanResult -CategorizedItems $script:TestItems -Format 'TXT' -OutputPath $tempDir

                $result.Success | Should -Be $true

                # Check BOM
                $bytes = [System.IO.File]::ReadAllBytes($result.FilePath)
                $bytes[0] | Should -Be 0xEF
                $bytes[1] | Should -Be 0xBB
                $bytes[2] | Should -Be 0xBF

                # Check CRLF line endings
                $content = [System.IO.File]::ReadAllText($result.FilePath)
                $content | Should -Match "`r`n"
                # Should not have bare LF without CR
                $withoutCRLF = $content -replace "`r`n", ''
                $withoutCRLF | Should -Not -Match "`n"
            }
            finally {
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Empty Categories" {
        It "HTML report shows empty category message" {
            $tempDir = Join-Path $env:TEMP "drivepulse-test-$(Get-Random)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

            try {
                $emptyItems = @()
                $result = New-DriveReport -ScanResult $script:TestScanResult -CategorizedItems $emptyItems -Format 'HTML' -OutputPath $tempDir

                $result.Success | Should -Be $true
                $html = [System.IO.File]::ReadAllText($result.FilePath)
                $html | Should -Match 'Tidak ada item dalam kategori ini'
            }
            finally {
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It "TXT report shows empty category message" {
            $tempDir = Join-Path $env:TEMP "drivepulse-test-$(Get-Random)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

            try {
                $emptyItems = @()
                $result = New-DriveReport -ScanResult $script:TestScanResult -CategorizedItems $emptyItems -Format 'TXT' -OutputPath $tempDir

                $result.Success | Should -Be $true
                $content = [System.IO.File]::ReadAllText($result.FilePath)
                $content | Should -Match 'Tidak ada item dalam kategori ini'
            }
            finally {
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
