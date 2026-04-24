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
tar --exclude='node_modules' --exclude='.git' --exclude='dist' \
    --exclude='attached_assets' --exclude='.local' --exclude='*.log' \
    --exclude='screenshots' --exclude='.cache' \
    -czf .local/build/voxzap-source.tar.gz \
    package.json package-lock.json tsconfig.json vite.config.ts \
    drizzle.config.ts components.json tailwind.config.ts postcss.config.js \
    prisma/ server/ client/ shared/ script/ public/ uploads/.gitkeep

# Validar
tar tzf .local/build/voxzap-source.tar.gz | grep -cE '^(prisma|server|client|script)/'
# deve ser > 4
md5sum .local/build/voxzap-source.tar.gz
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
mkdir -p /opt/tenants/<tenant>/source
mkdir -p /nvme/tenants/<tenant>/{uploads,config}
chmod 755 /nvme/tenants/<tenant>
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
docker compose build app 2>&1 | tail -20

# 5. Verificar se tem migração de schema pendente
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

# 8. Se tudo OK, limpar source antigo
rm -rf source.OLD
```

### Rollback (se algo quebrar)

```bash
cd /opt/tenants/<tenant>
docker compose stop app
mv source source.NEW && mv source.OLD source
docker compose build app && docker compose up -d --no-deps app
# Para rollback de schema: pg_restore do backup feito no passo 1
```

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

- [ ] DNS do `<DOMAIN>` resolvendo para o IP do servidor
- [ ] Slot decidido e portas calculadas (App + DB + RTP se aplicável)
- [ ] Credenciais geradas e salvas em `.local/build/<tenant>.credentials` (chmod 600)
- [ ] Tarball gerado com `script/` incluído (validado com `tar tzf | grep script`)
- [ ] Diretórios criados em `/opt/tenants/<tenant>` e `/nvme/tenants/<tenant>`
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
