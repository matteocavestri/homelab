# office.target

Personal productivity services: a password manager, an RSS reader and a notes
app. Medium tier. Attached directly to `default.target`.

- **Deploy:** `make deploy-office`
- **Parent:** `default.target`
- **Source:** `ansible/sdtargets/office/`

## Services

| Service | Image | Version | Exposure | Volumes | Config |
|---|---|---|---|---|---|
| vaultwarden | `docker.io/vaultwarden/server` | 1.37.2 | `127.0.0.1:8087` (+ `monitoring.network`) | `vaultwarden-data:/data` | `vaultwarden.env` |
| freshrss | `docker.io/freshrss/freshrss` | 1.29.1 | `127.0.0.1:8183` (+ `monitoring.network`) | `freshrss-data`, `freshrss-extensions` | `freshrss.env` |
| trilium | `docker.io/triliumnext/trilium` | 0.105.0 | `127.0.0.1:8084` (+ `monitoring.network`, `ai.network`) | `trilium-data` | `trilium.env` |

## Networking

`office.network` (bridge); all containers also join `monitoring.network` for
scraping. NPMplus fronts them at `https://pass.cavestrihome.com` (Vaultwarden,
internal port 8080), the FreshRSS vhost, and a Trilium vhost (internal port
8080). Trilium also joins `ai.network` (owned by `ai.target`) so it can reach
`ollama:11434` directly for its AI features.

## Auth

- **Vaultwarden:** own account system, `signups_allowed: false`.
- **FreshRSS:** Authentik OIDC (`freshrss` app slug), username claim
  `preferred_username`, honours `X-Forwarded-*` headers from NPMplus.
- **Trilium:** own built-in login (no OIDC wired up).

## Resource slice — `office.slice` (tier: medium)

| CPUWeight run/startup | CPUQuota | Memory min/low/high/max | Swap |
|---|---|---|---|
| 150 / 300 | 400% | 128M / 256M / 1536M / 2G | 1G |

Low-traffic, swap-tolerant.

## Configuration

`config.yml` — Vaultwarden domain / rocket port / signups flag; FreshRSS OIDC
provider metadata URL, client ID, claims and scopes. Trilium has no
service-specific settings (just `TZ`). Vaultwarden admin token, FreshRSS OIDC
client secret and DB/crypto secrets in `vault.yml`. Env files →
`~/.config/office/`.

## Backup — `backup-office.timer`, daily 04:15

Config tree + `vaultwarden-data`, `freshrss-data`, `freshrss-extensions`,
`trilium-data`.
