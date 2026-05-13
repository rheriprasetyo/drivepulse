<#
.SYNOPSIS
    DrivePulse — Analisis drive C: dan rekomendasi pembersihan
.DESCRIPTION
    Scan folder-folder besar di C: drive, kategorikan item yang aman
    dihapus vs perlu dicek manual, dan kasih panduan cleanup.
.EXAMPLE
    .\scripts\analyze.ps1
.NOTES
    Author: Yombi + Heri Prasetyo R
    Requires: Windows PowerShell 5.1+
#>

# ──────────────────────────────────────────────
# 1. Cek admin rights
# ──────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "⚠️  Sebaiknya jalanin sebagai Administrator (klik kanan PowerShell → Run as Administrator)" -ForegroundColor Yellow
    Write-Host "   Biar hasil scanning lebih lengkap. Tapi tetep bisa jalan kok.\n" -ForegroundColor Gray
}

# ──────────────────────────────────────────────
# 2. Header
# ──────────────────────────────────────────────
Write-Host "╔══════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║        🧹  DrivePulse v1.0           ║" -ForegroundColor Cyan
Write-Host "║   Analisis & Panduan Bersihin C:     ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ──────────────────────────────────────────────
# 3. Scan drive info
# ──────────────────────────────────────────────
Write-Host "⏳ Scanning C: Drive..." -ForegroundColor Green

$drive = Get-PSDrive C
$usedGB = [math]::Round($drive.Used / 1GB, 2)
$freeGB = [math]::Round($drive.Free / 1GB, 2)
$totalGB = [math]::Round(($drive.Used + $drive.Free) / 1GB, 2)
$usedPct = [math]::Round(($drive.Used / ($drive.Used + $drive.Free)) * 100, 1)

Write-Host ""
Write-Host "📊  Status C: Drive" -ForegroundColor Cyan
Write-Host "──────────────────────────────────────"

# Color based on usage
$color = if ($usedPct -ge 90) { "Red" } elseif ($usedPct -ge 75) { "Yellow" } else { "Green" }
Write-Host ("  Total     : {0} GB" -f $totalGB) -ForegroundColor Gray
Write-Host ("  Terpakai  : {0} GB" -f $usedGB) -ForegroundColor $color
Write-Host ("  Sisa      : {0} GB" -f $freeGB) -ForegroundColor $color
Write-Host ("  Terpakai  : {0}%" -f $usedPct) -ForegroundColor $color

# Progress bar
$barSize = 30
$filled = [math]::Round(($usedPct / 100) * $barSize)
$empty = $barSize - $filled
$bar = "█" * $filled + "░" * $empty
Write-Host ("  [{0}]" -f $bar) -ForegroundColor $color
Write-Host ""

# ──────────────────────────────────────────────
# 4. Scan folder besar
# ──────────────────────────────────────────────
Write-Host "⏳ Menganalisis folder besar..." -ForegroundColor Green

