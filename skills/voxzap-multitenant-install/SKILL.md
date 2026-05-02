---
name: voxzap-multitenant-install
description: Instalação e atualização do sistema VoxZap (WhatsApp/CRM, stack Prisma+Postgres+Node) em servidor multi-tenant compartilhado (padrão eveo*.voxserver.app.br). Use quando for provisionar novo tenant VoxZap, atualizar código de tenant existente, ou diagnosticar problemas de deploy. Cobre alocação de portas, build Docker, schema Prisma, seed automático, nginx HTTPS, certbot, e os bugs históricos descobertos durante a virada Locktec e o provisionamento Voxtel.
---

# VoxZap Multi-Tenant Install / Update

Skill para **instalar e atualizar** o sistema VoxZap (WhatsApp/CRM stack: Node.js + Prisma + PostgreSQL) em servidor multi-tenant compartilhado padrão Voxtel (`eveo*.voxserver.app.br`).

VoxZap é stack **diferente do VoxCALL**: NÃO tem Asterisk, NÃO tem SIP/RTP/AMI/ARI. É só app Node + Postgres + (opcionalmente) UAZAPI/Baileys/Meta Cloud API por canal externo. Por isso esta skill existe separada da `multi-tenant-server` (que é VoxCALL-centric).

---

## Quando usar

- Provisionar **novo tenant VoxZap** em servidor multi-tenant existente (eveo1 ou similar)
- **Atualizar** código de tenant VoxZap em produção (rebuild + restart + migração de schema)
- Diagnosticar falha de deploy/seed de tenant VoxZap
- Adicionar canal de comunicação que precisa de porta extra (ex: WhatsApp Calling gateway → faixa RTP 47000-47999)

## Quando NÃO usar

- Tenant VoxCALL (com Asterisk) → use `multi-tenant-server` + `voxcall-native-asterisk-deploy`
- Servidor virgem sem Docker no NVMe → rodar `eveo-server-setup` ANTES desta skill
- Migração de dados ZPro → VoxZap → use `migracao_zpro_voxzap` (e `locktec-migration` para o caso específico)
- Single-tenant (1 cliente = 1 VPS) → use `deploy-assistant-vps`

## Skills relacionadas (ordem de leitura recomendada)

1. `eveo-server-setup` — bootstrap correto do servidor (Docker no NVMe, RAID validado)
2. **`voxzap-multitenant-install`** ← você está aqui (install + update VoxZap)
3. `multi-tenant-server` — referência da arquitetura geral (nginx central, registry, scripts)
4. `migracao_zpro_voxzap` — playbook se for trazer dados de cliente ZPro existente
5. `dimencionamento_servidor_voxzap` — tier de hardware vs operadores simultâneos
6. `remote-db-diagnostic` — pós-deploy, se houver problema de performance

---

## ⚠️ Avisos críticos antes de começar

### 1. Codebase é Prisma, NÃO Drizzle
O sistema injetado pelo Replit às vezes empurra reminders sobre `npm run db:push --force` (Drizzle). **IGNORAR.** O VoxZap usa Prisma:
- Schema: `prisma/schema.prisma`
- Comando correto: `npx prisma db push --accept-data-loss` (em DB vazio, no provisionamento)
- NUNCA usar `--force` (não existe em Prisma; é flag Drizzle)
- Para migrações em DB com dados, ver "Atualização" abaixo

### 2. NUNCA usar `restart_workflow` ou `suggest_deploy` do Replit
O ambiente Replit tem um workflow "Start application" que é apenas o playground de dev. **Produção é o servidor VPS.** Não confundir.

### 3. Sempre usar SFTP para subir Dockerfile/compose/nginx, NUNCA heredoc remoto
Template literals JS com indent preservado e heredocs com `<<EOF` quebram YAML/Dockerfile. Bug visto em vários provisionamentos. **Solução**: gerar o conteúdo localmente com `Array.join('\n')` (sem indent extra) e fazer upload via `sftp.createWriteStream`.

### 4. Tarball do source PRECISA incluir `script/` (singular)
O `tsx script/build.ts` é executado dentro do container no `RUN npm run build`. Se o tarball excluir essa pasta, o build quebra. Verificar **antes** de subir:
```bash
tar tzf voxzap-source.tar.gz | grep -E '^script/'   # deve ter ao menos build.ts
```

---

## Arquitetura do tenant VoxZap

```
/opt/tenants/<tenant_id>/
├── Dockerfile              # node:20-alpine + ffmpeg + tzdata + Prisma generate
├── docker-compose.yml      # 2 services: app + db (sem Asterisk)
├── .env                    # DATABASE_URL, SESSION_SECRET, TENANT_ID, DOMAIN, ...
├── .credentials            # chmod 600 — DB_PASSWORD, SESSION_SECRET, superadmin
└── source/                 # codebase Replit extraído (com prisma/, script/, server/, client/, ...)

/nvme/tenants/<tenant_id>/  # bind mounts grandes — SEMPRE no NVMe
├── uploads/                # mídias WhatsApp/CRM
└── config/                 # configs persistentes do app

# Volume nomeado (também em /nvme/docker/volumes/ se Docker estiver no NVMe):
<tenant_id>_pgdata          # dados do Postgres
```

