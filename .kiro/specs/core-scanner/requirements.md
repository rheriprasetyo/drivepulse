# Requirements Document

## Introduction

DrivePulse Core Scanner (v1.1) is the first major milestone after the project foundation. It refactors the monolithic `scripts/analyze.ps1` into a modular architecture (`src/scanner/`, `src/ui/`) and adds Deep Scan mode, progress indication, and rule-based categorization from `config/default-rules.json`. The scanner analyzes drive C: to identify space-consuming folders and categorize them as safe to delete or requiring manual review, all presented through an interactive CLI in Bahasa Indonesia for non-technical Indonesian users.

## Glossary

- **Scanner**: The PowerShell module (`src/scanner/scan.ps1`) responsible for traversing the file system and collecting folder size data
- **Categorizer**: The PowerShell module (`src/scanner/categorize.ps1`) responsible for classifying scanned items as Safe or Check based on rules
- **CLI_Menu**: The interactive command-line interface module (`src/ui/cli.ps1`) that displays results and accepts user input in Bahasa Indonesia
- **Rules_File**: The JSON configuration file (`config/default-rules.json`) containing categorization rules, thresholds, and side-effect descriptions
- **Quick_Scan**: A scan mode that examines top-level folders and known junk locations only
- **Deep_Scan**: A scan mode that recursively traverses all subfolders on the target drive
- **Safe_Item**: A scanned item categorized as safe to delete without risk of data loss
- **Check_Item**: A scanned item that requires manual user review before deletion
- **Dry_Run_Mode**: The default operating mode where the system displays what would be deleted without performing any file deletion
- **Progress_Indicator**: A visual element in the CLI that shows scan progress to the user
- **Access_Denied_Error**: A file system error occurring when the script lacks permission to read a folder

## Requirements

### Requirement 1: Quick Scan Mode

**User Story:** As a non-technical user, I want to quickly scan my drive for junk files, so that I can see cleanup recommendations within seconds without waiting for a full analysis.

#### Acceptance Criteria

1. WHEN the user selects Quick Scan from the CLI_Menu, THE Scanner SHALL scan top-level folders of drive C: and all known junk locations defined in the Rules_File
2. WHEN Quick Scan is executed on a drive with 500 GB capacity or less, THE Scanner SHALL complete the scan within 15 seconds
3. WHEN Quick Scan completes, THE Scanner SHALL return a structured result containing the path, size in bytes, and label for each scanned location
4. THE Scanner SHALL resolve environment variable paths (such as %TEMP%, %LOCALAPPDATA%, %APPDATA%, %USERPROFILE%) defined in the Rules_File to their actual file system paths before scanning

### Requirement 2: Deep Scan Mode

**User Story:** As a user who wants a thorough analysis, I want to recursively scan all subfolders on my drive, so that I can find hidden space consumers that Quick Scan might miss.

#### Acceptance Criteria

1. WHEN the user selects Deep Scan from the CLI_Menu, THE Scanner SHALL recursively traverse all subfolders on drive C:
2. WHEN Deep Scan is executed on a drive with 500 GB capacity or less, THE Scanner SHALL complete the scan within 60 seconds
3. WHEN Deep Scan completes, THE Scanner SHALL return a structured result containing the path, size in bytes, and label for each folder exceeding the largeFolderGB threshold defined in the Rules_File
4. WHILE Deep Scan is running, THE Progress_Indicator SHALL display the current folder being scanned and an estimated completion percentage

### Requirement 3: Item Categorization

**User Story:** As a non-technical user, I want each scanned item to be clearly labeled as safe or needing review, so that I know what I can delete without risk.

#### Acceptance Criteria

1. WHEN scan results are available, THE Categorizer SHALL classify each item as either Safe_Item or Check_Item based on matching rules in the Rules_File
2. WHEN an item is classified as Safe_Item, THE Categorizer SHALL attach the corresponding sideEffect description from the Rules_File
3. WHEN an item is classified as Check_Item, THE Categorizer SHALL attach the corresponding reason and recommendation fields from the Rules_File
4. WHEN a scanned folder matches no rule in the Rules_File and exceeds the largeFolderGB threshold, THE Categorizer SHALL classify the folder as Check_Item with reason "Folder besar tanpa aturan spesifik"
5. WHEN a scanned item path matches a rule with requiresAdmin set to true and the script is not running with administrator privileges, THE Categorizer SHALL still list the item but annotate it with a note that administrator rights are needed for full access

### Requirement 4: Dry-Run Mode

**User Story:** As a cautious user, I want the tool to show me what would be deleted without actually deleting anything, so that I feel safe using it.

#### Acceptance Criteria

1. THE CLI_Menu SHALL operate in Dry_Run_Mode by default on every scan execution
2. WHILE in Dry_Run_Mode, THE Scanner SHALL perform read-only file system operations and SHALL NOT delete, move, or modify any files or folders
3. WHEN displaying results in Dry_Run_Mode, THE CLI_Menu SHALL show a clear label "[MODE: DRY-RUN — tidak ada file yang dihapus]" at the top of the results

