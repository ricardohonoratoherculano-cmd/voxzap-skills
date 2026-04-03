---
name: deploy-assistant-vps
description: Deploy Node.js applications to VPS via Docker Compose through SSH. Use when building or modifying a guided deploy assistant, VPS deployment UI, Docker Compose generation, nginx configuration, SSL certificate installation, coturn TURN server setup, or SSH-based remote server management. Supports dual-mode nginx (Docker container vs existing host nginx).
---

# Deploy Assistant VPS — Reusable Skill

This skill documents the architecture, patterns, and conventions for building a guided VPS deployment system that deploys Node.js applications via Docker Compose through SSH, with an interactive web-based terminal.

## Architecture Overview

- **Frontend:** React deploy page with guided steps panel + interactive SSH terminal
- **Backend:** Express API routes for deploy steps, SSH command execution, and file generation
- **Deployment:** Docker Compose on remote VPS (app + database + optional nginx containers)
- **Connection:** SSH via `ssh2` library, stored in database as SSH configurations
- **SSL:** Let's Encrypt via certbot (webroot mode)
- **TURN:** coturn for WebRTC NAT traversal (installed on VPS host, not in Docker)

## Core Components

| Component | Purpose |
|-----------|---------|
| Docker Generator | Generates Dockerfile, docker-compose.yml, nginx.conf, .env files |
| Deploy Routes | API endpoints for each deploy step (`/api/admin/ssh/deploy/*`) |
| SSH Executor | Runs commands on remote VPS via SSH, returns stdout/stderr/exitCode |
| Deploy Assistant UI | Guided 7-step panel + interactive SSH terminal |

## Deploy Flow — 7 Steps

1. **Check VPS** — OS, resources, Docker installed, port 443 status
2. **Install Docker** — Docker Engine + Docker Compose (if not installed)
3. **Generate Files** — Dockerfile, docker-compose.yml, nginx.conf, .env (sent to VPS via SFTP)
4. **Upload Source** — Tar + upload project source code to VPS
5. **Build & Deploy (Nova Instalação)** — `nohup bash deploy.sh &` (background build + `prisma db push --force-reset` = **RESETA O BANCO**, recria schema vazio, seed cria apenas SuperAdmin)
6. **Verify Status** — Check container health + build logs
7. **Certificado SSL** — Let's Encrypt HTTPS certificate via certbot (requires containers running)
8. **TURN Server (Chamadas)** — Install coturn on VPS host for WebRTC NAT traversal (WhatsApp voice calls)

### Update Flow (Code Changes Only) — "Atualizar VoxZap"
When only application code changed (no infrastructure/config changes):
- Use the **"Atualizar VoxZap"** quick update button (NOT the full deploy steps)
- **MANDATORY: Release Notes must be filled before updating.** The UI enforces this:
  1. User fills Release Notes form (Adicionado/Melhorado/Corrigido — at least one section required)
  2. User selects bump type (patch/minor/major) and clicks "Registrar Versão"
  3. This calls `POST /api/version/bump` with `{ bumpType, releaseNotes: { added[], improved[], fixed[] } }` which updates `package.json` version and writes a new entry in `CHANGELOG.md`
  4. Only after version is registered, the "Atualizar VoxZap" button becomes active
- This runs `update.sh` which does: build → `prisma db push` (schema sync, **NO data loss**) → restart
- Route: `POST /api/admin/ssh/deploy/update-and-start` (uploads `update.sh` via SFTP, then runs it)
- Steps 1-3, 6-8 are NOT needed for simple code updates
- **Version utility:** `server/lib/version.ts` — `getAppVersion()`, `parseChangelog()`, `bumpVersion()`
- **Frontend state:** `versionBumped` flag gates the update button; `releaseAdded/releaseImproved/releaseFixed` text fields parsed line-by-line

### Full Deploy (First Time or Infrastructure Changes)
Run all 8 steps in order. Step 5 **RESETS THE DATABASE** — only the default SuperAdmin user will exist after deploy. Step 8 (coturn) is now integrated into the guided deploy UI.

### CRITICAL: Two Deploy Scripts
| Script | Used By | Database Action |
|--------|---------|-----------------|
| `deploy.sh` | Step 5 (Nova Instalação) | `prisma db push --force-reset` — DROPS ALL DATA, recreates schema, seed creates SuperAdmin only |
| `update.sh` | "Atualizar VoxZap" button | `prisma db push` (no reset) — syncs schema changes, preserves all data |

### Step 8 — TURN Server (Chamadas) — Implementation Details
- **Route:** `POST /api/admin/ssh/deploy/install-coturn`
- **Payload:** `{ domain, databaseUrl }` (both from generate-files step)
- **Auto-detects** VPS public IP via `curl -4 -s ifconfig.me`
- **Idempotent:** If coturn already installed, reads existing config, syncs Settings to DB
- **Password:** Generated via `crypto.randomBytes(12).toString("base64url")` (no special chars)
- **Username:** Fixed `voxzap`
- **DB sync mechanism:** Uploads `turn-config.json` + `turn-upsert.js` via SFTP to `/tmp/`, then `docker cp` into container + `docker exec node /tmp/turn-upsert.js` — avoids shell injection with DB URLs containing `$`
- **Health check:** Verifies `systemctl is-active coturn` + port 3478 listening after install
- **Config includes `verbose`** for session-level logging in `/var/log/turnserver.log`

## Post-Deploy Troubleshooting

### Webhooks Parados Após Deploy ("Invalid signature")

**Sintoma:** Após deploy/update, TODAS as mensagens recebidas param de funcionar. Logs mostram:
```
[Webhook] POST received, entries=1
[Webhook] Invalid signature, rejecting payload
POST /api/webhook/whatsapp 403
```

**Causa:** O campo `Tenants.metaToken` está preenchido com um valor incorreto (não corresponde ao App Secret real da Meta). Quando o valor existe e é diferente do padrão, a validação HMAC-SHA256 é ativada e rejeita tudo.

**Diagnóstico via SSH:**
```bash
docker logs voxzap-app --since 10m 2>&1 | grep "Invalid signature"
```

**Correção imediata no banco:**
```sql
UPDATE "Tenants" SET "metaToken" = 'f69031a3cacc058ea59fe8a7ae710fb4595c146813161cae533ee81c30b7f28c' WHERE id = 1;
```
Isso reseta para o valor padrão, pulando a validação de assinatura. Não precisa reiniciar o container — a query é feita em tempo real.

**Nota:** O container NÃO precisa de variável de ambiente `WHATSAPP_APP_SECRET` ou `META_APP_SECRET`. O App Secret é resolvido do banco (`Tenants.metaToken`) por tenant. Ver documentação completa na skill `whatsapp-messaging-expert` → "Validação de Assinatura".

### Verificação de Container VPS

```bash
docker inspect voxzap-app --format='Created: {{.Created}} Started: {{.State.StartedAt}}'
docker logs voxzap-app --since 5m 2>&1 | tail -30
docker exec voxzap-app printenv | grep -E 'NODE_ENV|DATABASE_URL|SESSION_SECRET'
```

## CRITICAL RULES — Lessons Learned from Production

### 1. Database Driver: `pg` in Production, Neon in Development
`server/db.ts` MUST use the native `pg` driver when `NODE_ENV=production` and `@neondatabase/serverless` in development.

