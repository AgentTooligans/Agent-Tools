#requires -Version 7
<#
  Isolated test suite for agent-tools.ps1.

  Nothing here touches the real machine. It builds its own throwaway tree
  (fake HOME, fake PATH, fake wsl.exe, fake Git Bash) under a temp directory
  and deletes it on the way out. Runs anywhere pwsh 7 exists -- macOS, Linux
  and Windows -- because the stubs are shell scripts, not real binaries.

  CONTRACT UNDER TEST (agent-tools 3.8.1+): Git Bash is the DEFAULT, because a
  tool it installs lands on the native Windows PATH where native Claude Code
  can see it. WSL is opt-in (-Wsl or $env:AGENT_TOOLS_USE_WSL) because its
  installs live inside the distro, invisible to a native-Windows agent.

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
foreach ($d in 'bin','log','none','pf/Git/bin','pfx86/Git/bin','lad/Programs/Git/bin','scoop/scoop/apps/git/current/bin') {
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
Write-Stub (Join-Path $ENVDIR 'bin/wsl.exe')                   $wslStub
Write-Stub (Join-Path $ENVDIR 'pf/Git/bin/bash.exe')           $bashStub
Write-Stub (Join-Path $ENVDIR 'pfx86/Git/bin/bash.exe')        $bashStub
Write-Stub (Join-Path $ENVDIR 'lad/Programs/Git/bin/bash.exe') $bashStub
Write-Stub (Join-Path $ENVDIR 'scoop/scoop/apps/git/current/bin/bash.exe') $bashStub

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
    $env:USERPROFILE  = "$ENVDIR/none"
    $env:AGENT_TOOLS_USE_WSL = ''
    $env:PATH = "/usr/bin:/bin"        # no wsl.exe unless a test adds it
    Remove-Item "$ENVDIR/log/wsl.args" -ErrorAction SilentlyContinue
}

