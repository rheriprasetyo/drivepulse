# Implementation Plan: Core Scanner

## Overview

Refactor the monolithic `scripts/analyze.ps1` into a modular architecture with type definitions, scanner, categorizer, and CLI modules. Implement Quick Scan and Deep Scan modes with rule-based categorization and an interactive Bahasa Indonesia CLI. All modules communicate via structured `[PSCustomObject]` data types and are tested with Pester 5.x unit tests and custom property-based tests.

## Tasks

- [ ] 1. Implement type definitions and test infrastructure
  - [ ] 1.1 Implement type definitions in `src/scanner/types.ps1`
    - Replace the existing skeleton with the full type system: `ScanMode` enum, `ItemCategory` enum, and factory functions `New-ScanItem`, `New-CategorizedItem`, `New-ScanResult`, `New-ScanError`
    - Each factory function returns a `[PSCustomObject]` with the correct `PSTypeName`
    - `New-ScanResult` computes `TotalBytes` and `UsagePercent` from `UsedBytes` and `FreeBytes`
    - _Requirements: 9.1, 9.2, 1.3_

  - [ ] 1.2 Set up Pester 5.x test infrastructure in `tests/`
    - Create `tests/unit/` and `tests/property/` and `tests/integration/` and `tests/helpers/` directories
    - Create `tests/helpers/generators.ps1` with random data generators: `New-RandomPath`, `New-RandomScanItem`, `New-RandomRulesJson`, `New-RandomInvalidJson`
    - Ensure Pester 5.x can discover and run tests from the `tests/` directory
    - _Requirements: 9.1, 9.2_

  - [ ]* 1.3 Write unit tests for type factories in `tests/unit/types.Tests.ps1`
    - Test `New-ScanItem` returns object with correct PSTypeName and all required fields
    - Test `New-CategorizedItem` returns object with correct PSTypeName and category metadata
    - Test `New-ScanResult` correctly computes TotalBytes and UsagePercent
    - Test `New-ScanError` returns object with Path, Message, and Timestamp
    - _Requirements: 1.3, 9.1_

- [ ] 2. Implement scanner module
  - [ ] 2.1 Implement `Resolve-RulePath` helper in `src/scanner/scan.ps1`
    - Replace `%TEMP%`, `%LOCALAPPDATA%`, `%APPDATA%`, `%USERPROFILE%` placeholders with actual environment variable values
    - Return a fully resolved absolute path with no `%` characters remaining
    - Handle unknown environment variables gracefully (return path as-is)
    - _Requirements: 1.4, 10.3_

  - [ ] 2.2 Implement `Get-FolderSize` helper in `src/scanner/scan.ps1`
    - Recursively calculate total size of a folder using `Get-ChildItem -Recurse -Force` and `Measure-Object`
    - Return -1 if the folder is inaccessible (Access Denied)
    - Catch `UnauthorizedAccessException` and general exceptions gracefully
    - _Requirements: 1.3, 6.1_

  - [ ] 2.3 Implement `Start-DriveScan` Quick mode in `src/scanner/scan.ps1`
    - Import `types.ps1` at the top of the module
    - Load rules file and extract all paths from `categories.safe.items` and `categories.check.items`
    - Resolve environment variables in each path using `Resolve-RulePath`
    - For each resolved path: check existence, measure size with `Get-FolderSize`, create `ScanItem`
    - Record `ScanError` for inaccessible folders, mark item as `IsAccessible = $false`
    - Get drive info via `Get-PSDrive` for used/free bytes
    - Measure elapsed time and return `ScanResult` object
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 6.1, 6.2_

  - [ ] 2.4 Implement `Start-DriveScan` Deep mode in `src/scanner/scan.ps1`
    - Get drive info via `Get-PSDrive` for used/free bytes
    - Load rules file and extract `thresholds.largeFolderGB` value
    - Enumerate top-level directories of the drive root
    - Recursively traverse subfolders with `Get-ChildItem -Directory -Recurse`
    - For each folder, calculate size; if size >= threshold, add as `ScanItem`
    - Record `ScanError` for Access Denied folders, continue scanning
    - Support a progress callback parameter for reporting current path and percentage
    - Measure elapsed time and return `ScanResult` object
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 6.1, 6.2_

  - [ ]* 2.5 Write property tests for scanner in `tests/property/scan.Property.Tests.ps1`
    - **Property 1: Environment Variable Path Resolution** — For any path with %TEMP%, %LOCALAPPDATA%, %APPDATA%, %USERPROFILE%, `Resolve-RulePath` returns a string with no `%` characters starting with a valid drive letter
    - **Validates: Requirements 1.4**
    - **Property 5: Access Denied Recovery** — For any mix of accessible/inaccessible paths, returned items + errors count equals total paths attempted
    - **Validates: Requirements 6.1**
    - **Property 6: Access Denied Error Logging** — For any inaccessible folder, `ScanResult.Errors` contains a `ScanError` with the exact path and non-empty message
    - **Validates: Requirements 6.2**
    - Use generators from `tests/helpers/generators.ps1`, minimum 100 iterations per property
    - _Requirements: 1.4, 6.1, 6.2_

  - [ ]* 2.6 Write unit tests for scanner in `tests/unit/scan.Tests.ps1`
    - Test `Resolve-RulePath` with known environment variables
    - Test `Get-FolderSize` with accessible and inaccessible mock paths (using Pester TestDrive)
    - Test Quick Scan returns correct structure with mocked file system
    - Test Deep Scan respects threshold filtering
    - Test drive info (UsedBytes, FreeBytes) is populated
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 2.1, 2.3_

