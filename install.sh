#!/usr/bin/env bash
# Put agent-tools on your PATH, then verify it runs.
#
#   ./install.sh            install to ~/.local/bin
#   ./install.sh /usr/local/bin   install somewhere else
#   ./install.sh --version  print what this checkout would install, then stop
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read the release identity out of the script rather than duplicating it here.
# Two copies of a version number is one copy too many.
SRC_VERSION="$(sed -n 's/^VERSION=//p' "$SRC/agent-tools" 2>/dev/null | head -1)"
SRC_DATE="$(sed -n 's/^VERSION_DATE=//p' "$SRC/agent-tools" 2>/dev/null | head -1)"

case "${1:-}" in
    --version|-v|version)
        printf 'agent-tools %s   (released %s)\n' "${SRC_VERSION:-unknown}" "${SRC_DATE:-unknown}"
        printf '  source:    %s\n' "$SRC"
        existing="$(command -v agent-tools 2>/dev/null)"
        if [ -n "$existing" ]; then
            have_v="$(sed -n 's/^VERSION=//p' "$existing" 2>/dev/null | head -1)"
            printf '  installed: %s  (%s)\n' "${have_v:-unknown}" "$existing"
            if [ -n "$have_v" ] && [ "$have_v" != "$SRC_VERSION" ]; then
                printf '  -> this checkout is %s; run ./install.sh to update\n' "$SRC_VERSION"
            fi
        else
            printf '  installed: not on PATH yet\n'
        fi
        exit 0 ;;
esac

DEST="${1:-$HOME/.local/bin}"

# Say what is about to happen before it happens. An installer that prints only
# a path leaves you guessing which version you just put on your PATH.
printf 'installing agent-tools %s (released %s)\n' "${SRC_VERSION:-unknown}" "${SRC_DATE:-unknown}"
existing="$(command -v agent-tools 2>/dev/null)"
if [ -n "$existing" ]; then
    prev="$(sed -n 's/^VERSION=//p' "$existing" 2>/dev/null | head -1)"
    [ -n "$prev" ] && printf '  replacing %s at %s\n' "$prev" "$existing"
fi

mkdir -p "$DEST" || { echo "cannot create $DEST"; exit 1; }
# Strip CR on the way in. .gitattributes handles git clones, but a file that
# arrived by zip, email or copy-paste from Windows can still carry CRLF, and a
# CRLF shebang fails with: /usr/bin/env: 'bash\r': No such file or directory
tr -d '\r' < "$SRC/agent-tools" > "$DEST/agent-tools" && chmod 755 "$DEST/agent-tools"
echo "installed: $DEST/agent-tools"

# Record where this checkout lives so `agent-tools update self` can find it.
# The installed file is a COPY: at runtime $0 is ~/.local/bin/agent-tools and
# has no path back to the repo it came from.
AT_CONF_DIR="$HOME/.config/agent-tools"
mkdir -p "$AT_CONF_DIR" 2>/dev/null
if [ -f "$AT_CONF_DIR/config" ]; then
    grep -v '^source_checkout=' "$AT_CONF_DIR/config" > "$AT_CONF_DIR/config.tmp" 2>/dev/null || true
    mv "$AT_CONF_DIR/config.tmp" "$AT_CONF_DIR/config" 2>/dev/null
fi
printf 'source_checkout=%s\n' "$SRC" >> "$AT_CONF_DIR/config"
echo "recorded source checkout: $SRC"
if grep -q $'\r' "$SRC/agent-tools" 2>/dev/null; then
    echo "  note: source had Windows (CRLF) line endings — stripped during install"
fi

# Helper scripts that agent-tools SHELLS OUT TO. These are not optional extras:
# agent-tools looks for them next to its own binary (dirname of `command -v
# agent-tools`), so leaving them behind gives you a command that reports
# "claude-mem-export.py not found next to agent-tools" the first time you run
# `agent-tools memory export`, `agent-tools obsidian`, or
# `agent-tools memory migrate-from-agentmemory`.
#
#   claude-mem-export.py         memory export + obsidian, claude-mem backend
#   memory-export.py             memory export from a legacy agentmemory server
#   agentmemory-to-claude-mem.py the one-way migration off agentmemory
#
# graphify-full-run.sh / graphify-run-status are genuinely optional (large doc
# corpora only), but cost nothing to carry along.
missing=0
for f in claude-mem-export.py memory-export.py agentmemory-to-claude-mem.py \
         graphify-full-run.sh graphify-run-status; do
    if [ ! -f "$SRC/scripts/$f" ]; then
        case "$f" in
            *.py) echo "  WARNING: $SRC/scripts/$f is missing — some commands will fail"
                  missing=1 ;;
        esac
        continue
    fi
    tr -d '\r' < "$SRC/scripts/$f" > "$DEST/$f" && chmod 755 "$DEST/$f" && echo "installed: $DEST/$f"
done
[ "$missing" = 1 ] && echo "  (re-run from a complete checkout to fix)"

case ":$PATH:" in
    *":$DEST:"*) echo "PATH: ok" ;;
    *)
       # Ubuntu's default .profile only adds ~/.local/bin if it ALREADY existed
       # at login, so a fresh install is invisible until the next session. Offer
       # to fix it rather than just warning.
       echo
       echo "$DEST is not on your PATH."
       line="export PATH=\"$DEST:\$PATH\""
       prof=""
       for f in "$HOME/.bashrc" "$HOME/.profile" "$HOME/.zshrc"; do
           [ -f "$f" ] && { prof="$f"; break; }
       done
       if [ -n "$prof" ] && [ -t 0 ]; then
           printf "Add it to %s? [Y/n] " "$prof"
           read -r ans
           case "$ans" in [nN]*) ;; *)
               grep -qF "$DEST" "$prof" 2>/dev/null || printf '\n# agent-tools\n%s\n' "$line" >> "$prof"
               echo "added to $prof — run: source $prof" ;;
           esac
       else
           echo "Add this to your shell profile:"
           echo "    $line"
       fi ;;
esac

echo
"$DEST/agent-tools" version 2>/dev/null || echo "(could not run agent-tools — check bash is available)"
echo
echo "Next:  agent-tools doctor"