**WHY:** The Neon driver uses WebSocket (`wss://`) to connect to PostgreSQL. In Docker, the hostname `db` resolves to the PostgreSQL container IP. Neon tries to connect to `wss://db/v2` which resolves to `containerIP:443` — the PostgreSQL container does NOT serve WebSocket on port 443, causing `ECONNREFUSED`.

```typescript
// server/db.ts — CORRECT dual-driver pattern
const isProduction = process.env.NODE_ENV === 'production';
if (isProduction) {
  const pgPool = new PgPool({ connectionString: process.env.DATABASE_URL });
  pool = pgPool;
  db = drizzlePg({ client: pgPool, schema });
} else {
  neonConfig.webSocketConstructor = ws;
  const neonPool = new NeonPool({ connectionString: process.env.DATABASE_URL });
  pool = neonPool;
  db = drizzleNeon({ client: neonPool, schema });
}
```

### 2. Dockerfile: Single-Stage, NO `npm prune --production`
The Dockerfile MUST be single-stage and MUST NOT run `npm prune --production`.

**WHY:** The app imports `vite` at runtime in `server/vite.ts` (top-level import). Even though `setupVite()` is only called in development, esbuild with `--packages=external` keeps the import reference. If vite is pruned, the production app crashes with `ERR_MODULE_NOT_FOUND: Cannot find package 'vite'`. Also, `drizzle-kit` (a devDependency) is needed for `drizzle-kit push --force` during deploy.

```dockerfile
FROM node:20-alpine
RUN apk add --no-cache ffmpeg
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build
EXPOSE 5000
CMD ["npm", "start"]
```

**FFmpeg is required** for GSM→MP3 conversion of Asterisk call recordings. Without it, the recording playback endpoint returns 415 errors.

### 3. docker-compose.yml: No `version:`, Service Name `db`
- **NO `version:` attribute** — Docker Compose V2 ignores it and prints a warning
- **Service name MUST be `db`** (not `postgres`) — the DATABASE_URL uses `@db:5432`
- **`postgres:16-alpine`** (not 15)
- **DB port bound to localhost** — `127.0.0.1:5432:5432` (not exposed externally)
- **Docker resource isolation** — VoxCALL and Asterisk MUST use completely separate service names, volume names, and network names (see "Docker Resource Isolation" section below)

### 4. nginx.conf: String Array Concatenation, NOT Template Literals
When generating nginx config, use string array `.join('\n')`, NOT ES6 template literals.

**WHY:** Template literals with `$` characters (e.g., `$http_upgrade`, `$host`) work in JS but require `\\$` escaping in some contexts. Using `\\$` in a template literal produces `\$` in the output (literal backslash + dollar), not `$`. The array approach avoids this entirely.

```typescript
// CORRECT — array concatenation
const conf = [
  'proxy_set_header Upgrade $http_upgrade;',
  'proxy_set_header Host $host;',
].join('\n');

// WRONG — template literal with escaping produces \$
const conf = `proxy_set_header Upgrade \\$http_upgrade;`;  // Output: \$http_upgrade
```

### 5. Tar Upload MUST Exclude Docker Files
The source code tar MUST exclude files that are generated by the deploy assistant, or the tar extract will OVERWRITE the correct generated files with stale workspace copies.

```bash
tar czf /tmp/source.tar.gz \
  --exclude=node_modules --exclude=.git --exclude=dist --exclude=.cache \
  --exclude=attached_assets --exclude=.agents --exclude=.local \
  --exclude="*.tar.gz" --exclude=scripts \
  --exclude=docker-compose.yml --exclude=Dockerfile \
  --exclude=deploy.sh --exclude=nginx.conf --exclude=.env \
  --exclude=docker \
  -C "$projectRoot" .
```

**RULE:** NEVER store `docker-compose.yml`, `Dockerfile`, `deploy.sh`, `nginx.conf`, `.env`, or `docker/` directory in the workspace root. These are generated dynamically by `server/dockerGenerator.ts`.

### 6. Deploy Script: Must Include `drizzle-kit push` + App Restart
The deploy script runs `docker compose up -d` which starts the app, but the database schema doesn't exist yet (fresh PostgreSQL volume). The app crashes on seed because tables don't exist.

```bash
docker compose up -d
sleep 5
docker exec voxcall-app npx drizzle-kit push --force
docker compose restart app
echo "BUILD_SUCCESS" > deploy.status
```

### 7. `docker compose restart` Does NOT Reload env_file
If you change `.env` on the VPS, `docker compose restart app` only restarts the process — it does NOT re-read the env_file. You MUST use `docker compose up -d app` (or `--force-recreate`) to pick up new environment variables. This applies to the `update-env-key` endpoint and any manual `.env` changes.

### 8a. Config File Persistence — Docker Volume `app_configs`
All JSON config files (`db-config.json`, `db-replica-config.json`, `ari-config.json`, `ami-config.json`, `ssh-config.json`, `sip-webrtc-config.json`, `smtp-config.json`, `asterisk-recordings-config.json`, `menu-permissions.json`, `system-settings.json`, `backup-schedule.json`) are stored in a persistent Docker volume mounted at `/app/config/`.

**How it works:**
- `getConfigDir()` helper in `routes.ts`, `agent.ts`, `storage.ts`, `ssh-terminal.ts`, `backup-scheduler.ts` resolves to `/app/config/` in production (`NODE_ENV=production`) and `process.cwd()` in development
- Docker volume `app_configs` mounted at `/app/config` in both docker-compose variants (with-nginx and no-nginx)
- The config directory is auto-created on startup via `fs.mkdir(configDir, { recursive: true })`
- Without this volume, all configs are lost on container restart/rebuild (ephemeral `/app` filesystem)

**RULE:** NEVER use `path.join(process.cwd(), 'some-config.json')` directly. Always use `path.join(getConfigDir(), 'some-config.json')`.

### 8b. Updating `.env` Keys on VPS — `update-env-key` Endpoint
The endpoint `POST /api/admin/ssh/deploy/update-env-key` allows updating individual keys in the VPS `.env` file from the Deploy Assistant UI (e.g., OpenAI API key).

**How it works:**
1. Reads entire `.env` via SSH (`cat /opt/voxcall/.env`)
2. Modifies the target key in Node.js (avoids shell escaping issues with `sed`)
3. Encodes new content as base64 and writes back via SSH (`echo 'base64...' | base64 -d > .env`)
4. Recreates the container via `docker compose up -d app` (NOT `restart` — see rule 7)

**WHY base64:** OpenAI API keys and passwords contain special characters (`$`, `-`, `@`, etc.) that are interpreted by the shell. Using sed/echo with these characters silently corrupts the value. Base64 encoding bypasses all shell interpretation.

**WHY NOT `docker compose restart`:** `restart` only stops/starts the process — it does NOT re-read `env_file`. The updated `.env` values are invisible to the container until it's recreated with `docker compose up -d`.

**Allowed keys:** Currently restricted to `OPENAI_API_KEY` via an allowlist. Add new keys to `allowedKeys` array in the endpoint.

### 9. Docker Stop/Kill Can Hang
Containers with network issues can cause `docker stop` and `docker kill` to hang indefinitely. Solution: restart the Docker daemon with `systemctl restart docker`, then `docker rm -f` the containers and redeploy.

### 10. nginx http2 Directive
Modern nginx (alpine) deprecates `listen 443 ssl http2`. Use separate directives:
```nginx
listen 443 ssl;
http2 on;
```

