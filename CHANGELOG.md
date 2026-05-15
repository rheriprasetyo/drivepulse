# 📋 Changelog

Semua perubahan penting di project DrivePulse dicatat di sini.

Format mengikuti [Keep a Changelog](https://keepachangelog.com/id-ID/1.1.0/), versioning mengikuti [Semantic Versioning](https://semver.org/).

---

## [1.0.0] — 2026-05-14

### Added
- PRD v1.1 — Product Requirements Document lengkap dengan:
  - Diferensiasi vs kompetitor (matrix)
  - Trust & Safety Principles
  - Acceptance Criteria (testable)
  - Permission & Security model
  - Error states handling
  - Minimum requirements
- README.md — revamp dengan:
  - Quick Start guide yang ramah user awam
  - FAQ section
  - Keamanan & Privasi statement
  - Roadmap dengan status visual
- `scripts/analyze.ps1` — skeleton entry point
- `docs/guide.md` — panduan cleanup dasar
- `.gitignore` — ignore file standar Windows/PowerShell
- `LICENSE` — MIT License
- `CHANGELOG.md` — file ini

### Defined
- Struktur folder project (`src/`, `scripts/`, `docs/`, `config/`, `tests/`, `installer/`, `assets/`)
- Kriteria "Aman vs Perlu Dicek" dengan kolom efek samping
- Quick Scan (< 15 detik) vs Deep Scan (< 60 detik)
- Dry-run mode sebagai default behavior
- Roadmap 6 milestone (v1.0 → v3.0)

---

## [1.1.0] — 2026-05-14

### Added
- Core Scanner implementation:
  - Quick Scan + Deep Scan modes
  - CLI interaktif dengan menu pilihan
  - Kategorisasi otomatis (Aman / Perlu Dicek / Tidak Diketahui)
  - Dry-run output dengan penjelasan Bahasa Indonesia
  - Cleanup guide per item
  - Unit tests + Property tests (100+ iterasi)
  - Integration tests
  - Config file (`config/default-rules.json`)
- Fixed issues #1-#4 via PR #5

### Changed
- Updated PRD to v1.1 dengan:
  - Safety Principles
  - Acceptance Criteria
  - Competitor Matrix
  - Permission & Security Model

---

## [1.2.0] — 2026-05-15

### Added
- HTML Report Generator:
  - Generate report visual dari hasil scan
  - Template HTML dengan CSS styling & progress bar
  - Replace placeholders: `{{DATE}}`, `{{DRIVE}}`, `{{TOTAL_GB}}`, `{{USED_GB}}`, `{{USED_PCT}}`
  - Color coding: merah (>90%), kuning (75-90%), hijau (<75%)
- TXT Report Generator:
  - Plain text format untuk export sederhana
  - Human-readable output
- User Preferences (Whitelist):
  - `config/whitelist.json` — folder yang gak boleh dihapus
  - CLI flag `--whitelist` — load whitelist dari config
  - CLI flag `--no-whitelist` — override whitelist
- Config Manager:
  - `src/config/config-manager.ps1` — manage user preferences
  - Load/save config dari/to JSON
- Comprehensive Tests:
  - Unit tests (`tests/unit/report.Tests.ps1`)
  - Property tests (`tests/property/report.Property.Tests.ps1`)
  - Integration tests (`tests/integration/report-export.Tests.ps1`)
- Kiro Specs:
  - `.kiro/specs/report-config/` — requirements, design, tasks

### Changed
- Improved `src/reporter/template.html`:
  - Dark theme styling
  - Responsive design untuk mobile
  - Progress bar visual untuk storage usage
- Updated `src/ui/cli.ps1`:
  - Add report generation commands
  - Export functionality
  - Whitelist support
- Updated `tests/helpers/generators.ps1`:
  - Test data generators

### Fixed
- Resolved issues #1-#4 (v1.1)
- Fixed color coding logic for drive status
- Improved error handling in report generation

---

## [1.3.0] — 2026-05-15

### Added
- Safety & Cleanup Module:
  - One-click cleanup dengan preview (dry-run default)
  - Interactive confirmation workflow
  - Progress tracking & reporting
  - `src/cleaner/clean.ps1` — core cleanup logic
- Backup & Restore System:
  - `src/backup/backup.ps1` — backup before delete
  - `src/backup/restore.ps1` — restore from backup
  - Rollback functionality
  - 7-day retention policy
  - Auto-clean old backups
- Audit Logging System:
  - `src/audit/audit.ps1` — log semua actions
  - Log file: `logs/audit.log`
  - Timestamp, action, file, user tracking
  - Searchable audit history
- Staging Area:
  - `src/staging/staging.ps1` — staging untuk file yang akan dihapus
  - List staging files
  - Restore from staging
  - Auto-clean after 7 days
- CLI Commands:
  - `cleanup --preview` — preview cleanup
  - `cleanup --execute` — execute cleanup
  - `backup --create` — create backup
  - `backup --restore` — restore from backup
  - `staging --list` — list staging files
  - `staging --restore` — restore from staging
  - `audit --list` — list audit logs
  - `audit --search` — search audit logs
- Comprehensive Tests:
  - Unit tests (`cleanup.Tests.ps1`, `backup.Tests.ps1`, `audit.Tests.ps1`, `staging.Tests.ps1`)
  - Property tests (`cleanup.Property.Tests.ps1`, `backup.Property.Tests.ps1`, `audit.Property.Tests.ps1`, `staging.Property.Tests.ps1`)
  - Integration tests (`cleanup-flow.Tests.ps1`, `restore-flow.Tests.ps1`)
  - CLI tests (`cli-cleanup.Tests.ps1`, `backup-menu.Tests.ps1`, `config-retention.Tests.ps1`)
- Kiro Specs:
  - `.kiro/specs/safety-cleanup/` — requirements, design, tasks

### Changed
- Updated `src/ui/cli.ps1`:
  - Add cleanup, backup, staging, audit commands
  - Interactive menu untuk safety features
  - Enhanced error handling
- Updated `tests/helpers/generators.ps1`:
  - Test data generators untuk cleanup/backup/staging
- Updated `tests/integration/cli-menu.Tests.ps1`:
  - CLI menu integration tests

### Fixed
- Improved error handling in backup operations
- Fixed retention policy enforcement
- Enhanced staging area cleanup logic
- Better progress tracking in cleanup workflow

### Security
- Audit log untuk semua sensitive operations
- Dry-run mode default untuk cleanup
- Confirmation required before delete
- 7-day retention policy untuk staging & backups

---

## [Unreleased]

### Planned (v1.4 — Installer)
- Build installer (.exe) untuk end-user
- Auto-detect Windows version
- Silent install option
- Desktop shortcut creation
- Auto-update mechanism
- System integration (right-click context menu)

### Planned (v2.0 — GUI Desktop App)
- GUI desktop application (Electron/Tauri)
- Drag & drop folder scanning
- Real-time progress visualization
- Export report ke PDF/Excel
- Mobile app integration
- Cloud sync for settings & logs

---

> Format entry untuk rilis mendatang:
> ### Added — fitur baru
> ### Changed — perubahan di fitur existing
> ### Fixed — bug fix
> ### Removed — fitur yang dihapus
> ### Security — perbaikan keamanan

### Planned (v1.4 — Installer)
- Build installer (.exe) untuk end-user
- Auto-detect Windows version
- Silent install option
- Desktop shortcut creation

### Planned (v2.0 — GUI Desktop App)
- GUI desktop application (Electron/Tauri)
- Drag & drop folder scanning
- Real-time progress visualization
- Export report ke PDF/Excel
- Mobile app integration

---

> Format entry untuk rilis mendatang:
> ### Added — fitur baru
> ### Changed — perubahan di fitur existing
> ### Fixed — bug fix
> ### Removed — fitur yang dihapus
> ### Security — perbaikan keamanan

---

> Format entry untuk rilis mendatang:
> ### Added — fitur baru
> ### Changed — perubahan di fitur existing
> ### Fixed — bug fix
> ### Removed — fitur yang dihapus
> ### Security — perbaikan keamanan
