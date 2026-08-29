# common

Shared assets used by every target. **Not a systemd target** — it has no
`.target` unit and is not in the `default.target` tree. Deployed by
`tasks/deploy_common.yml` (tag `common`), which runs first on every `make deploy`.

- **Deploy:** runs automatically with `make deploy`; standalone:
  `ansible-playbook deploy.yml --tags common`
- **Source:** `ansible/sdtargets/common/`

## Backup helper — `~/.local/bin/backup-target.sh`

Single script (`files/backup-target.sh`) invoked by each
`backup-<target>.service` with the target name as its argument. Per target it:

1. Verifies `/mnt/Backup` is mounted and writable; takes a per-target `flock`.
2. Stages into `~/.local/share/backup/<target>.<pid>/`.
3. Backs up the config tree (quadlets + target/slice/network units + the
   `~/.config` subtree — layout differs per target, see `config_base_for()`),
   named volumes (`podman unshare tar`), and Postgres DBs (`pg_dump`) as defined
   in the per-target `case` block.
4. `rsync`s archives to `/mnt/Backup/<host>/<target>/`, keeping the last **5**
   (`KEEP=5`).
5. Notifies ntfy — `systemd-info` topic on success, `systemd-critical` (urgent)
   on any error; exits non-zero on failure.

Per-target schedules and contents are summarised in the main `README.md`
("Backups" table) and on each target page.

## Notification units

| Unit | Trigger | ntfy topic | Priority |
|---|---|---|---|
| `notify-failure@.service` | `OnFailure=notify-failure@%n.service` on container units | `${NTFY_TOPIC}` (`systemd-critical`) | urgent |
| `notify-recovery@.service` | recovery hook | `systemd-warning` | default |

Both source `~/.config/infrastructure/monitoring/ntfy/ntfy.env` (produced by the
[monitoring](monitoring.md) target) and `curl` the ntfy server. Templates →
`~/.config/systemd/user/`.

## Podman drop-ins

| Drop-in | Effect |
|---|---|
| `podman.service.d/loglevel.conf` | `LOGGING="--log-level=warn"` — quieten the Podman API service |
| `podman-auto-update.service.d/override.conf` | `Restart=on-failure` / `RestartSec=5min`, `StartLimitIntervalSec=1h` / `StartLimitBurst=5` for `podman-auto-update.service` |

Containers set `AutoUpdate=registry`; the system `podman-auto-update.timer`
applies image updates and this override makes its service resilient.

## daemon-reload

`deploy_common.yml` runs `systemctl --user daemon-reload` once if any shared
unit changed (the per-target engine does the same for its own files).