### 11. SuperAdmin Credentials & SIP Extension
The `.env` file supports superadmin auto-creation and SIP configuration via:
```
SUPERADMIN_PASSWORD=RiCa$$0808
SUPERADMIN_EMAIL=superadmin@domain.com
SUPERADMIN_USERNAME=superadmin
SUPERADMIN_SIP_EXTENSION=1050
SUPERADMIN_SIP_PASSWORD=sip_password_here
```
**IMPORTANT:** `.env` values are NOT single-quoted. The `$` character is escaped as `$$` by the `escapeEnvDollar()` helper in `generateEnvFile()`. Docker Compose interprets `$$` as a literal `$`. Example: password `RiCa$0808` is written as `RiCa$$0808` in `.env`.

The app seed checks `process.env.SUPERADMIN_PASSWORD` — if set, creates/updates the superadmin user on startup. If `SUPERADMIN_SIP_EXTENSION` is also set, configures the superadmin's SIP extension for the softphone.

**IMPORTANT:** Each user needs their own `sipExtension` and `sipPassword` in the database for the softphone to work. Without these, the softphone shows "Seu usuário não tem ramal SIP configurado" instead of registering. The deploy UI has fields for the superadmin's SIP extension and password.

### 12. Per-User SIP Configuration
The SIP/WebRTC config endpoint (`GET /api/sip-webrtc/config`) returns global settings (server, STUN, TURN) but overwrites `extension` and `password` with the logged-in user's `sipExtension`/`sipPassword` from the database. If a user has no SIP extension, the auto-register component skips registration and the softphone stays disconnected.

### 13. Docker Resource Isolation — VoxCALL vs Asterisk (CRITICAL)
When VoxCALL and Asterisk run on the same VPS (or share Docker), their docker-compose files MUST use **completely separate** service names, volume names, network names, AND **Docker Compose project names**. Using identical names causes:
- **Data destruction**: `docker compose down -v` in one project deletes shared volumes, destroying the other project's database
- **Orphan container removal**: `docker compose down --remove-orphans` treats containers from the other project as orphans and kills them
- **DNS conflicts**: Two services named `db` on the same Docker network cause hostname resolution to the wrong container

**Current resource naming:**

| Resource | VoxCALL (`docker-compose.yml`) | Asterisk (`docker-compose.asterisk.yml`) |
|----------|-------------------------------|----------------------------------------|
| **Project name (`-p`)** | `voxcall` | `voxcall-asterisk` |
| DB service | `db` | `asterisk-db` |
| DB container | `voxcall-db` | `voxcall-asterisk-db` |
| DB volume | `pgdata` | `asterisk_pgdata` |
| Network | `voxcall-net` | `voxcall-asterisk-net` |
| DB image | `postgres:16-alpine` | `postgres:16-alpine` |
| **DB env TZ** | — | `TZ=America/Sao_Paulo`, `PGTZ=America/Sao_Paulo` |
| **App env TZ** | — | `TZ=America/Sao_Paulo` |

**Resource Priority (OOM & Performance):**
Containers are configured with **no CPU/memory hard limits** so they can dynamically use all available VPS resources. Priority is enforced via `oom_score_adj` (Linux OOM killer preference — lower = last to be killed):

| Container | `oom_score_adj` | Kill Priority | Role |
|-----------|----------------|---------------|------|
| `voxcall-asterisk` | **-1000** | Never killed (protected) | Asterisk PBX — critical telephony |
| `voxcall-asterisk-db` | **-900** | Last resort | Asterisk PostgreSQL — call data |
| `voxcall-db` | **-500** | Low priority | VoxCALL PostgreSQL |
| `voxcall-app` | **300** | First to be killed | VoxCALL web app (recoverable) |
| `voxcall-nginx` | (default 0) | Normal | Reverse proxy |

Additional performance settings:
- **`shm_size`**: `512mb` (Asterisk DB), `256mb` (VoxCALL DB) — PostgreSQL shared memory for sorting/hashing
- **`ulimits`** (Asterisk only): `nofile` and `nproc` = 65536 — handles high concurrent call volumes
- **No `mem_limit`/`cpus` restrictions** — all containers can use 100% of VPS resources when needed

**Rules:**
- **ALL `docker compose` commands MUST include `-p <project> -f <file>`** to scope operations to the correct project. Example: `docker compose -p voxcall -f docker-compose.yml down` (VoxCALL) vs `docker compose -p voxcall-asterisk -f docker-compose.asterisk.yml down` (Asterisk)
- **NEVER use bare `docker compose down`** without `-p` and `-f` flags — Docker infers the project name from the directory, which is the same (`/opt/voxcall`) for both projects
- **NEVER use `--remove-orphans`** — it kills containers from the other project that share the same inferred project name
- NEVER use the same volume, network, or service name across different compose files on the same host
- Asterisk deploy script cleanup MUST target `asterisk_pgdata` specifically, never generic `pgdata`
- Deploy order when both need fresh install: **VoxCALL first**, then Asterisk
- **NEVER add `mem_limit`, `cpus`, or `deploy.resources.limits`** to Asterisk or PostgreSQL containers — they must be free to use all VPS resources dynamically

### 14. Timezone Configuration — Asterisk Containers (CRITICAL)
All Asterisk-related containers MUST use `America/Sao_Paulo` timezone. Without this, CDR timestamps are recorded 3 hours ahead.

**Root cause**: Asterisk reads `/etc/localtime` (NOT the `TZ` environment variable) for its internal clock. If `/etc/localtime` points to UTC, the CDR module sends UTC timestamps to PostgreSQL, which interprets them as local time (America/Sao_Paulo), causing a +3h offset.

**Required configuration:**

1. **Asterisk Dockerfile** — MUST include both `ENV TZ` and the `/etc/localtime` symlink:
   ```dockerfile
   ENV TZ=America/Sao_Paulo
   RUN ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime && echo "America/Sao_Paulo" > /etc/timezone
   ```

2. **docker-compose.asterisk.yml** — both containers need TZ env:
   ```yaml
   asterisk:
     environment:
       TZ: America/Sao_Paulo
   asterisk-db:
     environment:
       TZ: America/Sao_Paulo
       PGTZ: America/Sao_Paulo
   ```

3. **PostgreSQL** — `postgresql.conf` must have `timezone = 'America/Sao_Paulo'` and `ALTER DATABASE asterisk SET timezone = 'America/Sao_Paulo'`

**Verification**: `docker exec voxcall-asterisk asterisk -rx "core show settings" | grep time` — Startup time must show Brasília time, NOT UTC.

### 15. Timezone Configuration — VoxZap Containers (CRITICAL)
VoxZap containers MUST have `tzdata` installed and `/etc/localtime` configured. **PostgreSQL database timezone MUST be UTC.**

**Root cause**: Prisma/pg driver sends timestamps to PostgreSQL WITHOUT the `Z` UTC marker (e.g., `2026-03-29T20:25:46.741` instead of `2026-03-29T20:25:46.741Z`). If PostgreSQL timezone is set to a local timezone (e.g., America/Sao_Paulo), it interprets the bare timestamp as local time, causing a +3h offset in stored data.

**Required configuration:**

1. **VoxZap Dockerfile** — MUST include `tzdata`, `ARG TZ`, `ENV TZ`, and `/etc/localtime`:
   ```dockerfile
   RUN apk add --no-cache ffmpeg tzdata
   ARG TZ=America/Sao_Paulo
   ENV TZ=${TZ}
   RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
   ```

