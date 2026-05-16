# Prompt untuk Kiro — Implementasi Selective Cleanup

## Goal
Tambah fitur **selective cleanup** di `src/cleaner/clean.ps1` dan `src/ui/cli.ps1`. User bisa memilih item tertentu dari list preview sebelum cleanup dieksekusi, bukan "all-or-nothing".

## Branch
`feature/selective-cleanup` (dari master)
GitHub Issue: #12

## File yang berubah
- `src/cleaner/clean.ps1` — utama
- `src/ui/cli.ps1` — opsional kalo butuh

## Detail implementasi

### 1. Modifikasi `Show-CleanupPreview` di `clean.ps1`

Tambah nomor urut `[1]`, `[2]`, dll di setiap item yang ditampilkan.

### 2. Fungsi baru: `Invoke-ItemSelection` di `clean.ps1`

```powershell
function Invoke-ItemSelection {
    <#
    .SYNOPSIS
        Meminta user memilih item dari preview list.
    .DESCRIPTION
        Support input format: "1,3,5", "1-5", "all", atau Enter kosong.
        Return array indeks (0-based) atau $null jika batal.
    .PARAMETER TotalItems
        Total jumlah item yang bisa dipilih
    .OUTPUTS
        [int[]] atau $null
    #>
    param([int]$TotalItems)
    
    # Logic:
    # - Parse comma-separated: "1,3,5" → @(0,2,4)
    # - Parse range: "1-5" → @(0,1,2,3,4)
    # - Keyword "all" → @(0..TotalItems-1)
    # - Enter kosong → return $null
    # - Invalid → retry maks 3x, lalu return $null
    # - Index out of range → skip & warning
}
```

### 3. Modifikasi `Start-SafeCleanup` di `clean.ps1`

**Tambah parameter baru:**
```powershell
function Start-SafeCleanup {
    param(
        [Parameter(Mandatory)]
        [PSCustomObject[]]$Items,
        
        [switch]$DryRun,
        [switch]$Force,
        [string]$SessionId,
        
        # BARU:
        [switch]$InteractiveSelect  # Jika true, tanya user pilih item di preview
    )
```

**Flow baru setelah preview:**
1. Preview muncul dengan nomor urut
2. Tanya: "Pilih item yang ingin dibersihkan (1,3,5 / 1-5 / all):"
3. Panggil `Invoke-ItemSelection`
4. Filter `$safeItems` berdasarkan hasil selection
5. Display "Anda akan membersihkan N item (XX GB)"
6. Tanya konfirmasi akhir "Lanjutkan? (y/n)"
7. Baru eksekusi backup → staging untuk item yang dipilih

### 4. CLI menu (`cli.ps1`) — OPSIONAL

Post-scan menu sekarang sudah ada [5] Bersihkan. Hanya perlu pastiin panggilan ke `Start-SafeCleanup` pake parameter `-InteractiveSelect:$true` biar selective mode aktif.

## Notes penting
- Jaga backward compatibility: `Start-SafeCleanup` tanpa `-InteractiveSelect` harus tetap behave seperti sekarang (all-or-nothing)
- Dry-run mode tetap jalan: preview tetap gak modify file apapun
- Handle edge case: user masukkan nomor yang gak valid → retry atau skip
- Test case: "all", "1", "1-3", "1,3,5", "", invalid, out-of-range

## Requirements terkait
- Req 1 (Cleanup Preview & Dry-Run)
- Req 2 (Interactive Confirmation) — bisa reuse logika konfirmasi existing
- Req 10 (CLI Cleanup Commands)

## Commit message template
```
feat: selective cleanup — user bisa pilih item dari preview

- Show-CleanupPreview: tambah nomor urut per item
- Invoke-ItemSelection: parse input "1,3,5", "1-5", "all"
- Start-SafeCleanup: support parameter -InteractiveSelect
- Filter safeItems berdasarkan user selection sebelum eksekusi
- Tanya konfirmasi akhir setelah selection
- Backward compatible: tanpa -InteractiveSelect = all-or-nothing

Closes #12
```

## Simpan prompt ini ke file kalau perlu:
`D:\saas\drivepulse\.kiro\prompts\selective-cleanup.md`
