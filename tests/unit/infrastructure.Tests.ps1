<#
.SYNOPSIS
    Infrastructure smoke test — verifies Pester 5.x and generators work correctly
#>

BeforeAll {
    . "$PSScriptRoot\..\helpers\generators.ps1"
}

Describe "Test Infrastructure" {
    Context "Pester 5.x is available" {
        It "Pester version is 5.x or higher" {
            $pesterModule = Get-Module Pester
            $pesterModule.Version.Major | Should -BeGreaterOrEqual 5
        }
    }

    Context "Generators are loaded" {
        It "New-RandomPath generates a path with env var placeholder" {
            $path = New-RandomPath
            $path | Should -Not -BeNullOrEmpty
            $path | Should -Match '%[A-Z]+%'
        }

        It "New-RandomScanItem returns a valid ScanItem" {
            $item = New-RandomScanItem
            $item | Should -Not -BeNull
            $item.PSObject.TypeNames | Should -Contain 'DrivePulse.ScanItem'
            $item.Path | Should -Not -BeNullOrEmpty
            $item.Label | Should -Not -BeNullOrEmpty
            $item.SizeBytes | Should -BeGreaterOrEqual 0
        }

        It "New-RandomRulesJson generates valid JSON" {
            $json = New-RandomRulesJson
            $json | Should -Not -BeNullOrEmpty
            { $json | ConvertFrom-Json } | Should -Not -Throw
            $parsed = $json | ConvertFrom-Json
            $parsed.thresholds | Should -Not -BeNull
            $parsed.categories | Should -Not -BeNull
        }

        It "New-RandomInvalidJson generates invalid JSON" {
            $invalid = New-RandomInvalidJson
            # Most strategies produce non-empty strings that fail JSON parsing
            # Empty string is also invalid JSON for ConvertFrom-Json
            { $invalid | ConvertFrom-Json -ErrorAction Stop } | Should -Throw
        }
    }
}