### Stack Docker

```yaml
# docker-compose.yml — gerar via Array.join('\n'), NUNCA com heredoc remoto
services:
  app:
    build: .
    container_name: <tenant_id>-app
    restart: unless-stopped
    ports:
      - "127.0.0.1:<APP_PORT>:5000"
    env_file: [.env]
    volumes:
      - /nvme/tenants/<tenant_id>/uploads:/app/uploads
      - /nvme/tenants/<tenant_id>/config:/app/config
    depends_on:
      db: { condition: service_healthy }
    networks: [tenant-net]
    mem_limit: 8g          # ajustar por tier (ver dimencionamento_servidor_voxzap)
    cpus: 8.0

  db:
    image: postgres:16
    container_name: <tenant_id>-db
    restart: unless-stopped
    environment:
      POSTGRES_USER: voxzap
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: voxzap
    volumes:
      - pgdata:/var/lib/postgresql/data
    ports:
      - "127.0.0.1:<DB_PORT>:5432"
    shm_size: "1gb"
    command:
      - postgres
      - -c
      - shared_buffers=2GB
      - -c
      - effective_cache_size=6GB
      - -c
      - shared_preload_libraries=pg_stat_statements
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U voxzap -d voxzap"]
      interval: 5s
      timeout: 5s
      retries: 10
    mem_limit: 8g
    cpus: 8.0

volumes:
  pgdata:

networks:
  tenant-net:
    driver: bridge
```

### Dockerfile padrão

```dockerfile
FROM node:20-alpine
RUN apk add --no-cache ffmpeg tzdata openssl
ENV TZ=America/Sao_Paulo
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
WORKDIR /app
COPY source/package*.json source/prisma ./
RUN npm ci --ignore-scripts && npx prisma generate
COPY source/ .
RUN npm run build
EXPOSE 5000
CMD ["npm", "start"]
```

### Alocação de portas

Mesma fórmula do `multi-tenant-server`, mas sem SIP/RTP/AMI/ARI:

| Serviço | Fórmula | Slot 1 | Slot 2 | Slot 3 | Bind |
|---|---|---|---|---|---|
| App HTTP | 5000 + N | 5001 | 5002 | 5003 | 127.0.0.1 |
| PostgreSQL | 25432 + N | 25433 | 25434 | 25435 | 127.0.0.1 |
| RTP gateway (WhatsApp Calling, opcional) | 47000 + ((N-1)×100) | 47000 | 47100 | 47200 | 0.0.0.0 |

Faixa RTP só é usada se o tenant tiver gateway de **WhatsApp Calling → Asterisk** (ver skill `whatsapp-asterisk-gateway`). Para tenants WhatsApp messaging-only (UAZAPI/Baileys/Meta), pular.

### Dimensionamento

| Operadores simultâneos | App | DB | Servidor mínimo |
|---|---|---|---|
| até 10 | 2g/2cpu | 2g/2cpu | 4 vCPU / 8 GB (vide skill `dimencionamento_servidor_voxzap`) |
| 10–32 | 8g/8cpu | 8g/8cpu | 8 vCPU / 16 GB (eveo1 nominal) |
| 32–60 | 16g/8cpu | 16g/8cpu | 16 vCPU / 32 GB |

---

## Fluxo de **instalação** de novo tenant VoxZap

### Pré-requisitos no servidor
- `eveo-server-setup` já rodada (Docker no NVMe, RAID validado, `/nvme` com folga)
- DNS do domínio do tenant apontando para o IP do servidor (`A` record)
- `/opt/tenants/_shared/tenant-registry.json` existe
- `/opt/tenants/nginx/` rodando (container `tenants-nginx`)
- Certbot binário disponível (`/usr/bin/certbot`) com webroot em `/var/www/certbot`

### 🛑 Pre-flight check OBRIGATÓRIO (rodar ANTES de qualquer mkdir/build)

Este check evita o bug histórico do Locktec: instalar tenant no SSD pequeno enquanto o NVMe grande fica ocioso. **Aborta com exit 1 se algo estiver errado.** Copiar e colar exatamente como está no servidor remoto:

