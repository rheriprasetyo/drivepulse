<#
.SYNOPSIS DrivePulse entry point — imports modules and launches CLI
#>

# Import CLI module (which imports scanner + categorizer)
. "$PSScriptRoot\..\src\ui\cli.ps1"

# Check admin status
$Script:IsAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

# Show admin info message (one-time, per Requirement 6.4)
if (-not $Script:IsAdmin) {
    Show-AdminInfoMessage
}

# Launch interactive menu
Show-MainMenu
