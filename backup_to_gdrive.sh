#!/bin/bash

# Bestemmingen
SOURCE_DIR="/home/bert/docker-data"
BACKUP_NAME="smarthome_full_$(date +%Y%m%d).tar.gz"
GDRIVE_REMOTE="gdrive:Backups/SmartHome"

echo "Git commit $SOURCE_DIR naar github..."

cd $SOURCE_DIR
git add .
git commit -m "Automatische backup op $(date +'%Y-%m-%d %H:%M')"
git push origin main
echo "Start backup van $SOURCE_DIR naar $REMOTE..."

# 1. Inpakken 
tar --exclude='*.log' --exclude='*.db-shm' --exclude='*.db-wal' -czf /tmp/$BACKUP_NAME .

# 3. Uploaden met rclone
rclone copy /tmp/$BACKUP_NAME $GDRIVE_REMOTE
rm /tmp/$BACKUP_NAME

rclone delete $GDRIVE_REMOTE --min-age 15d