```bash
set -e
echo '=== Pre-flight: detecção da melhor partição para o tenant ==='

# 1. Lista todos os filesystems montados, não-loop, não-tmpfs, ordenados por tamanho
echo '--- Volumes disponíveis ---'
df -BG --output=target,size,avail,pcent -x tmpfs -x devtmpfs -x squashfs 2>/dev/null \
  | tail -n +2 | sort -k2 -h -r

# 2. Identifica o MAIOR volume montado (descarta /boot, snap, overlay)
BEST_MOUNT=$(df -BG --output=target,size -x tmpfs -x devtmpfs -x squashfs 2>/dev/null \
  | tail -n +2 \
  | grep -vE '^/boot|^/snap|^/var/lib/docker/overlay|^/run' \
  | sort -k2 -h -r | head -1 | awk '{print $1}')
BEST_SIZE_G=$(df -BG --output=size "$BEST_MOUNT" | tail -1 | tr -dc '0-9')
BEST_AVAIL_G=$(df -BG --output=avail "$BEST_MOUNT" | tail -1 | tr -dc '0-9')
echo "→ Maior volume detectado: $BEST_MOUNT (${BEST_SIZE_G}G total, ${BEST_AVAIL_G}G livres)"

# 3. Onde Docker está armazenando dados?
DOCKER_ROOT=$(docker info 2>/dev/null | awk '/Docker Root Dir/{print $NF}')
DOCKER_MOUNT=$(df -BG --output=target "$DOCKER_ROOT" 2>/dev/null | tail -1)
DOCKER_AVAIL_G=$(df -BG --output=avail "$DOCKER_ROOT" 2>/dev/null | tail -1 | tr -dc '0-9')
echo "→ Docker root: $DOCKER_ROOT (em $DOCKER_MOUNT, ${DOCKER_AVAIL_G}G livres)"

# 4. HARD FAIL #1: Docker NÃO está no maior volume
if [ "$DOCKER_MOUNT" != "$BEST_MOUNT" ]; then
  echo "❌ ABORT: Docker está em $DOCKER_MOUNT mas o maior volume é $BEST_MOUNT."
  echo "   Rodar a skill 'eveo-server-setup' (seção 5: Procedimento de MIGRAÇÃO) ANTES de continuar."
  echo "   Resumo: parar Docker, mover /var/lib/docker para ${BEST_MOUNT}/docker,"
  echo "   ajustar /etc/docker/daemon.json com data-root=${BEST_MOUNT}/docker, restart."
  exit 1
fi

# 5. HARD FAIL #2: pouco espaço livre no maior volume (< 50G)
if [ "${BEST_AVAIL_G:-0}" -lt 50 ]; then
  echo "❌ ABORT: Apenas ${BEST_AVAIL_G}G livres em $BEST_MOUNT. Mínimo 50G por tenant VoxZap."
  echo "   Rodar 'docker system prune -a' ou expandir o volume antes de continuar."
  exit 1
fi

# 6. Se /nvme não existir mas o maior volume tiver outro nome, avisar e adaptar
TENANT_DATA_ROOT="${BEST_MOUNT}/tenants"
if [ "$BEST_MOUNT" != "/nvme" ]; then
  echo "⚠️  AVISO: maior volume é '$BEST_MOUNT' (não '/nvme'). Os bind mounts do tenant vão para:"
  echo "      $TENANT_DATA_ROOT/<tenant>/{uploads,config}"
  echo "   Atualizar docker-compose.yml com este path antes do 'docker compose up'."
fi

echo "✅ Pre-flight OK. Tenant será instalado em: $TENANT_DATA_ROOT"
echo "   Exportando para uso nos próximos passos:"
echo "   export TENANT_DATA_ROOT=$TENANT_DATA_ROOT"
```

**Regra**: nunca hardcode `/nvme/tenants/...` no docker-compose.yml até este check ter rodado e exportado `TENANT_DATA_ROOT`. Substituir todos os `/nvme/tenants/<tenant>` desta skill por `${TENANT_DATA_ROOT}/<tenant>` quando estiver gerando os templates.

**Por que este check existe (bug histórico Locktec — abril/2026)**: a equipe instalou Docker no padrão (`/var/lib/docker` no SSD ~100GB) sem perceber que o servidor tinha 1.8TB de NVMe RAID montado em `/nvme` totalmente ociosos. Resultado: SSD lotou em 2 semanas, app caiu, foi preciso parar tudo e migrar Docker pro NVMe (downtime). Este check captura essa situação ANTES de instalar qualquer coisa nova.

### Passo a passo

#### 1. Decidir slot e gerar credenciais (no Replit / local)
```javascript
// no code_execution
const slot = 3;  // ler do registry: registry.nextSlot
const TENANT_ID = 'voxzap-<cliente>';
const DOMAIN = '<cliente>.voxzap.cc';
const APP_PORT = 5000 + slot;
const DB_PORT = 25432 + slot;
const RTP_START = 47000 + (slot - 1) * 100;
const RTP_END = RTP_START + 99;

const crypto = await import('crypto');
const DB_PASSWORD = crypto.randomBytes(16).toString('hex');
const SESSION_SECRET = crypto.randomBytes(32).toString('hex');
```

Salvar em `.local/build/<tenant>.credentials` com chmod 600.

