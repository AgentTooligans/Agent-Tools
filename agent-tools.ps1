<#
.SYNOPSIS
  PowerShell front-end for agent-tools.

.DESCRIPTION
  agent-tools is a bash script. This wrapper lets you call it from PowerShell
  with the same commands, running it through Git Bash (the default) or WSL.

  WHY GIT BASH FIRST.
  Native-Windows Claude Code fires hooks and launches MCP servers in the
  NATIVE Windows environment, so the tools agent-tools installs must be on the
  native Windows PATH. Git Bash shares Windows' HOME and PATH, so a tool it
  installs is visible to native Claude Code. A tool installed inside a WSL
  distro is NOT - it lives in a separate Linux filesystem the native agent
  cannot see. So Git Bash is the correct default; WSL is only right when you
  also run Claude Code INSIDE WSL.

  Force WSL with  -Wsl  or  $env:AGENT_TOOLS_USE_WSL=1  (use this only when your
  agent runs inside the distro).

  Since agent-tools 3.3.0 the agentmemory backend (the one with no
  native-Windows installer) is gone; claude-mem, graphify, code-review-graph,
  token-savior, superpowers, context-mode and the skill packs (caveman,
  pocock) all work under Git Bash. The one remaining gap is rtk, which needs
  either Rust (`cargo install --git`) or the release zip on PATH.

.EXAMPLE
  agent-tools doctor
  agent-tools init
  agent-tools refresh
  agent-tools install rtk
  agent-tools -Wsl doctor        # force the WSL path
  agent-tools install-machine -y
#>
[CmdletBinding()]
param(
    [switch] $Wsl,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Arguments
)

$ErrorActionPreference = 'Stop'

function Show-Missing {
    param([string]$Where, [string]$How)
    Write-Host ""
    Write-Host "  agent-tools is not installed in $Where." -ForegroundColor Red
    Write-Host "  $How"
    Write-Host ""
}

# Quote a string for safe use inside a single-quoted bash string.
function ConvertTo-BashSingleQuoted {
    param([string]$Text)
    return "'" + ($Text -replace "'", "'\''") + "'"
}

# ---------------------------------------------------------------------------
# Locate a Git Bash. Explicitly EXCLUDE C:\Windows\System32\bash.exe: that is
# the WSL launcher, not Git Bash, and `Get-Command bash.exe` finds it first on
# most machines. Running it here would silently reroute into WSL.
# ---------------------------------------------------------------------------
function Find-GitBash {
    $candidates = @(
        "$env:ProgramFiles\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe",
        "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe"
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    # Last resort: anything named bash.exe on PATH that is NOT the WSL shim.
    $cmd = Get-Command bash.exe -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and $cmd.Source -notmatch '\\System32\\') {
        return $cmd.Source
    }
    return $null
}

# Return the installed WSL distro list, or $null if wsl.exe is missing / has
# no distro. `wsl -l -q` prints UTF-16; normalise the embedded NULs away.
function Get-WslDistros {
    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if (-not $wsl) { return $null }
    $distros = (& wsl.exe -l -q 2>$null) -join "`n" -replace "`0", ''
    if ($distros.Trim()) { return $distros } else { return $null }
}

# ---------------------------------------------------------------------------
# Run agent-tools under Git Bash. Exits the process with the tool's code.
# ---------------------------------------------------------------------------
function Invoke-GitBash {
    param([string]$Bash, [string]$ArgString, [string]$Cwd)

    # ~/.local/bin is NOT on PATH on a fresh install until the next login, so
    # prepend it explicitly rather than depending on the login shell. This runs
    # AFTER the login profile because it is inside the -c string.
    $bashPrefix = 'export PATH="$HOME/.local/bin:$PATH"; '

    # Probe before pretending to run, so an uninstalled tool surfaces our
    # instructions instead of bash's raw "command not found".
    $probe = (& $Bash -lc ($bashPrefix + "command -v agent-tools") 2>$null | Select-Object -First 1)
    if (-not $probe) {
        Show-Missing "Git Bash" @"
Install it from Git Bash:
      cd /path/to/Agent-Tools && ./install.sh
"@
        exit 1
    }

    # Pin the working directory the SAME way the WSL branch does. A login shell
    # can `cd` on startup, which would point repo-scoped commands (init,
    # refresh, install --project) at the wrong tree. MSYS accepts the drive
    # form with forward slashes (C:/Users/...), so convert backslashes.
    $cdPrefix = ''
    if ($Cwd -match '^[A-Za-z]:') {
        $bashCwd = $Cwd -replace '\\', '/'
        $cdPrefix = "cd $(ConvertTo-BashSingleQuoted $bashCwd) && "
    }

    & $Bash -lc ($bashPrefix + $cdPrefix + "agent-tools " + $ArgString)
    exit $LASTEXITCODE
}

