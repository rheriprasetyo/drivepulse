# Implementation Plan: Safety Cleanup

## Overview

This plan implements the DrivePulse v1.3 Safety & Cleanup feature, transforming the application from a read-only disk analysis tool into a safe, reversible cleanup tool. Implementation follows the safety-first architecture: dry-run → preview → confirm → backup → stage → auto-purge. Tasks are ordered to build foundational modules first (audit, backup, staging), then the orchestrator (cleaner), and finally the CLI integration.

## Tasks

- [x] 1. Set up module structure and shared utilities
  - [x] 1.1 Create audit logger module with core functions
    - Create `src/audit/audit.ps1` with `Write-AuditEntry`, `Initialize-AuditLog`, and `Get-AuditLogPath` functions
    - Implement single-line JSON serialization with proper escaping (RFC 8259)
    - Implement append-only writes with CRLF line endings and flush-to-disk
    - Implement log rotation when file exceeds 10 MB
    - Use UTF-8 without BOM encoding
    - _Requirements: 7.1, 7.2, 7.8, 7.9, 7.10, 7.11, 13.1, 13.2, 13.3, 13.4, 13.5_

  - [x]* 1.2 Write property tests for audit logger
    - **Property 8: Audit log entry round-trip serialization**
    - **Property 9: Audit log append-only invariant**
    - **Property 10: Audit log rotation threshold**
    - Create `tests/property/audit.Property.Tests.ps1`
    - Add `New-RandomAuditEntry` generator to `tests/helpers/generators.ps1`
    - **Validates: Requirements 7.1, 7.2, 7.11, 13.1, 13.2, 13.3, 13.5**

  - [x]* 1.3 Write unit tests for audit logger
    - Create `tests/unit/audit.Tests.ps1`
    - Test: audit log file creation when missing (Req 7.8)
    - Test: directory creation when missing (Req 7.8)
    - Test: warning on write failure without blocking (Req 7.9)
    - Test: UTF-8 without BOM encoding (Req 13.4)
    - Test: flush to disk before returning (Req 7.10)
    - _Requirements: 7.8, 7.9, 7.10, 13.4_

- [x] 2. Implement backup module
  - [x] 2.1 Create backup module with core functions
    - Create `src/backup/backup.ps1` with `Backup-BeforeDelete`, `Restore-FromBackup`, `Get-AvailableBackups`, `Remove-ExpiredBackups`, and `Test-BackupSpace` functions
    - Implement byte-for-byte copy with size verification
    - Preserve directory structure using drive-encoded paths under session subdirectory
    - Write `backup-manifest.json` per session with metadata (original path, timestamp, size, sessionId)
    - Implement retention-based purge with configurable period (1-90 days, default 7)
    - Integrate with audit logger for backup/restore/auto-purge/purge-failed actions
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6_

  - [x]* 2.2 Write property tests for backup module
    - **Property 5: Backup byte-for-byte round-trip**
    - **Property 6: Backup structure and metadata preservation**
    - **Property 7: Retention-based purge correctness**
    - Create `tests/property/backup.Property.Tests.ps1`
    - Add `New-RandomSessionId`, `New-RandomFileContent`, `New-RandomRetentionDays`, `New-RandomTimestamp` generators to `tests/helpers/generators.ps1`
    - **Validates: Requirements 4.1, 4.2, 4.3, 4.5, 4.7, 5.1, 6.2, 6.4, 6.5**

  - [x]* 2.3 Write unit tests for backup module
    - Create `tests/unit/backup.Tests.ps1`
    - Test: skip deletion on backup failure (Req 4.4)
    - Test: insufficient space notification (Req 4.6)
    - Test: restore recreates missing parent directories (Req 5.1)
    - Test: batch restore by session (Req 5.2)
    - Test: restore summary display (Req 5.3)
    - Test: prompt on file conflict during restore (Req 5.4)
    - Test: continue on restore failure (Req 5.5)
    - Test: error when backup purged (Req 5.6)
    - Test: invalid retention falls back to default 7 (Req 6.5)
    - Test: skip and log on purge file access error (Req 6.6)
    - _Requirements: 4.4, 4.6, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 6.5, 6.6_

