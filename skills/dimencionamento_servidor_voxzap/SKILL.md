---
name: dimencionamento_servidor_voxzap
description: Guia de dimensionamento de servidor para instalações VoxZap. Indica capacidade estimada de operadores simultâneos por tier de hardware (vCPU/RAM/disco) com base nos testes reais da Locktec (8 vCPU / 8 GB sustentando 32 operadores ativos) e extrapolação para tiers menores e maiores. Use ao orçar VPS para novo cliente, propor upgrade de servidor sob carga, ou validar se a infra suportará pico previsto.
---

# Dimensionamento de Servidor VoxZap

Guia para estimar a capacidade de um servidor VoxZap com base no perfil de hardware (vCPU / RAM / disco). Os números vêm de **medição real em produção** no cliente piloto (Locktec, eveo1.voxserver.app.br) + extrapolação calibrada para tiers menores/maiores.

## ⚠️ Honestidade dos números
- **Tier "Padrão" (8 vCPU / 8 GB)** está **medido em produção** com 32 operadores simultâneos ativos sustentados, ~6.5K mensagens/dia, 1 conexão WhatsApp Cloud API + 1 webchat.
- Tiers acima e abaixo são **extrapolações** baseadas no comportamento observado de CPU/RAM/I-O da Locktec, escalando linearmente onde faz sentido (operadores) e sublinear/conservador onde há gargalos previsíveis (DB/disco). Validar em campo antes de prometer SLA.

## Tabela de tiers recomendados

| Tier | vCPU | RAM | Disco | Operadores simult. | Volume sugerido | Cenário típico | Status |
|------|------|-----|-------|--------------------|-----------------|----------------|--------|
| **Mini** | 2 | 4 GB | 40 GB SSD | até **5** | até 1K msg/dia | POC, demo, single user | extrapolado ⚠️ |
| **Pequeno** | 2 | 8 GB | 80 GB SSD | até **10** | até 3K msg/dia | cliente pequeno (1 fila) | extrapolado ⚠️ |
| **Médio** | 4 | 8 GB | 100 GB SSD | até **20** | até 5K msg/dia | clínica/loja média | extrapolado ⚠️ |
| **Padrão** | 8 | 8 GB | 150 GB SSD | até **35** | até 8K msg/dia | call center médio | **medido (Locktec)** ✅ |
| **Grande** | 8 | 16 GB | 250 GB SSD | até **50** | até 15K msg/dia | call center médio com IA | extrapolado ⚠️ |
| **XGrande** | 16 | 32 GB | 500 GB SSD | até **100** | até 30K msg/dia | call center grande / multi-canal | extrapolado ⚠️ |
| **Enterprise** | 32 | 64 GB | 1 TB NVMe | até **200+** | 50K+ msg/dia | multi-tenant em servidor compartilhado (eveo1) | extrapolado ⚠️ |

> **Operador simultâneo** = operador logado, polling ativo (`/api/users/me/*`, `/api/notifications`, `/api/tickets/N/messages`), atendendo chats. Operador "logado mas inativo" pesa ~30% disso.

## Distribuição de recursos por container

Em todos os tiers, o servidor roda **3 containers** (app + db + nginx). A distribuição padrão é:

```yaml
# docker-compose.yml — exemplo do tier Padrão (8 vCPU / 8 GB)
services:
  app:
    deploy:
      resources:
        limits:
          cpus: "8"        # pode pedir todo o host (Node single-thread + workers)
          memory: 6g
    environment:
      NODE_OPTIONS: "--max-old-space-size=4096"
  db:
    deploy:
      resources:
        limits:
          cpus: "4"
          memory: 2g
    shm_size: 256m
  nginx:
    deploy:
      resources:
        limits:
          cpus: "1"
          memory: 256m
```

### Regra geral de divisão por tier

| Tier | app cpus | app memory | NODE_OPTIONS max-old-space | db cpus | db memory | db shm_size |
|------|----------|------------|---------------------------|---------|-----------|-------------|
| Mini (2/4) | 2 | 2g | 1536 | 1 | 1g | 128m |
| Pequeno (2/8) | 2 | 4g | 3072 | 1 | 2g | 256m |
| Médio (4/8) | 4 | 4g | 3072 | 2 | 2g | 256m |
| Padrão (8/8) | 8 | 6g | 4096 | 4 | 2g | 256m |
| Grande (8/16) | 8 | 10g | 7168 | 4 | 4g | 512m |
| XGrande (16/32) | 12 | 20g | 14336 | 4 | 8g | 1g |
| Enterprise (32/64) | 24 | 40g | 28672 | 8 | 16g | 2g |

