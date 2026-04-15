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
| **WSS (WebRTC)** | 8089 + (N×10) | 8099 | 8109 | 8119 | 8189 | 0.0.0.0 |
| **AMI** | 5038 + N | 5039 | 5040 | 5041 | 5048 | 127.0.0.1 |
| **ARI HTTP** | 8088 + N | 8089 | 8090 | 8091 | 8098 | 127.0.0.1 |
| **RTP início** | 10000 + (N×1000) | 11000 | 12000 | 13000 | 20000 | 0.0.0.0 |
| **RTP fim** | RTP início + 999 | 11999 | 12999 | 13999 | 20999 | 0.0.0.0 |

**WSS (WebSocket Secure):** Porta usada pelo Asterisk para conexões WebRTC (softphone browser). O Nginx do tenant faz proxy reverso da porta WSS, permitindo que clientes WebRTC se conectem via `wss://dominio.com/ws`. A porta WSS direta é opcional — pode ser exposta no firewall para clientes SIP que conectam direto.

**Portas expostas externamente (firewall):** SIP, WSS e RTP. Todas as demais (APP, DB, AMI, ARI) ficam em `127.0.0.1` apenas.

### Limites por Servidor

- **Máximo recomendado**: 20 tenants por servidor dedicado (depende dos recursos)
- **RTP**: Cada tenant tem 1000 portas RTP (suficiente para ~500 chamadas simultâneas)
- **Portas reservadas**: Slot 0 é reservado (portas padrão do Asterisk para uso direto se necessário)
- **Firewall**: Apenas portas SIP e RTP do tenant precisam ser abertas no firewall externo; AMI/ARI ficam em `127.0.0.1`

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
      "wssPort": 8099,
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
      "wssPort": 8109,
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
      - ./asterisk:/etc/asterisk/custom:ro
    environment:
      - ASTERISK_SIP_PORT=${SIP_PORT}
      - ASTERISK_AMI_PORT=${AMI_PORT}
      - ASTERISK_ARI_PORT=${ARI_PORT}
      - ASTERISK_RTP_START=${RTP_START}
      - ASTERISK_RTP_END=${RTP_END}
      - ASTERISK_EXTERNAL_IP=${EXTERNAL_IP}
      - ASTERISK_WSS_PORT=${WSS_PORT}
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
WSS_PORT=8099
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
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./conf.d:/etc/nginx/conf.d:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
      - /var/lib/letsencrypt:/var/lib/letsencrypt
    network_mode: host
```

**`network_mode: host`**: Permite que o Nginx acesse `127.0.0.1:APP_PORT` de cada tenant diretamente, sem precisar de rede Docker compartilhada.

### Template de Server Block (conf.d/tenant_{id}.conf)

```nginx
# Rate limiting zones (colocar no nginx.conf principal ou em conf.d/00-rate-limit.conf)
# limit_req_zone $binary_remote_addr zone=api_limit:10m rate=30r/s;
# limit_req_zone $binary_remote_addr zone=login_limit:10m rate=5r/m;

# Tenant: acme (slot 1, app porta 5001, WSS porta 8099)
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

    # WebSocket proxy para Asterisk WSS (WebRTC softphone)
    location /ws {
        proxy_pass http://127.0.0.1:8099/ws;
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
WSS_PORT=${ASTERISK_WSS_PORT:-8089}
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
bindaddr=0.0.0.0
bindport=${WSS_PORT}
tlsenable=no
EOF

ARI_PASS=${ARI_PASSWORD:?ERRO: ARI_PASSWORD obrigatório}
cat > /etc/asterisk/ari.conf <<EOF
[general]
enabled=yes
pretty=yes
allowed_origins=*

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
read=all
write=all
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

[transport-wss]
type=transport
protocol=wss
bind=0.0.0.0:${WSS_PORT}
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

echo "[entrypoint] Asterisk configurado: SIP=${SIP_PORT} WSS=${WSS_PORT} AMI=${AMI_PORT} ARI=${ARI_PORT} RTP=${RTP_START}-${RTP_END}"

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
WSS_PORT=$((8089 + SLOT * 10))
RTP_START=$((10000 + SLOT * 1000))
RTP_END=$((RTP_START + 999))

DB_PASSWORD="voxcall_$(openssl rand -hex 8)"
SESSION_SECRET="session_$(openssl rand -hex 16)"
AMI_PASSWORD="ami_$(openssl rand -hex 12)"
ARI_PASSWORD="ari_$(openssl rand -hex 12)"

echo "  Portas: APP=$APP_PORT DB=$DB_PORT SIP=$SIP_PORT WSS=$WSS_PORT AMI=$AMI_PORT ARI=$ARI_PORT RTP=$RTP_START-$RTP_END"

# 1. Criar diretórios
TENANT_DIR="$TENANTS_DIR/$TENANT_ID"
mkdir -p "$TENANT_DIR"/{source,config,backups,asterisk}

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
WSS_PORT=$WSS_PORT
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
      - ./asterisk:/etc/asterisk/custom:ro
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
# Tenant: $TENANT_ID ($DOMAIN) — Slot $SLOT, App porta $APP_PORT, WSS porta $WSS_PORT
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

    # WebSocket proxy para Asterisk WSS (WebRTC softphone)
    location /ws {
        proxy_pass http://127.0.0.1:$WSS_PORT/ws;
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
    'wssPort': $WSS_PORT,
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
echo "  5. SSL (se ainda não tem wildcard):"
echo "     certbot certonly --webroot -w /var/lib/letsencrypt -d $DOMAIN --agree-tos --email $ADMIN_EMAIL"
echo "  6. Reload Nginx:"
echo "     docker exec mt-nginx nginx -t && docker exec mt-nginx nginx -s reload"
echo ""
echo "Credenciais:"
echo "  URL: https://$DOMAIN"
echo "  Admin: superadmin / $ADMIN_PASSWORD"
echo "  Email: $ADMIN_EMAIL"
echo "  DB Password: $DB_PASSWORD"
echo "  AMI Password: $AMI_PASSWORD"
echo "  ARI Password: $ARI_PASSWORD"
echo ""
echo "Portas abertas no firewall (se necessário):"
echo "  SIP: $SIP_PORT/udp,$SIP_PORT/tcp"
echo "  WSS: $WSS_PORT/tcp"
echo "  RTP: $RTP_START-$RTP_END/udp"
```

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

---

## 11. Firewall (UFW/iptables)

Cada tenant precisa das seguintes portas abertas no firewall externo:

```bash
# Template para abrir portas de um tenant
open_tenant_ports() {
  local TENANT_ID=$1
  local SIP_PORT=$2
  local WSS_PORT=$3
  local RTP_START=$4
  local RTP_END=$5

  ufw allow ${SIP_PORT}/udp comment "SIP ${TENANT_ID}"
  ufw allow ${SIP_PORT}/tcp comment "SIP ${TENANT_ID}"
  ufw allow ${WSS_PORT}/tcp comment "WSS ${TENANT_ID}"
  ufw allow ${RTP_START}:${RTP_END}/udp comment "RTP ${TENANT_ID}"
}

# Exemplo: Tenant slot 1
open_tenant_ports acme 5070 8099 11000 11999

# Exemplo: Tenant slot 2
open_tenant_ports globex 5080 8109 12000 12999
```

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
