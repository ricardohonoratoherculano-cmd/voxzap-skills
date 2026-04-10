---
name: voxcall-native-asterisk-deploy
description: Deploy do VoxCALL em VPS onde o Asterisk roda nativamente (não em Docker). Use quando precisar fazer deploy, atualizar, debugar ou estender o VoxCALL em uma VPS que já tem Asterisk instalado diretamente no host, com Docker Swarm, Nginx Proxy Manager, e PostgreSQL em container. Diferente do deploy-assistant-vps (Docker Compose completo), este cenário integra o VoxCALL como um serviço Swarm adicional ao ecossistema existente.
---

# Deploy VoxCALL — Asterisk Nativo na VPS

Skill para deploy e manutenção do VoxCALL em VPS onde o Asterisk roda **diretamente no host** (não em Docker). O VoxCALL é adicionado como um serviço Docker Swarm ao ecossistema já existente, sem afetar os serviços em produção.

## Quando Usar

- Deploy do VoxCALL em VPS com Asterisk nativo
- Atualização de código do VoxCALL em VPS com Swarm
- Debug de conectividade entre container VoxCALL e Asterisk nativo
- Configuração de proxy reverso no Nginx Proxy Manager
- Gerenciamento de certificados SSL via NPM + Let's Encrypt
- Troubleshooting de banco de dados compartilhado/separado

## Quando NÃO Usar

- Deploy com Docker Compose completo (Asterisk em Docker) → use `deploy-assistant-vps`
- Deploy com Asterisk em container Docker → use `deploy-assistant-vps`
- Configuração do Asterisk em si (dialplan, PJSIP, etc.) → use skills de Asterisk

## Diferenças Chave vs deploy-assistant-vps

| Aspecto | deploy-assistant-vps | Este cenário (Asterisk nativo) |
|---------|---------------------|-------------------------------|
| Asterisk | Docker container | Instalado no host |
| Orquestração | Docker Compose | Docker Swarm |
| PostgreSQL | Container próprio | Container compartilhado existente |
| Nginx/SSL | Container nginx ou NPM | Nginx Proxy Manager (NPM) existente |
| Rede | Bridge ou custom | Overlay Swarm (`nginx_network`) |
| DB VoxCALL | Banco dedicado (`voxcall-db`) | Banco separado no PostgreSQL existente |
| Gravações | Volume montado do container Asterisk | Bind mount do diretório do host |
| AMI/ARI | Via hostname Docker interno | Via IP público ou hostname da VPS |

## Arquitetura de Referência — VPS modelo.voxtel.app.br

### Infraestrutura Existente
```
VPS (85.31.63.92 / modelo.voxtel.app.br)
├── Asterisk (nativo, não Docker)
│   ├── AMI: porta 5038 (user: primax, pass: primax@123)
│   ├── ARI: porta 8088 (user: voxari, pass: RiCa@8531989898)
│   ├── Gravações: /var/spool/asterisk/monitor/
│   └── chan_sip/PJSIP: portas SIP padrão
├── Docker Swarm
│   ├── npm_npm (Nginx Proxy Manager) — portas 80/443
│   ├── postgres_postgres (PostgreSQL 16) — porta 25432
│   ├── voxcall_voxcall (VoxCALL app) — porta 5000
│   ├── apache-php_apache_php (sistemas legados)
│   ├── voxdial_voxdial (discador)
│   ├── voxtel-monitor_voxtel_monitor
│   ├── voxtel-agente_voxtel_agente
│   ├── portainer_portainer — porta 9000
│   ├── node-red_node-red
│   ├── vox-iot_emqx (MQTT)
│   └── outros serviços...
│   └── Rede overlay: nginx_network (compartilhada por todos)
└── coturn (TURN server, nativo) — porta 3478
```

### VoxCALL Service — Configuração Completa

