# Smart Home Docker Data Management

## Project Overview
This directory (`/home/bert/docker-data`) contains maintenance, safeguard, and backup scripts for a Docker-based Smart Home environment.

## Script Execution Conventions
- **Root Privileges**: Scripts generally require root to run. They enforce this by checking `EUID` and re-executing with `sudo` (e.g., `exec sudo "$0" "$@"`).
- **User Context**: Commands interacting with user-specific configurations (`git`, `docker`, and `rclone`) MUST be executed as the user `bert` using `sudo -u bert <command>`.
- **Robustness**: Scripts should use `set -euo pipefail` for strict error handling.
- **Cleanup**: Use `trap cleanup EXIT` to ensure temporary directories, scripts, and archives are reliably removed upon script exit.

## Backup Standards
- **Tooling**: Backups are created using `tar` (for flat files) or database-specific dump tools, then uploaded via `rclone`.
- **Naming Convention**: Archives should be timestamped using the format `[app_name]_$(date +%Y%m%d).[tar.gz|sql.gz]`.
- **Storage**: Uploaded to Google Drive under the remote `gdrive:Backups/[App]`.
- **Retention Policies**: 
  - 15 days for general full stack backups.
  - 90 days for targeted application backups (Actual Budget, Dawarich, Portainer, Photos).
- **Permissions**: Temporary backup files generated in `/tmp` as root must have their ownership changed to `bert:bert` (`chown "$(id -u bert):$(id -g bert)"`) before uploading, as `rclone` runs under `bert`.

## Key Paths
- **Primary Volumes**: `/home/bert/docker-data` and `/data/dockerdata`
- **Temporary Backups**: `/tmp/[backup_name]`

## Application-Specific Safeguards & Quirks
- **Actual Budget**: SQLite databases are backed up using a Node.js snapshot script (`db.backup()`) injected into the live container to guarantee consistency without downtime.
- **Dawarich**: PostgreSQL/PostGIS databases are dumped online using `pg_dump`. A separate safeguard script (`dawarich_geocode_guard.sh`) disables the nightly reverse-geocoding job to avoid hitting API rate limits during backfills.
- **Portainer**: Backed up via its own HTTP API (`POST /api/backup`) using a token stored in `.portainer_token`.
- **Immich (Photos)**: Backed up using `rclone copy` (not `sync`) to prevent accidental remote deletion. Regeneratable folders (`/thumbs/**`, `/encoded-video/**`) are explicitly excluded.

## Updates
- System updates are handled via `update.sh` using standard `apt` commands. Docker container updates are typically done by pulling new images and pruning the old ones.