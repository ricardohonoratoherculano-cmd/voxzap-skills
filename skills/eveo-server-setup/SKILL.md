---
name: eveo-server-setup
description: Setup padrão e checklist de provisionamento para servidores dedicados do provedor EVEO (eveo*.voxserver.app.br). Use quando for instalar qualquer cliente novo (VoxZap, VoxCall, Voxtel-IO Hub, multi-tenant) em uma VPS EVEO, OU quando precisar diagnosticar/corrigir uma instalação EVEO existente. Garante que Docker seja instalado direto no NVMe RAID desde o início, evitando o problema de SSD pequeno (~100GB LVM) ficar lotado enquanto 1.8TB de NVMe ficam ociosos. Inclui mapeamento de hardware, ordem correta de bootstrap, validações, e procedimento de migração quando já está instalado errado.
---

# EVEO Server Setup — Checklist de Provisionamento

## Contexto

EVEO é provedor de servidores dedicados usado pela Voxtel. Hostnames seguem o padrão `eveo<N>.voxserver.app.br`. SSH na **porta 22300** (não 22). Acesso `root` com senha (sem chave por padrão).

### Hardware típico EVEO (baseado em eveo1)
- **Disco de boot**: 1× SSD SATA ~480GB (`/dev/sda`) particionado em LVM com VG `ubuntu-vg`. Apenas ~100GB são alocados ao LV root inicialmente — o resto do VG fica livre como "buffer".
- **Storage principal**: 2× NVMe Kingston SNV3 1.8TB (`/dev/nvme0n1` + `/dev/nvme1n1`) em **RAID 1 mdadm** → `/dev/md0`, montado em `/nvme`.
- **CPU**: tipicamente 8 vCPU (Ryzen / Xeon E)
- **RAM**: 8–32 GB
- **Rede**: 1Gbps com IPv4 público + reverse DNS configurável

### O problema clássico

Sem instrução em contrário, a equipe instala Docker no padrão (`/var/lib/docker` no SSD) e **esquece completamente do RAID NVMe**. Resultado real visto no Locktec (abril/2026):

| Métrica | Antes do fix | Causa |
|---|---|---|
| `/` em 78% (72GB/98GB) | LV root nunca foi expandido | LVM com 120GB livres no VG ignorados |
| `/nvme` em 0.0001% (32K/1.8TB) | RAID montado mas não usado | Ninguém apontou Docker pra lá |
| Risco | "disk full" → DB para → cliente offline | — |

**Esta skill existe para esse problema NUNCA acontecer de novo em servidor EVEO.**

---

> **Nota cruzada**: o pre-flight check da skill `voxzap-multitenant-install` valida automaticamente se o Docker está rodando no maior volume disponível e aborta com exit 1 caso contrário. Use esse check como rede de segurança antes de provisionar QUALQUER tenant novo, mesmo em servidor que já parece configurado. Ele detecta também se alguém esqueceu de migrar o Docker pra `/nvme` depois de reiniciar a VPS.

## 1. Inventário inicial (sempre rodar antes de qualquer coisa)

```bash
# Identificar hardware
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL
cat /proc/mdstat                    # confirma RAID NVMe
mdadm --detail /dev/md0 2>/dev/null # detalhes RAID se existir
vgs && lvs                          # estado LVM
df -h
nproc && free -h
```

### Saída esperada em servidor EVEO virgem
```
NAME       SIZE  TYPE  MOUNTPOINT  MODEL
sda        447G  disk              SSD (boot)
├─sda1     ...
└─sda3     ...   lvm
nvme0n1    1.8T  disk              KINGSTON SNV3...
└─md0      1.8T  raid1 /nvme
nvme1n1    1.8T  disk              KINGSTON SNV3...
└─md0      1.8T  raid1 /nvme

ubuntu-vg  220G total  100G usado em ubuntu-lv  (~120G livre)
```

Se o RAID NÃO existir, **abrir ticket EVEO** pedindo configuração de RAID 1 nos NVMes antes de prosseguir. Não tente fazer instalação de produção sem RAID.

---

## 2. Bootstrap padrão para servidor EVEO novo

Execute **NESTA ORDEM** antes de instalar QUALQUER container:

### 2.1 Garantir RAID NVMe montado e em fstab

```bash
# Se /nvme não existir
mkdir -p /nvme
mount /dev/md0 /nvme
echo "/dev/md0 /nvme ext4 defaults,noatime 0 2" >> /etc/fstab
mount -a && df -h /nvme
```

### 2.2 Expandir LV root para usar TODO o VG

```bash
lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv
df -h /
# Resultado esperado: / com ~220GB
```

### 2.3 Instalar Docker JÁ apontando para /nvme

```bash
# Instala Docker via repo oficial
curl -fsSL https://get.docker.com | sh

# IMEDIATAMENTE para o daemon antes que crie estado em /var/lib/docker
systemctl stop docker
systemctl stop docker.socket

# Configura data-root no NVMe + log rotation
mkdir -p /nvme/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "data-root": "/nvme/docker",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF

# Remove qualquer estado residual no SSD
rm -rf /var/lib/docker

systemctl start docker
docker info | grep -E 'Docker Root Dir|Storage Driver'
# DEVE mostrar: Docker Root Dir: /nvme/docker
```

