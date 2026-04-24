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

## Referências cruzadas

- `.agents/skills/multi-tenant-server/SKILL.md` — quando consolidar múltiplos clientes em um servidor
- `.agents/skills/migracao_zpro_voxzap/SKILL.md` — performance tuning pós-cutover (Fase 5)
- `.agents/skills/locktec-migration/SKILL.md` — caso real medido (cliente piloto)
- `.agents/skills/deploy-assistant-vps/SKILL.md` — provisionamento de VPS novo