#### 2. Empacotar source (na máquina local/Replit)
```bash
# IMPORTANTE: incluir script/ (singular). Excluir o que não é source.
# Tambem excluir .agents/ (skills do agente, nao pertencem ao build do tenant).
# NAO listar 'public/' aqui — essa pasta NAO existe no projeto VoxZap atual
# (tar falha com exit code 2 e o tarball mesmo assim eh gerado, mas evite).
tar --exclude='node_modules' --exclude='.git' --exclude='dist' \
    --exclude='attached_assets' --exclude='.local' --exclude='*.log' \
    --exclude='screenshots' --exclude='.cache' --exclude='.agents' \
    -czf .local/build/voxzap-source.tar.gz \
    package.json package-lock.json tsconfig.json vite.config.ts \
    drizzle.config.ts components.json tailwind.config.ts postcss.config.js \
    prisma/ server/ client/ shared/ script/ uploads/.gitkeep

# Validar
tar tzf .local/build/voxzap-source.tar.gz | grep -cE '^(prisma|server|client|script)/'
# deve ser > 4 (em deploys recentes — 290 entradas dessas pastas)
md5sum .local/build/voxzap-source.tar.gz
ls -lh .local/build/voxzap-source.tar.gz   # tipico: ~1.1MB compactado
```

#### 3. Upload via SFTP (NUNCA scp + heredoc)
```javascript
// Subir o tarball para /tmp/<tenant>-source.tar.gz
const fs = await import('fs');
const { Client } = await import('ssh2');
function sftpUpload(localPath, remotePath) { /* createReadStream → createWriteStream */ }
await sftpUpload('.local/build/voxzap-source.tar.gz', `/tmp/${TENANT_ID}-source.tar.gz`);
```

#### 4. Criar diretórios + extrair
```bash
# IMPORTANTE: $TENANT_DATA_ROOT vem exportado pelo pre-flight check (acima).
# Em servidores EVEO padrão, será /nvme/tenants. Em outros provedores pode variar.
: "${TENANT_DATA_ROOT:?ERRO: pre-flight check não rodou. Voltar e executar a seção 'Pre-flight check OBRIGATÓRIO'.}"

mkdir -p /opt/tenants/<tenant>/source
mkdir -p $TENANT_DATA_ROOT/<tenant>/{uploads,config}
chmod 755 $TENANT_DATA_ROOT/<tenant>
tar xzf /tmp/<tenant>-source.tar.gz -C /opt/tenants/<tenant>/source
```

#### 5. Gerar Dockerfile, docker-compose.yml, .env, .credentials via SFTP
**Crítico**: gerar o conteúdo como `Array.join('\n')` no JS local e subir via SFTP write stream. NÃO usar heredoc no SSH — quebra YAML por causa de indentação preservada de template literals.

Validar antes do build:
```bash
cd /opt/tenants/<tenant> && docker compose config | head -20
```

#### 6. Build da imagem (~3-5 min)
```bash
cd /opt/tenants/<tenant>
docker compose build app 2>&1 | tail -30
docker images | grep <tenant>-app   # deve listar :latest, ~3GB
```

#### 7. Subir DB primeiro
```bash
docker compose up -d db
sleep 10
docker compose ps db   # status: healthy
```

#### 8. Criar schema via Prisma (DB vazio → seguro)
```bash
docker compose run --rm app npx prisma db push --accept-data-loss
# deve criar ~100 tabelas (depende da versão do schema)
docker compose exec db psql -U voxzap -d voxzap -c '\dt' | wc -l
```

⚠️ **Se a chamada acima falhar com `relation already exists`**, o DB NÃO está vazio. Provavelmente reusou volume de instalação anterior. Investigar antes de continuar.

#### 9. Subir app + verificar seed automático
```bash
docker compose up -d app
sleep 15
docker compose logs app --tail=80 | grep -iE 'seed|superadmin|listening|error'
```

O `server/seed.ts` roda **automaticamente** no primeiro boot e cria:
- 1 tenant inicial (nome do cliente)
- 1 user `superadmin@<dominio>` com senha **`RiCa$0808`** (hardcoded — alterar via UI no primeiro login)
- 4 settings padrão
- 2 integrações externas (UAZAPI placeholder etc.)

⚠️ **Se o log mostrar `seed already executed`**, o tenant foi reaproveitado. Verificar `SELECT count(*) FROM "Users"` antes de prosseguir.

#### 10. Atualizar registry
```bash
# Backup primeiro!
cp /opt/tenants/_shared/tenant-registry.json \
   /opt/tenants/_shared/tenant-registry.json.bak.$(date +%s)
# Editar via JS/python pra adicionar a entrada e bumpar nextSlot
```

Entrada padrão:
```json
"voxzap-<cliente>": {
  "slot": <N>,
  "domain": "<cliente>.voxzap.cc",
  "stack": "voxzap",
  "status": "active",
  "createdAt": "2026-04-24T16:10:00Z",
  "appPort": <APP_PORT>,
  "dbPort": <DB_PORT>,
  "rtpStart": <RTP_START>,
  "rtpEnd": <RTP_END>,
  "memoryLimit": "8G",
  "cpuLimit": "8.0",
  "notes": "VoxZap (sem Asterisk). Cliente <X>."
}
```

#### 11. Nginx HTTP-only + ACME challenge
```nginx
# /opt/tenants/nginx/conf.d/tenant_<tenant>.conf — HTTP-only inicial
server {
    listen 80;
    server_name <DOMAIN>;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 200 "<tenant> pending TLS"; add_header Content-Type text/plain; }
}
```

