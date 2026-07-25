#!/usr/bin/env bash
#
# reviewpc-cleanup.sh
# Debloat pass (shared across distros; lists and edge cases live in distro/):
#  - Removes preinstalled apps not needed on a review machine
#  - Disables crash-report prompts (ABRT on Fedora, apport on Ubuntu)
#  - Stops background update downloads (keeps benchmarks clean)
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PREFIX="Cleanup"
source "$SCRIPT_DIR/common-utils.sh"

ensure_not_root
init_distro
ensure_sudo
start_logging "Cleanup"

log "Starting cleanup..."

# ---------------------------
# 1) Remove unwanted preinstalled apps (lists defined per-distro)
# ---------------------------
log "Removing unwanted preinstalled applications..."
for pkg in "${CLEANUP_PKGS[@]}"; do
  if native_pkg_installed "$pkg"; then
    log "Removing $pkg..."
    native_remove_pkg "$pkg" && ok "$pkg removed." || warn "Failed to remove $pkg."
  else
    ok "$pkg not installed. Skipping."
  fi
done

distro_remove_libreoffice

# ---------------------------
# 2) Distro-specific cleanup (crash reporters, auto-updates)
# ---------------------------
distro_cleanup_extras

# ---------------------------
# 3) Stop GNOME Software background update downloads
# ---------------------------
if have_cmd gsettings && gsettings get org.gnome.software download-updates &>/dev/null; then
  log "Disabling GNOME Software automatic update downloads..."
  gsettings set org.gnome.software download-updates false \
    && ok "Automatic update downloads disabled." \
    || warn "Could not set GNOME Software preference."
fi

ok "Cleanup completed."
