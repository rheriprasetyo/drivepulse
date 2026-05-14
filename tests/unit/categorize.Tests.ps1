BeforeAll {
    . "$PSScriptRoot\..\..\src\scanner\categorize.ps1"
}

Describe "Initialize-Rules" {
    Context "Valid rules file" {
        It "Returns parsed rules object with thresholds and categories" {
            $rulesFile = "$PSScriptRoot\..\..\config\default-rules.json"
            $result = Initialize-Rules -RulesFile $rulesFile

            $result | Should -Not -BeNullOrEmpty
            $result.thresholds | Should -Not -BeNullOrEmpty
            $result.categories | Should -Not -BeNullOrEmpty
            $result.thresholds.largeFolderGB | Should -BeGreaterThan 0
        }
    }

    Context "Missing file" {
        It "Exits with code 1 when file does not exist" {
            $missingPath = Join-Path $TestDrive "nonexistent.json"
            $srcPath = (Resolve-Path "$PSScriptRoot\..\..\src\scanner\categorize.ps1").Path

            $result = & pwsh -NoProfile -Command ". '$srcPath'; Initialize-Rules -RulesFile '$missingPath'" 2>&1
            $LASTEXITCODE | Should -Be 1
        }
    }

    Context "Invalid JSON" {
        It "Exits with code 1 when file contains invalid JSON" {
            $invalidFile = Join-Path $TestDrive "invalid.json"
            Set-Content -Path $invalidFile -Value "not valid json {{{" -Encoding UTF8
            $srcPath = (Resolve-Path "$PSScriptRoot\..\..\src\scanner\categorize.ps1").Path

            $result = & pwsh -NoProfile -Command ". '$srcPath'; Initialize-Rules -RulesFile '$invalidFile'" 2>&1
            $LASTEXITCODE | Should -Be 1
        }
    }
}

Describe "Get-ItemCategory" {
    BeforeAll {
        # Build a test rules object in-memory (no file I/O needed)
        $script:testRules = @{
            thresholds = @{ largeFolderGB = 5 }
            categories = @{
                safe = @{
                    items = @(
                        @{ id = "temp"; label = "Temp Files"; path = "C:\TestSafe\Cache"; sideEffect = "Cache akan dibuat ulang otomatis"; requiresAdmin = $false }
                        @{ id = "admin-safe"; label = "Admin Folder"; path = "C:\AdminOnly"; sideEffect = "Perlu admin"; requiresAdmin = $true }
                    )
                }
                check = @{
                    items = @(
                        @{ id = "docs"; label = "Documents"; path = "C:\TestCheck\Docs"; reason = "Mungkin ada file penting"; recommendation = "Cek isi folder dulu" }
                        @{ id = "large"; label = "Large Folders"; path = "*"; reason = "Folder besar"; recommendation = "Review" }
                    )
                }
            }
        }
    }

    It "Returns Safe with correct sideEffect for known safe path" {
        $item = New-ScanItem -Path "C:\TestSafe\Cache" -Label "Cache" -SizeBytes 1GB
        $result = Get-ItemCategory -ScanItem $item -Rules $script:testRules -IsAdmin $false

        $result.Category | Should -Be ([ItemCategory]::Safe)
        $result.SideEffect | Should -Be "Cache akan dibuat ulang otomatis"
    }

    It "Returns Check with correct reason/recommendation for known check path" {
        $item = New-ScanItem -Path "C:\TestCheck\Docs" -Label "Docs" -SizeBytes 2GB
        $result = Get-ItemCategory -ScanItem $item -Rules $script:testRules -IsAdmin $false

        $result.Category | Should -Be ([ItemCategory]::Check)
        $result.Reason | Should -Be "Mungkin ada file penting"
        $result.Recommendation | Should -Be "Cek isi folder dulu"
    }

    It "Returns Check with generic reason for unknown large folder" {
        # 6GB > 5GB threshold
        $item = New-ScanItem -Path "C:\Unknown\BigFolder" -Label "Big" -SizeBytes ([long]6GB)
        $result = Get-ItemCategory -ScanItem $item -Rules $script:testRules -IsAdmin $false

        $result.Category | Should -Be ([ItemCategory]::Check)
        $result.Reason | Should -Be "Folder besar tanpa aturan spesifik"
    }

    It "Returns Unknown for small unmatched folder" {
        # 1GB < 5GB threshold
        $item = New-ScanItem -Path "C:\Unknown\SmallFolder" -Label "Small" -SizeBytes 1GB
        $result = Get-ItemCategory -ScanItem $item -Rules $script:testRules -IsAdmin $false

        $result.Category | Should -Be ([ItemCategory]::Unknown)
    }

    It "Sets RequiresAdmin=true when rule has requiresAdmin and not admin" {
        $item = New-ScanItem -Path "C:\AdminOnly" -Label "Admin" -SizeBytes 500MB
        $result = Get-ItemCategory -ScanItem $item -Rules $script:testRules -IsAdmin $false

        $result.RequiresAdmin | Should -Be $true
        $result.Category | Should -Be ([ItemCategory]::Safe)
    }

    It "Sets RequiresAdmin=false when running as admin" {
        $item = New-ScanItem -Path "C:\AdminOnly" -Label "Admin" -SizeBytes 500MB
        $result = Get-ItemCategory -ScanItem $item -Rules $script:testRules -IsAdmin $true

        $result.RequiresAdmin | Should -Be $false
    }

    It "Path matching is case-insensitive" {
        $item = New-ScanItem -Path "c:\testsafe\cache" -Label "Cache Lower" -SizeBytes 1GB
        $result = Get-ItemCategory -ScanItem $item -Rules $script:testRules -IsAdmin $false

        $result.Category | Should -Be ([ItemCategory]::Safe)
    }
}
