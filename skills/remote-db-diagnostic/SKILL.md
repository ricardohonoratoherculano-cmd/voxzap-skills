---
name: remote-db-diagnostic
description: Diagnóstico remoto de performance de banco de dados PostgreSQL em VPS de clientes. Use quando um cliente reportar instabilidade, lentidão, envio de mensagens falhando, load average alto, ou muitas conexões ao banco. Inclui procedimento completo via SSH para identificar e corrigir problemas de índices, conexões, queries lentas, e performance geral do PostgreSQL.
---

# Diagnóstico Remoto de Performance PostgreSQL — Skill Completa

Skill para diagnóstico e correção de problemas de performance em bancos de dados PostgreSQL de clientes que rodam o sistema VoxZap/ZPro em VPS próprias.

## Quando Usar

- Cliente reporta lentidão no sistema
- Instabilidade para enviar/receber mensagens
- Load average alto na VPS
- Muitas conexões abertas ao banco de dados
- Queries lentas travando o sistema
- VPS com CPU ou memória alta por causa do PostgreSQL

## Pré-requisitos

Solicitar ao cliente:
1. **IP/hostname da VPS** (ex: `cliente.voxserver.app.br`)
2. **Porta SSH** (geralmente 22)
3. **Usuário SSH** (geralmente `root`)
4. **Senha SSH**
5. **Nome do container PostgreSQL** (geralmente `postgresql`)
6. **Usuário do PostgreSQL** (geralmente `zpro`)
7. **Nome do banco** (geralmente `postgres`)

## Conexão SSH

Sempre usar `sshpass` para conexão não-interativa:

```bash
sshpass -p 'SENHA' ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p PORTA root@HOST "COMANDO"
```

## Procedimento de Diagnóstico — 6 Etapas

### Etapa 1: Saúde Geral da VPS

```bash
echo '=== UPTIME/LOAD ===' && uptime
echo '=== MEMORY ===' && free -h
echo '=== DISK ===' && df -h /
echo '=== DOCKER CONTAINERS ===' && docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
echo '=== TOP CPU PROCESSES ===' && ps aux --sort=-%cpu | head -15
```

**O que procurar:**
- Load average > número de CPUs = problema
- Muitos processos `postgres:` consumindo CPU = queries sem índice
- Memória swap em uso = sistema sob pressão
- Container PostgreSQL reiniciando = crash do banco

### Etapa 2: Conexões do PostgreSQL

```sql
-- Total de conexões
SELECT count(*) as total_connections FROM pg_stat_activity;

-- Conexões por estado
SELECT state, count(*) FROM pg_stat_activity GROUP BY state ORDER BY count DESC;

-- Conexões por aplicação
SELECT application_name, count(*) FROM pg_stat_activity GROUP BY application_name ORDER BY count DESC;

-- Queries rodando há mais de 30 segundos
SELECT pid, now() - query_start AS duration, state, left(query, 200) AS query
FROM pg_stat_activity
WHERE state != 'idle' AND query_start IS NOT NULL AND now() - query_start > interval '30 seconds'
ORDER BY duration DESC LIMIT 10;
```

**O que procurar:**
- Mais de 100 conexões = connection pooling inexistente ou leak
- Muitas conexões em estado `active` = queries lentas
- Queries rodando há minutos = falta de índice ou deadlock

### Etapa 3: Tabelas com Sequential Scans Excessivos (CRÍTICO)

Esta é a query mais importante — identifica tabelas sem índices adequados:

```sql
SELECT schemaname, relname as table_name, seq_scan, seq_tup_read, idx_scan, n_live_tup as row_count
FROM pg_stat_user_tables
WHERE seq_scan > 100 AND (idx_scan IS NULL OR idx_scan < seq_scan)
ORDER BY seq_tup_read DESC
LIMIT 30;
```

**Interpretação:**
- `seq_scan` alto + `idx_scan` baixo/zero = tabela sendo varrida inteira (FULL TABLE SCAN)
- `seq_tup_read` > 1 bilhão = impacto severo na performance
- Tabelas pequenas com milhões de `seq_scan` = consultadas em loop sem índice

**Tabelas historicamente problemáticas no ZPro (sem índices no código original):**

