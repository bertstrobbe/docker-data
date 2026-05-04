#!/bin/bash

# Check if running as root, if not, re-run with sudo
if [ "$EUID" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

# Bestemmingen
SOURCE_DIR="/home/bert/docker-data"
BACKUP_NAME="smarthome_full_$(date +%Y%m%d).tar.gz"
GDRIVE_REMOTE="gdrive:Backups/SmartHome"

# directories to include in the backup
BACKUP_PATHS=("/home/bert/docker-data" "/data/dockerdata")

echo "Git commit $SOURCE_DIR naar github..."

cd "$SOURCE_DIR"
git add .
git commit -m "Automatische backup op $(date +'%Y-%m-%d %H:%M')"
git push origin main
echo "Start backup van ${BACKUP_PATHS[*]} naar $GDRIVE_REMOTE..."

# 1. Inpakken
cd /
tar --exclude='*.log' --exclude='*.db-shm' --exclude='*.db-wal' -czf /tmp/$BACKUP_NAME -C /home/bert docker-data -C / data/dockerdata
chown "$(id -u bert):$(id -g bert)" /tmp/$BACKUP_NAME

# 3. Uploaden met rclone
rclone copy /tmp/$BACKUP_NAME $GDRIVE_REMOTE
rm /tmp/$BACKUP_NAME

rclone delete $GDRIVE_REMOTE --min-age 15d