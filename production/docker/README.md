# Docker Compose Production

The Docker Production infrastructure is composed of multiple complete stacks.

### Deployments list

1. **Networking:**
   - make your .env file based on .env.example
   - docker compose up -d traefik pihole crowdsec cloudflareddns
   - docker exec crowdsec cscli bouncers add bouncer-traefik
   - Put your crowdsec api in your .env file
   - docker compose up -d --force-recreate
   - NB: You can't reach the clouflare dahboard until you set up Authentik

2) **Auth:**

   - make your .env file based on .env.example
   - docker compose up -d
   - add an authentik user
   - add traefik oauth service to your user
   - Now you can reach traefik and you have OAuth2.0, LDAP, SAML and MFA.

3) **Monitoring:**

### Stacks list

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