- [ ] 3. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 4. Implement categorizer module
  - [ ] 4.1 Implement `Initialize-Rules` in `src/scanner/categorize.ps1`
    - Import `types.ps1` at the top of the module
    - Check if rules file exists with `Test-Path`; if missing, display error in Bahasa Indonesia and exit with code 1
    - Parse JSON with `ConvertFrom-Json`; if invalid JSON, display descriptive error and exit with code 1
    - Validate required structure (thresholds, categories keys present)
    - Return parsed rules object on success
    - _Requirements: 10.1, 10.2, 10.3, 10.4_

  - [ ] 4.2 Implement `Get-ItemCategory` in `src/scanner/categorize.ps1`
    - Normalize item path for comparison (resolve env vars, case-insensitive matching)
    - Search `rules.categories.safe.items` for path match; if found, return `CategorizedItem` with Category=Safe and sideEffect from rule
    - Search `rules.categories.check.items` for path match; if found, return `CategorizedItem` with Category=Check, reason and recommendation from rule
    - If no match and size >= largeFolderGB threshold, return `CategorizedItem` with Category=Check and reason "Folder besar tanpa aturan spesifik"
    - If no match and size < threshold, return `CategorizedItem` with Category=Unknown
    - If rule has `requiresAdmin=true` and `IsAdmin=$false`, set `RequiresAdmin=$true` on the item
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

  - [ ] 4.3 Implement `Get-AllCategories` in `src/scanner/categorize.ps1`
    - Iterate over all items in `ScanResult.Items`
    - Call `Get-ItemCategory` for each item
    - Return array of `CategorizedItem` objects
    - _Requirements: 3.1_

  - [ ]* 4.4 Write property tests for categorizer in `tests/property/categorize.Property.Tests.ps1`
    - **Property 4: Categorization Produces Valid Output with Correct Metadata** — For any valid ScanItem and rules, `Get-ItemCategory` returns a CategorizedItem with valid Category (Safe/Check/Unknown) and correct metadata fields per category
    - **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5**
    - **Property 3: Deep Scan Threshold Filtering** — For any set of items with varying sizes and positive threshold, only items >= threshold appear in results
    - **Validates: Requirements 2.3**
    - Use generators from `tests/helpers/generators.ps1`, minimum 100 iterations per property
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 2.3_

  - [ ]* 4.5 Write property tests for rules parsing in `tests/property/rules.Property.Tests.ps1`
    - **Property 10: Invalid JSON Graceful Handling** — For any invalid JSON string, `Initialize-Rules` does not throw an unhandled exception and produces a descriptive error message
    - **Validates: Requirements 10.2**
    - **Property 11: Rules File Round-Trip Parsing** — For any valid rules JSON structure, parsing and re-serializing produces semantically equivalent output
    - **Validates: Requirements 10.4**
    - Use `New-RandomInvalidJson` and `New-RandomRulesJson` generators, minimum 100 iterations per property
    - _Requirements: 10.2, 10.4_

  - [ ]* 4.6 Write unit tests for categorizer in `tests/unit/categorize.Tests.ps1`
    - Test `Initialize-Rules` with valid rules file
    - Test `Initialize-Rules` with missing file (should exit gracefully)
    - Test `Initialize-Rules` with invalid JSON (should exit gracefully)
    - Test `Get-ItemCategory` with known safe path → returns Safe with correct sideEffect
    - Test `Get-ItemCategory` with known check path → returns Check with correct reason/recommendation
    - Test `Get-ItemCategory` with unknown large folder → returns Check with generic reason
    - Test `Get-ItemCategory` with requiresAdmin rule when not admin
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 10.1, 10.2_

