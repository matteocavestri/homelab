# homelab

Ansible playbook that deploys a Podman Quadlet container stack (rootless,
`systemd --user`) on AlmaLinux 10.

## Layout

```
ansible/
  ansible.cfg
  inventory/hosts.yml
  group_vars/
    all/versions.yml   # image tag/digest per container
    all/common.yml     # shared config (TZ, admin/ACME email)
    all/vault.yml       # secrets (ansible-vault encrypted)
    <target>.yml        # per-role slice limits + config
  roles/
    ai/ auth/ media_arr/ media_immich/ media_jellyfin/
    monitoring/ netcore/ office/ proxy/
    common/ bin/ backup_timers/ status/
  site.yml
scripts/
  check_updates.py       # skopeo-based image update checker
```

## Usage

### Secrets

`group_vars/all/vault.yml` is encrypted with `ansible-vault`:

```bash
cd ansible
ansible-vault edit group_vars/all/vault.yml
```

### Deploy

```bash
cd ansible
ansible-playbook site.yml --ask-vault-pass          # whole stack
ansible-playbook site.yml --tags monitoring         # single role
ansible-playbook site.yml --check --diff --ask-vault-pass   # dry run
```

The playbook doesn't enable/start service targets on first deploy — after the
first run:

```bash
systemctl --user enable --now <name>.target
loginctl enable-linger <user>
```

### Check status

```bash
ansible-playbook site.yml --tags status --ask-vault-pass
```

Read-only: reports `is-enabled`/`is-active` for every target and backup timer,
and lists any failed unit.

### Check for image updates

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r scripts/requirements.txt   # requires skopeo

