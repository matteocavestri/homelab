# office.target

Personal productivity services: a password manager and an RSS reader. Medium
tier. Attached directly to `default.target`.

- **Deploy:** `make deploy-office`
- **Parent:** `default.target`
- **Source:** `ansible/sdtargets/office/`

## Services

| Service | Image | Version | Exposure | Volumes | Config |
|---|---|---|---|---|---|
| vaultwarden | `docker.io/vaultwarden/server` | 1.37.2 | `127.0.0.1:8087` (+ `monitoring.network`) | `vaultwarden-data:/data` | `vaultwarden.env` |
| freshrss | `docker.io/freshrss/freshrss` | 1.29.1 | `127.0.0.1:8183` (+ `monitoring.network`) | `freshrss-data`, `freshrss-extensions` | `freshrss.env` |

## Networking

`office.network` (bridge); both containers also join `monitoring.network` for
scraping. NPMplus fronts them at `https://pass.cavestrihome.com` (Vaultwarden,
internal port 8080) and the FreshRSS vhost.

## Auth

- **Vaultwarden:** own account system, `signups_allowed: false`.
- **FreshRSS:** Authentik OIDC (`freshrss` app slug), username claim
  `preferred_username`, honours `X-Forwarded-*` headers from NPMplus.

## Resource slice — `office.slice` (tier: medium)

| CPUWeight run/startup | CPUQuota | Memory min/low/high/max | Swap |
|---|---|---|---|
| 150 / 300 | 400% | 128M / 256M / 1536M / 2G | 1G |

Low-traffic, swap-tolerant.

## Configuration

`config.yml` — Vaultwarden domain / rocket port / signups flag; FreshRSS OIDC
provider metadata URL, client ID, claims and scopes. Vaultwarden admin token,
FreshRSS OIDC client secret and DB/crypto secrets in `vault.yml`. Env files →
`~/.config/office/`.

## Backup — `backup-office.timer`, daily 04:15

Config tree + `vaultwarden-data`, `freshrss-data`, `freshrss-extensions`.
