# homelab

Ansible playbook that deploys a Podman Quadlet container stack (rootless,
`systemd --user`) on AlmaLinux 10.

## Layout

```
Makefile                   # deploy / deploy-<target> / diff / check / updates / list
ansible/
  ansible.cfg
  inventory/hosts.yml
  deploy.yml               # deploy the stack (whole, or --tags <sdtarget>)
  check.yml                # read-only unit status report
  group_vars/all/
    versions.yml           # image tag/digest per container
    common.yml             # shared config (TZ, admin/ACME email)
    vault.yml              # secrets (ansible-vault encrypted)
  tasks/
    deploy_common.yml      # backup script, notify@ units, podman drop-ins
    deploy_target.yml      # generic per-sdtarget deploy engine
    report_status.yml      # check.yml body
  sdtargets/
    common/                # shared assets, not a systemd target
      files/backup-target.sh
      templates/           # notify@ units, podman drop-ins
    <sdtarget>/            # ai auth arr immich jellyfin monitoring netcore
      config.yml           #   office proxy infrastructure media
      manifest.yml         # config.yml  = slice limits + app config
      templates/*.j2       # manifest.yml = env/config file map + restarts
scripts/
  check_updates.py         # skopeo-based image update checker
```

Each `sdtargets/<name>/` is one systemd `.target`. Quadlet and systemd unit
templates (`*.container/.network/.target/.slice/.service/.timer.j2`) are deployed
by filename convention; `env` and other config files are declared explicitly in
`manifest.yml` with their destination, mode and which units to restart on change.

## Usage

The `Makefile` at the repo root wraps the common commands (`--ask-vault-pass` is
added automatically, and it `cd`s into `ansible/` for you).

### Secrets

`ansible/group_vars/all/vault.yml` is encrypted with `ansible-vault`:

```bash
cd ansible
ansible-vault edit group_vars/all/vault.yml
```

### Deploy

```bash
make deploy                 # whole stack
make deploy-monitoring      # one sdtarget (== ansible-playbook deploy.yml --tags monitoring)
make diff                   # dry run (--check --diff)
make list                   # list deployable sdtargets

# or call ansible directly, from ansible/:
ansible-playbook deploy.yml --ask-vault-pass
ansible-playbook deploy.yml --tags monitoring,ai --ask-vault-pass
```

The playbook doesn't enable/start service targets on first deploy — after the
first run:

```bash
systemctl --user enable --now <name>.target
loginctl enable-linger <user>
```

Backup timers (`backup-<sdtarget>.timer`) are the exception: `make deploy` keeps
them enabled and started.

### Check status

```bash
make check        # == ansible-playbook check.yml --ask-vault-pass
```

Read-only: reports `is-enabled`/`is-active` for every sdtarget `.target` and
every backup/EGR `.timer`, lists failed units, and fails if a timer is not
enabled+active or a unit has failed.

### Check for image updates

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r scripts/requirements.txt   # requires skopeo

