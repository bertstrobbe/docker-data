#!/bin/bash
#
# Aparte backup van Portainer (los van de smarthome-backup).
# Gebruikt Portainer's eigen backup-API (POST /api/backup) voor een
# CONSISTENTE snapshot van portainer.db + alle beheerde stack-composes
# + certs/keys, terwijl Portainer gewoon blijft draaien. Uploadt naar
# Google Drive met 90 dagen retentie.
#
# Restore: verse Portainer -> init-scherm -> "Restore from backup" -> upload
# de tar.gz (en geef het wachtwoord op als BACKUP_PASSWORD ingevuld was).
#
set -euo pipefail

# Als root draaien (zoals de andere backup-scripts)
if [ "$EUID" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

# Configuratie
PORTAINER_URL="http://127.0.0.1:9000"                  # lokaal, omzeilt Caddy/TLS
TOKEN_FILE="/home/bert/docker-data/.portainer_token"   # admin API-key (X-API-Key), 1 regel
GDRIVE_REMOTE="gdrive:Backups/Portainer"
RETENTION_DAYS=90
BACKUP_PASSWORD=""                                     # leeg = onversleuteld; vul in om te encrypten (BEWAAR 'M!)
BACKUP_NAME="portainer_$(date +%Y%m%d).tar.gz"
OUT="/tmp/$BACKUP_NAME"

cleanup() { rm -f "$OUT" 2>/dev/null || true; }
trap cleanup EXIT

[ -f "$TOKEN_FILE" ] || { echo "Token-bestand ontbreekt: $TOKEN_FILE" >&2; exit 1; }
API_KEY="$(tr -d '[:space:]' < "$TOKEN_FILE")"
[ -n "$API_KEY" ] || { echo "Token-bestand is leeg: $TOKEN_FILE" >&2; exit 1; }

echo "Consistente Portainer-backup ophalen via API..."

# Portainer's backup-API geeft een tar.gz terug (optioneel met wachtwoord versleuteld).
set +e
http_code=$(curl -sS -o "$OUT" -w '%{http_code}' \
    -X POST "$PORTAINER_URL/api/backup" \
    -H "X-API-Key: $API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"password\":\"$BACKUP_PASSWORD\"}")
rc=$?
set -e
[ $rc -eq 0 ] || { echo "curl netwerkfout (rc=$rc)" >&2; exit 1; }
if [ "$http_code" != "200" ]; then
    echo "Portainer backup-API gaf HTTP $http_code:" >&2
    cat "$OUT" >&2 2>/dev/null || true     # bevat meestal een JSON-foutmelding
    echo >&2
    exit 1
fi

# Verificatie: niet-leeg, en geldige gzip wanneer onversleuteld
[ -s "$OUT" ] || { echo "Backup is leeg!" >&2; exit 1; }
if [ -z "$BACKUP_PASSWORD" ]; then
    gzip -t "$OUT" 2>/dev/null || { echo "Backup is geen geldige gzip!" >&2; exit 1; }
fi

chown "$(id -u bert):$(id -g bert)" "$OUT"
echo "Backup gemaakt: $OUT ($(du -h "$OUT" | cut -f1))"

# Uploaden met rclone (rclone-config is gebruikersspecifiek -> als bert)
echo "Uploaden naar $GDRIVE_REMOTE..."
sudo -u bert rclone copy "$OUT" "$GDRIVE_REMOTE"

# Oude backups opruimen
sudo -u bert rclone delete "$GDRIVE_REMOTE" --min-age "${RETENTION_DAYS}d" --include "portainer_*.tar.gz"

echo "Klaar."
