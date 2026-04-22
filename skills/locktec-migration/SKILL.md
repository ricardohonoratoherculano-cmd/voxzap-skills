---
name: locktec-migration
description: Migração completa do cliente Locktec (ZPro) para VoxZap. Inclui clonagem do banco PostgreSQL (89 tabelas, 1.2M+ mensagens, 183K tickets, 26K contatos), transferência de 13GB de mídias (57K arquivos), mapeamento de schemas ZPro→VoxZap, ajuste de tenantId, mediaUrl, sequences, e validação end-to-end. Use quando for executar a migração real do cliente Locktec para produção VoxZap.
---

# Migração Locktec (ZPro) → VoxZap — Skill Completo

Skill para execução da migração completa do cliente Locktec do sistema ZPro para o VoxZap.
Já foi executado com sucesso na homologação (Tasks #55 e #56) e na **virada definitiva em 2026-04-19**. Este documento serve como guia definitivo para a migração real em produção.

## ⚠️ Lições da Virada Definitiva (2026-04-19)

Durante a virada definitiva foram descobertos 3 itens que o runbook original não cobria. Tudo já está consertado nos scripts mas precisa estar visível aqui:

1. **`Tenants` NÃO está em `migrate.py` TABLES** — `TRUNCATE … CASCADE` derruba `Tenants` junto, mas migrate.py não a re-importa. Sem `Tenants(id=1)`, o restore das `Queues` falha com FK violation. **Workaround**: rodar `/tmp/copy_tenant.py` (gerado on-the-fly) que copia o tenant id=2 do ZPro com remap id→1 antes do `ai-preserve.sh restore`.

2. **`te_fix.sh` v1 NÃO remapeava `tenantId`** — importava `TicketEvaluations` com `tenantId=2` literal do ZPro. `validate.sh` filtra por `tenantId=1` e mostrava 0. **Corrigido na v2**: `INSERT … (cols, "tenantId") SELECT cols, 1 FROM te_stage`.

3. **Origem ZPro acessível só por IP** — domínio `voxzaplocktec.voxserver.app.br` foi migrado pelo cliente; usar `217.216.90.134` direto. Já refletido em `migrate.py`, `te_fix.sh`, `validate.sh`.

4. **`UsersQueues` órfãs derrubam `GET /api/queues` (HTTP 500)** — o ZPro pode ter linhas em `UsersQueues` apontando para users soft-deleted/de outros tenants que `migrate.py` não importa. O Prisma faz `include: { Users }` e devolve `null`, e o `.map(uq => uq.Users.id)` no `queue.repository.ts` crasha com "Cannot read properties of null". Sintoma na UI: página "Filas de Atendimento" exibe "Nenhuma fila encontrada" mesmo com 28 filas no banco. **Cleanup obrigatório pós-migração**:
   ```sql
   DELETE FROM "UsersQueues" uq USING (
     SELECT uq2."userId", uq2."queueId" FROM "UsersQueues" uq2
     LEFT JOIN "Users" u ON u.id=uq2."userId" WHERE u.id IS NULL
   ) o WHERE uq."userId"=o."userId" AND uq."queueId"=o."queueId";
   ```
   Verificar com `SELECT count(*) FROM "UsersQueues" uq LEFT JOIN "Users" u ON u.id=uq."userId" WHERE u.id IS NULL` (deve ser 0). Recomendado adicionar isto ao final do `migrate.py` ou criar `clean_orphans.sh`.

**`ai-preserve.sh` agora cobre 9 categorias** (não só IA): AiAgents/Routes/Departments/Files/Chunks/Logs + Queues + QueueScheduleExceptions + **Whatsapps** (UPSERT dinâmico de 120 colunas, preserva tokens Meta Cloud API tokenAPI/wabaId/bmToken/fbPageId). Após restore, usuário só precisa atualizar webhook URL na Meta — todos os tokens permanecem válidos.

## ⚠️ Lições da Estabilização Pós-Cutover (2026-04-20)

Bugs descobertos nos primeiros dias rodando em produção. Já corrigidos no código do container `voxzap-locktec-app` (com backups `.bak*` por arquivo) e refletidos em `migrate.py` quando aplicável.

5. **Re-engagement message (Meta error 131047) — janela 24h indexada por formato do número**. Contatos existentes com `5585XXXXXXXX` (12 dígitos, sem 9) recebiam erro `131047 / Re-engagement message` ao receber template/mensagem mesmo dentro de 24h. Causa raiz: a Meta indexa a janela 24h pelo **formato exato** do número, não pelo número canônico. Mensagem inbound chegava com `558598XXXXXXXX` (13 dígitos com 9), e o envio outbound usando `5585XXXXXXXX` era tratado como recipient diferente.

   **Patch em `server/services/whatsapp.service.ts:739`**: adicionado `errorCode === 131047` e match `"re-engagement"` ao `isRecipientError`, disparando o retry automático com `getAlternatePhoneNumber()` (que já existe em `server/lib/phone-utils.ts`). Backup `.bak2` no container. **Não migrar contatos em massa** — o retry no código resolve o caso por caso. Distribuição na base Locktec: ~19% (4.977) em 13-dig, ~81% (20.952) em 12-dig.

6. **Settings.signed default — ZPro vs VoxZap divergem**. ZPro guardava `signed='disabled'` por padrão; VoxZap espera `signed='enabled'` (operadores assinam mensagens com seu nome). Após migração, 32 operadores sumiam da assinatura. **Corrigido em `migrate.py` via `fix_inherited_defaults()`** (idempotente, roda após cópia de Settings). Uma chave (`notificationSilenced`) também é herdada do ZPro mas é **chave morta** no VoxZap — não consumida pelo código, pode ignorar.

7. **Notificações sonoras + push do navegador desabilitáveis via toggle admin (Settings.notificationsEnabled)**. Em VoxZap puro são hardcoded em 3 pontos do frontend: `client/src/pages/atendimento.tsx` (som de novo ticket), `client/src/pages/chat-interno.tsx` (som de chat interno) e `client/src/contexts/call-context.tsx` (push de chamada VoxCall). Operadores Locktec reclamavam de barulho — implementado **toggle admin global** em Configurações.

   Arquitetura: componente `NotifSettingSync` em `App.tsx` faz `useQuery` em `/api/settings/notificationsEnabled` com `refetchInterval: 60000` e expõe via `(window as any).__voxzapNotifEnabled`. Os 3 pontos checam essa flag antes de tocar/notificar. Latência de propagação: até 60s sem reload, ou imediato com Ctrl+F5. UI no card "Notificações sonoras e push" (`configuracoes.tsx`, abaixo de "Assinatura do Operador"), só visível a admin/superadmin. Marcador de patch: `/* NOTIF_TOGGLE_LOCKTEC */`. Default semeado pela `migrate.py` (`fix_inherited_defaults` → `seeds`): `'disabled'`. **Atenção JSX**: o marcador inline em código TSX precisa estar entre `{/* */}` ou vira texto visível na tela.

8. **Webhook Meta NÃO precisa ser reapontado** após troca de servidor, desde que o tenant aponte para o mesmo domínio (`locktec.voxzap.cc`). Status 8/8 chegando em produção em eveo1 sem nenhuma alteração no Meta Business Manager. Removido do checklist pós-cutover.

9. **Nova Conversa bloqueada por ticket aberto em outro canal** — `POST /api/tickets/new-conversation` em `routes.ts:3427` (linha pré-patch) consultava `prisma.tickets.findFirst({ where: { contactId, tenantId, status: { in: ["open","pending"] } } })` **sem filtrar por `whatsappId`**. Resultado: contato com ticket aberto em CobrancaAtiva impedia abrir Nova Conversa em Locktec — devolvia o ticket existente em vez de criar novo. **Patch**: adicionar `whatsappId: connection.id` ao `where`. Backup `.bak_newconv` no container.

   **Validado**: outras consultas semelhantes (handlers WebChat em `routes.ts:4211` e `routes.ts:4314`) já filtram por `whatsappId` corretamente. Bug isolado a este endpoint.

   **Padrão de revisão**: VoxZap mantém UM ticket por (contato × canal × status_aberto). Qualquer consulta `tickets.findFirst({ contactId, status:open|pending })` que NÃO filtre por canal é suspeita em ambientes multi-canal por contato (caso típico: campanha de cobrança ativa + canal de atendimento padrão coexistindo).

10. **`GlobalNotificationHandler` dispara toasts pra TODOS os operadores logados** (não apenas pro dono do ticket). Componente em `client/src/components/global-notification-handler.tsx` ouve socket events `onNewMessage`, `onInternalNewMessage`, `onParticipantAdded`, `onParticipantRemoved` e dispara `toast()` + `playBeep()` em cada um, sem checar se a mensagem/ticket pertence ao operador. Resultado em produção Locktec: 32 operadores recebendo notificação visual de cada nova mensagem do tenant inteiro, gerando ruído altíssimo. **Patch imediato (gate)**: adicionado `if (!(window as any).__voxzapNotifEnabled) return;` no início dos 4 handlers. Marcador `/* NOTIF_GLOBAL_GATE_LOCKTEC */`. Backup `.bak_global` no container.

    **Pendência arquitetural (tech debt)**: rotear notificações somente pra quem deve receber. Duas opções:
    - **Frontend** (mais rápido): em `handleNewMessage`, comparar `data.userId === currentUser.id` OU `data.queueId in user.queues` antes do toast. Continua broadcast no socket mas filtra na borda.
    - **Backend** (mais limpo): mudar `broadcastNewMessage` (em `server/routes.ts` e `server/lib/socket.ts`) pra emitir em rooms específicas (`user-${userId}`, `queue-${queueId}`) em vez de `tenant-${tenantId}`. Reduz tráfego socket e elimina exposição cruzada de dados entre operadores.

    Caso típico que motivou o pedido do cliente: operador A em atendimento ativo via toast "Nova mensagem recebida — Shirley enviou uma mensagem" toda vez que QUALQUER cliente do tenant manda mensagem, independentemente da fila/dono. Investigar se padrão se repete em `webhook.service.ts` (broadcasts diretos do webhook Meta).

## Visão Geral

| Item | Valor |
|------|-------|
| Cliente | Locktec |
| Sistema Origem | ZPro (Sequelize/PostgreSQL) |
| Sistema Destino | VoxZap (Prisma/PostgreSQL) |
| Volume DB | ~1.275 GB |
| Messages | 1.227.241 rows (813 MB) |
| LogTickets | 1.630.973 rows (224 MB) |
| Tickets | 183.689 rows (103 MB) |
| MessageUpserts | 172.931 rows (83 MB) |
| Contacts | 26.816 rows (13 MB) |
| Users (operadores) | 49 rows |
| Mídias | 57.404 arquivos, 13 GB |
| Tempo estimado DB | ~20 minutos |
| Tempo estimado mídias | ~10 minutos (rsync VPS→VPS) |

## Servidores

### Locktec — Origem (SOMENTE LEITURA em produção!)
- **VPS**: `$LOCKTEC_HOST` (consultar credenciais no scratchpad da sessão), porta SSH: `$LOCKTEC_SSH_PORT`, user: `root`
- **PostgreSQL**: container Docker `postgresql`, porta `5432`, user: `zpro`, db: `postgres`
- **Mídias**: `/home/deployzdg/zpro.io/backend/public/2/` (tenant 2)
- **Sistema**: ZPro original com Sequelize
- **tenantId dos dados**: `2`

### VoxZap — Destino
- **VPS**: `$VOXZAP_HOST` (consultar credenciais no scratchpad da sessão), porta SSH: `$VOXZAP_SSH_PORT`, user: `root`
- **PostgreSQL**: externo em `$DB_HOST:5432`, user: `zpro`, db: `postgres`
- **Mídias**: `/opt/voxzap/uploads/` (host) → `/app/uploads` (container Docker `voxzap-app`)
- **DATABASE_URL**: usar variável de ambiente `DATABASE_URL` ou consultar credenciais no scratchpad da sessão
- **tenantId destino**: `1`

> **IMPORTANTE**: Todas as credenciais (senhas SSH, DATABASE_URL, tokens) devem ser obtidas do scratchpad da sessão ou de variáveis de ambiente. NUNCA hardcoded neste documento.
> **Para produção**: Substituir os dados do servidor destino pelos dados do servidor VoxZap de produção do cliente.

## Pré-requisitos

1. **Acesso SSH** a ambos os VPS
2. **sshpass** instalado no Replit (já disponível)
3. **Ferramentas nos VPS**: `rsync`, `psql`, `pg_dump` (já disponíveis via Docker)
4. **Espaço em disco** no destino: mínimo 20GB livres (13GB mídias + margem)
5. **Janela de manutenção** agendada com o cliente (downtime ~30 min)
6. **Backup do banco destino** antes de começar

## Dados a PRESERVAR no VoxZap (NÃO apagar)

| Tabela | O que preservar | Motivo |
|--------|----------------|--------|
| `Tenants` | ID=1 (VoxTel) | Tenant principal |
| `Users` ID=1 | SuperAdmin (`superadmin@voxtel.biz`) | Acesso administrativo |
| `Whatsapps` ID=1 | Canal WABA conectado com `tokenAPI` | Conexão WhatsApp ativa |
| `AiAgents` | Agente IA configurado | Portaria Locktec |
| `AiAgentChunks` | 8 chunks de knowledge base | Base de conhecimento |
| `AiAgentFiles` | 1 arquivo de KB | Arquivo fonte do RAG |
| `AiAgentRoutes` | 19 rotas de intenção | Roteamento da IA |
| `AiAgentDepartments` | 24 departamentos do agente | Roteamento por departamento |
| `AiAgentLogs` | Histórico de conversas IA (se existir) | Auditoria |
| **Filesystem** `uploads/ai-knowledge/` | `ai-assistant-config.json`, `ai-knowledge-index.json`, arquivos `.md` da KB | Configuração e base de conhecimento do Assistente IA (lê do disco, não do banco) |

## Tabelas a NÃO copiar da Locktec

| Tabela | Motivo |
|--------|--------|
| `Whatsapps` | Preservar canal VoxZap WABA |
| `Tenants` | Preservar tenant VoxTel |
| `AiAgents`, `AiAgentChunks`, `AiAgentFiles`, `AiAgentRoutes`, `AiAgentDepartments`, `AiAgentLogs` | Preservar configuração IA (definitiva, importada do voxtel — Task #119) |
| `Baileys`, `BaileysSessions` | Sessão WhatsApp local do ZPro (não aplicável) |
| `SequelizeMeta` | Migrations Sequelize (não aplicável) |
| `Licenses`, `LicenseActivationLogs`, `LicenseRequestLogs` | Licenciamento ZPro |
| `Proxies`, `Plans` | Config específica ZPro |

---

## FASE 1: Migração do Banco de Dados

### Passo 1 — Backup de segurança dos dados preserváveis

Antes de qualquer alteração, exportar os dados que devem ser preservados no VoxZap:

```bash
# Executar no Replit via SSH no VPS destino
PGPASSWORD='<senha>' pg_dump --data-only \
  --table="Whatsapps" --table="AiAgents" --table="AiAgentChunks" \
  --table="AiAgentFiles" --table="AiAgentRoutes" --table="Tenants" \
  -h <host-db-destino> -p 5432 -U zpro postgres > /tmp/voxzap-preserved-backup.sql

# Backup do SuperAdmin separado
PGPASSWORD='<senha>' psql -h <host-db-destino> -p 5432 -U zpro -d postgres \
  -c "COPY (SELECT * FROM \"Users\" WHERE id=1) TO STDOUT WITH CSV HEADER" > /tmp/superadmin-backup.csv
```

### Passo 2 — Comparar schemas entre ZPro e VoxZap

O ZPro (Sequelize) e o VoxZap (Prisma) têm diferenças de colunas. Para cada tabela a ser copiada, usar a query abaixo em AMBOS os bancos e comparar:

```sql
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'NomeDaTabela'
ORDER BY ordinal_position;
```

**Diferenças conhecidas (já mapeadas na homologação):**

| Tabela | Coluna | ZPro | VoxZap | Ação |
|--------|--------|------|--------|------|
| `Messages` | `id` | UUID varchar | UUID varchar | Compatível |
| `Messages` | `mediaUrl` | filename relativo | `/uploads/filename` | Ajustar após import |
| `Tickets` | `closedAt` | timestamp | BigInt (epoch ms) | Converter no INSERT |
| `Users` | email duplicado | `superadmin@voxtel.biz` | já existe como ID=1 | Renomear para `superadmin-locktec@...` |
| Todas | `tenantId` | `2` (Locktec) | `1` (VoxZap) | Substituir no INSERT |

### Passo 3 — Limpar banco destino (manter preservados)

> ⚠️ **ATENÇÃO — risco de perda silenciosa da configuração de IA (Task #119)**
>
> `TRUNCATE "Queues" CASCADE` propaga em PostgreSQL para QUALQUER tabela com FK
> apontando para `Queues`, **independentemente do `ON DELETE`**. As tabelas
> `AiAgentRoutes` e `AiAgentDepartments` têm FK em `targetQueueId → Queues.id` e
> seriam apagadas pelo CASCADE — o que é EXATAMENTE o que a Task #119 quer evitar.
>
> Para mitigar isto, **antes do TRUNCATE Queues** rode o script
> `deploy/voxzap-locktec/migration/ai-preserve.sh backup` (faz `pg_dump --data-only`
> das 6 tabelas de IA + cópia do diretório `uploads/ai-knowledge/`). **Depois** dos
> truncates, rode `ai-preserve.sh restore` com `session_replication_role='replica'`
> (os `targetQueueId` ficam órfãos até o usuário remapear na UI; isso é esperado).
>
> Validação obrigatória pós-reset: contagem de `AiAgents/Routes/Departments/Files/Chunks`
> deve voltar ao valor pré-reset; `ls /opt/tenants/voxzap-locktec/uploads/ai-knowledge/`
> deve ter os 3 arquivos esperados.

```bash
# Pre-reset (no eveo1):
bash /opt/voxzap/locktec/migration/ai-preserve.sh backup
```

```sql
-- Conectar ao banco VoxZap destino
-- Desabilitar verificação de FK temporariamente
SET session_replication_role = 'replica';

-- TRUNCATE tabelas transacionais (NÃO truncar as preservadas)
TRUNCATE "Messages" CASCADE;
TRUNCATE "LogTickets" CASCADE;
TRUNCATE "Tickets" CASCADE;
TRUNCATE "MessageUpserts" CASCADE;
TRUNCATE "Contacts" CASCADE;
TRUNCATE "ContactCustomFields" CASCADE;
TRUNCATE "ContactTags" CASCADE;
TRUNCATE "ContactWallets" CASCADE;
TRUNCATE "ContactUpserts" CASCADE;
TRUNCATE "TicketProtocols" CASCADE;
TRUNCATE "TicketEvaluations" CASCADE;
TRUNCATE "TicketNotes" CASCADE;
TRUNCATE "TicketShareds" CASCADE;
TRUNCATE "TicketActionLogs" CASCADE;
TRUNCATE "TicketActions" CASCADE;
TRUNCATE "Queues" CASCADE;
TRUNCATE "Tags" CASCADE;
TRUNCATE "FastReply" CASCADE;
TRUNCATE "Settings" CASCADE;
TRUNCATE "Kanbans" CASCADE;
TRUNCATE "Campaigns" CASCADE;
TRUNCATE "CampaignContacts" CASCADE;
TRUNCATE "ApiMessages" CASCADE;
TRUNCATE "AutoReplyLogs" CASCADE;
TRUNCATE "Notifications" CASCADE;
TRUNCATE "CallLogs" CASCADE;
TRUNCATE "UserMessagesLog" CASCADE;
TRUNCATE "PrivateMessage" CASCADE;
TRUNCATE "BirthdayMessagesSents" CASCADE;
TRUNCATE "MessagesOffLine" CASCADE;
TRUNCATE "Opportunitys" CASCADE;
TRUNCATE "UsersQueues" CASCADE;
TRUNCATE "UserWhatsapps" CASCADE;
TRUNCATE "UsersPrivateGroups" CASCADE;
TRUNCATE "OperatorKanbanColumns" CASCADE;
TRUNCATE "OperatorKanbanTickets" CASCADE;
TRUNCATE "TagQueueRoutes" CASCADE;
TRUNCATE "QueueScheduleExceptions" CASCADE;
TRUNCATE "VoxcallIntegrations" CASCADE;
TRUNCATE "VoxcallAbandonedLogs" CASCADE;

-- Remover Users exceto SuperAdmin
DELETE FROM "Users" WHERE id != 1;

-- Reabilitar FK
SET session_replication_role = 'DEFAULT';
```

### Passo 4 — Exportar e importar dados da Locktec

**Estratégia**: Conectar diretamente do container Docker da Locktec ao banco VoxZap. O container da Locktec já tem `.pgpass` configurado.

**Ordem de importação** (respeitar foreign keys):
1. Users (operadores)
2. Queues, Tags, Settings, FastReply, Kanbans
3. Contacts, ContactCustomFields, ContactTags, ContactWallets
4. Tickets (depende de Users, Contacts, Queues)
5. Messages (depende de Tickets, Contacts)
6. LogTickets, TicketProtocols, TicketEvaluations, TicketNotes, etc.
7. Demais tabelas (Campaigns, Notifications, etc.)

**Padrão de INSERT para cada tabela** (exemplo com Contacts):

```bash
# Executar dentro do container Docker da Locktec
docker exec -i postgresql psql -U zpro -d postgres -c "
INSERT INTO \"Contacts\" (id, name, number, email, \"profilePicUrl\", \"tenantId\", \"createdAt\", \"updatedAt\", ...)
SELECT id, name, number, email, \"profilePicUrl\", 
  1 as \"tenantId\",  -- MUDAR de 2 para 1
  \"createdAt\", \"updatedAt\", ...
FROM dblink(
  'host=<host-db-destino> port=5432 dbname=postgres user=zpro password=<senha>',
  'SELECT * FROM \"Contacts\" WHERE \"tenantId\" = 2'
) AS src(id int, name text, ...);
"
```

**Alternativa mais prática (usada na homologação com sucesso):**

Configurar `.pgpass` no container Locktec para acessar o banco VoxZap diretamente, depois usar INSERT...SELECT via `dblink` ou export/import CSV:

```bash
# No container Locktec, exportar tabela
docker exec -i postgresql psql -U zpro -d postgres \
  -c "COPY (SELECT * FROM \"Contacts\" WHERE \"tenantId\"=2) TO STDOUT WITH CSV HEADER" \
  > /tmp/contacts.csv

# Transferir e importar no VoxZap (ajustando tenantId)
# Ou usar conexão direta se .pgpass estiver configurado
```

**CRÍTICO — Tratamento do User com email duplicado:**
A Locktec tem um user com email `superadmin@voxtel.biz` (mesmo do SuperAdmin VoxZap). Durante a importação dos Users, renomear esse email:

```sql
-- Após importar Users da Locktec, ajustar o email duplicado
UPDATE "Users" SET email = 'superadmin-locktec@voxtel.biz' 
WHERE id = <id-do-user-locktec> AND email = 'superadmin@voxtel.biz';
```

**CRÍTICO — Converter closedAt de timestamp para BigInt:**
```sql
-- Na query de INSERT dos Tickets
EXTRACT(EPOCH FROM "closedAt")::bigint * 1000 as "closedAt"
```

**CRÍTICO — Substituir tenantId:**
Em TODAS as queries de INSERT, substituir `tenantId=2` por `tenantId=1`:
```sql
1 as "tenantId"  -- em vez de copiar o tenantId original
```

### Passo 5 — Ajustar sequences

Após importar todos os dados, resetar as sequences de auto-incremento:

```sql
SELECT setval(pg_get_serial_sequence('"Users"', 'id'), (SELECT COALESCE(MAX(id),1) FROM "Users"));
SELECT setval(pg_get_serial_sequence('"Tickets"', 'id'), (SELECT COALESCE(MAX(id),1) FROM "Tickets"));
SELECT setval(pg_get_serial_sequence('"Contacts"', 'id'), (SELECT COALESCE(MAX(id),1) FROM "Contacts"));
SELECT setval(pg_get_serial_sequence('"Queues"', 'id'), (SELECT COALESCE(MAX(id),1) FROM "Queues"));
SELECT setval(pg_get_serial_sequence('"Tags"', 'id'), (SELECT COALESCE(MAX(id),1) FROM "Tags"));
SELECT setval(pg_get_serial_sequence('"Kanbans"', 'id'), (SELECT COALESCE(MAX(id),1) FROM "Kanbans"));
SELECT setval(pg_get_serial_sequence('"Campaigns"', 'id'), (SELECT COALESCE(MAX(id),1) FROM "Campaigns"));
SELECT setval(pg_get_serial_sequence('"Settings"', 'id'), (SELECT COALESCE(MAX(id),1) FROM "Settings"));
SELECT setval(pg_get_serial_sequence('"FastReply"', 'id'), (SELECT COALESCE(MAX(id),1) FROM "FastReply"));
SELECT setval(pg_get_serial_sequence('"Notifications"', 'id'), (SELECT COALESCE(MAX(id),1) FROM "Notifications"));
SELECT setval(pg_get_serial_sequence('"LogTickets"', 'id'), (SELECT COALESCE(MAX(id),1) FROM "LogTickets"));
SELECT setval(pg_get_serial_sequence('"TicketProtocols"', 'id'), (SELECT COALESCE(MAX(id),1) FROM "TicketProtocols"));
-- Repetir para TODAS as tabelas com serial/autoincrement
```

### Passo 6 — Validação do banco

```sql
-- Conferir volumes importados
SELECT 'Messages' as tabela, COUNT(*) as total FROM "Messages"
UNION ALL SELECT 'Tickets', COUNT(*) FROM "Tickets"
UNION ALL SELECT 'Contacts', COUNT(*) FROM "Contacts"
UNION ALL SELECT 'LogTickets', COUNT(*) FROM "LogTickets"
UNION ALL SELECT 'Users', COUNT(*) FROM "Users"
UNION ALL SELECT 'MessageUpserts', COUNT(*) FROM "MessageUpserts"
ORDER BY total DESC;

-- Verificar que preservados estão intactos
SELECT id, name, email FROM "Users" WHERE id = 1; -- SuperAdmin
SELECT id, name, status, type FROM "Whatsapps" WHERE id = 1; -- Canal WABA
SELECT id, name FROM "AiAgents"; -- Agente IA
SELECT COUNT(*) FROM "AiAgentChunks"; -- Chunks (deve ser 8)
SELECT COUNT(*) FROM "AiAgentRoutes"; -- Rotas (deve ser 19)

-- Verificar tenantId correto
SELECT "tenantId", COUNT(*) FROM "Messages" GROUP BY "tenantId"; -- Deve ser tudo 1
SELECT "tenantId", COUNT(*) FROM "Tickets" GROUP BY "tenantId"; -- Deve ser tudo 1
```

**Volumes esperados (da homologação):**

| Tabela | Rows esperados |
|--------|---------------|
| Messages | 1.227.241 |
| LogTickets | 1.630.973 |
| Tickets | 183.689 |
| MessageUpserts | 172.931 |
| Contacts | 26.816 |
| Users | ~50 (49 Locktec + 1 SuperAdmin) |

---

## FASE 2: Migração das Mídias

### Passo 1 — Configurar SSH key-based auth entre VPS

```bash
# No VPS destino (VoxZap), gerar chave SSH
ssh-keygen -t rsa -b 2048 -f /root/.ssh/id_rsa -N '' -q

# Copiar chave pública para Locktec
# (obter a chave com: cat /root/.ssh/id_rsa.pub)
# No VPS Locktec, adicionar ao authorized_keys:
echo '<chave-publica>' >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# Testar conexão sem senha
ssh -o StrictHostKeyChecking=no root@$LOCKTEC_HOST 'echo OK'
```

### Passo 2 — Transferir mídias com rsync

```bash
# No VPS destino (VoxZap), executar rsync em background
nohup rsync -avz --progress \
  --exclude='baileysBackup/' \
  -e 'ssh -o StrictHostKeyChecking=no' \
  root@$LOCKTEC_HOST:/home/deployzdg/zpro.io/backend/public/2/ \
  /opt/voxzap/uploads/ \
  > /tmp/rsync_media.log 2>&1 &

echo "PID: $!"
```

**Monitorar progresso:**
```bash
tail -5 /tmp/rsync_media.log
# Verificar se concluiu:
grep "DONE\|completed" /tmp/rsync_media.log
```

### Passo 3 — Ajustar permissões

```bash
# O container Docker roda como uid 1000
chown -R 1000:1000 /opt/voxzap/uploads/
```

### Passo 4 — Atualizar mediaUrl no banco

O ZPro armazena `mediaUrl` como nome de arquivo relativo (ex: `image.png`).
O VoxZap espera `/uploads/filename` para servir arquivos locais.

```sql
-- Prefixar todas as mediaUrl com /uploads/
UPDATE "Messages"
SET "mediaUrl" = '/uploads/' || "mediaUrl"
WHERE "mediaUrl" IS NOT NULL 
  AND "mediaUrl" != '' 
  AND "mediaUrl" NOT LIKE '/uploads/%' 
  AND "mediaUrl" NOT LIKE 'http%';
```

**Na homologação, atualizou 53.699 rows.**

### Passo 5 — Validar mídias

```bash
# Dentro do container, verificar que os arquivos estão acessíveis
docker exec voxzap-app ls /app/uploads/ | wc -l
# Esperado: ~57.371

# Testar via HTTP (imagem, PDF, áudio)
curl -s -o /dev/null -w "HTTP %{http_code}" "https://<dominio>/uploads/<arquivo.jpeg>"
curl -s -o /dev/null -w "HTTP %{http_code}" "https://<dominio>/uploads/<arquivo.pdf>"
curl -s -o /dev/null -w "HTTP %{http_code}" "https://<dominio>/uploads/<arquivo.ogg>"
# Todos devem retornar HTTP 200
```

---

## FASE 3: Validação Final

### Checklist pós-migração

- [ ] Login SuperAdmin funciona (`superadmin@voxtel.biz`)
- [ ] Dashboard mostra volumes reais (~183K tickets, ~1.2M mensagens)
- [ ] Listagem de tickets funciona com paginação
- [ ] Busca de contatos retorna resultados (26K+)
- [ ] Canal WhatsApp está CONNECTED
- [ ] Agente IA responde corretamente
- [ ] Mensagens com mídia exibem imagens/áudios/PDFs
- [ ] Performance do dashboard aceitável (< 5s)
- [ ] Operadores da Locktec conseguem fazer login
- [ ] Envio de mensagens funciona (novo ticket)
- [ ] Recebimento de mensagens funciona (webhook)

### APIs para validar via curl

```bash
# Login
TOKEN=$(curl -s -X POST "https://<dominio>/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"$ADMIN_EMAIL","password":"$ADMIN_PASSWORD"}' | jq -r '.token')

# Dashboard stats
curl -s -H "Authorization: Bearer $TOKEN" "https://<dominio>/api/dashboard/stats"

# Tickets (paginação)
curl -s -H "Authorization: Bearer $TOKEN" "https://<dominio>/api/tickets?page=1&limit=20"

# Contatos
curl -s -H "Authorization: Bearer $TOKEN" "https://<dominio>/api/contacts?page=1&limit=20"

# Whatsapps (status do canal)
curl -s -H "Authorization: Bearer $TOKEN" "https://<dominio>/api/whatsapps"
```

---

## Notas Operacionais

### Operações de longa duração via SSH
- Sempre usar `nohup ... &` para processos longos (SSH timeout em ~60s)
- Usar `sshpass` para SSH do Replit para os VPS
- Monitorar logs em `/tmp/` (ex: `/tmp/rsync_media.log`)

### Conexão direta entre DBs
Na homologação, usamos o container Docker da Locktec conectando diretamente ao banco VoxZap (sem intermediário). Configurar `.pgpass` no container:

```bash
docker exec -i postgresql bash -c "echo '<host-destino>:5432:postgres:zpro:<senha>' > /root/.pgpass && chmod 600 /root/.pgpass"
```

### Updates em massa (>1M rows)
Para updates grandes (ex: tenantId em 1.2M Messages), executar via `nohup` no container:

```bash
docker exec -i postgresql nohup psql -U zpro -h <host-destino> -d postgres -c "
UPDATE \"Messages\" SET \"tenantId\" = 1 WHERE \"tenantId\" = 2;
" > /tmp/update_tenantid.log 2>&1 &
```

### Estrutura de arquivos de mídia

| Path Locktec (ZPro) | Path VoxZap | Descrição |
|---------------------|-------------|-----------|
| `public/2/*.jpeg` | `/uploads/*.jpeg` | Imagens de mensagens |
| `public/2/*.pdf` | `/uploads/*.pdf` | Documentos PDF |
| `public/2/*.ogg` | `/uploads/*.ogg` | Áudios WhatsApp |
| `public/2/*.mp4` | `/uploads/*.mp4` | Vídeos |
| `public/2/*.mp3` | `/uploads/*.mp3` | Áudios convertidos |
| `public/2/fastreply/*` | `/uploads/fastreply/*` | Mídias de respostas rápidas |
| `public/2/chatbot/*` | `/uploads/chatbot/*` | Mídias de chatbot |
| `public/2/birthday/*` | `/uploads/birthday/*` | Mídias de aniversário |
| N/A | `/uploads/ai-knowledge/*` | Base de conhecimento IA (PRESERVAR!) |

### Como o VoxZap serve mídias

1. **Backend** (`server/routes.ts`):
   - `app.use("/uploads", express.static(uploadDir))` — serve arquivos estáticos de `/uploads/`
   - `app.get("/api/media/:mediaId")` — proxy para Meta API (para media IDs do WhatsApp Cloud)

2. **Frontend** (`getMediaUrl()` em `atendimento.tsx`, `contatos.tsx`, `painel-atendimentos.tsx`):
   - Se `mediaUrl` começa com `/uploads/` ou `http` → usa diretamente
   - Caso contrário → trata como Meta media ID e prepende `/api/media/`
   - Por isso é **obrigatório** prefixar com `/uploads/` após a migração

---

## Compatibilidade com Índice Anti-Duplicação

O VoxZap possui um índice parcial único `idx_tickets_one_open_per_contact` que impede 2 tickets ativos (open/pending/paused) para o mesmo contato+tenant+whatsappId. **Este índice NÃO interfere na migração** porque:

1. A migração faz `TRUNCATE "Tickets" CASCADE` antes do import — tabela vazia, sem conflitos
2. Os 183K tickets da Locktec são históricos (status `closed`) — o índice parcial só atua sobre `open/pending/paused`
3. Se por acaso existir um ticket aberto duplicado nos dados da Locktec, a migração deve fechar o mais antigo antes do import

**Verificação pré-migração recomendada** (executar no banco origem antes de importar):
```sql
SELECT "contactId", COUNT(*) as cnt
FROM "Tickets"
WHERE status IN ('open', 'pending', 'paused')
GROUP BY "contactId"
HAVING COUNT(*) > 1;
```
Se retornar resultados, fechar os duplicados mais antigos antes de migrar.

## FASE 4: Normalização e Limpeza Pós-Migração

O script de migração copia os números de telefone dos contatos **no formato original do ZPro**, sem normalização. Isso significa que após a migração, podem existir:
- Números sem DDI (ex: `85988788084` em vez de `5585988788084`)
- Números sem nono dígito (ex: `558588788084` em vez de `5585988788084`)
- Contatos duplicados (mesmo número em formatos diferentes)

**A partir da correção de normalização centralizada**, novos contatos criados pelo webhook, campanha, importação CSV ou manualmente já são normalizados automaticamente. Porém, os dados migrados precisam de limpeza manual.

### Bug Crítico Resolvido: Tickets Duplicados por Número Não-Normalizado

**Problema**: Quando um operador enviava um template para um contato migrado com número sem DDI (ex: `8576020655`), e o cliente respondia, o webhook recebia o número completo (`5585976020655`). O sistema não encontrava o contato original porque `buildPhoneSearchNumbers()` não gerava variantes sem o DDI `55`, resultando na criação de um novo contato e ticket duplicado.

**Solução aplicada** (v1.5.0+):
1. `buildPhoneSearchNumbers()` em `server/lib/phone-utils.ts` agora gera variantes sem DDI:
   - Para `5585976020655` → busca também `85976020655` (11 dígitos) e `8576020655` (10 dígitos)
2. O endpoint `POST /api/new-conversation` auto-normaliza o número do contato quando selecionado via `contactId`
3. A busca rápida de contatos (`/api/contacts/quick-search`) foi ampliada para 30 resultados com ordenação alfabética

**Lição**: Após migração, é ESSENCIAL rodar a sequência de normalização abaixo para evitar duplicatas. Contatos sem DDI causam problemas em todo o fluxo (webhook, nova conversa, campanhas).

### Sequência Obrigatória Pós-Migração

Executar na página **Contatos → Ações** na seguinte ordem:

#### Passo 1: Checar Nono Dígito (BR)
- Normaliza celulares brasileiros: adiciona DDI `55` se necessário E adiciona nono dígito se faltando
- Exemplo: `85988788084` (11 dígitos) → `5585988788084` (13 dígitos)
- Exemplo: `558588788084` (12 dígitos) → `5585988788084` (13 dígitos)
- Verifica automaticamente se já existe contato com o número normalizado antes de atualizar (proteção anti-duplicata)
- Retorna relatório: quantos atualizados, quantos ignorados por conflito, quantos com erro

#### Passo 2: Remover Duplicados
- Remove contatos com número exato duplicado (mantém o mais antigo, que tipicamente tem tickets)
- Só remove contatos **sem tickets** associados
- Seguro: não perde histórico de conversas

#### Passo 3: Gerenciar Duplicatas (Admin)
- Para casos mais complexos: números parecidos mas não idênticos (ex: com/sem DDI, com/sem nono dígito)
- Busca inteligente por telefone, email, CPF ou IA
- Merge manual: escolhe qual manter, transfere tickets, combina dados
- **IMPORTANTE**: Após migração Locktec, foram encontrados ~552 contatos sem DDI que eram duplicatas de contatos já normalizados. Cada um desses precisa ser mergeado individualmente (mover Tickets, Messages, interaction_summaries para o contato canônico antes de excluir)

#### Passo 4: Exportar Contatos
- Gerar CSV de validação pós-limpeza
- Conferir que todos os números estão no formato correto (13 dígitos para celular BR: 55 + DDD + 9 + 8 dígitos)
- Validar que não há duplicatas remanescentes

### Alternativa: Importação via CSV

Para clientes menores onde a migração direta de banco não é necessária, a funcionalidade **Importar** (Contatos → Ações → Importar) pode ser usada:
- Aceita CSV com colunas: numero, nome, email, cpf, empresa, primeiro nome, sobrenome
- Normaliza automaticamente todos os números (DDI + nono dígito)
- Permite vincular todos os contatos importados a uma **Tag** e/ou **Carteira** específica
- Faz merge suave com contatos existentes (não sobrescreve dados já preenchidos)
- Proteção contra duplicatas automática

---

## FASE 5: Importação das configurações de IA (Task #119) — definitivo

> **Quando rodar**: SEMPRE antes do reset+import definitivo da Locktec (Task #118).
> A configuração de IA fica no servidor `voxtel.voxzap.app.br` e tem que ser
> trazida pro destino para sobreviver ao reset.

### Origem (somente leitura)
- **VPS**: `voxtel.voxzap.app.br` — porta SSH `22300`, user `root` (senha no scratchpad)
- **Postgres**: externo, **versão 18.x**. URL completa em
  `docker inspect voxzap-app | jq '.[0].Config.Env[]' | grep DATABASE_URL`
  (formato: `postgresql://zpro:<urlencoded>@voxzap.voxserver.app.br:5432/postgres`)
- **tenantId dos dados**: `1` (mesmo do destino — sem rewrite!)
- **Filesystem**: `/opt/voxzap/uploads/ai-knowledge/` (~92 KB, 3 arquivos)

### Destino
- **VPS**: `eveo1.voxserver.app.br` porta `22300`, user `root`
- **DB**: container `voxzap-locktec-db`, **PG 16.x**, user `voxzap`, db `voxzap`
- **App**: container `voxzap-locktec-app`
- **Filesystem**: `/opt/tenants/voxzap-locktec/uploads/ai-knowledge/` (chown `1000:1000`)
- **URL**: `https://locktec.voxzap.cc`

### O que vem (5 tabelas + filesystem)

| Item | Volume | Observação |
|------|--------|-----------|
| `AiAgents` | 1 | agente PortariaLocktec |
| `AiAgentRoutes` | 19 | `targetQueueId` orfão até remap (Task #121) |
| `AiAgentDepartments` | 24 | `targetQueueId` orfão até remap (Task #121) |
| `AiAgentFiles` | 1 | metadados do arquivo da KB |
| `AiAgentChunks` | 8 | embeddings RAG |
| `AiAgentLogs` | (skip) | histórico de conversas — NÃO copiar |
| `uploads/ai-knowledge/` | 92 KB / 3 arquivos | `ai-assistant-config.json`, `ai-knowledge-index.json`, `*.md` |

### Pegadinhas conhecidas

1. **Versão do pg_dump**: a origem é PG 18, então use `postgres:18-alpine` (não 16).
2. **`SET transaction_timeout = 0`** aparece no dump (PG 17+ only) e quebra restore em PG 16. Stripar com `sed -i '/^SET transaction_timeout/d'`.
3. **`session_replication_role='replica'`** é obrigatório no restore: `targetQueueId` aponta pra Queues que ainda não existem no destino.
4. **Quem chama o restore não pode iniciar `BEGIN;` se já passar `--single-transaction`** — escolher um dos dois.

### Script pronto: procedimento copy-paste

Roda da máquina do agente (Replit) que tem `sshpass` + acesso SSH a ambos.

```bash
export SSHPASS='<senha-no-scratchpad>'
SSH="sshpass -e ssh -p 22300 -o StrictHostKeyChecking=no -o LogLevel=ERROR -T"
SCP="sshpass -e scp -P 22300 -o StrictHostKeyChecking=no -o LogLevel=ERROR"
TS=$(date +%Y%m%d-%H%M%S)
DUMP=/tmp/voxtel-ai-${TS}.sql

# 1) Descobrir DATABASE_URL na origem
DBURL=$($SSH root@voxtel.voxzap.app.br \
  'docker inspect voxzap-app | python3 -c "import json,sys; print(dict(e.split(\"=\",1) for e in json.load(sys.stdin)[0][\"Config\"][\"Env\"])[\"DATABASE_URL\"])"')

# 2) pg_dump das 5 tabelas (sem AiAgentLogs)
$SSH root@voxtel.voxzap.app.br "docker run --rm postgres:18-alpine pg_dump '$DBURL' \
  --data-only --column-inserts --no-owner --no-acl \
  --table='public.\"AiAgents\"' --table='public.\"AiAgentRoutes\"' \
  --table='public.\"AiAgentDepartments\"' --table='public.\"AiAgentFiles\"' \
  --table='public.\"AiAgentChunks\"'" > $DUMP

# 3) Sanitizar incompatibilidade PG18→PG16 e enviar para o destino
sed -i '/^SET transaction_timeout/d' $DUMP
$SCP $DUMP root@eveo1.voxserver.app.br:/tmp/voxtel-ai-${TS}.sql

# 4) Backup do destino, restore, reset de sequences
$SSH root@eveo1.voxserver.app.br "
  mkdir -p /opt/voxzap/backups
  docker exec voxzap-locktec-db pg_dump -U voxzap -d voxzap --data-only --column-inserts \
    -t '\"AiAgents\"' -t '\"AiAgentRoutes\"' -t '\"AiAgentDepartments\"' \
    -t '\"AiAgentFiles\"' -t '\"AiAgentChunks\"' -t '\"AiAgentLogs\"' \
    > /opt/voxzap/backups/aiagents-pre-import-${TS}.sql

  { echo \"SET session_replication_role='replica';\"; cat /tmp/voxtel-ai-${TS}.sql; } | \
    docker exec -i voxzap-locktec-db psql -U voxzap -d voxzap -v ON_ERROR_STOP=1 --single-transaction

  docker exec -i voxzap-locktec-db psql -U voxzap -d voxzap -c \"
    SELECT setval(pg_get_serial_sequence('\\\"AiAgents\\\"','id'), GREATEST(COALESCE(MAX(id),0),1)) FROM \\\"AiAgents\\\";
    SELECT setval(pg_get_serial_sequence('\\\"AiAgentRoutes\\\"','id'), GREATEST(COALESCE(MAX(id),0),1)) FROM \\\"AiAgentRoutes\\\";
    SELECT setval(pg_get_serial_sequence('\\\"AiAgentDepartments\\\"','id'), GREATEST(COALESCE(MAX(id),0),1)) FROM \\\"AiAgentDepartments\\\";
    SELECT setval(pg_get_serial_sequence('\\\"AiAgentFiles\\\"','id'), GREATEST(COALESCE(MAX(id),0),1)) FROM \\\"AiAgentFiles\\\";
    SELECT setval(pg_get_serial_sequence('\\\"AiAgentChunks\\\"','id'), GREATEST(COALESCE(MAX(id),0),1)) FROM \\\"AiAgentChunks\\\";\"
"

# 5) Filesystem ai-knowledge: voxtel → local → eveo1
mkdir -p /tmp/ai-knowledge
$SCP -r root@voxtel.voxzap.app.br:/opt/voxzap/uploads/ai-knowledge/. /tmp/ai-knowledge/
$SCP -r /tmp/ai-knowledge/. root@eveo1.voxserver.app.br:/opt/tenants/voxzap-locktec/uploads/ai-knowledge/
$SSH root@eveo1.voxserver.app.br 'chown -R 1000:1000 /opt/tenants/voxzap-locktec/uploads/ai-knowledge/'
```

### Validação obrigatória (login `superadmin@voxtel.biz` / senha do `server/seed.ts`)

```bash
TOKEN=$(curl -ksS -X POST https://locktec.voxzap.cc/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"superadmin@voxtel.biz","password":"<senha-do-seed>"}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')

curl -ksS -H "Authorization: Bearer $TOKEN" https://locktec.voxzap.cc/api/ai-agents | jq
curl -ksS -H "Authorization: Bearer $TOKEN" https://locktec.voxzap.cc/api/ai-assistant/config | jq
curl -ksS -H "Authorization: Bearer $TOKEN" https://locktec.voxzap.cc/api/ai-assistant/files | jq
```

**Critérios de aceite (banco):** `AiAgents=1, AiAgentRoutes=19, AiAgentDepartments=24, AiAgentFiles=1, AiAgentChunks=8`. **API:** três 200 com agente PortariaLocktec, `hasGeminiKey=true` e o arquivo `descricao_completa_IA.md` com `chunksCount=25, status=ready`.

### Proteção durante o reset definitivo (Task #118)

O `TRUNCATE "Queues" CASCADE` do Passo 3 propaga via FK `targetQueueId` e apagaria `AiAgentRoutes` + `AiAgentDepartments`. Para evitar isso:

1. **Antes do reset**: subir o script para o eveo1 e rodar `backup`:
   ```bash
   scp -P 22300 deploy/voxzap-locktec/migration/ai-preserve.sh \
       root@eveo1.voxserver.app.br:/opt/voxzap/locktec/migration/
   ssh -p 22300 root@eveo1.voxserver.app.br \
       'bash /opt/voxzap/locktec/migration/ai-preserve.sh backup'
   ```
2. **Depois do reset+import** da Locktec, restaurar:
   ```bash
   ssh -p 22300 root@eveo1.voxserver.app.br \
       'bash /opt/voxzap/locktec/migration/ai-preserve.sh restore'
   ```
   O script imprime contagem antes/depois e diff para validação imediata.

### Pós-import: ações manuais que ficam para o usuário

| Ação | Onde | Task de tracking |
|------|------|------------------|
| Vincular canais WhatsApp ao agente PortariaLocktec | UI `/canais` (campo Agente IA) | #120 |
| Remapear `targetQueueId` de cada rota e departamento para as Queues reais da Locktec | UI `/agentes-ia` | #121 |
| Validar que IA sobreviveu ao reset (contagens + endpoints 200) | Curl autenticado | #122 |

### Artefatos no repositório

- `deploy/voxzap-locktec/migration/ai-preserve.sh` — backup/restore das **6 tabelas IA + 2 tabelas Filas** (`Queues`, `QueueScheduleExceptions`) + filesystem `uploads/ai-knowledge/`. Para Queues usa **UPSERT** (`ON CONFLICT (id) DO UPDATE`) que preserva `userId` local (CASE EXISTS) e não toca em `UsersQueues`/`TagQueueRoutes`. Para IA usa **DELETE+INSERT** (não TRUNCATE — `Whatsapps.aiAgentId` é FK pra `AiAgents`).
- `deploy/voxzap-locktec/migration/migrate.py` — guarda dura `PRESERVE_AI_TABLES`
- `deploy/voxzap-locktec/evidence/ai-config-import-evidence.txt` — evidência da execução de 2026-04-19

---

## Resultado da Homologação (Referência)

Executada com sucesso em março/2026:
- **Task #55**: Clonagem do banco — 1.227.241 Messages, 183.689 Tickets, 26.816 Contacts importados
- **Task #56**: Transferência de mídias — 57.382 arquivos, 13GB, todas validadas com HTTP 200
- **Tempo total**: ~45 minutos (20 min DB + 10 min rsync + 15 min validação)
- **Disco usado**: 39GB de 75GB (52%)

---

## FASE 6: Habilitar segundo domínio na virada (Task #123)

**Quando executar:** durante a janela de manutenção da virada definitiva, **depois** de confirmar que o DNS `voxzaplocktec.voxserver.app.br` foi repontado pro IP do eveo1 (`177.104.171.145`). Hoje aponta via CNAME pra `locktec.voxserver.app.br` → `217.216.90.134` (servidor antigo).

**Por quê:** os usuários antigos da Locktec acessavam o sistema (ZPro) via `voxzaplocktec.voxserver.app.br`. Pra evitar forçar todos a mudar o link de uma vez, mantemos os dois domínios apontando pro mesmo tenant durante a transição. O canônico continua sendo `locktec.voxzap.cc`.

### 6.1 — Pré-checagem de DNS (obrigatório antes do passo 6.2)

```bash
ssh root@eveo1.voxserver.app.br -p 22300

# DNS deve apontar pro 177.104.171.145
dig +short voxzaplocktec.voxserver.app.br | tail -1
dig @8.8.8.8 +short voxzaplocktec.voxserver.app.br | tail -1
```

⚠️ Se ainda aparecer `217.216.90.134`, **PARE**. Aguarde a propagação. Não tente emitir o cert — Let's Encrypt tem rate limit de 5 falhas/hora por domínio.

### 6.2 — Adicionar o domínio no nginx (HTTP-01 webroot)

Antes do cert, precisa adicionar o `server_name` HTTP pra o desafio HTTP-01 do certbot funcionar (ele bate em `http://novo-dominio/.well-known/acme-challenge/`).

```bash
cd /opt/tenants/voxzap-locktec
docker exec tenants-nginx cp /etc/nginx/conf.d/tenant_voxzap-locktec.conf \
  /etc/nginx/conf.d/tenant_voxzap-locktec.conf.bak.$(date +%Y%m%d-%H%M%S)

# Adiciona o segundo server_name no bloco HTTP (porta 80)
docker exec tenants-nginx sed -i \
  's/server_name locktec.voxzap.cc;/server_name locktec.voxzap.cc voxzaplocktec.voxserver.app.br;/' \
  /etc/nginx/conf.d/tenant_voxzap-locktec.conf

docker exec tenants-nginx nginx -t && docker exec tenants-nginx nginx -s reload
```

### 6.3 — Emitir o cert SSL via Let's Encrypt (HTTP-01)

```bash
# Webroot que o nginx serve em /.well-known/acme-challenge/
certbot certonly --webroot -w /var/www/certbot \
  -d voxzaplocktec.voxserver.app.br \
  --email admin@voxtel.biz --agree-tos --no-eff-email --non-interactive

# Confirmar que o cert foi gerado
ls -la /etc/letsencrypt/live/voxzaplocktec.voxserver.app.br/
```

### 6.4 — Adicionar o cert ao bloco HTTPS

Editar `/etc/nginx/conf.d/tenant_voxzap-locktec.conf` no `tenants-nginx` adicionando um bloco HTTPS espelho do existente, mas com `server_name` e `ssl_certificate*` apontando pro novo domínio. **Não mexer no bloco HTTPS atual do `locktec.voxzap.cc`** — manter os dois lado a lado pra rollback fácil.

```nginx
server {
    listen 443 ssl;
    http2 on;
    server_name voxzaplocktec.voxserver.app.br;
    ssl_certificate /etc/letsencrypt/live/voxzaplocktec.voxserver.app.br/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/voxzaplocktec.voxserver.app.br/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    client_max_body_size 100M;

    # mesmas três location { } do bloco existente (api/login, api/, /)
    # — copiar idênticas
}
```

```bash
docker exec tenants-nginx nginx -t && docker exec tenants-nginx nginx -s reload
```

### 6.5 — Smoke test pelos dois domínios

Pelo navegador (e/ou via curl):

```bash
# Cert válido nos dois?
curl -sI https://locktec.voxzap.cc/ | head -3
curl -sI https://voxzaplocktec.voxserver.app.br/ | head -3

# App responde nos dois?
curl -s https://voxzaplocktec.voxserver.app.br/api/version 2>/dev/null | head -c 200
```

Pelo navegador: login, abrir uma conversa, enviar/receber mensagem, confirmar que o WebSocket conecta (DevTools > Network > WS) sem erro de CORS/host.

### 6.6 — Confirmar renovação automática

```bash
certbot renew --dry-run --cert-name voxzaplocktec.voxserver.app.br
```

### 6.7 — Rollback (caso algo dê ruim)

Remover **só** o segundo domínio, mantendo o canônico intacto:

```bash
# Restaura o backup do conf nginx (gerado em 6.2)
docker exec tenants-nginx cp /etc/nginx/conf.d/tenant_voxzap-locktec.conf.bak.<timestamp> \
  /etc/nginx/conf.d/tenant_voxzap-locktec.conf
docker exec tenants-nginx nginx -t && docker exec tenants-nginx nginx -s reload

# (Opcional) revogar o cert
certbot revoke --cert-name voxzaplocktec.voxserver.app.br --non-interactive
```

### 6.8 — Aposentar o domínio antigo (futuro)

Quando todos os usuários estiverem usando `locktec.voxzap.cc`, basta inverter o passo 6.4 (remover o segundo bloco HTTPS) e revogar o cert. **Não está no escopo da virada** — fazer só quando o cliente sinalizar que pode.

### Notas

- O app usa `req.get("host")` em todos os pontos relevantes — não tem whitelist de host hardcoded. Funciona com qualquer domínio que o nginx mande pro container.
- O webhook do WhatsApp na Meta **não muda** — continua registrado em `locktec.voxzap.cc/webhook/whatsapp`. As mensagens chegam pelo domínio canônico, independente de qual domínio o usuário esteja usando na UI.
- Tempo estimado total: **~5 min** depois que o DNS estiver propagado.

## Pendências de Performance (registrar para fazer em horário tranquilo)

Tarefas levantadas durante estabilização Locktec — agendar para janela de manutenção, NÃO mexer durante horário comercial:

### P1 — Backend: socket rooms por operador
- **Problema**: `broadcastNewMessage` e correlatos emitem evento para o tenant inteiro (32+ operadores recebem cada mensagem). Causa: ruído visual, tráfego desnecessário, vazamento de dados entre operadores.
- **Solução**: trocar `io.to('tenant-' + tenantId).emit(...)` por `io.to('user-' + ticket.userId).emit(...)` ou `io.to('queue-' + ticket.queueId).emit(...)`.
- **Antes de mexer**: mapear TODOS os pontos onde broadcast tenant-wide é chamado (`server/socket.ts`, `whatsappService.ts`, `routes.ts`) e validar que rooms `user-X` e `queue-Y` estão sendo joinadas no connect handler.
- **Esforço**: 2-4h. **Risco**: médio (se errar room, operador deixa de receber mensagem do próprio ticket).

### P2 — Cache em disco para mídia WhatsApp Cloud
- **Problema**: cada `/api/media/<id>` faz round-trip Meta → server → cliente toda vez. Áudios demoram 1-4s pra abrir, mesmo na segunda escuta.
- **Solução**: salvar buffer em `/app/uploads/waba-cache/<mediaId>.<ext>` na primeira request; servir do disco nas subsequentes. Mídia WhatsApp é imutável → cache eterno.
- **Local**: `routes.ts:2995` (`app.get("/api/media/:mediaId")`).
- **Bonus**: adicionar `Content-Type` correto ao salvar pra Safari/iOS funcionarem (com pré-conversão opus→mp3 via ffmpeg, item P3).
- **Esforço**: 3h. **Risco**: baixo. **Ganho**: 90% mais rápido após primeira escuta.

### P3 — Pré-conversão opus → mp3
- **Problema**: Safari/iOS não tocam `audio/ogg; codecs=opus` (formato nativo do WhatsApp Cloud).
- **Solução**: quando salvar no cache (P2), executar `ffmpeg -i input.ogg -codec:a libmp3lame output.mp3` em background; servir mp3 quando `User-Agent` for Safari OU sempre (mp3 universal).
- **Pré-requisito**: instalar `ffmpeg` no Dockerfile do voxzap-locktec-app.
- **Esforço**: 5h (inclui mexer no Dockerfile, rebuild, teste). **Risco**: médio (se ffmpeg falhar, fallback pra ogg).

### P4 — Throttle de prefetch de mídia (frontend)
- **Problema**: `atendimento.tsx` linha ~2061 dispara `fetch` para todas as mídias da conversa em paralelo. Se a tela tem 10 áudios, todos competem pela mesma banda.
- **Solução**: limitar a 2-3 fetches concorrentes via fila (p-limit ou implementação manual).
- **Esforço**: 30min. **Risco**: nenhum.

### P5 — Estender `ai-preserve.sh` com 5 campos AiAgent
- **Problema**: campos novos de IA (`grokModel`, `qwenModel`, `lmModel`, etc) não são preservados em re-imports.
- **Local**: `deploy/voxzap-locktec/migration/ai-preserve.sh`.
- **Esforço**: 30min.

### P6 — Patch equivalente WebChat BH-on-transfer
- **Problema**: `socket.ts:690` (WebChat) ainda valida horário comercial em transferência manual entre filas.
- **Espelho do bug #5 já corrigido em `whatsappService.ts`**.
- **Esforço**: 30min.

### P7 — Unificar UI duplicada Verify Token
- **Problema**: campo "Verify Token" aparece em dois lugares na tela de Canais (modal de criação + edição), gerando confusão.
- **Esforço**: 1h.

### P8 — Cleanup `UsersQueues` órfãs em `migrate.py`
- **Problema**: re-importações deixam vínculos `UsersQueues` apontando para queues inexistentes.
- **Solução**: passo de cleanup no `migrate.py` que faz `DELETE FROM "UsersQueues" WHERE "queueId" NOT IN (SELECT id FROM "Queues")`.
- **Esforço**: 15min.


### P9 — Normalização em massa de números não-normalizados
- **Escopo** (medido em 2026-04-20 no banco Locktec, 27.973 contatos):
  - 20.515 celulares **sem o 9** (12 dígitos, local iniciando em 6-9) → precisam ganhar o 9
  - 927 colisões: o normalizado JÁ existe como outro contato (mesma pessoa, registros separados) → exige merge de tickets
  - 713 sem prefixo 55 (DDI faltando ou estrangeiros) → investigar
  - 1.980 tamanho inválido (< 12 ou > 13 dígitos) → dados sujos do ZPro
- **Função de referência**: `/app/server/lib/phone-utils.ts` → `normalizeBrazilianPhone()`.
- **Query de diagnóstico** (read-only, reexecutar antes de atuar):
  ```sql
  SELECT
    COUNT(*) FILTER (WHERE "isGroup"=false AND length(number)=13 AND number ~ '^55[1-9][0-9]9[0-9]{8}$') AS movel_com_9_ok,
    COUNT(*) FILTER (WHERE "isGroup"=false AND length(number)=12 AND number ~ '^55[1-9][0-9][2-5][0-9]{7}$') AS fixo_ok,
    COUNT(*) FILTER (WHERE "isGroup"=false AND length(number)=12 AND number ~ '^55[1-9][0-9][6-9][0-9]{7}$') AS movel_sem_9,
    COUNT(*) FILTER (WHERE "isGroup"=false AND number !~ '^55' AND number ~ '^[0-9]+$') AS sem_prefixo_55,
    COUNT(*) FILTER (WHERE "isGroup"=false AND length(number) NOT IN (12,13) AND number ~ '^[0-9]+$') AS tamanho_invalido
  FROM "Contacts";
  ```
- **Detecção de colisão** (CRÍTICO antes do UPDATE em massa):
  ```sql
  WITH n AS (
    SELECT id, number, substring(number,1,4) || '9' || substring(number,5,8) AS normalized
    FROM "Contacts"
    WHERE "isGroup"=false AND length(number)=12 AND number ~ '^55[1-9][0-9][6-9][0-9]{7}$'
  )
  SELECT n.id AS contato_desatualizado, n.number AS atual, n.normalized AS alvo,
         c.id AS contato_existente, c.name AS nome_existente
  FROM n JOIN "Contacts" c ON c.number = n.normalized AND c.id != n.id;
  ```
- **Plano de execução (janela de manutenção, 02h-04h):**
  1. `pg_dump` da tabela `Contacts` + `Tickets` antes de qualquer coisa
  2. Exportar CSV das 927 colisões para o cliente decidir regra de merge (padrão: manter o contato com mais tickets)
  3. Para os ~19.588 sem colisão: `UPDATE "Contacts" SET number = substring(number,1,4) || '9' || substring(number,5,8), "updatedAt"=NOW() WHERE id IN (...)` em lotes de 1000
  4. Para as 927 colisões: script que move tickets do descartado pro mantido e depois `DELETE` (ou `update` com flag `blocked=true` para preservar histórico)
  5. 713 sem DDI e 1.980 tamanho inválido: triagem manual ou marcar `blocked=true`
  6. Rodar a query de diagnóstico de novo para confirmar que `movel_sem_9 = 0`
- **Riscos**:
  - FK de `Tickets.contactId`, `Messages.contactId` é por `id` (não por `number`), então o UPDATE do campo `number` é seguro quanto a integridade relacional.
  - Mensagens in-flight durante o update podem criar contato novo com o número antigo → minimizar janela, fazer em horário de baixíssimo tráfego.
  - Constraint unique em `(tenantId, number)` bloqueia updates com colisão → por isso o passo de detecção prévia é obrigatório.
- **Esforço**: 4-6h (inclui backup, triagem, execução em lotes, validação). **Risco**: médio-alto (por isso só em janela dedicada).
- **Não fazer** enquanto o cliente estiver ativo em horário comercial.


### P10 — Logger do Express jogando JSON inteiro no log (voxzap-locktec-app) ✅ RESOLVIDO 2026-04-21
- **Problema**: o middleware de log do Express imprime o body completo da resposta JSON em cada request, incluindo respostas 304 (cache hit). Operadores fazem polling constante de `/api/users`, `/api/users/me/sound-preference`, `/api/users/me/signature` → 28 GB/dia de log.
- **Sintoma**: arquivo `/var/lib/docker/containers/<id>-json.log` cresce ~6 MB/min em horário comercial. Encheu disco em 3 dias (incidente 2026-04-20 14:00).
- **Patch aplicado** em `/opt/tenants/voxzap-locktec/source/server/index.ts` (backup `.bak.1776734362`, script idempotente em `/tmp/patch_index.py` na VPS):
  1. Skip body em 304s (cache hit, sem corpo útil)
  2. Skip prefixes: `/api/users/me/`, `/api/notifications`, `/api/tickets/has-pending`, `/api/settings/get/`
  3. Skip patterns regex: `/^\/api\/tickets\/\d+\/messages$/`, `/^\/api\/tickets\/\d+$/`
  4. Truncate body a 200 chars com indicador `[+NB]` mostrando bytes suprimidos
- **Deploy**: `npm start` produção roda `node dist/index.cjs` (bundle compilado, não tsx direto). Source NÃO é bind-mount (só `uploads`/`config` são). Foi necessário rebuild Docker: `docker compose build app && docker compose up -d app`. Build ~24s (vite client + esbuild server), restart ~12s downtime. Tag rollback: `voxzap-locktec-app:pre-p10-p22-1776734162`.
- **Validação pós-deploy** (60s sob tráfego baixo de feriado):
  - `GET /api/version 200 in 4ms :: {"version":"1.5.0",...[+3603B]` — body truncado a 200 chars + indicador `[+3603B]` ✅
  - 304s polling logam só status sem body (`GET /api/users/me/sound-preference 304 in 11ms`) ✅
  - avg 165 bytes/linha vs ~3KB+ antes → **94% redução**
  - Log file total = 4.2 KB para 5min uptime (vs MB-scale anteriormente)
- **Esforço real**: ~1h (incluindo rebuild). **Risco**: 0 (só log, app health Up sem erros críticos).

### P11 — psqlODBC antigo no planoclin-asterisk gerando 200 erros/seg ✅ MITIGADO 2026-04-21
- **Problema**: o Asterisk do planoclin usa driver psqlODBC desatualizado, que tenta consultar `pg_class.relhasoids` — coluna **removida no PostgreSQL 12**. Cada conexão ODBC nova dispara N introspections, todas falham, cada erro loga 1 KB de SQL (linha STATEMENT verbose).
- **Sintoma**: container `planoclin-asterisk-extdb` (PostgreSQL externo) gera 17 GB/dia de log com `ERROR: column c.relhasoids does not exist`.
- **Mitigação aplicada** (sem fix root cause): `ALTER SYSTEM SET log_min_error_statement = 'panic'` + `pg_reload_conf()` no extdb (user `asterisk` é superuser, não `postgres`). Suprime apenas o STATEMENT verbose; ERROR continua visível para debug futuro.
  ```
  docker exec planoclin-asterisk-extdb psql -U asterisk -d asterisk -c "ALTER SYSTEM SET log_min_error_statement = 'panic'"
  docker exec planoclin-asterisk-extdb psql -U asterisk -d asterisk -c "SELECT pg_reload_conf()"
  ```
  ⚠️ Multi-statement em uma única `-c` falha com `ALTER SYSTEM cannot run inside a transaction block` (psql implícito). Sempre rodar em chamadas separadas.
- **Validação pós-mitigação** (60s sob carga real):
  - 49 erros relhasoids ainda ocorrem (driver bug intacto)
  - **0 linhas STATEMENT** (era 100% das ERRORs com STATEMENT block antes) → **93% redução de bytes/erro** (~80 bytes/linha vs ~1.1 KB antes)
- **Solução root cause** (deferida): atualizar `odbc-postgresql`/`psqlODBC` para v13+ dentro do container `planoclin-asterisk`. Requer rebuild da imagem `voxcall-asterisk:latest` = território do **agente VoxCall**.
- **Coordenar com o agente do VoxCall** quando for atacar a causa real.


## Janela de Manutenção 2026-04-20 20:30 — Performance Tuning Pós-Cutover

Executado durante a primeira noite tranquila após go-live (servidor compartilhado eveo1: 80 CPUs / 64 GB / NVMe).

### Diagnóstico que motivou
- **Load average 7+ com 98% das CPUs ociosas**: containers da Locktec limitados a 2 CPUs (app) e 1 CPU (db) num host de 80 CPUs. Cliente reclamava de lentidão e o Docker barrava o app antes mesmo de pedir CPU pro host.
- **Estatísticas do PG zeradas**: `pg_stat_user_tables` mostrava `Tickets: 199 live` quando o real era `205.142`. Planner operava às cegas.
- **Erros `PrismaClientValidationError` em loop** no log do app: `prisma.tickets.findFirst({ where: { tenantId: 1, id: <NaN> } })` — handler `/api/tickets/:id/messages` recebia ID inválido e passava NaN pro Prisma.

### Ações executadas (todas em ~5min, downtime ~1min na recriação do compose)

#### P12 — VACUUM ANALYZE em todo o banco
```sql
VACUUM (VERBOSE, ANALYZE) "Tickets";    -- 205.142 rows reanalisadas
VACUUM (VERBOSE, ANALYZE) "Messages";   -- 1.326.637 rows reanalisadas
VACUUM ANALYZE;                          -- 100 tabelas, dead_total final = 3
```

#### P16 — 12 índices criados em FKs grandes sem cobertura
```sql
CREATE INDEX CONCURRENTLY idx_messages_wabamediaid_fk ON "Messages"("wabaMediaId") WHERE "wabaMediaId" IS NOT NULL;
CREATE INDEX CONCURRENTLY idx_tickets_difysessionid_fk ON "Tickets"("difySessionId") WHERE "difySessionId" IS NOT NULL;
CREATE INDEX CONCURRENTLY idx_tickets_typebotsessionid_fk ON "Tickets"("typebotSessionId") WHERE "typebotSessionId" IS NOT NULL;
CREATE INDEX CONCURRENTLY idx_tickets_threadid_fk ON "Tickets"("threadId") WHERE "threadId" IS NOT NULL;
CREATE INDEX CONCURRENTLY idx_tickets_runid_fk ON "Tickets"("runId") WHERE "runId" IS NOT NULL;
CREATE INDEX CONCURRENTLY idx_tickets_assistantid_fk ON "Tickets"("assistantId") WHERE "assistantId" IS NOT NULL;
CREATE INDEX CONCURRENTLY idx_tickets_chatgptorgid_fk ON "Tickets"("chatgptOrganizationId") WHERE "chatgptOrganizationId" IS NOT NULL;
CREATE INDEX CONCURRENTLY idx_webhooklogs_wamessageid_fk ON "WebhookLogs"("waMessageId") WHERE "waMessageId" IS NOT NULL;
CREATE INDEX CONCURRENTLY idx_webhooklogs_connectionid_fk ON "WebhookLogs"("connectionId") WHERE "connectionId" IS NOT NULL;
CREATE INDEX CONCURRENTLY idx_systemlogs_ticketid_fk ON "SystemLogs"("ticketId") WHERE "ticketId" IS NOT NULL;
CREATE INDEX CONCURRENTLY idx_systemlogs_contactid_fk ON "SystemLogs"("contactId") WHERE "contactId" IS NOT NULL;
CREATE INDEX CONCURRENTLY idx_systemlogs_userid_fk ON "SystemLogs"("userId") WHERE "userId" IS NOT NULL;
```

#### P17 — 15 índices nunca usados removidos (157 MB)
`messages_tenantid_status_createdat_idx`, `idx_message_quoted_id`, 3× `idx_logtickets_*`, `messages_tenantid_scheduledate_idx`, 2× `idx_webhooklogs_*`, 3× `idx_tickets_*`reply/chatflow, 3× `idx_systemlogs_*`, `idx_messageupserts_whatsappid_fk`.

#### P14 — pg_stat_statements ativo
Adicionado em `shared_preload_libraries` no compose, depois `CREATE EXTENSION pg_stat_statements;`. Coleta queries em produção pra análise futura.

#### P15 — Recursos de container expandidos
Compose `/opt/tenants/voxzap-locktec/docker-compose.yml` (backup `.bak.1776727786`):
- **app**: `mem_limit: 8g`, `cpus: 8.0`, `NODE_OPTIONS=--max-old-space-size=6144`, `UV_THREADPOOL_SIZE=16`
- **db**: `mem_limit: 16g`, `cpus: 16.0`, `shm_size: 4gb`
- Logging json-file 50m × 3 nos dois (substitui o paliativo do logrotate-host)

#### Tuning PG completo (via `command:` no compose)
```
shared_buffers=4GB                  effective_cache_size=12GB
work_mem=32MB                       maintenance_work_mem=1GB
max_connections=200                 random_page_cost=1.1   (NVMe)
effective_io_concurrency=200        max_worker_processes=16
max_parallel_workers=16             max_parallel_workers_per_gather=4
max_parallel_maintenance_workers=4  max_wal_size=4GB
min_wal_size=1GB                    wal_buffers=16MB
checkpoint_completion_target=0.9    default_statistics_target=200
shared_preload_libraries=pg_stat_statements
pg_stat_statements.max=10000        pg_stat_statements.track=top
jit=off   (PG16 default ativo, atrapalha OLTP latência)
log_min_duration_statement=2000     log_lock_waits=on
log_temp_files=10MB
```

#### P13 — Bug `prisma.tickets.findFirst({id: NaN})` corrigido
Dois patches no source `/opt/tenants/voxzap-locktec/source/`:
1. `server/repositories/ticket.repository.ts` — guard no início de `findById`:
   ```ts
   async findById(id: number, tenantId: number) {
     if (!Number.isFinite(id) || id <= 0) return null;   // <<< NEW
     const ticket: any = await prisma.tickets.findFirst(...);
   ```
2. `server/routes.ts` handler `GET /api/tickets/:id/messages` — fail-fast 400:
   ```ts
   const ticketId = parseInt(req.params.id);
   if (!Number.isFinite(ticketId) || ticketId <= 0) {     // <<< NEW
     return res.status(400).json({ message: "ID de ticket invalido" });
   }
   ```
Aplicar `docker compose build app && docker compose up -d` reconstrói imagem com patches. Backup `.bak.1776727786` em ambos arquivos.

### Resultado
- Load: 7,08 → **1,82**
- App CPU: 80% (de 2) → 0-3% (de 8)
- DB CPU: 100% (de 1) → 0-4% (de 16)
- Erros Prisma: vários/min → **0**
- Query mais lenta (mean): desconhecida → **2,3 ms**
- Mídia/imagens carregam mais rápido (índice `idx_messages_wabamediaid_fk` cobre 475 MB de tabela)

### Divisão de recursos do servidor (acordada com o user)
| Sistema | CPUs | RAM | Status |
|---|---|---|---|
| VoxZap Locktec (app+db) | 24 | 24 GB | **aplicado** |
| VoxCall (planoclin + voxtel) | 40 | 32 GB | reservado, não aplicado (do agente VoxCall) |
| Sistema operacional + folga | 16 | 8 GB | livre |

### Pendências REMOVIDAS da lista P1-P11 após esta janela
- ~~P12 P14 P15 P16 P17 P19~~ — todas executadas
- **P13** — corrigido (bug Prisma findFirst com NaN)

### Pendências que continuam abertas
P1 (sockets rooms), P2 (cache disco mídia), P3 (opus→mp3 ffmpeg), P4 (throttle prefetch), P5 (ai-preserve 5 campos), P6 (WebChat BH-on-transfer), P7 (UI Verify Token), P8 (cleanup UsersQueues), P9 (normalização massa 20.515 celulares), P10 (logger Express body), P11 (psqlODBC planoclin), P18 (mídias→S3), P20 (Node cluster mode).

### Decisão sobre P20 (Node cluster mode)
**Adiada** — com app a 0-3% CPU dos 8 disponíveis após o tuning, não há justificativa pra adicionar a complexidade de múltiplos workers + sticky sessions socket.io agora. Reavaliar se algum pico futuro saturar 1 worker.

---

## 📊 Sessão 2026-04-21 — Pendências P1-P9 (Phases 2-3)

### ✅ COMPLETADO
- **P2+P3+P4** (rebuild #1, ~10s downtime, tag `pre-p2p3p4`):
  - P2: cache disco WABA mídia em `/app/uploads/waba-cache/` (server/routes.ts handler `/api/media`)
  - P3: opus→mp3 ffmpeg conversion no upload
  - P4: throttle prefetch frontend (max 3 concorrentes em atendimento.tsx)
- **P1** (rebuild #2, 57s downtime, tag `pre-p1`):
  - socket.ts: room `admins:tenantId` para perfis admin/super/superadmin
  - `broadcastNewMessage`/`broadcastTicketUpdate` async com lookup ticket → emit granular `ticket:`/`user:`/`queue:`/`admins:`
  - 0 erros, 2 reconexões saudáveis pós-rebuild
  - ⚠️ Patch só no Locktec (não foi pro upstream). Frontend nunca filtrado — admins recebiam toast de tudo, e operador que dependesse só do `data.ticketUserId` não tinha o campo.
- **P1-frontend / NOTIF_GRANULAR_ROUTING upstream** (2026-04-21, tag `pre-notif-routing`):
  - Upstream `server/websocket/socket.ts`: refeito `broadcastNewMessage` async com payload enriquecido (`ticketUserId`, `ticketQueueId`) + admin room idêntica.
  - Upstream `client/src/components/global-notification-handler.tsx`: filtro `data.ticketUserId === user.id || isAdmin` antes de toast/beep. Tickets pendentes silenciosos (exceto admin).
  - Locktec: drop-in replacement (substitui o P1 anterior). `broadcastTicketUpdate` volta a tenant-wide (sem regressão UX — driva apenas refresh silencioso de listas).
  - Marcador `NOTIF_GRANULAR_ROUTING` nos dois arquivos.
- **P7** (rebuild #3, 19s downtime, tag `pre-p7`):
  - 5 inputs read-only duplicados de Verify Token removidos dos modais (WABA/IG/FB create + IG/WABA edit)
  - 1 banner global adicionado no topo de canais.tsx (`text-global-verify-token`)
  - Campo admin de DEFINIR token (linha 3462) preservado — é o canônico
  - Bundle servido confirmado: 1 banner, 0 duplicatas
- **P8** (DB op pura, sem rebuild):
  - 0 órfãs encontradas em `UsersQueues` (cleanup defensivo OK pra futuras re-importações)
  - 237 bindings válidos confirmados

### ⏭️ DEFERIDOS
- **P5** (ai-preserve.sh): script vive fora do VPS (workstation do user), atualizar manualmente quando necessário
- **P6** (WebChat BH-on-transfer): bug não reproduzível na linha referenciada (socket.ts:690 hoje é loop bot, não tem BH check). Lógica BH vive em `ai-agent.service.ts:977/1560/1954`. Sem repro claro de problema, defer

### ✅ P9 COMPLETADO (2026-04-21)
**Normalização nono dígito em massa — surgical fix com audit trail completo**

Survey antes:
- 27.985 contatos tenant 1
- 20.378 precisavam fix (12-dig BR mobile sem 9)
- 930 colisões (12-dig + 13-dig já existindo)
- Tabelas dependentes: 11 mapeadas, só Messages com volume relevante

Execução (3 transações):
1. **Setup audit/backup**: criada coluna `Contacts.numberOriginal varchar` + tabelas `Contacts_collision_p9` (930 rows pra revisão humana), `Contacts_bak_p9_1776733763` (19.448), `Messages_bak_p9_1776733763` (1.050)
2. **UPDATE transacional canônico**:
   - `Contacts`: 19.448 normalizados (regex `^55[1-9][0-9][6-9][0-9]{7}$`, ancorado), `numberOriginal` = valor antigo
   - `Messages.remoteJid`: 1.050 normalizados (regex `^...@`, ancorado)
   - 0 audit violations confirmadas (`number == numberOriginal[:4] || '9' || numberOriginal[5:]`)
3. **Cleanup Upserts** (TRUNCATE em transação após backup metadata):
   - `ContactUpserts`: 8.499 → 0 (backup `ContactUpserts_bak_p9_1776734162`)
   - `MessageUpserts`: 209.016 → 0 (backup `MessageUpserts_bak_p9_1776734162`)
   - Motivo: tabelas eram fila de dedup idle 24h+; código só referencia em `contact-dedup.service.ts:466` via FK `contactId` (não via `remoteJid`); cutover parou de alimentá-las; futuras webhooks repopulam fresh

NÃO tocado:
- `Whatsapps.number/phone` — 4 canais (0800, fixos comerciais, Voxtel) — risco de quebrar conexão WABA ativa
- 930 colisões em `Contacts_collision_p9` — exigem decisão humana caso-a-caso (merge ou skip)
- 1.293 contatos com >13 dig pré-existentes (lixo da migração ZPro com múltiplos números concatenados em 1 row, samples tipo `5585988633028 86999911912 86999911912`)

⚠️ Lição aprendida — **bug regex sem âncora final**:
- Tentativa inicial de UPDATE em ContactUpserts/MessageUpserts usou regex `'^55[1-9][0-9][6-9][0-9]{7}'` SEM `$` ou `@` no fim → matchou tanto 12-dig (correto) quanto 13-dig (incorreto), inserindo "9" em rows já corretas. Corrupção: ~1.958 ContactUpserts + ~18.780 MessageUpserts (puras, fora @lid/@g.us legítimos)
- Resolução: TRUNCATE eliminou tudo (corrupção + lixo pré-existente do import) numa tacada; backup metadata preservado; tabelas se repopulam automaticamente
- **Aprendizado canônico**: SEMPRE ancorar regex `^...$` ou `^...@` ao normalizar números — nunca usar prefix-match sem terminador

Estado pós-P9:
- Contacts: 27.985 (intacto)
- Messages: 1.325.999 (intacto)
- Tickets: 205.152 (intacto)
- App: 0 erros críticos pós-fix

### ⚠️ NOVO ACHADO (não bloqueante, fora do escopo de hoje)
- **VoxHub Word Cloud**: tabela `word_cloud_data` tem índice composto `idx_wordcloud_word_channel_tenant_period` mas marcado como `is_unique=false`. Código em `routes.ts` faz `INSERT ... ON CONFLICT (word, channel, tenantId, period)` que falha com Postgres `42P10`. ~30 prisma:errors/min sob carga de mensagens. **Mensagens são salvas com sucesso** — só a analítica VoxHub falha. Solução: `CREATE UNIQUE INDEX` substituindo o índice atual. P22 sugerido para próxima janela.

### Tags rollback ativas no VPS
```
voxzap-locktec-app:latest          # P1+P2+P3+P4+P7
voxzap-locktec-app:pre-p7          # P1+P2+P3+P4 (sem consolidação verify token)
voxzap-locktec-app:pre-p1          # P2+P3+P4 (sem socket rooms granulares)
voxzap-locktec-app:pre-p2p3p4      # cutover original
```

### Arquivos backup VPS
- `/opt/tenants/voxzap-locktec/source/server/routes.ts.bak.1776731296` (P2+P3)
- `/opt/tenants/voxzap-locktec/source/client/src/pages/atendimento.tsx.bak.1776731296` (P4)
- `/opt/tenants/voxzap-locktec/source/server/websocket/socket.ts.bak.1776731701` (P1)
- `/opt/tenants/voxzap-locktec/source/client/src/pages/canais.tsx.bak.1776732349` (P7)

---

### ✅ P22 — VoxHub Word Cloud unique constraint (2026-04-21)

**Bug**: `word_cloud_data` index `idx_wordcloud_word_channel_tenant_period` era btree não-único e nem incluía `queueName`. Código em `voxhub.service.ts:801-805` usa `INSERT ... ON CONFLICT (word, channel, "tenantId", COALESCE("queueName", ''), period)` — expressão com COALESCE que precisa de matching unique constraint.

**Fix aplicado** (sem downtime, tabela vazia):
```sql
CREATE UNIQUE INDEX idx_wordcloud_unique_upsert
ON word_cloud_data (word, channel, "tenantId", (COALESCE("queueName", '')), period);
DROP INDEX idx_wordcloud_word_channel_tenant_period;
```

**Validação**: 2 INSERTs com mesma chave colapsaram em 1 row com `frequency=6` (soma 1+5). Matematicamente correto.
