#requires -Version 7
<#
  Isolated test suite for agent-tools.ps1.

  Nothing here touches the real machine. It builds its own throwaway tree
  (fake HOME, fake PATH, fake wsl.exe, fake Git Bash) under a temp directory
  and deletes it on the way out. Runs anywhere pwsh 7 exists -- macOS, Linux
  and Windows -- because the stubs are shell scripts, not real binaries.

  Usage:   pwsh -File tests/ps1/run-tests.ps1
           pwsh -File tests/ps1/run-tests.ps1 -Target /path/to/agent-tools.ps1
#>
[CmdletBinding()]
param(
    [string] $Target
)

$ErrorActionPreference = 'Continue'

# Default to the wrapper shipped next to this suite (repo root, two levels up).
if (-not $Target) {
    $Target = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'agent-tools.ps1'
}
$SCRIPT = (Resolve-Path $Target).Path

# ---------------------------------------------------------------------------
# Build the fake world.
# ---------------------------------------------------------------------------
$ENVDIR = Join-Path ([System.IO.Path]::GetTempPath()) ("at-ps1-tests-" + [guid]::NewGuid().ToString('N').Substring(0,8))
foreach ($d in 'bin','log','none','pf/Git/bin','pfx86/Git/bin','lad/Programs/Git/bin') {
    New-Item -ItemType Directory -Force -Path (Join-Path $ENVDIR $d) | Out-Null
}

# `wsl.exe`: answers -l / wslpath / -e bash -lc, driven by STUB_* variables.
# STUB_HAS_AT controls whether `command -v agent-tools` finds anything, which
# is how the "installed vs not" branches get exercised without an install.
$wslStub = @'
#!/bin/bash
log="$STUB_LOG/wsl.args"
printf '%s\n' "--- call ---" >> "$log"; printf '[%s]\n' "$@" >> "$log"
case "$1" in
  -l) [ -n "$STUB_DISTROS" ] && printf '%s\n' "$STUB_DISTROS"; exit 0 ;;
  wslpath) printf '/mnt/c/faked%s\n' "$(printf '%s' "$3" | tr '\\' '/')"; exit 0 ;;
  -e)
     # $2=bash $3=-lc $4=<command string>
     case "$4" in
       *"command -v agent-tools") [ "$STUB_HAS_AT" = 1 ] && echo "/home/u/.local/bin/agent-tools"; exit 0 ;;
       *) printf 'WSL_RAN: %s\n' "$4"; exit "${STUB_EXIT:-0}" ;;
     esac ;;
esac
exit 0
'@

# Git Bash: same STUB_HAS_AT contract as the WSL stub, so the wrapper's
# Git-Bash-side probe can be tested the same way as the WSL-side one.
$bashStub = @'
#!/bin/bash
case "$2" in
  *"command -v agent-tools") [ "$STUB_HAS_AT" = 1 ] && echo "/home/u/.local/bin/agent-tools"; exit 0 ;;
esac
printf 'GITBASH_RAN: %s\n' "$2"
exit "${STUB_EXIT:-0}"
'@

function Write-Stub {
    param([string]$Path, [string]$Body)
    Set-Content -Path $Path -Value $Body -NoNewline
    if ($IsMacOS -or $IsLinux) { & chmod 755 $Path }
}
Write-Stub (Join-Path $ENVDIR 'bin/wsl.exe')                  $wslStub
Write-Stub (Join-Path $ENVDIR 'pf/Git/bin/bash.exe')          $bashStub
Write-Stub (Join-Path $ENVDIR 'pfx86/Git/bin/bash.exe')       $bashStub
Write-Stub (Join-Path $ENVDIR 'lad/Programs/Git/bin/bash.exe') $bashStub

$env:STUB_LOG = Join-Path $ENVDIR 'log'
$pass = 0; $fail = 0; $results = @()

function Reset-Env {
    $env:STUB_DISTROS = ''
    # Default to "installed" so only the tests that care about absence set 0.
    $env:STUB_HAS_AT  = '1'
    $env:STUB_EXIT    = ''
    $env:ProgramFiles = "$ENVDIR/none"
    ${env:ProgramFiles(x86)} = "$ENVDIR/none"
    $env:LOCALAPPDATA = "$ENVDIR/none"
    $env:PATH = "/usr/bin:/bin"        # no wsl.exe unless a test adds it
    Remove-Item "$ENVDIR/log/wsl.args" -ErrorAction SilentlyContinue
}

function Invoke-Target {
    param([string[]]$TargetArgs = @())
    # *>&1 not 2>&1: the wrapper uses Write-Host, which goes to the INFORMATION
    # stream (6), not stdout or stderr. 2>&1 alone silently captures nothing.
    $out = & $SCRIPT @TargetArgs *>&1 | Out-String
    return [pscustomobject]@{ Output = $out; Code = $LASTEXITCODE }
}

function Check {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        $script:pass++
        $script:results += "  PASS  $Name"
    } else {
        $script:fail++
        $script:results += "  FAIL  $Name`n        $Detail"
    }
}

