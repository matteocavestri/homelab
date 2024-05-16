# Docker Compose Production

The Docker Production infrastructure is composed of multiple complete stacks.

### Deployments list

**NOTE:** Create every path before creating the containers

1. **Networking:**

   - make your .env file based on .env.example
   - `docker compose up -d traefik pihole crowdsec cloudflareddns`
   - `docker exec crowdsec cscli bouncers add bouncer-traefik`
   - Put your crowdsec api in your .env file
   - `docker compose up -d --force-recreate`
   - NOTE: You can't reach the clouflare dahboard until you set up Authentik

2. **Auth:**

   - make your .env file based on .env.example
   - `docker compose up -d`
   - add an authentik user
   - add traefik oauth service to your user
   - Now you can reach traefik and you have OAuth2.0, LDAP, SAML and MFA.

3. **Monitoring:**

   - Create authentik Oauth2.0 for Grafana
   - make your .env file based on .env.example
   - `docker compose up -d`

4. **All the others:**

   - You have set up:
     - Reverse Proxy
     - DNS Server
     - AdBlocker
     - Cybersecurity Analysis
     - Auth Server
     - Monitoring Servers
     - Monitoring Containers
     - Monitoring Uptime
     - Monitoring ISP
     - Monitoring Reverse Proxy
     - Monitoring Auth Server
     - Monitoring Server DNS
     - Monitoring CLoudflare
     - Monitoring Dashboards
   - Now you can set up every service you want

### Stacks list

- **Networking Stack:**
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