```bash
mkdir -p /var/www/certbot/.well-known/acme-challenge
docker exec tenants-nginx nginx -t && docker exec tenants-nginx nginx -s reload

# Validar ACME path antes do certbot (evita rate limit Let's Encrypt)
echo 'test' > /var/www/certbot/.well-known/acme-challenge/test
curl -m 10 http://<DOMAIN>/.well-known/acme-challenge/test  # deve retornar 'test'
rm -f /var/www/certbot/.well-known/acme-challenge/test
```

#### 12. Emitir certificado
```bash
certbot certonly --webroot -w /var/www/certbot \
  -d <DOMAIN> \
  --non-interactive --agree-tos -m suporte@voxtel.com.br \
  --keep-until-expiring
ls /etc/letsencrypt/live/<DOMAIN>/
openssl x509 -in /etc/letsencrypt/live/<DOMAIN>/cert.pem -noout -subject -dates
# auto-renew já configurado pelo certbot via systemd timer
```

#### 13. Substituir nginx pela config HTTPS completa
```nginx
server {
    listen 80;
    server_name <DOMAIN>;
    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://$host$request_uri; }
}
server {
    listen 443 ssl;
    http2 on;
    server_name <DOMAIN>;
    ssl_certificate /etc/letsencrypt/live/<DOMAIN>/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/<DOMAIN>/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    client_max_body_size 100M;

    location /api/login {
        limit_req zone=login_limit burst=3 nodelay;
        proxy_pass http://127.0.0.1:<APP_PORT>;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
    location /api/ {
        limit_req zone=api_limit burst=1000 nodelay;
        proxy_pass http://127.0.0.1:<APP_PORT>;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
    location / {
        proxy_pass http://127.0.0.1:<APP_PORT>;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";       # Socket.io precisa
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
}
```

```bash
docker exec tenants-nginx nginx -t && docker exec tenants-nginx nginx -s reload
```

#### 14. Validações obrigatórias end-to-end
```bash
# 1. HTTP -> HTTPS redirect
curl -sk -m 10 -o /dev/null -w 'HTTP %{http_code} redir=%{redirect_url}\n' http://<DOMAIN>/
# esperado: HTTP 301 redir=https://<DOMAIN>/

# 2. HTTPS root
curl -sk -m 10 -o /dev/null -w 'HTTP %{http_code} ssl_verify=%{ssl_verify_result}\n' https://<DOMAIN>/
# esperado: HTTP 200 ssl_verify=0

# 3. Health
curl -sk https://<DOMAIN>/api/health
# esperado: {"status":"healthy","database":"connected","uptime":...}

# 4. Login JWT (smoke test)
curl -sk https://<DOMAIN>/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"superadmin@<dominio>","password":"RiCa$0808"}' | jq .token
# esperado: string JWT longa
```

Se tudo passou: tenant ATIVO. Documentar no commit message.

---

## Fluxo de **atualização** (deploy de nova versão)

Para atualizar tenant existente com novo código (igual ao install, mas sem refazer DB/seed/nginx).

### Passo a passo

```bash
# 1. Backup do banco ANTES de qualquer deploy
docker compose -f /opt/tenants/<tenant>/docker-compose.yml exec -T db \
  pg_dump --format=custom --compress=6 -U voxzap voxzap \
  > /nvme/backups/<tenant>/db_pre_deploy_$(date +%Y%m%d_%H%M%S).dump

# 2. Subir o tarball novo
sftp upload .local/build/voxzap-source.tar.gz -> /tmp/<tenant>-source.tar.gz

# 3. Trocar source preservando o /app/uploads (que é bind mount, está fora do build)
cd /opt/tenants/<tenant>
mv source source.OLD
mkdir source
tar xzf /tmp/<tenant>-source.tar.gz -C source

# 4. Build
# ATENCAO ao timeout: docker build leva ~40-60s. Se rodar via scripts/clients/ssh.mjs,
# o default SSH_TIMEOUT_MS=60000 pode estourar. Sempre usar:
#   SSH_TIMEOUT_MS=180000 node scripts/clients/ssh.mjs <slug> '... docker compose build app ...'
# Se o bash local cair com exit -1 (timeout), o build CONTINUA na VPS — verificar com
# uma segunda chamada SSH curta consultando `docker images | grep <slug>-app` e
# `docker compose ps`.
docker compose build app 2>&1 | tail -20

# 5. Verificar se tem migração de schema pendente
# PARA DEPLOYS SOMENTE FRONTEND (sem mudancas em prisma/schema.prisma):
# pode pular este passo OU rodar mesmo assim — em deploys frontend-only o output
# tipico eh "The database is already in sync with the Prisma schema. Done in 500ms".
docker compose run --rm app npx prisma migrate status 2>&1 | tail -10
# OU, se o projeto não usa migrations (só db push):
docker compose run --rm app npx prisma db push --accept-data-loss --skip-generate
# IMPORTANTE: em PRODUÇÃO com dados, --accept-data-loss pode dropar colunas.
# Sempre revisar o diff ANTES (--dry-run não existe; usar `prisma migrate diff`).

# 6. Restart graceful (db continua up)
docker compose up -d --no-deps app
sleep 10

# 7. Validar
curl -sk https://<DOMAIN>/api/health | jq
docker compose logs app --tail=30 | grep -iE 'error|listening'

# (opcional) confirmar que o source novo realmente esta no container — util quando
# voce mudou um arquivo especifico e quer ter certeza que entrou no build:
grep -n '<string-distintiva-da-mudanca>' source/<caminho/do/arquivo>

# 8. Se tudo OK, limpar source antigo
rm -rf source.OLD
```