2. **docker-compose.yml** — app container needs TZ build arg and env:
   ```yaml
   app:
     build:
       args:
         - TZ=America/Sao_Paulo
     environment:
       - TZ=America/Sao_Paulo
   ```

3. **PostgreSQL** — Database timezone MUST be UTC (NOT local timezone):
   ```sql
   ALTER DATABASE postgres SET timezone = 'UTC';
   ```
   Deploy/update scripts (`server/dockerGenerator.ts`) set this automatically.

4. **Dashboard queries** — Use `AT TIME ZONE 'America/Sao_Paulo'` to convert UTC→local for display:
   ```sql
   EXTRACT(HOUR FROM "createdAt" AT TIME ZONE 'America/Sao_Paulo')
   ```

**Verification**:
- `docker exec voxzap-app date` — Must show Brasília time (-03), NOT UTC
- `docker exec voxzap-app ls /etc/localtime` — Must exist
- PostgreSQL: `SHOW timezone;` — Must return `UTC`

## TURN Server (coturn) — WebRTC NAT Traversal

### Why TURN is Required
STUN alone only works when both sides (browser and Asterisk) can exchange UDP packets directly. In many networks (symmetric NAT, corporate firewalls, mobile 4G/5G), STUN fails and WebRTC needs a TURN server to relay audio. Without TURN, calls connect (SIP signaling works via WSS) but audio fails intermitently.

### coturn Installation on VPS
coturn is installed directly on the VPS host (NOT in Docker) because it needs direct access to the public IP and UDP ports.

```bash
apt-get update && apt-get install -y coturn

cat > /etc/turnserver.conf << 'EOF'
listening-port=3478
tls-listening-port=5349
fingerprint
lt-cred-mech
realm=DOMAIN
server-name=DOMAIN
external-ip=VPS_PUBLIC_IP
min-port=49152
max-port=65535
user=USERNAME:PASSWORD
no-cli
no-multicast-peers
no-loopback-peers
log-file=/var/log/turnserver.log
simple-log
verbose
EOF

echo "TURNSERVER_ENABLED=1" > /etc/default/coturn
systemctl enable --now coturn
```

### Current VPS TURN Configurations

#### VoxZap (voxtel.voxzap.app.br)
- **VPS:** 72.61.34.151 port 3478 (UDP + TCP)
- **Realm:** voxtel.voxzap.app.br
- **User:** voxzap / VoxTurn2026!
- **Config file:** `/etc/turnserver.conf`
- **Service:** `systemctl status coturn`
- **Verbose logging:** enabled (`verbose` directive in config)
- **Session log:** `/var/log/turnserver.log`
- **LIVE-VALIDATED:** TURN allocations confirmed (session 001, relay on 72.61.34.151, 77s stable call)

#### VoxCALL (voxdrive.voxtel.app.br)
- **VPS:** 85.209.93.135 port 3478 (UDP)
- **Realm:** voxdrive.voxtel.app.br
- **User:** voxcall / VoxTurn2026!
- **Config file:** `/etc/turnserver.conf`
- **Service:** `systemctl status coturn`

## Multi-Server Architecture

### VPS App Server (85.209.93.135)
- **SSH**: 85.209.93.135:22300, user root
- **Domain**: voxdrive.voxtel.app.br
- **Containers**: `voxcall-app`, `voxcall-nginx`, `voxcall-db` (+ wg-easy, portainer)
- **Purpose**: Runs the VoxCALL web application
- **coturn**: Installed on this VPS for WebRTC TURN relay

### Asterisk Server (boghos.voxcall.cc)
- **SSH**: boghos.voxcall.cc:22300, user root, same password as app VPS
- **Public IP**: 77.37.69.68
- **Containers**: `voxcall-asterisk` (network_mode: host), `voxcall-asterisk-db` (PostgreSQL 16-alpine on port 25432)
- **Purpose**: Runs Asterisk 22 PBX with PJSIP realtime
- **Docker Compose**: `/opt/voxcall/docker-compose.asterisk.yml`
- **Config dir**: Inside container at `/etc/asterisk/` (pjsip_wizard.conf, rtp.conf, etc.)

### Asterisk NAT Configuration (CRITICAL)
When Asterisk runs in Docker, even with `network_mode: host`, the PJSIP transports MUST have `local_net` configured. Without it, Asterisk doesn't know when to use `external_media_address` in SDP, causing no-audio issues.

**Required in pjsip_wizard.conf for BOTH transports:**
```ini
local_net=172.16.0.0/12
local_net=10.0.0.0/8
local_net=192.168.0.0/16
local_net=127.0.0.0/8
```

**Required in rtp.conf:**
```ini
stunaddr=74.125.250.129:19302
```
Use IPv4 IP directly — Docker containers may resolve hostnames to IPv6 which Asterisk can't use for STUN.

**Extension template mapping:**
- `webrtc_template` (ramais_wss_pjsip.conf) → WebRTC/browser clients only (2000-2xxx)
- `endpoint_template` (ramais_udp_pjsip.conf) → SIP pure/softphone (8500-8xxx, 9xxx)
- Using a SIP softphone with a WebRTC endpoint → signaling works but audio fails (DTLS vs RTP mismatch)

**Writing configs to Docker container** (avoids shell escaping issues):
```bash
echo "<base64_content>" | base64 -d > /tmp/config.conf
docker cp /tmp/config.conf voxcall-asterisk:/etc/asterisk/config.conf
rm /tmp/config.conf
docker exec voxcall-asterisk asterisk -rx "module reload res_pjsip.so"
```

### SIP/WebRTC Config with TURN
File: `sip-webrtc-config.json` (project root, read by `GET /api/sip-webrtc/config`)
```json
{
  "sipServer": "vitahome.voxserver.app.br",
  "wssPort": 8089,
  "extension": "",
  "password": "",
  "stunServer": "stun:stun.l.google.com:19302",
  "turnServer": "turn:85.209.93.135:3478",
  "turnUsername": "voxcall",
  "turnPassword": "VoxTurn2026!",
  "enabled": true
}
```

### ICE Configuration in SipContext.tsx
The WebRTC ICE setup includes:
- **Multiple STUN fallbacks:** Primary (configurable) + `stun:stun.cloudflare.com:3478` + `stun:stun1.l.google.com:19302`
- **TURN normalization:** Auto-adds `turn:` prefix if missing, creates TURNS (TLS) entry on port 5349
- **ICE restart on failure:** `pc.restartIce()` on `failed` state, and after 3s timeout on `disconnected` state
- **ICE gathering logging:** `onicegatheringstatechange` for debugging
- **Dynamic stream attachment:** `ontrack` event handler for late-arriving media tracks
- **ICE transport policy:** `"all"` (tries direct first, falls back to relay)
- **Candidate pool size:** 10 (pre-fetches candidates for faster connection)

```typescript
const iceServers: RTCIceServer[] = [];
iceServers.push({ urls: [stunUrl, "stun:stun.cloudflare.com:3478", "stun:stun1.l.google.com:19302"] });
if (turnUrl) {
  iceServers.push({ urls: normalizedTurn, username, credential });
  iceServers.push({ urls: turnsUrl, username, credential }); // TURNS on :5349
}
```

## Dual-Mode Nginx

### Mode 1: Docker Nginx (`nginxMode: 'docker'`)
For fresh VPS with no web server on port 443.

