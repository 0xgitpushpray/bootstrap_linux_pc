#!/usr/bin/env bash
#
# reviewpc-install.sh
# App installer (shared across distros; package layer lives in distro/).
# Every step checks whether the tool is already installed and skips if so.
#
# Usage: ./reviewpc-install.sh [--git-user-name NAME] [--git-user-email EMAIL]
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PREFIX="Install"
source "$SCRIPT_DIR/common-utils.sh"

GIT_USER_NAME=""
GIT_USER_EMAIL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --git-user-name)  GIT_USER_NAME="$2";  shift 2 ;;
    --git-user-email) GIT_USER_EMAIL="$2"; shift 2 ;;
    *) warn "Unknown argument: $1"; shift ;;
  esac
done

ensure_not_root
init_distro
ensure_sudo
start_logging "Install"

# ---------------------------
# 1) Repositories (distro-specific) + Flathub
# ---------------------------
log "Configuring repositories..."
distro_setup_repos

if have_cmd flatpak; then
  if ! flatpak remotes | grep -q flathub; then
    log "Adding Flathub remote..."
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  else
    ok "Flathub remote already configured. Skipping."
  fi
fi

# ---------------------------
# 2) Browsers
# ---------------------------
log "Installing browsers..."
install_pkg google-chrome-stable

# ---------------------------
# 3) Dev tools
# ---------------------------
log "Installing dev tools..."
install_pkg git
install_pkg code
install_pkg python3
install_pkg python3-pip
install_pkg nodejs
install_pkg cmake
install_pkg gcc-c++
install_pkg libcurl-devel   # needed by llama.cpp build
install_pkg gh

install_pkg git-lfs
if have_cmd git-lfs; then
  git lfs install --skip-repo &>/dev/null && ok "git-lfs activated."
fi

distro_install_uv
distro_install_dotnet

# Miniconda3 (official silent installer)
if have_cmd conda || [[ -d "$HOME/miniconda3" ]]; then
  ok "Miniconda already installed. Skipping."
else
  log "Installing Miniconda3..."
  MINICONDA_SH="$(mktemp /tmp/miniconda-XXXX.sh)"
  if curl -fsSL -o "$MINICONDA_SH" "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh" \
      && bash "$MINICONDA_SH" -b -p "$HOME/miniconda3"; then
    "$HOME/miniconda3/bin/conda" init bash >/dev/null
    ok "Miniconda3 installed to ~/miniconda3."
  else
    warn "Miniconda3 installation failed. Continuing."
  fi
  rm -f "$MINICONDA_SH"
fi

# ---------------------------
# 4) AI tooling
# ---------------------------
log "Installing AI tooling..."

# Ollama (official installer; sets up systemd service)
if have_cmd ollama; then
  ok "Ollama already installed. Skipping."
else
  log "Installing Ollama..."
  if curl -fsSL https://ollama.com/install.sh | sh; then
    ok "Ollama installed."
  else
    warn "Ollama installation failed. Continuing."
  fi
fi

# LM Studio (Linux AppImage). Bump this version as needed.
LMSTUDIO_VERSION="0.3.20-4"
LMSTUDIO_URL="https://installers.lmstudio.ai/linux/x64/${LMSTUDIO_VERSION}/LM-Studio-${LMSTUDIO_VERSION}-x64.AppImage"
LMSTUDIO_DIR="$HOME/Applications"
LMSTUDIO_BIN="$LMSTUDIO_DIR/LM-Studio.AppImage"
if [[ -f "$LMSTUDIO_BIN" ]]; then
  ok "LM Studio already installed. Skipping."
else
  log "Installing LM Studio ${LMSTUDIO_VERSION}..."
  install_pkg fuse   # AppImages need FUSE (libfuse2 on Ubuntu)
  mkdir -p "$LMSTUDIO_DIR"
  if curl -fL -o "$LMSTUDIO_BIN" "$LMSTUDIO_URL"; then
    chmod +x "$LMSTUDIO_BIN"
    mkdir -p "$HOME/.local/share/applications"
    cat > "$HOME/.local/share/applications/lm-studio.desktop" <<EOF
[Desktop Entry]
Name=LM Studio
Exec=$LMSTUDIO_BIN
Type=Application
Categories=Development;
Terminal=false
EOF
    ok "LM Studio installed to $LMSTUDIO_BIN."
  else
    warn "LM Studio download failed (check LMSTUDIO_VERSION/URL). Continuing."
  fi
fi

# Claude Code (official native installer; installs to ~/.local/bin)
if have_cmd claude; then
  ok "Claude Code already installed. Skipping."
else
  log "Installing Claude Code..."
  if curl -fsSL https://claude.ai/install.sh | bash; then
    ok "Claude Code installed."
  else
    warn "Claude Code installation failed. Continuing."
  fi
fi

# ---------------------------
# 5) llama.cpp (built from source; backend chosen by hardware)
# ---------------------------
detect_llama_backend() {
  local gpu_info
  gpu_info="$(lspci -nn 2>/dev/null | grep -Ei 'vga|3d|display' || true)"
  if grep -qi nvidia <<<"$gpu_info"; then
    # CUDA only if the toolkit is actually present; otherwise Vulkan works
    # fine on NVIDIA with the proprietary driver.
    if have_cmd nvcc || [[ -d /usr/local/cuda ]]; then
      echo cuda
    else
      echo vulkan
    fi
  elif grep -qiE 'amd|ati|intel' <<<"$gpu_info"; then
    echo vulkan
  else
    echo cpu
  fi
}

