#!/usr/bin/env bash
#
# reviewpc-finish-setup.sh
# Final configuration (shared across distros — both target GNOME):
#  - Chrome as default browser
#  - GNOME dash favorites: System Monitor, VS Code, Terminal, Chrome, Files
#  - Notifications off
#  - Performance power profile, no auto-suspend, no screen blanking
#  - Dev tweaks (compiler toolchain group, inotify watches)
#  - SSH enabled for remote access
#  - Git config fallback
#
# Usage: ./reviewpc-finish-setup.sh [--git-user-name NAME] [--git-user-email EMAIL]
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PREFIX="Finish"
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
start_logging "Finish"

log "Starting finisher..."

# ---------------------------
# 1) Chrome as default browser
# ---------------------------
if have_cmd xdg-settings; then
  current_browser="$(xdg-settings get default-web-browser 2>/dev/null || true)"
  if [[ "$current_browser" == "google-chrome.desktop" ]]; then
    ok "Chrome already the default browser. Skipping."
  elif [[ -f /usr/share/applications/google-chrome.desktop ]]; then
    log "Setting Chrome as default browser..."
    xdg-settings set default-web-browser google-chrome.desktop \
      && ok "Chrome set as default browser." \
      || warn "Could not set default browser."
  else
    warn "Chrome desktop entry not found; run reviewpc-install.sh first."
  fi
fi

# ---------------------------
# 2) GNOME dash favorites ("taskbar pins")
# ---------------------------
if have_cmd gsettings; then
  log "Applying dash favorites..."

  desktop_entry_exists() {
    [[ -f "/usr/share/applications/$1" || -f "$HOME/.local/share/applications/$1" ]]
  }

  # Candidates in pin order; first existing variant of each wins
  FAVORITES=()
  for candidates in \
    "org.gnome.SystemMonitor.desktop gnome-system-monitor.desktop io.missioncenter.MissionCenter.desktop" \
    "code.desktop" \
    "org.gnome.Ptyxis.desktop org.gnome.Terminal.desktop org.gnome.Console.desktop" \
    "google-chrome.desktop" \
    "org.gnome.Nautilus.desktop"; do
    for d in $candidates; do
      if desktop_entry_exists "$d"; then
        FAVORITES+=("'$d'")
        break
      fi
    done
  done

  if [[ ${#FAVORITES[@]} -gt 0 ]]; then
    fav_list="[$(IFS=, ; echo "${FAVORITES[*]}")]"
    gsettings set org.gnome.shell favorite-apps "$fav_list" \
      && ok "Dash favorites set: $fav_list" \
      || warn "Could not set dash favorites."
  else
    warn "No pin targets found. Run after apps are installed."
  fi
else
  warn "gsettings not available (not GNOME?). Skipping favorites."
fi

# ---------------------------
# 3) Disable notifications
# ---------------------------
if have_cmd gsettings; then
  log "Disabling notification banners..."
  gsettings set org.gnome.desktop.notifications show-banners false \
    && ok "Notification banners disabled." \
    || warn "Could not disable notifications."
fi

# ---------------------------
# 4) Power tweaks (Ultimate Performance equivalent)
# ---------------------------
log "Applying power tweaks..."

if have_cmd powerprofilesctl; then
  if powerprofilesctl list 2>/dev/null | grep -q performance; then
    powerprofilesctl set performance \
      && ok "Performance power profile activated." \
      || warn "Could not set performance profile."
  else
    warn "Performance profile not offered on this hardware. Skipping."
  fi
fi

if have_cmd gsettings; then
  # No screen blanking, no auto-suspend — a review/benchmark machine
  # should never sleep mid-run.
  gsettings set org.gnome.desktop.session idle-delay 0
  gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
  gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing'
  gsettings set org.gnome.settings-daemon.plugins.power idle-dim false
  ok "Screen blanking and auto-suspend disabled."
fi

# ---------------------------
# 5) Dev tweaks
# ---------------------------
log "Applying dev tweaks..."

distro_install_dev_group

SYSCTL_FILE="/etc/sysctl.d/90-reviewpc.conf"
if [[ -f "$SYSCTL_FILE" ]]; then
  ok "inotify limits already configured. Skipping."
else
  log "Raising inotify watch limits..."
  sudo tee "$SYSCTL_FILE" >/dev/null <<'EOF'
fs.inotify.max_user_watches=524288
EOF
  sudo sysctl -p "$SYSCTL_FILE" >/dev/null && ok "inotify limits raised."
fi

# ---------------------------
# 6) Enable SSH for remote access
# ---------------------------
log "Enabling SSH remote access..."

install_pkg openssh-server

if systemctl is-active "$SSH_SERVICE" &>/dev/null; then
  ok "$SSH_SERVICE already running."
else
  sudo systemctl enable --now "$SSH_SERVICE" \
    && ok "$SSH_SERVICE enabled and started." \
    || warn "Could not enable $SSH_SERVICE."
fi

distro_open_ssh_firewall

SSH_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
if [[ -n "$SSH_IP" ]]; then
  ok "SSH ready: ssh $USER@$SSH_IP"
fi

# ---------------------------
# 7) Git config fallback
# ---------------------------
if [[ -n "$GIT_USER_NAME" && -n "$GIT_USER_EMAIL" ]] && have_cmd git; then
  current_name="$(git config --global user.name 2>/dev/null || true)"
  current_email="$(git config --global user.email 2>/dev/null || true)"
  if [[ -z "$current_name" || -z "$current_email" ]]; then
    log "Configuring git (fallback)..."
    set_reviewpc_git_config "$GIT_USER_NAME" "$GIT_USER_EMAIL"
  else
    ok "Git already configured: $current_name <$current_email>"
  fi
fi

ok "Done. Log out/in if dash favorites or default apps don't show immediately."
