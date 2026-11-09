[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('server', 'agent')]
    [string]$Role,

    [string]$WslDistribution = 'Ubuntu'
)

$ErrorActionPreference = 'Stop'
$roleName = $Role.ToLowerInvariant()

# Use the same Linux installer on native Linux and in WSL.
# Keep double quotes out of the command for Windows PowerShell's native argument handling.
$bootstrap = 'installer=$(mktemp /tmp/compose-control.XXXXXXXX) && trap ''rm -f -- $installer'' EXIT && curl -fsSL https://raw.githubusercontent.com/stoxello/Compose-Control-Releases/main/install.sh -o $installer && bash $installer ' + $roleName

if ($env:OS -eq 'Windows_NT') {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        throw 'Install Ubuntu on WSL 2 with systemd, then run this command again.'
    }
    & wsl.exe --distribution $WslDistribution --cd '~' --exec bash -c $bootstrap
} elseif ($IsLinux) {
    & bash -c $bootstrap
} else {
    throw 'Run this installer on Linux x86-64 or on Windows with Ubuntu on WSL 2.'
}

if ($LASTEXITCODE -ne 0) {
    throw "Compose Control $roleName installation failed with exit code $LASTEXITCODE. See the output above."
}

if ($env:OS -eq 'Windows_NT') {
    Write-Host ""
    Write-Host "The deployment directory and log command above are inside WSL. To open that Linux shell, run:"
    Write-Host ('  wsl.exe --distribution "{0}" --cd ~' -f $WslDistribution)
    if ($roleName -eq 'agent') {
        Write-Host "Use an agent address reachable from your server. If the server is on another machine, allow access to the agent port through WSL networking."
    }
}