| Tabela | Colunas para indexar | Impacto |
|--------|---------------------|---------|
| TicketProtocols | ticketId, tenantId | CRÍTICO — bilhões de seq_tup_read |
| UsersQueues | queueId | ALTO — milhões de seq_scans |
| TicketEvaluations | ticketId | ALTO — centenas de milhões de seq_tup_read |
| ContactWallets | tenantId | ALTO — dezenas de milhões de seq_scans |
| TicketNotes | ticketId, tenantId | MÉDIO |
| UserWhatsapps | userId, whatsappId | MÉDIO |
| MessagesOffLine | ticketId, contactId | MÉDIO |
| FastReply | tenantId | MÉDIO |
| Kanbans | tenantId | BAIXO |
| Reasons | tenantId | BAIXO |
| TicketActions | tenantId, active | BAIXO |

### Etapa 4: Verificar Índices Existentes

```sql
-- Ver todos os índices de uma tabela específica
SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'NomeDaTabela';

-- Índices mais usados (os que estão funcionando)
SELECT indexrelname, idx_scan, pg_size_pretty(pg_relation_size(indexrelid)) as size
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC LIMIT 20;

-- Tabelas com zero índices (só PK)
SELECT t.relname as table_name, t.n_live_tup as rows, t.seq_scan
FROM pg_stat_user_tables t
LEFT JOIN pg_stat_user_indexes i ON t.relname = i.relname
WHERE t.seq_scan > 0
GROUP BY t.relname, t.n_live_tup, t.seq_scan
HAVING count(i.indexrelname) <= 1
ORDER BY t.seq_scan DESC LIMIT 20;
```

### Etapa 5: Tamanho das Tabelas

```sql
SELECT relname as table_name, n_live_tup as row_count,
       pg_size_pretty(pg_total_relation_size(schemaname||'.'||quote_ident(relname))) as total_size
FROM pg_stat_user_tables
ORDER BY n_live_tup DESC LIMIT 20;
```

### Etapa 6: Slow Queries (se pg_stat_statements disponível)

```sql
SELECT calls, total_exec_time::bigint as total_ms, mean_exec_time::int as avg_ms,
       rows, left(query, 200) as query
FROM pg_stat_statements
ORDER BY total_exec_time DESC LIMIT 20;
```

Se não disponível (erro), pular — nem todos os clientes têm esta extensão.

## Correção — Criar Índices

### Template de Criação de Índices

Sempre usar `CREATE INDEX IF NOT EXISTS` para idempotência:

```sql
-- Índice simples em uma coluna
CREATE INDEX IF NOT EXISTS "idx_{tabela}_{coluna}" ON "{Tabela}" ("{coluna}");

-- Índice composto (multi-coluna)
CREATE INDEX IF NOT EXISTS "idx_{tabela}_{col1}_{col2}" ON "{Tabela}" ("{col1}", "{col2}");
```

### Script Padrão Completo para ZPro

Este script cria TODOS os índices que o ZPro original não possui e que causam problemas de performance. Executar dentro do container PostgreSQL:

```sql
-- TicketProtocols (CRÍTICO)
CREATE INDEX IF NOT EXISTS "idx_ticketprotocols_ticketid" ON "TicketProtocols" ("ticketId");
CREATE INDEX IF NOT EXISTS "idx_ticketprotocols_tenantid" ON "TicketProtocols" ("tenantId");
CREATE INDEX IF NOT EXISTS "idx_ticketprotocols_tenantid_ticketid" ON "TicketProtocols" ("tenantId", "ticketId");

-- TicketNotes
CREATE INDEX IF NOT EXISTS "idx_ticketnotes_ticketid" ON "TicketNotes" ("ticketId");
CREATE INDEX IF NOT EXISTS "idx_ticketnotes_tenantid" ON "TicketNotes" ("tenantId");
CREATE INDEX IF NOT EXISTS "idx_ticketnotes_tenantid_ticketid" ON "TicketNotes" ("tenantId", "ticketId");

-- TicketEvaluations (já tem tenantId e userId)
CREATE INDEX IF NOT EXISTS "idx_ticketevaluations_ticketid" ON "TicketEvaluations" ("ticketId");
CREATE INDEX IF NOT EXISTS "idx_ticketevaluations_tenantid_ticketid" ON "TicketEvaluations" ("tenantId", "ticketId");

-- UsersQueues
CREATE INDEX IF NOT EXISTS "idx_usersqueues_queueid" ON "UsersQueues" ("queueId");

-- ContactWallets
CREATE INDEX IF NOT EXISTS "idx_contactwallets_tenantid" ON "ContactWallets" ("tenantId");

-- UserWhatsapps
CREATE INDEX IF NOT EXISTS "idx_userwhatsapps_userid" ON "UserWhatsapps" ("userId");
CREATE INDEX IF NOT EXISTS "idx_userwhatsapps_whatsappid" ON "UserWhatsapps" ("whatsappId");
CREATE INDEX IF NOT EXISTS "idx_userwhatsapps_userid_whatsappid" ON "UserWhatsapps" ("userId", "whatsappId");

-- MessagesOffLine
CREATE INDEX IF NOT EXISTS "idx_messagesoffline_ticketid" ON "MessagesOffLine" ("ticketId");
CREATE INDEX IF NOT EXISTS "idx_messagesoffline_contactid" ON "MessagesOffLine" ("contactId");

-- FastReply
CREATE INDEX IF NOT EXISTS "idx_fastreply_tenantid" ON "FastReply" ("tenantId");
CREATE INDEX IF NOT EXISTS "idx_fastreply_tenantid_userid" ON "FastReply" ("tenantId", "userId");

-- Kanbans
CREATE INDEX IF NOT EXISTS "idx_kanbans_tenantid" ON "Kanbans" ("tenantId");

-- Reasons
CREATE INDEX IF NOT EXISTS "idx_reasons_tenantid" ON "Reasons" ("tenantId");

-- TicketActions
CREATE INDEX IF NOT EXISTS "idx_ticketactions_tenantid" ON "TicketActions" ("tenantId");
CREATE INDEX IF NOT EXISTS "idx_ticketactions_tenantid_active" ON "TicketActions" ("tenantId", "active");
```

