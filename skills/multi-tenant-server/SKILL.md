---
name: multi-tenant-server
description: Arquitetura Multi-Tenant para rodar múltiplos clientes VoxCALL/VoxZap em um único servidor dedicado com isolamento Docker, Asterisk por tenant, Nginx centralizado por domínio, e scripts de provisionamento/remoção. Use quando precisar provisionar, gerenciar, monitorar ou remover tenants em servidores dedicados compartilhados.
---

# Arquitetura Multi-Tenant — Servidor Dedicado

Skill para operar múltiplos clientes (tenants) em um único servidor dedicado, cada um com seu próprio stack Docker isolado (VoxCALL + Asterisk + PostgreSQL), roteado por domínio via Nginx centralizado.

## Quando Usar

- Provisionar novo cliente em servidor dedicado compartilhado
- Remover/desativar tenant existente
- Planejar alocação de portas SIP/RTP/AMI/ARI/WSS para novo tenant
- Configurar Nginx como ponto de entrada centralizado
- Monitorar saúde e recursos de todos os tenants
- Backup centralizado por tenant
- Migração de tenant entre servidores

## Quando NÃO Usar

- Deploy single-tenant (1 cliente = 1 VPS) → use `deploy-assistant-vps`
- VPS com Asterisk nativo (não Docker) → use `voxcall-native-asterisk-deploy`
- Configuração interna do Asterisk (dialplan, PJSIP) → use skills de Asterisk

## Modelo de Isolamento

Cada tenant opera com **isolamento por stack Docker** separado:
- Stack próprio: VoxCALL app + Asterisk + PostgreSQL
- Rede Docker bridge isolada para app↔db (não compartilhada entre tenants)
- Volumes próprios para dados, gravações e configs
- Faixas de portas exclusivas (SIP, RTP, AMI, ARI)
- Limites de memória e CPU por container
- Credenciais AMI/ARI únicas por tenant (geradas no provisionamento)

**Pontos compartilhados:**
- Nginx na porta 80/443 (roteia por domínio)
- Asterisk usa `network_mode: host` (necessário para SIP/RTP com NAT) — portas AMI/ARI são vinculadas a `127.0.0.1` para evitar exposição externa

**Tradeoff de host networking:** O Asterisk precisa de `network_mode: host` para que SIP/RTP funcionem corretamente com NAT traversal. Isso significa que cada instância Asterisk escuta diretamente no host. A mitigação é: (1) portas AMI/ARI vinculadas exclusivamente a `127.0.0.1`, (2) credenciais únicas por tenant, (3) firewall bloqueando portas de controle externamente.

---

## 1. Estrutura de Diretórios

```
/opt/tenants/
├── nginx/                          # Nginx centralizado
│   ├── docker-compose.yml
│   ├── conf.d/
│   │   ├── tenant_acme.conf        # Server block do tenant acme
│   │   ├── tenant_globex.conf      # Server block do tenant globex
│   │   └── ...
│   └── ssl/                        # Certificados (ou /etc/letsencrypt)
│
├── acme/                           # Tenant "acme"
│   ├── docker-compose.yml          # Stack completo do tenant
│   ├── .env                        # Variáveis de ambiente
│   ├── Dockerfile                  # Build do VoxCALL
│   ├── source/                     # Código-fonte do VoxCALL
│   ├── config/                     # Configs persistentes (ami, ari, db, ssh, smtp)
│   ├── backups/                    # Backups locais
│   └── asterisk/                   # Configs customizadas do Asterisk
│       ├── pjsip_custom.conf
│       ├── extensions_custom.conf
│       └── ...
│
├── globex/                         # Tenant "globex"
│   ├── docker-compose.yml
│   ├── .env
│   ├── ...
│
└── _shared/                        # Recursos compartilhados
    ├── provision-tenant.sh         # Script de provisionamento
    ├── remove-tenant.sh            # Script de remoção
    ├── update-tenant.sh            # Script de atualização
    ├── backup-all.sh               # Backup centralizado
    ├── monitor-all.sh              # Monitoramento
    ├── tenant-registry.json        # Registro de todos os tenants
    └── base-source.tar.gz          # Código-fonte base do VoxCALL
```

---

## 2. Estratégia de Portas

Cada tenant recebe um **slot numérico** (1, 2, 3...) que define todas as suas portas.

### Fórmula de Alocação

| Serviço | Fórmula | Tenant 1 | Tenant 2 | Tenant 3 | Tenant 10 | Bind |
|---------|---------|----------|----------|----------|-----------|------|
| **VoxCALL HTTP** | 5000 + N | 5001 | 5002 | 5003 | 5010 | 127.0.0.1 |
| **PostgreSQL** | 25432 + N | 25433 | 25434 | 25435 | 25442 | 127.0.0.1 |
| **SIP (UDP/TCP)** | 5060 + (N×10) | 5070 | 5080 | 5090 | 5160 | 0.0.0.0 |
| **AMI** | 5038 + N | 5039 | 5040 | 5041 | 5048 | 127.0.0.1 |
| **ARI/WSS HTTP** | 8088 + N | 8089 | 8090 | 8091 | 8098 | 127.0.0.1 |
| **RTP início** | 10000 + (N×1000) | 11000 | 12000 | 13000 | 20000 | 0.0.0.0 |
| **RTP fim** | RTP início + 999 | 11999 | 12999 | 13999 | 20999 | 0.0.0.0 |

**ARI e WS compartilham a mesma porta HTTP:** O Asterisk tem um único servidor HTTP interno (`http.conf`, `bindaddr=127.0.0.1`) que serve tanto a API REST do ARI (`/ari/...`) quanto WebSocket SIP para WebRTC (`/ws`). A porta ARI_PORT atende ambos.

