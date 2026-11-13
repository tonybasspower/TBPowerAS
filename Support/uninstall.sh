#!/bin/bash
# TBPower AS — disinstallazione / uninstall (Apple Silicon).
#   sudo "/Library/Application Support/TBPowerAS/uninstall.sh"
#   (oppure, dalla cartella del repo: sudo ./Support/uninstall.sh)
# Riabilita la carica, ripristina stop/timer, poi rimuove app, helper,
# regola sudoers e LaunchDaemon di TBPower AS. Non tocca altre app.
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo / eseguire con sudo: sudo \"$0\"" >&2; exit 1; }

DIR="/Library/Application Support/TBPowerAS"
HELPER="$DIR/tbpower-as-helper"
LABEL="com.tbp.tbpower-as.chargelimit"
APP="/Applications/TBPower AS.app"

echo "==> Quit TBPower AS"
pkill -x TBPowerAS 2>/dev/null || true
sleep 1

echo "==> LaunchDaemon"
launchctl bootout "system/$LABEL" 2>/dev/null || true
rm -f "/Library/LaunchDaemons/$LABEL.plist"
rm -f /var/log/tbpower-as-chargelimit.log

if [[ -x "$HELPER" ]]; then
  echo "==> Restore defaults (charging enabled, sleep, Amphetamine off)"
  "$HELPER" charge-pause 0 2>/dev/null || true
  "$HELPER" nosleep 0 2>/dev/null || true
  "$HELPER" amphetamine 0 2>/dev/null || true
fi

echo "==> sudoers"
rm -f /etc/sudoers.d/tbpower-as

echo "==> Files"
# Avvio al login su macOS 11/12 (LaunchAgent dell'utente che ha lanciato sudo).
if [ -n "${SUDO_USER:-}" ]; then
  rm -f "$(eval echo "~$SUDO_USER")/Library/LaunchAgents/com.tbp.tbpower-as.login.plist"
fi
rm -rf "$APP"
# La cartella di supporto per ultima (può contenere questo script).
rm -rf "$DIR"

echo "TBPower AS removed / rimosso. Low Power Mode is left as is: reset with"
echo "  sudo pmset -a lowpowermode 0"
