#!/usr/bin/env bash
#
# distro/ubuntu.sh
# Ubuntu adapter: package-manager layer + Ubuntu-specific edge cases.
# Sourced by common-utils.sh — do not run directly.
#

SSH_SERVICE="ssh"

CLEANUP_PKGS=(
  aisleriot
  gnome-mahjongg
  gnome-mines
  gnome-sudoku
  rhythmbox
  shotwell
  simple-scan
  transmission-gtk
)

export DEBIAN_FRONTEND=noninteractive

# Map canonical (Fedora-style) names to Ubuntu package names
pkg_name() {
  case "$1" in
    gcc-c++)       echo "g++" ;;
    libcurl-devel) echo "libcurl4-openssl-dev" ;;
    lm_sensors)    echo "lm-sensors" ;;
    fuse)          echo "libfuse2" ;;   # AppImage support (libfuse2t64 on 24.04+, aliased)
    *)             echo "$1" ;;
  esac
}

native_pkg_installed() { dpkg -s "$1" &>/dev/null; }
native_install_pkg()   { sudo apt-get install -y "$1"; }
native_remove_pkg()    { sudo apt-get remove -y "$1"; }

distro_setup_repos() {
  # universe/multiverse are usually on for Desktop, but make sure
  log "Ensuring universe and multiverse repositories are enabled..."
  sudo add-apt-repository -y universe >/dev/null 2>&1 || true
  sudo add-apt-repository -y multiverse >/dev/null 2>&1 || true

  if [[ ! -f /etc/apt/sources.list.d/google-chrome.list ]]; then
    log "Adding Google Chrome repository..."
    curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
      | sudo gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" \
      | sudo tee /etc/apt/sources.list.d/google-chrome.list >/dev/null
  else
    ok "Google Chrome repository already configured. Skipping."
  fi

  if [[ ! -f /etc/apt/sources.list.d/vscode.list ]]; then
    log "Adding VS Code repository..."
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
      | sudo gpg --dearmor -o /usr/share/keyrings/microsoft.gpg
    echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
      | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
  else
    ok "VS Code repository already configured. Skipping."
  fi

  log "Updating apt package lists..."
  sudo apt-get update

  # Ubuntu doesn't preinstall Flatpak; needed for KDiskMark/Mission Center
  install_pkg flatpak
}

distro_install_vulkan_deps() {
  install_pkg libvulkan-dev
  install_pkg glslc
  install_pkg glslang-tools
  install_pkg mesa-vulkan-drivers
}

# uv isn't in Ubuntu's repos; use the official installer (-> ~/.local/bin)
distro_install_uv() {
  if have_cmd uv; then
    ok "uv already installed. Skipping."
    return 0
  fi
  log "Installing uv via official installer..."
  curl -LsSf https://astral.sh/uv/install.sh | sh \
    && ok "uv installed." \
    || warn "uv installation failed. Continuing."
}

# Full ffmpeg is in universe/multiverse — no swap dance needed
distro_install_ffmpeg() {
  install_pkg ffmpeg
}

distro_install_dotnet() {
  if have_cmd dotnet; then
    ok ".NET SDK already installed. Skipping."
    return 0
  fi
  log "Installing .NET SDK..."
  sudo apt-get install -y dotnet-sdk-10.0 \
    || sudo apt-get install -y dotnet-sdk-9.0 \
    || sudo apt-get install -y dotnet-sdk-8.0 \
    && ok ".NET SDK installed." \
    || warn ".NET SDK installation failed. Continuing."
}

distro_install_dev_group() {
  install_pkg build-essential
}

distro_cleanup_extras() {
  # apport = Ubuntu's crash reporter
  if systemctl list-unit-files apport.service &>/dev/null; then
    log "Disabling apport crash reporting..."
    sudo systemctl disable --now apport.service 2>/dev/null \
      && ok "apport disabled." \
      || warn "Could not disable apport."
    if [[ -f /etc/default/apport ]]; then
      sudo sed -i 's/^enabled=1/enabled=0/' /etc/default/apport
    fi
  fi

  # unattended-upgrades pollutes benchmark runs with background CPU/disk/network
  if systemctl list-unit-files unattended-upgrades.service &>/dev/null; then
    log "Disabling unattended-upgrades..."
    sudo systemctl disable --now unattended-upgrades.service 2>/dev/null \
      && ok "unattended-upgrades disabled." \
      || warn "Could not disable unattended-upgrades."
  fi
}

distro_remove_libreoffice() {
  if dpkg -l 'libreoffice*' 2>/dev/null | grep -q '^ii'; then
    log "Removing LibreOffice suite..."
    sudo apt-get remove -y 'libreoffice*' && sudo apt-get autoremove -y \
      && ok "LibreOffice removed." \
      || warn "Failed to remove LibreOffice."
  else
    ok "LibreOffice not installed. Skipping."
  fi
}

distro_open_ssh_firewall() {
  # ufw is inactive by default on Ubuntu Desktop; only add a rule if it's on
  if have_cmd ufw && sudo ufw status | grep -q 'Status: active'; then
    if sudo ufw status | grep -qw '22\|OpenSSH'; then
      ok "Firewall already allows SSH."
    else
      sudo ufw allow ssh \
        && ok "Firewall opened for SSH." \
        || warn "Could not open firewall for SSH."
    fi
  else
    ok "ufw inactive — SSH reachable without firewall changes."
  fi
}
