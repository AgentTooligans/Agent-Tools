#!/usr/bin/env bash
# Run every suite in this repo.
#
#   tests/run-all.sh
#
# The bash suite always runs. The PowerShell suite runs only where pwsh 7 is
# present -- it is SKIPPED, never failed, on a machine without it, because the
# wrapper it tests is only reachable from Windows anyway.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rc=0

echo "########################################"
echo "# bash suite"
echo "########################################"
bash "$ROOT/tests/bash/run-tests.sh" || rc=1

echo
echo "########################################"
echo "# PowerShell wrapper suite"
echo "########################################"
if command -v pwsh >/dev/null 2>&1; then
    pwsh -NoProfile -File "$ROOT/tests/ps1/run-tests.ps1" || rc=1
else
    echo
    echo "  SKIP  pwsh not installed — agent-tools.ps1 is untested on this machine."
    echo "        macOS/Linux:  brew install --cask powershell   (or the tarball)"
    echo "        Windows:      pwsh ships with Windows 10+"
    echo
fi

echo
if [ "$rc" = 0 ]; then echo "ALL SUITES PASSED"; else echo "FAILURES ABOVE"; fi
exit "$rc"