### Comando SSH para Aplicação Remota

```bash
sshpass -p 'SENHA' ssh -o StrictHostKeyChecking=no -p PORTA root@HOST \
  "docker exec CONTAINER psql -U USUARIO -d BANCO -c \"SQL_AQUI\""
```

**Nota:** Escapar aspas duplas dentro de SQL com `\\\"`.

## Verificação Pós-Correção

### Checar se índices foram criados

```sql
SELECT indexrelname, relname FROM pg_stat_user_indexes
WHERE indexrelname LIKE 'idx_%'
ORDER BY relname;
```

### Resetar estatísticas e monitorar

```sql
SELECT pg_stat_reset();
```

Esperar 1-2 minutos e verificar:

```sql
SELECT relname, seq_scan, idx_scan, seq_tup_read
FROM pg_stat_user_tables
WHERE relname IN ('TicketProtocols','TicketNotes','TicketEvaluations','UsersQueues','ContactWallets','UserWhatsapps','MessagesOffLine','FastReply','Kanbans','Reasons','TicketActions')
ORDER BY seq_tup_read DESC;
```

**Resultado esperado:** `idx_scan` deve ser significativamente maior que `seq_scan` para as tabelas corrigidas.

### Monitorar load average

```bash
uptime
```

**Resultado esperado:** Load average deve reduzir em 2-5 minutos após a aplicação dos índices.

## Passo Crítico: VACUUM ANALYZE (SEMPRE executar)

Após criar índices, o PostgreSQL pode continuar fazendo varreduras sequenciais se as estatísticas internas estiverem desatualizadas. O `n_live_tup` pode mostrar valores absurdamente baixos (ex: 428 quando a tabela tem 1.2M registros), fazendo o planner ignorar os índices.

**Sintoma:** Índices criados mas `seq_scan` continua alto e `idx_scan` continua zero.

**Diagnóstico rápido:**
```sql
SELECT relname, n_live_tup, n_dead_tup, last_vacuum, last_autovacuum, last_analyze
FROM pg_stat_user_tables
WHERE relname IN ('Messages','Tickets','Contacts','ContactTags','LogTickets')
ORDER BY n_live_tup DESC;
```

Se `n_live_tup` parecer muito baixo comparado ao tamanho real da tabela, executar:

```sql
VACUUM ANALYZE "Messages";
VACUUM ANALYZE "Tickets";
VACUUM ANALYZE "Contacts";
VACUUM ANALYZE "ContactTags";
VACUUM ANALYZE "Settings";
VACUUM ANALYZE "UsersQueues";
VACUUM ANALYZE "ContactWallets";
VACUUM ANALYZE "Queues";
VACUUM ANALYZE "Tenants";
VACUUM ANALYZE "Whatsapps";
```

**Executar VACUUM ANALYZE é obrigatório após criar índices.** Sem isso, os índices podem não ser usados.

## Passo Crítico: Restart do Backend (PM2)

O backend Node.js (ZPro) geralmente roda via PM2 como usuário `deployzdg`. Após dias rodando, acumula memória e conexões idle.

**Verificar PM2:**
```bash
su - deployzdg -c 'pm2 list'
```

**Reiniciar backend:**
```bash
su - deployzdg -c 'pm2 restart zpro-backend'
```

**Por que reiniciar:** Libera conexões PostgreSQL acumuladas (pode cair de 30+ para 9), libera memória (de ~700MB para ~270MB), e força reconexões frescas que usarão as estatísticas atualizadas do banco.

