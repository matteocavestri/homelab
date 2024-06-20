#!/bin/bash

# Definisci i nomi dei container per ciascuno stack
monitoring_stack=("grafana" "uptimekuma" "prometheus" "cadvisor" "node_exporter" "nvidia_exporter" "promtail" "graphite" "influxdb" "sonarr-exporter" "radarr-exporter" "lidarr-exporter" "prowlarr-exporter" "qbittorrent-exporter" "nzbget_exporter" "speedtest-tracker" "pihole-exporter")
cloud_stack=("nextcloud" "mariadb-nextcloud" "nextcloud-redis" "collabora" "nextcloud-appapi-dsp" "vaultwarden")
media_stack=("jellyfin" "jellyseerr" "gluetun" "flaresolverr" "prowlarr" "radarr" "sonarr" "lidarr" "qbittorrent" "nzbget" "tdarr")
auth_stack=("authentik-server" "authentik-worker" "authentik-db" "authentik-redis")
networking_stack=("traefik" "crowdsec" "bouncer-traefik" "pihole" "cloudflareddns")

# Definizione dei colori
COLOR_BLUE="\033[1;34m"
COLOR_GREEN="\033[1;32m"
COLOR_ORANGE="\033[1;33m"
COLOR_RED="\033[1;31m"
COLOR_BOLD="\033[1m"
COLOR_RESET="\033[0m"

# Funzione per controllare lo stato dei container in uno stack
check_stack() {
    local stack_name=$1
    shift
    local containers=("$@")

    echo -e "${COLOR_BOLD}${stack_name} STACK:${COLOR_RESET}"

    for container in "${containers[@]}"; do
        if echo "$docker_output" | grep -q "^${container}$"; then
            # Verifica lo stato di salute del container
            health_status=$(docker inspect --format='{{json .State.Health.Status}}' "$container" 2>/dev/null | tr -d '"')

            if [ "$health_status" == "healthy" ]; then
                echo -e "  ${container}: ${COLOR_BLUE}RUNNING HEALTHY${COLOR_RESET}"
            elif [ "$health_status" == "unhealthy" ]; then
                echo -e "  ${container}: ${COLOR_ORANGE}RUNNING UNHEALTHY${COLOR_RESET}"
            else
                echo -e "  ${container}: ${COLOR_GREEN}RUNNING (HEALTH CHECK NOT CONFIGURED)${COLOR_RESET}"
            fi
        else
            echo -e "  ${container}: ${COLOR_RED}NOT RUNNING${COLOR_RESET}"
        fi
    done
    echo ""
}

# Esegui il comando docker ps e salva l'output
docker_output=$(docker ps --format "{{.Names}}")

# Controlla e stampa lo stato dei container per ciascuno stack
check_stack "MONITORING" "${monitoring_stack[@]}"
check_stack "CLOUD" "${cloud_stack[@]}"
check_stack "MEDIA" "${media_stack[@]}"
check_stack "AUTH" "${auth_stack[@]}"
check_stack "NETWORKING" "${networking_stack[@]}"