```bash
docker service create \
  --name voxcall_voxcall \
  --network nginx_network \
  --replicas 1 \
  --mount type=bind,source=/opt/voxcall/config,target=/app/config \
  --mount type=bind,source=/var/spool/asterisk/monitor,target=/var/spool/asterisk/monitor,readonly \
  --env NODE_ENV=production \
  --env DATABASE_URL="postgresql://asterisk:PASSWORD@postgres_postgres:5432/voxcall" \
  --env PORT=5000 \
  --env SESSION_SECRET=voxcall-production-secret-XXXX \
  --env TZ=America/Sao_Paulo \
  --env SUPERADMIN_PASSWORD=SENHA_SUPERADMIN \
  --env SUPERADMIN_USERNAME=superadmin \
  --env SUPERADMIN_EMAIL=email@dominio.com \
  --limit-memory 512M \
  --reserve-memory 256M \
  voxcall:latest
```

**Variáveis de ambiente obrigatórias:**

| Variável | Descrição | Exemplo |
|----------|-----------|---------|
| `NODE_ENV` | Modo de execução | `production` |
| `DATABASE_URL` | Conexão Drizzle ORM (banco `voxcall`) | `postgresql://user:pass@postgres_postgres:5432/voxcall` |
| `PORT` | Porta do Express | `5000` |
| `SESSION_SECRET` | Segredo para sessões Express | `voxcall-production-secret-2026` |
| `TZ` | Timezone | `America/Sao_Paulo` |
| `SUPERADMIN_PASSWORD` | Senha do superadmin (criado/atualizado no boot) | `RiCa$0808` |
| `SUPERADMIN_USERNAME` | Username do superadmin | `superadmin` |
| `SUPERADMIN_EMAIL` | Email do superadmin | `ricardo@voxtel.biz` |

**Volumes montados:**

| Host Path | Container Path | Modo | Propósito |
|-----------|---------------|------|-----------|
| `/opt/voxcall/config` | `/app/config` | read-write | Configs JSON persistentes (db-config, ami-config, ari-config, ssh-config, smtp-config, etc.) |
| `/var/spool/asterisk/monitor` | `/var/spool/asterisk/monitor` | read-only | Gravações de chamadas do Asterisk nativo |

## Deploy Passo a Passo

### 1. Criar Dockerfile

```dockerfile
FROM node:20-alpine
RUN apk add --no-cache ffmpeg tzdata
ENV TZ=America/Sao_Paulo
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
WORKDIR /app
COPY package*.json ./
RUN npm ci --ignore-scripts
COPY . .
RUN npm run build
EXPOSE 5000
CMD ["npm", "start"]
```

**Regras do Dockerfile:**
- **Single-stage obrigatório** — NÃO usar multi-stage, NÃO fazer `npm prune --production` (vite é importado em runtime por `server/vite.ts`)
- **ffmpeg obrigatório** — Converte gravações GSM→MP3 para playback no browser
- **tzdata obrigatório** — Timezone correta para logs e timestamps
- **`--ignore-scripts`** — Evita erros com scripts de build de dependências opcionais

### 2. Empacotar e Enviar Código

```bash
# No workspace Replit
tar czf /tmp/voxcall-source.tar.gz \
  --exclude=node_modules --exclude=.git --exclude=dist --exclude=.cache \
  --exclude=attached_assets --exclude=.agents --exclude=.local \
  --exclude='*.tar.gz' --exclude=scripts \
  --exclude=docker-compose.yml --exclude=Dockerfile \
  --exclude=deploy.sh --exclude=nginx.conf --exclude=.env \
  --exclude=docker --exclude=.config --exclude=.upm \
  -C /home/runner/workspace .

# Upload via SCP
sshpass -p 'PASSWORD' scp -P SSH_PORT /tmp/voxcall-source.tar.gz /tmp/Dockerfile.voxcall root@VPS_HOST:/opt/voxcall/
```

### 3. Extrair e Buildar no VPS

