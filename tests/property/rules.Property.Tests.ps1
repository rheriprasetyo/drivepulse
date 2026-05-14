<#
.SYNOPSIS
    DrivePulse — Rules Parsing Property-Based Tests
.DESCRIPTION
    Property-based tests for the rules parsing module verifying:
    - Property 10: Invalid JSON Graceful Handling
    - Property 11: Rules File Round-Trip Parsing
.NOTES
    Uses 20 iterations per property test for faster execution.
    Uses generators from tests/helpers/generators.ps1
#>

Describe "Rules Parsing Property Tests" {
    BeforeAll {
        # Use absolute paths for reliable resolution
        $script:CategorizeModule = Join-Path $PSScriptRoot "..\..\src\scanner\categorize.ps1" | Resolve-Path
        . "$PSScriptRoot\..\..\src\scanner\categorize.ps1"
        . "$PSScriptRoot\..\helpers\generators.ps1"
    }

    Context "Property 10: Invalid JSON Graceful Handling" {
        <#
            **Validates: Requirements 10.2**
            For any invalid JSON string, Initialize-Rules does not throw an unhandled
            exception and produces a descriptive error message.
        #>

        It "Invalid JSON files cause graceful termination with descriptive error message" {
            1..20 | ForEach-Object {
                $invalidJson = New-RandomInvalidJson
                $tempFile = Join-Path $TestDrive "invalid_rules_${_}.json"
                Set-Content -Path $tempFile -Value $invalidJson -Encoding UTF8

                # Build a script that uses absolute paths (not $PSScriptRoot which won't resolve in child process)
                $categorizeModulePath = $script:CategorizeModule.Path
                $scriptContent = @"
`$ErrorActionPreference = 'Stop'
. '$categorizeModulePath'
Initialize-Rules -RulesFile '$tempFile'
"@
                $scriptFile = Join-Path $TestDrive "run_init_${_}.ps1"
                Set-Content -Path $scriptFile -Value $scriptContent -Encoding UTF8

                $output = & pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scriptFile 2>&1
                $exitCode = $LASTEXITCODE

                # The process should have exited with code 1 (graceful termination, not a crash)
                $exitCode | Should -Be 1

                # Output should contain a descriptive error indicator (Bahasa Indonesia error messages)
                $outputStr = ($output | Out-String)
                ($outputStr -match '❌|error|gagal|rusak|tidak valid|tidak ditemukan|tidak lengkap') | Should -BeTrue -Because "Output should contain error description. Got: $outputStr"
            }
        }
    }

    Context "Property 11: Rules File Round-Trip Parsing" {
        <#
            **Validates: Requirements 10.4**
            For any valid rules JSON structure, parsing and re-serializing produces
            semantically equivalent output.
        #>

        It "Valid rules JSON round-trips correctly through Initialize-Rules" {
            1..20 | ForEach-Object {
                $rulesJson = New-RandomRulesJson
                $tempFile = Join-Path $TestDrive "valid_rules_${_}.json"
                Set-Content -Path $tempFile -Value $rulesJson -Encoding UTF8

                # Parse with Initialize-Rules (valid JSON should succeed without exit)
                $parsed = Initialize-Rules -RulesFile $tempFile

                # Parsed result should not be null
                $parsed | Should -Not -BeNullOrEmpty

                # Re-serialize
                $reserialized = $parsed | ConvertTo-Json -Depth 10

                # Parse the reserialized version
                $reparsed = $reserialized | ConvertFrom-Json

                # Compare key structural fields for semantic equivalence
                $reparsed.thresholds.largeFolderGB | Should -Be $parsed.thresholds.largeFolderGB
                $reparsed.thresholds.criticalUsagePct | Should -Be $parsed.thresholds.criticalUsagePct
                $reparsed.thresholds.warningUsagePct | Should -Be $parsed.thresholds.warningUsagePct

                # Compare safe items count
                $originalSafeCount = @($parsed.categories.safe.items).Count
                $reparsedSafeCount = @($reparsed.categories.safe.items).Count
                $reparsedSafeCount | Should -Be $originalSafeCount

                # Compare check items count
                $originalCheckCount = @($parsed.categories.check.items).Count
                $reparsedCheckCount = @($reparsed.categories.check.items).Count
                $reparsedCheckCount | Should -Be $originalCheckCount

                # Compare category descriptions
                $reparsed.categories.safe.description | Should -Be $parsed.categories.safe.description
                $reparsed.categories.check.description | Should -Be $parsed.categories.check.description

                # Compare individual safe item fields
                for ($i = 0; $i -lt $originalSafeCount; $i++) {
                    $origItem = @($parsed.categories.safe.items)[$i]
                    $reItem = @($reparsed.categories.safe.items)[$i]
                    $reItem.id | Should -Be $origItem.id
                    $reItem.label | Should -Be $origItem.label
                    $reItem.path | Should -Be $origItem.path
                    $reItem.sideEffect | Should -Be $origItem.sideEffect
                }

                # Compare individual check item fields
                for ($i = 0; $i -lt $originalCheckCount; $i++) {
                    $origItem = @($parsed.categories.check.items)[$i]
                    $reItem = @($reparsed.categories.check.items)[$i]
                    $reItem.id | Should -Be $origItem.id
                    $reItem.label | Should -Be $origItem.label
                    $reItem.path | Should -Be $origItem.path
                    $reItem.reason | Should -Be $origItem.reason
                    $reItem.recommendation | Should -Be $origItem.recommendation
                }
            }
        }
    }
}