$scanTargets = @(
    @{ Path = "$env:TEMP"; Label = "User Temp"; Category = "safe" }
    @{ Path = "C:\Windows\Temp"; Label = "Windows Temp"; Category = "safe" }
    @{ Path = "C:\`$Recycle.Bin"; Label = "Recycle Bin"; Category = "safe" }
    @{ Path = "$env:LOCALAPPDATA\npm-cache"; Label = "npm cache"; Category = "safe" }
    @{ Path = "$env:LOCALAPPDATA\pip"; Label = "pip cache"; Category = "safe" }
    @{ Path = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"; Label = "Chrome Cache"; Category = "safe" }
    @{ Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"; Label = "Edge Cache"; Category = "safe" }
    @{ Path = "$env:APPDATA\Zoom"; Label = "Zoom Cache"; Category = "safe" }
    @{ Path = "C:\Windows\Prefetch"; Label = "Windows Prefetch"; Category = "safe" }
    @{ Path = "$env:USERPROFILE\Downloads"; Label = "Downloads"; Category = "check" }
    @{ Path = "$env:LOCALAPPDATA\CapCut"; Label = "CapCut (Video Editor)"; Category = "check" }
    @{ Path = "C:\3uTools"; Label = "3uTools (iOS)"; Category = "check" }
    @{ Path = "$env:LOCALAPPDATA\Android"; Label = "Android SDK"; Category = "check" }
    @{ Path = "$env:USERPROFILE\Videos"; Label = "Videos"; Category = "check" }
    @{ Path = "$env:USERPROFILE\Music"; Label = "Music"; Category = "check" }
)

$results = @()
$totalSafe = 0
$totalCheck = 0

foreach ($target in $scanTargets) {
    $path = $target.Path
    if (Test-Path $path) {
        try {
            $size = (Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue | 
                     Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            if ($size -and $size -gt 0) {
                $sizeGB = [math]::Round($size / 1GB, 2)
                $sizeMB = [math]::Round($size / 1MB, 0)
                
                $results += [PSCustomObject]@{
                    Item = $target.Label
                    Path = $path
                    SizeGB = $sizeGB
                    SizeMB = $sizeMB
                    Category = $target.Category
                }
                
                if ($target.Category -eq "safe") { $totalSafe += $size }
                else { $totalCheck += $size }
            }
        } catch {
            # Skip folder yang gak bisa diakses
        }
    }
}

# Sort by size descending
$results = $results | Sort-Object SizeGB -Descending

# ──────────────────────────────────────────────
# 5. Tampilkan hasil
# ──────────────────────────────────────────────
Write-Host ""
Write-Host "📋  Hasil Analisis" -ForegroundColor Cyan
Write-Host "──────────────────────────────────────"

Write-Host "" 
Write-Host "✅  AMAN DIHAPUS" -ForegroundColor Green
$safeItems = $results | Where-Object { $_.Category -eq "safe" }
if ($safeItems) {
    $safeItems | ForEach-Object {
        $displaySize = if ($_.SizeGB -ge 1) { "{0:N2} GB" -f $_.SizeGB } else { "{0} MB" -f $_.SizeMB }
        Write-Host ("  • {0,-25} {1,8}" -f $_.Item, $displaySize) -ForegroundColor White
    }
} else {
    Write-Host "  (tidak ada)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "❓  PERLU DICEK MANUAL" -ForegroundColor Yellow
$checkItems = $results | Where-Object { $_.Category -eq "check" }
if ($checkItems) {
    $checkItems | ForEach-Object {
        $displaySize = if ($_.SizeGB -ge 1) { "{0:N2} GB" -f $_.SizeGB } else { "{0} MB" -f $_.SizeMB }
        Write-Host ("  • {0,-25} {1,8}" -f $_.Item, $displaySize) -ForegroundColor White
    }
} else {
    Write-Host "  (tidak ada)" -ForegroundColor Gray
}

# ──────────────────────────────────────────────
# 6. Ringkasan
# ──────────────────────────────────────────────
$totalSafeGB = [math]::Round($totalSafe / 1GB, 2)
$totalCheckGB = [math]::Round($totalCheck / 1GB, 2)
$totalPotential = $totalSafeGB + $totalCheckGB

Write-Host ""
Write-Host "📈  RINGKASAN" -ForegroundColor Cyan
Write-Host "──────────────────────────────────────"
Write-Host ("  ✅ Aman dihapus     : {0,6} GB" -f $totalSafeGB) -ForegroundColor Green
Write-Host ("  ❓ Perlu dicek      : {0,6} GB" -f $totalCheckGB) -ForegroundColor Yellow
Write-Host ("  ─────────────────────────")
Write-Host ("  🎯 Potensi kosong   : {0,6} GB" -f $totalPotential) -ForegroundColor Magenta
Write-Host ""

# ──────────────────────────────────────────────
# 7. Rekomendasi
# ──────────────────────────────────────────────
Write-Host "💡  REKOMENDASI" -ForegroundColor Cyan
Write-Host "──────────────────────────────────────"

if ($usedPct -ge 90) {
    Write-Host "  🔴 CRITICAL! Drive hampir penuh. Segera bersihin!" -ForegroundColor Red
} elseif ($usedPct -ge 75) {
    Write-Host "  🟡 Warning. Mulai banyak sampah, yuk dibersihin." -ForegroundColor Yellow
} else {
    Write-Host "  🟢 Masih aman. Tapi tetap jaga kebersihan ya~" -ForegroundColor Green
}

Write-Host ""
Write-Host "  Langkah selanjutnya:" -ForegroundColor White
Write-Host "  1. Baca panduan lengkap di: docs\guide.md" -ForegroundColor Gray
Write-Host "  2. Atau ikutin menu interaktif di bawah" -ForegroundColor Gray
Write-Host ""

# ──────────────────────────────────────────────
# 8. Menu interaktif
# ──────────────────────────────────────────────
Write-Host "📌  PILIHAN" -ForegroundColor Cyan
Write-Host "──────────────────────────────────────"
Write-Host "  1. Lihat detail folder (path lengkap)" -ForegroundColor White
Write-Host "  2. Tampilkan panduan bersihin" -ForegroundColor White
Write-Host "  3. Export report ke file" -ForegroundColor White
Write-Host "  4. Keluar" -ForegroundColor White
Write-Host ""

$choice = Read-Host "  Pilih (1-4)"
Write-Host ""

switch ($choice) {
    "1" {
        Write-Host "📁  DETAIL FOLDER" -ForegroundColor Cyan
        Write-Host "──────────────────────────────────────"
        $results | ForEach-Object {
            $displaySize = if ($_.SizeGB -ge 1) { "{0:N2} GB" -f $_.SizeGB } else { "{0} MB" -f $_.SizeMB }
            $icon = if ($_.Category -eq "safe") { "✅" } else { "❓" }
            Write-Host ("  {0} {1}" -f $icon, $_.Item) -ForegroundColor White
            Write-Host ("     Lokasi: {0}" -f $_.Path) -ForegroundColor Gray
            Write-Host ("     Ukuran: {0}" -f $displaySize) -ForegroundColor Gray
            Write-Host ""
        }
    }
    "2" {
        Write-Host "📖  PANDUAN CEPAT" -ForegroundColor Cyan
        Write-Host "──────────────────────────────────────"
        Write-Host ""
        Write-Host "  ✅ AMAN DIHAPUS (bisa langsung):" -ForegroundColor Green
        Write-Host "  • Buka Run (Win+R) → ketik %temp% → Ctrl+A → Shift+Delete"
        Write-Host "  • Buka Run → cleanmgr → pilih C: → bersihin"
        Write-Host "  • npm cache: npm cache clean --force"
        Write-Host ""
        Write-Host "  ❓ PERLU DICEK DULU:" -ForegroundColor Yellow
        Write-Host "  • Downloads → buka foldernya, hapus installer lama"
        Write-Host "  • CapCut → cek project yang udah selesai"
        Write-Host "  • 3uTools → kalo backup udah gak dipake, hapus"
        Write-Host ""
        Write-Host "  📖 Panduan lengkap: buka docs\guide.md" -ForegroundColor Gray
    }
    "3" {
        $reportFile = "$PSScriptRoot\..\report-drivepulse-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
        $results | Format-Table -AutoSize | Out-File $reportFile
        Write-Host ("  ✅ Report tersimpan: {0}" -f $reportFile) -ForegroundColor Green
    }
    default {
        Write-Host "  Sip, sampai jumpa! 🦥" -ForegroundColor Cyan
    }
}

Write-Host ""
Write-Host "╔══════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   Udah dibantu Yombi 🦥              ║" -ForegroundColor Cyan
Write-Host "║   Kalo bingung, hubungi @rheriprasetyo║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════╝" -ForegroundColor Cyan
