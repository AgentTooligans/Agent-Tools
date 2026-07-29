# Platforms

| platform | support | service | verified |
|---|---|---|---|
| macOS | full | launchd user agent | ✅ macOS 15 (Apple Silicon) |
| Linux | full | systemd `--user` | ✅ Ubuntu 24.04 container |
| WSL2 | full | systemd `--user` | ✅ Windows 11 + Ubuntu 26.04, systemd on |
| Windows native | **graphify only** | none | ⚠️ **not yet verified** |

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

Known unknowns on native Windows (Git Bash), untested as of 2026-07-29:

- the `uv` install path (the Astral installer is a `sh` script)
- `python` vs `python3` — handled in code, unverified in practice
- path translation when registering MCP servers