- [ ] 5. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 6. Implement CLI module
  - [ ] 6.1 Implement `Format-Size` and `Show-DriveStatus` in `src/ui/cli.ps1`
    - Import scanner and categorizer modules at the top
    - `Format-Size`: return "X.X GB" for bytes >= 1GB, "X MB" for bytes < 1GB
    - `Show-DriveStatus`: display drive usage bar with color coding (red >= 90%, yellow >= 75%, green < 75%), total/used/free in GB, usage percentage
    - _Requirements: 8.1, 8.2, 5.3_

  - [ ] 6.2 Implement `Show-ScanResults` and `Show-ErrorSummary` in `src/ui/cli.ps1`
    - `Show-ScanResults`: display "[MODE: DRY-RUN — tidak ada file yang dihapus]" label, group items into "Aman Dihapus" (green) and "Perlu Dicek Manual" (yellow) sections, show label + size + metadata per item, show summary totals
    - `Show-ErrorSummary`: display count of skipped folders, offer to show full list on user request
    - All text in Bahasa Indonesia with casual tone
    - _Requirements: 4.1, 4.3, 8.3, 8.4, 8.5, 8.6, 6.3, 5.1_

  - [ ] 6.3 Implement `Show-Progress` in `src/ui/cli.ps1`
    - For Quick Scan: display name of current location being scanned
    - For Deep Scan: display progress bar with percentage and current folder path
    - Display total elapsed time when scan completes
    - _Requirements: 7.1, 7.2, 7.3_

  - [ ] 6.4 Implement `Show-MainMenu` with full navigation in `src/ui/cli.ps1`
    - Display main menu: [1] Quick Scan, [2] Deep Scan, [3] Bantuan, [4] Keluar
    - Handle user input: validate choice, show friendly error for invalid input, re-display menu
    - On scan selection: call `Start-DriveScan`, show progress, call `Get-AllCategories`, display results
    - On Bantuan: show help text in Bahasa Indonesia
    - On Keluar: exit gracefully
    - Use ASCII-compatible box-drawing characters and emoji that render in PowerShell 5.1
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_

  - [ ]* 6.5 Write property tests for formatting in `tests/property/format.Property.Tests.ps1`
    - **Property 7: Size Formatting Correctness** — For any byte value >= 0, `Format-Size` returns " GB" suffix when >= 1GB and " MB" suffix when < 1GB, with valid numeric portion
    - **Validates: Requirements 8.2**
    - **Property 9: Summary Totals Invariant** — For any array of CategorizedItems, total safe space equals sum of SizeBytes where Category=Safe, total check space equals sum where Category=Check
    - **Validates: Requirements 8.6**
    - Use `New-RandomScanItem` generator, minimum 100 iterations per property
    - _Requirements: 8.2, 8.6_

  - [ ]* 6.6 Write unit tests for CLI in `tests/unit/format.Tests.ps1`
    - Test `Format-Size` with 0 bytes, 500MB, 1GB, 100GB values
    - Test `Show-DriveStatus` color logic (mock Write-Host, verify color parameters)
    - Test `Show-MainMenu` re-prompts on invalid input (mock Read-Host)
    - Test all output text is in Bahasa Indonesia (no English user-facing strings)
    - _Requirements: 5.1, 5.3, 5.5, 8.1, 8.2_

- [ ] 7. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 8. Refactor entry point and integration
  - [ ] 8.1 Refactor `scripts/analyze.ps1` to use modular architecture
    - Remove all inline scanning, categorization, and display logic
    - Import `src/ui/cli.ps1` (which transitively imports scanner and categorizer)
    - Check admin status and call `Show-AdminInfoMessage` if not admin (Requirement 6.4)
    - Call `Show-MainMenu` to launch the interactive CLI
    - Ensure the script remains the single entry point for users
    - _Requirements: 9.3, 9.4, 6.4_

  - [ ]* 8.2 Write integration tests in `tests/integration/full-scan.Tests.ps1`
    - Test full Quick Scan flow using Pester TestDrive with mock directory structure
    - Test full Deep Scan flow with threshold filtering on mock directories
    - Test rules file loading from actual `config/default-rules.json`
    - Test end-to-end: scan → categorize → verify output structure
    - _Requirements: 1.1, 2.1, 3.1, 9.4, 10.1_

  - [ ]* 8.3 Write CLI integration tests in `tests/integration/cli-menu.Tests.ps1`
    - Test menu navigation with mocked `Read-Host` (simulate user selecting Quick Scan, Deep Scan, Help, Exit)
    - Test invalid input handling and re-prompt behavior
    - Test dry-run label appears in output
    - Test Bahasa Indonesia text in all user-facing output
    - _Requirements: 4.1, 4.3, 5.1, 5.2, 5.4, 5.5_

- [ ] 9. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties from the design document
- Unit tests validate specific examples and edge cases
- All user-facing output must be in Bahasa Indonesia with casual tone
- PowerShell 5.1+ compatibility required — no external dependencies beyond Pester 5.x for testing
- The existing `config/default-rules.json` is the source of truth for categorization rules

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2"] },
    { "id": 1, "tasks": ["1.3", "2.1", "2.2"] },
    { "id": 2, "tasks": ["2.3", "2.4"] },
    { "id": 3, "tasks": ["2.5", "2.6", "4.1"] },
    { "id": 4, "tasks": ["4.2", "4.3"] },
    { "id": 5, "tasks": ["4.4", "4.5", "4.6"] },
    { "id": 6, "tasks": ["6.1", "6.2", "6.3"] },
    { "id": 7, "tasks": ["6.4"] },
    { "id": 8, "tasks": ["6.5", "6.6", "8.1"] },
    { "id": 9, "tasks": ["8.2", "8.3"] }
  ]
}
```