python3 scripts/check_updates.py                 # table
python3 scripts/check_updates.py --json           # machine-readable
python3 scripts/check_updates.py --only jellyfin  # single image
python3 scripts/check_updates.py --apply          # write updates to versions.yml
```

## Backups

| Target | Schedule (daily) | What gets backed up |
|---|---|---|
| auth | 01:00 | config tree, `pg_dump` authentik-postgres, authentik media/templates/certs volumes |
| netcore | 02:00 | config tree, ddns-updater/pihole volumes |
| proxy | 03:00 | config tree, npmplus/crowdsec/geoip volumes |
| jellyfin | 03:30 | config tree, jellyfin-config volume |
| arr | 03:45 | config tree, every `*-config` volume (incl. sportarr) + tdarr |
| monitoring | 04:00 | config tree, data volumes of ntfy/alertmanager/grafana/mimir/loki/tempo/pyroscope |
| office | 04:15 | config tree, vaultwarden-data, freshrss-data/-extensions |
| immich | 04:30 | config tree, `pg_dump` immich-postgres |
| ai | 04:45 | config tree, openwebui-data only |

## Container versions

Managed in `ansible/group_vars/all/versions.yml`, checked with
`scripts/check_updates.py`.

### ai

| Service | Image | Version |
|---|---|---|
| comfyui | `localhost/comfyui-p4` | local build (untracked) |
| crawl4ai | `docker.io/unclecode/crawl4ai` | 0.9.2 |
| mcpo | `ghcr.io/open-webui/mcpo` | latest (digest-tracked) |
| n8n | `docker.io/n8nio/n8n` | 2.36.6 |
| ollama | `docker.io/ollama/ollama` | 0.32.15 |
| openai-edge-tts | `docker.io/travisvn/openai-edge-tts` | latest (digest-tracked) |
| openterminal | `ghcr.io/open-webui/open-terminal` | latest (digest-tracked) |
| openwebui | `ghcr.io/open-webui/open-webui` | v0.11.0 |
| pipelines | `ghcr.io/open-webui/pipelines` | main (digest-tracked) |
| qdrant | `docker.io/qdrant/qdrant` | v1.19 |
| searxng | `docker.io/searxng/searxng` | latest (digest-tracked) |
| tika | `docker.io/apache/tika` | 4.0.0-1-full |

### auth

| Service | Image | Version |
|---|---|---|
| authentik | `ghcr.io/goauthentik/server` | 2026.8.0, pinned by digest |
| authentik-postgres | `docker.io/library/postgres` | 17-alpine (digest-tracked) |

### common

| Service | Image | Version |
|---|---|---|
| homepage | `ghcr.io/gethomepage/homepage` | v2.1.2 |

### media_arr

| Service | Image | Version |
|---|---|---|
| exportarr (x4: lidarr/prowlarr/radarr/sonarr) | `ghcr.io/onedr0p/exportarr` | v2.3.0 |
| flaresolverr | `ghcr.io/flaresolverr/flaresolverr` | v3.5.0 |
| gluetun | `docker.io/qmcgaw/gluetun` | v3.41.3 |
| jellyseerr | `ghcr.io/seerr-team/seerr` | v3.4.1 |
| lidarr | `lscr.io/linuxserver/lidarr` | latest (digest-tracked) |
| nzbget | `lscr.io/linuxserver/nzbget` | latest (digest-tracked) |
| nzbget-exporter | `docker.io/frebib/nzbget-exporter` | latest (digest-tracked) |
| prowlarr | `lscr.io/linuxserver/prowlarr` | latest (digest-tracked) |
| qbittorrent | `lscr.io/linuxserver/qbittorrent` | 5.1.4-r3-ls453 |
| qbittorrent-exporter | `ghcr.io/martabal/qbittorrent-exporter` | v2.0.2 |
| radarr | `lscr.io/linuxserver/radarr` | latest (digest-tracked) |
| sonarr | `lscr.io/linuxserver/sonarr` | latest (digest-tracked) |
| sportarr | `docker.io/sportarr/sportarr` | 4.1.3.1113 |
| tdarr | `ghcr.io/haveagitgat/tdarr` | latest (digest-tracked) |

### media_immich

| Service | Image | Version |
|---|---|---|
| immich-machine-learning | `ghcr.io/immich-app/immich-machine-learning` | release (digest-tracked) |
| immich-postgres | `ghcr.io/immich-app/postgres` | 14-vectorchord0.4.3-pgvectors0.2.0 |
| immich-redis | `docker.io/valkey/valkey` | 9.1.1 |
| immich-server | `ghcr.io/immich-app/immich-server` | release (digest-tracked) |

### media_jellyfin

| Service | Image | Version |
|---|---|---|
| jellyfin | `docker.io/jellyfin/jellyfin` | 10.11.11 |
| jellyfin-exporter | `docker.io/rebelcore/jellyfin-exporter` | v1.5.2 |

### monitoring

| Service | Image | Version |
|---|---|---|
| alertmanager | `docker.io/prom/alertmanager` | v0.34.0 |
| alloy | `docker.io/grafana/alloy` | v1.19.0 |
| grafana | `docker.io/grafana/grafana` | 13.2.0 |
| loki | `docker.io/grafana/loki` | 3.7.6 |
| mimir | `docker.io/grafana/mimir` | 3.2.0 |
| node-exporter | `docker.io/prom/node-exporter` | v1.12.1 |
| ntfy | `docker.io/binwiederhier/ntfy` | v2.27.0 |
| nvidia-gpu-exporter | `docker.io/utkuozdemir/nvidia_gpu_exporter` | 1.14.0 |
| podman-exporter | `quay.io/navidys/prometheus-podman-exporter` | latest (digest-tracked) |
| pyroscope | `docker.io/grafana/pyroscope` | 2.3.0 (digest-tracked) |
| tempo | `docker.io/grafana/tempo` | 3.0.3 |

### netcore

| Service | Image | Version |
|---|---|---|
| ddns-updater | `docker.io/qmcgaw/ddns-updater` | 2.10.0 |
| pihole | `docker.io/pihole/pihole` | 2026.07.2 |

### office

| Service | Image | Version |
|---|---|---|
| freshrss | `docker.io/freshrss/freshrss` | 1.29.1 |
| vaultwarden | `docker.io/vaultwarden/server` | 1.37.2 |

### proxy

| Service | Image | Version |
|---|---|---|
| crowdsec | `docker.io/crowdsecurity/crowdsec` | v1.7.8 |
| crowdsec-web-ui | `ghcr.io/theduffman85/crowdsec-web-ui` | 2026.8.1 |
| geoipupdate | `ghcr.io/maxmind/geoipupdate` | v8.0.0 |
| npmplus | `docker.io/zoeyvid/npmplus` | 2026-07-24-r1 |

## Services

Ports are host-published bindings only; a service reachable solely on its
`.network` from other containers is marked *internal*.

### ai — `ai.network`, `ai.slice`

| Service | Ports | Network | Volumes | Config |
|---|---|---|---|---|
| comfyui | 127.0.0.1:8188 | ai.network, GPU (CDI) | `comfyui-storage:/root` | `comfyui.env` |
| crawl4ai | internal | ai.network | `crawl4ai-data:/home/appuser/.crawl4ai` | `crawl4ai.env` |
| mcpo | internal | ai.network | `mcpo-config.json:/app/config.json:ro`, `~/projects:/projects`, podman socket | — |
| n8n | 127.0.0.1:5678 | ai.network | `n8n-data:/home/node/.n8n` | `n8n.env` |
| ollama | 127.0.0.1:11434 | ai.network, GPU | `ollama-data:/root/.ollama` | `ollama.env` |
| openai-edge-tts | internal | ai.network | — | `openai-edge-tts.env` |
| openterminal | internal | ai.network | `open-terminal-data:/home/user` | `openterminal.env` |
| openwebui | 127.0.0.1:8081 | ai.network + monitoring.network | `openwebui-data:/app/backend/data` | `openwebui.env` |
| pipelines | internal | ai.network | `pipelines-data:/app/pipelines` | `pipelines.env` |
| qdrant | 127.0.0.1:6333 | ai.network | `qdrant-data:/qdrant/storage` | `qdrant.env` |
| searxng | 127.0.0.1:8083 | ai.network | `settings.yml:/etc/searxng/settings.yml:ro` | `searxng.env` |
| tika | internal | ai.network | `tika-data:/root/.tika` | `tika.env` |

### auth — `authentik.network`, `auth.slice`

| Service | Ports | Network | Volumes | Config |
|---|---|---|---|---|
| authentik-postgres | internal | authentik.network | `authentik-postgres-data:/var/lib/postgresql/data` | `authentik.env` |
| authentik-server | 127.0.0.1:9000 | authentik.network + monitoring.network | `authentik-media:/media`, `authentik-custom-templates:/templates` | `authentik.env` |
| authentik-worker | internal | authentik.network | media/templates volumes + `authentik-certs:/certs` | `authentik.env` |

### common

| Service | Ports | Network | Volumes | Config |
|---|---|---|---|---|
| homepage | 3057:3000 | default | `homepage-config:/app/config`, rootless podman socket as `docker.sock` | `homepage.env` |

### media_arr — `arr.network`, `arr.slice`

Downloaders/indexers route through Gluetun's VPN network namespace; their host
ports are actually published by `gluetun.container` itself.

| Service | Ports (via gluetun) | Network | Volumes | Config |
|---|---|---|---|---|
| gluetun | 127.0.0.1: 8888, 8082, 6789, 7878, 8989, 8686, 9696, 8191, 1867 | arr.network, `/dev/net/tun` | `gluetun-config:/gluetun` | `gluetun.env` |
| qbittorrent | (8082 UI, via gluetun) | container:gluetun | `qbittorrent-config:/config`, `/mnt/Downloads:/downloads` | `qbittorrent.env` |
| nzbget | (6789, via gluetun) | container:gluetun | `nzbget-config:/config`, `/mnt/Downloads:/downloads` | `nzbget.env` |
| radarr | (7878, via gluetun) | container:gluetun | `radarr-config:/config`, `/mnt/Downloads`, `/mnt/Media/Film:/movies` | `radarr.env` |
| sonarr | (8989, via gluetun) | container:gluetun | `sonarr-config:/config`, `/mnt/Downloads`, `/mnt/Media/Serie-TV:/tv` | `sonarr.env` |
| lidarr | (8686, via gluetun) | container:gluetun | `lidarr-config:/config`, `/mnt/Media/Musica:/music`, `/mnt/Downloads` | `lidarr.env` |
| prowlarr | (9696, via gluetun) | container:gluetun | `prowlarr-config:/config` | `prowlarr.env` |
| flaresolverr | (8191, via gluetun) | container:gluetun | — | `flaresolverr.env` |
| sportarr | (1867, via gluetun) | container:gluetun | `sportarr-config:/config`, `/mnt/Media/Sports:/sports`, `/mnt/Downloads` | `sportarr.env` |
| jellyseerr | 127.0.0.1:5055 | arr.network + jellyfin.network | `jellyseerr-config:/app/config` | `jellyseerr.env` |
| tdarr | 127.0.0.1:8265, 8266 | arr.network + proxy.network, GPU | `tdarr-configs`, `tdarr-logs`, `tdarr-server`, `/mnt/Media:/media`, `~/.local/share/tdarr/temp:/temp` | `tdarr.env` |
| exportarr-lidarr/-prowlarr/-radarr/-sonarr | internal | arr.network + monitoring.network | — | `exportarr-<svc>.env` |
| qbittorrent-exporter | internal | arr.network + monitoring.network | — | `qbittorrent-exporter.env` |
| nzbget-exporter | internal | arr.network + monitoring.network | — | `nzbget-exporter.env` |

### media_immich — `immich.network`, `immich.slice`

| Service | Ports | Network | Volumes | Config |
|---|---|---|---|---|
| immich-postgres | internal | immich.network | `immich-postgres-data:/var/lib/postgresql/data` | `immich-postgres.env` |
| immich-redis | internal | immich.network | — | — |
| immich-machine-learning | internal | immich.network | `immich-model-cache:/cache` | — |
| immich-server | 127.0.0.1:2283 | immich.network, GPU | `/mnt/Media/Foto/immich:/usr/src/app/upload`, `/etc/localtime:ro` | `immich.env` |

### media_jellyfin — `jellyfin.network`, `jellyfin.slice`

| Service | Ports | Network | Volumes | Config |
|---|---|---|---|---|
| jellyfin | 127.0.0.1:8096 | jellyfin.network, GPU | `jellyfin-config:/config`, `/mnt/Media:/media` | `jellyfin.env` |
| jellyfin-exporter | internal | jellyfin.network + monitoring.network | — | `jellyfin-exporter.env` |

Also ships `update-egr.service`/`.timer`, a daily unit unrelated to the
containers above (updates an IPTV EPG file).

### monitoring — `monitoring.network`, `monitoring.slice`

| Service | Ports | Network | Volumes | Config |
|---|---|---|---|---|
| alertmanager | internal | monitoring.network | `alertmanager-data`, `alertmanager.yaml:ro` | — |
| alloy | 127.0.0.1:12345, 14317 | monitoring.network | `config.alloy:ro`, `/var/log/journal:ro`, podman socket | `alloy.env` |
| grafana | 127.0.0.1:3000 | monitoring.network | `grafana-data`, provisioning dir `:ro` | `grafana.env` |
| loki | internal | monitoring.network | `loki-data`, `loki.yaml:ro` | — |
| mimir | internal | monitoring.network | `mimir-data`, `mimir.yaml:ro`, `rules:ro` | — |
| node-exporter | internal | monitoring.network | `/proc`, `/sys`, `/:/host/root:ro,rslave`, dbus socket | — |
| ntfy | 127.0.0.1:8091 | monitoring.network | `ntfy-data:/var/lib/ntfy`, `server.yml:ro` | `ntfy.env` |
| nvidia-gpu-exporter | internal | monitoring.network, GPU | `/usr/bin/nvidia-smi:ro` | `nvidia-gpu-exporter.env` |
| podman-exporter | internal | monitoring.network | podman socket | `podman-exporter.env` |
| pyroscope | internal | monitoring.network | `pyroscope-data`, `pyroscope.yaml:ro` | — |
| tempo | 127.0.0.1:3200, 4317 | monitoring.network | `tempo-data`, `tempo.yaml:ro` | — |

### netcore — `netcore.network`, `netcore.slice`

| Service | Ports | Network | Volumes | Config |
|---|---|---|---|---|
| ddns-updater | internal | netcore.network | `ddns-updater-data:/updater/data` | `ddns.env` |
| pihole | host | host | `pihole-data:/etc/pihole`, `pihole-dnsmasq:/etc/dnsmasq.d` | `pihole.env` |

### office — `office.network`, `office.slice`

| Service | Ports | Network | Volumes | Config |
|---|---|---|---|---|
| freshrss | 127.0.0.1:8183 | office.network + monitoring.network | `freshrss-data`, `freshrss-extensions` | `freshrss.env` |
| vaultwarden | 127.0.0.1:8087 | office.network + monitoring.network | `vaultwarden-data:/data` | `vaultwarden.env` |

### proxy — `proxy.network`, `proxy.slice`

Most proxy-facing services use `Network=host` directly rather than
`proxy.network`.

| Service | Ports | Network | Volumes | Config |
|---|---|---|---|---|
| npmplus | host | host | `npmplus-data:/data`, `geoip-data:/data/goaccess/geoip` | `npmplus.env` |
| crowdsec | host | host | `crowdsec-conf`, `crowdsec-data`, npmplus nginx logs `:ro` | `crowdsec.env` |
| crowdsec-web-ui | host | host | `crowdsec-web-ui-data:/app/data` | `crowdsec-web-ui.env` |
| geoipupdate | internal | proxy.network | `geoip-data:/usr/share/GeoIP` | `geoipupdate.env` |