### Padrão "deploy compacto numa só chamada SSH" (quando a mudança é frontend-only)

Quando você está aplicando hotfix pequeno sem mudanças de schema, dá pra encadear
trocar-source + build + restart + validar numa única chamada `ssh.mjs` para reduzir
latência. **Sempre** com `set -e` e `SSH_TIMEOUT_MS=180000`:

```bash
SSH_TIMEOUT_MS=180000 node scripts/clients/ssh.mjs <slug> '
  set -e && cd /opt/tenants/<slug> &&
  rm -rf source.OLD && mv source source.OLD && mkdir source &&
  tar xzf /tmp/<slug>-source.tar.gz -C source &&
  echo "=== source trocado ===" &&
  grep -n "<string-distintiva-da-mudanca>" source/<caminho/do/arquivo> &&
  docker compose build app 2>&1 | tail -8 && echo "=== build OK ===" &&
  docker compose up -d --no-deps app && sleep 12 &&
  docker compose ps app &&
  curl -sk -o /dev/null -w "Health: HTTP %{http_code}\n" https://<DOMAIN>/api/health &&
  rm -rf source.OLD
'
```

O `grep` da string distintiva entre extract e build é o melhor sanity-check barato
para garantir que o tarball certo foi enviado.

### Rollback (se algo quebrar)

```bash
cd /opt/tenants/<tenant>
docker compose stop app
mv source source.NEW && mv source.OLD source
docker compose build app && docker compose up -d --no-deps app
# Para rollback de schema: pg_restore do backup feito no passo 1
```

---

## Hotfix CIRÚRGICO in-place no `dist/index.cjs` (sem rebuild)

