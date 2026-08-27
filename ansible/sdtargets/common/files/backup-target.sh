#!/bin/bash
# backup-target.sh — backs up one systemd target to the NAS
# Usage: backup-target.sh <target-name>

set -euo pipefail

TARGET="${1:-}"
HOSTNAME=$(hostname -s)
BACKUP_ROOT="/mnt/Backup/${HOSTNAME}"
VOLUMES_BASE="${HOME}/.local/share/containers/storage/volumes"
CONFIGS_BASE="${HOME}/.config"
SYSTEMD_USER="${HOME}/.config/systemd/user"
QUADLET_DIR="${HOME}/.config/containers/systemd"
STAGING_ROOT="${HOME}/.local/share/backup"
KEEP=5
NTFY_ENV="${HOME}/.config/infrastructure/monitoring/ntfy/ntfy.env"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
LOCK_FILE="${HOME}/.local/share/backup/.lock-${TARGET}"

if [[ -z "$TARGET" ]]; then
    echo "ERROR: no target specified" >&2
    exit 1
fi

if ! mountpoint -q /mnt/Backup; then
    echo "ERROR: /mnt/Backup is not mounted" >&2
    exit 2
fi

if [[ ! -w /mnt/Backup ]]; then
    echo "ERROR: /mnt/Backup is not writable" >&2
    exit 2
fi

mkdir -p "$STAGING_ROOT"

# One run per target at a time: a slow run must not overlap the next timer fire,
# or two manual runs of the same target racing on the same staging directory.
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "ERROR: another backup-target.sh run for '${TARGET}' is already in progress" >&2
    exit 4
fi

# Staging is namespaced per run (target+pid): different targets' timers can run
# concurrently and must not delete each other's in-flight staging files on exit.
STAGING="${STAGING_ROOT}/${TARGET}.$$"
mkdir -p "$STAGING"
cleanup_staging() { rm -rf "$STAGING"; }
trap cleanup_staging EXIT

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

notify() {
    local title="$1" msg="$2" priority="$3" topic="$4"
    if [[ -f "$NTFY_ENV" ]]; then
        # shellcheck disable=SC1090
        source "$NTFY_ENV"
        curl -sf \
            -u "${NTFY_USER}:${NTFY_PASS}" \
            -H "Title: ${title}" \
            -H "Priority: ${priority}" \
            -H "Tags: floppy_disk" \
            -d "${msg}" \
            "${NTFY_URL}/${topic}" || true
    fi
}

rotate_backups() {
    local dir="$1"
    local count
    count=$(find "$dir" -maxdepth 1 -mindepth 1 \( -name "*.tar.gz" -o -name "*.sql.gz" \) | wc -l)
    if (( count > KEEP )); then
        find "$dir" -maxdepth 1 -mindepth 1 \( -name "*.tar.gz" -o -name "*.sql.gz" \) | \
            sort | head -n $(( count - KEEP )) | \
            xargs rm -f
    fi
}

backup_volume() {
    local volume_name="$1"
    local dest_dir="$2"
    local volume_path="${VOLUMES_BASE}/${volume_name}/_data"

    if [[ ! -d "$volume_path" ]]; then
        log "WARN: volume $volume_name not found at $volume_path, skipping"
        return 0
    fi

    local archive="${STAGING}/${volume_name}_${TIMESTAMP}.tar.gz"
    local dest_file="${dest_dir}/${volume_name}_${TIMESTAMP}.tar.gz"

    log "Backing up volume $volume_name to staging"
    mkdir -p "$dest_dir"

    podman unshare tar -czf "$archive" -C "$volume_path" .

    log "Transferring $volume_name to NAS"
    rsync -a "$archive" "$dest_file"
    rm -f "$archive"

    rotate_backups "$dest_dir"
    log "Volume $volume_name done"
}

backup_postgres() {
    local container="$1"
    local dest_dir="$2"
    local dbname="$3"
    local dbuser="$4"

    local archive="${STAGING}/${dbname}_${TIMESTAMP}.sql.gz"
    local dest_file="${dest_dir}/${dbname}_${TIMESTAMP}.sql.gz"

    log "pg_dump $dbname from container $container"
    mkdir -p "$dest_dir"

    podman exec "$container" pg_dump -U "$dbuser" "$dbname" | \
        gzip > "$archive"

    log "Transferring dump $dbname to NAS"
    rsync -a "$archive" "$dest_file"
    rm -f "$archive"

    rotate_backups "$dest_dir"
    log "pg_dump $dbname done"
}

# Maps a target name to its config tree under ~/.config (layout isn't uniform:
# arr/jellyfin/immich nest under media/, auth/monitoring/netcore/proxy under
# infrastructure/, everything else - ai, office, homepage - sits flat).
config_base_for() {
    case "$1" in
        arr|jellyfin|immich) echo "${CONFIGS_BASE}/media/$1" ;;
        auth|monitoring|netcore|proxy) echo "${CONFIGS_BASE}/infrastructure/$1" ;;
        *) echo "${CONFIGS_BASE}/$1" ;;
    esac
}

