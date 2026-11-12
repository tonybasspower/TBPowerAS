#!/bin/bash
# Installazione isolata TBPower AS. Da eseguire personalmente con sudo.
set -euo pipefail
cd "$(dirname "$0")"
die() { echo "ERRORE: $*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "eseguire sudo ./install-helper.sh 93"
[[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null)" == 1 ]] || die "solo Apple Silicon"
USER_NAME="${SUDO_USER:-}"
[[ "$USER_NAME" =~ ^[a-z_][a-z0-9_.-]*$ && "$USER_NAME" != root ]] || die "avviare da un utente normale con sudo"
LIMIT="${1:-93}"
[[ "$LIMIT" =~ ^[0-9]{2,3}$ ]] && ((LIMIT >= 50 && LIMIT <= 100)) || die "limite 50–100"
DIR="/Library/Application Support/TBPowerAS"
HELPER="$DIR/tbpower-as-helper"
LABEL="com.tbp.tbpower-as.chargelimit"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
[[ -x build/tbpower-as-helper ]] || die "prima eseguire ./build-app.sh senza sudo"
/usr/bin/lipo build/tbpower-as-helper -verify_arch arm64 || die "helper non arm64"
install -d -o root -g wheel -m 755 "$DIR"
# Stop only OUR daemon before replacing its executable/config.
launchctl bootout "system/$LABEL" 2>/dev/null || true
install -o root -g wheel -m 755 build/tbpower-as-helper "$HELPER"
install -o root -g wheel -m 755 Support/uninstall.sh "$DIR/uninstall.sh"
"$HELPER" charge-supported || die "SMC carica non supportato; nessuna regola sudoers installata"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
printf '%s\n' "$USER_NAME ALL=(root) NOPASSWD: /Library/Application\\ Support/TBPowerAS/tbpower-as-helper" > "$TMP"
visudo -cf "$TMP" >/dev/null || die "regola sudoers invalida"
install -o root -g wheel -m 440 "$TMP" /etc/sudoers.d/tbpower-as
if [[ ! -f "$DIR/config" ]]; then "$HELPER" charge-limit "$LIMIT"; fi
# Safe reset before the daemon applies the configured threshold.
"$HELPER" reapply
install -o root -g wheel -m 644 "Support/$LABEL.plist" "$PLIST"
launchctl bootstrap system "$PLIST"
if [[ -d "build/TBPower AS.app" ]]; then
  ditto "build/TBPower AS.app" "/Applications/TBPower AS.app"
  chown -R "$USER_NAME":admin "/Applications/TBPower AS.app"
fi
echo 'Helper AS installato. Apri: open "/Applications/TBPower AS.app"'
echo "Recupero carica: sudo '$HELPER' charge-pause 0"
echo "Disinstalla: sudo '$DIR/uninstall.sh'"
