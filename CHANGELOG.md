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

## [Unreleased]

### Planned (v1.1 — Core Scanner)
- Scanner lengkap: Quick Scan + Deep Scan
- CLI interaktif dengan menu pilihan
- Kategorisasi otomatis (aman / perlu dicek)
- Dry-run output dengan penjelasan Bahasa Indonesia
- Cleanup guide per item

---

> Format entry untuk rilis mendatang:
> ### Added — fitur baru
> ### Changed — perubahan di fitur existing
> ### Fixed — bug fix
> ### Removed — fitur yang dihapus
> ### Security — perbaikan keamanan
