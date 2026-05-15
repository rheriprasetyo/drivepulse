# Requirements Document

## Introduction

Fitur Report & Config (v1.2) menambahkan kemampuan DrivePulse untuk menghasilkan laporan visual dalam format HTML dan TXT dari hasil scan, serta menyediakan sistem konfigurasi user preferences (whitelist, blacklist, threshold) yang disimpan secara lokal. Laporan menggunakan kode warna untuk menunjukkan tingkat kritis penggunaan drive, dan user dapat mengkustomisasi perilaku DrivePulse sesuai kebutuhan.

## Glossary

- **Report_Generator**: Modul PowerShell (`src/reporter/report.ps1`) yang menghasilkan laporan dari data scan
- **HTML_Report**: File laporan berformat HTML yang dihasilkan dari template dengan CSS styling, progress bar, dan kode warna
- **TXT_Report**: File laporan berformat plain text yang mudah di-copy paste
- **Template_Engine**: Mekanisme penggantian placeholder variable (`{{VAR}}`) dalam template HTML dengan data aktual
- **Config_Manager**: Modul yang mengelola pembacaan dan penulisan file konfigurasi user preferences
- **User_Config**: File JSON (`%LOCALAPPDATA%\DrivePulse\config.json`) yang menyimpan preferensi pengguna
- **Whitelist**: Daftar path folder yang tidak boleh disentuh/dihapus oleh DrivePulse
- **Blacklist**: Daftar path folder custom yang selalu direkomendasikan untuk dihapus
- **Threshold**: Nilai batas ukuran folder (dalam GB) yang menentukan apakah folder dianggap "besar"
- **ScanResult**: Objek hasil scan (`DrivePulse.ScanResult`) berisi DriveLetter, TotalBytes, UsedBytes, FreeBytes, UsagePercent, Items, Errors, ElapsedSeconds
- **CategorizedItem**: Objek item terkategorisasi (`DrivePulse.CategorizedItem`) berisi Path, Label, SizeBytes, Category (Safe/Check), SideEffect, Reason, Recommendation
- **Color_Code**: Sistem pewarnaan berdasarkan persentase penggunaan drive — merah (kritis >90%), kuning (warning 75-90%), hijau (aman <75%)
- **CLI**: Command-line interface DrivePulse (`src/ui/cli.ps1`)

## Requirements

### Requirement 1: Generate HTML Report

**User Story:** As a user, I want to generate an HTML report from scan results, so that I can view a visual summary of my drive analysis in a browser.

#### Acceptance Criteria

1. WHEN a ScanResult object is provided with Format "HTML", THE Report_Generator SHALL produce a valid HTML file by replacing template placeholders ({{DATE}}, {{DRIVE}}, {{TOTAL_GB}}, {{USED_GB}}, {{USED_PCT}}, {{VERSION}}) with actual scan data, where TOTAL_GB and USED_GB are displayed as numbers rounded to 2 decimal places in gigabytes (bytes ÷ 1,073,741,824)
2. WHEN generating an HTML_Report, THE Template_Engine SHALL replace the {{SAFE_ITEMS}} section with an HTML table of all CategorizedItem objects where Category equals Safe, displaying Label, SizeBytes formatted as a human-readable string with appropriate unit (KB for < 1 MB, MB for < 1 GB, GB otherwise) rounded to 2 decimal places, and SideEffect
3. WHEN generating an HTML_Report, THE Template_Engine SHALL replace the {{CHECK_ITEMS}} section with an HTML table of all CategorizedItem objects where Category equals Check, displaying Label, SizeBytes formatted as a human-readable string with appropriate unit (KB for < 1 MB, MB for < 1 GB, GB otherwise) rounded to 2 decimal places, Reason, and Recommendation
4. WHEN generating an HTML_Report and the ScanResult contains CategorizedItem objects where Category equals Check, THE Template_Engine SHALL replace the {{RECOMMENDATIONS}} section with a list of recommendations in Bahasa Indonesia, containing one recommendation entry per unique Recommendation value from the Check-category items
5. WHEN the HTML_Report is generated, THE Report_Generator SHALL save the file to the specified OutputPath with filename format `DrivePulse-Report-{yyyy-MM-dd}.html`
6. THE HTML_Report SHALL be a self-contained file that renders correctly when opened in Edge, Chrome, or Firefox without requiring external network requests, stylesheets, scripts, or image resources
7. IF the specified OutputPath does not exist or is not writable, THEN THE Report_Generator SHALL return an error indicating the output location is inaccessible without creating a partial file
8. WHEN generating an HTML_Report and the ScanResult contains zero CategorizedItem objects for a given Category (Safe or Check), THE Template_Engine SHALL replace the corresponding section placeholder with a message in Bahasa Indonesia indicating no items were found for that category