- Three containers: app (Node.js), db (PostgreSQL), nginx (nginx:alpine ports 80/443)
- Nginx config generated by `generateNginxConf(domain)` and mounted into container
- SSL certificates mounted from host: `/etc/letsencrypt:/etc/letsencrypt`
- Certbot webroot at `/var/lib/letsencrypt`

### Mode 2: Existing Nginx (`nginxMode: 'existing'`)
For VPS that already has Nginx/Apache running on port 443.

- Two containers only: app (Node.js on `127.0.0.1:PORT`), db (PostgreSQL)
- No nginx container — app binds to localhost only (not exposed externally)
- Site config generated by `generateNginxSiteConf(domain, appPort)` and installed at `/etc/nginx/sites-available/DOMAIN`
- Symlink created: `/etc/nginx/sites-enabled/DOMAIN` → `nginx -t && systemctl reload nginx`
- `proxy_pass` points to `http://127.0.0.1:PORT` (host network, not Docker network)
- Certbot webroot at `/var/www/html`

### Port 443 Auto-Detection
The `checkPort443` command detects what's on port 443:
```bash
ss -tlnp | grep ":443" || echo "PORTA_443_LIVRE"
nginx -v 2>&1 || echo "NGINX_NAO_INSTALADO"
apache2 -v 2>&1 || httpd -v 2>&1 || echo "APACHE_NAO_INSTALADO"
```

Frontend parses output:
- `PORTA_443_LIVRE` → port free, default to Docker mode
- Otherwise → port occupied, auto-select "existing" mode, show yellow badge with service name

## Docker Generator Pattern (`server/dockerGenerator.ts`)

Functions that generate deployment files as strings:

| Function | Purpose |
|----------|---------|
| `generateDockerfile()` | Single-stage Node.js build with FFmpeg (npm ci + build, NO prune) |
| `generateDockerCompose(config)` | 3-container setup: app + db + nginx (Docker mode) |
| `generateDockerComposeNoNginx(config)` | 2-container setup: app + db, app on `127.0.0.1:PORT` (Existing mode) |
| `generateNginxConf(domain)` | HTTP-only nginx config for initial deploy (proxy to `app:5000`) |
| `generateNginxConfSsl(domain)` | HTTPS nginx config with SSL (redirect HTTP→HTTPS) |
| `generateNginxSiteConf(domain, appPort)` | Nginx site config for host nginx (proxy to `127.0.0.1:PORT`) |
| `generateEnvFile(config)` | Production .env with DB, domain, session, OpenAI, superadmin + SIP credentials. Uses `escapeEnvDollar()` to escape `$` as `$$` |
| `generateDeployScript()` | Bash deploy script with build + drizzle-kit push + app restart |
| `generateAsteriskDockerCompose(config)` | Asterisk docker-compose: `asterisk-db` (PG 16) + `asterisk` (build from Dockerfile), isolated network `voxcall-asterisk-net` |
| `generateAsteriskDeployScript(projectDir, config)` | Bash script for Asterisk build: configs, Docker build, DB wait, schema init |
| `escapeEnvDollar(val)` | Helper: escapes `$` as `$$` for Docker Compose .env variable interpolation |
| `getDeployCommands()` | Predefined SSH command strings for all deploy operations |

### Config Parameter
```typescript
interface DeployConfig {
  appPort?: number;           // Host port mapping (default: 5000)
  dbPort?: number;            // PostgreSQL port (default: 5432)
  dbPassword?: string;        // Auto-generated if empty
  dbName?: string;            // Default: 'voxcall'
  domain?: string;            // FQDN for SSL/nginx
  sessionSecret?: string;     // Auto-generated if empty
  openaiKey?: string;         // OpenAI API key (optional, for AI features)
  superadminPassword?: string; // SuperAdmin password (creates user on startup)
  superadminEmail?: string;   // Default: 'superadmin@voxtel.biz'
  superadminUsername?: string; // Default: 'superadmin'
  superadminSipExtension?: string; // SuperAdmin SIP extension (e.g., '1050')
  superadminSipPassword?: string;  // SuperAdmin SIP password
}
```

### Deploy Commands Object
```typescript
getDeployCommands() returns {
  checkRequirements: string,    // OS info, disk, memory, Docker check
  installDocker: string,        // apt install docker + compose
  installCertbot: string,       // apt install certbot
  createProjectDir: string,     // mkdir -p /opt/voxcall/
  buildAndStart: string,        // nohup bash deploy.sh & (background)
  buildLogs: string,            // deploy.status + deploy.log + container status
  checkStatus: string,          // docker compose ps + app logs
  stop: string,                 // docker compose down
  restart: string,              // docker compose restart
  logs: string,                 // docker compose logs --tail=150
  checkPort443: string,         // ss + nginx/apache detection
  generateSslCertDocker: (domain, email?) => string,  // certbot for Docker nginx
  generateSslCertHost: (domain, email?) => string,    // certbot for host nginx
  installNginxSite: (domain) => string,               // symlink + reload host nginx
  projectDir: string,           // '/opt/voxcall'
}
```

## Backend Routes Pattern

All deploy routes use consistent pattern:
```
POST /api/admin/ssh/deploy/{action}
```

### Route List
| Route | Body | Purpose |
|-------|------|---------|
| `check-requirements` | SSH creds | Check VPS + port 443 detection |
| `install-docker` | SSH creds | Install Docker Engine + Compose |
| `generate-files` | SSH creds + `{ domain, appPort, dbPort, dbPassword, openaiKey, superadminPassword, superadminSipExtension, superadminSipPassword, nginxMode }` | Generate and upload config files via SFTP |
| `upload-source` | SSH creds | Tar + SFTP upload of project source |
| `build-and-start` | SSH creds | `nohup bash deploy.sh &` |
| `build-logs` | SSH creds | deploy.status + deploy.log + containers |
| `status` | SSH creds | `docker compose ps` |
| `logs` | SSH creds | `docker compose logs` |
| `stop` | SSH creds | `docker compose down` |
| `restart` | SSH creds | `docker compose restart` |
| `install-ssl` | SSH creds + `{ domain, email, nginxMode }` | Let's Encrypt certificate via certbot |
| `diagnostics` | SSH creds | Comprehensive VPS diagnostic |

### Authentication & Authorization
```typescript
app.post('/api/admin/ssh/deploy/*', requireAuth, requireRole(["superadmin"]), async (req, res) => { ... });
```

### SSH Execution
```typescript
async function executeDeployCommand(cmd: string, timeout: number, sshConfig: SshConfig): Promise<ExecResult> {
  // Returns: { success: boolean, stdout: string, stderr: string }
}
```

### File Transfer
Files are sent via SFTP using `uploadFileViaSftp()`:
```typescript
async function uploadFileViaSftp(content: Buffer, remotePath: string, sshConfig: SshConfig): Promise<void>
```

### Source Code Upload
```typescript
// 1. Create tarball (excluding node_modules, .git, dist, Docker files, etc.)
execSync('tar czf /tmp/voxcall-source.tar.gz --exclude=... -C "' + projectRoot + '" .');
// 2. Upload via SFTP
await uploadFileViaSftp(tarBuffer, projectDir + '/source.tar.gz', ssh);
// 3. Extract on VPS
await executeDeployCommand('cd ' + projectDir + ' && tar xzf source.tar.gz && rm source.tar.gz', 120000, ssh);
```

