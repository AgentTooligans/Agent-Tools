<#
.SYNOPSIS
  PowerShell front-end for agent-tools.

.DESCRIPTION
  agent-tools is a bash script. This wrapper lets you call it from PowerShell
  with the same commands, translating your current directory into the path the
  Linux side expects.

  It prefers WSL because that is the smoother environment, but since
  agent-tools 3.3.0 it is no longer required. The agentmemory backend that had
  no native-Windows installer was removed; claude-mem, graphify,
  code-review-graph, token-savior, superpowers, context-mode and the skill
  packs (caveman, pocock) all work under Git Bash too. The one remaining gap
  is rtk, which needs either Rust (`cargo install --git`) or the release zip
  on PATH.

.EXAMPLE
  agent-tools doctor
  agent-tools init
  agent-tools refresh
  agent-tools tools
  agent-tools install rtk
  agent-tools install pocock
  agent-tools update all
  agent-tools update pocock
  agent-tools install-machine -y
#>
[CmdletBinding()]
param(
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

$cmdArgs = if ($Arguments) { $Arguments } else { @('help') }
# Each argument single-quoted so spaces and shell metacharacters survive.
$argString = ($cmdArgs | ForEach-Object { ConvertTo-BashSingleQuoted $_ }) -join ' '
$cwd = (Get-Location).Path

# ---------------------------------------------------------------------------
# Preferred path: WSL
# ---------------------------------------------------------------------------
$wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
if ($wsl) {
    # Is a distro actually installed? `wsl -l -q` prints UTF-16; normalise it.
    $distros = (& wsl.exe -l -q 2>$null) -join "`n" -replace "`0", ''
    if ($distros.Trim()) {

        # Translate the Windows CWD (C:\...) to the Linux view (/mnt/c/...).
        # A UNC path under \\wsl$\ or \\wsl.localhost\ is ALREADY inside the
        # distro, so wslpath would mangle it — fall back to the home directory
        # and warn, rather than running somewhere unintended.
        $linuxCwd = $null
        if ($cwd -match '^\\\\wsl') {
            Write-Host "  note: running from a \\wsl$ UNC path; using your WSL home instead." -ForegroundColor Yellow
        } else {
            try   { $linuxCwd = (& wsl.exe wslpath -a "$cwd" 2>$null | Select-Object -First 1).Trim() }
            catch { $linuxCwd = $null }
        }

        $prefix = if ($linuxCwd) { "cd $(ConvertTo-BashSingleQuoted $linuxCwd) && " } else { "" }

        # ~/.local/bin is NOT on PATH on a fresh Ubuntu until the next login
        # (its .profile only adds the directory if it already existed), so
        # prepend it explicitly rather than depending on the login shell.
        $pathFix = 'export PATH="$HOME/.local/bin:$PATH"; '

        # Confirm the tool exists on the Linux side before pretending to run it.
        $probe = (& wsl.exe -e bash -lc "$pathFix command -v agent-tools" 2>$null | Select-Object -First 1)
        if (-not $probe) {
            Show-Missing "WSL" @"
Install it inside WSL:
      wsl
      cd /path/to/Agent-Tools && ./install.sh
"@
            exit 1
        }

        & wsl.exe -e bash -lc "$pathFix $prefix agent-tools $argString"
        exit $LASTEXITCODE
    }
}

# ---------------------------------------------------------------------------
# Fallback: Git Bash. Everything but rtk installs here since 3.3.0.
# ---------------------------------------------------------------------------
$gitBash = @(
    "$env:ProgramFiles\Git\bin\bash.exe",
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

if ($gitBash) {
    Write-Host "  note: no WSL distro found — using Git Bash." -ForegroundColor Yellow
    Write-Host "        graphify, claude-mem, code-review-graph, token-savior," -ForegroundColor Yellow
    Write-Host "        superpowers, context-mode, caveman and pocock all work here." -ForegroundColor Yellow
    Write-Host "        Only rtk needs more: cargo, or its release zip on PATH." -ForegroundColor Yellow
    # Git Bash understands C:\ paths but prefers /c/... ; it also accepts the
    # drive form, so just stay where we are.
    # Build the bash command by concatenation. Backtick-escaped quotes inside a
    # double-quoted PowerShell string are a parser trap — this form has no
    # escaping at all.
    $bashPrefix = 'export PATH="$HOME/.local/bin:$PATH"; '
    # Probe before running, exactly as the WSL branch does. Without this an
    # uninstalled tool surfaced as bash's raw "command not found" instead of
    # the instructions Show-Missing already exists to print.
    $probe = (& $gitBash -lc ($bashPrefix + "command -v agent-tools") 2>$null | Select-Object -First 1)
    if (-not $probe) {
        Show-Missing "Git Bash" @"
Install it from Git Bash:
      cd /path/to/Agent-Tools && ./install.sh
"@
        exit 1
    }
    & $gitBash -lc ($bashPrefix + "agent-tools " + $argString)
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "  Neither WSL nor Git Bash was found." -ForegroundColor Red
Write-Host "  agent-tools is a bash script and needs one of them."
Write-Host ""
Write-Host "  Recommended:  wsl --install"
Write-Host "  Alternative:  install Git for Windows (provides Git Bash)"
Write-Host ""
exit 1