if have_cmd llama-server && have_cmd llama-cli; then
  ok "llama.cpp already installed. Skipping."
else
  BACKEND="$(detect_llama_backend)"
  log "Building llama.cpp from source (backend: $BACKEND)..."

  CMAKE_FLAGS=(-DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF)
  case "$BACKEND" in
    cuda)
      CMAKE_FLAGS+=(-DGGML_CUDA=ON)
      ;;
    vulkan)
      log "Installing Vulkan build dependencies..."
      distro_install_vulkan_deps
      CMAKE_FLAGS+=(-DGGML_VULKAN=ON)
      ;;
    cpu)
      log "No supported GPU detected; building CPU-only."
      ;;
  esac

  LLAMA_SRC="$HOME/src/llama.cpp"
  mkdir -p "$HOME/src"
  if [[ -d "$LLAMA_SRC/.git" ]]; then
    log "Updating existing llama.cpp checkout..."
    git -C "$LLAMA_SRC" pull --ff-only || warn "Could not update llama.cpp checkout."
  else
    git clone --depth 1 https://github.com/ggml-org/llama.cpp "$LLAMA_SRC"
  fi

  if cmake -S "$LLAMA_SRC" -B "$LLAMA_SRC/build" "${CMAKE_FLAGS[@]}" \
      && cmake --build "$LLAMA_SRC/build" -j"$(nproc)" \
      && cmake --install "$LLAMA_SRC/build" --prefix "$HOME/.local"; then
    ok "llama.cpp installed to ~/.local/bin (llama-cli, llama-server, llama-bench)."
  else
    warn "llama.cpp build failed. Re-run this script or build manually in $LLAMA_SRC."
  fi

  # Make sure ~/.local/bin is on PATH for future shells
  if ! grep -q '\.local/bin' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    log "Added ~/.local/bin to PATH in ~/.bashrc."
  fi
fi

# ---------------------------
# 6) llama-benchy + visualization tools (all uv-based)
# ---------------------------
log "Installing llama-benchy and viz tools..."

# uv may have just been installed to ~/.local/bin
export PATH="$HOME/.local/bin:$PATH"

if ! have_cmd uv; then
  warn "uv not available; skipping llama-benchy tools."
else
  # llama-benchy from PyPI
  if have_cmd llama-benchy; then
    ok "llama-benchy already installed. Skipping."
  else
    log "Installing llama-benchy via uv..."
    uv tool install llama-benchy \
      && ok "llama-benchy installed." \
      || warn "llama-benchy installation failed. Continuing."
  fi

  # viz-web resolves ../llama-benchy-viz-tui via [tool.uv.sources],
  # so both repos must be cloned side by side before installing.
  VIZ_TUI_SRC="$HOME/src/llama-benchy-viz-tui"
  VIZ_WEB_SRC="$HOME/src/llama-benchy-viz-web"
  mkdir -p "$HOME/src"
  for repo in llama-benchy-viz-tui llama-benchy-viz-web; do
    if [[ -d "$HOME/src/$repo/.git" ]]; then
      log "Updating existing $repo checkout..."
      git -C "$HOME/src/$repo" pull --ff-only || warn "Could not update $repo checkout."
    else
      git clone --depth 1 "https://github.com/alexziskind1/$repo" "$HOME/src/$repo" \
        || warn "Could not clone $repo."
    fi
  done

  if have_cmd llama-benchy-viz-tui; then
    ok "llama-benchy-viz-tui already installed. Skipping."
  elif [[ -d "$VIZ_TUI_SRC" ]]; then
    log "Installing llama-benchy-viz-tui via uv..."
    uv tool install "$VIZ_TUI_SRC" \
      && ok "llama-benchy-viz-tui installed." \
      || warn "llama-benchy-viz-tui installation failed. Continuing."
  fi

  if have_cmd llama-benchy-viz-web; then
    ok "llama-benchy-viz-web already installed. Skipping."
  elif [[ -d "$VIZ_WEB_SRC" && -d "$VIZ_TUI_SRC" ]]; then
    log "Installing llama-benchy-viz-web via uv..."
    uv tool install "$VIZ_WEB_SRC" \
      && ok "llama-benchy-viz-web installed." \
      || warn "llama-benchy-viz-web installation failed. Continuing."
  fi
fi

# ---------------------------
# 7) Benchmarks / monitoring
# ---------------------------
log "Installing benchmarks/monitoring..."
install_pkg cpu-x        # CPU-Z equivalent
install_pkg lm_sensors   # hardware sensors (HWMonitor backend)
install_pkg btop         # resource monitor TUI
install_pkg fio          # disk benchmark CLI
install_pkg iperf3       # network throughput testing
install_flatpak io.github.jonmagon.kdiskmark          # CrystalDiskMark equivalent
install_flatpak io.missioncenter.MissionCenter        # HWMonitor/Task Manager style GUI

# ---------------------------
# 8) Media / productivity / utilities
# ---------------------------
log "Installing media/productivity..."
install_pkg vlc
install_pkg obs-studio
distro_install_ffmpeg

log "Installing utilities..."
install_pkg gnome-tweaks
install_pkg htop

ok "All apps installed."

# ---------------------------
# 9) Git configuration
# ---------------------------
if [[ -n "$GIT_USER_NAME" && -n "$GIT_USER_EMAIL" ]]; then
  set_reviewpc_git_config "$GIT_USER_NAME" "$GIT_USER_EMAIL"
fi
