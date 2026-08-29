# immich.target

Immich — self-hosted photo and video management with GPU-accelerated machine
learning (face / object recognition, smart search). Medium tier.

- **Deploy:** `make deploy-immich`
- **Parent:** `media.target`
- **Source:** `ansible/sdtargets/immich/`

## Services

| Service | Image | Version | Exposure | Volumes |
|---|---|---|---|---|
| immich-server | `ghcr.io/immich-app/immich-server` | release (digest) | `127.0.0.1:2283`, GPU | `/mnt/Media/Foto/immich:/usr/src/app/upload`, `/etc/localtime:ro` |
| immich-machine-learning | `ghcr.io/immich-app/immich-machine-learning` | release (digest) | internal | `immich-model-cache:/cache` |
| immich-postgres | `ghcr.io/immich-app/postgres` | 14-vectorchord / pgvectors | internal | `immich-postgres-data:/var/lib/postgresql/data` |
| immich-redis | `docker.io/valkey/valkey` | 9.1.1 | internal | — |

## Networking

`immich.network` (bridge) for all four containers. `immich-server` also gets the
NVIDIA GPU (CDI, `compute,video,utility`). NPMplus fronts `127.0.0.1:2283`.

## Storage

Originals live on the NAS mount `/mnt/Media/Foto/immich`. The Postgres image
bundles the `vectorchord` / `pgvecto.rs` extensions Immich needs for vector
search — its tag pattern is constrained in `versions.yml` so updates stay within
the `14-vectorchord*-pgvectors*` family.

## Resource slice — `immich.slice` (tier: medium)

| CPUWeight run/startup | CPUQuota | Memory min/low/high/max | Swap |
|---|---|---|---|
| 150 / 300 | 800% | 256M / 512M / 6G / 8G | 4G |

Large swap tolerance — ML model load and background jobs are bursty and
swap-friendly. `gomaxprocs`/`omp_num_threads` capped at 4.

## Configuration

`config.yml` — DB/redis hostnames, `GOMAXPROCS`/`OMP_NUM_THREADS`, NVIDIA
device/capability vars. DB password and Immich secrets in `vault.yml`. Env files
→ `~/.config/media/immich/`.

## Backup — `backup-immich.timer`, daily 04:30

Config tree + `pg_dump` of `immich-postgres`. **The photo library itself is not
backed up by this timer** — it relies on the NAS's own protection of
`/mnt/Media`.
