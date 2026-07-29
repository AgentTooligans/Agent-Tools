# Platforms

| platform | support | service | verified |
|---|---|---|---|
| macOS | full | launchd user agent | ✅ macOS 15 (Apple Silicon) |
| Linux | full | systemd `--user` | ✅ Ubuntu 24.04 container |
| WSL2 | full | systemd `--user` | ✅ Windows 11 + Ubuntu 26.04, systemd on |
| Windows native | **graphify only** | none | ✅ Win 11 + Git Bash |

"Verified" means the tool was actually run there, not that it should work.

---

## macOS

launchd user agent at `~/Library/LaunchAgents/com.agentmemory.server.plist`.

## Linux

systemd `--user` unit at `~/.config/systemd/user/agentmemory.service`.
`install-machine` also runs `loginctl enable-linger`, without which the memory
server dies at logout on most distros.

**Without systemd** (containers, minimal distros) there is no supervisor. The
tool detects this and prints the exact manual command — including the working
directory, which is not optional:

```bash
cd ~/.agentmemory && agentmemory --tools core &
```

**Root without sudo** (containers, CI) is handled: it runs package managers
directly when uid 0, uses sudo when available, and otherwise stops with
instructions instead of failing obscurely.

**Sudo that needs a password, with no terminal** is also handled. `sudo -n` is
tried first; if a password is required and stdin is not a TTY, the tool refuses
rather than hanging until `sudo: timed out`.

---

## WSL2

Same as Linux when systemd is enabled. To enable it:

```ini
# /etc/wsl.conf
[boot]
systemd=true
```
then `wsl --shutdown` from Windows and reopen.

### The WSL trap that matters most

**WSL inherits the Windows PATH.** `node` and `npm` routinely resolve to
Windows binaries through `/mnt/c` interop:

```
npm:         /mnt/c/Program Files/nodejs/npm
agentmemory: /mnt/c/Users/<you>/AppData/Roaming/npm/agentmemory
```

Installing through those puts packages in the **Windows** npm prefix. A Linux
systemd unit then points at a Windows binary, the service fails, and every
status check still prints green. This was observed on real WSL2 on 2026-07-29 —
the installer reported "agentmemory installed ✓" and the service was dead.

So inside WSL, **a Windows-hosted binary counts as not installed**. `doctor`
names the offender and the fix:

```
✗ npm is the WINDOWS one (/mnt/c/Program Files/nodejs/npm)
  — 'sudo apt-get install -y nodejs npm' inside WSL
```

### Node version — the trap on Ubuntu 24.04

**agentmemory declares `engines: node >=20`, and npm only WARNS about that.** So
on Ubuntu 24.04 — whose `apt` Node is **18.19** — it installs happily and then
crash-loops forever:

```
SyntaxError: The requested module 'node:util'
does not provide an export named 'styleText'
```

(`styleText` arrived in Node 20.12.) The systemd unit restarts it, so you get a
service that is permanently "active" and never answers on :3111.

`agent-tools` now refuses to install agentmemory on Node < 20, and offers a
NodeSource upgrade instead. Verified end to end on a pristine Ubuntu 24.04 WSL2
distro: 18.19 → 22.23.1 → agentmemory installed → service healthy on :3111.

### Line endings — CRLF is fatal

Cloning this repo on Windows with git's default `core.autocrlf=true` rewrites
the script to CRLF, and then it cannot start at all:

```
/usr/bin/env: 'bash\r': No such file or directory
```

Two defenses, both in place:

- `.gitattributes` pins `eol=lf`, so git checkouts stay LF on every platform.
- `install.sh` strips CR while installing, covering delivery by zip, email or
  copy-paste, where `.gitattributes` cannot help. It says so when it does.

### Path quirks — all verified passing

`init` was run in each of these on real WSL2, on both filesystems:

| path contains | `/mnt/c` | native Linux |
|---|---|---|
| spaces (`My Test Folder`) | ✅ | ✅ |
| unicode (`tëst-プロジェクト`) | ✅ | ✅ |
| parentheses and `&` | ✅ | ✅ |
| `#` and `$` | ✅ | ✅ |
| apostrophes (`o'brien's stuff`) | ✅ | ✅ |
| deep nesting (11 levels) | ✅ | ✅ |

### Windows folders (`/mnt/c/...`) vs native Linux folders

**Both work.** Verified on real WSL2 by running `init` in each and committing:

| | `~/project` (ext4) | `/mnt/c/Users/you/project` (DrvFs) |
|---|---|---|
| `init` completes | ✅ | ✅ |
| graph builds | ✅ | ✅ |
| post-commit hook is executable | ✅ | ✅ |
| hook actually fires on commit | ✅ | ✅ (confirmed via its log) |

DrvFs mounts everything `rwxrwxrwx`, so the hook's executable bit is effectively
free there.

Two caveats for `/mnt/c`, neither a blocker:

- **It is slower.** DrvFs 9p I/O is markedly slower than ext4, and graphify is
  I/O-heavy. Large graphs build faster in a native Linux folder.
- **Everything reads as 777**, so permissions are not meaningful on that mount.

If you have the choice, keep repos in the Linux filesystem and reach them from
Windows via `\\wsl$\`. If your repo already lives on `C:`, it works fine.

---

## Windows native

**graphify works** — it is pure Python and installs through `uv`.

**agentmemory does not.** Upstream's own README:

> *"On Windows the fast path is WSL2. Native Windows engine setup is manual
> (about 10 to 20 minutes) and `agentmemory connect` is currently unsupported
> there."*

Its engine has no PowerShell, scoop or winget package; you fetch
`iii-x86_64-pc-windows-msvc.zip` from GitHub releases by hand. One exception:
`agentmemory connect copilot-cli` is Windows-safe.

So on native Windows `agent-tools` sets up graphify and says so plainly rather
than pretending. **Use WSL2.**

### Verified on Windows 11 + Git Bash (2026-07-29)

| step | result |
|---|---|
| platform detection | ✅ `MINGW64_NT-10.0` → `windows` |
| `doctor` | ✅ degrades honestly, no crash |
| `install-machine` | ✅ uv 0.12.0 via the Astral installer, graphify with extras + pin |
| agentmemory | ✅ correctly SKIPPED with the reason |
| `init` | ✅ gitignore, hook-guard, hook, MCP, AGENTS.md, graph built |
| `graphify query` | ✅ returned the expected nodes |
| `graphify affected` | ✅ `.run() [calls] src/app.py:L6` |

**The Windows trap that nearly broke it: `python3` is a Microsoft Store stub.**

```
python3 -> AppData/Local/Microsoft/WindowsApps/python3     (stub)
python  -> AppData/Local/Programs/Python/Python312/python  (real, 3.12.10)
```

The stub is on PATH and answers every call with *"Python was not found; run
without arguments to install from the Microsoft Store"*. An existence check
(`command -v python3`) picks it over the real interpreter sitting next to it. So
the picker now **executes** a probe (`python -c pass`) and takes the first one
that actually runs, trying `python3`, `python`, then `py`.

**If no Python at all:** `uv python install` provisions one — no admin rights and
no extra package manager, since uv is already required for graphify.
`install-machine` offers this automatically.

Note graphify itself does not need a system Python (uv gives it its own);
`agent-tools` needs one for reading the graph and writing
`.claude/settings.json`.

### PowerShell

`agent-tools.ps1` gives PowerShell users the same commands, preferring WSL and
falling back to Git Bash. Verified: `version`, `doctor` and `init` all ran from
`C:\Users\...\ps test repo` — spaces included — translating correctly to
`/mnt/c/...`.
