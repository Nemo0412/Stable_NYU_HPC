# Stable_NYU_HPC

Stable helpers for NYU Torch HPC + Cursor Remote-SSH, based on **[Ignition](https://github.com/wenboluu/Ignition)** by [wenboluu](https://github.com/wenboluu).

> Upstream: https://github.com/wenboluu/Ignition.git  
> This fork: https://github.com/Nemo0412/Stable_NYU_HPC.git

**One command · One Microsoft login · Reuse SSH for hours** — then use the same ControlMaster from terminal, VS Code, or Cursor.

## What changed vs upstream Ignition

Compared to [wenboluu/Ignition](https://github.com/wenboluu/Ignition):

1. **Manual Microsoft device-code auth (no auto Paste + Enter)**  
   Auto keystrokes often race the Microsoft page and trigger `AADSTS165000` (token/cookie mismatch). Flow is now:
   - open the login URL and copy the PIN
   - you paste and finish sign-in in the browser yourself
   - press **Enter** in the terminal when done  
   Upstream’s `ssh -O check` ControlMaster probe is kept.

2. **`preinstall-cursor-torch.sh`**  
   Downloads the Cursor remote server locally, SCPs it to Torch **scratch**, and extracts it so Remote-SSH does not time out on slow home/VAST I/O or hit home inode quotas.

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

## 3. Cursor Remote-SSH on Torch (optional)

Home on Torch has a tight **inode** quota; Cursor Server unpacks many small files. Prefer install under scratch.

Suggested Cursor User settings (adjust paths to your NetID):

```json
{
  "remote.SSH.serverInstallPath": {
    "torch": "/scratch/YOUR_NETID/cursor-server"
  },
  "remote.SSH.localServerDownload": "always",
  "remote.SSH.connectTimeout": 600
}
```

After `ignite` succeeds:

```bash
./preinstall-cursor-torch.sh torch
```

Then connect Cursor → Remote-SSH → **torch**.

## 4. Using the connection

Once `ignite` reports ready, anything using Host `torch` reuses the mux until it expires:

- Cursor / VS Code Remote-SSH
- `ssh torch`, `scp`, `rsync`, etc.

## FAQ

**Q:** Terminal says ready but the browser says invalid PIN?  
**A:** Usually a mismatched / stale PIN session. Close extra Microsoft tabs, run one `ignite`, paste that PIN only, finish auth, then press Enter.

**Q:** `SSH exited before PIN prompt`?  
**A:** VPN/network, Torch rate-limiting new SSH, or a leftover ControlMaster. Check VPN, `ssh -O exit torch`, wait a bit, retry once.

## Acknowledgements

- Based on **[Ignition](https://github.com/wenboluu/Ignition)** ([wenboluu/Ignition](https://github.com/wenboluu/Ignition.git)).
- Expect-based device-code extraction inspired by [JosiahWayne/torch-login](https://github.com/JosiahWayne/torch-login).
- Thanks to the NYU HPC team for Torch.