# ---------------------------------------------------------------------------
# Run agent-tools under WSL. Returns $false if there is no usable distro (so
# the caller can fall back); otherwise runs and exits the process.
# ---------------------------------------------------------------------------
function Invoke-Wsl {
    param([string]$ArgString, [string]$Cwd)

    $distros = Get-WslDistros
    if (-not $distros) { return }

    # Translate the Windows CWD (C:\...) to the Linux view (/mnt/c/...). A UNC
    # path under \\wsl$ or \\wsl.localhost is ALREADY inside the distro, so
    # wslpath would mangle it - fall back to the home directory and warn.
    $linuxCwd = $null
    if ($Cwd -match '^\\\\wsl') {
        Write-Host "  note: running from a \\wsl$ UNC path; using your WSL home instead." -ForegroundColor Yellow
    } else {
        try   { $linuxCwd = (& wsl.exe wslpath -a "$Cwd" 2>$null | Select-Object -First 1).Trim() }
        catch { $linuxCwd = $null }
    }

    $prefix  = if ($linuxCwd) { "cd $(ConvertTo-BashSingleQuoted $linuxCwd) && " } else { "" }
    $pathFix = 'export PATH="$HOME/.local/bin:$PATH"; '

    $probe = (& wsl.exe -e bash -lc "$pathFix command -v agent-tools" 2>$null | Select-Object -First 1)
    if (-not $probe) {
        Show-Missing "WSL" @"
Install it inside WSL:
      wsl
      cd /path/to/Agent-Tools && ./install.sh
"@
        exit 1
    }

    & wsl.exe -e bash -lc "$pathFix $prefix agent-tools $ArgString"
    exit $LASTEXITCODE
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
$cmdArgs   = if ($Arguments) { $Arguments } else { @('help') }
# Each argument single-quoted so spaces and shell metacharacters survive.
$argString = ($cmdArgs | ForEach-Object { ConvertTo-BashSingleQuoted $_ }) -join ' '
$cwd       = (Get-Location).Path

$preferWsl = $Wsl.IsPresent -or ($env:AGENT_TOOLS_USE_WSL -and $env:AGENT_TOOLS_USE_WSL -ne '0')
$gitBash   = Find-GitBash

if ($preferWsl) {
    # WSL explicitly requested. Use it if a distro exists; else fall back to
    # Git Bash rather than failing.
    if (Get-WslDistros) {
        Invoke-Wsl -ArgString $argString -Cwd $cwd   # exits
    }
    if ($gitBash) {
        Write-Host "  note: -Wsl was requested but no WSL distro is installed - using Git Bash." -ForegroundColor Yellow
        Invoke-GitBash -Bash $gitBash -ArgString $argString -Cwd $cwd
    }
} else {
    # DEFAULT: Git Bash - its installs land on the native Windows PATH, so
    # native Claude Code can see the hooks and MCP servers agent-tools wires.
    if ($gitBash) {
        Invoke-GitBash -Bash $gitBash -ArgString $argString -Cwd $cwd   # exits
    }
    # No Git Bash. WSL works, but warn: it targets the WSL environment, so use
    # it only if your agent also runs inside the distro.
    if (Get-WslDistros) {
        Write-Host "  note: no Git Bash found - using WSL." -ForegroundColor Yellow
        Write-Host "        This installs INSIDE the distro. Native-Windows Claude Code will" -ForegroundColor Yellow
        Write-Host "        not see those tools; run Claude Code inside WSL, or install Git" -ForegroundColor Yellow
        Write-Host "        for Windows for native support." -ForegroundColor Yellow
        Invoke-Wsl -ArgString $argString -Cwd $cwd
    }
}

# ---------------------------------------------------------------------------
# Neither shell is available. Offer to bootstrap Git for Windows via winget.
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "  Neither Git Bash nor WSL was found." -ForegroundColor Red
Write-Host "  agent-tools is a bash script and needs one of them."
Write-Host ""

# Only offer the interactive install when someone is actually there to answer.
# A redirected/non-interactive run (CI, the test suite, a piped invocation)
# would otherwise block forever on Read-Host.
$interactive = -not [System.Console]::IsInputRedirected
$winget = Get-Command winget -ErrorAction SilentlyContinue
if ($winget -and $interactive) {
    $ans = Read-Host "  Install Git for Windows now with winget? [y/N]"
    if ($ans -match '^[Yy]') {
        & winget.exe install --id Git.Git -e --source winget `
            --accept-package-agreements --accept-source-agreements
        # winget does not refresh THIS session's PATH, but Git installs to a
        # known location, so re-probe directly instead of asking for a restart.
        $gitBash = Find-GitBash
        if ($gitBash) {
            Write-Host "  Git for Windows installed. Continuing..." -ForegroundColor Green
            Invoke-GitBash -Bash $gitBash -ArgString $argString -Cwd $cwd
        }
        Write-Host "  Installed, but bash.exe was not found where expected." -ForegroundColor Yellow
        Write-Host "  Open a new terminal and re-run the command." -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "  Recommended:  winget install Git.Git      (or install Git for Windows)"
Write-Host "  Alternative:  wsl --install               (only if your agent runs in WSL)"
Write-Host ""
exit 1