Cenário raro mas real: bug pequeno, isolado, em produção; rebuild + deploy + restart é arriscado (downtime, schema drift entre tenants, janela proibida). Se a correção pode ser expressa como **substituição de bytes específicos** no bundle JavaScript já buildado (`/app/dist/index.cjs`), dá pra patcheá-lo in-place dentro do container, sem tocar no source/build/schema. Usado pela primeira vez em 2026-04-30 no voxzap-locktec (Tarefa #166, regex safety-net de transferência).

**Quando usar:**
- A mudança é estritamente literal (string→string, regex→regex) e cabe em `String.replaceAll`.
- Source no Replit já tem a versão correta — você só está empurrando a mesma correção que outro tenant já tem em produção.
- Schema do DB do tenant pode estar **desincronizado** do source (caso clássico: tenant velho com migração ZPro, source atual já evoluiu) — rebuild full quebraria.
- Janela de não-rebuild explicitamente solicitada pelo cliente.

**Quando NÃO usar:**
- Mudança envolve nova função, nova rota, nova dependência, nova variável de ambiente → REBUILD.
- Mudança envolve mais de ~3 substituições literais → maior risco de off-by-one, fazer rebuild.
- Não há backup confiável do schema atual.

### Procedimento (template)

```bash
# 1. SNAPSHOT pré-patch (host + container, com timestamp)
TS=$(date +%Y%m%d_%H%M%S)
node scripts/clients/ssh.mjs <tenant> "
  docker exec <tenant>-app md5sum /app/dist/index.cjs
  mkdir -p /opt/tenants/<tenant>/backups
  docker cp <tenant>-app:/app/dist/index.cjs /opt/tenants/<tenant>/backups/index.cjs.pre-hotfix-$TS
  docker exec <tenant>-app cp /app/dist/index.cjs /tmp/index.cjs.pre-hotfix-$TS
"

# 2. CONSTRUIR + TESTAR localmente o regex/string nova (testes positivos E negativos)
node .local/tmp/test_new_pattern.mjs   # ALL TESTS PASSED antes de prosseguir

# 3. PATCH SCRIPT em Node (NUNCA sed/awk — escape de caracteres não-ASCII vira inferno).
#    O script DEVE: contar ocorrências antes (esperado=N), aplicar replaceAll, contar depois
#    (esperado: N do antigo→0, N do novo após patch), comparar delta de bytes esperado vs real,
#    abortar com exit≠0 em qualquer divergência ANTES de writeFileSync.
node scripts/clients/upload.mjs <tenant> .local/tmp/patch.mjs /tmp/patch.mjs
node scripts/clients/ssh.mjs <tenant> "
  docker cp /tmp/patch.mjs <tenant>-app:/tmp/patch.mjs
  docker exec <tenant>-app node /tmp/patch.mjs
"

# 4. VALIDAR semanticamente: extrair o literal patcheado direto do bundle e rodar os mesmos
#    testes que rodaram localmente. Pega bugs de encoding/escape que grep não pega.
node scripts/clients/ssh.mjs <tenant> "docker exec <tenant>-app node /tmp/validate_in_bundle.mjs"

# 5. RESTART (graceful, ≤15s) + checar boot logs
node scripts/clients/ssh.mjs <tenant> "
  docker restart <tenant>-app
  sleep 10
  docker logs <tenant>-app --since 30s 2>&1 | grep -iE 'error|fatal|exception' | head
"

# 6. SMOKE: /api/health + baseline SQL read-only do KPI afetado pelo bug (registrar pré e pós)
curl -sk https://<dominio>/api/health
docker exec <tenant>-db psql -U voxzap -d voxzap -f baseline.sql
```

### Rollback (≤60s)

```bash
node scripts/clients/ssh.mjs <tenant> "
  docker cp /opt/tenants/<tenant>/backups/index.cjs.pre-hotfix-<TS> <tenant>-app:/app/dist/index.cjs
  docker restart <tenant>-app
"
```

### Verificação pós-rollback (OBRIGATÓRIA)

Rollback sem verificação pode mascarar restore parcial / arquivo errado. SEMPRE rodar este bloco logo após o rollback e SÓ declarar “revertido” se as 3 verificações passarem:

```bash
node scripts/clients/ssh.mjs <tenant> "
  echo '=== md5 atual deve bater com o md5 ORIGINAL pré-patch ==='
  docker exec <tenant>-app md5sum /app/dist/index.cjs
  md5sum /opt/tenants/<tenant>/backups/index.cjs.pre-hotfix-<TS>
  echo
  echo '=== /api/health deve estar healthy + database connected ==='
  curl -sk -m 5 https://<dominio>/api/health
  echo
  echo '=== boot logs últimos 60s sem error/fatal/exception ==='
  docker logs <tenant>-app --since 60s 2>&1 | grep -iE 'error|fatal|exception' | head -20 || echo '(sem erros)'
"
```

Se md5 atual ≠ md5 do backup: rollback falhou (arquivo errado). NÃO declarar revertido — repetir `docker cp` ou investigar.

Se /api/health não retornar `{"status":"healthy",...,"database":"connected"}`: app subiu corrupto. Container provavelmente em loop de restart — `docker logs` para diagnóstico.

Se logs mostrarem stack trace novo: rollback derrubou alguma config/dependência colateral. Avaliar antes de continuar.

### Marcador operacional no host (recomendado)

Ao patchear in-place, deixar um arquivo de aviso no diretório do tenant para operadores que façam manutenção futura sem ler o `replit.md`:

```bash
node scripts/clients/ssh.mjs <tenant> "
  cat > /opt/tenants/<tenant>/HOTFIX-IN-PLACE-NOTICE.txt <<EOF
ATENÇÃO: container <tenant>-app contém HOTFIX IN-PLACE no /app/dist/index.cjs
Aplicado em: <TS_BRT>
Tarefa: #<N>
Causa: <descrição curta>
md5 pré-patch:  <md5_antes>
md5 pós-patch:  <md5_depois>
Backup do bundle pré-patch: /opt/tenants/<tenant>/backups/index.cjs.pre-hotfix-<TS>

⚠️ NÃO rodar 'docker compose build app' ou 'docker compose up --force-recreate'
   sem antes garantir que o source em /opt/tenants/<tenant>/source/ está
   sincronizado com a versão do Replit que originou o patch.
   Caso contrário o build sobrescreve o hotfix e o bug volta.

Documentação completa: replit.md → 'Production Hotfixes Log'
EOF
  ls -la /opt/tenants/<tenant>/HOTFIX-IN-PLACE-NOTICE.txt
"
```

Esse arquivo é a “senha” pra qualquer pessoa que SSH-e direto na VPS sem passar pelo Replit. Remover só após o próximo deploy sincronizado.

### Regras invioláveis do hotfix in-place

1. **NUNCA** usar `sed` / `awk` / `tr` para o patch — Unicode (ç, á, ê) e backslashes escapados explodem silenciosamente.
2. **SEMPRE** `String.replaceAll` em Node, com **assertion de count** antes e depois da substituição. Se contou diferente do esperado, abortar **antes** de `writeFileSync`.
3. **SEMPRE** dois backups: host (`/opt/tenants/<tenant>/backups/`) + container (`/tmp/`). O do container salva você se o host estiver indisponível na hora do rollback.
4. **SEMPRE** documentar o md5 antes/depois e o delta de bytes esperado, para auditoria.
5. **SEMPRE** documentar no `replit.md` (seção "Production Hotfixes Log") com data, tenant, causa-raiz, identidade dos literais substituídos, md5 antes/depois, paths dos backups, e plano de rollback. O patch SOBREESCREVE no próximo build/deploy do tenant — quem fizer o próximo deploy precisa saber que o source TEM que estar sincronizado.
6. **NÃO** rodar testes e2e que possam gerar tickets reais / mensagens reais. Validação é via teste sintético do regex/string carregado do próprio bundle (passo 4) + monitoramento passivo do KPI afetado (passo 6+).

### Caso de referência: Tarefa #166

- Tenant: `voxzap-locktec` (eveo1, slot 2)
- Bundle: `/app/dist/index.cjs` (3.064.601 → 3.065.891 bytes, +1.277)
- md5: `19ab35e60adf4d764d6cb3c5c987fa65` → `df99dfddc70ad50242aa11193f1bed6b`
- Substituídos: 2 regex literais permissivas (offsets 1.772.236 e 1.774.228) por uma única regex estrita (851 chars de source) compilada do `server/services/ai-agent.service.ts:35-68`.
- Tempo total: ~10 min (snapshot + patch + validação + restart + smoke).
- Ver `replit.md` → "Production Hotfixes Log" para detalhes completos.

---

## Bugs históricos resolvidos (não repetir)

| # | Bug | Sintoma | Causa | Fix |
|---|---|---|---|---|
| 1 | Tarball sem `script/` | `tsx script/build.ts: not found` no build | `--exclude` muito agressivo no tar | Listar pastas explicitamente em vez de excluir |
| 2 | Heredoc remoto quebra YAML | `docker compose config` falha com indent inconsistente | Template literal preserva indent de IDE | Gerar string como `Array.join('\n')` e subir via SFTP |
| 3 | `prisma db push --force` | comando inválido | `--force` é flag Drizzle, não Prisma | Usar `--accept-data-loss` (em DB vazio) |
| 4 | Reuso de volume `<tenant>_pgdata` | Seed pula, login falha com "user exists" | Volume nomeado herdado de instalação anterior | `docker volume rm <tenant>_pgdata` ANTES do `compose up db` se for instalação limpa |
| 5 | nginx reload não aplica | Config nova ignorada | `tenants-nginx` é container, host nginx pode estar instalado em paralelo | SEMPRE `docker exec tenants-nginx nginx -s reload`, nunca `systemctl reload nginx` |
| 6 | Cert Let's Encrypt rate-limit | `too many failed authorizations` | Tentou certbot antes do DNS propagar / antes do ACME path responder | Validar `curl http://<dominio>/.well-known/acme-challenge/test` ANTES do certbot |
| 7 | Socket.io não conecta via HTTPS | WebSocket falha 400 | Falta `Upgrade`/`Connection` headers no `location /` | Incluir `proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade";` |
| 8 | App OOM no boot | Container reinicia loop | `mem_limit` 2g insuficiente para Prisma client + UAZAPI + Socket | Subir para 4g/8g conforme tier |

---

## Histórico de provisionamentos VoxZap

| Tenant | Servidor | Slot | Domínio | Data | Notas |
|---|---|---|---|---|---|
| voxzap-locktec | eveo1 | 2 | locktec.voxzap.cc | 2026-04-19 | Primeira virada ZPro→VoxZap. Migração de 1.2M msgs + 13GB mídias. Ver `locktec-migration`. |
| voxzap-voxtel | eveo1 | 3 | voxtel.voxzap.cc | 2026-04-24 | Tenant interno Voxtel. Padrão 8g/8cpu. Volumes em /nvme. UAZAPI integrado. |

Adicionar nova linha aqui a cada novo tenant provisionado. Marcar `notas` se foi instalação limpa, migração corretiva, ou se teve particularidade.

---

## Checklist final (copiar pro commit message)

- [ ] **Pre-flight check rodou e exportou `TENANT_DATA_ROOT`** (Docker está no maior volume, ≥50G livres)
- [ ] DNS do `<DOMAIN>` resolvendo para o IP do servidor
- [ ] Slot decidido e portas calculadas (App + DB + RTP se aplicável)
- [ ] Credenciais geradas e salvas em `.local/build/<tenant>.credentials` (chmod 600)
- [ ] Tarball gerado com `script/` incluído (validado com `tar tzf | grep script`)
- [ ] Diretórios criados em `/opt/tenants/<tenant>` e `$TENANT_DATA_ROOT/<tenant>`
- [ ] Dockerfile + docker-compose.yml + .env subidos via SFTP (não heredoc)
- [ ] `docker compose config` validou OK
- [ ] Imagem buildada (~3GB)
- [ ] DB up + healthy
- [ ] `prisma db push` criou tabelas (contar com `\dt` no psql)
- [ ] App up, seed automático rodou (superadmin + tenant + settings)
- [ ] Registry atualizado (com backup `.bak.<timestamp>`)
- [ ] Nginx HTTP-only + ACME path respondendo HTTP 200
- [ ] Cert Let's Encrypt emitido (validade > 80 dias)
- [ ] Nginx HTTPS completo + reload OK
- [ ] HTTP→HTTPS 301 ✓
- [ ] HTTPS / → 200 com SSL válido ✓
- [ ] /api/health → `healthy` + `connected` ✓
- [ ] /api/auth/login com superadmin → JWT recebido ✓
- [ ] Linha adicionada no histórico desta skill