**Verificar logs após restart:**
```bash
su - deployzdg -c 'pm2 logs zpro-backend --lines 20 --nostream'
```

## Procedimento Completo Resumido (8 Etapas)

1. Conectar via SSH
2. Verificar `uptime`, `nproc`, `free -h` e `docker ps`
3. Analisar `pg_stat_user_tables` (seq_scans excessivos)
4. Criar índices faltantes com `CREATE INDEX IF NOT EXISTS`
5. **Executar VACUUM ANALYZE** em todas as tabelas pesadas
6. **Verificar e ajustar configuração do PostgreSQL** (shared_buffers, work_mem, etc.) — ver seção "Configuração inadequada do PostgreSQL"
7. **Reiniciar container PostgreSQL** (`docker restart postgresql`) se configuração foi alterada
8. **Reiniciar backend** via `pm2 restart zpro-backend` (como deployzdg)
9. Resetar stats com `pg_stat_reset()` e monitorar load por 2-5 minutos

## Problemas Adicionais Comuns

### Connection Leak (muitas conexões idle)
- Verificar se o backend tem connection pooling
- Verificar se não há conexões órfãs
- Matar conexões idle antigas:
```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle' AND query_start < now() - interval '1 hour';
```

### Tabela inchada (bloat)
```sql
SELECT relname, n_dead_tup, n_live_tup,
       round(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) as dead_pct
FROM pg_stat_user_tables
WHERE n_dead_tup > 10000
ORDER BY n_dead_tup DESC LIMIT 10;
```

Se `dead_pct` > 20%, executar VACUUM:
```sql
VACUUM ANALYZE "NomeDaTabela";
```

### Configuração inadequada do PostgreSQL (MUITO COMUM)

O PostgreSQL instalado via Docker geralmente vem com configurações padrão (shared_buffers=128MB, work_mem=4MB), independente do hardware da VPS. Isso causa alto consumo de CPU pelos IO Workers e lentidão generalizada.

**Diagnóstico:**
```sql
SELECT name, setting, unit, source FROM pg_settings
WHERE name IN ('shared_buffers','work_mem','maintenance_work_mem','effective_cache_size','max_connections','wal_buffers','random_page_cost','max_wal_size','io_method','io_workers')
ORDER BY name;
```

```bash
# Verificar hardware
nproc && free -h | head -2
# Verificar IO workers consumindo CPU (PG 17+)
ps aux | grep 'postgres: io worker' | grep -v grep
```

**Sintoma clássico:** `shared_buffers = 128MB` em VPS com 16GB+ de RAM, IO Workers (`postgres: io worker`) consumindo 10-15% de CPU cada continuamente.

**Tabela de referência para tuning:**

| Parâmetro | Fórmula | Exemplo (48GB RAM, 12 CPUs, SSD) |
|-----------|---------|-----------------------------------|
| shared_buffers | 8-10% da RAM (máx ~8GB) | 4GB |
| effective_cache_size | 65-70% da RAM | 32GB |
| work_mem | RAM / max_connections / 4 | 32MB |
| maintenance_work_mem | RAM / 80 | 512MB |
| wal_buffers | 3% de shared_buffers (máx 64MB) | 64MB |
| random_page_cost | 1.1 para SSD, 4.0 para HDD | 1.1 |
| max_wal_size | 2-4GB | 2GB |
| min_wal_size | 512MB-1GB | 512MB |
| checkpoint_completion_target | 0.9 | 0.9 |

**Como aplicar:**

1. Localizar o arquivo de configuração:
```sql
SHOW config_file;
```

2. Adicionar configurações no final do `postgresql.conf`:
```bash
docker exec CONTAINER bash -c 'cat >> /CAMINHO/postgresql.conf << EOF

# === TUNING VoxZap (XGB RAM, Y CPUs, SSD) - DATA ===
shared_buffers = 4GB
effective_cache_size = 32GB
work_mem = 32MB
maintenance_work_mem = 512MB
wal_buffers = 64MB
random_page_cost = 1.1
checkpoint_completion_target = 0.9
max_wal_size = 2GB
min_wal_size = 512MB
EOF
'
```

3. Reiniciar o container PostgreSQL (breve interrupção ~5s):
```bash
docker restart postgresql
```

4. Reiniciar o backend para reconectar:
```bash
su - deployzdg -c 'pm2 restart zpro-backend'
```

