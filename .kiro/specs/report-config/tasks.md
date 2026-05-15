# Implementation Plan: Report & Config

## Overview

Implement the Report & Config feature (v1.2) for DrivePulse, adding HTML/TXT report generation from scan results and a user configuration system (whitelist, blacklist, threshold). The implementation builds on the existing `src/reporter/report.ps1` skeleton and extends the CLI menu with export capabilities and config-aware filtering.

## Tasks

- [x] 1. Create shared format utilities and config manager foundation
  - [x] 1.1 Create `src/reporter/format-utils.ps1` with Format-Size, Format-SizeDetailed, Format-Percent, and Get-ColorCode functions
    - Extract `Format-Size` logic from `src/ui/cli.ps1` into the new shared module
    - Implement `Format-SizeDetailed` for HTML report (KB/MB/GB with 2 decimal places)
    - Implement `Format-Percent` returning "X.X%" format
    - Implement `Get-ColorCode` returning hex color based on UsagePercent thresholds (>90 red, 75-90 yellow, <75 green)
    - Update `src/ui/cli.ps1` to dot-source `format-utils.ps1` instead of defining its own `Format-Size`
    - _Requirements: 9.3, 2.2, 2.3, 2.4_

  - [x] 1.2 Create `src/config/config-manager.ps1` with Get-UserConfig, Save-UserConfig, Test-ValidWindowsPath, and Get-EffectiveThreshold functions
    - Implement `Get-UserConfig` to read `%LOCALAPPDATA%\DrivePulse\config.json`, create defaults if missing, warn on invalid JSON
    - Implement `Save-UserConfig` with validation (largeFolderGB 0.1-100, whitelist ≤100 entries, blacklist ≤50 entries each ≤260 chars)
    - Implement `Test-ValidWindowsPath` to check drive letter + `:\` prefix
    - Implement `Get-EffectiveThreshold` to resolve threshold from user config or default
    - Create directory `%LOCALAPPDATA%\DrivePulse\` if it does not exist
    - Write UTF-8 JSON with 2-space indentation
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 7.1, 7.2, 7.3, 7.4_

  - [x] 1.3 Write property tests for format utilities
    - **Property 4: Color Code Mapping** — verify Get-ColorCode returns correct hex for all UsagePercent 0-100
    - **Property 15: Size Formatting Consistency** — verify Format-Size and Format-SizeDetailed produce correct unit suffixes and decimal places for random byte values
    - **Validates: Requirements 2.2, 2.3, 2.4, 9.3**

  - [x] 1.4 Write property tests for config manager
    - **Property 8: Invalid JSON Config Falls Back to Defaults** — verify random invalid JSON strings produce default config
    - **Property 9: Config Save/Load Round Trip** — verify save then load produces identical config
    - **Property 10: Config Validation** — verify invalid configs are rejected and valid configs accepted
    - **Property 14: Effective Threshold Resolution** — verify threshold resolution logic for valid/invalid values
    - **Validates: Requirements 4.3, 4.4, 4.7, 7.2, 7.3**

- [x] 2. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 3. Implement whitelist/blacklist filter module
  - [x] 3.1 Create `src/reporter/filter.ps1` with Invoke-WhitelistFilter and Invoke-BlacklistEnrich functions
    - Implement `Invoke-WhitelistFilter` to remove Safe items whose Path matches whitelist entries (case-insensitive, including subdirectories)
    - Implement `Invoke-BlacklistEnrich` to add existing blacklist folders as Safe items with correct fields (SideEffect, Label, Recommendation)
    - Whitelist takes priority over blacklist when a path appears in both
    - Skip invalid path entries (not starting with drive letter + `:\`)
    - Skip non-existent blacklist paths silently
    - _Requirements: 5.1, 5.2, 5.5, 5.6, 6.1, 6.2, 6.3, 6.4, 6.5_

  - [x] 3.2 Write property tests for whitelist/blacklist filtering
    - **Property 11: Whitelist Path Matching** — verify items are excluded iff path matches or is subdirectory of whitelist entry (case-insensitive)
    - **Property 12: Invalid Path Entries Are Skipped** — verify invalid entries are skipped and valid entries processed
    - **Property 13: Whitelist Priority Over Blacklist** — verify whitelist wins when path is in both lists
    - **Validates: Requirements 5.2, 5.6, 6.4, 6.5**

- [x] 4. Implement HTML report generation
  - [x] 4.1 Update `src/reporter/template.html` with full HTML template including placeholders, embedded CSS, responsive layout, progress bar, and color-coded styling
    - Include all placeholders: {{DATE}}, {{DRIVE}}, {{TOTAL_GB}}, {{USED_GB}}, {{USED_PCT}}, {{VERSION}}, {{SAFE_ITEMS}}, {{CHECK_ITEMS}}, {{RECOMMENDATIONS}}, {{PROGRESS_BAR}}, {{COLOR_CODE}}
    - Embed all CSS in `<style>` tag with responsive design (single-column below 600px, max-width 800px for 600-1200px)
    - Progress bar element with min-height 20px, width driven by UsagePercent
    - All text in Bahasa Indonesia
    - No external stylesheet, script, or image references
    - _Requirements: 1.1, 1.6, 2.1, 2.5, 2.6, 2.7_

  - [x] 4.2 Implement `New-HtmlReport` function in `src/reporter/report.ps1`
    - Read template.html and replace all placeholders with actual scan data
    - Replace {{TOTAL_GB}} and {{USED_GB}} with bytes ÷ 1,073,741,824 rounded to 2 decimal places
    - Build HTML table for Safe items (Label, SizeBytes via Format-SizeDetailed, SideEffect)
    - Build HTML table for Check items (Label, SizeBytes via Format-SizeDetailed, Reason, Recommendation)
    - Build recommendations section with one entry per unique Recommendation value from Check items
    - Show empty category message in Bahasa Indonesia when zero items in a category
    - Save file as `DrivePulse-Report-{yyyy-MM-dd}.html` at OutputPath
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.8_

  - [x] 4.3 Write property tests for HTML report generation
    - **Property 1: Byte-to-GB Conversion Accuracy** — verify TOTAL_GB and USED_GB equal Round(bytes / 1073741824, 2)
    - **Property 2: Category Items Rendering Completeness** — verify all Safe and Check items appear in HTML output
    - **Property 3: Recommendations Deduplication** — verify unique recommendation count matches rendered count
    - **Property 5: Self-Contained HTML** — verify no external link/script/img elements in output
    - **Validates: Requirements 1.1, 1.2, 1.3, 1.4, 1.6, 2.7**

- [x] 5. Implement TXT report generation
  - [x] 5.1 Implement `New-TxtReport` function in `src/reporter/report.ps1`
    - Build header section with tanggal (yyyy-MM-dd HH:mm:ss), drive letter, total/terpakai using Format-Size, persentase (1 decimal)
    - List Safe items under "Aman Dihapus" heading sorted by SizeBytes descending with Label and formatted size
    - List Check items under "Perlu Dicek Manual" heading sorted by SizeBytes descending with Label, formatted size, and Recommendation
    - Show "Tidak ada item dalam kategori ini" for empty categories
    - Include summary section with total reclaimable space and total space needing review
    - Save file as `DrivePulse-Report-{yyyy-MM-dd}.txt` at OutputPath, overwriting existing
    - Use UTF-8 encoding with BOM and CRLF line endings
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9_

  - [x] 5.2 Write property tests for TXT report generation
    - **Property 6: TXT Report Items Sorted by Size Descending** — verify items within each category are in non-increasing SizeBytes order
    - **Property 7: Report Summary Totals Accuracy** — verify totals equal sum of SizeBytes per category, empty = "0 MB"
    - **Property 16: UsagePercent Display Accuracy** — verify displayed percent equals Round(UsagePercent, 1) as "X.X%"
    - **Validates: Requirements 3.3, 3.4, 3.6, 9.1, 9.2, 9.4, 9.5**

- [x] 6. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 7. Wire up report generator entry point and error handling
  - [x] 7.1 Implement the main `New-DriveReport` function in `src/reporter/report.ps1`
    - Replace the existing placeholder implementation
    - Accept ScanResult, CategorizedItems, Format, and OutputPath parameters
    - Validate OutputPath exists and is writable before generating
    - Return `DrivePulse.ReportResult` object with Success, FilePath, Format, Error fields
    - Delegate to `New-HtmlReport` or `New-TxtReport` based on Format parameter
    - Handle errors (path not found, permission denied, disk full) without creating partial files
    - Dot-source `format-utils.ps1` and `filter.ps1` at module load
    - _Requirements: 1.5, 1.7, 3.7, 3.8_

  - [x] 7.2 Write unit tests for report generator error handling
    - Test error returned for non-existent OutputPath
    - Test no partial file created on failure
    - Test correct filename pattern for HTML and TXT
    - Test TXT file uses UTF-8 BOM + CRLF encoding
    - _Requirements: 1.5, 1.7, 3.7, 3.8, 3.9_

- [x] 8. Implement CLI integration for report export and config
  - [x] 8.1 Implement `Show-ExportMenu` function in `src/ui/cli.ps1`
    - Display format choice prompt: [1] HTML [2] TXT
    - Invoke `New-DriveReport` with current ScanResult, selected format, and default OutputPath ($env:USERPROFILE\Desktop)
    - Display confirmation message in Bahasa Indonesia with absolute file path on success
    - Display error message in Bahasa Indonesia on failure and return to post-scan menu
    - Re-prompt up to 3 times on invalid input, then return to post-scan menu
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5_

  - [x] 8.2 Integrate config loading and whitelist/blacklist filtering into CLI scan flow
    - Load user config via `Get-UserConfig` at startup
    - Apply `Get-EffectiveThreshold` to override default rules threshold
    - Apply whitelist filter and blacklist enrichment to categorized items before display and report
    - Support `--no-whitelist` CLI flag to skip whitelist filtering
    - Add export option to post-scan menu (after scan results display)
    - Dot-source `config-manager.ps1` and `filter.ps1`
    - _Requirements: 4.1, 5.2, 5.3, 5.4, 6.2, 7.2, 8.1_

  - [x] 8.3 Write unit tests for CLI export menu and config integration
    - Test CLI export prompt displays correct options
    - Test CLI displays confirmation with file path on success
    - Test CLI displays error and returns to menu on failure
    - Test CLI re-prompts up to 3 times on invalid input
    - Test --no-whitelist flag ignores whitelist
    - Test default whitelist applied without flags
    - _Requirements: 8.1, 8.3, 8.4, 8.5, 5.3, 5.4_

- [x] 9. Add test data generators and integration tests
  - [x] 9.1 Extend `tests/helpers/generators.ps1` with new random data generators
    - Implement `New-RandomScanResult` — random ScanResult with valid byte ranges (0-2TB)
    - Implement `New-RandomCategorizedItems` — random array of CategorizedItem objects with Safe/Check categories
    - Implement `New-RandomUserConfig` — random valid config objects within constraints
    - Implement `New-RandomInvalidThreshold` — random invalid largeFolderGB values
    - Implement `New-RandomWindowsPath` — random valid absolute Windows paths
    - Implement `New-RandomInvalidPath` — random strings that are not valid Windows paths
    - _Requirements: supports all property tests_

  - [x] 9.2 Write integration tests in `tests/integration/report-export.Tests.ps1`
    - Test full HTML report generation from mock scan data end-to-end
    - Test full TXT report generation from mock scan data end-to-end
    - Test CLI export flow with mocked user input
    - Test config load → scan → filter → report pipeline
    - _Requirements: 1, 2, 3, 4, 5, 6, 7, 8 (integration)_

- [x] 10. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties from the design document
- Unit tests validate specific examples and edge cases
- The existing `Format-Size` in `cli.ps1` is extracted to a shared utility to avoid duplication
- All user-facing text must be in Bahasa Indonesia
- PowerShell Pester framework is used for all tests, consistent with existing test structure

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2", "9.1"] },
    { "id": 1, "tasks": ["1.3", "1.4", "3.1"] },
    { "id": 2, "tasks": ["3.2", "4.1"] },
    { "id": 3, "tasks": ["4.2", "5.1"] },
    { "id": 4, "tasks": ["4.3", "5.2", "7.1"] },
    { "id": 5, "tasks": ["7.2", "8.1", "8.2"] },
    { "id": 6, "tasks": ["8.3", "9.2"] }
  ]
}
```
