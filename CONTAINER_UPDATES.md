# Docker Container Update Guide

This document outlines the standard operating procedures for updating Docker containers and stacks in this environment, taking into account **Watchtower**, **Portainer**, and stack-specific quirks.

---

## 1. Quick Reference Matrix

| Container / Stack | Update Method | Notes / Prerequisites |
| :--- | :--- | :--- |
| **`music-assistant`** | 🤖 Automatic (Watchtower) | Runs hourly via label `com.centurylinklabs.watchtower.enable=true` |
| **`zigbee2mqtt`** | 🤖 Automatic (Watchtower) | Automatically pulled & restarted when new image appears |
| **`firefox_kiosk`** | 🤖 Automatic (Watchtower) | Automatically updated by Watchtower |
| **`orb-sensor`** | 🤖 Automatic (Watchtower) | Automatically updated by Watchtower |
| **`mosquitto`** | 🤖 Automatic (Watchtower) | Automatically updated by Watchtower |
| **`watchtower`** | 🤖 Automatic (Watchtower) | Self-updates |
| **`homeassistant`** | ⚡ One-Shot CLI Watchtower | **Do not re-pull `smarthome` stack in Portainer** (fails due to local image). Use one-shot command. |
| **`actualbudget`** | 🖥️ Portainer Stack UI | Pinned version (e.g. `26.8.1`). Run backup before updating tag. |
| **`immich` Stack** | 🖥️ Portainer Stack UI | Pinned version (`server`, `machine-learning`, `postgres`, `redis`). Check breaking changes & backup first. |
| **`dawarich` Stack** | 🖥️ Portainer Stack UI | Run DB backup first (`backup_dawarich_to_gdrive.sh`). |
| **`photon`** | 🖥️ Portainer Stack UI | Redeploy / pull updated base image if needed. |
| **`portainer`** | 💻 Docker CLI | Standalone container. Updated by replacing container with latest LTS image. |
| **`caddy`** | 🔨 Build / GHCR Pull | Custom build with deSEC plugin (`ghcr.io/bertstrobbe/caddy-desec:2`). |
| **`garmin_connect_exporter`** | 🔨 Local Build / Git | Locally built image (`garmin_connect_exporter-app`). |
| **`yt-pot-provider`** | 🔨 Local Build | Locally built image (`yt-pot-provider:1`). |

---

## 2. Pre-Update Best Practices

Before performing manual updates on critical data stores (Actual Budget, Immich, Dawarich, Home Assistant):

1. **Trigger Backup Scripts**:
   ```bash
   # In /home/bert/docker-data/
   sudo ./backup_actual_to_gdrive.sh       # Actual Budget snapshot
   sudo ./backup_dawarich_to_gdrive.sh     # Dawarich Postgres dump
   sudo ./backup_photos_to_gdrive.sh       # Immich photos & DB
   sudo ./backup_portainer_to_gdrive.sh    # Portainer config backup
   sudo ./backup_to_gdrive.sh              # General smart home data
   ```
2. **Review Release Notes**:
   - Check changelogs for breaking changes (especially for **Home Assistant**, **Immich**, and **Dawarich**).

---

## 3. Update Procedures

### Category A: Auto-Updated Containers (Watchtower)

Watchtower is running as a daemon container checking for updates every hour (`WATCHTOWER_POLL_INTERVAL=3600`) with `WATCHTOWER_LABEL_ENABLE=true`.

Containers tagged with `com.centurylinklabs.watchtower.enable=true` will update automatically and clean up old images.

#### Enabling / Disabling Watchtower for a Container
Add or remove the following label in the container's Portainer stack / compose file:
```yaml
labels:
  - "com.centurylinklabs.watchtower.enable=true"
```

#### Manually Triggering an Immediate Watchtower Scan
To force Watchtower to immediately check and update all labeled containers right now:
```bash
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e DOCKER_API_VERSION=1.40 \
  containrrr/watchtower --run-once --label-enable --cleanup
```

