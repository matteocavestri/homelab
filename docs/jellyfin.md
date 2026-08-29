# jellyfin.target

Jellyfin media server with NVIDIA hardware transcoding, plus a metrics exporter
and an unrelated daily IPTV EPG-refresh job. Medium tier.

- **Deploy:** `make deploy-jellyfin`
- **Parent:** `media.target`
- **Source:** `ansible/sdtargets/jellyfin/`

## Services

| Service | Image | Version | Exposure | Volumes |
|---|---|---|---|---|
| jellyfin | `docker.io/jellyfin/jellyfin` | 10.11.11 | `127.0.0.1:8096`, GPU | `jellyfin-config:/config`, `/mnt/Media:/media`, tmpfs `/cache` (2G) |
| jellyfin-exporter | `docker.io/rebelcore/jellyfin-exporter` | v1.5.2 | internal (+ `monitoring.network`) | — |

## Networking

`jellyfin.network` (bridge). `jellyfin-exporter` also joins `monitoring.network`
and scrapes `http://jellyfin:8096`. NPMplus fronts `127.0.0.1:8096`. The
container has a `/health` HTTP healthcheck (`HealthOnFailure=kill`). Also joined
from `arr.target` by `jellyseerr`.

## GPU / transcoding

`AddDevice=nvidia.com/gpu=all`, capabilities `compute,video,utility`. The
transcode scratch area is a 2 GB tmpfs, not a volume.

## Resource slice — `jellyfin.slice` (tier: medium)

| CPUWeight run/startup | CPUQuota | Memory min/low/high/max | Swap |
|---|---|---|---|
| 150 / 300 | 800% | 256M / 512M / 3G / 4G | 2G |

Idle most of the time; transcoding is a burst load.

## EGR IPTV job

`update-egr.service` + `update-egr.timer` (`OnCalendar=daily`, `Persistent=true`)
run `~/iptv/bin/update-egr.sh` to refresh an IPTV EPG file. This is independent
of the containers above; the script and `~/iptv/` tree are not managed by this
repo. The timer is covered by `make check`.

## Configuration

`config.yml` — exporter target URL, NVIDIA device/capability vars. Env files →
`~/.config/media/jellyfin/`.

## Backup — `backup-jellyfin.timer`, daily 03:30

Config tree + `jellyfin-config` volume. Media under `/mnt/Media` is not included
(NAS-protected).