## SSL / HTTPS Pattern

### Certificate Generation
```bash
# Docker mode (certbot webroot, shared volume with nginx container)
certbot certonly --webroot -w /var/lib/letsencrypt -d DOMAIN --non-interactive --agree-tos --email EMAIL

# Existing nginx mode (certbot webroot on host filesystem)
certbot certonly --webroot -w /var/www/html -d DOMAIN --non-interactive --agree-tos --email EMAIL
```

### SSL Flow (Step 7 in guided deploy)
1. Steps 1-6 deploy with HTTP-only nginx config (`generateNginxConf`)
2. Step 7 runs certbot to generate certificate
3. Backend uploads SSL nginx config (`generateNginxConfSsl`) to VPS
4. Reloads nginx: `docker compose exec nginx nginx -s reload`
5. SSL email field is inline with Step 7 in the UI (optional, defaults to admin@domain)

### Certificate Mount (Docker Mode)
```yaml
nginx:
  volumes:
    - ./nginx.conf:/etc/nginx/conf.d/default.conf
    - /etc/letsencrypt:/etc/letsencrypt
    - /var/lib/letsencrypt:/var/lib/letsencrypt
```

### Nginx HTTPS Config Pattern
```nginx
server {
    listen 80;
    server_name DOMAIN;
    location /.well-known/acme-challenge/ { root /var/lib/letsencrypt; }
    location / { return 301 https://$host$request_uri; }
}
server {
    listen 443 ssl;
    http2 on;
    server_name DOMAIN;
    ssl_certificate /etc/letsencrypt/live/DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    client_max_body_size 50M;
    location / {
        proxy_pass http://app:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
}
```

## Webhook Proxy (Modo Desenvolvimento)

Mecanismo para redirecionar webhooks da Meta (WhatsApp) da VPS para o Replit durante desenvolvimento, evitando deploys repetidos na VPS.

### Infraestrutura no nginx

O nginx da VPS usa um arquivo include para definir o destino dos webhooks:

```nginx
# Em nginx.conf (bloco HTTPS)
set $webhook_backend http://app:5000;
set $webhook_host app;
include /etc/nginx/webhook_target.inc;

location /api/webhook/ {
    proxy_pass $webhook_backend;
    proxy_set_header Host $webhook_host;
    proxy_set_header X-Hub-Signature-256 $http_x_hub_signature_256;
    # ... demais headers
}
```

O arquivo `/opt/voxzap/webhook_target.inc` controla o destino:
- **Produção (padrão):** `set $webhook_backend http://app:5000;` + `set $webhook_host app;`
- **Dev (proxy ativo):** `set $webhook_backend https://REPLIT_DOMAIN;` + `set $webhook_host REPLIT_DOMAIN;`

### Endpoints da API

| Endpoint | Método | Acesso | Descrição |
|----------|--------|--------|-----------|
| `/api/admin/webhook-proxy/status` | POST | superadmin | Lê `webhook_target.inc` via SSH, retorna se proxy está ativo e para onde aponta |
| `/api/admin/webhook-proxy/toggle` | POST | superadmin | Grava novo conteúdo em `webhook_target.inc` e executa `nginx -s reload` |

Ambos recebem credenciais SSH no body (`sshHost`, `sshPort`, `sshUser`, `sshPassword`).

### Fluxo de Ativação
1. SuperAdmin acessa `/webhook-proxy` no painel
2. Informa credenciais SSH da VPS
3. Clica "Verificar Status" → lê o arquivo via SSH
4. Ativa o toggle → grava URL do Replit no `webhook_target.inc` + `nginx -s reload`
5. Webhooks da Meta passam pela VPS e são redirecionados ao Replit
6. Ao finalizar desenvolvimento, desativa o toggle → restaura `http://app:5000`

### Arquivos Relevantes
| Arquivo | Responsabilidade |
|---------|-----------------|
| `server/routes.ts` | Endpoints `/api/admin/webhook-proxy/status` e `/toggle` |
| `client/src/pages/webhook-proxy.tsx` | UI do toggle com formulário SSH, status e controles |
| `client/src/lib/menu-config.ts` | Menu item "Webhook Proxy" (superadminOnly) |
| VPS: `/opt/voxzap/webhook_target.inc` | Arquivo nginx include que define o destino dos webhooks |

## Frontend Pattern (`deploy-assistant.tsx`)

### Layout
- Two-column layout: left panel (config + steps + container management), right panel (SSH terminal)
- Height-constrained: `h-[calc(100vh-4rem)]` to prevent page scroll
- Terminal: sticky card with `max-h-[calc(100vh-6rem)]`, internal `overflow-y-auto` scroll
- Terminal features: line counter, "Limpar" (clear) button, auto-scroll to bottom

### State Management
```typescript
const [sshHost, setSshHost] = useState("");
const [sshPort, setSshPort] = useState(22);
const [sshUser, setSshUser] = useState("root");
const [sshPassword, setSshPassword] = useState("");
const [domain, setDomain] = useState("");
const [appPort, setAppPort] = useState(5000);
const [dbPort, setDbPort] = useState(5432);
const [dbPassword, setDbPassword] = useState("");
const [openaiKey, setOpenaiKey] = useState("");
const [superadminPassword, setSuperadminPassword] = useState("");
const [superadminSipExtension, setSuperadminSipExtension] = useState("");
const [superadminSipPassword, setSuperadminSipPassword] = useState("");
const [sslEmail, setSslEmail] = useState("");
const [nginxMode, setNginxMode] = useState<'docker' | 'existing'>('docker');
const [port443Status, setPort443Status] = useState<{ occupied: boolean; service: string } | null>(null);
```

### Deploy Steps
7 steps rendered as a list with "Executar" buttons:
1-6: Standard deploy steps
7: Certificado SSL — has inline email input field below the step row

### Nginx Mode Selector
Radio button group with two options:
- "Nginx no Docker (VPS limpa)" — for fresh VPS
- "Usar Nginx/Apache existente da VPS" — for VPS with existing web server
Auto-selects "existing" when port 443 is detected as occupied after Step 1.

### Container Management Section
Separate card below the steps with: Status, Logs, Ver Logs do Build, Reiniciar, Parar, Diagnóstico Completo.

## Security Considerations

- **Localhost binding** (existing mode): app on `127.0.0.1:PORT` prevents direct external access
- **SFTP file transfer**: prevents shell injection (replaces base64 via echo for critical files)
- **Input sanitization**: domain stripped to `[a-zA-Z0-9.\-]`, ports clamped to 1024-65535
- **Role model**: `superadmin` role required for all deploy endpoints
- **Certbot auto-install**: checks `which certbot` before attempting install
- **NEVER hardcode SSH credentials** in scripts — always pass via UI form or environment variables
- **DATABASE_URL is REQUIRED**: The `generate-files` step validates that `databaseUrl` is non-empty and starts with `postgresql://`. No placeholder fallback — deploy fails fast if missing. If the password contains special characters (`/`, `=`, `@`, `#`), they MUST be URL-encoded in the connection string (e.g., `/` → `%2F`, `=` → `%3D`, `@` → `%40`). The frontend shows this hint to the user.
- **Passwords with `$` characters**: `$` is escaped as `$$` in `.env` values via `escapeEnvDollar()` helper. Values are NOT single-quoted. Docker Compose interprets `$$` as literal `$`. Files uploaded via SFTP (NOT shell echo, which expands `$`)
- **TURN credentials**: Stored in `sip-webrtc-config.json` (server-side only, returned via authenticated API)