> ⚠️ **Nunca limitar app a menos de 2 vCPU**. O bug clássico (Locktec pré-tuning) era load average 7+ com 98% das CPUs ociosas porque o Docker barrava o app antes dele pedir CPU pro host. Sintoma: cliente reclama de lentidão, `htop` mostra host calmo, `docker stats` mostra app no teto de CPU.

## Fatores que mudam o dimensionamento (cuidado!)

Os números acima assumem perfil "atendimento padrão". Aplicar **multiplicador** se o cliente tem:

| Fator | Impacto | Multiplicador na capacidade |
|-------|---------|----------------------------|
| **AI Agent ativo** (LLM em todo ticket) | RAM + CPU + latência de API externa | × 0.6 (preferir tier acima) |
| **Múltiplas conexões WhatsApp** (>3) | Polling/webhooks paralelos | × 0.8 por canal extra |
| **Campanhas ativas em paralelo** | Worker com lote de envios | × 0.7 durante a campanha |
| **Mídia pesada** (áudio/vídeo dominante) | Disco I/O + storage | dobrar disco, ↑I/O |
| **Histórico ZPro grande migrado** (>1M msgs) | DB ↑, queries de relatório lentas | × 0.85, considerar tier db acima |
| **Relatórios de BI rodando em horário comercial** | Lock no DB | × 0.7, agendar fora do pico |
| **Webchat público alto tráfego** | Conexões WS extras | × 0.85 |

Exemplo: cliente com 30 operadores + AI Agent + 4 conexões WhatsApp → 30 / (0.6 × 0.8) ≈ 62 operadores "equivalentes" → tier **Grande** ou **XGrande**, não Padrão.

## Disco — calcular separado

CPU/RAM dimensionam atendimento simultâneo; disco dimensiona histórico acumulado.

| Item | Consumo típico |
|------|----------------|
| DB (PostgreSQL) por 1M de mensagens | ~700 MB |
| DB por 100K tickets | ~50 MB |
| Mídia recebida (áudio/imagem/doc) | ~250 KB/mensagem média |
| Logs Docker (com P10 patch aplicado) | ~50 MB/dia/tenant |
| Logs Docker (SEM P10) | até 30 GB/dia/tenant ⚠️ |
| Backups locais (recomendado 3 dias) | tamanho_db × 3 |

**Regra prática**: `disco_util = (volume_db_atual + projecao_12_meses) × 1.5 + 20 GB margem`.

Para Locktec: 1.275 GB DB + 13 GB mídia atual + crescimento ~1 GB/mês × 12 = ~26 GB → **150 GB folga confortável** (3-4 anos sem precisar redimensionar).

## Sinais de servidor saturado (subir tier)

| Métrica | Limite saudável | Como medir |
|---------|-----------------|------------|
| Load average 5min | < (vCPU × 0.7) | `uptime` no host |
| RAM disponível | > 15% | `free -h` |
| Disco livre | > 30% | `df -h` |
| Latência média `/api/tickets` | < 300ms | log do app pós-P10 |
| Conexões PG ativas | < `max_connections × 0.5` | `SELECT count(*) FROM pg_stat_activity` |
| `docker stats` CPU% do app | < 80% sustentado | `docker stats` |
| Operadores reclamando "lentidão" | 0 | suporte do cliente |

Se 2+ métricas estouram em horário de pico por 3+ dias seguidos, **subir tier** (com janela de manutenção).

## Sinais de servidor superdimensionado (descer tier ou consolidar)

- Load average 5min < (vCPU × 0.15) por semanas
- RAM utilizada < 30% no pico
- CPU app < 25% sustentado no pico
- Disco com >70% livre e crescimento <1%/mês

Nesse caso, considerar **consolidar em servidor multi-tenant compartilhado** (ver skill `multi-tenant-server`) — eveo1 (32/64) suporta 4-6 clientes pequeno/médio sem perda de SLA.

## Premissas que validam estes números

Para a tabela acima ser confiável, o cliente precisa estar com:

- ✅ **P10 aplicado** (logger do Express enxuto) — sem isso, disco enche em 3 dias
- ✅ **Logrotate Docker** configurado (paliativo se P10 ausente)
- ✅ **Postgres com `shared_buffers` ajustado** (~25% da RAM do container db)
- ✅ **Limites Docker NÃO restritos abaixo do recomendado** acima
- ✅ **Timezone correto** no host e nos containers (logs e relatórios)
- ✅ **Backup diário automatizado** rodando fora do pico (3-5 AM)

Sem essas premissas, **degradar 1 tier** na estimativa.

## Checklist rápido para orçar novo cliente

