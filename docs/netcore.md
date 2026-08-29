# netcore.target

Core network path: local DNS resolution (Pi-hole) and dynamic DNS updates.
Highest-priority tier — kept alive under memory pressure because DNS latency
affects everything else.

- **Deploy:** `make deploy-netcore`
- **Parent:** `infrastructure.target`
- **Source:** `ansible/sdtargets/netcore/`

## Services

| Service | Image | Version | Exposure | Volumes | Config |
|---|---|---|---|---|---|
| pihole | `docker.io/pihole/pihole` | 2026.07.2 | `Network=host` (DNS :53, web :3080) | `pihole-data:/etc/pihole`, `pihole-dnsmasq:/etc/dnsmasq.d` | `pihole.env` |
| ddns-updater | `docker.io/qmcgaw/ddns-updater` | 2.10.0 | internal — `127.0.0.1:8000` in-container | `ddns-updater-data:/updater/data` | `ddns.env` |

## Networking

- `netcore.network` (bridge) is defined but Pi-hole runs on `Network=host` so it
  can bind :53 on the LAN address.
- Pi-hole upstreams: `9.9.9.9;1.1.1.1`, DNSSEC on, conditional reverse lookups
  for `192.168.1.0/24` via `192.168.1.1` (`lan` domain).

## Resource slice — `netcore.slice` (tier: high)

| CPUWeight run/startup | CPUQuota | Memory min/low/high/max | Swap |
|---|---|---|---|
| 500 / 900 | 200% | 128M / 256M / 640M / 1G | 256M |

Small swap allowance — cold-page eviction only, DNS must stay responsive.

## Configuration

`ansible/sdtargets/netcore/config.yml`:

- `pihole` — upstreams, listening mode `all`, `webserver_port: 3080`, DNSSEC,
  reverse-server config for the LAN.
- `ddns_updater` — 5m poll / 5m cooldown, all public-IP fetchers enabled,
  72h config backup to `/updater/data`. Domain/provider records themselves are
  in `vault.yml`.

Env files render to `~/.config/infrastructure/netcore/{pihole,ddns-updater}/`.

## Backup — `backup-netcore.timer`, daily 02:00

Config tree + `ddns-updater-data`, `pihole-data`, `pihole-dnsmasq` volumes,
pushed to `/mnt/Backup/<host>/netcore/`.
