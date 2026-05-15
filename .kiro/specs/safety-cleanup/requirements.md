# Requirements Document

## Introduction

DrivePulse v1.3 (Safety & Cleanup) implements the one-click cleanup, backup/rollback, audit logging, and staging area features. This milestone transforms DrivePulse from a read-only analysis tool into a safe, reversible cleanup tool. All destructive operations are protected by dry-run defaults, mandatory backup, interactive confirmation, and comprehensive audit logging. A staging area provides an intermediate holding zone before permanent deletion.

## Glossary

- **Cleaner**: The module (`src/cleaner/cleaner.ps1`) responsible for orchestrating file cleanup operations including preview, confirmation, and execution.
- **Backup_Module**: The module (`src/backup/backup.ps1`) responsible for creating backups of files before deletion and managing backup lifecycle.
- **Audit_Logger**: The module (`src/audit/audit.ps1`) responsible for recording all actions to the audit log file.
- **Staging_Area**: The module (`src/staging/staging.ps1`) responsible for managing the intermediate holding area where files are moved before permanent deletion.
- **Backup_Root**: The directory `%LOCALAPPDATA%\DrivePulse\Backup\` where backup copies are stored.
- **Staging_Root**: The directory `%LOCALAPPDATA%\DrivePulse\Staging\` where files awaiting deletion are held.
- **Audit_Log**: The file `logs/audit.log` (relative to project root) where all actions are recorded.
- **Retention_Period**: The configurable duration (default 7 days) after which backup and staging files are automatically purged.
- **Dry_Run_Mode**: The default operating mode where cleanup operations are simulated without modifying any files.
- **CLI**: The command-line interface module (`src/ui/cli.ps1`) providing interactive menu access to all DrivePulse features.
- **Cleanup_Session**: A single invocation of the cleanup process, identified by a unique session ID and timestamp.

## Requirements

### Requirement 1: Cleanup Preview and Dry-Run

**User Story:** As a user, I want to preview what files will be cleaned up before any deletion occurs, so that I can verify the operation is safe.

#### Acceptance Criteria

1. THE Cleaner SHALL operate in Dry_Run_Mode by default when no explicit mode is specified.
2. WHILE Dry_Run_Mode is active, THE Cleaner SHALL display a summary of files that would be deleted including file path, size in bytes, and category (Safe, Check, or Unknown) for each item, up to a maximum of 1000 items.
3. WHILE Dry_Run_Mode is active, THE Cleaner SHALL not modify, move, or delete any files on the filesystem.
4. WHEN the user requests a cleanup preview, THE Cleaner SHALL display the total number of items and total size that would be deleted, with size shown in both bytes and human-readable units (KB, MB, or GB).
5. WHEN the user confirms cleanup after preview, THE Cleaner SHALL switch from Dry_Run_Mode to execution mode for that Cleanup_Session.
6. WHEN the user declines cleanup after preview, THE Cleaner SHALL remain in Dry_Run_Mode and return to the preview summary without modifying any files.
7. IF no items qualify for cleanup after a scan, THEN THE Cleaner SHALL display a message indicating zero items found for cleanup and SHALL not prompt the user for confirmation.

### Requirement 2: Interactive Confirmation

**User Story:** As a user, I want to explicitly confirm before any files are deleted, so that I do not accidentally lose data.

#### Acceptance Criteria

1. WHEN the user initiates a cleanup in execution mode, THE Cleaner SHALL display a confirmation prompt listing the total item count and total size (formatted in the nearest human-readable unit: KB, MB, or GB) before proceeding.
2. WHEN the user responds with "y" or "Y" to the confirmation prompt, THE Cleaner SHALL proceed with the cleanup operation.
3. WHEN the user responds with any value other than "y" or "Y" to the confirmation prompt (including empty input), THE Cleaner SHALL abort the cleanup operation, display a cancellation message in Bahasa Indonesia, and return to the menu without modifying any files.
4. THE Cleaner SHALL display the confirmation prompt in Bahasa Indonesia.
5. IF the cleanup item list contains zero items, THEN THE Cleaner SHALL display a message in Bahasa Indonesia indicating there is nothing to clean and return to the menu without showing the confirmation prompt.

### Requirement 3: Cleanup Progress Tracking

**User Story:** As a user, I want to see progress during cleanup operations, so that I know the operation is proceeding and how much remains.

#### Acceptance Criteria

1. WHILE a cleanup operation is in progress, THE Cleaner SHALL display the current item being processed (path truncated to a maximum of 60 characters with trailing ellipsis if longer) and the percentage of total items completed as an integer from 0 to 100.
2. WHILE a cleanup operation is in progress, THE Cleaner SHALL display the cumulative space freed so far in human-readable units (bytes, KB, MB, or GB as appropriate to the magnitude).
3. WHEN a cleanup operation completes (regardless of whether errors occurred during processing), THE Cleaner SHALL display a summary including total items processed, total space freed, total errors encountered, and total elapsed time in seconds.
4. IF an error occurs during cleanup of a specific item, THEN THE Cleaner SHALL skip that item, record the error to the audit log with the item path, error description, and timestamp, and continue processing remaining items.
5. WHILE a cleanup operation is in progress, THE Cleaner SHALL update the displayed progress after each item is processed so that the percentage and cumulative space freed reflect the latest state.

### Requirement 4: Backup Before Delete

**User Story:** As a user, I want files to be backed up before deletion, so that I can recover them if needed.

#### Acceptance Criteria

1. WHEN the Cleaner processes a file for deletion after user confirmation, THE Backup_Module SHALL create a byte-for-byte copy of that file in the Backup_Root and verify the copy size matches the original file size before the file is removed from its original location.
2. THE Backup_Module SHALL preserve the original directory structure relative to the drive root within the Backup_Root, using the Cleanup_Session identifier as a top-level subdirectory to prevent filename collisions across sessions.
3. THE Backup_Module SHALL record metadata for each backed-up file including original absolute path, backup timestamp in ISO 8601 format, file size in bytes, and the associated Cleanup_Session identifier, persisted as a JSON file within the Backup_Root.
4. IF the Backup_Module fails to create a backup for a file due to insufficient disk space, permission error, or copy verification failure, THEN THE Cleaner SHALL skip deletion of that file, log the failure reason to the DrivePulse log directory, and continue processing remaining files.
5. WHEN a backup is created, THE Backup_Module SHALL assign it to the current Cleanup_Session, where a Cleanup_Session begins when the user initiates a cleanup operation and ends when all selected files have been processed or the user cancels.
6. IF the available disk space in the Backup_Root location is less than the total size of files queued for deletion, THEN THE Backup_Module SHALL notify the user before processing begins and allow the user to proceed with partial backup or cancel the operation.
7. WHEN a backup record exceeds the configured retention period (default: 7 days), THE Backup_Module SHALL automatically purge the expired backup files and their associated metadata during the next cleanup or restore operation.

### Requirement 5: Restore from Backup

**User Story:** As a user, I want to restore previously backed-up files to their original locations, so that I can recover from accidental deletions.

#### Acceptance Criteria

1. WHEN the user requests a restore of a specific file, THE Backup_Module SHALL copy the file from Backup_Root back to its original path, recreating any missing parent directories as needed.
2. WHEN the user requests a batch restore by Cleanup_Session, THE Backup_Module SHALL restore all files associated with that session to their original paths, recreating any missing parent directories as needed.
3. WHEN a restore operation completes, THE Backup_Module SHALL display a summary containing the number of files successfully restored, the number of files that failed, and the total size of restored files.
4. IF the original path of a file to be restored already contains a file, THEN THE Backup_Module SHALL prompt the user for confirmation before overwriting, and skip restoring that file if the user declines.
5. IF a restore operation fails for a specific file, THEN THE Backup_Module SHALL log the error to the DrivePulse log directory and continue restoring remaining files.
6. IF the user requests a restore of a file whose backup has been purged due to retention expiry, THEN THE Backup_Module SHALL display an error message indicating the backup is no longer available and skip that file.

### Requirement 6: Backup Retention Policy

**User Story:** As a user, I want old backups to be automatically cleaned up after 7 days, so that backup storage does not grow indefinitely.

#### Acceptance Criteria

1. THE Backup_Module SHALL use a default Retention_Period of 7 days.
2. WHEN the Cleaner starts a new Cleanup_Session, THE Backup_Module SHALL remove all backup files whose recorded backup timestamp is older than the Retention_Period.
3. WHEN expired backups are purged, THE Audit_Logger SHALL record each purged file with the action "auto-purge", including the file path, file size, and original backup timestamp.
4. THE Backup_Module SHALL allow the Retention_Period to be configured via the user config file with a valid range of 1 to 90 days.
5. IF the configured Retention_Period value is outside the valid range of 1 to 90 days or is not a valid integer, THEN THE Backup_Module SHALL ignore the invalid value, apply the default Retention_Period of 7 days, and display a warning message indicating the invalid configuration.
6. IF a backup file cannot be removed during a Cleanup_Session due to a file access error, THEN THE Backup_Module SHALL skip that file, continue processing remaining expired backups, and log the failure to the Audit_Logger with the action "purge-failed" and the file path.

### Requirement 7: Audit Logging

**User Story:** As a user, I want every cleanup action to be recorded in an audit log, so that I have a complete history of what was modified.

#### Acceptance Criteria

1. THE Audit_Logger SHALL write log entries to the Audit_Log file at `logs/audit.log` relative to the DrivePulse application root, appending each new entry to the end of the file without overwriting existing entries.
2. THE Audit_Logger SHALL write each log entry as a single JSON object on one line containing the following fields: timestamp in ISO 8601 format with UTC offset, action type as a string, absolute file path of the affected file, and current Windows username.
3. WHEN a file is deleted, THE Audit_Logger SHALL record an entry with action "delete".
4. WHEN a file is backed up, THE Audit_Logger SHALL record an entry with action "backup".
5. WHEN a file is restored, THE Audit_Logger SHALL record an entry with action "restore".
6. WHEN a file is moved to the Staging_Area, THE Audit_Logger SHALL record an entry with action "stage".
7. WHEN a staged or backed-up file is auto-purged, THE Audit_Logger SHALL record an entry with action "auto-purge".
8. IF the Audit_Log file does not exist, THEN THE Audit_Logger SHALL create the file and any missing parent directories before writing the first entry.
9. IF writing to the Audit_Log fails, THEN THE Audit_Logger SHALL write a warning message indicating the failure reason to the console and continue the cleanup operation without blocking.
10. WHEN the Audit_Logger writes an entry, THE Audit_Logger SHALL flush the entry to disk before returning control to the calling operation, ensuring no entry is lost if the application terminates unexpectedly.
11. IF the Audit_Log file exceeds 10 MB in size, THEN THE Audit_Logger SHALL rotate the file by renaming it with a timestamp suffix and creating a new empty Audit_Log file before writing the next entry.

### Requirement 8: Staging Area Management

**User Story:** As a user, I want files marked for deletion to be moved to a staging area first, so that I have a grace period before permanent removal.

#### Acceptance Criteria

1. WHEN the Cleaner executes a cleanup operation, THE Staging_Area SHALL move target files from their original location to the Staging_Root instead of deleting them immediately.
2. THE Staging_Area SHALL preserve the original directory structure relative to the drive root within the Staging_Root.
3. THE Staging_Area SHALL record metadata for each staged file including original path, staging timestamp, and file size in bytes.
4. WHEN the user requests a list of staged files, THE Staging_Area SHALL display all files currently in the Staging_Root with their original path, size, and staging date, sorted by staging date in descending order.
5. WHEN the user requests restoration of a staged file, THE Staging_Area SHALL move the file back to its original path and recreate any missing parent directories as needed.
6. IF the original path of a staged file to be restored already contains a file, THEN THE Staging_Area SHALL prompt the user for confirmation before overwriting.
7. WHEN a staged file has remained in the Staging_Root beyond the configured retention period (default: 7 days), THE Staging_Area SHALL permanently delete that file and its associated metadata.
8. IF the available disk space is insufficient to move a target file to the Staging_Root, THEN THE Staging_Area SHALL skip staging for that file, notify the user that the file could not be staged due to insufficient space, and leave the original file unmodified.

### Requirement 9: Staging Area Auto-Clean

**User Story:** As a user, I want staged files to be permanently deleted after 7 days, so that the staging area does not consume disk space indefinitely.

#### Acceptance Criteria

1. THE Staging_Area SHALL use a default Retention_Period of 7 days for staged files.
2. WHEN the Cleaner starts a new Cleanup_Session, THE Staging_Area SHALL permanently delete all staged files whose staging timestamp exceeds the Retention_Period.
3. WHEN a staged file is permanently deleted during auto-clean, THE Audit_Logger SHALL record the deleted file's original path, file size in bytes, staging timestamp, and the action "auto-purge".
4. THE Staging_Area SHALL allow the Retention_Period to be configured via the user config file with a value between 1 and 90 days inclusive, and SHALL fall back to the default of 7 days if the configured value is outside this range or non-numeric.
5. IF a staged file cannot be deleted during a Cleanup_Session due to a locked file or permission error, THEN THE Staging_Area SHALL skip that file, log a warning to the Audit_Logger with the file path and failure reason, and continue processing the remaining files.
6. WHEN the user launches DrivePulse, THE Cleaner SHALL start a Cleanup_Session before any other cleanup operations are performed.

### Requirement 10: CLI Cleanup Commands

**User Story:** As a user, I want cleanup commands accessible from the CLI menu, so that I can initiate and manage cleanup operations interactively.

#### Acceptance Criteria

1. THE CLI SHALL provide a menu option to start a cleanup operation that displays a dry-run preview listing only items categorized as "Aman Dihapus" (Safe) from the most recent scan, with each item's label and size.
2. WHEN the user selects the cleanup option and no scan result is available, THE CLI SHALL display a message indicating that a scan must be performed first and return the user to the main menu.
3. WHEN the user selects the cleanup option, THE CLI SHALL display categorized items from the most recent scan grouped into "Aman Dihapus" and "Perlu Dicek Manual" sections, showing each item's label and size, followed by a total reclaimable space summary.
4. IF the user confirms cleanup execution by entering "y" at the confirmation prompt, THEN THE CLI SHALL back up the selected items before deletion and execute the cleanup on items categorized as "Aman Dihapus" only.
5. IF the user declines cleanup execution by entering "n" or any input other than "y" at the confirmation prompt, THEN THE CLI SHALL cancel the operation without modifying any files and return the user to the main menu.
6. THE CLI SHALL display all cleanup-related text, prompts, and messages in Bahasa Indonesia.

### Requirement 11: CLI Backup Commands

**User Story:** As a user, I want backup and restore commands accessible from the CLI menu, so that I can manage my backups interactively.

#### Acceptance Criteria

1. THE CLI SHALL provide a menu option to list all available backups grouped by Cleanup_Session, displaying for each entry: original file path, file size, and backup timestamp.
2. THE CLI SHALL provide a menu option to restore a specific file from backup, allowing the user to select the target file by entering its displayed list number.
3. THE CLI SHALL provide a menu option to restore all files from a specific Cleanup_Session, allowing the user to select the session by entering its displayed list number.
4. WHEN no backups are available, THE CLI SHALL display a message indicating no backups exist.
5. THE CLI SHALL display all backup-related text in Bahasa Indonesia.
6. WHEN a restore operation completes successfully, THE CLI SHALL display a confirmation message indicating the number of files restored and their total size.
7. IF a restore operation fails due to a file conflict, insufficient permissions, or insufficient disk space, THEN THE CLI SHALL display an error message indicating the failure reason and preserve the backup data unchanged.

### Requirement 12: CLI Staging Commands

**User Story:** As a user, I want staging area commands accessible from the CLI menu, so that I can review and manage staged files interactively.

#### Acceptance Criteria

1. THE CLI SHALL provide a menu option to list all files currently in the Staging_Area, displaying for each file: original path, size in human-readable format (B, KB, MB, or GB as appropriate), and staging date in YYYY-MM-DD HH:mm format.
2. THE CLI SHALL provide a menu option to restore a specific file from the Staging_Area, where the user selects the file by entering its corresponding number from the displayed list.
3. IF the user selects the option to permanently delete a file from the Staging_Area, THEN THE CLI SHALL display a confirmation prompt before executing the deletion, and only proceed if the user explicitly confirms.
4. WHEN the Staging_Area is empty and the user selects any staging-related menu option, THE CLI SHALL display a message indicating no staged files exist and return the user to the previous menu.
5. THE CLI SHALL display all staging-related text in Bahasa Indonesia.
6. IF a restore operation fails because a file already exists at the original path, THEN THE CLI SHALL display an error message indicating the conflict and the conflicting path, without overwriting the existing file.

### Requirement 13: Audit Log Serialization

**User Story:** As a developer, I want the audit log to use a consistent, parseable format, so that log entries can be reliably read and analyzed.

#### Acceptance Criteria

1. THE Audit_Logger SHALL write each log entry as a single line of JSON containing the fields: timestamp (string, ISO 8601 format), action (string), file (string, absolute Windows path), and user (string), with each line terminated by a CRLF line ending.
2. THE Audit_Logger SHALL append new entries to the end of the Audit_Log file without modifying existing entries.
3. THE Audit_Logger SHALL produce JSON where parsing any written log line and extracting the timestamp, action, file, and user fields yields the original values without data loss (round-trip property), including correct JSON escaping of backslashes and special characters in file paths.
4. THE Audit_Logger SHALL use UTF-8 encoding without BOM (Byte Order Mark) for the Audit_Log file.
5. IF a log entry field value contains characters that are special in JSON (backslash, double quote, or control characters), THEN THE Audit_Logger SHALL escape them according to the JSON specification (RFC 8259) before writing the entry.