Write-Host "`n=== agent-tools.ps1 isolated test suite ===" -ForegroundColor Cyan
Write-Host "target: $SCRIPT"
Write-Host "sandbox: $ENVDIR`n"

# ---------------------------------------------------------------------------
# 1. Neither WSL nor Git Bash present
# ---------------------------------------------------------------------------
Reset-Env
$r = Invoke-Target @('doctor')
Check "1a no-WSL/no-GitBash: exits 1" ($r.Code -eq 1) "got exit $($r.Code)"
Check "1b no-WSL/no-GitBash: explains both are missing" `
    ($r.Output -match 'Neither WSL nor Git Bash') $r.Output
Check "1c no-WSL/no-GitBash: suggests wsl --install" `
    ($r.Output -match 'wsl --install') $r.Output

# ---------------------------------------------------------------------------
# 2. wsl.exe exists but NO distro installed -> must fall through to Git Bash
#    (this is the branch that would otherwise run commands into nothing)
# ---------------------------------------------------------------------------
Reset-Env
$env:PATH = "$ENVDIR/bin:/usr/bin:/bin"
$env:STUB_DISTROS = ''                    # `wsl -l -q` prints nothing
$env:ProgramFiles = "$ENVDIR/pf"
$r = Invoke-Target @('version')
Check "2a wsl-present/no-distro: falls through to Git Bash" `
    ($r.Output -match 'GITBASH_RAN') $r.Output
Check "2b wsl-present/no-distro: says why it used Git Bash" `
    ($r.Output -match 'no WSL distro found') $r.Output

# ---------------------------------------------------------------------------
# 3. `wsl -l -q` emits UTF-16 with NUL bytes -- the script strips them.
#    A NUL-padded distro name must still count as "a distro exists".
# ---------------------------------------------------------------------------
Reset-Env
$env:PATH = "$ENVDIR/bin:/usr/bin:/bin"
$env:STUB_DISTROS = "U`0b`0u`0n`0t`0u`0"
$env:STUB_HAS_AT  = '1'
$r = Invoke-Target @('version')
Check "3a NUL-padded distro list: detected as a real distro" `
    ($r.Output -match 'WSL_RAN') $r.Output
Check "3b NUL-padded distro list: does not fall through to Git Bash" `
    ($r.Output -notmatch 'GITBASH_RAN') $r.Output

# ---------------------------------------------------------------------------
# 4. WSL + distro, but agent-tools is NOT installed inside it
# ---------------------------------------------------------------------------
Reset-Env
$env:PATH = "$ENVDIR/bin:/usr/bin:/bin"
$env:STUB_DISTROS = 'Ubuntu'
$env:STUB_HAS_AT  = '0'
$r = Invoke-Target @('doctor')
Check "4a WSL without agent-tools: exits 1" ($r.Code -eq 1) "got exit $($r.Code)"
Check "4b WSL without agent-tools: says it is missing in WSL" `
    ($r.Output -match 'not installed in WSL') $r.Output
Check "4c WSL without agent-tools: gives the install recipe" `
    ($r.Output -match './install.sh') $r.Output
Check "4d WSL without agent-tools: does NOT run the command anyway" `
    ($r.Output -notmatch 'WSL_RAN') $r.Output

# ---------------------------------------------------------------------------
# 5. Happy path: WSL + distro + agent-tools present
# ---------------------------------------------------------------------------
Reset-Env
$env:PATH = "$ENVDIR/bin:/usr/bin:/bin"
$env:STUB_DISTROS = 'Ubuntu'
$env:STUB_HAS_AT  = '1'
$r = Invoke-Target @('install','pocock')
Check "5a WSL happy path: command reaches the Linux side" `
    ($r.Output -match 'WSL_RAN') $r.Output
Check "5b WSL happy path: prepends ~/.local/bin to PATH" `
    ($r.Output -match 'export PATH="\$HOME/\.local/bin:\$PATH"') $r.Output
Check "5c WSL happy path: cd's into the translated Linux cwd" `
    ($r.Output -match "cd '/mnt/c/faked") $r.Output