- [x] 3. Implement staging module
  - [x] 3.1 Create staging module with core functions
    - Create `src/staging/staging.ps1` with `Move-ToStaging`, `Restore-FromStaging`, `Get-StagedFiles`, `Remove-ExpiredStaged`, and `Remove-StagedFile` functions
    - Implement file move preserving directory structure with drive-encoded paths
    - Maintain `staging-manifest.json` with metadata (original path, staged path, size, timestamp, sessionId)
    - Implement retention-based auto-purge (1-90 days, default 7)
    - Integrate with audit logger for stage/auto-purge actions
    - Sort staged files by timestamp descending
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7, 8.8, 9.1, 9.2, 9.3, 9.4, 9.5_

  - [x]* 3.2 Write property tests for staging module
    - **Property 11: Staging moves files preserving structure**
    - **Property 12: Staged files list sort order**
    - **Property 13: Staging restore round-trip**
    - Create `tests/property/staging.Property.Tests.ps1`
    - Add `New-RandomStagedFile` generator to `tests/helpers/generators.ps1`
    - **Validates: Requirements 8.1, 8.2, 8.3, 8.4, 8.5**

  - [x]* 3.3 Write unit tests for staging module
    - Create `tests/unit/staging.Tests.ps1`
    - Test: prompt on file conflict during restore (Req 8.6)
    - Test: skip on insufficient space (Req 8.8)
    - Test: auto-purge after retention period (Req 8.7, 9.2)
    - Test: invalid retention falls back to default 7 (Req 9.4)
    - Test: skip and log on locked file during purge (Req 9.5)
    - Test: empty staging area behavior (Req 12.4)
    - _Requirements: 8.6, 8.7, 8.8, 9.2, 9.4, 9.5, 12.4_

- [x] 4. Checkpoint - Core modules complete
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. Implement cleaner orchestrator
  - [x] 5.1 Update cleaner module with safe cleanup orchestration
    - Update `src/cleaner/clean.ps1` with `Start-SafeCleanup`, `Get-CleanupPreview`, and `Show-CleanupProgress` functions
    - Implement dry-run mode as default (no filesystem modifications)
    - Implement preview with item count, total size, per-item details
    - Implement confirmation prompt in Bahasa Indonesia (proceed only on "y"/"Y")
    - Generate unique session ID (YYYYMMDD-HHmmss-<6 hex>)
    - Orchestrate: purge expired → backup → stage → progress → summary
    - Filter to "Safe" category items only for execution
    - Implement skip-and-continue error handling per item
    - Display progress with truncated path (60 chars + "..."), percentage, cumulative space freed
    - Display completion summary (items processed, space freed, errors, elapsed time)
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 2.1, 2.2, 2.3, 2.4, 2.5, 3.1, 3.2, 3.3, 3.4, 3.5, 9.6, 10.4_

  - [x]* 5.2 Write property tests for cleaner orchestrator
    - **Property 1: Dry-run filesystem invariance**
    - **Property 2: Preview completeness and correctness**
    - **Property 3: Progress tracking correctness**
    - **Property 4: Error resilience — skip and continue**
    - **Property 14: Safe-only cleanup filter**
    - Create `tests/property/cleanup.Property.Tests.ps1`
    - Add `New-RandomBackupManifest` generator to `tests/helpers/generators.ps1`
    - **Validates: Requirements 1.2, 1.3, 1.4, 1.6, 2.1, 2.3, 3.1, 3.2, 3.4, 3.5, 4.4, 5.5, 10.4**

  - [x]* 5.3 Write unit tests for cleaner orchestrator
    - Create `tests/unit/cleanup.Tests.ps1`
    - Test: default mode is dry-run (Req 1.1)
    - Test: empty item list shows message, no prompt (Req 1.7, 2.5)
    - Test: confirmation with "y"/"Y" proceeds (Req 2.2)
    - Test: non-"y" input aborts with Bahasa Indonesia message (Req 2.3, 2.4)
    - Test: completion summary fields (Req 3.3)
    - Test: only "Safe" items processed (Req 10.4)
    - _Requirements: 1.1, 1.7, 2.2, 2.3, 2.4, 2.5, 3.3, 10.4_