backup_configs() {
    local target="$1"
    local dest_dir="$2"
    local config_base
    config_base=$(config_base_for "$target")

    log "Backing up $target configs"
    local archive="${STAGING}/configs-${target}_${TIMESTAMP}.tar.gz"
    local dest_file="${dest_dir}/configs-${target}_${TIMESTAMP}.tar.gz"
    mkdir -p "$dest_dir"

    local tmpdir
    tmpdir=$(mktemp -d "${STAGING}/configs-XXXXXX")

    # quadlets for every service the target wants
    local services
    services=$(systemctl --user show "${target}.target" --property=Wants --value 2>/dev/null | \
        tr ' ' '\n' | grep '\.service$' | sed 's/\.service$//')
    for svc in $services; do
        [[ -f "${QUADLET_DIR}/${svc}.container" ]] && \
            cp "${QUADLET_DIR}/${svc}.container" "$tmpdir/" 2>/dev/null || true
    done

    # target-level units
    for f in "${SYSTEMD_USER}/${target}.target" \
              "${SYSTEMD_USER}/${target}.slice" \
              "${QUADLET_DIR}/${target}.network"; do
        [[ -f "$f" ]] && cp "$f" "$tmpdir/" 2>/dev/null || true
    done

    # whole config tree (.env files and any other per-service config)
    [[ -d "$config_base" ]] && rsync -a "${config_base}/" "${tmpdir}/config/" 2>/dev/null || true

    tar -czf "$archive" -C "$tmpdir" .
    rm -rf "$tmpdir"

    rsync -a "$archive" "$dest_file"
    rm -f "$archive"

    rotate_backups "$dest_dir"
    log "Config backup for $target done"
}

run_backup() {
    local target="$1"
    local target_dir="${BACKUP_ROOT}/${target}"
    local errors=0

    log "=== Starting backup for target: $target ==="

    case "$target" in

    netcore)
        backup_configs "$target" "${target_dir}/configs" || (( errors++ ))
        backup_volume "ddns-updater-data" "${target_dir}/ddns-updater" || (( errors++ ))
        backup_volume "pihole-data" "${target_dir}/pihole" || (( errors++ ))
        backup_volume "pihole-dnsmasq" "${target_dir}/pihole" || (( errors++ ))
        ;;

    proxy)
        backup_configs "$target" "${target_dir}/configs" || (( errors++ ))
        backup_volume "npmplus-data" "${target_dir}/npmplus" || (( errors++ ))
        backup_volume "crowdsec-conf" "${target_dir}/crowdsec" || (( errors++ ))
        backup_volume "crowdsec-data" "${target_dir}/crowdsec" || (( errors++ ))
        backup_volume "geoip-data" "${target_dir}/geoipupdate" || (( errors++ ))
        ;;

    auth)
        backup_configs "$target" "${target_dir}/configs" || (( errors++ ))
        backup_postgres "authentik-postgres" \
            "${target_dir}/authentik-postgres" \
            "authentik" "authentik" || (( errors++ ))
        backup_volume "authentik-media" "${target_dir}/authentik-server" || (( errors++ ))
        backup_volume "authentik-custom-templates" "${target_dir}/authentik-server" || (( errors++ ))
        backup_volume "authentik-certs" "${target_dir}/authentik-worker" || (( errors++ ))
        ;;

    monitoring)
        backup_configs "$target" "${target_dir}/configs" || (( errors++ ))
        for svc in ntfy alertmanager grafana mimir loki tempo pyroscope; do
            backup_volume "${svc}-data" "${target_dir}/${svc}" || (( errors++ ))
        done
        ;;

    jellyfin)
        backup_configs "$target" "${target_dir}/configs" || (( errors++ ))
        backup_volume "jellyfin-config" "${target_dir}/jellyfin" || (( errors++ ))
        ;;

    arr)
        backup_configs "$target" "${target_dir}/configs" || (( errors++ ))
        for svc in gluetun sonarr radarr lidarr prowlarr nzbget qbittorrent jellyseerr sportarr; do
            backup_volume "${svc}-config" "${target_dir}/${svc}" || (( errors++ ))
        done
        for vol in tdarr-configs tdarr-logs tdarr-server; do
            backup_volume "$vol" "${target_dir}/tdarr" || (( errors++ ))
        done
        ;;

    office)
        backup_configs "$target" "${target_dir}/configs" || (( errors++ ))
        backup_volume "vaultwarden-data" "${target_dir}/vaultwarden" || (( errors++ ))
        backup_volume "freshrss-data" "${target_dir}/freshrss" || (( errors++ ))
        backup_volume "freshrss-extensions" "${target_dir}/freshrss" || (( errors++ ))
        ;;

    immich)
        backup_configs "$target" "${target_dir}/configs" || (( errors++ ))
        backup_postgres "immich-postgres" \
            "${target_dir}/immich-postgres" \
            "immich" "immich" || (( errors++ ))
        ;;

    ai)
        backup_configs "$target" "${target_dir}/configs" || (( errors++ ))
        backup_volume "openwebui-data" "${target_dir}/openwebui" || (( errors++ ))
        ;;

    *)
        log "ERROR: unknown target '$target'"
        return 3
        ;;
    esac

    log "=== Backup for target $target done (errors: $errors) ==="
    return "$errors"
}

if run_backup "$TARGET"; then
    log "Backup $TARGET completed successfully"
    notify \
        "💾 Backup OK: ${TARGET}@${HOSTNAME}" \
        "Backup of target ${TARGET} completed at ${TIMESTAMP}" \
        "default" \
        "systemd-info"
else
    log "Backup $TARGET completed WITH ERRORS"
    notify \
        "❌ Backup FAILED: ${TARGET}@${HOSTNAME}" \
        "Backup of target ${TARGET} failed at ${TIMESTAMP} — check the journal" \
        "urgent" \
        "systemd-critical"
    exit 1
fi
