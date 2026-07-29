#!/usr/bin/env bash
# Put agent-tools on your PATH, then verify it runs.
#
#   ./install.sh            install to ~/.local/bin
#   ./install.sh /usr/local/bin   install somewhere else
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${1:-$HOME/.local/bin}"

mkdir -p "$DEST" || { echo "cannot create $DEST"; exit 1; }
# Strip CR on the way in. .gitattributes handles git clones, but a file that
# arrived by zip, email or copy-paste from Windows can still carry CRLF, and a
# CRLF shebang fails with: /usr/bin/env: 'bash\r': No such file or directory
tr -d '\r' < "$SRC/agent-tools" > "$DEST/agent-tools" && chmod 755 "$DEST/agent-tools"
echo "installed: $DEST/agent-tools"
if grep -q $'\r' "$SRC/agent-tools" 2>/dev/null; then
    echo "  note: source had Windows (CRLF) line endings — stripped during install"
fi

# The helper scripts are optional; only useful for large doc corpora.
for f in graphify-full-run.sh graphify-run-status; do
    [ -f "$SRC/scripts/$f" ] || continue
    tr -d '\r' < "$SRC/scripts/$f" > "$DEST/$f" && chmod 755 "$DEST/$f" && echo "installed: $DEST/$f"
done

case ":$PATH:" in
    *":$DEST:"*) echo "PATH: ok" ;;
    *) echo
       echo "WARNING: $DEST is not on your PATH. Add this to your shell profile:"
       echo "    export PATH=\"$DEST:\$PATH\"" ;;
esac

echo
"$DEST/agent-tools" version 2>/dev/null || echo "(could not run agent-tools — check bash is available)"
echo
echo "Next:  agent-tools doctor"