- [x] 6. Extend configuration manager
  - [x] 6.1 Add retention period settings to config manager
    - Update `src/config/config-manager.ps1` to support `backupRetentionDays` and `stagingRetentionDays` fields
    - Validate range 1-90 days, fall back to default 7 on invalid values
    - Display warning on invalid configuration
    - _Requirements: 6.4, 6.5, 9.4_

- [x] 7. Implement CLI menu extensions
  - [x] 7.1 Add cleanup menu option to CLI
    - Update `src/ui/cli.ps1` with menu option `[5] Bersihkan` for cleanup
    - Display categorized items from most recent scan ("Aman Dihapus" and "Perlu Dicek Manual" sections)
    - Show total reclaimable space summary
    - Handle case when no scan result is available (display message, return to menu)
    - All text in Bahasa Indonesia
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5, 10.6_

  - [x] 7.2 Add backup menu option to CLI
    - Update `src/ui/cli.ps1` with menu option `[6] Backup` for backup management
    - List backups grouped by session (path, size, timestamp)
    - Restore specific file by list number
    - Restore all files from a session by list number
    - Handle empty backup state
    - Display restore summary (count, size)
    - Handle restore errors (conflict, permissions, space)
    - All text in Bahasa Indonesia
    - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5, 11.6, 11.7_

  - [x] 7.3 Add staging menu option to CLI
    - Update `src/ui/cli.ps1` with menu option `[7] Staging` for staging management
    - List staged files (original path, human-readable size, date in YYYY-MM-DD HH:mm)
    - Restore specific file by list number
    - Permanently delete with confirmation prompt
    - Handle empty staging state
    - Handle restore conflict error
    - All text in Bahasa Indonesia
    - _Requirements: 12.1, 12.2, 12.3, 12.4, 12.5, 12.6_

- [x] 8. Checkpoint - All modules integrated
  - Ensure all tests pass, ask the user if questions arise.

- [x] 9. Integration testing
  - [x]* 9.1 Write integration tests for cleanup flow
    - Create `tests/integration/cleanup-flow.Tests.ps1`
    - Test full cycle: scan → preview → confirm → backup → stage → verify
    - Test retention purge: create old entries → start session → verify purge
    - _Requirements: 1.1, 1.2, 1.5, 4.1, 8.1, 6.2, 9.2_

  - [x]* 9.2 Write integration tests for restore flow
    - Create `tests/integration/restore-flow.Tests.ps1`
    - Test restore cycle: backup → stage → restore from backup → verify content
    - Test staging restore: stage → restore from staging → verify content
    - _Requirements: 5.1, 5.2, 8.5_

- [x] 10. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties from the design document
- Unit tests validate specific examples and edge cases
- The project uses PowerShell 5.1 with Pester 5.x for testing
- All user-facing text must be in Bahasa Indonesia
- Custom generators are added incrementally to `tests/helpers/generators.ps1`

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2", "1.3", "2.1", "3.1"] },
    { "id": 2, "tasks": ["2.2", "2.3", "3.2", "3.3"] },
    { "id": 3, "tasks": ["5.1", "6.1"] },
    { "id": 4, "tasks": ["5.2", "5.3", "7.1", "7.2", "7.3"] },
    { "id": 5, "tasks": ["9.1", "9.2"] }
  ]
}
```
