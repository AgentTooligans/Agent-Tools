#!/usr/bin/env bash
# Isolated test suite for the agent-tools bash script.
#
# HERMETIC BY CONSTRUCTION. Every test runs with HOME pointed at a throwaway
# directory and, where a repo is needed, inside a throwaway git repo. Nothing
# here may install a package, contact the network, or write outside its own
# sandbox -- so the suite only exercises commands that are pure output
# (version, help, wire/unwire, resolve, config round-trips) plus the two
# install paths that decline at their confirm prompt when stdin is closed.
#
# Usage:  tests/bash/run-tests.sh [/path/to/agent-tools]
#
# Every `check` call passes a condition as $(... && echo 0 || echo 1), which
# yields exactly one word by construction. Quoting each one would only add
# noise, so SC2046 is disabled for the file rather than 40 times inline.
# shellcheck disable=SC2046
set -uo pipefail

AT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/agent-tools}"
[ -f "$AT" ] || { echo "no such script: $AT"; exit 1; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
FAKE_HOME="$SANDBOX/home"; mkdir -p "$FAKE_HOME"
REPO="$SANDBOX/repo";      mkdir -p "$REPO"
( cd "$REPO" && git init -q && git commit -q --allow-empty -m init ) 2>/dev/null

pass=0; fail=0; results=()

check() {  # check <name> <condition-exit> [detail]
    if [ "$2" = 0 ]; then
        pass=$((pass+1)); results+=("  PASS  $1")
    else
        fail=$((fail+1)); results+=("  FAIL  $1${3:+
        $3}")
    fi
}
# Run agent-tools with a fake HOME and closed stdin. $CWD picks the directory.
# LAW: the default cwd is the SANDBOX, never the repo this script lives in.
# `uninstall --purge` deletes the CURRENT repo's graphify-out/ and per-repo
# graphs by design, so a test that forgets to leave the repo destroys real
# work. It happened. $CWD may only ever be the sandbox or $REPO (the throwaway
# git repo), and no test passes --purge outside a directory it created.
run() {
    local cwd="${CWD:-$SANDBOX}"
    case "$cwd" in
        "$SANDBOX"|"$SANDBOX"/*|"$REPO"|"$REPO"/*) ;;
        *) echo "TEST BUG: refusing to run with cwd outside the sandbox: $cwd"; exit 99 ;;
    esac
    ( cd "$cwd" && HOME="$FAKE_HOME" bash "$AT" "$@" </dev/null 2>&1 )
}
run_code() { run "$@" >/dev/null 2>&1; printf '%s' $?; }
has()  { printf '%s' "$1" | grep -q -- "$2"; }
hasnt() { ! printf '%s' "$1" | grep -q -- "$2"; }

echo
echo "=== agent-tools bash test suite ==="
echo "target:  $AT"
echo "sandbox: $SANDBOX"
echo

# ---------------------------------------------------------------------------
# 1. Static hygiene. A parse error or a malformed shellcheck directive makes
#    every later test meaningless, so these come first.
# ---------------------------------------------------------------------------
bash -n "$AT" 2>/dev/null; check "1a parses (bash -n)" $?
if command -v shellcheck >/dev/null 2>&1; then
    out="$(shellcheck -S warning -f gcc "$AT" 2>&1)"
    check "1b shellcheck clean at warning level" $([ -z "$out" ] && echo 0 || echo 1) "$out"
    # LAW: `# shellcheck disable=SCxxxx  -- prose` does not parse, and a
    # directive shellcheck cannot parse aborts the WHOLE FILE, silently
    # leaving the script unchecked. Directives must carry no trailing prose.
    bad="$(grep -n 'shellcheck disable=[A-Z0-9,]* *--' "$AT" || true)"
    check "1c no malformed shellcheck directives" $([ -z "$bad" ] && echo 0 || echo 1) "$bad"
else
    results+=("  SKIP  1b/1c shellcheck not installed")
fi

# ---------------------------------------------------------------------------
# 2. Trivial commands must work with no config, no HOME contents, no repo.
# ---------------------------------------------------------------------------
out="$(run version)"
check "2a version prints a version" $(has "$out" 'agent-tools [0-9]' && echo 0 || echo 1) "$out"
check "2b version exits 0" "$([ "$(run_code version)" = 0 ] && echo 0 || echo 1)"
out="$(run platform)"
check "2c platform prints a known platform" \
    $(printf '%s' "$out" | grep -qE '^(macos|linux|wsl|windows|unknown)$' && echo 0 || echo 1) "$out"
out="$(run help)"
check "2d help mentions install-machine" $(has "$out" 'install-machine' && echo 0 || echo 1)
check "2e unknown command exits 2" "$([ "$(run_code no-such-command)" = 2 ] && echo 0 || echo 1)"

# Managed-service lifecycle is exercised with fake npx/curl commands, so it
# never contacts a provider or the real worker.
mkdir -p "$FAKE_HOME/.local/bin" "$FAKE_HOME/.claude-mem"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" "$*" >> "$HOME/restart.log"' 'exit 0' > "$FAKE_HOME/.local/bin/npx"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$FAKE_HOME/.local/bin/curl"
chmod +x "$FAKE_HOME/.local/bin/npx" "$FAKE_HOME/.local/bin/curl"
printf '%s\n' '{"pid":1,"port":37701}' > "$FAKE_HOME/.claude-mem/worker.pid"
out="$(run restart memory)"
check "2f restart memory shows stop" $(has "$out" 'stopping worker' && echo 0 || echo 1) "$out"
check "2g restart memory shows start" $(has "$out" 'starting worker' && echo 0 || echo 1) "$out"
check "2h restart memory confirms health" $(has "$out" 'worker responding' && echo 0 || echo 1) "$out"
out="$(run doctor)"
check "2h2 doctor explains the restart command" $(has "$out" 'agent-tools restart memory' && echo 0 || echo 1) "$out"
check "2i restart calls stop and start" \
    $(grep -qx 'claude-mem stop' "$FAKE_HOME/restart.log" && grep -qx 'claude-mem start' "$FAKE_HOME/restart.log" && echo 0 || echo 1)
out="$(run restart all)"
check "2j restart all names its current service" $(has "$out" '1 managed service: claude-mem' && echo 0 || echo 1) "$out"
check "2k restart rejects an unknown service" "$([ "$(run_code restart unknown)" = 2 ] && echo 0 || echo 1)"

# ---------------------------------------------------------------------------
# 3. Tool-name resolution, including the aliases people actually type.
# ---------------------------------------------------------------------------
for alias_pair in "crg:code-review-graph" "ts:token-savior" "token-saviour:token-savior"; do
    a="${alias_pair%%:*}"; want="${alias_pair##*:}"
    out="$(CWD="$REPO" run unwire "$a")"
    check "3 alias '$a' resolves to $want" $(has "$out" "$want" && echo 0 || echo 1) "$out"
done
# Every skill in a pack must resolve to its pack. `grilling` ships alongside
# grill-me and is installed by the same command, so naming it must work too.
for sk in grill-me grilling handoff wait-what; do
    out="$(CWD="$REPO" run unwire "$sk")"
    check "3 skill name '$sk' resolves to the pocock pack" \
        $(has "$out" 'pocock' && echo 0 || echo 1) "$out"
done
out="$(run install definitely-not-a-tool)"
check "3d unknown tool name is rejected" $(has "$out" 'unknown tool' && echo 0 || echo 1) "$out"

# ---------------------------------------------------------------------------
# 4. SCOPE. The rule the whole tool rests on: skills are machine-wide, hooks
#    and plugins have a --project form, MCP tools have wire/unwire. Getting
#    these messages wrong is what sends people to the wrong command.
# ---------------------------------------------------------------------------
for sk in caveman pocock; do
    out="$(CWD="$REPO" run unwire "$sk")"
    check "4a $sk is described as a skill pack, not a plugin" \
        $( (has "$out" 'skill pack' && hasnt "$out" 'it is a plugin') && echo 0 || echo 1) "$out"
    check "4b $sk is not told to use --project" \
        $(hasnt "$out" "install $sk --project" && echo 0 || echo 1) "$out"
done
out="$(CWD="$REPO" run unwire rtk)"
check "4c rtk is described as a hook" $(has "$out" 'it is a hook' && echo 0 || echo 1) "$out"
check "4d rtk IS told about --project" $(has "$out" 'install rtk --project' && echo 0 || echo 1) "$out"
out="$(CWD="$REPO" run unwire superpowers)"
check "4e superpowers is described as a plugin" $(has "$out" 'it is a plugin' && echo 0 || echo 1) "$out"

# --project on a skill pack must SAY it is machine-wide rather than silently
# doing a global install under a project-scoped flag.
for sk in caveman pocock; do
    out="$(CWD="$REPO" run install "$sk" --project)"
    check "4f install $sk --project warns it has no per-project form" \
        $(has "$out" 'no per-project form' && echo 0 || echo 1) "$out"
done

# --project outside a git repo is an error, not a silent machine-wide install.
out="$(run install rtk --project)"
check "4g --project outside a repo is refused" \
    $(has "$out" 'needs a git repository' && echo 0 || echo 1) "$out"
check "4h --project outside a repo exits non-zero" \
    "$([ "$(CWD="$SANDBOX" run_code install rtk --project)" != 0 ] && echo 0 || echo 1)"

# `agent-tools tools` is where people look before typing a command, so the
# scope rule has to be visible there, not only in the docs.
out="$(run tools)"
check "4i tools output states --project does not apply to skills" \
    $(has "$out" 'does NOT apply to caveman or pocock' && echo 0 || echo 1) "$out"

# ---------------------------------------------------------------------------
# 5. Help text must document the scope rule it enforces.
# ---------------------------------------------------------------------------
out="$(run help)"
check "5a help says skills are exempt from --project" \
    $(has "$out" 'skill packs' && echo 0 || echo 1)
check "5b help lists pocock as a tool" $(has "$out" 'pocock' && echo 0 || echo 1)
# It may EXPLAIN the removal; it must not OFFER it as a selectable value.
offered="$(printf '%s' "$out" | grep -E '^ +--memory=agentmemory' || true)"
check "5c agentmemory is not offered as a --memory value" \
    $([ -z "$offered" ] && echo 0 || echo 1) "$offered"
check "5d help explains the agentmemory removal" \
    $(has "$out" 'removed in 3.3.0' && echo 0 || echo 1)

# ---------------------------------------------------------------------------
# 6. The recorded source checkout. install.sh writes it; `update self` reads
#    it. Without it, every properly installed machine (running the COPY in
#    ~/.local/bin) reported "not running from a git checkout" and stopped.
# ---------------------------------------------------------------------------
SRC_REPO="$(cd "$(dirname "$AT")" && pwd)"
INSTALL_SH="$SRC_REPO/install.sh"
if [ -f "$INSTALL_SH" ]; then
    HOME="$FAKE_HOME" bash "$INSTALL_SH" "$SANDBOX/bin" >/dev/null 2>&1
    conf="$FAKE_HOME/.config/agent-tools/config"
    check "6a install.sh records source_checkout" $([ -f "$conf" ] && grep -q '^source_checkout=' "$conf" && echo 0 || echo 1)
    got="$(sed -n 's/^source_checkout=//p' "$conf" 2>/dev/null | tail -1)"
    check "6b recorded path is the checkout" $([ "$got" = "$SRC_REPO" ] && echo 0 || echo 1) "got '$got' want '$SRC_REPO'"
    # Re-running must not append a second line.
    HOME="$FAKE_HOME" bash "$INSTALL_SH" "$SANDBOX/bin" >/dev/null 2>&1
    n="$(grep -c '^source_checkout=' "$conf")"
    check "6c re-install does not duplicate the key" $([ "$n" = 1 ] && echo 0 || echo 1) "found $n lines"
    # The installed COPY must resolve back to the checkout rather than giving up.
    out="$( cd "$SANDBOX" && HOME="$FAKE_HOME" bash "$SANDBOX/bin/agent-tools" update self </dev/null 2>&1 )"
    check "6d update self finds the checkout from the installed copy" \
        $(hasnt "$out" 'no git checkout recorded' && echo 0 || echo 1) "$out"
    check "6e update self names the checkout path" $(has "$out" "$SRC_REPO" && echo 0 || echo 1) "$out"
else
    results+=("  SKIP  6 install.sh not found next to the script")
fi

# ---------------------------------------------------------------------------
# 7. Dead code and stale backend references. 3.3.0 removed agentmemory as a
#    BACKEND while keeping the migration path, so the distinction has to hold:
#    it may be detected and migrated, never installed or supervised.
# ---------------------------------------------------------------------------
check "7a no vestigial no-op case stub" \
    $(! grep -q 'case x in x)' "$AT" && echo 0 || echo 1)
check "7b no install path for agentmemory" \
    $(! grep -qE 'install_agentmemory|npm .*install.*@agentmemory' "$AT" && echo 0 || echo 1)
check "7c migration path still present" \
    $(grep -q 'memory_migrate_from_agentmemory' "$AT" && echo 0 || echo 1)
check "7d every default tool has an installer" \
    $(for t in rtk superpowers context_mode caveman pocock; do
          grep -q "^install_${t}()" "$AT" || exit 1; done; echo 0)

# ---------------------------------------------------------------------------
# 8. Every tool named in OPTIONAL_TOOLS must be reachable from install,
#    uninstall and update -- a tool that can be installed and not updated is
#    the failure mode this check exists to catch.
# ---------------------------------------------------------------------------
tools="$(sed -n 's/^OPTIONAL_TOOLS="\(.*\)"/\1/p' "$AT")"
for t in $tools; do
    check "8 $t is handled by install"   $(awk '/^install_tool_cmd\(\)/,/^}/' "$AT" | grep -q "^        $t)" && echo 0 || echo 1)
    check "8 $t is handled by uninstall" $(awk '/^uninstall_one\(\)/,/^}/' "$AT" | grep -qE "^        $t\)|\|$t\)" && echo 0 || echo 1)
    check "8 $t is handled by update"    $(awk '/^update_cmd\(\)/,/^}/' "$AT" | grep -q "= $t \]" && echo 0 || echo 1)
done

# ---------------------------------------------------------------------------
# 9. Versioning. Three dates that can differ, and a --short form for scripts.
# ---------------------------------------------------------------------------
out="$(run version)"
check "9a version reports the release date" $(has "$out" 'released' && echo 0 || echo 1) "$out"
check "9b version reports where it is installed" $(has "$out" 'installed' && echo 0 || echo 1) "$out"
out="$(run version --short)"
check "9c --short prints only the number" \
    $(printf '%s' "$out" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' && echo 0 || echo 1) "$out"
# VERSION and VERSION_DATE must both exist and be plausible, because install.sh
# reads them straight out of the file.
# LAW: drift detection must compare CONTENT. Comparing version strings alone
# missed a 46-line difference during development, because an edit without a
# version bump looks identical to the check.
check "9c2 drift detection hashes the file, not just VERSION" \
    $(grep -q 'file_hash' "$AT" && echo 0 || echo 1)
check "9c3 the same-version drift warning exists" \
    $(grep -q 'same version, different content' "$AT" && echo 0 || echo 1)
check "9d VERSION is set" $(grep -qE '^VERSION=[0-9]+\.[0-9]+\.[0-9]+$' "$AT" && echo 0 || echo 1)
check "9e VERSION_DATE is set" $(grep -qE '^VERSION_DATE=[0-9]{4}-[0-9]{2}-[0-9]{2}$' "$AT" && echo 0 || echo 1)
if [ -f "$INSTALL_SH" ]; then
    out="$(bash "$INSTALL_SH" --version 2>&1)"
    check "9f install.sh --version reports without installing" \
        $(has "$out" 'released' && echo 0 || echo 1) "$out"
    check "9g install.sh --version agrees with the script" \
        $(has "$out" "$(sed -n 's/^VERSION=//p' "$AT" | head -1)" && echo 0 || echo 1) "$out"
fi

# ---------------------------------------------------------------------------
# 10. Inventory: installed, available, and a version for each.
# ---------------------------------------------------------------------------
out="$(run status)"
check "10a status lists installed features" $(has "$out" 'Installed' && echo 0 || echo 1) "$out"
check "10b status lists available features" $(has "$out" 'Available' && echo 0 || echo 1) "$out"
check "10c status names the removal command" $(has "$out" 'agent-tools uninstall' && echo 0 || echo 1) "$out"
# It must work OUTSIDE a repo -- an inventory is machine-level, and the old
# status refused to run without one.
check "10d status works outside a git repo" \
    "$([ "$(run_code status)" = 0 ] && echo 0 || echo 1)" "$out"
out="$(CWD="$REPO" run status refresh)"
check "10e 'status refresh' still reaches the refresh view" \
    $(has "$out" 'Refresh status' && echo 0 || echo 1) "$out"
# LAW: never probe a uv tool for its own version -- token-savior boots a server
# and blocks. This is the check that keeps that from coming back.
# token-savior is the proven hazard: --version boots its server and blocks.
# The others answer, but go through the same cached uv lookup anyway.
check "10f never probes token-savior for its own version" \
    $(! grep -qE '^[^#]*\btoken-savior --version' "$AT" && echo 0 || echo 1) \
    "$(grep -nE '^[^#]*\btoken-savior --version' "$AT" || true)"
check "10g uv tool versions come from the cached list" \
    $(grep -q 'uv_tool_version' "$AT" && echo 0 || echo 1)

# ---------------------------------------------------------------------------
# 11. Uninstall. The destructive command, so the safety properties are the
#     tests: refuse without a target, never delete by default, and never act
#     non-interactively without an explicit flag.
# ---------------------------------------------------------------------------
check "11a uninstall with no target exits non-zero" \
    "$([ "$(run_code uninstall)" != 0 ] && echo 0 || echo 1)"
out="$(run uninstall)"
check "11b usage names 'all'" $(has "$out" 'all' && echo 0 || echo 1) "$out"
check "11c usage names --purge and --keep-data" \
    $( (has "$out" -- '--purge' && has "$out" -- '--keep-data') && echo 0 || echo 1) "$out"
out="$(run uninstall not-a-real-tool)"
check "11d unknown target is rejected" $(has "$out" 'unknown tool' && echo 0 || echo 1) "$out"

# `uninstall all` must refuse non-interactively rather than tearing down a
# machine because a script called it.
out="$(run uninstall all)"
check "11e 'all' refuses without a terminal" \
    $(has "$out" 'non-interactive' && echo 0 || echo 1) "$out"
check "11f 'all' exits non-zero when it refuses" \
    "$([ "$(run_code uninstall all)" != 0 ] && echo 0 || echo 1)"

# Data disclosure: a store in the fake HOME must be named, sized and labelled
# before anything is asked, and must survive a non-interactive run.
mkdir -p "$FAKE_HOME/.local/share/token-savior"
echo payload > "$FAKE_HOME/.local/share/token-savior/store.db"
out="$(run uninstall token-savior)"
check "11g names the data at risk" \
    $(has "$out" "$FAKE_HOME/.local/share/token-savior" && echo 0 || echo 1) "$out"
check "11h labels it unregenerable" $(has "$out" 'cannot be regenerated' && echo 0 || echo 1) "$out"
check "11i keeps the data when not told otherwise" \
    $([ -f "$FAKE_HOME/.local/share/token-savior/store.db" ] && echo 0 || echo 1) "data was deleted"
out="$(run uninstall token-savior --keep-data)"
check "11j --keep-data keeps it and says so" \
    $( (has "$out" 'data kept' && [ -f "$FAKE_HOME/.local/share/token-savior/store.db" ]) && echo 0 || echo 1) "$out"

# Only now, with --purge, may it go -- and only from inside the fake HOME.
out="$(run uninstall token-savior --purge)"
check "11k --purge deletes the named data" \
    $([ ! -f "$FAKE_HOME/.local/share/token-savior/store.db" ] && echo 0 || echo 1) "$out"

# Every feature the teardown claims to handle must actually have a branch.
for f in $(sed -n 's/^ALL_FEATURES="\(.*\)"/\1/p' "$AT"); do
    check "11 $f has an uninstall branch" \
        $(awk '/^uninstall_one\(\)/,/^}/' "$AT" | grep -qE "^        $f\)|\|$f\)" && echo 0 || echo 1)
    check "11 $f has a presence check" \
        $(awk '/^feature_present\(\)/,/^}/' "$AT" | grep -q "$f)" && echo 0 || echo 1)
done

# ---------------------------------------------------------------------------
# 12. The repo-scope purge guard. This is the accident that cost this project a
#     graph, so it gets the most direct test in the suite: --purge alone must
#     NEVER take a path that depends on the current working directory.
# ---------------------------------------------------------------------------
GREPO="$SANDBOX/guardrepo"
mkdir -p "$GREPO/graphify-out" "$FAKE_HOME/.config/graphify"
( cd "$GREPO" && git init -q ) 2>/dev/null
echo graph > "$GREPO/graphify-out/graph.json"
echo conf  > "$FAKE_HOME/.config/graphify/config.yaml"

out="$(CWD="$GREPO" run uninstall graphify --purge)"
check "12a --purge KEEPS repo-scoped data" \
    $([ -f "$GREPO/graphify-out/graph.json" ] && echo 0 || echo 1) "$out"
check "12b --purge says why it kept it" \
    $(has "$out" 'add --purge-repo' && echo 0 || echo 1) "$out"
check "12c repo rows are marked in the bill" \
    $(has "$out" 'THIS REPO' && echo 0 || echo 1) "$out"
check "12d --purge still deletes machine-wide data" \
    $([ ! -f "$FAKE_HOME/.config/graphify/config.yaml" ] && echo 0 || echo 1) "$out"

out="$(CWD="$GREPO" run uninstall graphify --purge --purge-repo)"
check "12e --purge-repo does delete it" \
    $([ ! -f "$GREPO/graphify-out/graph.json" ] && echo 0 || echo 1) "$out"
check "12f help documents --purge-repo" $(has "$(run help)" -- '--purge-repo' && echo 0 || echo 1)

# ---------------------------------------------------------------------------
# 13. All agents, not just Claude Code. The tools reach other hosts through
#     skills and CLIs; MCP is the optional, Claude-only path.
# ---------------------------------------------------------------------------
out="$(run agents)"
check "13a agents command runs" "$([ "$(run_code agents)" = 0 ] && echo 0 || echo 1)" "$out"
check "13b names codex" $(has "$out" 'codex' && echo 0 || echo 1) "$out"
check "13c names antigravity" $(has "$out" 'antigravity' && echo 0 || echo 1) "$out"
check "13d explains the CLI path" $(has "$out" 'graphify query' && echo 0 || echo 1) "$out"
check "13e says MCP is optional" $(has "$out" 'OPTIONAL' && echo 0 || echo 1) "$out"

# graphify's MCP must be togglable, or "MCP is optional" is not actionable.
out="$(CWD="$REPO" run unwire graphify)"
check "13f graphify can be unwired" \
    $(hasnt "$out" 'no per-project MCP entry' && echo 0 || echo 1) "$out"

# init --no-mcp: a repo set up with no server at all.
# Since 3.4.0 a PLAIN init wires nothing. This is the headline default, so it
# is asserted without any flag at all.
NOMCP="$SANDBOX/nomcp"
mkdir -p "$NOMCP"; ( cd "$NOMCP" && git init -q ) 2>/dev/null
out="$(CWD="$NOMCP" run init --yes)"
check "13g plain init wires no server by default" \
    $(has "$out" 'no MCP server wired' && echo 0 || echo 1) "$out"
check "13h it points at --add-mcp for the opt-in" \
    $(has "$out" -- '--add-mcp' && echo 0 || echo 1) "$out"
check "13i init writes AGENTS.md" $([ -f "$NOMCP/AGENTS.md" ] && echo 0 || echo 1) "$out"
# --no-mcp was the documented spelling for a few hours; keep accepting it
# rather than erroring on a flag someone scripted.
out="$(CWD="$NOMCP" run init --no-mcp --yes)"
check "13j --no-mcp is still accepted as the default" \
    $(hasnt "$out" 'unknown' && echo 0 || echo 1) "$out"
# AGENTS.md is the cross-agent standard file; the block in it must teach the
# CLI, because no other host reads Claude Code's MCP config.
check "13k the instruction block teaches the CLI" \
    $(grep -q 'graphify query' "$NOMCP/AGENTS.md" 2>/dev/null && echo 0 || echo 1)
check "13l the instruction block is host-neutral" \
    $(! grep -qi 'mcp__' "$NOMCP/AGENTS.md" 2>/dev/null && echo 0 || echo 1)
check "13m help documents --add-mcp" $(has "$(run help)" -- '--add-mcp' && echo 0 || echo 1)
check "13n help states the per-session cost of a server" \
    $(has "$(run help)" 'every session' && echo 0 || echo 1)
# LAW: init is re-run routinely. It must never tear out a server on its own.
check "13o init leaves an existing server alone" \
    $(awk '/^init_project\(\)/,/^}/' "$AT" | grep -q 'left as-is' && echo 0 || echo 1)

# 14. The CLI/MCP relationship the docs promise: one install provides both, and
#     wiring is reversible at any time. If these drift, the explanation in
#     AGENTS.md becomes wrong.
# ---------------------------------------------------------------------------
check "14a wire and unwire both accept graphify" \
    $(awk '/^wire_tool_cmd\(\)/,/^}/' "$AT" | grep -q 'graphify:unwire' && echo 0 || echo 1)
check "14b unwire graphify says the CLI still works" \
    $(awk '/^unwire_graphify\(\)/,/^}/' "$AT" | grep -q 'CLI still works' && echo 0 || echo 1)
check "14c --no-mcp is documented in help" $(has "$(run help)" -- '--no-mcp' && echo 0 || echo 1)
# The docs claim one package ships both entry points. Assert the script never
# tries to install an MCP server separately.
check "14d no separate MCP install path" \
    $(! grep -qE 'install .*graphify-mcp|uv tool install .*-mcp"' "$AT" && echo 0 || echo 1)

# 15. LLM backend selection. `refresh` used to hardcode --backend claude-cli,
#     which OVERRODE graphify's own auto-detection and broke every user who had
#     an API key but no Claude CLI.
# ---------------------------------------------------------------------------
check "15a refresh no longer hardcodes a backend" \
    $(! grep -qE 'graphify (extract|label) [^|]*--backend claude-cli' "$AT" && echo 0 || echo 1) \
    "$(grep -nE 'graphify (extract|label) [^|]*--backend claude-cli' "$AT" || true)"
check "15b a backend chooser exists" $(grep -q 'graphify_backend_args' "$AT" && echo 0 || echo 1)
check "15c an explicit override is honoured" \
    $(grep -q 'AGENT_TOOLS_BACKEND' "$AT" && echo 0 || echo 1)
check "15d API-key detection covers the non-Claude backends" \
    $(for v in GEMINI_API_KEY OPENAI_API_KEY DEEPSEEK_API_KEY; do
          grep -q "$v" "$AT" || exit 1; done; echo 0)
check "15e a semantic pass with no backend is refused up front" \
    $(grep -q 'require_llm_backend' "$AT" && echo 0 || echo 1)
check "15f --code-only is offered as the no-model path" \
    $(grep -q 'STRUCTURE needs no model' "$AT" && echo 0 || echo 1)
# The guard must NOT fire for --code-only, which needs no model at all.
check "15g --code-only skips the backend requirement" \
    $(awk '/^refresh\(\)/,/^}$/' "$AT" | grep -q 'mode" != "--code-only"' && echo 0 || echo 1)

# 16. Backend failure modes. Each of these was reproduced against a real
#     graphify before being asserted here.
# ---------------------------------------------------------------------------
check "16a an explicitly named backend is checked for its key" \
    $(grep -q 'backend_requirement_met' "$AT" && echo 0 || echo 1)
check "16b the missing requirement is named, not just reported" \
    $(grep -q 'backend_requirement_hint' "$AT" && echo 0 || echo 1)
check "16c a failed semantic pass explains itself" \
    $(grep -q 'semantic_pass_failed' "$AT" && echo 0 || echo 1)
check "16d it says the graph was not overwritten" \
    $(grep -q 'NOT overwritten with partial results' "$AT" && echo 0 || echo 1)
# Both extract paths must route failures through the explainer, not bare exit.
check "16e both extract calls use the failure explainer" \
    $([ "$(grep -c 'graphify extract .*|| semantic_pass_failed' "$AT")" = 2 ] && echo 0 || echo 1) \
    "$(grep -n 'graphify extract' "$AT")"
check "16f every backend graphify supports has a requirement rule" \
    $(for b in claude-cli openai gemini deepseek ollama; do
          awk '/^backend_requirement_met\(\)/,/^}/' "$AT" | grep -q "$b" || exit 1; done; echo 0)

# ---------------------------------------------------------------------------
printf '%s\n' "${results[@]}"
echo
echo "----------------------------------------"
echo "  $pass passed, $fail failed"
echo "----------------------------------------"
echo
[ "$fail" = 0 ]
