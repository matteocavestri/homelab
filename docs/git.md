# git.target

Forgejo git forge with PostgreSQL and a Forgejo Actions runner. Medium tier.
Attached directly to `default.target`.

- **Deploy:** `make deploy-git`
- **Parent:** `default.target`
- **Source:** `ansible/sdtargets/git/`

## Services

| Service | Image | Version | Exposure | Volumes |
|---|---|---|---|---|
| forgejo | `codeberg.org/forgejo/forgejo` | 17-rootless (digest) | `127.0.0.1:8085` (HTTP), `:2222` (SSH) | `forgejo-data:/var/lib/gitea`, `forgejo-config:/etc/gitea` |
| forgejo-postgres | `docker.io/library/postgres` | 17-alpine (digest) | internal | `forgejo-postgres-data` |
| forgejo-runner | `data.forgejo.org/forgejo/runner` | 13 (digest) | internal | `forgejo-runner-data:/data`, host podman socket |

## Networking

`git.network` (bridge). NPMplus fronts `https://git.cavestrihome.com` →
`127.0.0.1:8085`. Git over SSH: `ssh://git@git.cavestrihome.com:2222/...`
(forward port 2222 on the router for access outside the LAN). The runner talks to
Forgejo internally at `http://forgejo:3000`.

## Runner

The runner uses the **host user's rootless podman API socket**
(`/run/user/1000/podman/podman.sock`, mounted at the same path) as its Docker
daemon, and runs as `User=0` inside the rootless userns (= the unprivileged host
user). Job containers share that socket, so **a job can control every container of
the user and mount host paths** — only run trusted repos. Cache server disabled.

Prerequisite: `systemctl --user enable --now podman.socket`.

## First-time setup

1. Fill `vault_forgejo` in `vault.yml` (see `vault.yml.example`), `make deploy-git`,
   then `systemctl --user enable --now git.target`.
2. NPMplus proxy host `git.cavestrihome.com` → `127.0.0.1:8085` (websockets on, TLS).
3. Admin user:
   `podman exec forgejo forgejo admin user create --admin --username <u> --email <e> --random-password`
4. Authentik: create an OAuth2/OIDC provider + application `forgejo`, redirect URI
   `https://git.cavestrihome.com/user/oauth2/authentik/callback`. Then:
   `podman exec forgejo forgejo admin auth add-oauth --name authentik --provider openidConnect --key <client_id> --secret <client_secret> --auto-discover-url https://auth.cavestrihome.com/application/o/forgejo/.well-known/openid-configuration --scopes "openid email profile"`
5. Register the runner (the secret must match `vault_forgejo.runner_secret`):
   `podman exec forgejo forgejo forgejo-cli actions register --secret <runner_secret> --scope <user-or-org>`
   then `systemctl --user restart forgejo-runner` (entrypoint runs
   `create-runner-file` on first start, then the daemon).

## Auth

OIDC via Authentik (`ALLOW_ONLY_EXTERNAL_REGISTRATION`, auto-registration on); the
local password form stays enabled for the admin. Access is controlled by the
Authentik application bindings.

## Resource slice — `git.slice` (tier: medium)

| CPUWeight run/startup | CPUQuota | Memory min/low/high/max | Swap |
|---|---|---|---|
| 150 / 300 | 400% | 256M / 512M / 2G / 3G | 1G |

Job containers run in the host podman, outside this slice.

## Backup — `backup-git.timer`, daily 05:00

Config tree, `pg_dump` of `forgejo-postgres`, `forgejo-data`, `forgejo-config`,
`forgejo-runner-data`.
