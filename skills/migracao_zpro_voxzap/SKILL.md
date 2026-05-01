---
name: migracao_zpro_voxzap
description: Playbook completo e generalizado para migração de clientes ZPro (Sequelize/PostgreSQL) para VoxZap (Prisma/PostgreSQL). Consolida lições da virada Locktec (2026-04-19), estabilização pós-cutover e janela de performance tuning. Use quando for planejar ou executar migração ZPro→VoxZap em qualquer cliente novo. Para a execução específica do Locktec, ver skill `locktec-migration`.
---

# Migração ZPro → VoxZap — Playbook Generalizado

Skill consolidado a partir da migração Locktec (cliente piloto, 2026-04-19) e da janela de estabilização que se seguiu. Trata os pontos que **TODA** migração ZPro→VoxZap precisa cobrir, independente do cliente. Para parametrizações específicas do Locktec, ver `.agents/skills/locktec-migration/SKILL.md`.

## Quando usar
- Planejamento de migração de novo cliente saindo do ZPro
- Execução real da virada (clonagem DB + mídias + validação + cutover)
- Onboarding de novo tenant que já tem histórico em ZPro
- Diagnóstico de inconsistências em tenants já migrados

## Princípios fundamentais
1. **Nunca quebrar o sistema**, **nunca perder histórico**, **audit trail completo**, **nada deletado automaticamente** sem backup metadata.
2. ZPro origem é **somente leitura** durante toda a migração.
3. Toda transformação destrutiva deve ter backup (tabela `_collision_pN`, `.bak.timestamp`, ou tag Docker `pre-pX`).
4. Defaults divergentes entre ZPro e VoxZap devem ser **explicitamente** ajustados em `migrate.py`, não herdados.

## Pré-requisitos genéricos
| Item | Valor |
|------|-------|
| Acesso SSH a ambos os VPS | obrigatório |
| `sshpass`, `rsync`, `psql`, `pg_dump` | disponíveis nos VPS |
| Espaço em disco no destino | volume_dados × 1.5 + margem 20 GB |
| Janela de manutenção | mínimo 2h (1h cutover + 1h validação) |
| Backup do banco destino antes do TRUNCATE | obrigatório |
| Tag Docker `pre-cutover` da imagem app destino | obrigatório (rollback em <1min) |

## Visão geral das fases

| Fase | Objetivo | Tempo típico | Risco |
|------|----------|--------------|-------|
| F1 — Migração DB | Clonar dados (Tickets/Messages/Contacts/Whatsapps) ZPro→VoxZap, remap tenantId | 20-60 min | médio |
| F2 — Migração Mídias | rsync VPS→VPS de `public/<tenantOrigem>/` para `uploads/` | 10-30 min | baixo |
| F3 — Validação | Contagens, tickets abertos, mensagens recentes, login operadores | 30 min | — |
| F4 — Normalização pós-migração | Limpeza de colisões, normalização de números (ver §Pitfalls) | 1-4h (offline ok) | médio |
| F5 — Estabilização pós-cutover | Aplicar P10/P11/etc. (ver §Pós-cutover) | 1-2h (janela noturna) | baixo |

## Dados a PRESERVAR no VoxZap destino (NÃO truncar)
- `Tenants(id=destino)` — sempre. Sem ele, FK das `Queues` quebra.
- Tokens Meta Cloud API: `Whatsapps.tokenAPI`, `wabaId`, `bmToken`, `fbPageId` — usar `ai-preserve.sh` UPSERT dinâmico.
- Configurações de IA: `AiAgents`, `AiAgentRoutes`, `AiAgentDepartments`, `AiAgentFiles`, `AiAgentChunks`, `AiAgentLogs`.
- `Queues`, `QueueScheduleExceptions`.
- `Settings` previamente customizadas (ver pitfall §6 sobre defaults divergentes).

## Lições críticas consolidadas (numeração reservada para evolução)

### L1 — `Tenants` precisa ser repopulado antes de `ai-preserve.sh restore`
`TRUNCATE … CASCADE` derruba `Tenants` junto. `migrate.py` não inclui `Tenants` em `TABLES`. Sem ele, restore das `Queues` falha com FK violation.
**Workaround**: script `copy_tenant.py` que copia `Tenants(id=origem)` do ZPro com remap `id→destino` antes do restore.

### L2 — Remap `tenantId` em TODAS as tabelas auxiliares
Tabelas como `TicketEvaluations`, `Settings`, `UsersQueues` carregam `tenantId` literal do ZPro (geralmente `2`). Sem remap, `validate.sh` filtra por `tenantId=destino` (geralmente `1`) e mostra 0 rows.
**Padrão**: `INSERT … (cols, "tenantId") SELECT cols, <DEST_TENANT> FROM stage`.