```bash
# No VPS via SSH
mkdir -p /opt/voxcall/source
cd /opt/voxcall/source
tar xzf /opt/voxcall/voxcall-source.tar.gz
cp /opt/voxcall/Dockerfile.voxcall Dockerfile

# Docker Hub auth pode dar erro — logout antes se necessário
docker logout 2>/dev/null

# Build em background (pode levar 2-5 minutos)
nohup docker build -t voxcall:latest . > /opt/voxcall/build.log 2>&1 &
# Monitorar: tail -f /opt/voxcall/build.log
```

### 4. Criar Banco de Dados Separado

**CRÍTICO: NÃO usar o banco `asterisk` existente para as tabelas do Drizzle/VoxCALL.**

O Asterisk já tem dezenas de tabelas (cdr, queue_log, sip_conf, etc.) no banco `asterisk`. O `drizzle-kit push` ficará em modo interativo tentando renomear essas tabelas existentes.

```bash
# Criar banco dedicado
PGCONTAINER=$(docker ps --format "{{.Names}}" | grep postgres_postgres)
docker exec -e PGPASSWORD="DB_PASSWORD" $PGCONTAINER psql -U asterisk -d postgres -c "CREATE DATABASE voxcall OWNER asterisk;"
```

**Resultado:** Duas bases de dados coexistem no mesmo PostgreSQL:
- `asterisk` — Tabelas do Asterisk (cdr, queue_log, sip_conf, etc.) — acessado via `db-config.json` para queries CDR
- `voxcall` — Tabelas do VoxCALL (users, extensions, trunks, etc.) — acessado via `DATABASE_URL`

### 5. Criar Serviço Docker Swarm

```bash
docker service create \
  --name voxcall_voxcall \
  --network nginx_network \
  --replicas 1 \
  --mount type=bind,source=/opt/voxcall/config,target=/app/config \
  --mount type=bind,source=/var/spool/asterisk/monitor,target=/var/spool/asterisk/monitor,readonly \
  --env NODE_ENV=production \
  --env DATABASE_URL="postgresql://asterisk:PASSWORD@postgres_postgres:5432/voxcall" \
  --env PORT=5000 \
  --env SESSION_SECRET=voxcall-production-secret-XXXX \
  --env TZ=America/Sao_Paulo \
  --env SUPERADMIN_PASSWORD=SENHA \
  --env SUPERADMIN_USERNAME=superadmin \
  --env SUPERADMIN_EMAIL=email@dominio.com \
  --limit-memory 512M \
  --reserve-memory 256M \
  voxcall:latest
```

### 6. Push do Schema Drizzle

```bash
CONTAINER=$(docker ps --format "{{.Names}}" | grep voxcall_voxcall | head -1)
docker exec $CONTAINER npx drizzle-kit push --force
# Depois reiniciar para o seed rodar com as tabelas criadas
docker service update --force voxcall_voxcall
```

### 7. Configurar Nginx Proxy Manager (NPM)

O NPM usa um banco SQLite interno. A configuração pode ser feita pela UI (porta 81) ou diretamente via database + nginx config.

**Via NPM API (se credenciais disponíveis):**
```bash
# Obter token
TOKEN=$(curl -s http://localhost:81/api/tokens -H "Content-Type: application/json" \
  -d '{"identity":"email@dominio.com","secret":"senha"}' | jq -r .token)

# Criar proxy host
curl -s http://localhost:81/api/nginx/proxy-hosts -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"domain_names":["DOMINIO"],"forward_scheme":"http","forward_host":"voxcall_voxcall","forward_port":5000,"allow_websocket_upgrade":1}'
```