1. Quantos operadores simultâneos no pico? → coluna "Operadores simult."
2. Volume estimado de mensagens/dia? → coluna "Volume sugerido"
3. Vai usar AI Agent? → aplicar multiplicador × 0.6
4. Quantas conexões WhatsApp? → multiplicador por canal extra
5. Histórico ZPro a migrar? → calcular disco com regra prática + multiplicador 0.85
6. Pegar o **maior tier** entre todas as restrições.
7. Adicionar **20% de folga** acima do tier resultante (cliente vai crescer).
8. Validar com cliente: SLA, janela de manutenção aceita, orçamento.

## VoxCALL — adaptação para call center com Asterisk

VoxZap usa 3 containers (app + db + nginx). **VoxCALL adiciona 2 containers** que VoxZap não tem:
- **asterisk** (PBX, `network_mode: host`, SIP/RTP/AMI/ARI) — CPU-bound em pico de chamadas, RTP é I/O-sensível
- **asterisk-extdb** (PostgreSQL dedicado de telefonia: `cdr`, `queue_log`, `sip_conf`, `queue_table`, etc.) — escrita constante, queries de relatório pesadas

A regra é: **manter o sizing do app/db igual ao VoxZap do mesmo tier**, e **somar** o orçamento de Asterisk + Postgres-telefonia.

### Distribuição recomendada (VoxCALL multi-tenant em servidor compartilhado)

Tier "Padrão" VoxCALL = mesma capacidade que Padrão VoxZap (35 operadores), porém com Asterisk + extdb por tenant:

| Container | cpus | memory | Observações |
|-----------|------|--------|-------------|
| `{tenant}-app` (Node) | 6 | 6g | `NODE_OPTIONS=--max-old-space-size=4096`, `UV_THREADPOOL_SIZE=16` |
| `{tenant}-asterisk` | 4 | 4g | `network_mode: host`, `oom_score_adj: -500` |
| `{tenant}-db` (Drizzle/VoxCALL) | 1 | 1g | tabelas internas (users, extensions, dialplans...) |
| `{tenant}-asterisk-extdb` (PG telefonia) | 4 | 4g | `shm_size: 1gb`, `oom_score_adj: -800` |
| **Total por tenant** | **~15 vCPU** | **~15 GB** | em servidor 80/64 cabem ~4 tenants Padrão folgados |

### Postgres telefonia — params via `command:` (boot, NÃO online)

⚠️ Os params abaixo são **fixados via flag `-c` no docker-compose** e exigem recriação do container. `ALTER SYSTEM` + `pg_reload_conf()` **não tem efeito** quando o param está na linha de comando do postmaster (`pg_settings.source = 'command line'`).

```yaml
# /opt/tenants/{tenant}/asterisk-extdb/docker-compose.yml — tier Padrão
asterisk-extdb:
  image: postgres:17-alpine
  command: >
    -c shared_buffers=1GB              # 25% da memory do container
    -c effective_cache_size=3GB        # 75% da memory
    -c work_mem=32MB                   # ordenação por conexão
    -c maintenance_work_mem=256MB      # VACUUM/CREATE INDEX
    -c wal_buffers=16MB
    -c max_parallel_workers_per_gather=2
    -c random_page_cost=1.1            # SSD
    -c max_connections=200
  shm_size: "1gb"
  mem_limit: 4g
  cpus: 4.0
  oom_score_adj: -800
```

⚠️ **Cuidado com `work_mem × max_connections`**: pior caso teórico = `200 × 32MB = 6.4GB` em sorts/hash simultâneos, o que estoura `mem_limit: 4g` e dispara OOM-kill do extdb. Na prática o Asterisk usa <30 conexões e poucas fazem sort ao mesmo tempo, mas se for ativar relatório BI pesado em horário comercial, **reduzir `work_mem` para 16MB** ou **subir `mem_limit` para 6g**. Monitorar `pg_stat_activity` (`state='active'` + `query LIKE '%ORDER BY%'`) e `dmesg | grep -i 'killed process'` na primeira semana.

### Tabela de tiers VoxCALL (multi-tenant em eveo1 ou single-tenant)

| Tier | Operadores | App (cpu/mem) | Asterisk (cpu/mem) | extdb (cpu/mem/shm/shared_buf) | db (cpu/mem) | Soma limites (cpu/mem) | Host mín. single-tenant | Host com overcommit (multi-tenant) |
|------|-----------|---------------|--------------------|--------------------------------|--------------|------------------------|-------------------------|------------------------------------|
| Pequeno | até 10 | 2 / 2g | 2 / 2g | 2 / 2g / 512m / 512MB | 1 / 512m | 7 / 6.5g | **8 vCPU / 8 GB** | 4 vCPU / 6 GB (overcommit ~1.7×) |
| Médio | até 20 | 4 / 4g | 3 / 3g | 3 / 3g / 1g / 768MB | 1 / 1g | 11 / 11g | **12 vCPU / 12 GB** | 6 vCPU / 10 GB (overcommit ~1.8×) |
| **Padrão** | **até 35** | **6 / 6g** | **4 / 4g** | **4 / 4g / 1g / 1GB** | **1 / 1g** | **15 / 15g** | **16 vCPU / 16 GB** | **8 vCPU / 14 GB** (overcommit ~1.9×) ✅ medido (PlanoClin slot em eveo1 80/64) |
| Grande | até 60 | 8 / 10g | 6 / 6g | 6 / 6g / 2g / 2GB | 2 / 2g | 22 / 24g | **24 vCPU / 32 GB** | 12 vCPU / 28 GB (overcommit ~1.8×) |
| XGrande | até 100 | 12 / 16g | 8 / 8g | 8 / 12g / 4g / 4GB | 4 / 4g | 32 / 40g | **32 vCPU / 48 GB** | 20 vCPU / 44 GB (overcommit ~1.6×) |