### L3 — `UsersQueues` órfãs derrubam `GET /api/queues` (HTTP 500)
ZPro pode ter `UsersQueues` apontando para users soft-deleted/de outros tenants. Prisma `include: { Users }` devolve `null`, `.map(uq => uq.Users.id)` crasha. Sintoma: UI "Filas de Atendimento" exibe vazio mesmo com filas no banco.
**Cleanup obrigatório pós-migração**:
```sql
DELETE FROM "UsersQueues" uq USING (
  SELECT uq2."userId", uq2."queueId" FROM "UsersQueues" uq2
  LEFT JOIN "Users" u ON u.id=uq2."userId" WHERE u.id IS NULL
) o WHERE uq."userId"=o."userId" AND uq."queueId"=o."queueId";
```
Verificação: `SELECT count(*) FROM "UsersQueues" uq LEFT JOIN "Users" u ON u.id=uq."userId" WHERE u.id IS NULL` (deve ser 0).

### L4 — Webhook Meta NÃO precisa ser reapontado
Desde que o cliente mantenha o mesmo domínio (`<cliente>.voxzap.cc`). Status 8/8 chega em produção sem nenhuma alteração no Meta Business Manager. Removido do checklist pós-cutover.

### L5 — Re-engagement message (Meta error 131047) — janela 24h indexada por formato do número
Meta indexa janela 24h pelo **formato exato**, não pelo número canônico. Inbound chega com 13 dígitos (`558598XXXXXXXX`), outbound com 12 dígitos (`5585XXXXXXXX`) é tratado como recipient diferente.
**Patch upstream em `server/services/whatsapp.service.ts`**: incluir `errorCode === 131047` e match `"re-engagement"` no `isRecipientError`, disparando retry automático com `getAlternatePhoneNumber()` (`server/lib/phone-utils.ts`).
**Não migrar contatos em massa** — o retry no código resolve caso por caso.

### L6 — Defaults de `Settings` divergem entre ZPro e VoxZap
Ex.: ZPro guarda `signed='disabled'` por padrão; VoxZap espera `signed='enabled'` (operadores assinam mensagens com nome). Após migração, operadores somem da assinatura.
**Padrão de correção**: função `fix_inherited_defaults()` em `migrate.py` (idempotente, roda após cópia de Settings) que sobrescreve chaves divergentes para o default VoxZap. Chaves conhecidas mortas no VoxZap (ex.: `notificationSilenced`) podem ser ignoradas.

### L7 — `GlobalNotificationHandler` faz broadcast pra todos os operadores
Componente `client/src/components/global-notification-handler.tsx` ouve `onNewMessage`/`onInternalNewMessage`/`onParticipantAdded`/`onParticipantRemoved` e dispara `toast()` + `playBeep()` em todo operador logado, sem checar dono. Resultado em produção: ruído altíssimo.
**✅ RESOLVIDO no upstream em 2026-04-21** (commit upstream, marcador `NOTIF_GRANULAR_ROUTING`):
- **Backend** (`server/websocket/socket.ts`): connect handler joina `admins:${tenantId}` para `admin`/`superadmin`/`supervisor`. `broadcastNewMessage` virou `async`, faz lookup de `Tickets.userId/queueId` (PK index, custo desprezível) e emite `NEW_MESSAGE` apenas para `user:${ownerId}` (se atribuído) OU `queue:${queueId}` (se pendente) + sempre `admins:${tenantId}` + `ticket:${ticketId}`. Payload ganha `ticketUserId`/`ticketQueueId` para filtro frontend. Não emite mais para `tenant:${tenantId}` (corta os N×operadores broadcasts de toast/beep).
- **Frontend** (`client/src/components/global-notification-handler.tsx`): `handleNewMessage` filtra por `data.ticketUserId === user.id` ou `isAdmin` antes de tocar toast/beep. Tickets pendentes (sem dono) ficam silenciosos exceto para perfis elevados.
- **Preservado intencionalmente**: `broadcastTicketUpdate` continua tenant-wide (driva refresh de lista, sem toast/beep — sem regressão UX). `broadcastNewTicket` continua roteando para `queue:` (badge "Fila N" continua aparecendo pra todos da fila). Eventos coletivos (`USER_STATUS`, `CONNECTION_UPDATE`, `META_ACCOUNT_ALERT`, `CAMPAIGN_PROGRESS`) mantidos tenant-wide por natureza.