function Invoke-Target {
    param([string[]]$TargetArgs = @(), [switch]$ForceWsl)
    # *>&1 not 2>&1: the wrapper uses Write-Host, which goes to the INFORMATION
    # stream (6), not stdout or stderr. 2>&1 alone silently captures nothing.
    if ($ForceWsl) {
        $out = & $SCRIPT -Wsl @TargetArgs *>&1 | Out-String
    } else {
        $out = & $SCRIPT @TargetArgs *>&1 | Out-String
    }
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
# 1. Neither Git Bash nor WSL present
# ---------------------------------------------------------------------------
Reset-Env
$r = Invoke-Target @('doctor')
Check "1a no-shell: exits 1" ($r.Code -eq 1) "got exit $($r.Code)"
Check "1b no-shell: explains both are missing" `
    ($r.Output -match 'Neither Git Bash nor WSL') $r.Output
Check "1c no-shell: recommends installing Git" `
    ($r.Output -match 'Git\.Git|Git for Windows') $r.Output
Check "1d no-shell: still mentions WSL as the opt-in alternative" `
    ($r.Output -match 'wsl --install') $r.Output

# ---------------------------------------------------------------------------
# 2. DEFAULT: Git Bash wins even when a WSL distro is available. This is the
#    whole point of the flip -- native installs must land on the Windows PATH.
# ---------------------------------------------------------------------------
Reset-Env
$env:PATH = "$ENVDIR/bin:/usr/bin:/bin"     # wsl.exe reachable
$env:STUB_DISTROS = 'Ubuntu'                # a real distro exists
$env:ProgramFiles = "$ENVDIR/pf"            # Git Bash also present
$r = Invoke-Target @('version')
Check "2a both present: uses Git Bash by default" `
    ($r.Output -match 'GITBASH_RAN') $r.Output
Check "2b both present: does NOT touch WSL" `
    ($r.Output -notmatch 'WSL_RAN') $r.Output

# ---------------------------------------------------------------------------
# 3. -Wsl forces the WSL path even when Git Bash is present.
# ---------------------------------------------------------------------------
Reset-Env
$env:PATH = "$ENVDIR/bin:/usr/bin:/bin"
$env:STUB_DISTROS = 'Ubuntu'
$env:ProgramFiles = "$ENVDIR/pf"
$r = Invoke-Target @('version') -ForceWsl
Check "3a -Wsl: routes to WSL despite Git Bash present" `
    ($r.Output -match 'WSL_RAN') $r.Output
Check "3b -Wsl: does not use Git Bash" `
    ($r.Output -notmatch 'GITBASH_RAN') $r.Output

# ---------------------------------------------------------------------------
# 4. $env:AGENT_TOOLS_USE_WSL=1 forces WSL, same as the switch.
# ---------------------------------------------------------------------------
Reset-Env
$env:PATH = "$ENVDIR/bin:/usr/bin:/bin"
$env:STUB_DISTROS = 'Ubuntu'
$env:ProgramFiles = "$ENVDIR/pf"
$env:AGENT_TOOLS_USE_WSL = '1'
$r = Invoke-Target @('version')
Check "4a env AGENT_TOOLS_USE_WSL=1: routes to WSL" `
    ($r.Output -match 'WSL_RAN') $r.Output
Check "4b env AGENT_TOOLS_USE_WSL=1: not Git Bash" `
    ($r.Output -notmatch 'GITBASH_RAN') $r.Output

# ---------------------------------------------------------------------------
# 5. -Wsl requested but no distro installed -> fall back to Git Bash, with a note.
# ---------------------------------------------------------------------------
Reset-Env
$env:PATH = "$ENVDIR/bin:/usr/bin:/bin"
$env:STUB_DISTROS = ''                       # wsl.exe present, no distro
$env:ProgramFiles = "$ENVDIR/pf"
$r = Invoke-Target @('version') -ForceWsl
Check "5a -Wsl/no-distro: falls back to Git Bash" `
    ($r.Output -match 'GITBASH_RAN') $r.Output
Check "5b -Wsl/no-distro: explains the fallback" `
    ($r.Output -match 'no WSL distro') $r.Output

# ---------------------------------------------------------------------------
# 6. No Git Bash, but a WSL distro exists -> use WSL, and WARN that it targets
#    the distro (native Claude Code will not see those tools).
# ---------------------------------------------------------------------------
Reset-Env
$env:PATH = "$ENVDIR/bin:/usr/bin:/bin"
$env:STUB_DISTROS = 'Ubuntu'
# ProgramFiles stays "none" -> no Git Bash
$r = Invoke-Target @('version')
Check "6a no-GitBash/WSL-present: uses WSL" `
    ($r.Output -match 'WSL_RAN') $r.Output
Check "6b no-GitBash/WSL-present: warns install lands inside the distro" `
    ($r.Output -match 'inside the distro|no Git Bash') $r.Output

# ---------------------------------------------------------------------------
# 7. `wsl -l -q` emits UTF-16 with NUL bytes -- the script strips them, so a
#    NUL-padded distro name still counts (relevant to the no-GitBash fallback).
# ---------------------------------------------------------------------------
Reset-Env
$env:PATH = "$ENVDIR/bin:/usr/bin:/bin"
$env:STUB_DISTROS = "U`0b`0u`0n`0t`0u`0"
$r = Invoke-Target @('version')
Check "7a NUL-padded distro list: detected as a real distro" `
    ($r.Output -match 'WSL_RAN') $r.Output

# ---------------------------------------------------------------------------
# 8. WSL selected but agent-tools is NOT installed inside it (forced via -Wsl).
# ---------------------------------------------------------------------------
Reset-Env
$env:PATH = "$ENVDIR/bin:/usr/bin:/bin"
$env:STUB_DISTROS = 'Ubuntu'
$env:STUB_HAS_AT  = '0'
$r = Invoke-Target @('doctor') -ForceWsl
Check "8a WSL without agent-tools: exits 1" ($r.Code -eq 1) "got exit $($r.Code)"
Check "8b WSL without agent-tools: says it is missing in WSL" `
    ($r.Output -match 'not installed in WSL') $r.Output
Check "8c WSL without agent-tools: gives the install recipe" `
    ($r.Output -match './install.sh') $r.Output
Check "8d WSL without agent-tools: does NOT run the command anyway" `
    ($r.Output -notmatch 'WSL_RAN') $r.Output

# ---------------------------------------------------------------------------
# 9. WSL happy path (forced): marshalling + cwd translation + PATH fix.
# ---------------------------------------------------------------------------
Reset-Env
$env:PATH = "$ENVDIR/bin:/usr/bin:/bin"
$env:STUB_DISTROS = 'Ubuntu'
$r = Invoke-Target @('install','pocock') -ForceWsl
Check "9a WSL happy path: command reaches the Linux side" `
    ($r.Output -match 'WSL_RAN') $r.Output
Check "9b WSL happy path: prepends ~/.local/bin to PATH" `
    ($r.Output -match 'export PATH="\$HOME/\.local/bin:\$PATH"') $r.Output
Check "9c WSL happy path: cd's into the translated Linux cwd" `
    ($r.Output -match "cd '/mnt/c/faked") $r.Output
Check "9d WSL happy path: passes the subcommand and its argument" `
    ($r.Output -match "agent-tools 'install' 'pocock'") $r.Output

# ---------------------------------------------------------------------------
# 10. Exit-code propagation from both back-ends.
# ---------------------------------------------------------------------------
Reset-Env
$env:PATH = "$ENVDIR/bin:/usr/bin:/bin"
$env:STUB_DISTROS = 'Ubuntu'
$env:STUB_EXIT    = '3'
$r = Invoke-Target @('doctor') -ForceWsl
Check "10a WSL: propagates a non-zero exit code" ($r.Code -eq 3) "got exit $($r.Code)"

Reset-Env
$env:ProgramFiles = "$ENVDIR/pf"
$env:STUB_EXIT = '4'
$r = Invoke-Target @('doctor')
Check "10b Git Bash: propagates a non-zero exit code" ($r.Code -eq 4) "got exit $($r.Code)"

# ---------------------------------------------------------------------------
# 11. Git Bash discovered at each candidate location, including scoop.
# ---------------------------------------------------------------------------
foreach ($case in @(
    @{ Name='ProgramFiles';      Var='ProgramFiles';      Path="$ENVDIR/pf" },
    @{ Name='ProgramFiles(x86)'; Var='ProgramFiles(x86)'; Path="$ENVDIR/pfx86" },
    @{ Name='LOCALAPPDATA';      Var='LOCALAPPDATA';      Path="$ENVDIR/lad" },
    @{ Name='scoop (USERPROFILE)'; Var='USERPROFILE';     Path="$ENVDIR/scoop" }
)) {
    Reset-Env
    Set-Item "env:$($case.Var)" $case.Path
    $r = Invoke-Target @('version')
    Check "11 Git Bash found via $($case.Name)" ($r.Output -match 'GITBASH_RAN') $r.Output
}

# ---------------------------------------------------------------------------
# 12. No arguments must become `help`, not an empty command.
# ---------------------------------------------------------------------------
Reset-Env
$env:ProgramFiles = "$ENVDIR/pf"
$r = Invoke-Target @()
Check "12 no args defaults to 'help'" ($r.Output -match "agent-tools 'help'") $r.Output

# ---------------------------------------------------------------------------
# 13. Argument marshalling: spaces, quotes, shell metacharacters, injection
#     (exercised through the Git Bash path).
# ---------------------------------------------------------------------------
Reset-Env
$env:ProgramFiles = "$ENVDIR/pf"
$r = Invoke-Target @('install','a b','it''s','$(whoami)','`bt`',"'; id #",'x;rm -rf /')
Check "13a arg with a space survives quoted" ($r.Output -match "'a b'") $r.Output
Check "13b embedded single quote is escaped" ($r.Output -match "'it'\\''s'") $r.Output
Check "13c command substitution is NOT expanded" `
    (($r.Output -match '\$\(whoami\)') -and ($r.Output -notmatch [regex]::Escape((whoami)))) $r.Output
Check "13d backticks are not executed" ($r.Output -match '`bt`') $r.Output
Check "13e quote-break injection is neutralised" ($r.Output -match "''\\''; id #'") $r.Output
Check "13f semicolon does not split the command" ($r.Output -match "'x;rm -rf /'") $r.Output

# ---------------------------------------------------------------------------
# 14. Git Bash probe fires before running, exactly like the WSL branch.
# ---------------------------------------------------------------------------
Reset-Env
$env:ProgramFiles = "$ENVDIR/pf"
$env:STUB_HAS_AT  = '0'
$r = Invoke-Target @('doctor')
Check "14a Git Bash without agent-tools: exits 1" ($r.Code -eq 1) "got exit $($r.Code)"
Check "14b Git Bash without agent-tools: says it is missing in Git Bash" `
    ($r.Output -match 'not installed in Git Bash') $r.Output
Check "14c Git Bash without agent-tools: does NOT run the command anyway" `
    ($r.Output -notmatch 'GITBASH_RAN: export PATH.*agent-tools ') $r.Output

# ---------------------------------------------------------------------------
# 15. Static guards. Some branches (UNC translation, System32 exclusion, the
#     Git-Bash cwd pin, the winget bootstrap) need a real C:\ path or a real
#     Windows binary and cannot be executed on macOS/Linux. Verify the branch
#     CONDITIONS and command strings straight from the shipped source instead.
# ---------------------------------------------------------------------------
$src = Get-Content $SCRIPT -Raw

# 15a-d: UNC guard used before wslpath translation.
$mUnc = [regex]::Match($src, "-match '(\^\\\\[^']*wsl[^']*)'")
if (-not $mUnc.Success) {
    Check "15a UNC guard: pattern located in source" $false "could not find the \\wsl -match line"
} else {
    $pat = $mUnc.Groups[1].Value
    Check "15a UNC guard: matches \\wsl`$\ path"         ('\\wsl$\Ubuntu\home\me' -match $pat) $pat
    Check "15b UNC guard: matches \\wsl.localhost\ path" ('\\wsl.localhost\Ubuntu\home' -match $pat) $pat
    Check "15c UNC guard: ignores a normal C: path"      (-not ('C:\Users\me\code' -match $pat)) $pat
    Check "15d UNC guard: ignores another UNC share"     (-not ('\\server\share' -match $pat)) $pat
}

# 15e: the WSL launcher at System32 must be excluded from Git Bash discovery.
$mSys = [regex]::Match($src, "-notmatch '(\\\\System32\\\\)'")
if (-not $mSys.Success) {
    Check "15e System32 exclusion: guard present in source" $false 'no System32 -notmatch guard found'
} else {
    $sysPat = $mSys.Groups[1].Value
    Check "15e System32 exclusion: matches the WSL launcher path" `
        ('C:\Windows\System32\bash.exe' -match $sysPat) $sysPat
    Check "15f System32 exclusion: leaves a real Git Bash path alone" `
        (-not ('C:\Program Files\Git\bin\bash.exe' -match $sysPat)) $sysPat
}

# 15g: the Git-Bash cwd pin only fires for a drive-letter path.
$mDrive = [regex]::Match($src, "-match '(\^\[A-Za-z\]:)'")
if (-not $mDrive.Success) {
    Check "15g cwd pin: drive-letter guard present" $false 'no ^[A-Za-z]: guard found'
} else {
    $drivePat = $mDrive.Groups[1].Value
    Check "15g cwd pin: matches a Windows drive path" ('C:\Users\me\code' -match $drivePat) $drivePat
    Check "15h cwd pin: ignores a POSIX path"         (-not ('/mnt/c/code' -match $drivePat)) $drivePat
}

# 15i: backslashes are converted to forward slashes for the bash `cd`.
Check "15i cwd pin: converts backslashes for MSYS" `
    ($src -match "-replace '\\\\', '/'") 'no backslash->slash conversion found'

# 15j: winget bootstrap installs the right package id, guarded against a
#      non-interactive hang on Read-Host.
Check "15j bootstrap: winget targets Git.Git" ($src -match '--id Git\.Git') 'Git.Git id not found'
Check "15k bootstrap: Read-Host guarded by an interactivity check" `
    ($src -match 'IsInputRedirected') 'no interactivity guard around Read-Host'

# ---------------------------------------------------------------------------
# 16. Parse + static hygiene.
# ---------------------------------------------------------------------------
$errs = $null; $toks = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($SCRIPT, [ref]$toks, [ref]$errs)
Check "16a parses with zero errors" ($errs.Count -eq 0) ($errs | ForEach-Object { $_.Message })
Check "16b no stale agentmemory guidance in the wrapper" `
    ($src -notmatch 'agentmemory (does not|needs WSL2|cannot install)') 'found stale text'
Check "16c documents the pocock tool" ($src -match 'pocock') 'pocock not mentioned'
Check "16d documents why Git Bash is the default" `
    ($src -match 'native Windows PATH') 'missing the native-PATH rationale'

# ---------------------------------------------------------------------------
Write-Host ($results -join "`n")
Write-Host "`n----------------------------------------"
Write-Host ("  {0} passed, {1} failed" -f $pass, $fail) -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
Write-Host "----------------------------------------`n"

Remove-Item -Recurse -Force $ENVDIR -ErrorAction SilentlyContinue
exit $(if ($fail) { 1 } else { 0 })
