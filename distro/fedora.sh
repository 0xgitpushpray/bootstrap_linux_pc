#!/usr/bin/env bash
#
# distro/fedora.sh
# Fedora adapter: package-manager layer + Fedora-specific edge cases.
# Sourced by common-utils.sh — do not run directly.
#

SSH_SERVICE="sshd"

CLEANUP_PKGS=(
  gnome-tour
  gnome-maps
  gnome-weather
  gnome-contacts
  simple-scan
  rhythmbox
  mediawriter
)

# Canonical package names are the Fedora names
pkg_name() { echo "$1"; }

native_pkg_installed() { rpm -q "$1" &>/dev/null; }
native_install_pkg()   { sudo dnf install -y "$1"; }
native_remove_pkg()    { sudo dnf remove -y "$1"; }

distro_setup_repos() {
  local fedora_ver
  fedora_ver="$(rpm -E %fedora)"

  if ! native_pkg_installed rpmfusion-free-release; then
    log "Enabling RPM Fusion (free)..."
    sudo dnf install -y "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_ver}.noarch.rpm"
  else
    ok "RPM Fusion (free) already enabled. Skipping."
  fi

  if ! native_pkg_installed rpmfusion-nonfree-release; then
    log "Enabling RPM Fusion (nonfree)..."
    sudo dnf install -y "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_ver}.noarch.rpm"
  else
    ok "RPM Fusion (nonfree) already enabled. Skipping."
  fi

  if [[ ! -f /etc/yum.repos.d/google-chrome.repo ]]; then
    log "Adding Google Chrome repository..."
    sudo tee /etc/yum.repos.d/google-chrome.repo >/dev/null <<'EOF'
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF
  else
    ok "Google Chrome repository already configured. Skipping."
  fi

  if [[ ! -f /etc/yum.repos.d/vscode.repo ]]; then
    log "Adding VS Code repository..."
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
    sudo tee /etc/yum.repos.d/vscode.repo >/dev/null <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
  else
    ok "VS Code repository already configured. Skipping."
  fi

  if ! grep -q '^max_parallel_downloads' /etc/dnf/dnf.conf; then
    log "Enabling parallel dnf downloads..."
    echo 'max_parallel_downloads=10' | sudo tee -a /etc/dnf/dnf.conf >/dev/null
  fi
}

distro_install_vulkan_deps() {
  install_pkg vulkan-headers
  install_pkg vulkan-loader-devel
  install_pkg glslc
  install_pkg mesa-vulkan-drivers
}

distro_install_uv() {
  install_pkg uv
}

# Fedora preinstalls the codec-limited ffmpeg-free; swap for the full build
distro_install_ffmpeg() {
  if native_pkg_installed ffmpeg; then
    ok "ffmpeg already installed. Skipping."
    return 0
  fi
  log "Installing ffmpeg (full RPM Fusion build)..."
  if native_pkg_installed ffmpeg-free; then
    sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing \
      && ok "ffmpeg installed (swapped from ffmpeg-free)." \
      || warn "ffmpeg swap failed. Continuing."
  else
    sudo dnf install -y ffmpeg \
      && ok "ffmpeg installed." \
      || warn "ffmpeg installation failed. Continuing."
  fi
}

distro_install_dotnet() {
  if have_cmd dotnet; then
    ok ".NET SDK already installed. Skipping."
    return 0
  fi
  log "Installing .NET SDK..."
  sudo dnf install -y dotnet-sdk-10.0 || sudo dnf install -y dotnet-sdk-9.0 \
    && ok ".NET SDK installed." \
    || warn ".NET SDK installation failed. Continuing."
}

distro_install_dev_group() {
  if dnf group info development-tools 2>/dev/null | grep -qi 'installed'; then
    ok "development-tools group already installed. Skipping."
  else
    log "Installing development-tools group..."
    sudo dnf group install -y development-tools \
      && ok "development-tools group installed." \
      || warn "Could not install development-tools group."
  fi
}

distro_cleanup_extras() {
  log "Disabling ABRT crash-report services..."
  local unit
  for unit in abrtd.service abrt-journal-core.service abrt-oops.service abrt-xorg.service; do
    if systemctl list-unit-files "$unit" &>/dev/null && systemctl is-enabled "$unit" &>/dev/null; then
      sudo systemctl disable --now "$unit" && ok "$unit disabled." || warn "Could not disable $unit."
    else
      ok "$unit not present/enabled. Skipping."
    fi
  done
}

distro_remove_libreoffice() {
  if rpm -qa 'libreoffice*' | grep -q .; then
    log "Removing LibreOffice suite..."
    sudo dnf remove -y 'libreoffice*' && ok "LibreOffice removed." || warn "Failed to remove LibreOffice."
  else
    ok "LibreOffice not installed. Skipping."
  fi
}

distro_open_ssh_firewall() {
  if have_cmd firewall-cmd && systemctl is-active firewalld &>/dev/null; then
    if sudo firewall-cmd --query-service=ssh &>/dev/null; then
      ok "Firewall already allows SSH."
    else
      sudo firewall-cmd --add-service=ssh --permanent >/dev/null \
        && sudo firewall-cmd --reload >/dev/null \
        && ok "Firewall opened for SSH." \
        || warn "Could not open firewall for SSH."
    fi
  fi
}
