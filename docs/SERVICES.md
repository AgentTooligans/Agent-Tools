# The memory server: startup, restarts, and reboots

Only **agentmemory** runs as a service. graphify is a CLI — it runs when you
call it and exits. Nothing to supervise.

---

## What runs where

| platform | supervisor | starts at | survives reboot |
|---|---|---|---|
| macOS | launchd user agent | login | ✅ automatically |
| Linux | systemd `--user` + linger | boot | ✅ automatically |
| WSL2 | systemd `--user` | **when the distro starts** | ⚠️ see below |
| Windows native | none | — | ❌ not supported |

### Why not cron?

cron is a scheduler, not a supervisor. It can start something at a time, but it
will not restart a crashed process, does not track state, and gives you no
status command. launchd and systemd both restart on failure — which matters,
because the memory engine can die and you would otherwise never notice. That is
why `agent-tools` uses them and not a `@reboot` cron line.

---

## macOS

`~/Library/LaunchAgents/com.agentmemory.server.plist` with `RunAtLoad` and
`KeepAlive` on failure. Log in, it starts. It crashes, launchd restarts it.

```bash
launchctl print gui/$(id -u)/com.agentmemory.server   # status
launchctl bootout  gui/$(id -u)/com.agentmemory.server  # stop
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.agentmemory.server.plist
```

## Linux

`~/.config/systemd/user/agentmemory.service`, enabled, with `Restart=on-failure`.
`install-machine` also runs `loginctl enable-linger`, **without which the service
stops when you log out** and never starts on a headless boot.

```bash
systemctl --user status agentmemory
systemctl --user restart agentmemory
journalctl --user -u agentmemory -n 50
```

## WSL2 — the reboot gap

This is the one that surprises people.

**WSL distros do not start when Windows starts.** systemd inside the distro only
starts when the distro itself does — which happens the first time you open a WSL
terminal, or when something invokes `wsl.exe`. So after a Windows restart:

- the distro is stopped
- systemd is not running
- the memory server is **not running**
- it starts the moment you open WSL, and then keeps running

For most people that is fine: you open a terminal before you do any work, and
the server is up by the time an agent needs it.

**If you want it up without opening a terminal**, add a logon task that boots the
distro. In an Administrator PowerShell:

```powershell
$action  = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-d Ubuntu --exec /bin/true"
$trigger = New-ScheduledTaskTrigger -AtLogOn
Register-ScheduledTask -TaskName "Start WSL at logon" -Action $action -Trigger $trigger `
    -Description "Boots the WSL distro so its systemd services (agentmemory) start."
```

Running `/bin/true` is enough — starting the distro starts systemd, which starts
the service. Replace `Ubuntu` with your distro name from `wsl -l -q`.

To remove it:

```powershell
Unregister-ScheduledTask -TaskName "Start WSL at logon" -Confirm:$false
```

Also confirm systemd is actually on, or there is no supervisor at all:

```ini
# /etc/wsl.conf
[boot]
systemd=true
```
then `wsl --shutdown` from Windows and reopen.

## Windows native

No service is installed, because agentmemory does not run properly there — its
engine has no PowerShell/scoop/winget installer and `connect` is unsupported.
`agent-tools` sets up graphify and says so. Use WSL2.

If you insist on native Windows, you would fetch
`iii-x86_64-pc-windows-msvc.zip` from the iii releases, put `iii.exe` on PATH,
and register a Task Scheduler job running `agentmemory --tools core` with its
working directory set to `%USERPROFILE%\.agentmemory` — the working directory is
not optional, see [WHY.md](WHY.md).

---

## Checking it, whatever the platform

```bash
agent-tools doctor              # names the exact problem and fix
curl -s localhost:3111/agentmemory/health   # raw check
agentmemory status              # sessions, memories, flags
```

A useful detail: the engine downloads a binary on first run, so immediately
after installation the health check can fail for a few seconds while the service
is genuinely fine. Give it ~30s before concluding anything.