### L8 — Nova Conversa bloqueada por ticket aberto em outro canal
`POST /api/tickets/new-conversation` em `server/routes.ts` consultava `tickets.findFirst({ contactId, tenantId, status:in[open,pending] })` **sem filtrar por `whatsappId`**. Em ambientes multi-canal por contato (ex.: cobrança ativa + atendimento padrão), cliente impede abrir nova conversa em canal diferente.
**Patch**: adicionar `whatsappId: connection.id` ao `where`.
**Padrão de revisão geral**: VoxZap mantém UM ticket por (contato × canal × status_aberto). Toda consulta `findFirst({ contactId, status:open|pending })` que NÃO filtre por canal é suspeita.

### L9 — Normalização de Contacts (regex sem âncora gera corrupção)
Bug histórico do `phone-utils.ts`: regex sem âncora deixava lixo concatenado em `numberOriginal`/`number`, permitindo dois contatos diferentes colapsarem na normalização.
**Procedimento de correção pós-migração**:
1. Backfill `numberOriginal` (audit trail) antes de qualquer normalização.
2. Detectar colisões (mesmo número canônico, contactId diferente).
3. Mover colisões para tabela `Contacts_collision_pN` para revisão humana — **nunca merge automático**.
4. Truncar `ContactUpserts`/`MessageUpserts` (filas de processamento corrompidas) com backup metadata, NÃO `Contacts`/`Messages`.
**Validação**: `SELECT count(*) FROM Contacts WHERE number != phone_canonical(numberOriginal)` deve ser 0 após.

## Fase 5 — Estabilização pós-cutover (janela noturna obrigatória)

Aplicar nos primeiros 2-3 dias após go-live, em janela de baixo atendimento.

### P10 — Logger do Express verboso (já corrigido upstream em 2026-04-21)
- **Problema**: middleware `app.use((req,res,next)=>...)` em `server/index.ts` logava body completo de TODA resposta JSON, incluindo 304s. Polling de operadores (`/api/users/me/*`, `/api/notifications`, `/api/tickets/N/messages`) gerava 28 GB/dia.
- **Status**: ✅ **Patch já aplicado no upstream `server/index.ts`** (commit pós-Locktec). Toda nova instalação já vem com:
  - Skip de body em status 304
  - Skip de logging em prefixes `/api/users/me/`, `/api/notifications`, `/api/tickets/has-pending`, `/api/settings/get/`
  - Skip de patterns `^/api/tickets/\d+/messages$` e `^/api/tickets/\d+$`
  - Truncate de body a 200 chars com indicador `[+NB]`
- **Para tenants migrados ANTES dessa data**: aplicar patch idempotente em `<tenant_root>/source/server/index.ts` + rebuild Docker (`docker compose build app && docker compose up -d app`). Tag rollback antes: `docker tag <app>:latest <app>:pre-p10-<timestamp>`. Build ~24s, downtime ~12s. Validação: linha média deve cair de ~3KB para ~165 bytes.

### P11 — psqlODBC antigo no container Asterisk (planoclin/cliente-específico)
- **Problema**: driver psqlODBC do container Asterisk consulta `pg_class.relhasoids` (coluna **removida no PostgreSQL 12**). Cada conexão dispara N introspections, todas falham, cada erro loga ~1 KB de SQL (linha STATEMENT verbose). 17 GB/dia no extdb.
- **Mitigação rápida** (suprime apenas o STATEMENT, mantém ERROR para diagnóstico):
  ```bash
  # ATENÇÃO: superuser pode ser 'asterisk' ou 'postgres' dependendo do container.
  # Validar com: docker exec <ext-db> psql -U postgres -c "\du" (ou tentar ambos)
  docker exec <ext-db> psql -U <superuser> -d <db> -c "ALTER SYSTEM SET log_min_error_statement = 'panic'"
  docker exec <ext-db> psql -U <superuser> -d <db> -c "SELECT pg_reload_conf()"
  ```
  ⚠️ Multi-statement em uma única `-c` falha com `ALTER SYSTEM cannot run inside a transaction block`. **Sempre separar em chamadas independentes**.
  Resultado típico: queda de ~93% no volume de bytes/erro (de ~1.1 KB para ~80 B/linha).
- **Solução root cause** (deferir para janela coordenada): atualizar pacote `odbc-postgresql`/`psqlODBC` >= v13 dentro do container Asterisk do cliente. Requer rebuild da imagem `voxcall-asterisk:latest`. Coordenar com **agente VoxCall**.