### Requirement 2: HTML Report Visual Styling

**User Story:** As a user, I want the HTML report to be visually appealing with progress bars and responsive design, so that I can easily understand my drive status on any device.

#### Acceptance Criteria

1. THE HTML_Report SHALL include a progress bar element with a minimum height of 20px, where the filled portion width equals the UsagePercent value as a percentage of the total bar width
2. IF UsagePercent is greater than 90, THEN THE HTML_Report SHALL apply the Color_Code merah (red: `#ff4757`) to the progress bar fill and status indicators
3. IF UsagePercent is between 75 and 90 (inclusive), THEN THE HTML_Report SHALL apply the Color_Code kuning (yellow: `#ffa502`) to the progress bar fill and status indicators
4. IF UsagePercent is less than 75, THEN THE HTML_Report SHALL apply the Color_Code hijau (green: `#2ed573`) to the progress bar fill and status indicators
5. THE HTML_Report SHALL use responsive CSS that renders content in a single-column layout at viewport widths below 600px and a max-width constrained layout (800px) at viewport widths from 600px to 1200px, with no horizontal scrollbar at any width from 320px to 1200px
6. THE HTML_Report SHALL display all text content including headings, labels, status messages, and recommendations in Bahasa Indonesia
7. THE HTML_Report SHALL embed all CSS within a `<style>` element in the document head, with no external stylesheet references or script dependencies

### Requirement 3: Generate TXT Report

**User Story:** As a user, I want to generate a plain text report from scan results, so that I can easily copy-paste the information or view it in any text editor.

#### Acceptance Criteria

1. WHEN a ScanResult object is provided with Format "TXT", THE Report_Generator SHALL produce a plain text file containing a header section, a "Aman Dihapus" section listing Safe items, a "Perlu Dicek Manual" section listing Check items, and a summary section
2. THE TXT_Report header section SHALL include: tanggal (format yyyy-MM-dd HH:mm:ss), drive letter, total kapasitas displayed using Format-Size logic (values >= 1 GB as "X.X GB", values < 1 GB as "X MB"), terpakai displayed using Format-Size logic, dan persentase penggunaan (1 decimal place, e.g. "95.0%")
3. THE TXT_Report SHALL list all Safe items under a "Aman Dihapus" heading, each showing Label and formatted size using Format-Size logic, sorted by SizeBytes descending
4. THE TXT_Report SHALL list all Check items under a "Perlu Dicek Manual" heading, each showing Label, formatted size using Format-Size logic, and Recommendation text, sorted by SizeBytes descending
5. IF a category (Safe or Check) contains zero items, THEN THE TXT_Report SHALL display the section heading followed by a single line stating "Tidak ada item dalam kategori ini"
6. THE TXT_Report SHALL include a summary section showing total reclaimable space (sum of Safe items' SizeBytes, displayed using Format-Size logic) and total space needing review (sum of Check items' SizeBytes, displayed using Format-Size logic)
7. WHEN the TXT_Report is generated, THE Report_Generator SHALL save the file to the specified OutputPath with filename format `DrivePulse-Report-{yyyy-MM-dd}.txt`, overwriting any existing file with the same name
8. IF the specified OutputPath does not exist or is not writable, THEN THE Report_Generator SHALL return an error indicating the path is invalid without creating a partial file
9. THE TXT_Report SHALL use UTF-8 encoding with BOM (Byte Order Mark) and use CRLF line endings, ensuring characters render without corruption when opened in Notepad and displayed in PowerShell console

