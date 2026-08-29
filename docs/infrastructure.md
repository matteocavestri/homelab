# infrastructure.target

Aggregator target for the core infrastructure tier, and host of the two
dashboard apps (Homarr, Homepage) that don't warrant a target of their own.

- **Deploy:** `make deploy-infrastructure`
- **Parent:** `default.target`
- **Source:** `ansible/sdtargets/infrastructure/`

## Aggregation

`infrastructure.target` pulls in the high-priority tier:

```
Wants= netcore.target  proxy.target  auth.target  monitoring.target
```

See [netcore](netcore.md), [proxy](proxy.md), [auth](auth.md),
[monitoring](monitoring.md) for those services.

## Dashboard services

No dedicated slice — these run in the default user slice.

| Service | Image | Version | Exposure | Volumes | Config |
|---|---|---|---|---|---|
| homarr | `ghcr.io/homarr-labs/homarr` | v1.76.2 | `7575:7575` | `homarr-data:/appdata`, rootless podman socket as `docker.sock` | `homarr.env` |
| homepage | `ghcr.io/gethomepage/homepage` | v2.1.2 | `3057:3000` | `homepage-config:/app/config`, rootless podman socket as `docker.sock` | `homepage.env` |

Both read the rootless Podman socket to auto-discover containers. Homarr uses
pasta networking with host loopback mapped to `169.254.1.2`; Homepage uses the
default network. `homepage` config: `allowed_hosts`
`gethomepage.dev,home.fmpt.company`, PUID/PGID 1000.

## Configuration

`config.yml` — Homepage `allowed_hosts` + PUID/PGID only. Env files →
`~/.config/homarr/` and `~/.config/homepage/`. Secrets (Homarr encryption key)
in `vault.yml`.

## Backup

No backup timer — dashboard state is low-value and easily rebuilt.
