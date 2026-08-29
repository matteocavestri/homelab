# ai.target

Local LLM / AI workbench: Open WebUI as the front end, Ollama for inference,
n8n for automation (with an isolated code sandbox), ComfyUI for image
generation, and a set of RAG / tooling services (search, crawl, vector DB,
document extraction, TTS). Lowest-priority tier — best-effort, compressible
under host pressure.

- **Deploy:** `make deploy-ai`
- **Parent:** `default.target`
- **Source:** `ansible/sdtargets/ai/`

## Services

| Service | Image | Version | Exposure | Volumes |
|---|---|---|---|---|
| openwebui | `ghcr.io/open-webui/open-webui` | v0.11.1 | `127.0.0.1:8081` (+ `monitoring.network`) | `openwebui-data:/app/backend/data` |
| ollama | `docker.io/ollama/ollama` | 0.33.1 | `127.0.0.1:11434`, GPU | `ollama-data:/root/.ollama` |
| comfyui | `localhost/comfyui-p4` | local build (untracked) | `127.0.0.1:8188`, GPU (CDI) | `comfyui-storage:/root` |
| n8n | `docker.io/n8nio/n8n` | 2.37.4 | `127.0.0.1:5678` (+ `jellyfin`/`arr`/`monitoring` networks) | `n8n-data:/home/node/.n8n` |
| qdrant | `docker.io/qdrant/qdrant` | v1.19 | `127.0.0.1:6333` | `qdrant-data:/qdrant/storage` |
| searxng | `docker.io/searxng/searxng` | latest (digest) | `127.0.0.1:8083` | `settings.yml:ro` |
| crawl4ai | `docker.io/unclecode/crawl4ai` | 0.9.2 | internal | `crawl4ai-data` |
| tika | `docker.io/apache/tika` | 4.0.0-1-full | internal | `tika-data` |
| openai-edge-tts | `docker.io/travisvn/openai-edge-tts` | latest (digest) | internal | — |
| openterminal | `ghcr.io/open-webui/open-terminal` | latest (digest) | internal | `open-terminal-data` |
| pipelines | `ghcr.io/open-webui/pipelines` | main (digest) | internal | `pipelines-data` |
| mcpo | `ghcr.io/open-webui/mcpo` | latest (digest) | internal | `mcpo-config.json:ro`, `~/projects:/projects`, podman socket |

### n8n sandbox (isolated code execution for n8n)

| Service | Image | Version | Notes |
|---|---|---|---|
| sandbox-certs | `ghcr.io/n8n-io/n8n-sandbox-service-api` | 1.1.1 | one-shot: bootstraps the mTLS CA + leaf certs into `sandbox-tls` if absent |
| sandbox-api | `ghcr.io/n8n-io/n8n-sandbox-service-api` | 1.1.1 | control API, `Notify=healthy`, requires `sandbox-certs` |
| sandbox-runner-1 | `ghcr.io/n8n-io/n8n-sandbox-service-runner-dind` | 1.1.1 | privileged Docker-in-Docker runner, `AddDevice=/dev/fuse` |
| (inner) sandbox | `ghcr.io/n8n-io/n8n-sandbox-service-sandbox` | latest | pulled by the runner's inner dockerd, not by podman |

Volumes: `sandbox-tls` (mTLS material — rotate by emptying the volume then
restarting `sandbox-api` + `sandbox-runner-1`), `sandbox-runner-docker`.
Ports 8080/9090/9091 are deliberately **not** published: rootless `--privileged`
only grants capabilities the deploy user already has, but a sandbox escape still
runs as that user, so the runner is kept off the LAN-reachable surface.

## Networking

`ai.network` (bridge). `openwebui` also joins `monitoring.network`. Ollama binds
`0.0.0.0` inside the network; Open WebUI reaches it at `http://ollama:11434`.
GPU: ollama, comfyui, tdarr-style CDI (`nvidia.com/gpu`). OTel traces/metrics
from Open WebUI go to `alloy.dns.podman:14317`.

## Resource slice — `ai.slice` (tier: low)

| CPUWeight run/startup | CPUQuota | AllowedCPUs | Memory min/low/high/max | Swap |
|---|---|---|---|---|
| 50 / 100 | 2800% | `0-13,28-41` (NUMA node 0) | 1G / 2G / 20G / 24G | 16G |

The slice is pinned to one physical CPU (NUMA node 0, 28 threads) to avoid
cross-socket memory access; the 16 GB swap allowance absorbs model-weight
offload and spills to the LVM swap.

## Configuration

`config.yml` highlights:

- **openwebui** — Authentik OIDC (`llm.cavestrihome.com`, login form disabled,
  signup via OAuth, merge accounts by email), OTel enabled, local web fetch /
  KB exec enabled, `OLLAMA_BASE_URL=http://ollama:11434`.
- **ollama** — `flash_attention`, `kv_cache_type: q4_0`, default
  `context_length: 24576`, `keep_alive: 5m`, all NVIDIA devices.
- **comfyui** — `--lowvram`.
- **n8n** — internal task runners, `webhook_url: https://n8n.cavestrihome.com`,
  `N8N_METRICS=true` (Prometheus `/metrics` on `127.0.0.1:5678`, scraped over
  `monitoring.network`). Also joins `jellyfin.network` and `arr.network`.
- **openai-edge-tts** — Italian defaults (`it-IT-ElsaNeural`), mp3, API key
  required.
- **searxng** — `base_url: https://web.cavestrihome.com/`.
- **tika** — `-Xmx4g`.

Env / config files render under `~/.config/ai/` (per-service subdirs; sandbox
files under `~/.config/ai/n8n-sandbox/`, `openwebui.env` and `mcpo-config.json`
sit flat). Secrets in `vault.yml`.

## Backup — `backup-ai.timer`, daily 04:45

Config tree + `openwebui-data` **only**. Model weights (`ollama-data`), vector
data and ComfyUI storage are treated as reproducible and not backed up.
