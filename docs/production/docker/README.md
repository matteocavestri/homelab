# Docker Compose Production

The Docker Production infrastructure is composed of multiple complete stacks.

- **Networking Stack:**
  The networking stack adds the services of: reverse proxy, DNS server, dynamic DNS, cybersecurity.
  - Traefik
  - Pi-Hole
  - Crowdsec
  - Cloudflareddns
- **Auth Stack:**
  - Authentik Server
  - Authentik Worker
  - Postgresql
  - Redis
- **Monitoring Stack:**
  - Grafana
  - Prometheus
  - Node Exporter
  - Loki
  - Promtail
  - Cadvisor
  - Graphite
  - InfluxDB
  - PiHole Exporter
  - Cloudflare Exporter
  - Uptimekuma
- **Cloud Stack:**
  - Nextcloud
  - MadiDB
  - Redis
  - Collabora Online
- **Media Stack:**
  - Jellyfin
  - Jellyseer
  - Radarr
  - Sonarr
  - Lidarr
  - Readarr
  - NZBGet
  - Jackett/Deluge