## Project Directory Structure on VPS

```
/opt/voxcall/
├── Dockerfile              # Generated by dockerGenerator.ts
├── docker-compose.yml      # Generated by dockerGenerator.ts
├── nginx.conf              # Generated by dockerGenerator.ts
├── .env                    # Generated by dockerGenerator.ts
├── deploy.sh               # Generated by dockerGenerator.ts
├── deploy.status           # BUILD_START | BUILD_SUCCESS | BUILD_ERROR
├── deploy.log              # Detailed build log
├── sip-webrtc-config.json  # SIP/WebRTC + TURN config (from source tar)
├── package.json            # From source tar
├── server/                 # From source tar
├── client/                 # From source tar
├── shared/                 # From source tar
└── ...                     # Other source files
```

## VPS Host Services (outside Docker)

| Service | Port | Purpose |
|---------|------|---------|
| coturn | 3478 UDP | TURN relay for WebRTC NAT traversal |
| coturn | 5349 UDP | TURNS (TLS) relay (if SSL configured) |
| coturn | 49152-65535 UDP | Media relay port range |

## Troubleshooting

### Container won't stop (docker stop hangs)
```bash
systemctl restart docker
docker rm -f container_name
```

### Auth failed after deploy (PostgreSQL)
If the pgdata volume already existed with a different password:
```bash
docker exec voxcall-db psql -U voxcall -d voxcall -c "ALTER USER voxcall WITH PASSWORD 'new_password'"
docker compose up -d --force-recreate app  # NOT restart (won't re-read .env)
```

### Tables don't exist (seed fails)
```bash
docker exec voxcall-app npx drizzle-kit push --force
docker compose restart app
```

### App crashes with ERR_MODULE_NOT_FOUND: vite
Dockerfile is using multi-stage build or `npm prune --production`. Fix: use single-stage Dockerfile without prune.

### Env changes not picked up
`docker compose restart` does NOT reload env_file. Use:
```bash
docker compose up -d --force-recreate app
```

### Softphone shows "Desconectado" on VPS
The user's `sip_extension` and `sip_password` are empty in the database. Each user needs SIP credentials configured in Gerenciamento de Usuários. For superadmin, set `SUPERADMIN_SIP_EXTENSION` and `SUPERADMIN_SIP_PASSWORD` in `.env` and redeploy/restart, or update directly:
```bash
docker exec voxcall-db psql -U voxcall -d voxcall -c "UPDATE users SET sip_extension = '1050', sip_password = 'password' WHERE username = 'superadmin';"
```

### Login fails after Asterisk deploy ("Credenciais inválidas")
**Cause:** Asterisk and VoxCALL docker-compose files used the same volume name (`pgdata`), network (`voxcall-net`), and/or service name (`db`). The Asterisk deploy script's volume cleanup destroyed the VoxCALL database, or DNS resolved `db` to the wrong PostgreSQL container.
**Solution:** Ensure complete resource isolation in `dockerGenerator.ts` (see "Docker Resource Isolation" section). Redeploy VoxCALL (full install) first, then Asterisk.

### ARI connection refused on Asterisk (port 8088) / WSS port 8089 not listening
**Cause:** Asterisk HTTP server is "Disabled" — either `bindaddr` is commented out in `http.conf`, or `tlsenable=yes` with missing/wrong TLS certificate paths causes the entire HTTP server to fail silently.
**Diagnosis:** `docker exec voxcall-asterisk asterisk -rx 'http show status'` shows "Server Disabled" or only port 8088 but not 8089.

**Automated fix (deploy):** The Asterisk deploy script now automatically:
1. Mounts `/etc/letsencrypt` as read-only volume in the Asterisk container
2. If Let's Encrypt cert exists for the configured domain, writes `http.conf` with correct `tlscertfile`/`tlsprivatekey` paths pointing to `/etc/letsencrypt/live/<domain>/`
3. After container starts, applies the config inside the running container and runs `core reload`
4. Verifies port 8089 is active

