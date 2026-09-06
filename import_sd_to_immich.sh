#!/usr/bin/env bash
#
# import_sd_to_immich.sh
# 
# Importeert foto's en video's van een geplaatste SD-kaart (standaard /dev/mmcblk0p1)
# rechtstreeks naar Immich met behulp van immich-go.
#
# Gebruik:
#   ./import_sd_to_immich.sh [--dry-run] [--album "Album Naam"] [--folder-as-album]
#
set -euo pipefail

usage() {
    cat <<EOF
Gebruik: $(basename "$0") [OPTIES] [SUBMAP]

Opties:
  -d, --dry-run           Voer een simulatie uit zonder bestanden echt te uploaden
  -a, --album NAAM        Plaats alle geïmporteerde foto's in een specifiek album in Immich
  -f, --folder-as-album   Gebruik de submapnaam als albumnaam in Immich
  -s, --source DEVICE     Kies een ander device (standaard: /dev/mmcblk0p1)
  -h, --help              Toon deze uitleg

Omgevingsvariabelen (in ~/.bashrc.d/immich.sh of .env):
  IMMICH_SERVER           URL van Immich (standaard: http://localhost:2283)
  IMMICH_API_KEY          API-sleutel van Immich (verplicht)

Voorbeelden:
  $(basename "$0") --dry-run
  $(basename "$0")
  $(basename "$0") --album "Vakantie 2026"
  $(basename "$0") --folder-as-album
EOF
    exit 0
}

# Controleer eerst of enkel --help gevraagd wordt (geen sudo nodig)
for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        usage
    fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Laad omgevingsvariabelen indien nog niet gezet
if [ -z "${IMMICH_API_KEY:-}" ]; then
    # Probeer eerst ~/.bashrc.d/immich.sh van de actieve of bert gebruiker
    USER_HOME="${HOME:-/home/bert}"
    if [ -f "$USER_HOME/.bashrc.d/immich.sh" ]; then
        # shellcheck source=/dev/null
        source "$USER_HOME/.bashrc.d/immich.sh"
    elif [ -f "/home/bert/.bashrc.d/immich.sh" ]; then
        # shellcheck source=/dev/null
        source "/home/bert/.bashrc.d/immich.sh"
    fi
fi

if [ -z "${IMMICH_API_KEY:-}" ]; then
    # Fallback naar .env in de scriptdirectory
    if [ -f "$SCRIPT_DIR/.env" ]; then
        # Exporteer enkel relevante variabelen uit .env
        ENV_KEY=$(grep -E '^IMMICH_API_KEY=' "$SCRIPT_DIR/.env" | cut -d '=' -f2- | tr -d '"'\''')
        if [ -n "$ENV_KEY" ]; then
            export IMMICH_API_KEY="$ENV_KEY"
        fi
        if [ -z "${IMMICH_SERVER:-}" ]; then
            ENV_SRV=$(grep -E '^IMMICH_SERVER=' "$SCRIPT_DIR/.env" | cut -d '=' -f2- | tr -d '"'\''')
            if [ -n "$ENV_SRV" ]; then
                export IMMICH_SERVER="$ENV_SRV"
            fi
        fi
    fi
fi

# Herstart met sudo indien niet als root gestart (nodig voor mount/umount)
# Behoud hierbij de Immich-omgevingsvariabelen
if [ "${EUID}" -ne 0 ]; then
    exec sudo --preserve-env=IMMICH_API_KEY,IMMICH_SERVER "$0" "$@"
fi

DEVICE="/dev/mmcblk0p1"
MOUNT_POINT="/mnt/sd-import"
IMMICH_SERVER="${IMMICH_SERVER:-http://localhost:2283}"
IMMICH_GO="/usr/local/bin/immich-go"

# Verifieer API-sleutel
if [ -z "${IMMICH_API_KEY:-}" ]; then
    echo "Fout: IMMICH_API_KEY is niet ingesteld!" >&2
    echo "Configureer deze in ~/.bashrc.d/immich.sh of $SCRIPT_DIR/.env:" >&2
    echo "  export IMMICH_API_KEY=\"jouw_api_sleutel\"" >&2
    exit 1
fi

DRY_RUN=false
FOLDER_AS_ALBUM=false
INTO_ALBUM=""
CUSTOM_TARGET=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -a|--album)
            INTO_ALBUM="$2"
            shift 2
            ;;
        -f|--folder-as-album)
            FOLDER_AS_ALBUM=true
            shift
            ;;
        -s|--source)
            DEVICE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        -*)
            echo "Onbekende optie: $1" >&2
            usage
            ;;
        *)
            CUSTOM_TARGET="$1"
            shift
            ;;
    esac
done

if [ ! -x "$IMMICH_GO" ]; then
    echo "Fout: immich-go niet gevonden op $IMMICH_GO" >&2
    exit 1
fi

if [ ! -b "$DEVICE" ]; then
    echo "Fout: SD-kaart device '$DEVICE' niet gevonden." >&2
    echo "Controleer of het SD-kaartje goed in de NUC zit." >&2
    exit 1
fi

mkdir -p "$MOUNT_POINT"

WAS_ALREADY_MOUNTED=false
if mountpoint -q "$MOUNT_POINT"; then
    WAS_ALREADY_MOUNTED=true
    echo "Mountpunt $MOUNT_POINT was reeds aangekoppeld."
else
    echo "SD-kaart veilig aankoppelen (read-only): $DEVICE -> $MOUNT_POINT..."
    mount -o ro "$DEVICE" "$MOUNT_POINT"
fi

cleanup() {
    local exit_code=$?
    if [ "$WAS_ALREADY_MOUNTED" = false ] && mountpoint -q "$MOUNT_POINT"; then
        echo "SD-kaart ontkoppelen ($MOUNT_POINT)..."
        umount "$MOUNT_POINT" || true
    fi
    exit "$exit_code"
}
trap cleanup EXIT INT TERM

# Bepaal bronmap: custom opgave, DCIM map (standaard camera), of root van mount
SOURCE_DIR="$MOUNT_POINT"
if [ -n "$CUSTOM_TARGET" ]; then
    if [ -d "$MOUNT_POINT/$CUSTOM_TARGET" ]; then
        SOURCE_DIR="$MOUNT_POINT/$CUSTOM_TARGET"
    elif [ -d "$CUSTOM_TARGET" ]; then
        SOURCE_DIR="$CUSTOM_TARGET"
    else
        echo "Fout: Opgegeven bronmap '$CUSTOM_TARGET' bestaat niet." >&2
        exit 1
    fi
elif [ -d "$MOUNT_POINT/DCIM" ]; then
    SOURCE_DIR="$MOUNT_POINT/DCIM"
fi

echo "Bronmap voor import: $SOURCE_DIR"

# Stel immich-go argumenten samen
CMD_ARGS=(
    "upload" "from-folder"
    "--server" "$IMMICH_SERVER"
    "--api-key" "$IMMICH_API_KEY"
)

if [ "$DRY_RUN" = true ]; then
    echo "[!] Modus: DRY-RUN (er worden geen bestanden geüpload)"
    CMD_ARGS+=("--dry-run")
fi

if [ -n "$INTO_ALBUM" ]; then
    echo "Bestemming album: '$INTO_ALBUM'"
    CMD_ARGS+=("--into-album" "$INTO_ALBUM")
fi

if [ "$FOLDER_AS_ALBUM" = true ]; then
    echo "Optie actief: mapnamen worden overgenomen als album"
    CMD_ARGS+=("--folder-as-album" "FOLDER")
fi

CMD_ARGS+=("$SOURCE_DIR")

echo "Starten van immich-go import..."
# Voer uit als gebruiker 'bert' zodat logs/cache in /home/bert/.cache terechtkomen
if id -u bert >/dev/null 2>&1; then
    sudo -u bert "$IMMICH_GO" "${CMD_ARGS[@]}"
else
    "$IMMICH_GO" "${CMD_ARGS[@]}"
fi

echo "Import succesvol afgerond!"