### Requirement 5: Interactive CLI Menu

**User Story:** As a non-technical Indonesian user, I want a friendly menu in my language with colored output, so that I can navigate the tool easily without technical knowledge.

#### Acceptance Criteria

1. THE CLI_Menu SHALL display all user-facing text in Bahasa Indonesia using a casual and friendly tone
2. WHEN the CLI_Menu starts, THE CLI_Menu SHALL present a main menu with options: Quick Scan, Deep Scan, Bantuan (Help), and Keluar (Exit)
3. WHEN scan results are displayed, THE CLI_Menu SHALL use green color for Safe_Items, yellow color for Check_Items, and red color for critical disk usage warnings (above 90% usage)
4. THE CLI_Menu SHALL use only ASCII-compatible box-drawing characters and emoji that render correctly in Windows PowerShell 5.1 default console encoding
5. WHEN the user enters an invalid menu choice, THE CLI_Menu SHALL display a friendly error message and re-display the menu options

### Requirement 6: Access Denied Handling

**User Story:** As a user running the tool without administrator rights, I want the scan to continue even when some folders are inaccessible, so that I still get useful results.

#### Acceptance Criteria

1. WHEN the Scanner encounters an Access_Denied_Error while scanning a folder, THE Scanner SHALL skip the inaccessible folder and continue scanning remaining folders
2. WHEN the Scanner skips a folder due to Access_Denied_Error, THE Scanner SHALL log the skipped folder path and error message to an internal errors collection
3. WHEN the scan completes with skipped folders, THE CLI_Menu SHALL display a summary count of skipped folders and offer to show the full list on user request
4. IF the script is not running with administrator privileges, THEN THE CLI_Menu SHALL display a one-time informational message at startup explaining that running as Administrator provides more complete results

### Requirement 7: Progress Indication

**User Story:** As a user waiting for a scan, I want to see that the tool is working and how far along it is, so that I don't think it has frozen.

#### Acceptance Criteria

1. WHILE the Scanner is executing a Quick_Scan, THE Progress_Indicator SHALL display the name of each location currently being scanned
2. WHILE the Scanner is executing a Deep_Scan, THE Progress_Indicator SHALL display a progress bar showing estimated completion percentage and the current folder path
3. WHEN the scan completes, THE Progress_Indicator SHALL display the total elapsed time in seconds

### Requirement 8: Results Display

**User Story:** As a user, I want to see a clear summary of my drive usage including the biggest space consumers and what I can safely clean, so that I can make informed decisions.

#### Acceptance Criteria

1. WHEN scan results are displayed, THE CLI_Menu SHALL show total used space in GB, total free space in GB, and usage percentage for drive C:
2. WHEN scan results are displayed, THE CLI_Menu SHALL show a sorted list of the largest folders found, with size displayed in GB (for items >= 1 GB) or MB (for items < 1 GB)
3. WHEN scan results are displayed, THE CLI_Menu SHALL group items into "Aman Dihapus" (Safe) and "Perlu Dicek Manual" (Check) sections
4. WHEN displaying a Safe_Item, THE CLI_Menu SHALL show the item label, size, and side-effect explanation from the Rules_File
5. WHEN displaying a Check_Item, THE CLI_Menu SHALL show the item label, size, reason for manual check, and recommendation from the Rules_File
6. WHEN scan results are displayed, THE CLI_Menu SHALL show a summary with total reclaimable space for Safe_Items and total space requiring review for Check_Items

### Requirement 9: Modular Architecture

**User Story:** As a developer, I want the scanner logic separated into distinct modules, so that the codebase is maintainable and testable.

#### Acceptance Criteria

1. THE Scanner SHALL be implemented in `src/scanner/scan.ps1` as a standalone module exporting the `Start-DriveScan` function
2. THE Categorizer SHALL be implemented in `src/scanner/categorize.ps1` as a standalone module exporting the `Get-ItemCategory` function
3. THE CLI_Menu SHALL be implemented in `src/ui/cli.ps1` as a standalone module that imports Scanner and Categorizer modules
4. WHEN the entry point script (`scripts/analyze.ps1`) is executed, THE script SHALL import modules from `src/scanner/` and `src/ui/` rather than containing inline scanning logic
5. THE Scanner SHALL accept a drive letter parameter defaulting to "C" and a mode parameter accepting "Quick" or "Deep"

### Requirement 10: Rules File Parsing

**User Story:** As a developer, I want categorization rules loaded from a JSON config file, so that rules can be updated without modifying source code.

#### Acceptance Criteria

1. WHEN the Categorizer is initialized, THE Categorizer SHALL load and parse the Rules_File from `config/default-rules.json`
2. IF the Rules_File is missing or contains invalid JSON, THEN THE Categorizer SHALL display a clear error message and terminate gracefully without crashing
3. THE Categorizer SHALL read the thresholds.largeFolderGB value from the Rules_File to determine the size threshold for flagging large folders
4. FOR ALL valid Rules_File JSON structures, parsing the file and serializing the parsed object back to JSON SHALL produce a semantically equivalent structure (round-trip property)