### 2.4 Configurar swap no NVMe (opcional, recomendado)

```bash
# Swap de 8GB no NVMe (mais rápido que SSD SATA)
fallocate -l 8G /nvme/swapfile
chmod 600 /nvme/swapfile
mkswap /nvme/swapfile
swapon /nvme/swapfile
echo "/nvme/swapfile none swap sw 0 0" >> /etc/fstab
```

### 2.5 SSH hardening básico (manter porta 22300)

```bash
# Não mudar a porta — EVEO entrega na 22300
# Garantir fail2ban
apt install -y fail2ban
systemctl enable --now fail2ban
```

### 2.6 Timezone

```bash
timedatectl set-timezone America/Sao_Paulo
```

---

## 3. Validação pós-bootstrap

Antes de declarar o servidor pronto pra primeiro cliente:

```bash
# 1) Docker realmente no NVMe
test "$(docker info 2>/dev/null | awk '/Docker Root Dir/{print $NF}')" = "/nvme/docker" \
  && echo "OK Docker no NVMe" || echo "FALHA"

# 2) RAID OK
grep -q "\[UU\]" /proc/mdstat && echo "OK RAID UU" || echo "FALHA RAID"

# 3) / com folga
df -h / | awk 'NR==2{gsub("%","",$5); if ($5+0 < 50) print "OK / com "$4" livres"; else print "ATENCAO / em "$5"%"}'

# 4) NVMe vazio (esperado em servidor novo)
df -h /nvme

# 5) Teste de escrita Docker
docker run --rm hello-world | grep -q "Hello from Docker" && echo "OK Docker funcional" || echo "FALHA"
```

Os 5 checks devem passar. **Se algum falhar, NÃO INSTALAR cliente em produção.**

---

## 4. Padrão multi-tenant em servidor EVEO

Estrutura de diretórios padronizada (compatível com `multi-tenant-server` skill):

```
/opt/
├── tenants/
│   ├── nginx/                    docker-compose.yml (proxy reverso central)
│   ├── <cliente1>/               (ex: voxzap-locktec, planoclin)
│   │   ├── docker-compose.yml
│   │   ├── source/               código do app
│   │   └── .env
│   └── <cliente2>/
└── voxtel-io-hub/                stack compartilhada (LLM/ASR/TTS)
    └── docker-compose.prod.cpu.yml
```

Volumes Docker (gerenciados, ficam automaticamente em `/nvme/docker/volumes/`):
- `<cliente>_pgdata` → banco Postgres do cliente
- `<cliente>_asterisk_recordings` → gravações VoxCall
- `<cliente>_asterisk_configs` → configs Asterisk
- `asterisk-extdb_pgdata17` → banco externo Asterisk (CDR/queue_log)

**Não use bind mounts em `/opt/data/*` para coisas grandes.** Mantenha tudo em volumes Docker para que o NVMe seja usado automaticamente.

---

## 5. Procedimento de MIGRAÇÃO (servidor EVEO já instalado errado)

Se você herdou um servidor EVEO já em produção com Docker no SSD, siga este procedimento — **comprovado em produção no Locktec, abril/2026, com janela total de 2min28s e zero perda de dados**.

### 5.1 Pré-requisitos
- Janela de manutenção combinada com o cliente (~5–10 min, todas as stacks param juntas)
- Acesso `root` SSH
- Espaço livre em `/nvme` >= tamanho atual de `/var/lib/docker`

### 5.2 Fase 1 — Sem parada (limpeza + expansão LVM)

```bash
# Limpar lixo Docker (libera 5–25GB tipicamente)
docker builder prune -a -f
docker image prune -a -f

# Expandir / até esgotar VG
lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv
df -h /
```

### 5.3 Fase 2 — Janela de parada (move Docker para NVMe)

```bash
# T0 — parar todas as stacks graceful
for f in /opt/tenants/*/docker-compose.yml \
         /opt/tenants/*/*/docker-compose.yml \
         /opt/voxtel-io-hub/docker-compose.prod.cpu.yml; do
  [ -f "$f" ] && docker compose -f "$f" stop
done

# T1 — parar daemon
systemctl stop docker.socket
systemctl stop docker

# T2 — copiar para NVMe (rsync preserva owners, hardlinks, xattrs)
mkdir -p /nvme/docker
rsync -aHAX --numeric-ids --info=stats2 /var/lib/docker/ /nvme/docker/

# T3 — backup do antigo (NÃO apagar ainda — rollback de 48h)
mv /var/lib/docker /var/lib/docker.OLD

# T4 — apontar daemon
cp /etc/docker/daemon.json /etc/docker/daemon.json.OLD 2>/dev/null
cat > /etc/docker/daemon.json <<'EOF'
{
  "data-root": "/nvme/docker",
  "log-driver": "json-file",
  "log-opts": { "max-size": "50m", "max-file": "3" }
}
EOF

# T5 — subir
systemctl start docker
docker info | grep "Docker Root Dir"   # confirmar /nvme/docker

# T6 — voltar stacks (start preserva containers existentes)
for f in /opt/tenants/nginx/docker-compose.yml \
         /opt/tenants/*/docker-compose.yml \
         /opt/tenants/*/*/docker-compose.yml \
         /opt/voxtel-io-hub/docker-compose.prod.cpu.yml; do
  [ -f "$f" ] && docker compose -f "$f" start
done

# T7 — validar
docker ps --format 'table {{.Names}}\t{{.Status}}'
```