**Via manipulação direta do banco (se credenciais NPM desconhecidas):**
```bash
NPM_CONTAINER=$(docker ps --format "{{.Names}}" | grep npm)

# Descobrir admin email
docker exec $NPM_CONTAINER node -e "
const knex = require('knex')({client:'sqlite3',connection:{filename:'/data/database.sqlite'},useNullAsDefault:true});
knex('user').select('id','email','nickname').then(r=>{console.log(JSON.stringify(r));knex.destroy()});
"

# Inserir proxy host
docker exec $NPM_CONTAINER node -e "
const knex = require('knex')({client:'sqlite3',connection:{filename:'/data/database.sqlite'},useNullAsDefault:true});
knex('proxy_host').insert({
  created_on: new Date().toISOString(),
  modified_on: new Date().toISOString(),
  owner_user_id: 1,
  is_deleted: 0,
  domain_names: JSON.stringify(['DOMINIO']),
  forward_host: 'voxcall_voxcall',
  forward_port: 5000,
  access_list_id: 0,
  certificate_id: 0,
  ssl_forced: 0,
  caching_enabled: 0,
  block_exploits: 0,
  advanced_config: '',
  meta: JSON.stringify({letsencrypt_agree:true,dns_challenge:false,nginx_online:true,nginx_err:null}),
  allow_websocket_upgrade: 1,
  http2_support: 0,
  forward_scheme: 'http',
  enabled: 1,
  locations: '[]',
  hsts_enabled: 0,
  hsts_subdomains: 0
}).then(r=>{console.log('Inserted ID:',r[0]);knex.destroy()});
"
```

**Nginx config file — formato NPM padrão (sem SSL):**
```nginx
# DOMINIO
server {
  set $forward_scheme http;
  set $server         "voxcall_voxcall";
  set $port           5000;
  listen 80;
  listen [::]:80;
  server_name DOMINIO;
  include conf.d/include/letsencrypt-acme-challenge.conf;
  access_log /data/logs/proxy-host-ID_access.log proxy;
  error_log /data/logs/proxy-host-ID_error.log warn;
  location / {
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $http_connection;
    proxy_http_version 1.1;
    include conf.d/include/proxy.conf;
  }
  include /data/nginx/custom/server_proxy[.]conf;
}
```

**REGRA:** O `include conf.d/include/proxy.conf` do NPM **já contém** `proxy_pass`, `proxy_set_header Host`, `X-Forwarded-*`, etc. NUNCA adicionar `proxy_pass` explícito junto com `include proxy.conf` — causa erro `duplicate directive`.

### 8. Certificado SSL via Let's Encrypt

**Pré-requisito:** DNS do domínio deve apontar para o IP da VPS.

```bash
NPM_CONTAINER=$(docker ps --format "{{.Names}}" | grep npm)

# Solicitar certificado
docker exec $NPM_CONTAINER certbot certonly \
  --webroot --webroot-path /data/letsencrypt-acme-challenge \
  -d DOMINIO \
  --agree-tos --email EMAIL \
  --non-interactive

# Registrar certificado no NPM
docker exec $NPM_CONTAINER node -e "
const knex = require('knex')({client:'sqlite3',connection:{filename:'/data/database.sqlite'},useNullAsDefault:true});
knex('certificate').insert({
  created_on: new Date().toISOString(),
  modified_on: new Date().toISOString(),
  owner_user_id: 1,
  is_deleted: 0,
  provider: 'letsencrypt',
  nice_name: 'DOMINIO',
  domain_names: JSON.stringify(['DOMINIO']),
  expires_on: new Date(Date.now()+90*86400000).toISOString(),
  meta: JSON.stringify({letsencrypt_certificate:{cn:'DOMINIO'},letsencrypt_agree:true,dns_challenge:false})
}).then(r=>{
  const certId = r[0];
  console.log('Certificate ID:', certId);
  return knex('proxy_host').where('domain_names','like','%DOMINIO%').update({
    certificate_id: certId,
    ssl_forced: 1,
    modified_on: new Date().toISOString()
  });
}).then(()=>{console.log('SSL enabled');knex.destroy()});
"
```