### Requirement 4: User Config File Management

**User Story:** As a user, I want my preferences to be saved in a local config file, so that DrivePulse remembers my settings between sessions.

#### Acceptance Criteria

1. WHEN DrivePulse starts, THE Config_Manager SHALL read User_Config from the path `%LOCALAPPDATA%\DrivePulse\config.json` and load the values into memory for use during the session
2. IF the User_Config file does not exist, THEN THE Config_Manager SHALL create it with default values (whitelist: [], blacklist: [], largeFolderGB: 5)
3. IF the User_Config file contains invalid JSON, THEN THE Config_Manager SHALL display a warning message in Bahasa Indonesia to the CLI output indicating the file is corrupt, retain the corrupt file unchanged on disk, and proceed using default values (whitelist: [], blacklist: [], largeFolderGB: 5) without terminating
4. WHEN the user saves a preference change, THE Config_Manager SHALL write the complete User_Config as UTF-8 encoded JSON with 2-space indentation to `%LOCALAPPDATA%\DrivePulse\config.json`
5. IF the `%LOCALAPPDATA%\DrivePulse\` directory does not exist, THEN THE Config_Manager SHALL create it before writing the config file
6. IF writing to the User_Config file fails due to permission denial or insufficient disk space, THEN THE Config_Manager SHALL display an error message in Bahasa Indonesia to the CLI output indicating the failure reason and preserve the previous config file unchanged
7. THE Config_Manager SHALL validate that largeFolderGB is a numeric value between 1 and 100 inclusive, whitelist contains no more than 50 path entries, and blacklist contains no more than 50 path entries before writing to the config file

### Requirement 5: Whitelist Configuration

**User Story:** As a user, I want to define a whitelist of folders that DrivePulse should never touch, so that my important folders are always protected.

#### Acceptance Criteria

1. THE User_Config SHALL support a `whitelist` array containing between 0 and 100 absolute Windows folder paths that DrivePulse must exclude from cleanup recommendations
2. WHEN categorizing scan results, THE Report_Generator SHALL exclude any CategorizedItem whose Path matches a Whitelist entry using case-insensitive comparison, where a match is defined as the item path being equal to or a subdirectory of a whitelist entry, from the "Aman Dihapus" section
3. WHEN the CLI is invoked without the `--whitelist` or `--no-whitelist` flag, THE CLI SHALL apply the Whitelist from User_Config by default during report generation
4. WHEN the CLI is invoked with the `--no-whitelist` flag, THE CLI SHALL ignore the Whitelist and include all items in the report regardless of whitelist entries
5. IF a Whitelist entry path does not exist on the filesystem, THEN THE Config_Manager SHALL retain the entry in config without error (path may exist on other machines or be created later)
6. IF a Whitelist entry contains a value that is not a valid absolute Windows path (does not start with a drive letter followed by `:\`), THEN THE Config_Manager SHALL skip that entry and continue processing the remaining whitelist entries

### Requirement 6: Blacklist Configuration

**User Story:** As a user, I want to define a blacklist of custom folders that should always be recommended for deletion, so that DrivePulse automatically flags my known junk folders.

#### Acceptance Criteria

1. THE User_Config SHALL support a `blacklist` array containing between 0 and 50 absolute folder paths (each no longer than 260 characters) that DrivePulse must always recommend for cleanup
2. WHEN a folder path matches a Blacklist entry and exists on the filesystem, THE Report_Generator SHALL include it in the "Aman Dihapus" section with Category Safe, a SideEffect of "User-defined blacklist item", Label set to the folder name from the path, and Recommendation of "Folder ditandai oleh user untuk dihapus"
3. IF a Blacklist entry path does not exist on the filesystem, THEN THE Report_Generator SHALL skip the entry and continue processing remaining entries without displaying an error to the user
4. IF a Blacklist entry is not a valid absolute Windows path (does not start with a drive letter followed by `:\`), THEN THE Report_Generator SHALL skip the entry and continue processing remaining entries without displaying an error to the user
5. IF a folder path appears in both the Blacklist and the Whitelist, THEN THE User_Config SHALL treat the Whitelist entry as taking priority and exclude the folder from cleanup recommendations

### Requirement 7: Configurable Threshold

**User Story:** As a user, I want to configure the "large folder" threshold, so that DrivePulse uses my preferred size limit when identifying large folders.

#### Acceptance Criteria

1. THE User_Config SHALL support a `largeFolderGB` numeric field that defines the minimum size (in GB) for a folder to be considered "large", accepting values from 0.1 to 100 inclusive with up to two decimal places of precision
2. WHEN the User_Config contains a `largeFolderGB` value that is a number between 0.1 and 100 inclusive, THE Config_Manager SHALL use that value as the large folder threshold instead of the default (5 GB) from `default-rules.json`
3. IF the `largeFolderGB` value in User_Config is not a number, is less than 0.1, or is greater than 100, THEN THE Config_Manager SHALL fall back to the default value (5 GB) and display a warning message in Bahasa Indonesia indicating the invalid value and the default being used
4. IF the `largeFolderGB` field is absent from User_Config, THEN THE Config_Manager SHALL use the default value (5 GB) from `default-rules.json` without displaying a warning

### Requirement 8: CLI Integration for Report Export

**User Story:** As a user, I want to export reports from the CLI menu, so that I can generate reports after scanning without leaving the application.

#### Acceptance Criteria

1. WHEN the user selects the export option from the CLI menu after a scan, THE CLI SHALL prompt the user to choose between HTML and TXT format by displaying numbered options (e.g., [1] HTML, [2] TXT)
2. WHEN the user selects a valid format, THE CLI SHALL invoke New-DriveReport with the current ScanResult, the selected format, and the default OutputPath ($env:USERPROFILE\Desktop)
3. WHEN the report is generated successfully, THE CLI SHALL display a confirmation message in Bahasa Indonesia that includes the absolute file path of the generated report
4. IF the report generation fails, THEN THE CLI SHALL display an error message in Bahasa Indonesia indicating the failure reason (e.g., permission denied, disk full) and return the user to the post-scan menu without crashing
5. IF the user enters an invalid selection at the format prompt (not matching any offered option), THEN THE CLI SHALL display an error message in Bahasa Indonesia indicating the valid choices and re-prompt up to 3 times before returning to the post-scan menu

### Requirement 9: Report Data Accuracy

**User Story:** As a user, I want the report to accurately reflect the scan results, so that I can trust the information for decision-making.

#### Acceptance Criteria

1. THE Report_Generator SHALL produce reports where the sum of displayed Safe item sizes equals the sum of SizeBytes of all CategorizedItem objects with Category Safe, with zero loss from formatting (the formatted values, when parsed back to bytes at their displayed precision, SHALL equal the rounded value used for display)
2. THE Report_Generator SHALL produce reports where the displayed UsagePercent matches `ScanResult.UsagePercent` rounded to one decimal place, displayed as "X.X%" (e.g., "75.3%")
3. THE Report_Generator SHALL format all sizes using the same logic as Format-Size: values >= 1,073,741,824 bytes (1 GB) displayed as "X.X GB" (1 decimal place, rounded), values < 1,073,741,824 bytes displayed as "X MB" (no decimal place, rounded to nearest integer)
4. IF a category contains zero CategorizedItem objects, THEN THE Report_Generator SHALL display "0 MB" as the total size for that category
5. THE Report_Generator SHALL display totals for each category (Safe, Check) where each category total equals the sum of SizeBytes of all CategorizedItem objects belonging to that category, formatted per criterion 3
