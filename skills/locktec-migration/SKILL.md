---
name: locktec-migration
description: Migração completa do cliente Locktec (ZPro) para VoxZap. Inclui clonagem do banco PostgreSQL (89 tabelas, 1.2M+ mensagens, 183K tickets, 26K contatos), transferência de 13GB de mídias (57K arquivos), mapeamento de schemas ZPro→VoxZap, ajuste de tenantId, mediaUrl, sequences, e validação end-to-end. Use quando for executar a migração real do cliente Locktec para produção VoxZap.
---

# Migração Locktec (ZPro) → VoxZap — Skill Completo

Skill para execução da migração completa do cliente Locktec do sistema ZPro para o VoxZap.
Já foi executado com sucesso na homologação (Tasks #55 e #56). Este documento serve como guia definitivo para a migração real em produção.

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
- **VPS**: `voxzaplocktec.voxserver.app.br`, porta SSH: `22`, user: `root`
- **PostgreSQL**: container Docker `postgresql`, porta `5432`, user: `zpro`, db: `postgres`
- **Mídias**: `/home/deployzdg/zpro.io/backend/public/2/` (tenant 2)
- **Sistema**: ZPro original com Sequelize
- **tenantId dos dados**: `2`

### VoxZap — Destino
- **VPS Homologação**: `voxtel.voxzap.app.br`, porta SSH: `22300`, user: `root`
- **PostgreSQL**: externo em `voxzap.voxserver.app.br:5432`, user: `zpro`, db: `postgres`
- **Mídias**: `/opt/voxzap/uploads/` (host) → `/app/uploads` (container Docker `voxzap-app`)
- **DATABASE_URL**: `postgresql://zpro:%2F62qQgAlvjG2q7Q2bAX9Od1lwya3VdL5us4UyanT1pQ%3D@voxzap.voxserver.app.br:5432/postgres`
- **tenantId destino**: `1`

> **IMPORTANTE para produção**: Substituir os dados do servidor destino pelos dados do servidor VoxZap de produção do cliente.

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

## Tabelas a NÃO copiar da Locktec

| Tabela | Motivo |
|--------|--------|
| `Whatsapps` | Preservar canal VoxZap WABA |
| `Tenants` | Preservar tenant VoxTel |
| `AiAgents`, `AiAgentChunks`, `AiAgentFiles`, `AiAgentRoutes` | Preservar configuração IA |
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
ssh -o StrictHostKeyChecking=no root@voxzaplocktec.voxserver.app.br 'echo OK'
```

### Passo 2 — Transferir mídias com rsync

```bash
# No VPS destino (VoxZap), executar rsync em background
nohup rsync -avz --progress \
  --exclude='baileysBackup/' \
  -e 'ssh -o StrictHostKeyChecking=no' \
  root@voxzaplocktec.voxserver.app.br:/home/deployzdg/zpro.io/backend/public/2/ \
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
  -d '{"email":"superadmin@voxtel.biz","password":"<senha>"}' | jq -r '.token')

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

## Resultado da Homologação (Referência)

Executada com sucesso em março/2026:
- **Task #55**: Clonagem do banco — 1.227.241 Messages, 183.689 Tickets, 26.816 Contacts importados
- **Task #56**: Transferência de mídias — 57.382 arquivos, 13GB, todas validadas com HTTP 200
- **Tempo total**: ~45 minutos (20 min DB + 10 min rsync + 15 min validação)
- **Disco usado**: 39GB de 75GB (52%)
