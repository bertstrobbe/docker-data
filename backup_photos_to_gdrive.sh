#!/bin/bash
#
# Backup van de Immich-foto's naar Google Drive.
# Kopieert /srv/media/photos -> gdrive, ZONDER de herbouwbare mappen
# (thumbs + encoded-video; Immich regenereert die na een restore).
# Gebruikt 'copy' (niet 'sync'): er wordt NOOIT iets uit de backup verwijderd,
# zodat per ongeluk lokaal gewiste foto's in de backup bewaard blijven.
# De 'backups'-map bevat Immich's eigen DB-dumps -> de DB gaat zo mee off-site.
#
# Draait als bert (rclone-config is gebruikersspecifiek). Idempotent/hervatbaar:
# elke run uploadt enkel wat nog ontbreekt. flock voorkomt overlappende runs
# tijdens de (meerdaagse) eerste upload.
#
set -euo pipefail

exec 9>/tmp/.backup_photos_to_gdrive.lock
flock -n 9 || { echo "Vorige fotobackup draait nog; deze run overgeslagen."; exit 0; }

SRC="/srv/media/photos"
GDRIVE_REMOTE="gdrive:Backups/Photos"

echo "Fotobackup gestart $(date '+%Y-%m-%d %H:%M')..."
rclone copy "$SRC" "$GDRIVE_REMOTE" \
    --exclude "/thumbs/**" \
    --exclude "/encoded-video/**" \
    --transfers 4 \
    --checkers 8 \
    --fast-list \
    --stats 5m \
    --log-level INFO

# Off-site retentie van Immich's DB-dumps: 'copy' verwijdert nooit, dus de
# dagelijkse dumps zouden eindeloos opstapelen. Lokaal houdt Immich er 14;
# off-site bewaren we 90 dagen. Scope = ENKEL de backups-submap + het
# dump-bestandspatroon, zodat de foto-library nooit geraakt wordt.
echo "Oude DB-dumps (>90d) in de backup opruimen..."
rclone delete "$GDRIVE_REMOTE/backups" \
    --min-age 90d \
    --include "immich-db-backup-*.sql.gz" 2>/dev/null || true

echo "Klaar $(date '+%Y-%m-%d %H:%M')."
