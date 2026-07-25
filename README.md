# ReviewPC Bootstrap Scripts — Linux

A modular set of Bash scripts to automate Linux PC setup for reviews and deployment. Supports **Fedora** and **Ubuntu** (and their derivatives) from a single codebase — the distro is auto-detected at runtime. Linux counterpart to [bootstrap_windows_11_pc](https://github.com/alexziskind1/bootstrap_windows_11_pc).

## Architecture

Shared logic lives in the top-level scripts; everything distro-specific is isolated in a small adapter:

```
├── reviewpc-runall.sh        # One-click entry point (detects distro automatically)
├── common-utils.sh           # Logging, idempotency checks, adapter loading
├── distro/
│   ├── fedora.sh             # dnf layer: RPM Fusion, ffmpeg swap, ABRT, firewalld
│   └── ubuntu.sh             # apt layer: package-name map, apport, unattended-upgrades, ufw
├── reviewpc-cleanup.sh       # Debloat pass
├── reviewpc-install.sh       # App installs (~80% shared)
└── reviewpc-finish-setup.sh  # GNOME config (~100% shared)
```

Adapters implement one interface: `pkg_name`, `native_pkg_installed`, `native_install_pkg`, `native_remove_pkg`, `distro_setup_repos`, plus a handful of `distro_*` hooks for genuine edge cases (ffmpeg, uv, .NET, Vulkan deps, crash reporters, firewall). All decision logic stays in the shared scripts.

## Usage

### Quick Start
```bash
git clone https://github.com/alexziskind1/bootstrap_linux_pc.git
cd bootstrap_linux_pc
./reviewpc-runall.sh
```

Or download the zip, unzip, then:
```bash
cd bootstrap_linux_pc-main
bash reviewpc-runall.sh
```

Run as a **regular user** (not root/sudo) — the scripts request sudo internally where needed. Desktop settings (favorites, notifications, default browser) require your user session.

### Individual Scripts
Each component can be run independently:
```bash
./reviewpc-cleanup.sh
./reviewpc-install.sh --git-user-name "Your Name" --git-user-email "you@example.com"
./reviewpc-finish-setup.sh
```

All steps are **idempotent** — anything already installed or configured is detected and skipped, so re-running is safe and fast.

## Features

### What Gets Cleaned Up
- Unwanted preinstalled apps (per-distro list in `distro/*.sh`) + LibreOffice
- Crash-report prompts: ABRT (Fedora) / apport (Ubuntu)
- Background update downloads: GNOME Software auto-download off; unattended-upgrades disabled on Ubuntu (keeps benchmark runs clean)

### What Gets Installed
- **Repos:** Fedora → RPM Fusion (free + nonfree); Ubuntu → universe/multiverse + Flatpak. Both → Flathub, Google Chrome repo, VS Code repo
- **Browsers:** Google Chrome
- **Dev Tools:** Git, GitHub CLI (gh), git-lfs, VS Code, Python 3, Node.js, uv, Miniconda3, .NET SDK, cmake/gcc toolchain
- **AI Tools:** LM Studio (AppImage), Ollama, Claude Code, **llama.cpp** (built from source — see below)
- **Benchmarking:** llama-benchy, llama-benchy-viz-tui, llama-benchy-viz-web, fio (disk), iperf3 (network)
- **Monitoring:** CPU-X (CPU-Z equivalent), lm_sensors, btop, Mission Center (HWMonitor equivalent), KDiskMark (CrystalDiskMark equivalent)
- **Media/Utilities:** VLC, OBS Studio, ffmpeg (full build — swapped from ffmpeg-free on Fedora), GNOME Tweaks, htop

### llama.cpp Hardware Detection
llama.cpp is built from source with the backend chosen automatically:

| Detected hardware | Backend |
|---|---|
| NVIDIA GPU with CUDA toolkit installed | CUDA (`-DGGML_CUDA=ON`) |
| NVIDIA (no CUDA toolkit), AMD, or Intel GPU | Vulkan (`-DGGML_VULKAN=ON`) |
| No supported GPU | CPU |

Binaries (`llama-cli`, `llama-server`, `llama-bench`) are installed to `~/.local/bin`. Source stays in `~/src/llama.cpp` for rebuilds.

### llama-benchy + Visualization
- `llama-benchy` is installed from PyPI via `uv tool install`
- `llama-benchy-viz-tui` and `llama-benchy-viz-web` are cloned side by side into `~/src` (the web viz depends on the TUI's layers) and installed via `uv tool install`

Example run:
```bash
llama-benchy --emit-progress - --base-url http://localhost:8080/v1 --model <MODEL> | llama-benchy-viz-tui
```

### What Gets Configured
- Chrome set as default browser
- Dash favorites: System Monitor, VS Code, Terminal, Chrome, Files
- Notification banners disabled
- SSH enabled for remote access (`sshd`/`ssh` started + firewall opened; connect command printed at the end)
- Performance power profile; auto-suspend, screen blanking, and dimming disabled
- Developer tweaks (compiler toolchain, raised inotify watch limit)
- Git user name/email

## Adding Another Distro

Copy `distro/fedora.sh` or `distro/ubuntu.sh`, implement the same functions for the new package manager, and add a case to `init_distro` in `common-utils.sh`. The shared scripts need no changes.

## Logging
All scripts create timestamped logs in the `logs/` subdirectory for troubleshooting.

## Requirements
- Fedora Workstation or Ubuntu Desktop (GNOME) — tested on recent releases
- A regular user account with sudo privileges
- Internet connection