---

### Category B: Home Assistant (`homeassistant`)

> [!WARNING]
> **Do not use "Re-pull image and redeploy" on the `smarthome` stack in Portainer!**
> The `smarthome` stack contains `yt-pot-provider:1`, which is a local-only image that does not exist on Docker Hub. Triggering a full stack re-pull in Portainer will cause a **Status 500 error** and abort.

#### Recommended Update Method (One-Shot Watchtower):
Run a targeted one-shot Watchtower run specifically for `homeassistant`:
```bash
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -e DOCKER_API_VERSION=1.40 \
  containrrr/watchtower --run-once --cleanup homeassistant
```

This safely pulls the latest `ghcr.io/home-assistant/home-assistant:stable` image, stops the old container, and starts the new one while preserving all settings, environment variables, network mounts, and volumes.

---

### Category C: Updating Stacks via Portainer UI (Immich, Dawarich, Actual Budget, Photon)

For applications managed as Stacks in Portainer:

1. Open **Portainer** (`https://<portainer-url>:9443` or local port).
2. Go to **Stacks** in the left sidebar.
3. Select the stack you want to update (e.g., `immich`, `dawarich`, `actualbudget`).
4. Switch to the **Editor** tab.
5. **If version tags are pinned**:
   - Update the image tag (for example, change `immich-server:v3.1.0` to `immich-server:v3.2.0`).
6. Scroll down to the bottom of the editor:
   - Toggle **Re-pull image and redeploy** to `ON`.
   - Click **Update the stack**.
7. Wait for Portainer to pull the new layers and recreate the containers.

---

### Category D: Updating Portainer Server

Portainer cannot update its own container from within the Portainer UI. Update it using the Docker CLI:

```bash
# 1. Stop and remove the current Portainer container
docker stop portainer
docker rm portainer

# 2. Pull the latest LTS image
docker pull portainer/portainer-ce:lts

# 3. Re-run Portainer with the persistent volume mount
docker run -d \
  -p 8000:8000 \
  -p 9000:9000 \
  -p 9443:9443 \
  --name portainer \
  --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /data/dockerdata/portainer/data:/data \
  portainer/portainer-ce:lts
```

*(All configuration, user accounts, and stack definitions remain intact in `/data/dockerdata/portainer/data`.)*

---

### Category E: Locally Built Images

#### 1. Caddy (`ghcr.io/bertstrobbe/caddy-desec:2`)
If Caddy or the deSEC DNS plugin has an update:
1. Navigate to the build repository (`/home/bert/caddy-desec-build`).
2. Update the `Dockerfile` with the new Caddy version or build it locally.
3. Build and tag the new image:
   ```bash
   docker build -t ghcr.io/bertstrobbe/caddy-desec:2 .
   ```
4. In Portainer, redeploy the `caddy` stack (or restart the container).

#### 2. Garmin Connect Exporter (`garmin_connect_exporter`)
1. Navigate to `/home/bert/garmin_connect_exporter`.
2. Pull latest code (`git pull`) or make necessary edits.
3. Rebuild the image:
   ```bash
   docker compose build
   docker compose up -d
   ```

#### 3. YouTube Provider (`yt-pot-provider`)
1. Navigate to `/home/bert/docker-data/yt-provider`.
2. Rebuild the image:
   ```bash
   docker build -t yt-pot-provider:1 .
   ```
3. Restart the container:
   ```bash
   docker restart yt-pot-provider
   ```

---

## 4. Post-Update Verification & Clean Up

### Verify Containers are Running & Healthy
```bash
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
```

### Check Logs for Errors
```bash
# View recent logs of a specific container (e.g., homeassistant)
docker logs --tail 100 -f homeassistant
```

### Clean Up Dangling / Old Images
After manual updates, prune unused images to free up disk space:
```bash
# Remove dangling (untagged) images
docker image prune -f

# Or remove all unused images older than 7 days
docker image prune -a --filter "until=168h" -f
```