python3 scripts/check_updates.py                 # table
python3 scripts/check_updates.py --json           # machine-readable
python3 scripts/check_updates.py --only jellyfin  # single image
python3 scripts/check_updates.py --apply          # write updates to versions.yml
python3 scripts/check_updates.py --refresh        # ignore the 6h tag-list cache
```

`semver` entries only compare a pinned tag against tags of the same shape (so
`3.1.0.4875-ls39` tracks `…-ls40`, never a stray `8.1.2135` or a `nightly-`/
`amd64-` variant), and a detected update must also be a genuinely newer image.
Tag lists are cached under `~/.cache/homelab-check-updates/` for 6h; the first
run of the day is slow (open-webui alone publishes ~39k tags), later runs are
seconds.

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

## Services

Ports are host-published bindings only; a service reachable solely on its
`.network` from other containers is marked *internal*. Image tags/digests are
managed in `ansible/group_vars/all/versions.yml` and checked with
`scripts/check_updates.py`.

Each target's containers run in a dedicated `systemd` slice (`Slice=<name>.slice`,
limits in `sdtargets/<name>/config.yml`). The **Resource slice** table under each
target lists them: `CPUWeight` run/startup (relative CPU share under contention,
1–10000), `CPUQuota` (hard CPU ceiling, 100% = 1 thread), `AllowedCPUs` (thread
pinning), memory `MemoryMin`/`MemoryLow`/`MemoryHigh`/`MemoryMax`
(hard-guaranteed / soft-guaranteed / throttle / OOM ceiling), and `MemorySwapMax`.
Host: 56 threads, 32 GB RAM, 12 GB zram + 16 GB LVM swap. Tiers — **high**
(netcore, proxy, auth, monitoring: keep alive under pressure), **medium**
(immich, jellyfin, office), **low** (ai, arr: best-effort, compressible).
`infrastructure`/`media` have no dedicated slice.

### netcore.target

**Resource slice** — `netcore.slice`, tier: high

| CPUWeight (run/startup) | CPUQuota | AllowedCPUs | Memory min/low/high/max | Swap |
|---|---|---|---|---|
| 500 / 900 | 200% | — | 128M / 256M / 640M / 1G | 256M |

| Service | Image | Version | Ports | Network | Volumes | Config |
|---|---|---|---|---|---|---|
| ddns-updater | `docker.io/qmcgaw/ddns-updater` | 2.10.0 | internal | netcore.network | `ddns-updater-data:/updater/data` | `ddns.env` |
| pihole | `docker.io/pihole/pihole` | 2026.07.2 | host | host | `pihole-data:/etc/pihole`, `pihole-dnsmasq:/etc/dnsmasq.d` | `pihole.env` |

### proxy.target

**Resource slice** — `proxy.slice`, tier: high

| CPUWeight (run/startup) | CPUQuota | AllowedCPUs | Memory min/low/high/max | Swap |
|---|---|---|---|---|
| 500 / 900 | 800% | — | 256M / 512M / 2G / 3G | 512M |

Most proxy-facing services use `Network=host` directly rather than
`proxy.network`.

| Service | Image | Version | Ports | Network | Volumes | Config |
|---|---|---|---|---|---|---|
| npmplus | `docker.io/zoeyvid/npmplus` | 2026-07-24-r1 | host | host | `npmplus-data:/data`, `geoip-data:/data/goaccess/geoip` | `npmplus.env` |
| crowdsec | `docker.io/crowdsecurity/crowdsec` | v1.7.8 | host | host | `crowdsec-conf`, `crowdsec-data`, npmplus nginx logs `:ro` | `crowdsec.env` |
| crowdsec-web-ui | `ghcr.io/theduffman85/crowdsec-web-ui` | 2026.8.1 | host | host | `crowdsec-web-ui-data:/app/data` | `crowdsec-web-ui.env` |
| geoipupdate | `ghcr.io/maxmind/geoipupdate` | v8.0.0 | internal | proxy.network | `geoip-data:/usr/share/GeoIP` | `geoipupdate.env` |

### auth.target

**Resource slice** — `auth.slice`, tier: high

| CPUWeight (run/startup) | CPUQuota | AllowedCPUs | Memory min/low/high/max | Swap |
|---|---|---|---|---|
| 500 / 900 | 1400% | — | 384M / 768M / 3500M / 4G | 1G |

| Service | Image | Version | Ports | Network | Volumes | Config |
|---|---|---|---|---|---|---|
| authentik-postgres | `docker.io/library/postgres` | 17-alpine (digest-tracked) | internal | authentik.network | `authentik-postgres-data:/var/lib/postgresql/data` | `authentik.env` |
| authentik-server | `ghcr.io/goauthentik/server` | 2026.8.0, pinned by digest | 127.0.0.1:9000 | authentik.network + monitoring.network | `authentik-media:/media`, `authentik-custom-templates:/templates` | `authentik.env` |
| authentik-worker | `ghcr.io/goauthentik/server` | 2026.8.0, pinned by digest | internal | authentik.network | media/templates volumes + `authentik-certs:/certs` | `authentik.env` |

### monitoring.target

**Resource slice** — `monitoring.slice`, tier: high

| CPUWeight (run/startup) | CPUQuota | AllowedCPUs | Memory min/low/high/max | Swap |
|---|---|---|---|---|
| 500 / 900 | 800% | — | 512M / 1G / 6G / 8G | 2G |

| Service | Image | Version | Ports | Network | Volumes | Config |
|---|---|---|---|---|---|---|
| alertmanager | `docker.io/prom/alertmanager` | v0.34.0 | internal | monitoring.network | `alertmanager-data`, `alertmanager.yaml:ro` | — |
| alloy | `docker.io/grafana/alloy` | v1.19.0 | 127.0.0.1:12345, 14317 | monitoring.network | `config.alloy:ro`, `/var/log/journal:ro`, podman socket | `alloy.env` |
| grafana | `docker.io/grafana/grafana` | 13.2.0 | 127.0.0.1:3000 | monitoring.network | `grafana-data`, provisioning dir `:ro` | `grafana.env` |
| loki | `docker.io/grafana/loki` | 3.7.6 | internal | monitoring.network | `loki-data`, `loki.yaml:ro` | — |
| memcached | `docker.io/library/memcached` | 1.6.43 | internal | monitoring.network | — | — (results cache for mimir's query-frontend) |
| mimir | `docker.io/grafana/mimir` | 3.2.0 | internal | monitoring.network | `mimir-data`, `mimir.yaml:ro`, `rules:ro` | — |
| node-exporter | `docker.io/prom/node-exporter` | v1.12.1 | internal | monitoring.network | `/proc`, `/sys`, `/:/host/root:ro,rslave`, dbus socket | — |
| ntfy | `docker.io/binwiederhier/ntfy` | v2.27.0 | 127.0.0.1:8091 | monitoring.network | `ntfy-data:/var/lib/ntfy`, `server.yml:ro` | `ntfy.env` |
| nvidia-gpu-exporter | `docker.io/utkuozdemir/nvidia_gpu_exporter` | 1.14.0 | internal | monitoring.network, GPU | `/usr/bin/nvidia-smi:ro` | `nvidia-gpu-exporter.env` |
| podman-exporter | `quay.io/navidys/prometheus-podman-exporter` | latest (digest-tracked) | internal | monitoring.network | podman socket | `podman-exporter.env` |
| pyroscope | `docker.io/grafana/pyroscope` | 2.3.0 (digest-tracked) | internal | monitoring.network | `pyroscope-data`, `pyroscope.yaml:ro` | — |
| tempo | `docker.io/grafana/tempo` | 3.0.3 | 127.0.0.1:3200, 4317 | monitoring.network | `tempo-data`, `tempo.yaml:ro` | — |

### common (infrastructure.target)

**Resource slice** — none; containers run in the default user slice.

| Service | Image | Version | Ports | Network | Volumes | Config |
|---|---|---|---|---|---|---|
| homarr | `ghcr.io/homarr-labs/homarr` | v1.76.0 | 7575:7575 | pasta, host loopback mapped to 169.254.1.2 | `homarr-data:/appdata`, rootless podman socket as `docker.sock` | `homarr.env` |
| homepage | `ghcr.io/gethomepage/homepage` | v2.1.2 | 3057:3000 | default | `homepage-config:/app/config`, rootless podman socket as `docker.sock` | `homepage.env` |

### ai.target

**Resource slice** — `ai.slice`, tier: low

| CPUWeight (run/startup) | CPUQuota | AllowedCPUs | Memory min/low/high/max | Swap |
|---|---|---|---|---|
| 50 / 100 | 2800% | `0-13,28-41` (NUMA node 0) | 1G / 2G / 20G / 24G | 16G |

| Service | Image | Version | Ports | Network | Volumes | Config |
|---|---|---|---|---|---|---|
| comfyui | `localhost/comfyui-p4` | local build (untracked) | 127.0.0.1:8188 | ai.network, GPU (CDI) | `comfyui-storage:/root` | `comfyui.env` |
| crawl4ai | `docker.io/unclecode/crawl4ai` | 0.9.2 | internal | ai.network | `crawl4ai-data:/home/appuser/.crawl4ai` | `crawl4ai.env` |
| mcpo | `ghcr.io/open-webui/mcpo` | latest (digest-tracked) | internal | ai.network | `mcpo-config.json:/app/config.json:ro`, `~/projects:/projects`, podman socket | — |
| n8n | `docker.io/n8nio/n8n` | 2.37.1 | 127.0.0.1:5678 | ai.network | `n8n-data:/home/node/.n8n` | `n8n.env` |
| ollama | `docker.io/ollama/ollama` | 0.32.15 | 127.0.0.1:11434 | ai.network, GPU | `ollama-data:/root/.ollama` | `ollama.env` |
| openai-edge-tts | `docker.io/travisvn/openai-edge-tts` | latest (digest-tracked) | internal | ai.network | — | `openai-edge-tts.env` |
| openterminal | `ghcr.io/open-webui/open-terminal` | latest (digest-tracked) | internal | ai.network | `open-terminal-data:/home/user` | `openterminal.env` |
| openwebui | `ghcr.io/open-webui/open-webui` | v0.11.0 | 127.0.0.1:8081 | ai.network + monitoring.network | `openwebui-data:/app/backend/data` | `openwebui.env` |
| pipelines | `ghcr.io/open-webui/pipelines` | main (digest-tracked) | internal | ai.network | `pipelines-data:/app/pipelines` | `pipelines.env` |
| qdrant | `docker.io/qdrant/qdrant` | v1.19 | 127.0.0.1:6333 | ai.network | `qdrant-data:/qdrant/storage` | `qdrant.env` |
| searxng | `docker.io/searxng/searxng` | latest (digest-tracked) | 127.0.0.1:8083 | ai.network | `settings.yml:/etc/searxng/settings.yml:ro` | `searxng.env` |
| tika | `docker.io/apache/tika` | 4.0.0-1-full | internal | ai.network | `tika-data:/root/.tika` | `tika.env` |

### arr.target

**Resource slice** — `arr.slice`, tier: low

| CPUWeight (run/startup) | CPUQuota | AllowedCPUs | Memory min/low/high/max | Swap |
|---|---|---|---|---|
| 50 / 100 | 800% | — | 256M / 512M / 6G / 8G | 4G |

`qbittorrent` further caps itself at `MemoryMax=4G` / `MemorySwapMax=2G`,
`tdarr` at `CPUQuota=400%`.

Downloaders/indexers route through Gluetun's VPN network namespace; their host
ports are actually published by `gluetun.container` itself.

| Service | Image | Version | Ports (via gluetun) | Network | Volumes | Config |
|---|---|---|---|---|---|---|
| gluetun | `docker.io/qmcgaw/gluetun` | v3.41.3 | 127.0.0.1: 8888, 8082, 6789, 7878, 8989, 8686, 9696, 8191, 1867 | arr.network, `/dev/net/tun` | `gluetun-config:/gluetun` | `gluetun.env` |
| qbittorrent | `lscr.io/linuxserver/qbittorrent` | 5.1.4-r3-ls453 | (8082 UI, via gluetun) | container:gluetun | `qbittorrent-config:/config`, `/mnt/Downloads:/downloads` | `qbittorrent.env` |
| nzbget | `lscr.io/linuxserver/nzbget` | latest (digest-tracked) | (6789, via gluetun) | container:gluetun | `nzbget-config:/config`, `/mnt/Downloads:/downloads` | `nzbget.env` |
| radarr | `lscr.io/linuxserver/radarr` | latest (digest-tracked) | (7878, via gluetun) | container:gluetun | `radarr-config:/config`, `/mnt/Downloads`, `/mnt/Media/Film:/movies` | `radarr.env` |
| sonarr | `lscr.io/linuxserver/sonarr` | latest (digest-tracked) | (8989, via gluetun) | container:gluetun | `sonarr-config:/config`, `/mnt/Downloads`, `/mnt/Media/Serie-TV:/tv` | `sonarr.env` |
| lidarr | `lscr.io/linuxserver/lidarr` | latest (digest-tracked) | (8686, via gluetun) | container:gluetun | `lidarr-config:/config`, `/mnt/Media/Musica:/music`, `/mnt/Downloads` | `lidarr.env` |
| prowlarr | `lscr.io/linuxserver/prowlarr` | latest (digest-tracked) | (9696, via gluetun) | container:gluetun | `prowlarr-config:/config` | `prowlarr.env` |
| flaresolverr | `ghcr.io/flaresolverr/flaresolverr` | v3.5.0 | (8191, via gluetun) | container:gluetun | — | `flaresolverr.env` |
| sportarr | `docker.io/sportarr/sportarr` | 4.1.3.1113 | (1867, via gluetun) | container:gluetun | `sportarr-config:/config`, `/mnt/Media/Sports:/sports`, `/mnt/Downloads` | `sportarr.env` |
| jellyseerr | `ghcr.io/seerr-team/seerr` | v3.4.1 | 127.0.0.1:5055 | arr.network + jellyfin.network | `jellyseerr-config:/app/config` | `jellyseerr.env` |
| tdarr | `ghcr.io/haveagitgat/tdarr` | latest (digest-tracked) | 127.0.0.1:8265, 8266 | arr.network + proxy.network, GPU | `tdarr-configs`, `tdarr-logs`, `tdarr-server`, `/mnt/Media:/media`, `~/.local/share/tdarr/temp:/temp` | `tdarr.env` |
| exportarr-lidarr/-prowlarr/-radarr/-sonarr | `ghcr.io/onedr0p/exportarr` | v2.3.0 | internal | arr.network + monitoring.network | — | `exportarr-<svc>.env` |
| qbittorrent-exporter | `ghcr.io/martabal/qbittorrent-exporter` | v2.0.2 | internal | arr.network + monitoring.network | — | `qbittorrent-exporter.env` |
| nzbget-exporter | `docker.io/frebib/nzbget-exporter` | latest (digest-tracked) | internal | arr.network + monitoring.network | — | `nzbget-exporter.env` |

### immich.target

**Resource slice** — `immich.slice`, tier: medium

| CPUWeight (run/startup) | CPUQuota | AllowedCPUs | Memory min/low/high/max | Swap |
|---|---|---|---|---|
| 150 / 300 | 800% | — | 256M / 512M / 6G / 8G | 4G |

| Service | Image | Version | Ports | Network | Volumes | Config |
|---|---|---|---|---|---|---|
| immich-postgres | `ghcr.io/immich-app/postgres` | 14-vectorchord0.4.3-pgvectors0.2.0 | internal | immich.network | `immich-postgres-data:/var/lib/postgresql/data` | `immich-postgres.env` |
| immich-redis | `docker.io/valkey/valkey` | 9.1.1 | internal | immich.network | — | — |
| immich-machine-learning | `ghcr.io/immich-app/immich-machine-learning` | release (digest-tracked) | internal | immich.network | `immich-model-cache:/cache` | — |
| immich-server | `ghcr.io/immich-app/immich-server` | release (digest-tracked) | 127.0.0.1:2283 | immich.network, GPU | `/mnt/Media/Foto/immich:/usr/src/app/upload`, `/etc/localtime:ro` | `immich.env` |

### jellyfin.target

**Resource slice** — `jellyfin.slice`, tier: medium

| CPUWeight (run/startup) | CPUQuota | AllowedCPUs | Memory min/low/high/max | Swap |
|---|---|---|---|---|
| 150 / 300 | 800% | — | 256M / 512M / 3G / 4G | 2G |

| Service | Image | Version | Ports | Network | Volumes | Config |
|---|---|---|---|---|---|---|
| jellyfin | `docker.io/jellyfin/jellyfin` | 10.11.11 | 127.0.0.1:8096 | jellyfin.network, GPU | `jellyfin-config:/config`, `/mnt/Media:/media` | `jellyfin.env` |
| jellyfin-exporter | `docker.io/rebelcore/jellyfin-exporter` | v1.5.2 | internal | jellyfin.network + monitoring.network | — | `jellyfin-exporter.env` |

Also ships `update-egr.service`/`.timer`, a daily unit unrelated to the
containers above (updates an IPTV EPG file).

### office.target

**Resource slice** — `office.slice`, tier: medium

| CPUWeight (run/startup) | CPUQuota | AllowedCPUs | Memory min/low/high/max | Swap |
|---|---|---|---|---|
| 150 / 300 | 400% | — | 128M / 256M / 1536M / 2G | 1G |

| Service | Image | Version | Ports | Network | Volumes | Config |
|---|---|---|---|---|---|---|
| freshrss | `docker.io/freshrss/freshrss` | 1.29.1 | 127.0.0.1:8183 | office.network + monitoring.network | `freshrss-data`, `freshrss-extensions` | `freshrss.env` |
| vaultwarden | `docker.io/vaultwarden/server` | 1.37.2 | 127.0.0.1:8087 | office.network + monitoring.network | `vaultwarden-data:/data` | `vaultwarden.env` |