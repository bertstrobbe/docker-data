#!/bin/bash
#
# Backup van de Garmin/Voedings-rapporten naar Google Drive.
# Compileert dagelijkse rapporten per maand via Docker en kopieert ze als .txt naar gdrive.
#
set -euo pipefail

exec 9>/tmp/.backup_garmin_reports.lock
flock -n 9 || { echo "Vorige Garmin backup draait nog; deze run overgeslagen."; exit 0; }

REPORTS_DIR="/home/bert/garmin_connect_exporter/reports"
MONTHLY_DIR="$REPORTS_DIR/monthly"
GDRIVE_FOLDER_ID="1pxJIklzQHxtBKMBpU37uzvvHGXuNAbV6"

# Maak de monthly map aan als die nog niet bestaat
mkdir -p "$MONTHLY_DIR"

# Run compiler in docker as root to avoid permission denied issues
echo "Compileren van maandrapporten via Docker..."
docker compose -f /home/bert/garmin_connect_exporter/docker-compose.yml run --rm app python -c "
import os, glob
reports_dir = '/app/reports'
monthly_dir = '/app/reports/monthly'
os.makedirs(monthly_dir, exist_ok=True)
files = sorted(glob.glob(os.path.join(reports_dir, '20??-??-??.md')))
months = sorted(list(set(os.path.basename(f)[:7] for f in files)))
for m in months:
    compiled_path = os.path.join(monthly_dir, f'{m}_maandrapport.txt')
    month_files = sorted(glob.glob(os.path.join(reports_dir, f'{m}-??.md')))
    content = ''
    for f in month_files:
        with open(f, 'r') as fh:
            content += fh.read() + '\n\n---\n\n'
    with open(compiled_path, 'w') as fh:
        fh.write(content)
    print(f'Compiled {m}')
"

echo "Garmin rapporten backup gestart $(date '+%Y-%m-%d %H:%M')..."
# Sync enkel de monthly .txt bestanden naar Google Drive (behoudt constant File ID)
rclone copy "$MONTHLY_DIR" gdrive: --drive-root-folder-id "$GDRIVE_FOLDER_ID" \
    --include "*.txt" \
    --transfers 4 \
    --checkers 8 \
    --fast-list \
    --log-level INFO

echo "Klaar $(date '+%Y-%m-%d %H:%M')."