Check "5d WSL happy path: passes the subcommand and its argument" `
    ($r.Output -match "agent-tools 'install' 'pocock'") $r.Output

# ---------------------------------------------------------------------------
# 6. Exit-code propagation from the Linux side
# ---------------------------------------------------------------------------
Reset-Env
$env:PATH = "$ENVDIR/bin:/usr/bin:/bin"
$env:STUB_DISTROS = 'Ubuntu'
$env:STUB_HAS_AT  = '1'
$env:STUB_EXIT    = '3'
$r = Invoke-Target @('doctor')
Check "6a WSL: propagates a non-zero exit code" ($r.Code -eq 3) "got exit $($r.Code)"

Reset-Env
$env:PATH = "/usr/bin:/bin"
$env:ProgramFiles = "$ENVDIR/pf"
$env:STUB_EXIT = '4'
$r = Invoke-Target @('doctor')
Check "6b Git Bash: propagates a non-zero exit code" ($r.Code -eq 4) "got exit $($r.Code)"

# ---------------------------------------------------------------------------
# 7. Git Bash discovered at each of the three candidate locations
# ---------------------------------------------------------------------------
foreach ($case in @(
    @{ Name='ProgramFiles';       Var='ProgramFiles'; Path="$ENVDIR/pf" },
    @{ Name='ProgramFiles(x86)';  Var='ProgramFiles(x86)'; Path="$ENVDIR/pfx86" },
    @{ Name='LOCALAPPDATA';       Var='LOCALAPPDATA'; Path="$ENVDIR/lad" }
)) {
    Reset-Env
    Set-Item "env:$($case.Var)" $case.Path
    $r = Invoke-Target @('version')
    Check "7 Git Bash found via $($case.Name)" ($r.Output -match 'GITBASH_RAN') $r.Output
}

# ---------------------------------------------------------------------------
# 8. No arguments must become `help`, not an empty command
# ---------------------------------------------------------------------------
Reset-Env
$env:ProgramFiles = "$ENVDIR/pf"
$r = Invoke-Target @()
Check "8 no args defaults to 'help'" ($r.Output -match "agent-tools 'help'") $r.Output

# ---------------------------------------------------------------------------
# 9. Argument marshalling: spaces, quotes, shell metacharacters, injection
# ---------------------------------------------------------------------------
Reset-Env
$env:ProgramFiles = "$ENVDIR/pf"
$r = Invoke-Target @('install','a b','it''s','$(whoami)','`bt`',"'; id #",'x;rm -rf /')
Check "9a arg with a space survives quoted" ($r.Output -match "'a b'") $r.Output
Check "9b embedded single quote is escaped" ($r.Output -match "'it'\\''s'") $r.Output
Check "9c command substitution is NOT expanded" `
    (($r.Output -match '\$\(whoami\)') -and ($r.Output -notmatch [regex]::Escape((whoami)))) $r.Output
Check "9d backticks are not executed" ($r.Output -match '`bt`') $r.Output
Check "9e quote-break injection is neutralised" ($r.Output -match "''\\''; id #'") $r.Output
Check "9f semicolon does not split the command" ($r.Output -match "'x;rm -rf /'") $r.Output

# ---------------------------------------------------------------------------
# 10. The UNC guard. Cannot set a \\wsl$ cwd on macOS, so the REGEX ITSELF is
#     extracted from the shipped file and exercised -- the branch condition is
#     verified, the branch body is not executed.
# ---------------------------------------------------------------------------
$src = Get-Content $SCRIPT -Raw
$m = [regex]::Match($src, "if \(\`$cwd -match '([^']+)'\) \{")
if (-not $m.Success) {
    Check "10 UNC guard: pattern located in source" $false "could not find the -match line"
} else {
    $pat = $m.Groups[1].Value
    Check "10a UNC guard: matches \\wsl`$\ path"        ('\\wsl$\Ubuntu\home\me' -match $pat) $pat
    Check "10b UNC guard: matches \\wsl.localhost\ path" ('\\wsl.localhost\Ubuntu\home' -match $pat) $pat
    Check "10c UNC guard: ignores a normal C: path"      (-not ('C:\Users\me\code' -match $pat)) $pat
    Check "10d UNC guard: ignores another UNC share"     (-not ('\\server\share' -match $pat)) $pat
}

# ---------------------------------------------------------------------------
# 11. Parse + static hygiene
# ---------------------------------------------------------------------------
$errs = $null; $toks = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($SCRIPT, [ref]$toks, [ref]$errs)
Check "11a parses with zero errors" ($errs.Count -eq 0) ($errs | ForEach-Object { $_.Message })
Check "11b no stale agentmemory guidance in the wrapper" `
    ($src -notmatch 'agentmemory (does not|needs WSL2|cannot install)') 'found stale text'
Check "11c documents the pocock tool" ($src -match 'pocock') 'pocock not mentioned'

# ---------------------------------------------------------------------------
# 12. Git Bash branch must probe before running, exactly like the WSL branch.
#     Without the probe an uninstalled tool surfaced as bash's raw
#     "command not found" instead of the wrapper's own instructions.
# ---------------------------------------------------------------------------
Reset-Env
$env:ProgramFiles = "$ENVDIR/pf"
$env:STUB_HAS_AT  = '0'
$r = Invoke-Target @('doctor')
Check "12a Git Bash without agent-tools: exits 1" ($r.Code -eq 1) "got exit $($r.Code)"
Check "12b Git Bash without agent-tools: says it is missing in Git Bash" `
    ($r.Output -match 'not installed in Git Bash') $r.Output
Check "12c Git Bash without agent-tools: does NOT run the command anyway" `
    ($r.Output -notmatch 'GITBASH_RAN: export PATH.*agent-tools ') $r.Output

# ---------------------------------------------------------------------------
Write-Host ($results -join "`n")
Write-Host "`n----------------------------------------"
Write-Host ("  {0} passed, {1} failed" -f $pass, $fail) -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
Write-Host "----------------------------------------`n"

Remove-Item -Recurse -Force $ENVDIR -ErrorAction SilentlyContinue
exit $(if ($fail) { 1 } else { 0 })