5. Verificar se as configurações foram aplicadas:
```sql
SELECT name, setting, unit FROM pg_settings
WHERE name IN ('shared_buffers','work_mem','effective_cache_size','maintenance_work_mem','wal_buffers','random_page_cost','max_wal_size')
ORDER BY name;
```

6. Verificar IO workers após tuning:
```bash
ps aux | grep 'postgres: io worker' | grep -v grep
```

**Resultado esperado:** CPU dos IO Workers cai de ~12% para ~1% cada; load average reduz significativamente em 2-5 minutos.

### Arquivo .env do Backend Ausente

O backend ZPro usa `dotenv` para carregar variáveis do arquivo `.env` no diretório `/home/deployzdg/zpro.io/backend/`. Se esse arquivo não existir, o código usa defaults hardcoded (senha `"postgres"` em vez da real).

**Sintoma:** `password authentication failed for user "postgres"` nos logs do PM2, mesmo que o usuário do banco seja `zpro`.

**Diagnóstico:**
```bash
ls -la /home/deployzdg/zpro.io/backend/.env
```

**Correção:** Se o `.env` estiver em outro local (ex: `/root/.env`), copiar:
```bash
cp /root/.env /home/deployzdg/zpro.io/backend/.env
chown deployzdg:deployzdg /home/deployzdg/zpro.io/backend/.env
su - deployzdg -c 'pm2 restart zpro-backend'
```

**Verificação:** Após restart, confirmar que conectou:
```bash
curl -s -o /dev/null -w "HTTP %{http_code}" http://localhost:3000
docker exec postgresql psql -U zpro -d postgres -c "SELECT state, count(*) FROM pg_stat_activity WHERE usename = 'zpro' GROUP BY state;"
```

### Container reiniciando
```bash
docker logs --tail 50 postgresql
```

## Matriz de Cobertura de Índices

Tabelas que já possuíam índices adequados (NÃO precisaram de novos):

| Tabela | Índices já existentes | Observação |
|--------|----------------------|------------|
| Settings | settings_tenant_idx, settings_tenant_key_idx | Cobertura completa por tenantId e key |
| ChatFlow | idx_chatflow_tenantid, idx_chatflow_tenantid_isdeleted, idx_chatflow_userid_fk, idx_chatflow_lastuserid_fk | Cobertura completa |
| Notifications | notifications_tenantid_createdat_idx, notifications_tenantid_isread_idx, notifications_tenantid_userid_idx | Cobertura completa |
| PrivateMessage | privatemessage_tenantid_groupid_idx, privatemessage_tenantid_read_idx, privatemessage_tenantid_receiverid_idx, privatemessage_tenantid_senderid_idx | Cobertura completa |
| UserPushSubscriptions | userpushsubscriptions_tenantid_userid_idx | Cobertura completa |
| ApiConfigs | idx_apiconfigs_tenantid, idx_apiconfigs_sessionid_fk, idx_apiconfigs_userid_fk | Cobertura completa |

Tabelas do plan original que não puderam receber certos índices (coluna inexistente):

| Tabela | Índice planejado | Motivo de exclusão |
|--------|-----------------|-------------------|
| UsersQueues | tenantId | Tabela NÃO possui coluna tenantId (apenas userId, queueId) |
| LicenseRequestLogs | tenantId | Tabela NÃO possui coluna tenantId (apenas licenseCode, responseData) |

## Arquivos Relevantes no VoxZap

| Arquivo | Propósito |
|---------|-----------|
| `prisma/schema.prisma` | Schema com todos os @@index definidos |
| `prisma/migrations/20260320_add_performance_indexes/migration.sql` | SQL de todos os índices de performance |

## Histórico de Clientes Diagnosticados

| Data | Cliente | Host | Problema | Solução |
|------|---------|------|----------|---------|
| 2026-03-20 | LockTec | voxzaplocktec.voxserver.app.br:22 | Load avg 9.37, 8.7B seq_tup_read em TicketProtocols, shared_buffers=128MB (padrão) em VPS com 47GB RAM, IO Workers consumindo ~12% CPU cada, .env do backend ausente | (1) 21 índices criados; (2) VACUUM ANALYZE em tabelas pesadas (Messages tinha stats desatualizadas: n_live_tup=428 vs real 1.2M); (3) .env restaurado de /root para /home/deployzdg/zpro.io/backend/; (4) Tuning PG: shared_buffers 128MB→4GB, effective_cache_size 4GB→32GB, work_mem 4MB→32MB, maintenance_work_mem 64MB→512MB, wal_buffers 4MB→64MB, random_page_cost 4→1.1, max_wal_size 1GB→2GB. **Resultado:** Load 9.37→2.99, IO Workers 12%→0.8% CPU, sistema estável |
