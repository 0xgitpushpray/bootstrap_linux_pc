#!/usr/bin/env bash
#
# reviewpc-runall.sh
# One-click new-PC setup for reviews (Linux equivalent of ReviewPC.RunAll.ps1).
# Auto-detects the distro (Fedora or Ubuntu) and runs:
#  1) Cleanup (remove unwanted apps, disable crash reports & auto-updates)
#  2) Install applications (native packages, Flatpak, vendor installers, llama.cpp build)
#  3) Finish setup (Chrome default, dash favorites, notifications off, power/dev tweaks, SSH)
#
# Usage:
#   ./reviewpc-runall.sh
#
# Run as a regular user — sudo is requested internally where needed.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PREFIX="RunAll"
source "$SCRIPT_DIR/common-utils.sh"

# Zip downloads lose the executable bit; restore it defensively
chmod +x "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR"/distro/*.sh 2>/dev/null || true

ensure_not_root
init_distro
ensure_sudo
start_logging "RunAll"

log "Starting ReviewPC one-click setup..."

# ---------------------------
# User Input Section
# ---------------------------
log "Collecting user configuration..."
echo
echo "${C_CYAN}Git will be installed as part of this setup. Please provide your Git configuration:${C_RESET}"

GIT_USER_NAME=""
while [[ -z "$GIT_USER_NAME" ]]; do
  read -rp "Enter your Git user name (e.g., 'John Doe'): " GIT_USER_NAME
done

GIT_USER_EMAIL=""
while [[ ! "$GIT_USER_EMAIL" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]; do
  read -rp "Enter your Git email address (e.g., 'john@example.com'): " GIT_USER_EMAIL
done

ok "Git config: Name='$GIT_USER_NAME', Email='$GIT_USER_EMAIL'"
echo

# ---------------------------
# 1) Cleanup
# ---------------------------
run_reviewpc_script "$SCRIPT_DIR/reviewpc-cleanup.sh" "Cleanup" || exit 1

# ---------------------------
# 2) Install applications
# ---------------------------
run_reviewpc_script "$SCRIPT_DIR/reviewpc-install.sh" "App Installation" \
  --git-user-name "$GIT_USER_NAME" --git-user-email "$GIT_USER_EMAIL" || exit 1

# ---------------------------
# 3) Finish setup
# ---------------------------
run_reviewpc_script "$SCRIPT_DIR/reviewpc-finish-setup.sh" "Finish Setup" \
  --git-user-name "$GIT_USER_NAME" --git-user-email "$GIT_USER_EMAIL" || exit 1

# ---------------------------
# 4) Summary
# ---------------------------
echo
ok "✅ All setup steps completed successfully!"
log "Open a new terminal (or log out/in) so PATH changes and dash favorites take effect."