### Performance tuning padrão (servidor compartilhado eveo1: 80 CPU / 64 GB / NVMe)
Limites Docker default são restritivos para o host real. Subir para perfil "Heavy" no `docker-compose.yml` do tenant:
```yaml
services:
  app:
    deploy:
      resources:
        limits:
          cpus: "8"
          memory: 8g
    environment:
      NODE_OPTIONS: "--max-old-space-size=6144"
  db:
    deploy:
      resources:
        limits:
          cpus: "4"
          memory: 4g
```
Sintoma típico antes do tuning: load average 7+ com 98% das CPUs ociosas — Docker barra o app antes de pedir CPU pro host.

### Logrotate dos containers (paliativo enquanto P10 não está aplicado)
`/etc/logrotate.d/docker-containers`:
```
/var/lib/docker/containers/*/*-json.log {
  hourly
  size 100M
  rotate 3
  compress
  copytruncate
  missingok
  notifempty
}
```

## Pitfalls comuns

| Pitfall | Sintoma | Prevenção |
|---------|---------|-----------|
| ALTER SYSTEM dentro de transação implícita | `cannot run inside a transaction block` | Sempre `psql -c` separado por statement |
| Source NÃO é bind-mount no compose | Edits em `source/` não refletem no container | Rebuild Docker (`compose build && up -d`) ou `docker cp` + restart |
| Deploy assume `npm run dev`/tsx direto | Container produção roda `node dist/index.cjs` | Sempre rebuildar para alterações em `server/*.ts` |
| `Settings.signed` herdado do ZPro | Operadores somem da assinatura | `fix_inherited_defaults()` em `migrate.py` |
| Regex `phone-utils` sem âncora `^...$` | Contatos colapsam ou ganham lixo concatenado | Auditar regex + popular `numberOriginal` antes de qualquer normalização |
| `tickets.findFirst` sem `whatsappId` | Nova Conversa devolve ticket de outro canal | Toda query por contato + status precisa filtrar canal |
| `UsersQueues` órfãs | `GET /api/queues` HTTP 500 | DELETE de órfãs no fim de `migrate.py` |
| Seed inicial cria `UserWhatsapps` em massa para todos os operadores em todos os canais | Operador vê histórico cross-canal de outros canais (sensação de "vazamento" entre filas) ao abrir tickets do mesmo contato | Após cutover, auditar `UserWhatsapps` × `UsersQueues` por operador. Vínculo de canal **não tem UI no projeto** — é só SQL. Ver seção "Permissão de Canal vs Permissão de Fila" em `whatsapp-messaging-expert`. Flag opcional `restrictHistoryToOperatorChannels` (Settings) restringe histórico cross-ticket sem precisar editar vínculos. |

## Checklist rápido pós-cutover

- [ ] `docker tag <app>:latest <app>:pre-cutover-<timestamp>` (rollback rápido)
- [ ] `validate.sh` passa: contagens batem, login admin/operador funciona
- [ ] WhatsApp recebendo mensagens (8/8 status na Meta)
- [ ] `GET /api/queues` retorna 200 (cleanup `UsersQueues` órfãs)
- [ ] `/api/settings/notificationsEnabled` configurado conforme cliente
- [ ] Logger Express já patchado (P10) — `ls -la <tenant>/source/server/index.ts.bak*` ou versão upstream pós-2026-04-21
- [ ] Mitigação P11 aplicada se container Asterisk usar psqlODBC v12-
- [ ] Logrotate configurado (paliativo se P10 não estiver)
- [ ] `docker stats` mostra app respeitando limites Heavy
- [ ] Disco destino tem 50%+ livre

## Rollback de emergência

1. **Code-level**: `docker tag <app>:pre-cutover-<timestamp> <app>:latest && docker compose up -d app` (downtime ~12s)
2. **DB-level** (catastrófico): `pg_restore` do dump pré-cutover. **Tem que ter o dump** — confirmar antes de TRUNCATE.
3. **Whatsapp/webhook**: nenhuma ação se domínio inalterado (L4); se trocou, reapontar webhook na Meta.

## Referências cruzadas

- `.agents/skills/locktec-migration/SKILL.md` — execução real Locktec (números, scripts, paths)
- `.agents/skills/communication-channels-expert/SKILL.md` — arquitetura de canais e tabela `Whatsapps`
- `.agents/skills/whatsapp-messaging-expert/SKILL.md` — Meta Cloud API, janela 24h, error 131047
- `.agents/skills/multi-tenant-server/SKILL.md` — provisionamento de novo tenant em servidor compartilhado
- `.agents/skills/external-db-integration/SKILL.md` — integração com banco do CRM/ERP do cliente migrado
