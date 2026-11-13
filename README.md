# Stable_NYU_HPC

Stable helpers for NYU Torch HPC, based on **[Ignition](https://github.com/wenboluu/Ignition)** by [wenboluu](https://github.com/wenboluu).

> Upstream: https://github.com/wenboluu/Ignition.git  
> This fork: https://github.com/Nemo0412/Stable_NYU_HPC.git

**Core:** one Microsoft login via `ignite`, then reuse SSH for hours from any terminal tool.  
**Optional:** pre-install or relocate Remote-SSH servers (Cursor and/or VS Code) under scratch.

## What changed vs upstream Ignition

Compared to [wenboluu/Ignition](https://github.com/wenboluu/Ignition):

1. **Manual Microsoft device-code auth (no auto Paste + Enter)**  
   Auto keystrokes often race the Microsoft page and trigger `AADSTS165000`. Flow: copy PIN → you finish browser login → press Enter in the terminal. Upstream’s `ssh -O check` probe is kept.

2. **Optional multi-editor Remote-SSH helpers** (`preinstall-remote-server.sh`)  
   Cursor-only users are not required; terminal-only users can ignore these scripts entirely. Supports Cursor, VS Code, or both; local/remote download or symlink-to-scratch.

Upstream additions we keep: `ignite-sh` (password + Duo), `NYUSHHPC.md`, and ControlMaster probe tests.

## Platforms

- [x] macOS
- [ ] Linux
- [ ] Windows

Fully supported on macOS; Linux/Windows helpers exist but are lightly tested.

## Prerequisites

- **Expect** — `brew install expect` (macOS) or your distro’s `expect` package
- **SSH** — OpenSSH client
- Clipboard only (no auto keystroke tools required for the default `ignite` flow)

## 1. SSH config

```bash
mkdir -p ~/.ssh/cm
```

Add (replace `YOUR_NETID`):

```
Host torch
  Hostname login.torch.hpc.nyu.edu
  User YOUR_NETID
  StrictHostKeyChecking no
  ServerAliveInterval 60
  ForwardAgent yes
  UserKnownHostsFile /dev/null
  LogLevel ERROR
  ControlMaster auto
  ControlPersist 8h
  ControlPath ~/.ssh/cm/%C
  ServerAliveInterval 60
  ServerAliveCountMax 3
```

| Option | Purpose |
|--------|--------|
| `ControlMaster auto` | Reuse an existing SSH connection |
| `ControlPersist 8h` | Keep the shared connection alive after the last session |
| `ControlPath ~/.ssh/cm/%C` | Per-host control socket under `~/.ssh/cm/` |
| `ServerAliveInterval` / `CountMax` | Keep-alives so idle firewalls don’t drop the mux |

## 2. Install & run `ignite`

```bash
cd path/to/Stable_NYU_HPC
chmod +x ignite
ln -sf "$(pwd)/ignite" /usr/local/bin/ignite   # optional
ignite
```

**What happens:**

1. `ssh -MNf torch` starts and prints a device-code PIN.
2. Browser opens; PIN is copied to the clipboard.
3. You paste the PIN at https://login.microsoft.com/device and finish Microsoft login.
4. Return to the terminal and press **Enter**.
5. Script probes `ssh -O check`; on success you see `SSH session ready`.

Verbosity: `ignite quiet` · `ignite` (default) · `ignite vv`

Password + Duo hosts: see [`NYUSHHPC.md`](./NYUSHHPC.md) and `ignite-sh`.

## 3. Optional: IDE Remote-SSH servers on scratch

**Skip this section** if you only use `ssh` / `scp` / `rsync` / Jupyter over SSH — `ignite` alone is enough.

Torch **home** has a tight inode quota; IDE servers unpack many small files. Put them on **scratch** instead.

After `ignite` succeeds:

```bash
# Cursor only (recommended on Torch)
./preinstall-cursor-torch.sh torch

# Or both editors / other methods
./preinstall-remote-server.sh torch
./preinstall-remote-server.sh --editor vscode torch
./preinstall-remote-server.sh --method remote torch    # curl on login node
./preinstall-remote-server.sh --method symlink torch   # symlink home → scratch only
```

**Every Cursor desktop update** ships a new remote-server commit. On Torch scratch, Cursor’s own extract often stalls on a lock (`Could not acquire lock`). Fix: run `./preinstall-cursor-torch.sh torch` **before** reconnecting Remote-SSH (do not open multiple Remote windows during extract).

Pin commits if auto-detect fails: `CURSOR_COMMIT=...` / `VSCODE_COMMIT=...`.

Suggested settings (replace NetID / only keep the editor you use):

```json
{
  "remote.SSH.serverInstallPath": {
    "torch": "/scratch/YOUR_NETID/cursor-server"
  },
  "remote.SSH.localServerDownload": "auto",
  "remote.SSH.connectTimeout": 600
}
```

For VS Code use `/scratch/YOUR_NETID/vscode-server` as the install path value.

## 4. Using the connection

Once `ignite` reports ready, anything using Host `torch` reuses the mux until it expires:

- Plain SSH, `scp`, `rsync`, Git over SSH
- Cursor / VS Code Remote-SSH (if you set those up)

## FAQ

**Q:** Terminal says ready but the browser says invalid PIN?  
**A:** Usually a mismatched / stale PIN session. Close extra Microsoft tabs, run one `ignite`, paste that PIN only, finish auth, then press Enter.

**Q:** `SSH exited before PIN prompt`?  
**A:** VPN/network, Torch rate-limiting new SSH, or a leftover ControlMaster. Check VPN, `ssh -O exit torch`, wait a bit, retry once.

## Acknowledgements

- Based on **[Ignition](https://github.com/wenboluu/Ignition)** ([wenboluu/Ignition](https://github.com/wenboluu/Ignition.git)).
- Expect-based device-code extraction inspired by [JosiahWayne/torch-login](https://github.com/JosiahWayne/torch-login).
- Thanks to the NYU HPC team for Torch.
