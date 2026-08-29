# media.target

Pure aggregator target for the media tier. No containers, no slice, no network,
no config — its only job is to pull in the three media sub-targets.

- **Deploy:** `make deploy-media`
- **Parent:** `default.target`
- **Source:** `ansible/sdtargets/media/`

## Aggregation

```
Wants= jellyfin.target  arr.target  immich.target
```

- [jellyfin](jellyfin.md) — media server + transcoding
- [arr](arr.md) — download automation behind the VPN
- [immich](immich.md) — photo management

`manifest.yml` declares `config_files: []`; the directory contains only
`templates/media.target.j2`.

## Operations

```bash
systemctl --user enable --now media.target   # brings up all three children
```

Deploying `media` only renders the aggregator unit — deploy each child target
(`make deploy-jellyfin` etc.) to update its services.