### 5.4 Validação pós-migração

```bash
# Volumes fisicamente no NVMe?
docker volume ls -q | head -5 | while read v; do
  docker volume inspect "$v" --format '{{.Mountpoint}}'
done
# Todos devem começar com /nvme/docker/volumes/

# Escrita ativa no NVMe?
find /nvme/docker -type f -mmin -5 | wc -l   # deve ser > 0

# .OLD congelado?
find /var/lib/docker.OLD -type f -newermt "$(date '+%Y-%m-%d %H:%M' -d '5 min ago')" | wc -l
# deve ser 0

# HTTP cada cliente
for port in 5001 5002 80 443; do
  curl -s -o /dev/null -w "porta $port: %{http_code} em %{time_total}s\n" http://127.0.0.1:$port/
done
```

### 5.5 Rollback (se algo der errado nas primeiras 48h)

```bash
# Para tudo
for f in /opt/tenants/*/docker-compose.yml \
         /opt/tenants/*/*/docker-compose.yml \
         /opt/voxtel-io-hub/docker-compose.prod.cpu.yml; do
  [ -f "$f" ] && docker compose -f "$f" stop
done
systemctl stop docker docker.socket

# Restaura
mv /etc/docker/daemon.json.OLD /etc/docker/daemon.json
mv /var/lib/docker /nvme/docker.NEW   # mantém o NVMe pra inspeção
mv /var/lib/docker.OLD /var/lib/docker

systemctl start docker
# Sobe stacks de novo
```

### 5.6 Cleanup após 48h estáveis
```bash
rm -rf /var/lib/docker.OLD
rm -f /etc/docker/daemon.json.OLD
df -h /
```

---

## 6. Manutenção contínua em servidores EVEO

### Monitoramento mensal
```bash
# Espaço Docker
docker system df

# RAID saudável
cat /proc/mdstat   # esperar [UU]

# Smart dos NVMes
smartctl -H /dev/nvme0n1
smartctl -H /dev/nvme1n1
smartctl -A /dev/nvme0n1 | grep -E 'Available Spare|Percentage Used|Power_On_Hours'
```

### Sinais de alerta
- `Available Spare` < 50% em qualquer NVMe → planejar troca com EVEO
- `[U_]` ou `[_U]` no `/proc/mdstat` → RAID degradado, abrir ticket URGENTE
- `/` > 70% → rodar prune; se persistir, investigar bind mounts em `/opt/data`

---

## 7. Servidores EVEO conhecidos

| Hostname | SSH | Clientes (slot) | Data setup | Observações |
|---|---|---|---|---|
| `eveo1.voxserver.app.br` | porta 22300 | Planoclin/VoxCall (slot 1) + voxzap-locktec (slot 2) + voxzap-voxtel (slot 3) + voxtel-cc (slot 4, site institucional) + Voxtel-IO Hub | 2026-04 | Migração SSD→NVMe feita 2026-04-22 22:46. 8 vCPU, 8GB RAM. Multi-tenant. voxzap-voxtel adicionado 2026-04-24 (8g/8cpu, dados em /nvme/tenants/voxzap-voxtel/, domínio voxtel.voxzap.cc). voxtel-cc adicionado 2026-04-25 (PHP estático + nginx, 256m/0.5cpu, domínio voxtel.cc, ver skill `site-voxtel`). |

Adicione novos servidores aqui conforme forem provisionados. **Sempre marcar se foi feito setup correto desde o início OU se foi migração corretiva.**

---

## 8. Lições aprendidas Locktec (referência histórica)

- **Tempo total da migração corretiva**: 2min28s de janela (T0 22:44:25 → T7 22:46:53)
- **Velocidade rsync no RAID NVMe**: 308 MB/s (5.4GB em 17s)
- **Tamanho real `/var/lib/docker` ativo**: 5.1GB (não confundir com `du` em overlay montado que mostra 18GB)
- **Dados validados pós-migração**: 20 tickets + 182 mensagens novos nas primeiras horas, zero perda
- **Janela de pico do cliente**: 10h–18h (evitar essa janela em migrações futuras de outros clientes)

## 9. Skills relacionadas

- `multi-tenant-server` — provisionamento de novos tenants em servidor compartilhado (assume Docker já configurado corretamente, ou seja, esta skill rodada antes)
- `dimencionamento_servidor_voxzap` — quantos operadores cabem por tier de hardware
- `deploy-assistant-vps` — deploy de cliente novo (assume servidor EVEO já com setup desta skill)
- `voxcall-native-asterisk-deploy` — Asterisk nativo no host (raro em EVEO, padrão é container)
- `remote-db-diagnostic` — diagnóstico de performance Postgres