**Modelo de TLS (TLS termination no Nginx):**
- Asterisk roda com `protocol=ws` (plain WebSocket, sem TLS) em `127.0.0.1:ARI_PORT`
- Nginx termina TLS (certificado Let's Encrypt) na porta 443
- Clientes WebRTC conectam via `wss://dominio.com/ws` → Nginx faz proxy para `http://127.0.0.1:ARI_PORT/ws`
- A API ARI fica protegida por autenticação (user/password) e não é exposta externamente

**Portas expostas externamente (firewall):** Apenas SIP e RTP. Todas as demais (APP, DB, AMI, ARI/WSS) ficam em `127.0.0.1` — o Nginx centralizado faz proxy para o app e para WSS.

### Limites por Servidor

- **Máximo recomendado**: 20 tenants por servidor dedicado (depende dos recursos)
- **RTP**: Cada tenant tem 1000 portas RTP (suficiente para ~500 chamadas simultâneas)
- **Portas reservadas**: Slot 0 é reservado (portas padrão do Asterisk para uso direto se necessário)
- **Firewall**: Apenas portas SIP e RTP precisam ser abertas no firewall externo; AMI/ARI/WSS ficam em `127.0.0.1` (WSS via Nginx proxy)

### Registro de Tenants (tenant-registry.json)

```json
{
  "server": {
    "hostname": "srv01.voxtel.app.br",
    "ip": "195.35.19.21",
    "maxTenants": 20,
    "totalCPU": 16,
    "totalRAM": "64GB"
  },
  "tenants": {
    "acme": {
      "slot": 1,
      "domain": "acme.voxcall.cc",
      "status": "active",
      "createdAt": "2026-04-15T10:00:00Z",
      "appPort": 5001,
      "dbPort": 25433,
      "sipPort": 5070,
      "amiPort": 5039,
      "ariPort": 8089,
      "rtpStart": 11000,
      "rtpEnd": 11999,
      "memoryLimit": "512M",
      "cpuLimit": "1.0"
    },
    "globex": {
      "slot": 2,
      "domain": "globex.voxcall.cc",
      "status": "active",
      "createdAt": "2026-04-15T11:00:00Z",
      "appPort": 5002,
      "dbPort": 25434,
      "sipPort": 5080,
      "amiPort": 5040,
      "ariPort": 8090,
      "rtpStart": 12000,
      "rtpEnd": 12999,
      "memoryLimit": "512M",
      "cpuLimit": "1.0"
    }
  },
  "nextSlot": 3
}
```

---

## 3. Docker Compose por Tenant

Cada tenant tem seu próprio `docker-compose.yml` em `/opt/tenants/{tenant_id}/`.

### Template docker-compose.yml

```yaml
services:
  app:
    build: .
    container_name: ${TENANT_ID}-app
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:5000"
    env_file:
      - .env
    volumes:
      - ./config:/app/config
      - asterisk_recordings:/var/spool/asterisk/monitor:ro
    depends_on:
      db:
        condition: service_healthy
    networks:
      - tenant-net
    mem_limit: ${MEM_LIMIT:-512m}
    cpus: ${CPU_LIMIT:-1.0}
    oom_score_adj: 300

  asterisk:
    image: voxcall-asterisk:latest
    container_name: ${TENANT_ID}-asterisk
    restart: unless-stopped
    network_mode: host
    volumes:
      - asterisk_recordings:/var/spool/asterisk/monitor
      - asterisk_configs:/etc/asterisk
      - ./asterisk/custom:/etc/asterisk/custom:ro
    environment:
      - ASTERISK_SIP_PORT=${SIP_PORT}
      - ASTERISK_AMI_PORT=${AMI_PORT}
      - ASTERISK_ARI_PORT=${ARI_PORT}
      - ASTERISK_RTP_START=${RTP_START}
      - ASTERISK_RTP_END=${RTP_END}
      - ASTERISK_EXTERNAL_IP=${EXTERNAL_IP}
      - AMI_PASSWORD=${AMI_PASSWORD}
      - ARI_PASSWORD=${ARI_PASSWORD}
      - DB_HOST=127.0.0.1
      - DB_PORT=${DB_PORT}
      - DB_NAME=asterisk
      - DB_USER=voxcall
      - DB_PASSWORD=${DB_PASSWORD}
    mem_limit: ${AST_MEM_LIMIT:-1g}
    cpus: ${AST_CPU_LIMIT:-2.0}
    oom_score_adj: -500

  db:
    image: postgres:16-alpine
    container_name: ${TENANT_ID}-db
    restart: unless-stopped
    environment:
      POSTGRES_USER: voxcall
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: voxcall
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./init-db.sql:/docker-entrypoint-initdb.d/01-init.sql:ro
    ports:
      - "127.0.0.1:${DB_PORT}:5432"
    shm_size: "256mb"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U voxcall -d voxcall"]
      interval: 5s
      timeout: 5s
      retries: 5
    mem_limit: ${DB_MEM_LIMIT:-512m}
    cpus: ${DB_CPU_LIMIT:-1.0}
    oom_score_adj: -1000
    networks:
      - tenant-net

volumes:
  pgdata:
  asterisk_recordings:
  asterisk_configs:

networks:
  tenant-net:
    driver: bridge
```

### Notas Importantes

- **`network_mode: host`** no Asterisk: obrigatório para SIP/RTP funcionarem com NAT corretamente. O Asterisk escuta diretamente nas portas do host.
- **VoxCALL app** fica na rede bridge isolada (`tenant-net`), acessando o DB internamente e sendo acessado pelo Nginx via `127.0.0.1:APP_PORT`.
- **PostgreSQL** expõe porta apenas em `127.0.0.1` para que o Asterisk (em host mode) consiga conectar.

### init-db.sql (Criação do banco Asterisk)

```sql
-- Cria banco separado para tabelas do Asterisk (CDR, queue_log, etc.)
CREATE DATABASE asterisk OWNER voxcall;

\c asterisk

CREATE TABLE IF NOT EXISTS cdr (
    id SERIAL PRIMARY KEY,
    calldate TIMESTAMP NOT NULL DEFAULT NOW(),
    clid VARCHAR(80) DEFAULT '',
    src VARCHAR(80) DEFAULT '',
    dst VARCHAR(80) DEFAULT '',
    dcontext VARCHAR(80) DEFAULT '',
    channel VARCHAR(80) DEFAULT '',
    dstchannel VARCHAR(80) DEFAULT '',
    lastapp VARCHAR(80) DEFAULT '',
    lastdata VARCHAR(80) DEFAULT '',
    duration INTEGER DEFAULT 0,
    billsec INTEGER DEFAULT 0,
    disposition VARCHAR(45) DEFAULT '',
    amaflags INTEGER DEFAULT 0,
    accountcode VARCHAR(20) DEFAULT '',
    uniqueid VARCHAR(150) DEFAULT '',
    userfield VARCHAR(255) DEFAULT '',
    peeraccount VARCHAR(80) DEFAULT '',
    linkedid VARCHAR(150) DEFAULT '',
    sequence INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS queue_log (
    id SERIAL PRIMARY KEY,
    "time" TIMESTAMP NOT NULL DEFAULT NOW(),
    callid VARCHAR(80) DEFAULT '',
    queuename VARCHAR(256) DEFAULT '',
    agent VARCHAR(80) DEFAULT '',
    event VARCHAR(32) DEFAULT '',
    data1 VARCHAR(100) DEFAULT '',
    data2 VARCHAR(100) DEFAULT '',
    data3 VARCHAR(100) DEFAULT '',
    data4 VARCHAR(100) DEFAULT '',
    data5 VARCHAR(100) DEFAULT ''
);

CREATE INDEX IF NOT EXISTS idx_cdr_calldate ON cdr(calldate);
CREATE INDEX IF NOT EXISTS idx_cdr_src ON cdr(src);
CREATE INDEX IF NOT EXISTS idx_cdr_dst ON cdr(dst);
CREATE INDEX IF NOT EXISTS idx_queue_log_time ON queue_log("time");
CREATE INDEX IF NOT EXISTS idx_queue_log_queuename ON queue_log(queuename);
CREATE INDEX IF NOT EXISTS idx_queue_log_agent ON queue_log(agent);
```

### Arquivo .env do Tenant

```bash
# Tenant: acme
TENANT_ID=acme
NODE_ENV=production
PORT=5000
DATABASE_URL=postgresql://voxcall:SENHA_SEGURA@db:5432/voxcall
SESSION_SECRET=acme-session-secret-RANDOM
DOMAIN=acme.voxcall.cc
TZ=America/Sao_Paulo
SUPERADMIN_PASSWORD=SENHA_ADMIN
SUPERADMIN_USERNAME=superadmin
SUPERADMIN_EMAIL=admin@acme.com.br

# Portas (usadas no docker-compose.yml via ${VAR})
APP_PORT=5001
DB_PORT=25433
DB_PASSWORD=SENHA_SEGURA
SIP_PORT=5070
AMI_PORT=5039
ARI_PORT=8089
AMI_PASSWORD=ami_SENHA_UNICA_POR_TENANT
ARI_PASSWORD=ari_SENHA_UNICA_POR_TENANT
RTP_START=11000
RTP_END=11999
EXTERNAL_IP=195.35.19.21

# Limites de recursos
MEM_LIMIT=512m
CPU_LIMIT=1.0
AST_MEM_LIMIT=1g
AST_CPU_LIMIT=2.0
DB_MEM_LIMIT=512m
DB_CPU_LIMIT=1.0
```

---

## 4. Nginx Centralizado

O Nginx roda como container Docker separado na pasta `/opt/tenants/nginx/`, escutando nas portas 80/443 e roteando por `server_name` para o app correto de cada tenant.

### docker-compose.yml do Nginx

```yaml
services:
  nginx:
    image: nginx:alpine
    container_name: mt-nginx
    restart: unless-stopped
    volumes:
      - ./conf.d:/etc/nginx/conf.d:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
      - /var/lib/letsencrypt:/var/lib/letsencrypt
    network_mode: host
```

**Nota:** `network_mode: host` e `ports:` são mutuamente exclusivos no Docker Compose. Com host networking, o Nginx escuta diretamente nas portas 80/443 do host sem mapeamento.

**`network_mode: host`**: Permite que o Nginx acesse `127.0.0.1:APP_PORT` de cada tenant diretamente, sem precisar de rede Docker compartilhada.

### Template de Server Block (conf.d/tenant_{id}.conf)

```nginx
# Rate limiting zones (colocar no nginx.conf principal ou em conf.d/00-rate-limit.conf)
# limit_req_zone $binary_remote_addr zone=api_limit:10m rate=30r/s;
# limit_req_zone $binary_remote_addr zone=login_limit:10m rate=5r/m;

# Tenant: acme (slot 1, app porta 5001, ARI/WSS porta 8089)
server {
    listen 80;
    server_name acme.voxcall.cc;

    location /.well-known/acme-challenge/ {
        root /var/lib/letsencrypt;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl;
    http2 on;
    server_name acme.voxcall.cc;

    ssl_certificate /etc/letsencrypt/live/acme.voxcall.cc/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/acme.voxcall.cc/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    client_max_body_size 50M;

    # Rate limiting na API
    location /api/ {
        limit_req zone=api_limit burst=50 nodelay;
        proxy_pass http://127.0.0.1:5001;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }

    # Rate limiting mais restritivo no login
    location /api/login {
        limit_req zone=login_limit burst=3 nodelay;
        proxy_pass http://127.0.0.1:5001;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }

    # WebSocket proxy para Asterisk WS (TLS terminado no Nginx, upstream é WS plain)
    location /ws {
        proxy_pass http://127.0.0.1:8089/ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }

    # App (inclui WebSocket do Socket.io)
    location / {
        proxy_pass http://127.0.0.1:5001;
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

### Rate Limiting Global (conf.d/00-rate-limit.conf)

Criar este arquivo para definir as zonas de rate limiting usadas por todos os tenants:

```nginx
# /opt/tenants/nginx/conf.d/00-rate-limit.conf
# Zonas de rate limiting compartilhadas por todos os tenants
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=30r/s;
limit_req_zone $binary_remote_addr zone=login_limit:10m rate=5r/m;
limit_req_status 429;
```

### Wildcard SSL (Opcional)

Se todos os tenants usam subdomínios de um mesmo domínio (ex: `*.voxcall.cc`), pode-se usar um certificado wildcard:

```bash
certbot certonly --manual --preferred-challenges dns \
  -d "*.voxcall.cc" -d "voxcall.cc" \
  --agree-tos --email admin@voxtel.biz
```

Nesse caso, todos os server blocks usam o mesmo certificado:
```nginx
ssl_certificate /etc/letsencrypt/live/voxcall.cc/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/voxcall.cc/privkey.pem;
```

---

## 5. Imagem Docker do Asterisk (Compartilhada)

Todos os tenants usam a **mesma imagem** Docker do Asterisk (`voxcall-asterisk:latest`), construída uma vez no servidor.

A imagem aceita variáveis de ambiente para customizar portas, e um entrypoint gera os configs dinâmicos.

### Dockerfile do Asterisk Multi-Tenant

```dockerfile
FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    asterisk asterisk-modules asterisk-core-sounds-en \
    asterisk-core-sounds-pt-br asterisk-moh-opsound-wav \
    postgresql-client curl ffmpeg tzdata \
    && rm -rf /var/lib/apt/lists/*

ENV TZ=America/Sao_Paulo
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["asterisk", "-fvvv"]
```

### entrypoint.sh (Configura portas dinamicamente)

```bash
#!/bin/bash
set -e

SIP_PORT=${ASTERISK_SIP_PORT:-5060}
AMI_PORT=${ASTERISK_AMI_PORT:-5038}
ARI_PORT=${ASTERISK_ARI_PORT:-8088}
RTP_START=${ASTERISK_RTP_START:-10000}
RTP_END=${ASTERISK_RTP_END:-10999}
EXTERNAL_IP=${ASTERISK_EXTERNAL_IP:-}
DB_HOST=${DB_HOST:-127.0.0.1}
DB_PORT=${DB_PORT:-5432}
DB_NAME=${DB_NAME:-asterisk}
DB_USER=${DB_USER:-voxcall}
DB_PASSWORD=${DB_PASSWORD:-}

cat > /etc/asterisk/rtp.conf <<EOF
[general]
rtpstart=${RTP_START}
rtpend=${RTP_END}
EOF

cat > /etc/asterisk/http.conf <<EOF
[general]
enabled=yes
bindaddr=127.0.0.1
bindport=${ARI_PORT}
tlsenable=no
EOF

ARI_PASS=${ARI_PASSWORD:?ERRO: ARI_PASSWORD obrigatório}
cat > /etc/asterisk/ari.conf <<EOF
[general]
enabled=yes
pretty=yes
allowed_origins=http://127.0.0.1

[voxari]
type=user
read_only=no
password=${ARI_PASS}
EOF

AMI_PASS=${AMI_PASSWORD:?ERRO: AMI_PASSWORD obrigatório}
cat > /etc/asterisk/manager.conf <<EOF
[general]
enabled=yes
port=${AMI_PORT}
bindaddr=127.0.0.1

[voxami]
secret=${AMI_PASS}
deny=0.0.0.0/0.0.0.0
permit=127.0.0.0/255.0.0.0
read=system,call,log,verbose,command,agent,user,config,dtmf,reporting,cdr,dialplan
write=system,call,command,originate,reporting
EOF

if [ -n "$DB_PASSWORD" ]; then
cat > /etc/asterisk/cdr_pgsql.conf <<EOF
[global]
hostname=${DB_HOST}
port=${DB_PORT}
dbname=${DB_NAME}
password=${DB_PASSWORD}
user=${DB_USER}
table=cdr
EOF

cat > /etc/asterisk/res_pgsql.conf <<EOF
[general]
dbhost=${DB_HOST}
dbport=${DB_PORT}
dbname=${DB_NAME}
dbuser=${DB_USER}
dbpass=${DB_PASSWORD}
EOF
fi

cat > /etc/asterisk/pjsip.conf <<EOF
[global]
type=global
max_forwards=70
user_agent=VoxCALL-MT
default_from_user=voxcall

[transport-udp]
type=transport
protocol=udp
bind=0.0.0.0:${SIP_PORT}
${EXTERNAL_IP:+external_media_address=${EXTERNAL_IP}}
${EXTERNAL_IP:+external_signaling_address=${EXTERNAL_IP}}
local_net=10.0.0.0/8
local_net=172.16.0.0/12
local_net=192.168.0.0/16

[transport-tcp]
type=transport
protocol=tcp
bind=0.0.0.0:${SIP_PORT}
${EXTERNAL_IP:+external_media_address=${EXTERNAL_IP}}
${EXTERNAL_IP:+external_signaling_address=${EXTERNAL_IP}}
local_net=10.0.0.0/8
local_net=172.16.0.0/12
local_net=192.168.0.0/16

[transport-ws]
type=transport
protocol=ws
bind=127.0.0.1:${ARI_PORT}
${EXTERNAL_IP:+external_media_address=${EXTERNAL_IP}}
${EXTERNAL_IP:+external_signaling_address=${EXTERNAL_IP}}
local_net=10.0.0.0/8
local_net=172.16.0.0/12
local_net=192.168.0.0/16

#include pjsip_custom.conf
EOF

if [ -f /etc/asterisk/custom/pjsip_custom.conf ]; then
  cp /etc/asterisk/custom/pjsip_custom.conf /etc/asterisk/pjsip_custom.conf
fi

if [ -f /etc/asterisk/custom/extensions_custom.conf ]; then
  cp /etc/asterisk/custom/extensions_custom.conf /etc/asterisk/extensions_custom.conf
  grep -q "extensions_custom.conf" /etc/asterisk/extensions.conf 2>/dev/null || \
    echo "#include extensions_custom.conf" >> /etc/asterisk/extensions.conf
fi

echo "[entrypoint] Asterisk configurado: SIP=${SIP_PORT} ARI/WSS=${ARI_PORT} AMI=${AMI_PORT} RTP=${RTP_START}-${RTP_END}"

exec "$@"
```

---

## 6. Script de Provisionamento

### provision-tenant.sh

```bash
#!/bin/bash
set -euo pipefail

TENANTS_DIR="/opt/tenants"
REGISTRY="$TENANTS_DIR/_shared/tenant-registry.json"
BASE_SOURCE="$TENANTS_DIR/_shared/base-source.tar.gz"

usage() {
  echo "Uso: $0 <tenant_id> <domain> [superadmin_email] [superadmin_password]"
  echo "Exemplo: $0 acme acme.voxcall.cc admin@acme.com.br SenhaForte123"
  exit 1
}

[ $# -lt 2 ] && usage

TENANT_ID="$1"
DOMAIN="$2"
ADMIN_EMAIL="${3:-admin@${DOMAIN}}"
ADMIN_PASSWORD="${4:-VoxCALL@$(openssl rand -hex 4)}"
EXTERNAL_IP=$(curl -4 -s ifconfig.me || hostname -I | awk '{print $1}')

if [ -d "$TENANTS_DIR/$TENANT_ID" ]; then
  echo "ERRO: Tenant '$TENANT_ID' já existe em $TENANTS_DIR/$TENANT_ID"
  exit 1
fi

if [ ! -f "$REGISTRY" ]; then
  echo '{"server":{},"tenants":{},"nextSlot":1}' > "$REGISTRY"
fi

SLOT=$(python3 -c "import json; r=json.load(open('$REGISTRY')); print(r.get('nextSlot',1))")
echo "=== Provisionando tenant: $TENANT_ID (slot $SLOT, domínio $DOMAIN) ==="

# Calcular portas
APP_PORT=$((5000 + SLOT))
DB_PORT=$((25432 + SLOT))
SIP_PORT=$((5060 + SLOT * 10))
AMI_PORT=$((5038 + SLOT))
ARI_PORT=$((8088 + SLOT))
RTP_START=$((10000 + SLOT * 1000))
RTP_END=$((RTP_START + 999))

DB_PASSWORD="voxcall_$(openssl rand -hex 8)"
SESSION_SECRET="session_$(openssl rand -hex 16)"
AMI_PASSWORD="ami_$(openssl rand -hex 12)"
ARI_PASSWORD="ari_$(openssl rand -hex 12)"

echo "  Portas: APP=$APP_PORT DB=$DB_PORT SIP=$SIP_PORT AMI=$AMI_PORT ARI/WSS=$ARI_PORT RTP=$RTP_START-$RTP_END"

# 1. Criar diretórios
TENANT_DIR="$TENANTS_DIR/$TENANT_ID"
mkdir -p "$TENANT_DIR"/{source,config,backups,asterisk/custom}

# 2. Extrair código-fonte
if [ -f "$BASE_SOURCE" ]; then
  echo "  Extraindo código-fonte base..."
  tar xzf "$BASE_SOURCE" -C "$TENANT_DIR/source"
else
  echo "  AVISO: $BASE_SOURCE não encontrado. Copie o código manualmente para $TENANT_DIR/source/"
fi

# 3. Criar Dockerfile
cat > "$TENANT_DIR/Dockerfile" <<'DOCKERFILE'
FROM node:20-alpine
RUN apk add --no-cache ffmpeg tzdata
ENV TZ=America/Sao_Paulo
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
WORKDIR /app
COPY source/package*.json ./
RUN npm ci --ignore-scripts
COPY source/ .
RUN npm run build
EXPOSE 5000
CMD ["npm", "start"]
DOCKERFILE

# 4. Criar .env
cat > "$TENANT_DIR/.env" <<ENVFILE
TENANT_ID=$TENANT_ID
NODE_ENV=production
PORT=5000
DATABASE_URL=postgresql://voxcall:${DB_PASSWORD}@db:5432/voxcall
SESSION_SECRET=$SESSION_SECRET
DOMAIN=$DOMAIN
TZ=America/Sao_Paulo
SUPERADMIN_PASSWORD=$ADMIN_PASSWORD
SUPERADMIN_USERNAME=superadmin
SUPERADMIN_EMAIL=$ADMIN_EMAIL

APP_PORT=$APP_PORT
DB_PORT=$DB_PORT
DB_PASSWORD=$DB_PASSWORD
SIP_PORT=$SIP_PORT
AMI_PORT=$AMI_PORT
ARI_PORT=$ARI_PORT
AMI_PASSWORD=$AMI_PASSWORD
ARI_PASSWORD=$ARI_PASSWORD
RTP_START=$RTP_START
RTP_END=$RTP_END
EXTERNAL_IP=$EXTERNAL_IP

MEM_LIMIT=512m
CPU_LIMIT=1.0
AST_MEM_LIMIT=1g
AST_CPU_LIMIT=2.0
DB_MEM_LIMIT=512m
DB_CPU_LIMIT=1.0
ENVFILE

# 5. Criar init-db.sql
cat > "$TENANT_DIR/init-db.sql" <<'INITDB'
CREATE DATABASE asterisk OWNER voxcall;
\c asterisk
CREATE TABLE IF NOT EXISTS cdr (
    id SERIAL PRIMARY KEY,
    calldate TIMESTAMP NOT NULL DEFAULT NOW(),
    clid VARCHAR(80) DEFAULT '', src VARCHAR(80) DEFAULT '',
    dst VARCHAR(80) DEFAULT '', dcontext VARCHAR(80) DEFAULT '',
    channel VARCHAR(80) DEFAULT '', dstchannel VARCHAR(80) DEFAULT '',
    lastapp VARCHAR(80) DEFAULT '', lastdata VARCHAR(80) DEFAULT '',
    duration INTEGER DEFAULT 0, billsec INTEGER DEFAULT 0,
    disposition VARCHAR(45) DEFAULT '', amaflags INTEGER DEFAULT 0,
    accountcode VARCHAR(20) DEFAULT '', uniqueid VARCHAR(150) DEFAULT '',
    userfield VARCHAR(255) DEFAULT '', peeraccount VARCHAR(80) DEFAULT '',
    linkedid VARCHAR(150) DEFAULT '', sequence INTEGER DEFAULT 0
);
CREATE TABLE IF NOT EXISTS queue_log (
    id SERIAL PRIMARY KEY,
    "time" TIMESTAMP NOT NULL DEFAULT NOW(),
    callid VARCHAR(80) DEFAULT '', queuename VARCHAR(256) DEFAULT '',
    agent VARCHAR(80) DEFAULT '', event VARCHAR(32) DEFAULT '',
    data1 VARCHAR(100) DEFAULT '', data2 VARCHAR(100) DEFAULT '',
    data3 VARCHAR(100) DEFAULT '', data4 VARCHAR(100) DEFAULT '',
    data5 VARCHAR(100) DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_cdr_calldate ON cdr(calldate);
CREATE INDEX IF NOT EXISTS idx_cdr_src ON cdr(src);
CREATE INDEX IF NOT EXISTS idx_cdr_dst ON cdr(dst);
CREATE INDEX IF NOT EXISTS idx_queue_log_time ON queue_log("time");
CREATE INDEX IF NOT EXISTS idx_queue_log_queuename ON queue_log(queuename);
CREATE INDEX IF NOT EXISTS idx_queue_log_agent ON queue_log(agent);

-- ===== CEL (Channel Event Logging) =====
-- Pipeline: Asterisk CEL (CHAN_START) -> INSERT em cel (UNLOGGED)
--   -> trigger trg_cel_captura_canal -> INSERT em canal_chamada (linkedid, canal)
--   -> monitor_voxcall() lê no CONNECT -> UPDATE t_monitor_voxcall.canal
-- A tabela cel é UNLOGGED + trigger BEFORE INSERT que retorna NULL,
-- então nunca cresce em disco. Espelha server/asterisk-schema.sql:984-1070.
CREATE UNLOGGED TABLE IF NOT EXISTS cel (
    id numeric, eventtime text, eventtype text, userdeftype text,
    cid_name text, cid_num text, cid_ani text, cid_rdnis text, cid_dnid text,
    exten text, context text, channame text, appname text, appdata text,
    accountcode text, peeraccount text, uniqueid text, linkedid text,
    amaflags numeric, userfield text, peer text
);

CREATE TABLE IF NOT EXISTS canal_chamada (
    linkedid text PRIMARY KEY,
    canal text NOT NULL,
    created_at timestamp without time zone DEFAULT now()
);

CREATE OR REPLACE FUNCTION fn_cel_captura_canal() RETURNS trigger
    LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.eventtype = 'CHAN_START' THEN
        INSERT INTO canal_chamada (linkedid, canal)
        VALUES (NEW.linkedid, NEW.channame)
        ON CONFLICT (linkedid) DO NOTHING;
    END IF;
    RETURN NULL;  -- cancela INSERT na cel (UNLOGGED nunca cresce)
END;
$$;

DROP TRIGGER IF EXISTS trg_cel_captura_canal ON cel;
CREATE TRIGGER trg_cel_captura_canal
    BEFORE INSERT ON cel FOR EACH ROW
    EXECUTE FUNCTION fn_cel_captura_canal();

CREATE OR REPLACE FUNCTION fn_canal_chamada_cleanup() RETURNS trigger
    LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM canal_chamada WHERE created_at < now() - interval '24 hours';
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_canal_chamada_cleanup ON canal_chamada;
CREATE TRIGGER trg_canal_chamada_cleanup
    AFTER INSERT ON canal_chamada FOR EACH STATEMENT
    EXECUTE FUNCTION fn_canal_chamada_cleanup();
INITDB

# 6. Criar docker-compose.yml
cat > "$TENANT_DIR/docker-compose.yml" <<COMPOSE
services:
  app:
    build: .
    container_name: ${TENANT_ID}-app
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:5000"
    env_file:
      - .env
    volumes:
      - ./config:/app/config
      - asterisk_recordings:/var/spool/asterisk/monitor:ro
    depends_on:
      db:
        condition: service_healthy
    networks:
      - tenant-net
    mem_limit: \${MEM_LIMIT:-512m}
    cpus: \${CPU_LIMIT:-1.0}
    oom_score_adj: 300

  asterisk:
    image: voxcall-asterisk:latest
    container_name: ${TENANT_ID}-asterisk
    restart: unless-stopped
    network_mode: host
    volumes:
      - asterisk_recordings:/var/spool/asterisk/monitor
      - asterisk_configs:/etc/asterisk
      - ./asterisk/custom:/etc/asterisk/custom:ro
    environment:
      - ASTERISK_SIP_PORT=${SIP_PORT}
      - ASTERISK_AMI_PORT=${AMI_PORT}
      - ASTERISK_ARI_PORT=${ARI_PORT}
      - ASTERISK_RTP_START=${RTP_START}
      - ASTERISK_RTP_END=${RTP_END}
      - ASTERISK_EXTERNAL_IP=${EXTERNAL_IP}
      - AMI_PASSWORD=${AMI_PASSWORD}
      - ARI_PASSWORD=${ARI_PASSWORD}
      - DB_HOST=127.0.0.1
      - DB_PORT=${DB_PORT}
      - DB_NAME=asterisk
      - DB_USER=voxcall
      - DB_PASSWORD=${DB_PASSWORD}
    mem_limit: \${AST_MEM_LIMIT:-1g}
    cpus: \${AST_CPU_LIMIT:-2.0}
    oom_score_adj: -500

  db:
    image: postgres:16-alpine
    container_name: ${TENANT_ID}-db
    restart: unless-stopped
    environment:
      POSTGRES_USER: voxcall
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: voxcall
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./init-db.sql:/docker-entrypoint-initdb.d/01-init.sql:ro
    ports:
      - "127.0.0.1:${DB_PORT}:5432"
    shm_size: "256mb"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U voxcall -d voxcall"]
      interval: 5s
      timeout: 5s
      retries: 5
    mem_limit: \${DB_MEM_LIMIT:-512m}
    cpus: \${DB_CPU_LIMIT:-1.0}
    oom_score_adj: -1000
    networks:
      - tenant-net

volumes:
  pgdata:
  asterisk_recordings:
  asterisk_configs:

networks:
  tenant-net:
    driver: bridge
COMPOSE

# 7. Criar configs iniciais (AMI, ARI, DB)
cat > "$TENANT_DIR/config/ami-config.json" <<AMICONF
{
  "host": "127.0.0.1",
  "port": $AMI_PORT,
  "username": "voxami",
  "password": "$AMI_PASSWORD"
}
AMICONF

cat > "$TENANT_DIR/config/ari-config.json" <<ARICONF
{
  "host": "127.0.0.1",
  "port": $ARI_PORT,
  "username": "voxari",
  "password": "$ARI_PASSWORD",
  "protocol": "http"
}
ARICONF

cat > "$TENANT_DIR/config/db-config.json" <<DBCONF
{
  "host": "127.0.0.1",
  "port": $DB_PORT,
  "database": "asterisk",
  "username": "voxcall",
  "password": "$DB_PASSWORD",
  "ssl": false
}
DBCONF

# 7b. Criar overrides do Asterisk para o tenant (cel.conf + cel_pgsql.conf)
# O entrypoint da imagem voxcall-asterisk:latest copia tudo de /etc/asterisk/custom/*.conf
# por cima de /etc/asterisk/ no boot, então estes arquivos passam a valer para o tenant.
cat > "$TENANT_DIR/asterisk/custom/cel.conf" <<'CELCONF'
; CEL (Channel Event Logging) — habilitado para capturar canal externo via trigger PostgreSQL.
; events=ALL é necessário no Asterisk 22 (CHAN_START isolado causa reload failure).
; O trigger fn_cel_captura_canal() filtra apenas CHAN_START e retorna NULL para
; cancelar todos os INSERTs — a tabela cel (UNLOGGED) nunca cresce.
[general]
enable=yes
apps=all
events=ALL
dateformat=%F %T

[manager]
enabled=no
CELCONF

cat > "$TENANT_DIR/asterisk/custom/cel_pgsql.conf" <<CELPGSQL
[global]
hostname=127.0.0.1
port=$DB_PORT
dbname=asterisk
user=voxcall
password=$DB_PASSWORD
table=cel
appname=asterisk_$TENANT_ID
CELPGSQL

# 7c. Healthcheck pós-provisionamento do CEL (executar manualmente após docker compose up -d)
cat > "$TENANT_DIR/check-cel.sh" <<'CHECKCEL'
#!/bin/bash
# Valida que o pipeline CEL está ativo no tenant.
# Uso: ./check-cel.sh
set -e
TENANT_ID=$(grep '^TENANT_ID=' .env | cut -d= -f2)
DB_PORT=$(grep '^DB_PORT=' .env | cut -d= -f2)

echo "=== 1a. Asterisk: módulo cel_pgsql.so carregado? ==="
MOD=$(docker exec ${TENANT_ID}-asterisk asterisk -rx "module show like cel_pgsql" 2>&1 || true)
echo "$MOD"
echo "$MOD" | grep -q "cel_pgsql.so" || {
  echo "FALHA: cel_pgsql.so não está carregado. Corrija com:"
  echo "  docker exec ${TENANT_ID}-asterisk asterisk -rx 'module load cel_pgsql.so'"
  echo "  (ou adicione 'load => cel_pgsql.so' em asterisk/custom/modules.conf)"
  exit 1
}
echo "OK: módulo cel_pgsql.so carregado"

echo ""
echo "=== 1b. Asterisk: cel show status ==="
STATUS=$(docker exec ${TENANT_ID}-asterisk asterisk -rx "cel show status" 2>&1 || true)
echo "$STATUS"
echo "$STATUS" | grep -q "CEL Logging: Enabled" || { echo "FALHA: CEL não está habilitado"; exit 1; }
echo "$STATUS" | grep -qi "PGSQL" || { echo "FALHA: backend cel_pgsql não carregado"; exit 1; }
echo "OK: CEL ativo + cel_pgsql backend"

echo ""
echo "=== 2. DB: smoke test do trigger trg_cel_captura_canal ==="
docker exec ${TENANT_ID}-db psql -U voxcall -d asterisk -At <<SQL
INSERT INTO cel (eventtype, channame, linkedid)
VALUES ('CHAN_START', 'SIP/healthcheck-trunk', 'cel_smoke_$$');
SELECT 'cel_rows=' || COUNT(*) FROM cel WHERE linkedid='cel_smoke_$$';
SELECT 'canal_chamada_rows=' || COUNT(*) FROM canal_chamada WHERE linkedid='cel_smoke_$$';
DELETE FROM canal_chamada WHERE linkedid='cel_smoke_$$';
SQL
echo "Esperado: cel_rows=0 (cancelado), canal_chamada_rows=1"

echo ""
echo "=== 3. Pipeline funcionando? (após chamada real) ==="
echo "Após uma chamada nova, rodar:"
echo "  docker exec ${TENANT_ID}-db psql -U voxcall -d asterisk -c \\"
echo "    \"SELECT COUNT(*) FROM canal_chamada WHERE created_at > now() - interval '5 min';\""
echo "  Esperado: > 0"
CHECKCEL
chmod +x "$TENANT_DIR/check-cel.sh"

# 8. Criar Nginx rate limiting (se não existir) e server block
mkdir -p "$TENANTS_DIR/nginx/conf.d"
RATE_LIMIT_CONF="$TENANTS_DIR/nginx/conf.d/00-rate-limit.conf"
if [ ! -f "$RATE_LIMIT_CONF" ]; then
  cat > "$RATE_LIMIT_CONF" <<'RATELIMIT'
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=30r/s;
limit_req_zone $binary_remote_addr zone=login_limit:10m rate=5r/m;
limit_req_status 429;
RATELIMIT
  echo "  Rate limiting config criado: $RATE_LIMIT_CONF"
fi

NGINX_CONF="$TENANTS_DIR/nginx/conf.d/tenant_${TENANT_ID}.conf"

cat > "$NGINX_CONF" <<NGINXCONF
# Tenant: $TENANT_ID ($DOMAIN) — Slot $SLOT, App porta $APP_PORT, ARI/WSS porta $ARI_PORT
server {
    listen 80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/lib/letsencrypt;
    }

    location / {
        return 301 https://\\\$host\\\$request_uri;
    }
}

server {
    listen 443 ssl;
    http2 on;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    client_max_body_size 50M;

    # Rate limiting na API
    location /api/ {
        limit_req zone=api_limit burst=50 nodelay;
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \\\$host;
        proxy_set_header X-Real-IP \\\$remote_addr;
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }

    # Rate limiting restritivo no login
    location /api/login {
        limit_req zone=login_limit burst=3 nodelay;
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \\\$host;
        proxy_set_header X-Real-IP \\\$remote_addr;
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }

    # WebSocket proxy para Asterisk WS (TLS terminado no Nginx, upstream é WS plain)
    location /ws {
        proxy_pass http://127.0.0.1:$ARI_PORT/ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \\\$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \\\$host;
        proxy_set_header X-Real-IP \\\$remote_addr;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }

    # App (inclui WebSocket do Socket.io)
    location / {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \\\$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \\\$host;
        proxy_set_header X-Real-IP \\\$remote_addr;
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
}
NGINXCONF

# 9. Atualizar registry
python3 -c "
import json
r = json.load(open('$REGISTRY'))
r['tenants']['$TENANT_ID'] = {
    'slot': $SLOT,
    'domain': '$DOMAIN',
    'status': 'provisioned',
    'createdAt': '$(date -u +%Y-%m-%dT%H:%M:%SZ)',
    'appPort': $APP_PORT,
    'dbPort': $DB_PORT,
    'sipPort': $SIP_PORT,
    'amiPort': $AMI_PORT,
    'ariPort': $ARI_PORT,
    'rtpStart': $RTP_START,
    'rtpEnd': $RTP_END,
    'memoryLimit': '512M',
    'cpuLimit': '1.0'
}
r['nextSlot'] = $SLOT + 1
json.dump(r, open('$REGISTRY', 'w'), indent=2)
"

echo ""
echo "=== Tenant '$TENANT_ID' provisionado com sucesso! ==="
echo ""
echo "Próximos passos:"
echo "  1. Copie o código-fonte para: $TENANT_DIR/source/"
echo "     (ou coloque base-source.tar.gz em $TENANTS_DIR/_shared/)"
echo "  2. Build e start:"
echo "     cd $TENANT_DIR && docker compose up -d --build"
echo "  3. Push do schema Drizzle:"
echo "     docker exec ${TENANT_ID}-app npx drizzle-kit push --force"
echo "  4. Reiniciar app (para seed):"
echo "     docker compose restart app"
echo "  4b. Validar pipeline CEL (canal externo):"
echo "     ./check-cel.sh"
echo "  5. SSL (se ainda não tem wildcard):"
echo "     certbot certonly --webroot -w /var/lib/letsencrypt -d $DOMAIN --agree-tos --email $ADMIN_EMAIL"
echo "  6. Reload Nginx:"
echo "     docker exec mt-nginx nginx -t && docker exec mt-nginx nginx -s reload"
echo ""
CRED_FILE="$TENANT_DIR/.credentials"
cat > "$CRED_FILE" <<CRED
# Credenciais do tenant $TENANT_ID — ARQUIVO CONFIDENCIAL
# Gerado em: $(date '+%Y-%m-%d %H:%M:%S')
URL=https://$DOMAIN
ADMIN_USER=superadmin
ADMIN_PASSWORD=$ADMIN_PASSWORD
ADMIN_EMAIL=$ADMIN_EMAIL
DB_PASSWORD=$DB_PASSWORD
AMI_PASSWORD=$AMI_PASSWORD
ARI_PASSWORD=$ARI_PASSWORD
CRED
chmod 600 "$CRED_FILE"

echo "Credenciais salvas em: $CRED_FILE (chmod 600)"
echo "  URL: https://$DOMAIN"
echo "  Admin: superadmin"
echo ""
echo "Portas abertas no firewall (se necessário):"
echo "  SIP: $SIP_PORT/udp,$SIP_PORT/tcp"
echo "  RTP: $RTP_START-$RTP_END/udp"
```

**Higiene de credenciais:** O script salva credenciais em arquivo separado (`chmod 600`) em vez de imprimir senhas no stdout. Nunca redirecionar a saída do provisionamento para logs compartilhados. Rotacionar credenciais periodicamente via `docker exec <id>-app` para atualizar senhas no banco.

### 6.1 CEL (Channel Event Logging) — provisionamento automático

O pipeline `Asterisk CEL → cel (UNLOGGED) → trg_cel_captura_canal → canal_chamada → monitor_voxcall()` alimenta `t_monitor_voxcall.canal` (canal SIP do tronco externo). Sem ele o painel em tempo real fica com a coluna **Canal** vazia.

**Tenant Docker novo (caminho automático):** O `provision-tenant.sh` acima já cobre tudo:

| Componente | Arquivo gerado pelo script |
|---|---|
| Tabela `cel` UNLOGGED + trigger `trg_cel_captura_canal` | `init-db.sql` (seção `===== CEL =====`) |
| Tabela `canal_chamada` + cleanup 24h | `init-db.sql` |
| `cel.conf` (`enable=yes`, `events=ALL`) | `asterisk/custom/cel.conf` |
| `cel_pgsql.conf` apontando para `127.0.0.1:$DB_PORT/asterisk` | `asterisk/custom/cel_pgsql.conf` |
| Healthcheck pós-deploy (`cel show status` + smoke-test do trigger) | `check-cel.sh` |

A imagem `voxcall-asterisk:latest` (entrypoint atualizado em abr/2026) faz `cp /etc/asterisk/custom/*.conf /etc/asterisk/` no boot, então não há rebuild de imagem por tenant. Só reiniciar o container do Asterisk após mexer em `asterisk/custom/`:

```bash
docker compose -f /opt/tenants/<id>/docker-compose.yml restart asterisk
/opt/tenants/<id>/check-cel.sh
```

**Tenant legacy (Asterisk 11 em CentOS 7, source build):** A imagem Docker não se aplica — o `cel_pgsql.so` pode não estar compilado. Receita completa de compilação manual está em `.agents/skills/asterisk-callcenter-expert/SKILL.md` seção "Habilitar CEL para captura de canal externo" (compilar `cel_pgsql.so` a partir do source, copiar para `/usr/lib64/asterisk/modules/`, carregar com `module load`). Após habilitar o módulo, aplicar **manualmente** os mesmos arquivos `cel.conf` (com `events=CHAN_START` no Asterisk 11, não `ALL`) e `cel_pgsql.conf` apontando para o extdb do tenant. Validar com `asterisk -rx 'cel show status'` (esperado: `CEL Logging: Enabled` + linha do `cel_pgsql backend`).

---

## 7. Script de Remoção

### remove-tenant.sh

```bash
#!/bin/bash
set -euo pipefail

TENANTS_DIR="/opt/tenants"
REGISTRY="$TENANTS_DIR/_shared/tenant-registry.json"

[ $# -lt 1 ] && { echo "Uso: $0 <tenant_id> [--purge]"; exit 1; }

TENANT_ID="$1"
PURGE="${2:-}"
TENANT_DIR="$TENANTS_DIR/$TENANT_ID"

if [ ! -d "$TENANT_DIR" ]; then
  echo "ERRO: Tenant '$TENANT_ID' não encontrado em $TENANT_DIR"
  exit 1
fi

echo "=== Removendo tenant: $TENANT_ID ==="
read -p "Confirma remoção do tenant '$TENANT_ID'? (digite 'sim' para confirmar): " CONFIRM
[ "$CONFIRM" != "sim" ] && { echo "Cancelado."; exit 0; }

# 1. Parar containers
echo "  Parando containers..."
cd "$TENANT_DIR"
docker compose down 2>/dev/null || true

# 2. Remover Nginx config
NGINX_CONF="$TENANTS_DIR/nginx/conf.d/tenant_${TENANT_ID}.conf"
if [ -f "$NGINX_CONF" ]; then
  echo "  Removendo config Nginx..."
  rm -f "$NGINX_CONF"
  docker exec mt-nginx nginx -t 2>/dev/null && docker exec mt-nginx nginx -s reload 2>/dev/null || true
fi

# 3. Purge ou manter dados
if [ "$PURGE" = "--purge" ]; then
  echo "  PURGE: Removendo volumes Docker..."
  docker compose down -v 2>/dev/null || true
  echo "  PURGE: Removendo diretório do tenant..."
  rm -rf "$TENANT_DIR"
else
  echo "  Mantendo dados em $TENANT_DIR (use --purge para remover tudo)"
  # Marcar como inativo no registry
fi

# 4. Atualizar registry
if [ -f "$REGISTRY" ]; then
  python3 -c "
import json
r = json.load(open('$REGISTRY'))
if '$TENANT_ID' in r.get('tenants', {}):
    if '$PURGE' == '--purge':
        del r['tenants']['$TENANT_ID']
    else:
        r['tenants']['$TENANT_ID']['status'] = 'inactive'
json.dump(r, open('$REGISTRY', 'w'), indent=2)
"
fi

echo "=== Tenant '$TENANT_ID' removido ==="
```

---

## 8. Script de Atualização

### update-tenant.sh

```bash
#!/bin/bash
set -euo pipefail

TENANTS_DIR="/opt/tenants"
BASE_SOURCE="$TENANTS_DIR/_shared/base-source.tar.gz"

[ $# -lt 1 ] && { echo "Uso: $0 <tenant_id|all> [--rebuild]"; exit 1; }

TARGET="$1"
REBUILD="${2:-}"

update_tenant() {
  local tid="$1"
  local tdir="$TENANTS_DIR/$tid"

  if [ ! -d "$tdir" ]; then
    echo "AVISO: Tenant '$tid' não encontrado, pulando."
    return
  fi

  echo "=== Atualizando tenant: $tid ==="

  # Atualizar código-fonte
  if [ -f "$BASE_SOURCE" ]; then
    echo "  Extraindo código-fonte atualizado..."
    rm -rf "$tdir/source"
    mkdir -p "$tdir/source"
    tar xzf "$BASE_SOURCE" -C "$tdir/source"
  fi

  cd "$tdir"

  if [ "$REBUILD" = "--rebuild" ]; then
    echo "  Rebuild completo..."
    docker compose build --no-cache
  else
    echo "  Build incremental..."
    docker compose build
  fi

  echo "  Reiniciando app..."
  docker compose up -d app

  echo "  Aguardando app subir..."
  sleep 10

  echo "  Sincronizando schema..."
  docker exec "${tid}-app" npx drizzle-kit push --force 2>/dev/null || true

  echo "  Reiniciando após schema push..."
  docker compose restart app

  echo "  Tenant '$tid' atualizado!"
}

if [ "$TARGET" = "all" ]; then
  echo "=== Atualizando TODOS os tenants ==="
  for dir in "$TENANTS_DIR"/*/; do
    tid=$(basename "$dir")
    [ "$tid" = "nginx" ] || [ "$tid" = "_shared" ] && continue
    [ -f "$dir/docker-compose.yml" ] || continue
    update_tenant "$tid"
  done
else
  update_tenant "$TARGET"
fi
```

---

## 9. Backup Centralizado

### backup-all.sh

```bash
#!/bin/bash
set -euo pipefail

TENANTS_DIR="/opt/tenants"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_BASE="/opt/backups/multi-tenant"

mkdir -p "$BACKUP_BASE"

echo "=== Backup centralizado de todos os tenants ($TIMESTAMP) ==="

for dir in "$TENANTS_DIR"/*/; do
  tid=$(basename "$dir")
  [ "$tid" = "nginx" ] || [ "$tid" = "_shared" ] && continue
  [ -f "$dir/docker-compose.yml" ] || continue

  echo "--- Backup: $tid ---"
  BDIR="$BACKUP_BASE/$tid/backup_$TIMESTAMP"
  mkdir -p "$BDIR"

  # Backup do PostgreSQL (ambos os bancos)
  echo "  DB voxcall..."
  docker exec "${tid}-db" pg_dump -U voxcall voxcall 2>/dev/null | gzip > "$BDIR/voxcall.sql.gz" || echo "  AVISO: falha DB voxcall"

  echo "  DB asterisk..."
  docker exec "${tid}-db" pg_dump -U voxcall asterisk 2>/dev/null | gzip > "$BDIR/asterisk.sql.gz" || echo "  AVISO: falha DB asterisk"

  # Backup dos configs
  echo "  Configs..."
  tar czf "$BDIR/configs.tar.gz" -C "$dir" config/ .env docker-compose.yml 2>/dev/null || true

  # Backup das configs Asterisk customizadas
  if [ -d "$dir/asterisk" ]; then
    tar czf "$BDIR/asterisk-custom.tar.gz" -C "$dir" asterisk/ 2>/dev/null || true
  fi

  echo "  Tenant $tid backup concluído: $BDIR"
done

# Retenção: manter últimos 7 backups por tenant
for tenant_backup_dir in "$BACKUP_BASE"/*/; do
  tid=$(basename "$tenant_backup_dir")
  BACKUPS=($(ls -1d "$tenant_backup_dir"/backup_* 2>/dev/null | sort))
  TOTAL=${#BACKUPS[@]}
  if [ $TOTAL -gt 7 ]; then
    REMOVE=$((TOTAL - 7))
    echo "  Retenção $tid: removendo $REMOVE backup(s) antigo(s)"
    for ((i=0; i<REMOVE; i++)); do
      rm -rf "${BACKUPS[$i]}"
    done
  fi
done

echo "=== Backup centralizado concluído ==="
```

### Crontab Sugerido

```cron
# Backup diário de todos os tenants às 03:00
0 3 * * * /opt/tenants/_shared/backup-all.sh >> /var/log/tenant-backup.log 2>&1
```

---

## 10. Monitoramento

### monitor-all.sh

```bash
#!/bin/bash

TENANTS_DIR="/opt/tenants"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           MULTI-TENANT MONITOR — $(date '+%Y-%m-%d %H:%M')           ║"
echo "╠══════════════════════════════════════════════════════════════╣"
printf "║ %-12s │ %-8s │ %-8s │ %-8s │ %-10s ║\n" "TENANT" "APP" "AST" "DB" "MEM TOTAL"
echo "╠══════════════════════════════════════════════════════════════╣"

for dir in "$TENANTS_DIR"/*/; do
  tid=$(basename "$dir")
  [ "$tid" = "nginx" ] || [ "$tid" = "_shared" ] && continue
  [ -f "$dir/docker-compose.yml" ] || continue

  APP_STATUS=$(docker inspect --format='{{.State.Status}}' "${tid}-app" 2>/dev/null || echo "down")
  AST_STATUS=$(docker inspect --format='{{.State.Status}}' "${tid}-asterisk" 2>/dev/null || echo "down")
  DB_STATUS=$(docker inspect --format='{{.State.Status}}' "${tid}-db" 2>/dev/null || echo "down")

  # Calcular memória total do tenant
  MEM_TOTAL=0
  for container in "${tid}-app" "${tid}-asterisk" "${tid}-db"; do
    MEM=$(docker stats --no-stream --format '{{.MemUsage}}' "$container" 2>/dev/null | awk -F'/' '{print $1}' | tr -d ' ')
    if [[ "$MEM" == *GiB* ]]; then
      MEM_MB=$(echo "$MEM" | tr -d 'GiB' | awk '{printf "%.0f", $1*1024}')
    elif [[ "$MEM" == *MiB* ]]; then
      MEM_MB=$(echo "$MEM" | tr -d 'MiB' | awk '{printf "%.0f", $1}')
    else
      MEM_MB=0
    fi
    MEM_TOTAL=$((MEM_TOTAL + MEM_MB))
  done

  # Colorir status
  APP_ICON=$( [ "$APP_STATUS" = "running" ] && echo "✅" || echo "❌" )
  AST_ICON=$( [ "$AST_STATUS" = "running" ] && echo "✅" || echo "❌" )
  DB_ICON=$( [ "$DB_STATUS" = "running" ] && echo "✅" || echo "❌" )

  printf "║ %-12s │ %s %-5s │ %s %-5s │ %s %-5s │ %6sMB   ║\n" \
    "$tid" "$APP_ICON" "$APP_STATUS" "$AST_ICON" "$AST_STATUS" "$DB_ICON" "$DB_STATUS" "$MEM_TOTAL"
done

echo "╠══════════════════════════════════════════════════════════════╣"

# Recursos do servidor
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2+$4}')
MEM_INFO=$(free -m | awk '/Mem:/{printf "%s/%sMB (%.1f%%)", $3, $2, $3/$2*100}')
DISK_INFO=$(df -h / | awk 'NR==2{printf "%s/%s (%s)", $3, $2, $5}')

printf "║ %-60s ║\n" "CPU: ${CPU_USAGE}% | RAM: ${MEM_INFO}"
printf "║ %-60s ║\n" "Disco: ${DISK_INFO}"
echo "╚══════════════════════════════════════════════════════════════╝"
```

### Integração com Cloud Storage (upload de backups)

Os backups locais devem ser enviados ao Replit Cloud Storage para redundância geográfica. Usar a API REST do VoxCALL (`/api/cloud-storage`) que já implementa o serviço `CloudStorageService`:

```bash
#!/bin/bash
# upload-backups-cloud.sh — Envia backups compactados para Cloud Storage
set -euo pipefail

VOXCALL_API="https://voxtel.voxcall.cc"
CLOUD_STORAGE_KEY="${CLOUD_STORAGE_KEY:?Defina CLOUD_STORAGE_KEY}"
BACKUP_BASE="/opt/backups/multi-tenant"
TIMESTAMP=$(date +%Y%m%d)

for tenant_dir in "$BACKUP_BASE"/*/; do
  tid=$(basename "$tenant_dir")
  LATEST=$(ls -1d "$tenant_dir"/backup_* 2>/dev/null | sort | tail -1)
  [ -z "$LATEST" ] && continue

  ARCHIVE="/tmp/${tid}_backup_${TIMESTAMP}.tar.gz"
  tar czf "$ARCHIVE" -C "$LATEST" .

  echo "Enviando backup $tid para Cloud Storage..."
  curl -s -X POST "$VOXCALL_API/api/cloud-storage/upload" \
    -H "Authorization: Bearer $CLOUD_STORAGE_KEY" \
    -F "file=@$ARCHIVE" \
    -F "path=backups/multi-tenant/${tid}/${tid}_${TIMESTAMP}.tar.gz" \
    && echo "  OK: $tid" \
    || echo "  ERRO: $tid"

  rm -f "$ARCHIVE"
done

echo "Upload de backups para Cloud Storage concluído"
```

**Crontab:** Executar após o backup local (ex: `0 4 * * *`), referenciando o script `upload-backups-cloud.sh`.

### Alertas e Notificações

```bash
#!/bin/bash
# alert-check.sh — Verifica thresholds e envia alertas
set -euo pipefail

TENANTS_DIR="/opt/tenants"
ALERT_WEBHOOK="${ALERT_WEBHOOK:-}"  # URL do webhook (Slack, Discord, etc.)
ALERT_EMAIL="${ALERT_EMAIL:-}"       # Email para alertas via sendmail
ALERT_LOG="/var/log/tenant-alerts.log"

DISK_THRESHOLD=85   # % de uso de disco
MEM_THRESHOLD=90    # % de uso de RAM
CPU_THRESHOLD=95    # % de uso de CPU

send_alert() {
  local LEVEL=$1 SUBJECT=$2 BODY=$3
  local TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$TIMESTAMP] [$LEVEL] $SUBJECT: $BODY" >> "$ALERT_LOG"

  if [ -n "$ALERT_WEBHOOK" ]; then
    curl -s -X POST "$ALERT_WEBHOOK" \
      -H "Content-Type: application/json" \
      -d "{\"text\":\"[$LEVEL] $SUBJECT\\n$BODY\"}" || true
  fi

  if [ -n "$ALERT_EMAIL" ]; then
    echo "$BODY" | mail -s "[$LEVEL] Multi-Tenant Alert: $SUBJECT" "$ALERT_EMAIL" 2>/dev/null || true
  fi
}

# Verificar cada tenant
for dir in "$TENANTS_DIR"/*/; do
  tid=$(basename "$dir")
  [ "$tid" = "nginx" ] || [ "$tid" = "_shared" ] && continue
  [ -f "$dir/docker-compose.yml" ] || continue

  for container in "${tid}-app" "${tid}-asterisk" "${tid}-db"; do
    STATUS=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "not_found")
    if [ "$STATUS" != "running" ]; then
      send_alert "CRITICAL" "Container down: $container" "Status: $STATUS. Tentando restart..."
      docker start "$container" 2>/dev/null || true
    fi
  done
done

# Verificar recursos do servidor
DISK_USAGE=$(df / | awk 'NR==2{print int($5)}')
MEM_USAGE=$(free | awk '/Mem:/{printf "%.0f", $3/$2*100}')
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{printf "%.0f", $2+$4}')

[ "$DISK_USAGE" -ge "$DISK_THRESHOLD" ] && \
  send_alert "WARNING" "Disco alto" "Uso: ${DISK_USAGE}% (threshold: ${DISK_THRESHOLD}%)"

[ "$MEM_USAGE" -ge "$MEM_THRESHOLD" ] && \
  send_alert "WARNING" "Memória alta" "Uso: ${MEM_USAGE}% (threshold: ${MEM_THRESHOLD}%)"

[ "$CPU_USAGE" -ge "$CPU_THRESHOLD" ] && \
  send_alert "WARNING" "CPU alta" "Uso: ${CPU_USAGE}% (threshold: ${CPU_THRESHOLD}%)"
```

**Crontab de alertas:**
```cron
# Verificação de saúde a cada 5 minutos
*/5 * * * * /opt/tenants/_shared/alert-check.sh 2>&1
```

### Logging Centralizado

Consolidar logs de todos os tenants em um diretório central com rotação:

```bash
# /etc/logrotate.d/multi-tenant
/var/log/tenant-*.log {
    daily
    rotate 14
    compress
    missingok
    notifempty
    create 0644 root root
}

# Coletar logs de cada tenant:
# docker logs --since 24h ${tid}-app >> /var/log/tenant-${tid}-app.log
# docker logs --since 24h ${tid}-asterisk >> /var/log/tenant-${tid}-asterisk.log
```

**Script de coleta de logs:**
```bash
#!/bin/bash
# collect-logs.sh — Centraliza logs de todos os tenants
TENANTS_DIR="/opt/tenants"
LOG_DIR="/var/log/multi-tenant"
mkdir -p "$LOG_DIR"

for dir in "$TENANTS_DIR"/*/; do
  tid=$(basename "$dir")
  [ "$tid" = "nginx" ] || [ "$tid" = "_shared" ] && continue
  [ -f "$dir/docker-compose.yml" ] || continue

  for svc in app asterisk db; do
    docker logs --since 24h "${tid}-${svc}" >> "$LOG_DIR/${tid}-${svc}.log" 2>&1 || true
  done
done
```

**Crontab:** `0 * * * * /opt/tenants/_shared/collect-logs.sh` (coleta horária).

---

## 11. Firewall (UFW/iptables)

### CRITICAL: Preservar portas de serviços existentes ao ativar UFW

**Incidente real (Abr 2026):** Ao provisionar o primeiro tenant (PlanoClin) em um servidor que já tinha VoxZap rodando, o script habilitou UFW e só adicionou as portas do novo tenant. O VoxZap perdeu conectividade RTP para chamadas de voz WhatsApp porque as portas existentes (SIP 5060, RTP 10000-20000, TURN relay 49152-65535) foram bloqueadas pelo novo firewall.

**REGRA:** Antes de habilitar/modificar UFW, SEMPRE verificar serviços existentes com `ss -ulnp; ss -tlnp` e garantir que TODAS as portas estejam permitidas.

### Portas do sistema base (SEMPRE abrir)

```bash
# Portas que DEVEM estar abertas em TODO servidor multi-tenant:
ufw allow 22300/tcp comment "SSH"
ufw allow 80/tcp comment "HTTP"
ufw allow 443/tcp comment "HTTPS"
ufw allow 5060/udp comment "SIP-UDP-main"
ufw allow 5060/tcp comment "SIP-TCP-main"
ufw allow 8089/tcp comment "Asterisk-WSS"
ufw allow 10000:20000/udp comment "RTP-main"
ufw allow 3478/udp comment "TURN-UDP"
ufw allow 3478/tcp comment "TURN-TCP"
ufw allow 49152:65535/udp comment "TURN-relay"
```

### Portas por tenant

```bash
open_tenant_ports() {
  local TENANT_ID=$1
  local SIP_PORT=$2
  local RTP_START=$3
  local RTP_END=$4

  ufw allow ${SIP_PORT}/udp comment "SIP ${TENANT_ID}"
  ufw allow ${SIP_PORT}/tcp comment "SIP ${TENANT_ID}"
  ufw allow ${RTP_START}:${RTP_END}/udp comment "RTP ${TENANT_ID}"
}

# Exemplo: Tenant slot 1
open_tenant_ports acme 5070 11000 11999

# Exemplo: Tenant slot 2
open_tenant_ports globex 5080 12000 12999
```

### Docker network_mode para apps com chamadas WhatsApp

**Apps que usam VoxCall-GW (WhatsApp Calling via ExternalMedia/ARI) DEVEM rodar com `network_mode: host`.** Com bridge networking, o Asterisk envia RTP para o IP do host mas os pacotes não chegam ao container Docker (sem port mapping para portas UDP dinâmicas). Com `network_mode: host`, o app recebe RTP diretamente.

**ARI/WS não precisa de porta no firewall:** O Asterisk HTTP (ARI + WS) é vinculado a `127.0.0.1`. Clientes WebRTC acessam via Nginx HTTPS na porta 443 (`wss://dominio.com/ws` → Nginx termina TLS → proxy para `http://127.0.0.1:ARI_PORT/ws`).

**Portas que NÃO devem ser abertas externamente:**
- APP_PORT (5001, 5002...) — acessado apenas pelo Nginx local
- DB_PORT (25433, 25434...) — apenas 127.0.0.1
- AMI_PORT (5039, 5040...) — apenas 127.0.0.1
- ARI_PORT (8089, 8090...) — apenas 127.0.0.1

---

## 12. Requisitos do Servidor

### Hardware Mínimo por Tenant

| Recurso | Por Tenant | 5 Tenants | 10 Tenants | 20 Tenants |
|---------|-----------|-----------|------------|------------|
| CPU | 2 cores | 10 cores | 20 cores | 40 cores |
| RAM | 2 GB | 10 GB | 20 GB | 40 GB |
| Disco | 20 GB | 100 GB | 200 GB | 400 GB |
| Banda | 10 Mbps | 50 Mbps | 100 Mbps | 200 Mbps |

### Recomendação de Servidor

| Tenants | Servidor Recomendado |
|---------|---------------------|
| 1-5 | 8 cores / 16 GB RAM / 200 GB SSD |
| 6-10 | 16 cores / 32 GB RAM / 500 GB SSD |
| 11-20 | 32 cores / 64 GB RAM / 1 TB SSD |

### Software Necessário

- Ubuntu 22.04+ ou Debian 12+
- Docker CE + Docker Compose v2
- Certbot (para SSL)
- Python 3 (para scripts de registry)
- UFW ou iptables (firewall)
- curl, jq, openssl (utilitários)

---

## 13. Checklist de Provisionamento

1. [ ] Verificar recursos disponíveis no servidor (`free -h`, `df -h`, `nproc`)
2. [ ] Definir `tenant_id` (alfanumérico, sem espaços, lowercase)
3. [ ] Configurar DNS: `dominio.com` → IP do servidor
4. [ ] Executar `provision-tenant.sh <id> <dominio> <email> <senha>`
5. [ ] Copiar código-fonte para `/opt/tenants/<id>/source/` (ou usar base-source.tar.gz)
6. [ ] Build: `cd /opt/tenants/<id> && docker compose up -d --build`
7. [ ] Push schema: `docker exec <id>-app npx drizzle-kit push --force`
8. [ ] Restart app: `docker compose restart app`
8b. [ ] Validar CEL: `cd /opt/tenants/<id> && ./check-cel.sh` (deve passar items 1 e 2)
9. [ ] SSL: `certbot certonly --webroot -w /var/lib/letsencrypt -d <dominio>`
10. [ ] Reload Nginx: `docker exec mt-nginx nginx -t && docker exec mt-nginx nginx -s reload`
11. [ ] Abrir portas no firewall: SIP + RTP do tenant
12. [ ] Testar acesso: `https://<dominio>` — login com superadmin
13. [ ] Configurar AMI/ARI no VoxCALL (via interface web)
14. [ ] Testar chamada SIP de ponta a ponta

---

## 14. Troubleshooting

### Containers não sobem
```bash
cd /opt/tenants/<id>
docker compose logs --tail=50
docker compose ps
```

### Asterisk não conecta ao PostgreSQL
- O Asterisk roda em `network_mode: host`, então acessa o DB via `127.0.0.1:DB_PORT`
- Verificar se a porta do DB está exposta em `127.0.0.1:${DB_PORT}`
- Testar: `psql -h 127.0.0.1 -p ${DB_PORT} -U voxcall -d asterisk`

### SIP não registra
- Verificar porta SIP: `ss -tlnup | grep ${SIP_PORT}`
- Verificar firewall: `ufw status | grep ${SIP_PORT}`
- Verificar PJSIP: `docker exec <id>-asterisk asterisk -rx "pjsip show transports"`

### Nginx 502 Bad Gateway
- Verificar se o app está rodando: `docker inspect <id>-app`
- Verificar porta: `curl -s http://127.0.0.1:${APP_PORT}/`
- Verificar config: `docker exec mt-nginx nginx -t`

### Conflito de portas RTP
- Nunca alocar faixas RTP sobrepostas
- Verificar: `ss -ulnp | grep -E '1[0-9]{4}'`
- Cada tenant deve ter exatamente 1000 portas RTP exclusivas

### Memória insuficiente
- Monitorar: `./monitor-all.sh`
- Ajustar limites no `.env` do tenant
- Considerar migrar tenants para outro servidor

### Tenant aponta para Asterisk legacy do cliente (chan_sip)
Alguns tenants apontam o VoxCALL para o Asterisk **legado do próprio cliente** (que só tem `chan_sip` carregado), em vez do `<id>-asterisk` provisionado. Sintoma: membros de fila aparecem como `(Invalid)` e Originate falha.

**Fix:** Configurar o toggle PJSIP/SIP por tenant via UI ou arquivo:
```bash
# Forçar SIP no tenant
docker exec <id>-app sh -c 'echo "{\"channelTech\":\"SIP\"}" > /app/config/asterisk-config.json'
docker restart <id>-app

# Validar membros da fila no DB do Asterisk legacy
psql -h <asterisk_db_host> -p <port> -U asterisk -d asterisk \
  -c "SELECT membername, interface FROM queue_member_table;"
# Esperado: interface = SIP/<ramal>
```

Cada tenant tem seu próprio `/app/config/asterisk-config.json` (default `PJSIP`). Veja `.agents/skills/voxcall-native-asterisk-deploy/SKILL.md` seção "Toggle SIP/PJSIP" para detalhes do helper.

### Build (vite/esbuild) dentro do container exige `-w /app`
`docker exec <id>-app sh -c 'cd /app && npx vite build'` resolve o `outDir` errado e os assets gerados não chegam a `/app/dist/public/`. Sempre use:
```bash
docker exec -w /app <id>-app sh -c 'NODE_OPTIONS=--max-old-space-size=2048 npx vite build'
docker exec -w /app <id>-app sh -c 'NODE_OPTIONS=--max-old-space-size=2048 npx esbuild server/index.ts --platform=node --packages=external --bundle --format=esm --outdir=dist'
```
Após qualquer mudança de UI, conferir com `grep -c <novo-testid> /app/dist/public/assets/index-*.js` antes de pedir ao usuário um hard refresh.

---

## 15. Publicação e Sincronização

Esta skill é sincronizada com o repositório central de skills via `sync-skills.sh`:

```bash
# Publicar alterações desta skill para o repositório central
./sync-skills.sh push

# Baixar atualizações do repositório central
./sync-skills.sh pull
```

**Repositório:** `github.com/ricardohonoratoherculano-cmd/voxzap-skills`
**Caminho no repo:** `skills/multi-tenant-server/SKILL.md`
**Último push:** commit `5865a0c040b4bc6e20d534de1bcb6ea99fe192ad` (v4 — WS/TLS, Cloud Storage, alerting, hardened)

Ao modificar esta skill, sempre executar `sync-skills.sh push` para manter o repositório central atualizado. Para detalhes sobre o sistema de sincronização, consultar a skill `skills-sync`.
