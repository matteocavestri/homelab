# arr.target

Media automation: *arr managers (Radarr / Sonarr / Lidarr / Prowlarr /
Sportarr), download clients (qBittorrent, NZBGet), request UI (Jellyseerr),
transcoding (Tdarr) and Prometheus exporters. All download/index traffic is
tunnelled through a Gluetun VPN gateway. Lowest-priority tier.

- **Deploy:** `make deploy-arr`
- **Parent:** `media.target`
- **Source:** `ansible/sdtargets/arr/`

## VPN routing

`gluetun` (ProtonVPN, WireGuard, Switzerland, port-forwarding on) owns the
network namespace. qBittorrent, NZBGet, Radarr, Sonarr, Lidarr, Prowlarr,
Flaresolverr and Sportarr run with `Network=container:gluetun` — they have **no
network stack of their own**, and their host ports are actually published by
`gluetun.container` on `127.0.0.1`:

| Port (127.0.0.1) | Service |
|---|---|
| 8888 | Gluetun HTTP proxy |
| 8082 | qBittorrent WebUI |
| 6789 | NZBGet |
| 7878 | Radarr |
| 8989 | Sonarr |
| 8686 | Lidarr |
| 9696 | Prowlarr |
| 8191 | Flaresolverr |
| 1867 | Sportarr |

Gluetun also enables Shadowsocks + an HTTP proxy (stealth) and unblocks
`news.usenetserver.com` for Usenet.

## Services

| Service | Image | Version | Network | Volumes |
|---|---|---|---|---|
| gluetun | `docker.io/qmcgaw/gluetun` | v3.41.3 | `arr.network`, `/dev/net/tun`, `NET_ADMIN` | `gluetun-config:/gluetun` |
| qbittorrent | `lscr.io/linuxserver/qbittorrent` | 5.1.4-r3-ls453 | `container:gluetun` | `qbittorrent-config`, `/mnt/Downloads` |
| nzbget | `lscr.io/linuxserver/nzbget` | latest (digest) | `container:gluetun` | `nzbget-config`, `/mnt/Downloads` |
| radarr | `lscr.io/linuxserver/radarr` | latest (digest) | `container:gluetun` | `radarr-config`, `/mnt/Downloads`, `/mnt/Media/Film:/movies` |
| sonarr | `lscr.io/linuxserver/sonarr` | latest (digest) | `container:gluetun` | `sonarr-config`, `/mnt/Downloads`, `/mnt/Media/Serie-TV:/tv` |
| lidarr | `lscr.io/linuxserver/lidarr` | 3.1.0.4875-ls40 | `container:gluetun` | `lidarr-config`, `/mnt/Media/Musica:/music`, `/mnt/Downloads` |
| prowlarr | `lscr.io/linuxserver/prowlarr` | latest (digest) | `container:gluetun` | `prowlarr-config` |
| flaresolverr | `ghcr.io/flaresolverr/flaresolverr` | v3.5.0 | `container:gluetun` | — |
| sportarr | `docker.io/sportarr/sportarr` | 4.1.5.1115 | `container:gluetun` | `sportarr-config`, `/mnt/Media/Sports:/sports`, `/mnt/Downloads` |
| jellyseerr | `ghcr.io/seerr-team/seerr` | v3.4.1 | `arr.network` + `jellyfin.network` | `jellyseerr-config` |
| tdarr | `ghcr.io/haveagitgat/tdarr` | latest (digest) | `arr.network` + `proxy.network`, GPU | `tdarr-configs/-logs/-server`, `/mnt/Media:/media`, `~/.local/share/tdarr/temp:/temp` |
| exportarr-{radarr,sonarr,lidarr,prowlarr} | `ghcr.io/onedr0p/exportarr` | v2.3.0 | `arr.network` + `monitoring.network` | — |
| qbittorrent-exporter | `ghcr.io/martabal/qbittorrent-exporter` | v2.0.2 | `arr.network` + `monitoring.network` | — |
| nzbget-exporter | `docker.io/frebib/nzbget-exporter` | latest (digest) | `arr.network` + `monitoring.network` | — |

- **Jellyseerr** — `127.0.0.1:5055`, bridges to `jellyfin.network` to talk to
  Jellyfin. Uses Authentik OIDC.
- **Tdarr** — `127.0.0.1:8265` (UI) / `8266` (server), NVIDIA GPU, internal
  node `LeonardoNode`. Not routed through the VPN.
- **Exporters** — reach the *arr apps via `http://gluetun:<port>` and expose
  metrics on `monitoring.network` (ports 9707–9710).

## Resource slice — `arr.slice` (tier: low)

| CPUWeight run/startup | CPUQuota | Memory min/low/high/max | Swap |
|---|---|---|---|
| 50 / 100 | 800% | 256M / 512M / 6G / 8G | 4G |

Per-container caps: `qbittorrent` → `MemoryMax=4G` / `MemorySwapMax=2G`;
`tdarr` → `CPUQuota=400%`.

## Configuration

`config.yml` — Gluetun VPN provider/type/country and proxy toggles; exporter
ports + upstream URLs; download-client base URLs / usernames; Jellyseerr &
Flaresolverr log levels; Sportarr PUID/PGID/umask; Tdarr node/ffmpeg/GPU
settings. VPN WireGuard keys, API keys and client passwords in `vault.yml`.
Env files → `~/.config/media/arr/`.

## Backup — `backup-arr.timer`, daily 03:45

Config tree + every `*-config` volume (gluetun, sonarr, radarr, lidarr,
prowlarr, nzbget, qbittorrent, jellyseerr, sportarr) + `tdarr-configs`,
`tdarr-logs`, `tdarr-server`. Downloads and media libraries are not included.
