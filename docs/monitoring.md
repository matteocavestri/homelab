# monitoring.target

Full Grafana observability stack — metrics, logs, traces, profiles, alerting and
push notifications. High-priority tier: it must survive an incident in order to
diagnose it.

- **Deploy:** `make deploy-monitoring`
- **Parent:** `infrastructure.target`
- **Source:** `ansible/sdtargets/monitoring/`

## Services

| Service | Image | Version | Exposure | Role |
|---|---|---|---|---|
| grafana | `docker.io/grafana/grafana` | 13.2.0 | `127.0.0.1:3000` | dashboards / UI |
| mimir | `docker.io/grafana/mimir` | 3.2.0 | internal | metrics TSDB (Prometheus-compatible) |
| memcached | `docker.io/library/memcached` | 1.6.45 | internal | Mimir query-frontend results cache |
| loki | `docker.io/grafana/loki` | 3.7.7 | internal | log store |
| tempo | `docker.io/grafana/tempo` | 3.0.3 | `127.0.0.1:3200`, `4317` (OTLP) | trace store |
| pyroscope | `docker.io/grafana/pyroscope` | 2.3.0 (digest) | internal | continuous profiling |
| alertmanager | `docker.io/prom/alertmanager` | v0.34.0 | internal | alert routing |
| ntfy | `docker.io/binwiederhier/ntfy` | v2.28.0 | `127.0.0.1:8091` | push notifications |
| alloy | `docker.io/grafana/alloy` | v1.19.2 | `127.0.0.1:12345`, `14317` | collector (journal, podman, OTLP) |
| node-exporter | `docker.io/prom/node-exporter` | v1.12.1 | internal | host metrics |
| podman-exporter | `quay.io/navidys/prometheus-podman-exporter` | latest (digest) | internal | container metrics |
| nvidia-gpu-exporter | `docker.io/utkuozdemir/nvidia_gpu_exporter` | 1.14.0 | internal | GPU metrics (`nvidia-smi`) |

## Networking

`monitoring.network` (bridge). Other targets attach exporters or app containers
to this network so Alloy/Mimir can reach them: `authentik-server`,
`openwebui`, the `exportarr-*` set, `jellyfin-exporter`, `qbittorrent-exporter`,
`nzbget-exporter`, `freshrss`, `vaultwarden`.

## Pipeline

- **Metrics:** exporters → Mimir (remote-write / scrape) → Grafana. Recording &
  alerting rules in `files/mimir-rules-anonymous/` (authentik, blackbox,
  crowdsec, jellyfin, node-exporter).
- **Logs:** Alloy tails `/var/log/journal` → Loki → Grafana.
- **Traces:** apps → Alloy/Tempo OTLP (`:4317` / `:14317`) → Tempo → Grafana.
- **Profiles:** Pyroscope → Grafana.
- **Alerts:** Mimir ruler → Alertmanager → ntfy topic `systemd-critical`
  (also the sink for the `notify-failure@` / `notify-recovery@` units).

## Auth

Grafana uses Authentik OAuth (`auth_auto_login`, anonymous disabled); role
mapping: `Grafana Admins` → Admin, `Grafana Editors` → Editor, else Viewer.
Public URL `https://monitoring.fmpt.company`.

## Resource slice — `monitoring.slice` (tier: high)

| CPUWeight run/startup | CPUQuota | Memory min/low/high/max | Swap |
|---|---|---|---|
| 500 / 900 | 800% | 512M / 1G / 6G / 8G | 2G |

## Configuration

`config.yml` holds Grafana root URL + OAuth endpoints, ntfy URL/topic/user,
exporter GPU/socket settings. Rendered config files (Alloy `config.alloy`,
`mimir.yaml`, `loki.yaml`, `tempo.yaml`, `pyroscope.yaml`, `alertmanager.yaml`,
`datasources.yaml`, `ntfy server.yml`) and the static Mimir rule files land
under `~/.config/infrastructure/monitoring/<service>/`. Secrets (Grafana admin,
OAuth client secret, ntfy credentials) in `vault.yml`.

## Backup — `backup-monitoring.timer`, daily 04:00

Config tree + data volumes of ntfy, alertmanager, grafana, mimir, loki, tempo,
pyroscope.
