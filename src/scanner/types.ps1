<#
.SYNOPSIS
    DrivePulse — Definisi Tipe File & Folder
.DESCRIPTION
    Definisi tipe-tipe file dan folder yang dikenali DrivePulse,
    termasuk pattern matching dan metadata.
.NOTES
    Author: DrivePulse Team
    Status: Skeleton — belum diimplementasi
#>

# TODO: Implementasi di milestone v1.1
# - Definisi file types (installer, cache, temp, media, document, dll)
# - Pattern matching rules
# - Size threshold definitions

# Enum kategori
$Script:Categories = @{
    Safe    = "safe"      # Aman dihapus langsung
    Check   = "check"     # Perlu dicek user
    System  = "system"    # Jangan disentuh
    Unknown = "unknown"   # Belum dikategorikan
}

# Known safe patterns
$Script:SafePatterns = @(
    "*.tmp",
    "*.temp",
    "*.log",
    "thumbs.db",
    "desktop.ini"
)
