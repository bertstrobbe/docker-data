#!/bin/bash
#
# Aparte backup van Actual Budget (los van de smarthome-backup).
# Maakt een CONSISTENTE snapshot van de SQLite-bestanden via de online
# backup-API (db.backup()) terwijl de server gewoon blijft draaien, en
# uploadt die naar Google Drive met 90 dagen retentie.
#
set -euo pipefail

# Als root draaien (zoals backup_to_gdrive.sh)
if [ "$EUID" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

# Configuratie
CONTAINER="actualbudget"
GDRIVE_REMOTE="gdrive:Backups/Actual"
RETENTION_DAYS=90
BACKUP_NAME="actual_$(date +%Y%m%d).tar.gz"

CONTAINER_OUT="/tmp/actual_bk"          # snapshotmap IN de container
CONTAINER_JS="/tmp/actual_snapshot.js"  # snapshotscript IN de container
HOST_TMP="$(mktemp -d /tmp/actual_bk.XXXXXX)"
# mktemp maakt deze map als root (0700); de docker cp's draaien als bert
# (sudo -u bert docker), dus bert moet erin kunnen lezen/schrijven.
chown bert:bert "$HOST_TMP"

cleanup() {
    sudo -u bert docker exec "$CONTAINER" rm -rf "$CONTAINER_OUT" "$CONTAINER_JS" 2>/dev/null || true
    rm -rf "$HOST_TMP" "/tmp/$BACKUP_NAME" 2>/dev/null || true
}
trap cleanup EXIT

echo "Consistente snapshot maken van $CONTAINER..."

# 1. Snapshotscript schrijven en in de container uitvoeren.
#    db.backup() gebruikt de SQLite online-backup-API: veilig op een live DB.
cat > "$HOST_TMP/actual_snapshot.js" <<'JS'
// Absoluut pad: het script draait vanuit /tmp, maar de module zit in /app.
const Database = require("/app/node_modules/better-sqlite3");
const fs = require("fs");
const SRC = "/data";
const OUT = "/tmp/actual_bk";

fs.rmSync(OUT, { recursive: true, force: true });
for (const d of ["server-files", "user-files"]) fs.mkdirSync(`${OUT}/${d}`, { recursive: true });

(async () => {
  for (const sub of ["server-files", "user-files"]) {
    for (const f of fs.readdirSync(`${SRC}/${sub}`)) {
      const sp = `${SRC}/${sub}/${f}`;
      const dp = `${OUT}/${sub}/${f}`;
      if (f.endsWith(".sqlite")) {
        const db = new Database(sp, { readonly: true });
        await db.backup(dp);            // consistente copy van live DB
        db.close();
        const chk = new Database(dp, { readonly: true });
        const ic = chk.pragma("integrity_check", { simple: true });
        chk.close();
        if (ic !== "ok") throw new Error(`integrity_check faalde voor ${sp}: ${ic}`);
        console.log(`  ok  ${sub}/${f}`);
      } else {
        fs.copyFileSync(sp, dp);        // .blob attachments e.d.
        console.log(`  cp  ${sub}/${f}`);
      }
    }
  }
  if (fs.existsSync(`${SRC}/.migrate`)) fs.copyFileSync(`${SRC}/.migrate`, `${OUT}/.migrate`);
  console.log("snapshot compleet");
})().catch((e) => { console.error(e); process.exit(1); });
JS

sudo -u bert docker cp "$HOST_TMP/actual_snapshot.js" "$CONTAINER:$CONTAINER_JS"
sudo -u bert docker exec "$CONTAINER" node "$CONTAINER_JS"

# 2. Snapshot uit de container halen
sudo -u bert docker cp "$CONTAINER:$CONTAINER_OUT" "$HOST_TMP/snapshot"

# 3. Inpakken
tar -czf "/tmp/$BACKUP_NAME" -C "$HOST_TMP/snapshot" .
chown "$(id -u bert):$(id -g bert)" "/tmp/$BACKUP_NAME"
echo "Backup gemaakt: /tmp/$BACKUP_NAME ($(du -h "/tmp/$BACKUP_NAME" | cut -f1))"

# 4. Uploaden met rclone (rclone-config is gebruikersspecifiek)
echo "Uploaden naar $GDRIVE_REMOTE..."
sudo -u bert rclone copy "/tmp/$BACKUP_NAME" "$GDRIVE_REMOTE"

# 5. Oude backups opruimen
sudo -u bert rclone delete "$GDRIVE_REMOTE" --min-age "${RETENTION_DAYS}d" --include "actual_*.tar.gz"

echo "Klaar."