**Nginx config com SSL (substituir o arquivo anterior):**
```nginx
# DOMINIO
map $scheme $hsts_header {
    https   "max-age=63072000; preload";
}
server {
  set $forward_scheme http;
  set $server         "voxcall_voxcall";
  set $port           5000;
  listen 80;
  listen [::]:80;
  listen 443 ssl;
  listen [::]:443 ssl;
  server_name DOMINIO;
  include conf.d/include/letsencrypt-acme-challenge.conf;
  include conf.d/include/ssl-ciphers.conf;
  ssl_certificate /etc/letsencrypt/live/DOMINIO/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/DOMINIO/privkey.pem;
  include conf.d/include/force-ssl.conf;
  access_log /data/logs/proxy-host-ID_access.log proxy;
  error_log /data/logs/proxy-host-ID_error.log warn;
  location / {
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $http_connection;
    proxy_http_version 1.1;
    include conf.d/include/proxy.conf;
  }
  include /data/nginx/custom/server_proxy[.]conf;
}
```

Sempre testar e recarregar após alterar:
```bash
docker exec $NPM_CONTAINER nginx -t && docker exec $NPM_CONTAINER nginx -s reload
```

## Conectividade Container → Asterisk Nativo

Quando o Asterisk roda no host (não em Docker), o container precisa acessá-lo via:

1. **IP público/hostname da VPS** — funciona sempre, mas tráfego sai e volta pela rede
2. **IP do Docker gateway** — `172.17.0.1` ou `172.18.0.1` (verificar com `ip route` dentro do container)
3. **host.docker.internal** — disponível em Docker Swarm com `--host` flag (nem sempre funciona em overlay)

**Recomendação:** Usar o hostname/IP público da VPS nos arquivos de configuração (`ami-config.json`, `ari-config.json`). É o método mais confiável.

```json
// /opt/voxcall/config/ami-config.json
{
  "host": "modelo.voxtel.app.br",
  "port": 5038,
  "username": "primax",
  "password": "primax@123"
}

// /opt/voxcall/config/ari-config.json
{
  "host": "modelo.voxtel.app.br",
  "port": 8088,
  "username": "voxari",
  "password": "RiCa@8531989898",
  "protocol": "http"
}
```

**Portas do Asterisk que o VoxCALL acessa:**
- **5038** — AMI (Asterisk Manager Interface) — controle e eventos
- **8088** — ARI HTTP (Asterisk REST Interface) — API REST
- **8089** — ARI WebSocket (se habilitado) — eventos em tempo real

## Dual Database Pattern

O VoxCALL acessa **dois bancos de dados** simultaneamente:

### 1. Banco `voxcall` (via DATABASE_URL / Drizzle ORM)
- Tabelas internas: `users`, `extensions`, `trunks`, `dialplans`, `backups`, `agent_conversations`, `diagnostic_conversations`, `password_reset_tokens`, etc.
- Gerenciado pelo Drizzle ORM com `drizzle-kit push`
- Conexão: `postgresql://asterisk:PASS@postgres_postgres:5432/voxcall`

### 2. Banco `asterisk` (via db-config.json / pg Client direto)
- Tabelas do Asterisk: `cdr`, `queue_log`, `sip_conf`, `queue_table`, etc.
- Acessado por `withExternalPg()` e `withReplicaPg()` usando `pg.Client`
- Usado para relatórios CDR, call center, gravações, status de filas
- Conexão configurada em `/app/config/db-config.json`

```json
// /opt/voxcall/config/db-config.json — aponta para o banco ASTERISK
{
  "host": "postgres_postgres",
  "port": 5432,
  "database": "asterisk",
  "username": "asterisk",
  "password": "RiCa$853198",
  "ssl": false
}
```

**REGRA:** O `db-config.json` dentro do container deve usar o hostname Docker interno (`postgres_postgres`) e a porta interna (`5432`), NÃO o hostname externo com porta `25432`.

### getConfigDir() — Resolução de Caminhos

```typescript
// server/external-pg.ts
export function getConfigDir(): string {
  if (process.env.NODE_ENV === 'production') {
    return path.join(process.cwd(), 'config');  // /app/config/
  }
  return process.cwd();  // desenvolvimento: raiz do projeto
}
```

Em produção, todos os configs estão em `/app/config/` (montado de `/opt/voxcall/config/` no host).

## Atualização de Código (Update)

Para atualizar o VoxCALL sem perder dados:

