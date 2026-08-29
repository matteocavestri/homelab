# auth.target

Authentik — the single sign-on / OpenID Connect provider that every other
web service in the stack authenticates against. High-priority tier.

- **Deploy:** `make deploy-auth`
- **Parent:** `infrastructure.target` (`PartOf=`, ordered `After=` proxy)
- **Source:** `ansible/sdtargets/auth/`

## Services

| Service | Image | Version | Exposure | Volumes | Config |
|---|---|---|---|---|---|
| authentik-postgres | `docker.io/library/postgres` | 17-alpine (digest-tracked) | internal | `authentik-postgres-data:/var/lib/postgresql/data` | `authentik.env` |
| authentik-server | `ghcr.io/goauthentik/server` | 2026.8.0 (digest-pinned) | `127.0.0.1:9000` + `monitoring.network` | `authentik-media:/media`, `authentik-custom-templates:/templates` | `authentik.env` |
| authentik-worker | `ghcr.io/goauthentik/server` | 2026.8.0 (digest-pinned) | internal | media / templates volumes + `authentik-certs:/certs` | `authentik.env` |

## Networking

- `authentik.network` (bridge) — server, worker and postgres.
- `authentik-server` also joins `monitoring.network` so Alloy/Mimir can scrape
  its metrics.
- NPMplus publishes it at `https://auth.cavestrihome.com` (also referenced as
  `auth.fmpt.company` by older integrations); backend bind is `127.0.0.1:9000`.

## Consumers (OIDC clients)

Open WebUI, Grafana, FreshRSS, Jellyseerr and others use Authentik application
slugs under `/application/o/<slug>/`. Client IDs/secrets are configured per
consumer target; Authentik-side app/provider definitions are managed in the
Authentik UI, not in this repo.

## Resource slice — `auth.slice` (tier: high)

| CPUWeight run/startup | CPUQuota | Memory min/low/high/max | Swap |
|---|---|---|---|
| 500 / 900 | 1400% | 384M / 768M / 3500M / 4G | 1G |

## Configuration

`ansible/sdtargets/auth/config.yml` — Postgres user/db (`authentik`/`authentik`),
log level, and the ProtonMail SMTP settings (`smtp.protonmail.ch:587`, STARTTLS,
from/username `admin@fmpt.company`). Secret key, admin bootstrap credentials and
DB password are in `vault.yml`. Single env file →
`~/.config/infrastructure/auth/authentik/authentik.env`.

## Backup — `backup-auth.timer`, daily 01:00

Config tree, `pg_dump` of `authentik-postgres`, and the
`authentik-media` / `authentik-custom-templates` / `authentik-certs` volumes.