> **CPU limits são "burst/teto", não reserva**. Docker `cpus:` é hard cap (cgroup CPU quota). RAM `mem_limit:` é hard cap também (OOM-kill ao estourar). A coluna **Host mín. single-tenant** soma os tetos exatamente — se o cliente realmente saturar todos os containers ao mesmo tempo, é o que precisa do host. A coluna **overcommit (multi-tenant)** assume que app + extdb não picam juntos (na prática Asterisk pica em chamadas, app pica em login/dashboard, extdb pica em relatório — não simultâneos). É o modelo da eveo1 (80/64 com 4-5 tenants Padrão coexistindo). Se o cliente é single-tenant **e** vai rodar relatório BI no horário de pico, **provisionar pelo Host mín. single-tenant**, não pelo overcommit.

> **Caso real medido — PlanoClin (clin.voxcall.cc, slot em eveo1 80/64):** com tier Padrão acima sustenta operação atual sem OOM, RTP estável, queries CDR < 500ms. Antes do tuning estava com app=1g/1.5cpu (130MB usados, mas margem zero pra picos), extdb sem limite (336MB livres + shared_buffers=512MB era apertado para o volume de queue_log).

### Diferenças vs VoxZap a lembrar sempre

- **Asterisk não pode morrer**: `oom_score_adj: -500`, `restart: unless-stopped` obrigatório. Recriação derruba chamadas em curso (~10-20s) — **sempre** confirmar janela de manutenção com o cliente antes de `docker compose up -d` no stack do tenant.
- **extdb separado**: nunca compartilhar a instância PostgreSQL do app (Drizzle) com a do Asterisk — dois perfis de carga muito diferentes (OLTP enxuto vs escrita massiva de eventos + queries de relatório).
- **Compose separado para extdb**: `/opt/tenants/{tenant}/asterisk-extdb/docker-compose.yml` é independente do compose principal do tenant. Permite reiniciar só o PG telefonia sem mexer no Asterisk/app.
- **WSS/ARI**: a porta ARI (`8088 + slot`) serve tanto API REST do ARI quanto WebSocket WebRTC `/ws`. TLS terminado no Nginx-tenants centralizado.
- **Multiplicador de campanhas em VoxCALL**: discadores ativos consomem CPU do Asterisk linearmente (cada chamada = 1 canal). Aplicar × 0.7 no count de operadores se o tenant tem dialer rodando full-time.

### Procedimento de up-sizing (sem perder dados)

1. Backup `.env` + ambos composes + `pg_dump` do extdb
2. ALTER SYSTEM dos params USERSET-context (work_mem, etc.) — vale para sessões novas, **não** vale para params fixados em `command:`
3. Editar `.env` (limites de mem/cpu) e `asterisk-extdb/docker-compose.yml` (`-c` flags + `mem_limit` + `shm_size`)
4. **Confirmar janela com o cliente** (~30s de impacto)
5. `docker compose up -d` em `/opt/tenants/{tenant}/asterisk-extdb/` → aguardar `healthy`
6. `docker compose up -d` em `/opt/tenants/{tenant}/` → aguarda app responder `serving on port 5000`
7. Validar: `docker stats`, `pg_settings`, heap do Node (`v8.getHeapStatistics().heap_size_limit`), `curl https://dominio/`

## Referências cruzadas

- `.agents/skills/multi-tenant-server/SKILL.md` — quando consolidar múltiplos clientes em um servidor (VoxCALL e VoxZap)
- `.agents/skills/migracao_zpro_voxzap/SKILL.md` — performance tuning pós-cutover (Fase 5)
- `.agents/skills/locktec-migration/SKILL.md` — caso real medido VoxZap (cliente piloto Locktec)
- `.agents/skills/deploy-assistant-vps/SKILL.md` — provisionamento de VPS novo
- `.agents/skills/voxcall-native-asterisk-deploy/SKILL.md` — deploy VoxCALL com Asterisk nativo (cenário diferente do multi-tenant)
