# The memory worker: when it runs, and when it doesn't

**The short version: nothing here installs a background service.** No launchd
plist, no systemd unit, nothing that survives a reboot on its own.

That's deliberate, and it's a change from earlier versions. We used to
supervise a memory server, and supervising it turned out to cause more problems
than it solved — the details are further down if you're curious.

What you're left with is simpler: a lightweight worker that you start when you
want it, and that `agent-tools doctor` will tell you about if it isn't running.

graphify is a CLI — it runs when you call it and exits, so there was never
anything to supervise there. claude-mem runs a worker, but it manages its own
lifecycle and its store path is absolute, so it does not need one either.

| backend | what runs | supervised? |
|---|---|---|
| **claude-mem** (default) | worker on :37701 + web UI | **no unit** — `npx claude-mem start` |
| **none** | nothing | — |

---

## claude-mem: the one thing you must know

The installer says plainly:

> *Worker autostart skipped — start it manually with `npx claude-mem start`.*

That is lighter than a supervised server, but it is **not nothing**: if the
worker is not running, capture does not happen. Nothing warns you in the
session — memories simply never appear.

```bash
npx claude-mem start      # start it
npx claude-mem stop       # stop it
curl -s localhost:37701   # raw check
agent-tools doctor        # checks :37701 and names the fix
```

Agent-tools provides the portable lifecycle command:

```bash
agent-tools restart claude-mem  # stop, start, then wait for a health check
agent-tools restart memory      # alias for claude-mem
agent-tools restart all         # every managed service (currently claude-mem)
```

It prints each lifecycle stage and never changes Claude-mem's provider,
model, credentials, or store. `all` is intentionally honest: today
claude-mem is the only managed background worker; graphify runs on demand and
plugins/hooks do not have restartable services.

`agent-tools doctor` reports the worker under **Memory backend**. If you only
ever run one command from this page, run that one.

### Making it start at login

There is no unit, so nothing starts it for you after a reboot. Pick whichever
of these you prefer — none is installed automatically, because a worker you
did not ask for is exactly the kind of surprise this repo tries not to create.

**macOS / Linux / WSL2** — add it to your shell profile:

```bash
# ~/.zshrc or ~/.bashrc
(command -v npx >/dev/null && curl -sf -m 1 http://127.0.0.1:37701 >/dev/null 2>&1) \
    || npx claude-mem start >/dev/null 2>&1 &
```

The `curl` guard means opening ten terminals does not start ten workers.

**Or just let `agent-tools doctor` tell you.** Most people run it when
something looks wrong, and it prints the exact command.

---

## WSL2

Nothing special is required any more. Before 3.3.0 this section described a
reboot gap: WSL distros do not start when Windows starts, so systemd inside the
distro was not running, so the supervised memory server was not running. With
no unit in the picture, the gap is gone — the worker starts when you start it,
the same as on any other platform.

You no longer need `systemd=true` in `/etc/wsl.conf` for memory, and you no
longer need `loginctl enable-linger` on Linux. If you set either of those up
for agent-tools specifically, they are now inert as far as this project is
concerned. (Other software on your machine may still want them.)

---

## Windows native

Supported. Before 3.3.0 this page said "not supported", because the agentmemory
backend had no Windows engine installer. That backend is gone, and claude-mem
is plain Node — it runs under Git Bash or WSL alike.

**rtk** used to be the one Windows gap; as of 3.9.0 `agent-tools install rtk`
downloads its native release binary (`rtk-x86_64-pc-windows-msvc.zip`) onto your
PATH automatically, falling back to `cargo install --git` only if that download
is unavailable. See [PLATFORMS.md](PLATFORMS.md).

---

## Legacy: retiring a pre-3.3.0 agentmemory service

If this machine was set up by an older agent-tools, it may still have a
supervised agentmemory server. `agent-tools doctor` detects one and says so —
loudly, if it is capturing at the same time as claude-mem, because then every
tool call fires two hook sets into two stores.

One command retires it. **Your data is not deleted**: the store at
`~/.agentmemory` is left byte-for-byte intact, and a Markdown export is written
first.

```bash
agent-tools memory migrate-from-agentmemory
```

It exports the store, imports what it can into claude-mem through claude-mem's
own hook pipeline, then stops the server, disables the unit (keeping the file
as `.disabled`), disables the Claude Code plugin, and removes the stale MCP
entry.

To check by hand what is still there:

```bash
# macOS
launchctl print gui/$(id -u)/com.agentmemory.server
# Linux / WSL2
systemctl --user status agentmemory
journalctl --user -u agentmemory -n 50
```

Why that migration is one-way, and why the old server needed supervising at
all, is in [WHY.md](WHY.md) and [MEMORY.md](MEMORY.md).
