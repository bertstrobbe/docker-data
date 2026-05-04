#!/bin/bash

# Check if running as root, if not, re-run with sudo
if [ "$EUID" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

# Configuration
STOP_CONTAINERS=false  # Set to true to stop containers during backup (consistent but with downtime)

# Bestemmingen
SOURCE_DIR="/home/bert/docker-data"
BACKUP_NAME="smarthome_full_$(date +%Y%m%d).tar.gz"
GDRIVE_REMOTE="gdrive:Backups/SmartHome"

# directories to include in the backup
BACKUP_PATHS=("/home/bert/docker-data" "/data/dockerdata")

echo "Git commit $SOURCE_DIR naar github..."

# Run git commands as the original user to use their SSH keys
COMMIT_MSG="Automatische backup op $(date +'%Y-%m-%d %H:%M')"
sudo -u bert git -C "$SOURCE_DIR" add .
sudo -u bert git -C "$SOURCE_DIR" commit -m "$COMMIT_MSG" || true
sudo -u bert git -C "$SOURCE_DIR" push origin main

if [ "$STOP_CONTAINERS" = true ]; then
    echo "Stopping Docker containers for consistent backup..."
    cd "$SOURCE_DIR"
    sudo -u bert docker compose down
    trap 'cd "$SOURCE_DIR" && sudo -u bert docker compose up -d' EXIT
fi

echo "Start backup van ${BACKUP_PATHS[*]} naar $GDRIVE_REMOTE..."

# 1. Inpakken
tar --exclude='*.log' --exclude='*.db-shm' --exclude='*.db-wal' -czf "/tmp/$BACKUP_NAME" -C /home/bert docker-data -C / data/dockerdata
chown "$(id -u bert):$(id -g bert)" "/tmp/$BACKUP_NAME"

# 2. Containers herstarten
if [ "$STOP_CONTAINERS" = true ]; then
    echo "Restarting Docker containers..."
    cd "$SOURCE_DIR"
    sudo -u bert docker compose up -d
    trap - EXIT
    echo "Docker containers restarted"
fi

# 3. Uploaden met rclone (run as user since rclone config is user-specific)
sudo -u bert rclone copy "/tmp/$BACKUP_NAME" "$GDRIVE_REMOTE"
rm "/tmp/$BACKUP_NAME"

sudo -u bert rclone delete "$GDRIVE_REMOTE" --min-age 15d --include "smarthome_full_*.tar.gz"