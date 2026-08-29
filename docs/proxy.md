# proxy.target

Edge reverse proxy, TLS termination and web application firewall. High-priority
tier — this is the request path for every externally reachable service.

- **Deploy:** `make deploy-proxy`
- **Parent:** `infrastructure.target`
- **Source:** `ansible/sdtargets/proxy/`

## Services

| Service | Image | Version | Exposure | Volumes | Config |
|---|---|---|---|---|---|
| npmplus | `docker.io/zoeyvid/npmplus` | 2026-07-24-r1 | `Network=host` (80/443, admin UI) | `npmplus-data:/data`, `geoip-data:/data/goaccess/geoip` | `npmplus.env` |
| crowdsec | `docker.io/crowdsecurity/crowdsec` | v1.7.8 | `Network=host` (LAPI :8080, metrics :6060) | `crowdsec-conf`, `crowdsec-data`, npmplus nginx logs `:ro` | `crowdsec.env` |
| crowdsec-web-ui | `ghcr.io/theduffman85/crowdsec-web-ui` | 2026.8.2 | `Network=host` (:3007) | `crowdsec-web-ui-data:/app/data` | `crowdsec-web-ui.env` |
| geoipupdate | `ghcr.io/maxmind/geoipupdate` | v8.0.0 | internal | `geoip-data:/usr/share/GeoIP` | `geoipupdate.env` |

Most proxy services use `Network=host` directly rather than `proxy.network`.

## Data flow

- **NPMplus** terminates TLS (ACME / Let's Encrypt, email
  `matteo.cavestri@protonmail.ch`), runs 4 nginx workers with the GeoIP2 module,
  and forwards to backend containers on their loopback-published ports.
- **CrowdSec** parses NPMplus' nginx logs (`:ro` mount), applies the
  `ZoeyVid/npmplus` collection, and exposes its LAPI on `127.0.0.1:8080`;
  NPMplus enforces decisions as the bouncer.
- **geoipupdate** refreshes MaxMind `GeoLite2-Country/City/ASN` every 24h into
  the shared `geoip-data` volume consumed by both NPMplus and CrowdSec.

## Resource slice — `proxy.slice` (tier: high)

| CPUWeight run/startup | CPUQuota | Memory min/low/high/max | Swap |
|---|---|---|---|
| 500 / 900 | 800% | 256M / 512M / 2G / 3G | 512M |

## Configuration

`ansible/sdtargets/proxy/config.yml` — non-secret knobs only (MaxMind
`account_id`, edition IDs, NPMplus worker count / logrotate / GeoIP2 module,
CrowdSec collections, web-UI port and LAPI URLs). API keys, passwords and the
MaxMind license live in `vault.yml`. Env files render under
`~/.config/infrastructure/proxy/<service>/`.

## Backup — `backup-proxy.timer`, daily 03:00

Config tree + `npmplus-data`, `crowdsec-conf`, `crowdsec-data`, `geoip-data`.