```bash
# 1. No Replit: criar novo tarball
tar czf /tmp/voxcall-source.tar.gz --exclude=node_modules --exclude=.git ...

# 2. Upload para VPS
sshpass -p 'PASS' scp -P PORT /tmp/voxcall-source.tar.gz root@VPS:/opt/voxcall/

# 3. No VPS: extrair, rebuildar, atualizar serviço
cd /opt/voxcall/source
rm -rf *
tar xzf /opt/voxcall/voxcall-source.tar.gz
cp /opt/voxcall/Dockerfile.voxcall Dockerfile

# Build
docker build -t voxcall:latest .

# Schema sync (sem --force-reset = preserva dados)
docker service update --force voxcall_voxcall
sleep 15
CONTAINER=$(docker ps --format "{{.Names}}" | grep voxcall_voxcall | head -1)
docker exec $CONTAINER npx drizzle-kit push --force

# Reiniciar com schema atualizado
docker service update --force voxcall_voxcall
```

## Troubleshooting

### Container não consegue conectar ao PostgreSQL
- Verificar se o serviço está na rede `nginx_network`
- Testar DNS: `docker exec CONTAINER sh -c "getent hosts postgres_postgres"`
- Usar porta interna `5432` (não `25432`)

### drizzle-kit push fica interativo
- O banco tem tabelas existentes (ex: banco `asterisk` com tabelas do Asterisk)
- **Solução:** Criar banco separado (`voxcall`) e apontar DATABASE_URL para ele

### Gravações não tocam (403/404)
- Verificar mount: `docker exec CONTAINER ls /var/spool/asterisk/monitor/`
- Verificar que o mount é do diretório correto do host
- Verificar que o endpoint de áudio aceita Bearer token (getAuthHeaders)

### NPM não roteia para o VoxCALL
- Verificar arquivo nginx: `docker exec NPM_CONTAINER cat /data/nginx/proxy_host/ID.conf`
- Testar nginx: `docker exec NPM_CONTAINER nginx -t`
- Recarregar: `docker exec NPM_CONTAINER nginx -s reload`
- NUNCA usar `proxy_pass` explícito junto com `include proxy.conf`

### SSL "unrecognized name"
- O arquivo nginx config pode estar vazio (escrita falhou)
- Verificar que o arquivo tem o `server_name` correto
- Usar `tee` com pipe para escrever: `echo "$CONF" | docker exec -i NPM_CONTAINER tee /data/nginx/proxy_host/ID.conf`

### Docker Hub auth error no build
- `docker logout` antes de buildar resolve na maioria dos casos
- O Docker pode ter credenciais expiradas em `~/.docker/config.json`

### Collation version mismatch ao criar banco
```bash
PGCONTAINER=$(docker ps --format "{{.Names}}" | grep postgres)
docker exec -e PGPASSWORD="PASS" $PGCONTAINER psql -U USER -d postgres \
  -c "ALTER DATABASE template1 REFRESH COLLATION VERSION;"
docker exec -e PGPASSWORD="PASS" $PGCONTAINER psql -U USER -d postgres \
  -c "ALTER DATABASE postgres REFRESH COLLATION VERSION;"
```

## Instâncias Ativas

### smartcob.voxcall.cc (modelo.voxtel.app.br)
- **VPS IP:** 85.31.63.92
- **SSH:** porta 22300, user root
- **Domínio:** smartcob.voxcall.cc
- **Container:** voxcall_voxcall (Docker Swarm)
- **Porta interna:** 5000
- **DB VoxCALL:** `voxcall` no postgres_postgres
- **DB Asterisk:** `asterisk` no postgres_postgres
- **Configs:** /opt/voxcall/config/
- **Source:** /opt/voxcall/source/
- **Build log:** /opt/voxcall/build.log
- **SSL:** Let's Encrypt (expira 07/07/2026)
- **NPM Proxy Host ID:** 11
- **Login:** superadmin / RiCa$0808
- **Serviços coexistentes:** 14 serviços Docker Swarm (npm, postgres, apache, voxdial, portainer, etc.)
