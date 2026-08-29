# Homelab — Target documentation

Per-target reference for the Podman Quadlet stack deployed by this repo
(rootless, `systemd --user`, AlmaLinux 10). Each `ansible/sdtargets/<name>/`
directory maps to one systemd `.target`; the pages below document the services,
networking, resource limits, storage and configuration of each.

## Host

| | |
|---|---|
| Inventory host | `homelab` — `192.168.1.250`, SSH user `admin` (rootless, `become: false`) |
| Hardware | 56 threads, 32 GB RAM, 12 GB zram + 16 GB LVM swap |
| Runtime | Podman Quadlet units under `~/.config/containers/systemd`, `systemd --user` |
| Image pinning | `ansible/group_vars/all/versions.yml`, checked by `scripts/check_updates.py` |
| Secrets | `ansible/group_vars/all/vault.yml` (`ansible-vault`) |

## Target tree

```
default.target
├─ infrastructure.target   → netcore, proxy, auth, monitoring
├─ media.target            → jellyfin, arr, immich
├─ office.target
└─ ai.target
```

`infrastructure.target` and `media.target` are pure aggregators (no containers
of their own). `infrastructure.target` also runs Homarr/Homepage directly.

## Pages

| Target | Tier | Purpose |
|---|---|---|
| [netcore](netcore.md) | high | Pi-hole DNS + Dynamic DNS |
| [proxy](proxy.md) | high | NPMplus reverse proxy / WAF, CrowdSec, GeoIP |
| [auth](auth.md) | high | Authentik SSO (OIDC provider for the whole stack) |
| [monitoring](monitoring.md) | high | Grafana / Mimir / Loki / Tempo / Pyroscope / Alertmanager / ntfy |
| [immich](immich.md) | medium | Immich photo management |
| [jellyfin](jellyfin.md) | medium | Jellyfin media server + IPTV EPG job |
| [office](office.md) | medium | Vaultwarden, FreshRSS |
| [ai](ai.md) | low | Open WebUI, Ollama, n8n, ComfyUI, RAG tooling, n8n sandbox |
| [arr](arr.md) | low | *arr media automation behind a Gluetun VPN |
| [infrastructure](infrastructure.md) | — | Aggregator + Homarr / Homepage dashboards |
| [media](media.md) | — | Aggregator target |
| [common](common.md) | — | Shared assets: backup helper, `notify@` units, Podman drop-ins |

## Common operations

```bash
make deploy                 # whole stack
make deploy-<target>        # one target (== ansible-playbook deploy.yml --tags <target>)
make diff                   # dry run (--check --diff)
make check                  # read-only unit status report
make updates                # container image update check

# first deploy only — the playbook never enables service targets itself:
systemctl --user enable --now <target>.target
loginctl enable-linger admin
```

Backup timers (`backup-<target>.timer`) are the exception — `make deploy` keeps
them enabled and started.