**Manual fix (if deploy hasn't run):**
```bash
docker exec voxcall-asterisk bash -c 'cat > /etc/asterisk/http.conf << EOF
[general]
servername=Asterisk
tlsbindaddr=0.0.0.0:8089
bindaddr=0.0.0.0
bindport=8088
enabled=yes
tlsenable=yes
tlscertfile=/etc/letsencrypt/live/DOMAIN/fullchain.pem
tlsprivatekey=/etc/letsencrypt/live/DOMAIN/privkey.pem
EOF'
docker exec voxcall-asterisk asterisk -rx 'core reload'
```
Replace `DOMAIN` with the actual domain (e.g., `voxtel.voxcall.cc`).

**Important:** The Asterisk container MUST have `/etc/letsencrypt` mounted as a volume. The `docker-compose.asterisk.yml` now includes `- /etc/letsencrypt:/etc/letsencrypt:ro` in the asterisk service volumes.

**Note:** Also check `ari.conf` — passwords may be truncated (e.g., `RiCa@853198` instead of full `RiCa@8531989898`).

### WebRTC audio issues (one-way or no audio)
1. Check if coturn is running: `systemctl status coturn`
2. Check coturn is listening on public IP: `ss -ulnp | grep 3478` (must show PUBLIC_IP:3478, not just 172.x)
3. Check TURN session logs: `grep -i 'session\|allocat\|error' /var/log/turnserver.log | tail -20`
4. Verify TURN settings in DB: `SELECT key,value FROM "Settings" WHERE key IN ('calling_turn_url','calling_turn_username','calling_turn_credential')`
5. For VoxCALL: Verify `sip-webrtc-config.json` has TURN server configured
6. Check browser console for ICE logs: `[WebRTC] ICE state:` (VoxZap) or `[SIP] ICE connection state:` (VoxCALL)
7. Check browser console for ICE candidate types: `[WebRTC] ICE candidate: relay` confirms TURN is working
8. Compare SDP Answer size: ~827 bytes = STUN only; ~962 bytes = STUN + TURN relay candidates
9. If ICE fails consistently, check firewall allows UDP+TCP 3478 and UDP 49152-65535

### coturn not starting
```bash
journalctl -u coturn -n 50
cat /var/log/turnserver.log
```
Common issues: port already in use, invalid config syntax, missing `TURNSERVER_ENABLED=1` in `/etc/default/coturn`.

---

## VoxGuard Security Agent (Asterisk VPS) — v1.2

VoxGuard is a custom security agent deployed alongside Asterisk on the VPS host. It monitors Asterisk logs and SSH auth logs, blocking attackers via nftables sets with kernel-managed auto-expiry. Supports both **Docker** and **native** Asterisk installations with auto-detection.

### Dual Mode Support (v1.2)
- **Auto-detection**: On startup, VoxGuard checks `systemctl is-active asterisk` and `docker inspect <container>` to determine the mode
- **Docker mode**: Reads logs via `docker logs -f <container>`, checks health via `docker inspect`
- **Native mode**: Reads logs via `tail -F /var/log/asterisk/full`, checks health via `systemctl is-active asterisk`
- **SSH monitoring**: Uses `/var/log/auth.log` if available, otherwise falls back to `journalctl -u sshd -u ssh -f`
- Config field `"mode"`: `"auto"` (default), `"docker"`, or `"native"` to force a mode
- Config field `"asterisk_log_path"`: custom log path for native mode (default: auto-detect)

### Deployment
- Files uploaded from `modelo_asterisk/voxguard/` to VPS `/opt/voxcall/voxguard/` during `generate-asterisk`
- `asterisk-deploy.sh` auto-installs: copies to `/opt/voxguard/`, installs systemd service, enables + starts
- Can also install/update independently via `/api/admin/ssh/voxguard/install` endpoint or UI at `/voxguard`
- **Install endpoint auto-installs nftables** if not present on VPS (via `apt-get install -y nftables`)
- **Runs on HOST** (systemd service), NOT inside Docker container
- **Service file** uses `After=network.target` (no Docker dependency) — works on any VPS

### Key Commands
```bash
systemctl status voxguard        # Check service status
systemctl restart voxguard       # Restart after config changes
journalctl -u voxguard -f        # Follow live logs
tail -f /var/log/voxguard.log    # Application log
cat /var/lib/voxguard/stats.json # Persistent statistics
nft list set inet voxguard blocked  # View blocked IPs
nft flush set inet voxguard blocked # Unblock all IPs
```

### Management
- UI page at `/voxguard` (SuperAdmin only, ADMINISTRADOR section in sidebar)
- Full documentation in `voxfone-telephony-crm` skill under "VoxGuard — Security Agent"

---

## VoxZap VPS Manual Deploy Workflow

For the VoxZap project (separate from VoxCALL), deploys are manual via SCP + Docker:

### VPS Info
- **Host**: voxtel.voxzap.app.br, **Port**: 22300, **User**: root
- **App path**: `/opt/voxzap/`, **Container**: `voxzap-app-1`
- **DB**: External PostgreSQL at `voxzap.voxserver.app.br:5432` (user: zpro, db: postgres)

### Deploy Steps (Code Update)
```bash
sshpass -p 'PASSWORD' scp -P 22300 <local_file> root@voxtel.voxzap.app.br:/opt/voxzap/<path>

ssh root@voxtel.voxzap.app.br -p 22300 "
  docker cp /opt/voxzap/<file> voxzap-app-1:/app/<file>
  docker exec voxzap-app-1 npx vite build --outDir dist/public
  cd /opt/voxzap && docker compose restart app
"
```

### Key Points
- VPS has NO git repo — files must be copied via SCP
- Frontend is served from `dist/public/` (pre-built) — must rebuild after changes
- Backend runs TypeScript directly (tsx) — restart container picks up changes
- `docker cp` copies into running container; rebuild needed only for frontend
- Always `Ctrl+Shift+R` (force refresh) in browser after frontend rebuild to clear cache
- Migrations: run SQL directly via `psql` from Replit against the external PostgreSQL

### Migration Pattern
```bash
PGPASSWORD='<password>' psql -h voxzap.voxserver.app.br -p 5432 -U zpro -d postgres -f migrations/<file>.sql
```

### Database Optimization Script
Production database optimization script at `scripts/db-optimize-production.sql`:
- Removes 17 redundant indexes (exact duplicates + prefix-covered)
- Adds 3 composite indexes: Tickets(tenantId, status, updatedAt DESC), Messages(ticketId, tenantId), Messages(tenantId, createdAt DESC)
- Adds UNIQUE constraint on TicketEvaluations(ticketId, tenantId)
- Cleans up duplicate evaluations before adding constraint
- **Already applied** to production DB on 2026-03-30. Run on new instances after initial Prisma migration.
- Note: `CREATE INDEX CONCURRENTLY` cannot run inside a transaction — script must be run outside BEGIN/COMMIT or split into individual statements.

## Replication Assistant (PostgreSQL Logical Replication)

### Overview
The VoxZap includes a built-in Replication Assistant at `/replication-assistant` (SuperAdmin-only) for configuring PostgreSQL logical replication between primary and replica databases. This allows read-heavy queries (dashboard, reports) to be routed to a replica, reducing load on the primary that handles webhooks and writes.

### Architecture

```
Writes (webhooks, tickets) → PRIMARY DB → WAL → REPLICA DB → Reads (dashboard, reports)
```

**Connection helpers** (`server/lib/db-config.ts`):
- `withExternalPg(fn)` — connects to PRIMARY (`db-config.json`), used for all WRITE operations
- `withReplicaPg(fn)` — connects to REPLICA (`db-replica-config.json`) with automatic fallback to PRIMARY if replica is unavailable
- `loadReplicaConfig()` / `saveReplicaConfig()` — manages `db-replica-config.json`

**Current routing**:
- Dashboard stats (`server/services/dashboard.service.ts`) → uses `withReplicaPg()` for all heavy aggregation queries
- All other reads → Prisma (PRIMARY)
- All writes → Prisma (PRIMARY)

### Frontend Page
- **Route**: `/replication-assistant` (SuperAdminRoute)
- **File**: `client/src/pages/replication-assistant.tsx`
- **Menu**: "Replicação DB" in system menu (Copy icon, superadminOnly)

### UI Components
1. **Status Badge** — real-time badge showing Active (green, with lag + table count) or Inactive
2. **Replica Config Form** — host, port, database, user, password, SSL toggle
3. **Replication Config** — replication user name, password, table selection (all or specific)
4. **5 Guided Steps**:
   - Step 1: Check Primary — verifies wal_level, publications, replication users
   - Step 2: Check Replica — verifies connection, subscriptions, tables
   - Step 3: Configure Primary — creates replication user + PUBLICATION
   - Step 4: Configure Replica — creates SUBSCRIPTION pointing to primary
   - Step 5: Verify Status — checks replication lag, active replicas
5. **Terminal** — colored output panel (green=success, red=error, yellow=warn, blue=info)
6. **Stop Replication** — drops SUBSCRIPTION and PUBLICATION
7. **How it Works** — informational card with requirements

### Backend Routes (`server/routes.ts`)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/admin/db-replica-config` | GET | Get current replica config (password masked) |
| `/api/admin/db-replica-config` | PUT | Save replica config |
| `/api/admin/db-replica-config/test` | POST | Test replica connection |
| `/api/admin/replication/check-primary` | POST | Verify primary DB readiness |
| `/api/admin/replication/check-replica` | POST | Verify replica DB readiness |
| `/api/admin/replication/configure-primary` | POST | Create replication user + PUBLICATION |
| `/api/admin/replication/configure-replica` | POST | Create SUBSCRIPTION |
| `/api/admin/replication/check-status` | POST | Check replication status + lag |
| `/api/admin/replication/stop` | POST | Stop replication (drop sub + pub) |
| `/api/admin/replication/quick-status` | GET | Quick status (active, lag, tables) — polled every 30s |
| `/api/admin/db-tables` | GET | List all tables in primary (for table selector) |

### Requirements for Logical Replication
- PostgreSQL 10+ on both primary and replica
- `wal_level = logical` on primary (requires PostgreSQL restart)
- Replica accessible via network from primary
- Schema (tables) already created on replica before activating
- Replication user with `REPLICATION` privilege on primary

### Config Files
- `db-replica-config.json` — stored in config volume (`/app/config/` in Docker)
  ```json
  {
    "host": "192.168.1.200",
    "port": 5432,
    "database": "postgres",
    "user": "postgres",
    "password": "...",
    "ssl": false,
    "enabled": true,
    "name": "Réplica"
  }
  ```
