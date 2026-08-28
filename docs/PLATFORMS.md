# Which platforms this works on

Short answer: macOS, Linux, WSL2 and native Windows, and we've actually run it
on all of them rather than assuming.

Longer answer below, including the handful of places where a platform behaves
differently enough that you should know about it before you get surprised —
Windows symlinks and WSL filesystem boundaries being the two that bite hardest.

| platform | support | service | verified |
|---|---|---|---|
| macOS | full | **none needed** | ✅ macOS 15 (Apple Silicon) |
| Linux | full | **none needed** | ✅ Ubuntu 24.04 container |
| WSL2 | full | **none needed** | ✅ Windows 11 + Ubuntu 26.04 |
| Windows native | full — rtk installs from its native release binary | none | ✅ Win 11 + Git Bash |

"Verified" means the tool was actually run there, not that it should work.

**Since 3.3.0 nothing here installs a launchd plist or a systemd unit.** The
agentmemory backend that needed supervising was removed; claude-mem runs its
own worker with an absolute store path. That also closed the native-Windows
gap — see [Windows native](#windows-native) below. Details: [SERVICES.md](SERVICES.md).

## Per tool

| tool | macOS | Linux | WSL2 | Windows native | installed via |
|---|---|---|---|---|---|
| graphify | ✅ | ✅ | ✅ | ✅ | uv |
| claude-mem | ✅ | ✅ | ✅ | ✅ | npm |
| caveman | ✅ | ✅ | ✅ | ✅ | npx / skills |
| pocock | ✅ | ✅ | ✅ | ✅ `--copy` | skills (`npx skills add`) |
| rtk | ✅ brew | ✅ install.sh | ✅ install.sh | ⚠️ cargo or release zip | see below |
| superpowers | ✅ | ✅ | ✅ | ✅ | claude plugin |
| context-mode | ✅ | ✅ | ✅ | ✅ | claude plugin (Node ≥ 22.5) |
| code-review-graph | ✅ | ✅ | ✅ | ✅ | uv |
| token-savior | ✅ | ✅ | ✅ | ✅ | uv |

Everything installed through **uv**, **npm/npx** or the **Claude plugin
system** is platform-agnostic by construction. As of 3.9.0 there is no
Windows gap left: rtk installs from its native release binary too (below). The
one that used to bite, agentmemory, was removed — it shipped no native-Windows
engine installer, and that single fact is what kept this table saying
"Windows: graphify only" for three minor versions.

### The skill packs on native Windows

`npx skills add` **symlinks** `~/.agents/skills/<skill>` into each agent's own
skills directory. On Windows a symlink needs Administrator or Developer Mode,
and on a filesystem without symlink support the install can look successful
while leaving those directories empty.

`agent-tools` therefore passes `--copy` when the platform is `windows`, which
writes real files instead. Consequence worth knowing: copies do not track
`~/.agents/skills`, so after `agent-tools update pocock` (or `caveman`) on
Windows, re-run `agent-tools install <pack>` to refresh them. On macOS, Linux
and WSL the symlinks make that unnecessary.

### rtk on native Windows

Upstream's `install.sh` is POSIX-only, so on Windows `agent-tools install rtk`
downloads the native release binary directly:

1. fetches `rtk-x86_64-pc-windows-msvc.zip` from the latest `rtk-ai/rtk`
   release and extracts `rtk.exe` into `~/.local/bin` (on the native Windows
   PATH) — no Rust required, and naming the repo rather than the crates.io
   package sidesteps the name collision;
2. falls back to `cargo install --git https://github.com/rtk-ai/rtk` if the
   download is unavailable and Rust is present.

The hook it needs is a `settings.json` entry, not a native component, so it
works identically once the binary exists. For full filter support on Windows,
also install ripgrep: `winget install BurntSushi.ripgrep.MSVC`.

### context-mode and the Node floor

context-mode needs **Node >= 22.5**, two majors above this project's floor of
20. On older Node it installs cleanly and then every hook fails at
*runtime* — which reads as a broken session rather than a version problem. So
`install-machine` checks first and skips it with an explanation.

Ubuntu 24.04 — the most common WSL LTS — ships Node 18.19, so on a fresh WSL
distro expect to install Node before either of them.

---

## macOS, Linux and WSL2

**Nothing to supervise.** Earlier versions installed a launchd user agent
(`~/Library/LaunchAgents/com.agentmemory.server.plist`) and a systemd `--user`
unit (`~/.config/systemd/user/agentmemory.service`), plus `loginctl
enable-linger` on Linux so the memory server survived logout. All of that
existed to pin one working directory for a backend that no longer ships.

What remains is claude-mem's worker, started by you or by your shell profile:

```bash
npx claude-mem start
agent-tools doctor        # checks :37701 and prints the fix
```

`loginctl enable-linger` and `systemd=true` in `/etc/wsl.conf` are no longer
required by anything in this project. If you set them up for agent-tools, they
are now inert here (other software on your machine may still want them).

Retiring a unit an older install left behind: `agent-tools memory
migrate-from-agentmemory`, documented in [SERVICES.md](SERVICES.md).

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
npm:        /mnt/c/Program Files/nodejs/npm
claude-mem: /mnt/c/Users/<you>/AppData/Roaming/npm/claude-mem
```

Installing through those puts packages in the **Windows** npm prefix, where
anything on the Linux side that expects them fails while every status check
still prints green. This was observed on real WSL2 on 2026-07-29 — the
installer reported "installed ✓" and the resulting service was dead.

The removal of the supervised backend took away the worst version of this
failure (a systemd unit pointing at a Windows binary), but the underlying PATH
problem is unchanged and still bites npm-installed tools.

So inside WSL, **a Windows-hosted binary counts as not installed**. `doctor`
names the offender and the fix:

```
✗ npm is the WINDOWS one (/mnt/c/Program Files/nodejs/npm)
  — 'sudo apt-get install -y nodejs npm' inside WSL
```

### Node version — the trap on Ubuntu 24.04

**npm only WARNS about an unmet `engines` field.** So on Ubuntu 24.04 — whose
`apt` Node is **18.19** — a package declaring `node >=20` installs happily and
then crash-loops forever:

```
SyntaxError: The requested module 'node:util'
does not provide an export named 'styleText'
```

(`styleText` arrived in Node 20.12.) Under the old supervised backend systemd
kept restarting it, so you got a service that was permanently "active" and
never answered.

`agent-tools` refuses to install the npm-based tools on Node < 20, and offers a
NodeSource upgrade instead. Verified end to end on a pristine Ubuntu 24.04 WSL2
distro: 18.19 → 22.23.1 → healthy install.

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

**Supported since 3.3.0**, with one gap.

Working: graphify (pure Python via `uv`), claude-mem (plain Node),
code-review-graph and token-savior (uv), superpowers and context-mode (Claude
plugin system), caveman and pocock (the `skills` CLI).

**Not working: rtk.** No scoop or winget package, and its `install.sh` is
POSIX-only. `agent-tools install rtk` builds it with `cargo install --git` when
Rust is present, and otherwise prints the release-zip instructions rather than
installing something that might be the [wrong `rtk`](#rtk-on-native-windows).

### What changed

Through 3.2.x this section read *"graphify works, agentmemory does not — use
WSL2"*. That was accurate: agentmemory's engine had no PowerShell, scoop or
winget package (you fetched `iii-x86_64-pc-windows-msvc.zip` by hand), and
upstream's own README said `agentmemory connect` was *"currently unsupported
there"*.

Removing that backend removed the blocker. **WSL2 is still the smoother
route** — one PATH model, no Git Bash quirks — but it is no longer required.

### Verified on Windows 11 + Git Bash (2026-07-29)

| step | result |
|---|---|
| platform detection | ✅ `MINGW64_NT-10.0` → `windows` |
| `doctor` | ✅ degrades honestly, no crash |
| `install-machine` | ✅ uv 0.12.0 via the Astral installer, graphify with extras + pin |
| agentmemory (3.2.x only) | ✅ correctly SKIPPED with the reason — the backend is gone as of 3.3.0 |
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
