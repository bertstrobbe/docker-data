#!/bin/bash
#
# Aparte backup van Dawarich (los van de smarthome-backup).
# Maakt een logische dump van de PostgreSQL/PostGIS-database via pg_dump
# terwijl de container gewoon blijft draaien (online-consistent), en uploadt
# die gecomprimeerd naar Google Drive met 90 dagen retentie.
#
set -euo pipefail

# Als root draaien (zoals backup_actual_to_gdrive.sh); docker/rclone als bert.
if [ "$EUID" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

# Configuratie
CONTAINER="dawarich_db"
ENV_FILE="/data/dockerdata/dawarich/.env"
DB_NAME="dawarich"
DB_USER="postgres"
GDRIVE_REMOTE="gdrive:Backups/Dawarich"
RETENTION_DAYS=90
BACKUP_NAME="dawarich_$(date +%Y%m%d).sql.gz"
OUT="/tmp/$BACKUP_NAME"

cleanup() { rm -f "$OUT" 2>/dev/null || true; }
trap cleanup EXIT

# DB-wachtwoord uit het .env van de stack halen (zelfde waarde als de app gebruikt).
DB_PASS="$(grep -E '^POSTGRES_PASSWORD=' "$ENV_FILE" | cut -d= -f2-)"
if [ -z "$DB_PASS" ]; then
    echo "FOUT: POSTGRES_PASSWORD niet gevonden in $ENV_FILE" >&2
    exit 1
fi

echo "Dump maken van database '$DB_NAME' uit $CONTAINER..."

# pg_dump via TCP (-h 127.0.0.1) met PGPASSWORD, gecomprimeerd naar de host.
# Plain-SQL formaat -> herstelbaar met: gunzip -c <file> | docker exec -i dawarich_db psql -U postgres -d dawarich
sudo -u bert docker exec -e PGPASSWORD="$DB_PASS" "$CONTAINER" \
    pg_dump -U "$DB_USER" -h 127.0.0.1 -d "$DB_NAME" --clean --if-exists \
    | gzip > "$OUT"

# Sanity check: niet-lege dump.
if [ ! -s "$OUT" ]; then
    echo "FOUT: dump is leeg" >&2
    exit 1
fi
chown "$(id -u bert):$(id -g bert)" "$OUT"
echo "Backup gemaakt: $OUT ($(du -h "$OUT" | cut -f1))"

# Uploaden met rclone (rclone-config is gebruikersspecifiek voor bert).
echo "Uploaden naar $GDRIVE_REMOTE..."
sudo -u bert rclone copy "$OUT" "$GDRIVE_REMOTE"

# Oude backups opruimen.
sudo -u bert rclone delete "$GDRIVE_REMOTE" --min-age "${RETENTION_DAYS}d" --include "dawarich_*.sql.gz"

echo "Klaar."
