---
name: asterisk-callcenter-expert
description: Especialista em dados de Call Center com Asterisk/PostgreSQL. Use quando o usuário pedir relatórios de call center, KPIs (TMA, TME, SLA, Taxa de Abandono), análise de filas, desempenho de agentes, ou qualquer consulta envolvendo as tabelas queue_log e cdr do Asterisk armazenadas em PostgreSQL. Inclui mapeamento completo de eventos, colunas dinâmicas, e consultas SQL prontas para produção.
---

# Especialista em Dados de Call Center (Asterisk/PostgreSQL)

Skill para desenvolvimento de relatórios e dashboards de Call Center baseados nas tabelas `queue_log` e `cdr` do Asterisk, armazenadas em banco de dados PostgreSQL externo.

## Quando Usar

- Criar relatórios de desempenho de filas de atendimento (sintéticos e analíticos)
- Calcular KPIs: TMA, TME/ASA, SLA, Taxa de Abandono, Ocupação de Agentes
- Desenvolver dashboards de monitoramento de call center
- Consultar histórico de chamadas com cruzamento entre CDR e queue_log
- Analisar desempenho individual de agentes (pausas, logins, atendimentos)
- Gerar relatórios por período, fila, agente ou disposição

## Contexto do Projeto VoxCALL

- **Stack**: Node.js/Express (backend) + React/TypeScript (frontend)
- **Banco Externo**: PostgreSQL configurado via `db-config.json` na raiz do projeto (escrita) e opcionalmente `db-replica-config.json` (leitura)
- **Padrão de Conexão**: Limpar variáveis PGHOST/PGPASSWORD/DATABASE_URL do Replit antes de conectar ao banco externo
- **Padrão de Relatórios**: Seguir `client/src/lib/reportUtils.ts` para formatação, exportação e estilo
- **Formato de Data**: DD/MM/YYYY no frontend, ISO no backend
- **Idioma**: Português do Brasil em toda a interface
- **Contexto Asterisk**: SEMPRE usar `context: 'MANAGER'` em todas as ações ARI e AMI. Nunca usar `from-internal` ou outros contextos
- **ARI vs AMI**: ARI para originar/listar/desligar canais. AMI (porta 25038, TCP) para transferências de chamadas (Redirect = cega, Atxfer = assistida) — canais de call center NÃO estão em Stasis

## Visão Geral das Tabelas

O sistema utiliza **8 tabelas principais** no banco de dados PostgreSQL externo do Asterisk:

| Tabela | Tipo | Descrição |
|--------|------|-----------|
| `cdr` | Asterisk nativa | Bilhetagem — um registro por chamada |
| `queue_log` | Asterisk nativa | Eventos de fila — múltiplos registros por chamada |
| `queue_table` | Asterisk nativa | Configuração das filas (name, strategy, timeout, etc.) — gerenciada via `/queues-management` |
| `queue_member_table_tela` | **Customizada VoxCALL** | Membros/agentes das filas (membername, queue_name, interface, penalty, paused) |
| `monitor_operador` | **Customizada VoxCALL** | Estado em tempo real dos operadores (login, pausa, atendimentos) |
| `t_monitor_voxcall` | **Customizada VoxCALL** | Registro de cada atendimento com dados enriquecidos |
| `dialer_queue_log` | **Customizada VoxCALL** | Eventos de fila filtrados do discador (populada via trigger `trg_dialer_queue_log` no `queue_log`) |
| `dialer_agent_performance` | **Customizada VoxCALL** | Métricas agregadas por operador/campanha/dia (populada via trigger `trg_dialer_agent_performance` no `dialer_queue_log`) |

### Tabela `cdr` (Call Detail Records)

Visão **macro** da chamada — um registro por chamada com dados de bilhetagem.

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `calldate` | timestamp | Data e hora da chamada |
| `clid` | varchar | Caller ID completo (nome e número) |
| `src` | varchar | Número de origem (quem ligou) |
| `dst` | varchar | Número de destino (ramal, fila, número externo) |
| `dcontext` | varchar | Contexto do dialplan de destino |
| `channel` | varchar | Canal de origem (ex: PJSIP/2001-00000001) |
| `dstchannel` | varchar | Canal de destino |
| `lastapp` | varchar | Última aplicação executada (Dial, Queue, Hangup) |
| `lastdata` | varchar | Dados da última aplicação |
| `duration` | integer | Duração total em segundos (desde o ring) |
| `billsec` | integer | Tempo efetivamente falado (após atender) |
| `disposition` | varchar | Status final: ANSWERED, NO ANSWER, BUSY, FAILED |
| `amaflags` | integer | Flags de AMA (Automatic Message Accounting) |
| `accountcode` | varchar | Código de conta para billing |
| `uniqueid` | varchar | **ID único da chamada** — chave para JOIN com queue_log |
| `userfield` | varchar | Campo livre do usuário |
| `linkedid` | varchar | ID da chamada mãe (para chamadas linkadas) |

### Tabela `queue_log` (Eventos de Fila)

Visão **micro** e temporal do Call Center — múltiplos registros por chamada, um para cada evento.

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id` | serial | ID auto-incremento |
| `eventdate` | timestamp/varchar | Data e hora do evento |
| `callid` | varchar | **ID da chamada** — mapeia com `cdr.uniqueid` |
| `queuename` | varchar | Nome da fila (ex: suporte, vendas, financeiro) |
| `agent` | varchar | Agente envolvido (ex: PJSIP/1000, SIP/2001) |
| `event` | varchar | Tipo de evento (ver mapeamento abaixo) |
| `data1` | varchar | Dado dinâmico 1 — **significado muda conforme o evento** |
| `data2` | varchar | Dado dinâmico 2 — **significado muda conforme o evento** |
| `data3` | varchar | Dado dinâmico 3 — **significado muda conforme o evento** |
| `data4` | varchar | Dado dinâmico 4 |
| `data5` | varchar | Dado dinâmico 5 |

### Tabela `monitor_operador` (Customizada VoxCALL)

Estado **em tempo real** de cada operador — um registro por operador, atualizado continuamente pelo sistema. Funciona como um "painel de controle" dos agentes.

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id` | serial | ID auto-incremento |
| `operador` | varchar | Nome do operador (ex: NAJILA, GLEICY.LIMA, CENTRE1) |
| `ramal` | varchar | Ramal atual do operador (ex: 118, 104, 800) |
| `fl_pausa` | integer | Flag de pausa: **0** = disponível, **1** = em pausa |
| `tipo_pausa` | varchar | Motivo da pausa (ex: Banheiro, SUPERVISAO, Almoço). Vazio quando não está em pausa |
| `hora_entra_pausa` | timestamp | Horário em que entrou na pausa atual |
| `hora_sai_pausa` | timestamp | Horário em que saiu da última pausa |
| `hora_login` | timestamp | Horário do login do operador no dia |
| `hora_logoff` | timestamp | Horário do logoff (NULL = ainda logado) |
| `id_agentes_tela` | integer | ID do agente na tela de monitoramento |
| `ultimo_atendimento` | timestamp | Horário do último atendimento realizado |
| `fl_atendimento` | varchar | Flag de atendimento em andamento |
| `atendidas` | integer | **Contador de chamadas atendidas** no período (desde o login) |

**Observações importantes:**
- Cada operador tem **apenas 1 registro** na tabela (atualizado em tempo real, não é histórico)
- `fl_pausa = 1` com `hora_sai_pausa` vazio indica operador **atualmente em pausa**
- `hora_logoff` NULL indica operador **ainda logado**
- `atendidas` é o acumulador do dia — reseta no próximo login
- Operadores com nomes como CENTRE1, CENTRE2 são supervisores (tipo_pausa = SUPERVISAO)
- O campo `operador` é o nome de usuário, não o ramal — usar para JOIN com `t_monitor_voxcall.operador`

**Triggers de sincronização com `queue_member_table`:**
- **`trg_sync_monitor_to_queue`** (AFTER UPDATE OR DELETE) → `fn_sync_monitor_to_queue()`:
  - **UPDATE fl_pausa 0→1**: `UPDATE queue_member_table SET paused = '1' WHERE membername = operador` (pausa em todas as filas)
  - **UPDATE fl_pausa 1→0**: `UPDATE queue_member_table SET paused = '0' WHERE membername = operador` (despausa em todas as filas)
  - **DELETE** (deslogar): `DELETE FROM queue_member_table WHERE membername = operador` (remove de todas as filas)
- Isso garante que o Asterisk respeita a pausa/logoff — sem esta trigger, o operador continuaria recebendo chamadas mesmo pausado

### ⚠️ Pré-requisito: Backend Realtime do Asterisk DEVE ser pgsql (não ODBC) para PG 14+

Antes de qualquer análise de `queue_log`, confirmar que o Asterisk grava os eventos com **`data1`/`data2`/`data3` populados separadamente**, não tudo concatenado na coluna legada `data`.

**Diagnóstico rápido** — se a query abaixo retornar `data1/data2/data3` vazios para CONNECT/COMPLETE e a coluna `data` com algo tipo `"215|1776524400.135|7"`, o backend está errado:
```sql
SELECT event, data, data1, data2, data3 FROM queue_log
WHERE event IN ('ENTERQUEUE','CONNECT','COMPLETECALLER')
ORDER BY id DESC LIMIT 10;
```

**Sintoma típico**: ENTERQUEUE não aparece nunca, dashboard zerado, e `relatorio_operador` poluído com "operadores fantasma" no formato `ramal|uniqueid|posição` (porque a trigger lê o campo `data` concatenado como nome de operador).

**Causa**: `extconfig.conf` do Asterisk com `queue_log => odbc,...` falando com PostgreSQL 14+ — o `psqlodbcw.so` legado cai em path de compatibilidade que serializa as colunas dinâmicas no campo `data` e descarta o ENTERQUEUE silenciosamente.

**Fix**: trocar para o driver nativo `queue_log => pgsql,asterisk,queue_log` em `/etc/asterisk/extconfig.conf` (detalhes completos na skill `voxcall-native-asterisk-deploy`).

**Importante**: Isso afeta APENAS o backend Realtime do `queue_log`. O CDR (`cdr_pgsql.conf`) usa libpq direto e funciona normalmente com qualquer versão de PG.

**Triggers na `queue_log` para normalização e relatórios:**
- **`trg_normaliza_transferencia`** (BEFORE INSERT) → `fn_normaliza_transferencia()`:
  - Quando `event IN ('ATTENDEDTRANSFER', 'BLINDTRANSFER')`: seta `data5 = 'TRANSFERENCIA'`
  - Executa ANTES do trigger de relatório (ordem alfabética: normaliza → atualiza)
  - Motivo: o Asterisk grava `data5 = 'SAIU'` por padrão, não distinguindo transferências
- **`trg_atualiza_relatorio_operador`** (AFTER INSERT) → `fn_atualiza_relatorio_operador()`:
  - Processa eventos e atualiza `relatorio_operador` com UPSERT (ON CONFLICT):
    - `CONNECT`: incrementa `atendidas`
    - `RINGNOANSWER`: incrementa `ignoradas`
    - `COMPLETEAGENT/COMPLETECALLER`: soma `data2` (tempo falado) em `tempo_total/max/min_atendimento`
    - `ATTENDEDTRANSFER/BLINDTRANSFER`: incrementa `transferidas` + soma `data4` (tempo falado) em `tempo_total/max/min_atendimento`
  - Cast seguro: verifica `data ~ '^\d+$'` antes de `::integer` (ATENÇÃO: usar `\d` com backslash, NÃO `d` sem backslash — bug corrigido em 2026-03-04)
  - Filtra agentes com prefixo `PJSIP/SIP/IAX2/DAHDI/Local` (são canais, não operadores)
  - **Endpoint de correção**: `POST /api/admin/fix-relatorio-trigger` — recria a trigger com regex corrigido e faz backfill dos registros com `tempo_total_atendimento = 0`

### Tabela `t_monitor_voxcall` (Customizada VoxCALL)

Registro de cada **atendimento individual** com dados enriquecidos — informações que não existem no queue_log padrão como protocolo e código de gravação.

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `callid` | varchar | **ID da chamada** — chave para JOIN com `queue_log.callid` e `cdr.uniqueid` |
| `operador` | varchar | Nome do operador que atendeu — chave para JOIN com `monitor_operador.operador` |
| `telefone` | varchar | Número de telefone do cliente (ex: 81992940294) |
| `codgravacao` | varchar | Código da gravação (geralmente igual ao callid) |
| `protocolo` | varchar | Número de protocolo gerado (formato: YYYYMMDDHHmmSS, ex: 20260223160301) |
| `fila` | varchar | Nome da fila de atendimento (ex: Beneficiario, MaisOdonto) |
| `ramal` | varchar | Ramal do operador que atendeu |
| `espera` | varchar | Tempo de espera do cliente na fila (em segundos) |
| `hora_atendimento` | timestamp | Horário exato do atendimento |
| `canal` | varchar | Canal SIP utilizado (ex: SIP/187.72.45.132-000018ef) |

**Observações importantes:**
- O `protocolo` é gerado automaticamente no formato timestamp (YYYYMMDDHHmmSS) — serve como identificador para o cliente
- O `callid` permite cruzar com `queue_log` e `cdr` para obter dados completos da chamada
- O `telefone` vem já formatado como número (sem máscara)
- O `canal` mostra o IP do tronco SIP utilizado na chamada
- O campo `espera` pode estar vazio para chamadas diretas (sem fila)

## Relação entre as 4 Tabelas

```
┌────────────────────┐     ┌─────────────────────┐
│       cdr          │     │     queue_log        │
│  uniqueid ─────────────── callid               │
│  calldate          │     │  eventdate                │
│  src, dst          │     │  queuename, agent    │
│  duration, billsec │     │  event, data1-5      │
└────────────────────┘     └─────────────────────┘
         │                           │
         │ uniqueid = callid         │ callid = callid
         │                           │
┌────────────────────────────────────────────────┐
│              t_monitor_voxcall                 │
│  callid, operador, telefone, protocolo         │
│  fila, ramal, espera, hora_atendimento, canal  │
└────────────────────────────────────────────────┘
                     │
                     │ operador = operador
                     │
         ┌───────────────────────┐
         │   monitor_operador    │
         │  operador, ramal      │
         │  fl_pausa, tipo_pausa │
         │  hora_login, atendidas│
         └───────────────────────┘
```

**Chaves de JOIN:**
- `cdr.uniqueid = queue_log.callid` — liga bilhetagem com eventos de fila
- `cdr.uniqueid = t_monitor_voxcall.callid` — liga bilhetagem com dados de atendimento
- `queue_log.callid = t_monitor_voxcall.callid` — liga eventos com dados de atendimento
- `t_monitor_voxcall.operador = monitor_operador.operador` — liga atendimento com estado do operador

## Mapeamento Completo de Eventos do queue_log

### Ponto Crítico: Colunas Dinâmicas

As colunas `data1` a `data5` mudam de significado dependendo do valor da coluna `event`. Este é o maior desafio ao trabalhar com a tabela `queue_log`.

### Eventos de Chamada

| Evento | Descrição | data1 | data2 | data3 | data4 | data5 |
|--------|-----------|-------|-------|-------|-------|-------|
| `ENTERQUEUE` | Cliente entrou na fila | URL (se houver) | CallerID | Posição na fila | — | — |
| `CONNECT` | Agente atendeu | **Tempo de espera (seg)** | uniqueid do agente | — | — | — |
| `ABANDON` | Cliente desistiu | Posição na fila | Posição original | **Tempo de espera (seg)** | — | — |
| `COMPLETECALLER` | Cliente desligou | **Tempo de espera (seg)** | **Tempo falado (seg)** | Posição original | — | — |
| `COMPLETEAGENT` | Agente desligou | **Tempo de espera (seg)** | **Tempo falado (seg)** | Posição original | — | — |
| `TRANSFER` | Chamada transferida | Extensão destino | Contexto | **Tempo de espera (seg)** | **Tempo falado (seg)** | — |
| `BLINDTRANSFER` | Transferência cega | "BRIDGE" (tipo) | UUID (bridge ID) | Posição na fila | **Tempo falado (seg)** | `TRANSFERENCIA` (via trigger) |
| `ATTENDEDTRANSFER` | Transferência assistida | "BRIDGE" (tipo) | UUID (bridge ID) | Posição na fila | **Tempo falado (seg)** | `TRANSFERENCIA` (via trigger) |
| `RINGNOANSWER` | Agente não atendeu no ring | Tempo de ring (ms) | — | — | — | — |
| `EXITEMPTY` | Saiu: fila vazia | Posição | Posição orig | Tempo espera | — | — |
| `EXITWITHTIMEOUT` | Saiu: timeout da fila | Posição | Posição orig | Tempo espera | — | — |
| `EXITWITHKEY` | Saiu: pressionou tecla | Tecla pressionada | Posição | — | — | — |

### Eventos de Agente

| Evento | Descrição | data1 | data2 | data3 |
|--------|-----------|-------|-------|-------|
| `ADDMEMBER` | Agente adicionado à fila | — | — | — |
| `REMOVEMEMBER` | Agente removido da fila | — | — | — |

**IMPORTANTE sobre ADDMEMBER/REMOVEMEMBER:** Estes eventos vêm em PARES no queue_log:
1. Registro com `data = "Nome.operador"`, `agent = "ramal"`, `queuename = ""` (vazio)
2. Registro com `data = NULL`, `agent = "PJSIP/ramal"`, `queuename = "NomeFila"`
Para contar login/logoff por operador, usar SOMENTE registros onde `data IS NOT NULL AND data <> ''` (tipo 1). NÃO aplicar filtro de fila nesses eventos — login é por operador, não por fila.
| `PAUSE` | Agente entrou em pausa | Motivo da pausa | — | — |
| `UNPAUSE` | Agente saiu da pausa | Motivo da pausa | — | — |
| `PAUSEALL` | Agente pausou em todas as filas | — | — | — |
| `UNPAUSEALL` | Agente despausou em todas filas | — | — | — |
| `AGENTLOGIN` | Agente fez login | Canal | — | — |
| `AGENTLOGOFF` | Agente fez logoff | Canal | Tempo logado (seg) | — |
| `AGENTCALLBACKLOGIN` | Login via callback | — | — | — |
| `AGENTCALLBACKLOGOFF` | Logoff do callback | — | Tempo logado | — |

### Eventos do Sistema de Fila

| Evento | Descrição | data1 |
|--------|-----------|-------|
| `CONFIGRELOAD` | Configuração recarregada | — |
| `QUEUESTART` | Fila inicializada | — |

## KPIs Principais de Call Center

### Glossário de Métricas

| KPI | Nome Completo | Descrição | Fonte |
|-----|--------------|-----------|-------|
| **TMA** | Tempo Médio de Atendimento | Média do tempo que o agente fica ao telefone | queue_log: data2 de COMPLETECALLER/COMPLETEAGENT |
| **TME** | Tempo Médio de Espera | Média do tempo que o cliente aguarda na fila | queue_log: data1 de CONNECT |
| **ASA** | Average Speed of Answer | Igual ao TME (terminologia internacional) | queue_log: data1 de CONNECT |
| **SLA** | Service Level Agreement | % de chamadas atendidas dentro do tempo meta (ex: 20s) | queue_log: CONNECT com data1 <= meta |
| **Taxa de Abandono** | — | % de chamadas onde o cliente desistiu | queue_log: ABANDON / (CONNECT + ABANDON) |
| **FCR** | First Call Resolution | % resolvida no primeiro contato | Requer campo customizado |
| **Ocupação** | — | % do tempo que o agente está em chamada vs disponível | queue_log: CONNECT + PAUSE/UNPAUSE |
| **Aderência** | — | % do tempo que o agente seguiu a escala | queue_log: AGENTLOGIN/AGENTLOGOFF |

## Padrão de Conexão ao Banco Externo

### Read-Replica Support
- **Configuração**: `db-replica-config.json` (mesma estrutura que `db-config.json`)
- **Helper de Leitura**: `withReplicaPg()` — lê da réplica; fallback para `withExternalPg()` se réplica não configurada ou falhar
- **Helper de Escrita**: `withExternalPg()` — sempre usa o banco principal (`db-config.json`)
- **Pool de Leitura**: `createReplicaDbConnection()` em `storage.ts` — pool com fallback para `createCustomDbConnection()`
- **Regra**: Endpoints de leitura (Dashboard, relatórios, CDR, listagens) usam réplica. Endpoints de escrita (pause/unpause/logout, CRUD filas/operadores/membros) usam primário.
- **Fallback**: Transparente — se réplica não existe ou falha, usa banco principal sem erro visível ao usuário.

### Conexão Primária (db-config.json)

```typescript
import pg from 'pg';
import fs from 'fs/promises';

async function loadDbConfig() {
  const data = await fs.readFile('db-config.json', 'utf8');
  return JSON.parse(data);
}

async function queryExternalDb(sql: string, params?: any[]) {
  const config = await loadDbConfig();
  
  // Salvar e limpar variáveis do Replit para não interferir
  const savedEnv = {
    PGHOST: process.env.PGHOST,
    PGPASSWORD: process.env.PGPASSWORD,
    PGUSER: process.env.PGUSER,
    PGDATABASE: process.env.PGDATABASE,
    PGPORT: process.env.PGPORT,
    DATABASE_URL: process.env.DATABASE_URL,
  };
  
  Object.keys(savedEnv).forEach(key => delete process.env[key]);
  
  try {
    const client = new pg.Client({
      host: config.host,
      port: config.port,
      user: config.username,
      password: config.password,
      database: config.database,
      ssl: config.ssl ? { rejectUnauthorized: false } : false,
      connectionTimeoutMillis: 10000,
    });
    
    await client.connect();
    const result = await client.query(sql, params);
    await client.end();
    return result.rows;
  } finally {
    // Restaurar variáveis do Replit
    Object.entries(savedEnv).forEach(([key, value]) => {
      if (value) process.env[key] = value;
    });
  }
}
```

## Ponto Crítico: Cast de Tipos no PostgreSQL

O Asterisk salva `data1`, `data2`, `data3` como **texto (varchar)**. Para calcular médias e somas, é obrigatório fazer cast:

```sql
-- CORRETO: cast explícito
AVG(data1::integer)
SUM(data2::integer)
MAX(data3::integer)

-- ERRADO: gera erro de tipo
AVG(data1)  -- ERROR: function avg(character varying) does not exist
```

Para evitar erros com dados não numéricos, use cast seguro:
```sql
AVG(CASE WHEN data1 ~ '^\d+$' THEN data1::integer ELSE NULL END)
```

## Cruzamento entre Tabelas (JOIN)

Para relatórios completos que precisam de dados de ambas as tabelas:

```sql
SELECT 
  ql.eventdate,
  ql.queuename,
  ql.agent,
  ql.event,
  cdr.src AS origem,
  cdr.dst AS destino,
  cdr.duration,
  cdr.billsec,
  cdr.disposition
FROM queue_log ql
INNER JOIN cdr ON ql.callid = cdr.uniqueid
WHERE ql.event IN ('CONNECT', 'COMPLETECALLER', 'COMPLETEAGENT', 'ABANDON')
  AND ql.eventdate >= '2024-01-01'
ORDER BY ql.eventdate DESC;
```

## Referências Adicionais

Para consultas SQL prontas para todos os KPIs e exemplos de implementação no VoxCALL:
- `reference/tabelas-detalhadas.md` - Estrutura completa das tabelas com todos os eventos e exemplos
- `reference/consultas-kpi.md` - Consultas SQL prontas para produção: TMA, TME, SLA, Abandono, Ocupação, por período/fila/agente

## Dashboard e Painel "Gráfico da Operação"

### Tabela de Operadores — Colunas e Layout

O painel "Gráfico da Operação" exibe uma tabela com as seguintes colunas (todas centralizadas):

| Coluna | Fonte | Descrição |
|--------|-------|-----------|
| Ramal | `monitor_operador.ramal` | Ramal do operador |
| Operador | `monitor_operador.operador` | Nome do operador |
| Atend. | `monitor_operador.atendidas` | Chamadas atendidas no dia |
| Hora Login | `monitor_operador.hora_login` | Formatado "DD/MM/YYYY HH:MM:SS" |
| Status | Calculado via ARI + DB | LIVRE, OCUPADO, CHAMANDO, PAUSA, INDISPONÍVEL |
| Telefone | Canal ARI ativo | Número do interlocutor (apenas quando OCUPADO) |
| Tempo | Cache em memória | Relógio HH:MM:SS contando desde última mudança de status |

### Ordenação

A tabela é ordenada por ramal numérico (menor para maior):
```sql
ORDER BY ramal::integer
```

### Formatação de hora_login

O `hora_login` é formatado no **backend** usando `getUTCDate/getUTCMonth/getUTCHours` para "DD/MM/YYYY HH:MM:SS". O PostgreSQL do Asterisk agora usa `timezone = 'America/Sao_Paulo'` e retorna timestamps `with time zone`. O driver `pg` converte para objetos Date em UTC internamente, então `getUTC*` retorna o valor correto de Brasília para exibição. O frontend exibe o valor diretamente sem conversão.

### Layout da Tabela

- Usa `table-fixed` com `<colgroup>` para proporções: Ramal 6%, Operador 17%, Atend. 6%, Hora Login 18%, Status 24%, Telefone 15%, Tempo 14%
- Fonte: `text-xs` para compactação
- `minWidth: 700px` com scroll horizontal quando necessário
- Todas as colunas e dados são `text-center`

### Tabelas Auxiliares para Filas

| Tabela | Uso |
|--------|-----|
| `queue_table` | `SELECT name FROM queue_table ORDER BY name` — lista de filas para dropdown |
| `queue_member_table_tela` | `SELECT membername FROM queue_member_table_tela WHERE queue_name = $1` — filtrar operadores por fila |
| `queue_member_table_tela` | `SELECT queue_name FROM queue_member_table_tela WHERE membername = $1` — buscar filas do operador (usado no Agent Panel para Abandonadas e Gravações) |

### Tabela `relatorio_hora_voxcall` (Dados Horários)

Use esta tabela para consultas de volume/quantidade (mais leve que queue_log):

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id` | serial | ID auto-incremento |
| `datahora` | timestamp | Hora do registro |
| `recebidas` | integer | Chamadas recebidas na hora |
| `atendidas` | integer | Chamadas atendidas na hora |
| `abandonadas` | integer | Chamadas abandonadas na hora |
| `fila` | varchar | Nome da fila |

### Relatório Pivô: Chamadas Atendidas por Hora (`/answered-calls-by-hour`)

Relatório dedicado que mostra chamadas atendidas em formato pivô (Unidade/Mês/Operador em linhas, horas do dia em colunas). Dados da `queue_log` com filtro de tempo de conversa configurável.

- **Fonte**: `queue_log` — eventos `COMPLETEAGENT`/`COMPLETECALLER`, campo `data2` = tempo de conversa
- **Filtro de tempo**: Operador de comparação selecionável (`>`, `>=`, `=`, `<`, `<=`) + valor em segundos (padrão: `> 10s`)
- **Agrupamento**: `queuename` (Unidade), `TO_CHAR(eventdate, 'Mon/YY')` (Mês), `agent` (Operador)
- **Colunas dinâmicas**: Horas (`h8`, `h9`, `h10`...) — apenas horas com dados aparecem
- **Backend**: `storage.getAnsweredCallsByHourPivot()`, rota `GET /api/reports/answered-by-hour/:startDate/:endDate?queue=&operator=&talkTimeOp=&talkTimeValue=`
- **Frontend**: `client/src/pages/answered-calls-by-hour.tsx` — tabela pivô com heat map colorido, sticky header/columns, export Excel/PDF/Print
- **Query base**:
```sql
SELECT queuename AS unidade, TO_CHAR(eventdate, 'Mon/YY') AS mes, agent AS operador,
       EXTRACT(HOUR FROM eventdate)::int AS hora, COUNT(*) AS qtd
FROM queue_log
WHERE event IN ('COMPLETEAGENT', 'COMPLETECALLER')
  AND eventdate::date BETWEEN $startDate AND $endDate
  AND COALESCE(data2, '0')::int > $talkTimeValue
  AND agent IS NOT NULL AND agent <> '' AND agent <> 'NONE'
GROUP BY queuename, TO_CHAR(eventdate, 'YYYY-MM'), TO_CHAR(eventdate, 'Mon/YY'), agent, EXTRACT(HOUR FROM eventdate)::int
```

### Tabela `pausas_operador` (Pausas)

Use para **todos** os relatórios e dashboards de pausa (em vez de queue_log PAUSE/UNPAUSE):

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id_pausa` | serial | ID auto-incremento |
| `id_monitor` | integer | FK para monitor_operador |
| `operador` | varchar | Nome do operador |
| `ramal` | varchar | Ramal |
| `tipo_pausa` | varchar | Tipo de pausa (Banheiro, Almoço, etc.) |
| `hora_entra_pausa` | timestamp | Hora de entrada na pausa |
| `hora_sai_pausa` | timestamp | Hora de saída da pausa |
| `tempo_pausa_segundos` | integer | Duração em segundos |
| `data_pausa` | date | Data da pausa |

## Relatório SLA por Operador

Relatório que ranqueia operadores pela conformidade ao SLA (Service Level Agreement), com tempo de SLA configurável em segundos.

### Endpoint
`GET /api/reports/sla-by-operator/:startDate/:endDate` (`requireAuth`)

### Query Params
| Param | Tipo | Default | Descrição |
|-------|------|---------|-----------|
| `slaSeconds` | integer | 20 | Tempo limite de SLA em segundos |
| `queue` | string | — | Filtrar por fila específica |
| `search` | string | — | Busca parcial no nome do operador (ILIKE) |
| `page` | integer | 1 | Página da paginação |
| `limit` | integer | 10 | Registros por página |
| `export` | string | — | Se `all`, retorna tudo sem paginação |

### Colunas Retornadas
| Campo | Descrição |
|-------|-----------|
| `operador` | Nome do operador |
| `total_atendidas` | Total de chamadas atendidas no período |
| `dentro_sla` | Chamadas atendidas dentro do SLA (data1::int <= slaSeconds) |
| `fora_sla` | Chamadas atendidas fora do SLA (data1::int > slaSeconds) |
| `pct_sla` | Percentual SLA (dentro_sla / total * 100) |
| `tempo_medio_espera` | Tempo médio de espera na fila (segundos) |
| `tempo_max_espera` | Tempo máximo de espera na fila (segundos) |

### Fonte de Dados
- Tabela `queue_log`, evento `CONNECT`, campo `data1` = tempo de espera em segundos
- Operador extraído de `COALESCE(NULLIF(data, ''), agent)`, excluindo prefixos de canal
- Ordenação: `pct_sla DESC, total_atendidas DESC`

### Frontend
- Rota: `/sla-by-operator` | Arquivo: `client/src/pages/sla-by-operator.tsx`
- Filtros: Data Início/Fim, Fila (dropdown), Pesquisar Operador (texto), SLA (segundos, input numérico)
- Cores no % SLA: verde ≥ 80%, amarelo ≥ 60%, vermelho < 60% (com barra de progresso colorida)
- Exportação: Imprimir, PDF (jsPDF + autoTable), Excel (XLSX)
- Paginação: 10 por página com Primeira/Anterior/Próxima/Última

### Tabela `relatorio_operador` (Pré-agregada)

Tabela com dados pré-calculados por operador/fila/dia, mantida automaticamente pelo trigger `trg_atualiza_relatorio_operador`.

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id` | serial | ID auto-incremento |
| `data` | date | Data do registro |
| `operador` | varchar | Nome do operador |
| `fila` | varchar | Nome da fila |
| `atendidas` | integer | Chamadas atendidas |
| `ignoradas` | integer | Chamadas ignoradas (RINGNOANSWER) |
| `transferidas` | integer | Chamadas transferidas |
| `tempo_total_atendimento` | integer | Tempo total de atendimento em segundos |
| `tempo_max_atendimento` | integer | Tempo máximo de uma chamada |
| `tempo_min_atendimento` | integer | Tempo mínimo (999999 = sem chamadas) |

**Constraint**: `UNIQUE(data, operador, fila)` — permite UPSERT via `ON CONFLICT`

**Nota**: `tempo_min_atendimento = 999999` quando não há chamadas — renderizar como 0 no frontend.

**Tempos de transferência**: ATTENDEDTRANSFER/BLINDTRANSFER usam `data4` (tempo falado) que é somado em `tempo_total/max/min_atendimento` pelo trigger.

## Retorno Automático de Chamadas Abandonadas

### Tabelas Envolvidas

#### `queue_retorno_config` (Banco Externo)
| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `queue_name` | varchar PK | Nome da fila de retorno (ex: RetornoClientes, Voxtel) |
| `contexto_discagem` | varchar | Contexto Asterisk para discagem (ex: MANAGER) |
| `filas_origem` | varchar | Filas monitoradas, separadas por vírgula (ex: MarcacaoExame,MarcacaoExameCentro) |
| `ativo` | boolean | Se o retorno está ativo |
| `max_tentativas` | integer (default 3) | Máximo de tentativas por telefone por dia |
| `intervalo_minutos` | integer (default 10) | Intervalo mínimo entre tentativas |

#### `retorno_clientes` (Banco Externo)
| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `eventdate` | timestamp with time zone | Data/hora do evento |
| `queuename` | varchar | Sempre 'RetornoClientes' (hardcoded pela trigger) |
| `event` | varchar | Estado: ENTERQUEUE → ABANDON/CONNECT/COMPLETE* → LIGOU → RETORNADO/RETORNO/EXPIRADO |
| `callid` | varchar | ID da chamada |
| `data2` | varchar | Número de telefone do cliente |
| `queue` | varchar | Fila **real** onde a chamada entrou (ex: Voxtel, MarcacaoExame) |

#### `retorno_historico` (Banco Externo — criada pela aplicação)

Tabela de histórico detalhado de cada tentativa de retorno. Alimentada pela aplicação Node.js (não por trigger SQL) para maior controle e rastreabilidade.

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id` | serial PK | ID auto-incremento |
| `telefone` | varchar(32) NOT NULL | Número do cliente |
| `fila_origem` | varchar(128) | Fila onde o cliente abandonou |
| `fila_retorno` | varchar(128) | Fila de retorno configurada |
| `callid_original` | varchar(128) | callid do ABANDON original |
| `callid_retorno` | varchar(128) | callid gerado pelo Originate (se houver) |
| `operador` | varchar(128) | Operador que executou o retorno |
| `data_abandono` | timestamp | Quando o cliente abandonou |
| `data_retorno` | timestamp | Quando o retorno foi iniciado (discagem) |
| `data_resultado` | timestamp | Quando houve resultado final |
| `tentativa` | integer (default 1) | Número da tentativa (1, 2, 3...) |
| `max_tentativas` | integer (default 3) | Máximo configurado no momento da discagem |
| `status` | varchar(32) | DISCANDO, ATENDIDO, NAO_ATENDIDO, EXPIRADO |
| `duracao_segundos` | integer (default 0) | Duração da chamada de retorno (se atendida) |

**Índices**: `(telefone, status)`, `(data_abandono)`, `(fila_origem)`, `(operador)`, `(status, data_retorno)`

**Ciclo de vida do status**:
- `DISCANDO` — inserido no momento da discagem (`retorno-discar`)
- `ATENDIDO` — atualizado pelo cleanup job quando detecta RETORNADO/RETORNO no `retorno_clientes`
- `NAO_ATENDIDO` — atualizado pelo cleanup job quando LIGOU sem CONNECT após 2 minutos
- `EXPIRADO` — atualizado pelo cleanup job quando tentativas >= max_tentativas

**Por que alimentação via aplicação e não trigger SQL**:
1. A trigger `executa_t_monitor_voxcall` no `queue_log` é complexa e gerencia o `retorno_clientes` — adicionar mais lógica aumentaria risco de falha
2. A aplicação tem acesso ao contexto completo (operador, config, tentativa) que a trigger não teria
3. Facilita manutenção e debugging — toda a lógica fica em `server/routes.ts`
4. Permite rollback controlado (ex: falha AMI reverte LIGOU→ABANDON sem afetar historico)

### Trigger `monitor_voxcall` (executa_t_monitor_voxcall)

Trigger AFTER INSERT na `queue_log` que gerencia o ciclo de vida:

| Evento queue_log | Ação em retorno_clientes |
|-----------------|--------------------------|
| `ENTERQUEUE` | INSERT com event='ENTERQUEUE', queuename='RetornoClientes', queue=fila_real |
| `CONNECT` | UPDATE event='CONNECT' WHERE data2 matches (por telefone, não por callid!) |
| `ABANDON` | UPDATE event='ABANDON' WHERE callid matches |
| `COMPLETE*` | UPDATE event='COMPLETECALLER/COMPLETEAGENT' WHERE callid matches, DEPOIS UPDATE event='RETORNO' WHERE data2 matches (marca TODOS os registros do mesmo telefone) |

**Observação crítica**: A trigger CONNECT atualiza por `data2` (telefone), não por `callid`. Isso significa que quando um cliente atende em qualquer fila, TODOS os registros desse telefone são marcados como CONNECT.

### Ciclo de Vida dos Eventos

```
ENTERQUEUE → ABANDON (cliente desistiu, pendente para retorno)
ENTERQUEUE → CONNECT (operador atendeu, não precisa retornar)
ABANDON → LIGOU (sistema discou via AMI)
LIGOU → RETORNO/RETORNADO (chamada completada com sucesso)
LIGOU → ABANDON (revertido pelo cleanup após 2 min sem CONNECT, volta para pendente)
LIGOU → EXPIRADO (tentativas esgotadas, cleanup marca como finalizado)
```

### Query de Pendentes (`GET /api/agent/retorno-pendentes`)

**Lógica essencial**:
1. Busca ABANDONs do dia na `retorno_clientes` filtrados pelas filas do operador
2. `DISTINCT ON (rc.data2)` + `ORDER BY rc.data2, rc.eventdate DESC` — deduplica por telefone, pega ABANDON mais recente
3. Exclui telefones que tenham RETORNADO/RETORNO **depois** do ABANDON (`rc3.eventdate > rc.eventdate`)
4. Exclui telefones com LIGOU nos últimos 2 minutos (evita rediscagem imediata)
5. Exclui telefones que tenham CONNECT/COMPLETECALLER/COMPLETEAGENT **depois** do ABANDON
6. Exclui telefones com evento EXPIRADO no dia (tentativas esgotadas)
7. Pós-query: filtra por max_tentativas e intervalo_minutos da config

**Bug corrigido (2026-03-05)**: A verificação de sucesso usava RETORNADO/RETORNO no dia inteiro (`eventdate::date = CURRENT_DATE`), sem comparar com o horário do ABANDON. Um telefone que foi retornado pela manhã mas abandonou novamente à tarde nunca aparecia como pendente. Correção: adicionado `AND rc3.eventdate > rc.eventdate`.

### Discagem via AMI (`POST /api/agent/retorno-discar`)

**Verificação de ocupação (proteção 1-por-1)**: Antes de discar, o endpoint verifica:
1. `t_monitor_voxcall` — se o operador aparece nessa tabela, está em ligação → HTTP 423
2. `monitor_operador` — se `fl_pausa = 1`, está em pausa → HTTP 423
3. Só prossegue com o Originate se o operador estiver realmente livre

**Cooldown no frontend**: Após discagem bem-sucedida, o polling pausa por 15 segundos. Se receber HTTP 423, pausa por 5 segundos. Isso evita tentativas rápidas de discagem enquanto o operador está ocupado.

**AMI Originate correto** — usar `Context/Exten/Priority` com contexto = nome da fila de origem:
```typescript
const gotoContext = filaOrigem || filaDestino;
await amiAction({
  Action: 'Originate',
  Channel: 'LOCAL/' + data2 + '@' + contexto,
  Context: gotoContext,
  Exten: 's',
  Priority: '1',
  CallerID: '"RETORNO: ' + data2 + '" <' + data2 + '>',
  Timeout: '30000',
  Async: 'yes',
  Variable: 'CDR(userfield)=RETORNO',
});
```

**Como funciona**: O Originate AMI com Context/Exten/Priority liga para o Channel (cliente) e, quando o cliente atende, conecta a chamada ao dialplan no `Context: filaOrigem, Exten: s, Priority: 1`. O dialplan da fila executa a aplicação Queue() que coloca a chamada na fila correta.

**Evolução do Originate** (bugs encontrados e corrigidos):
1. ~~`Exten: 'Voxtel', Context: 'MANAGER'`~~ — erro "Extension does not exist" (extensão "Voxtel" não existe no contexto MANAGER)
2. ~~`Application: 'Queue', Data: 'Voxtel,tTr,,,,'`~~ — funcionava mas não usava o dialplan da fila (sem anúncios, sem MOH)
3. ~~`Application: 'Goto', Data: 'Voxtel,s,1'`~~ — Goto roda no leg ;1 do canal LOCAL, mas o cliente está no leg ;2; a bridge se desfaz e a chamada cai
4. **`Context: 'Voxtel', Exten: 's', Priority: '1'`** — correto! Após o cliente atender, a chamada é conectada ao dialplan da fila via Context/Exten/Priority do Originate

**Rollback em caso de falha AMI**: Se o Originate falhar, o registro é revertido de LIGOU para ABANDON para não ficar preso:
```typescript
catch (amiErr) {
  await withExternalPg(async (extClient) => {
    await extClient.query(
      "UPDATE retorno_clientes SET event = 'ABANDON' WHERE callid = $1 AND data2 = $2 AND event = 'LIGOU'",
      [callid, data2]
    );
  }).catch(() => {});
}
```

### Alimentação da `retorno_historico`

No `retorno-discar`, após AMI Originate bem-sucedido:
1. Conta tentativas anteriores do dia na `retorno_historico` para calcular `tentativa`
2. Busca `data_abandono` no `retorno_clientes` pelo callid
3. Busca `max_tentativas` da config pela fila de origem
4. Insere registro com status='DISCANDO', tentativa, operador, timestamps

### Cleanup Job (setInterval 2 minutos)

Roda a cada 2 minutos, para cada config ativa:
1. Busca registros com event='LIGOU' que não têm CONNECT na queue_log, **com MAX(eventdate) para saber quando foi o LIGOU**
2. **Espera 2 minutos** desde o LIGOU antes de agir (dar tempo de a chamada completar)
3. Conta tentativas na `retorno_historico` (não mais no `retorno_clientes`)
4. Se tentativas >= max_tentativas → marca EXPIRADO em `retorno_clientes` e `retorno_historico`
5. Se tentativas < max_tentativas → reverte LIGOU→ABANDON em `retorno_clientes`, marca NAO_ATENDIDO em `retorno_historico`
6. Verifica telefones com RETORNADO/RETORNO no `retorno_clientes` que têm DISCANDO na `retorno_historico` → atualiza para ATENDIDO

**Melhoria (2026-03-06)**: A reversão de LIGOU→ABANDON agora é baseada em 2 minutos desde o LIGOU (tempo fixo para a chamada completar), não mais no `intervalo_minutos`. O `intervalo_minutos` controla apenas quando o número reaparece como pendente no `retorno-pendentes`.

### Frontend (agent-panel.tsx)

- Toggle "Retorno Auto" visível para todos operadores que pertencem a filas com retorno configurado
- Quando LIVRE por 5+ segundos (`retornoLivreStable`), polling de `retorno-pendentes` a cada 3 segundos
- Ao encontrar pendentes, pega o primeiro e chama `retorno-discar`
- Banner cyan "CHAMADA DE RETORNO" durante chamada ativa
- Botão "Pular" para ignorar um telefone na sessão
- Histórico dos últimos 10 retornos com hora e status

### Dashboard — Métricas de Retorno

O dashboard (`/api/callcenter/dashboard`) inclui métricas de retorno em duas camadas:

**Camada 1 — Card "Retornadas"** (dados do `queue_log`):
- Total de CONNECT nas filas de retorno configuradas (sucesso real no Asterisk)
- Taxa de retorno = total_retornadas / total_abandonadas

**Camada 2 — Card "Retorno de Chamadas — Detalhamento"** (dados do `retorno_historico`):
- Tentativas totais do dia
- Atendidas (status='ATENDIDO')
- Sem Resposta (status='NAO_ATENDIDO')
- Expiradas (status='EXPIRADO' — tentativas esgotadas)
- Em Andamento (status='DISCANDO' ou 'PENDENTE')
- Taxa de sucesso e taxa sem resposta calculadas no frontend

**Campos no `totals` da resposta**:
- `retorno_tentativas`, `retorno_atendido`, `retorno_nao_atendido`, `retorno_expirado`, `retorno_em_andamento`

**Filtro de fila**: Quando `queueFilter` é aplicado, filtra `retorno_historico` por `fila_origem = queueFilter`

### Filas de Origem — Seletor

A configuração de `filas_origem` usa um seletor de checkboxes inline (não popover):
- Busca filas disponíveis via `GET /api/callcenter/queues` (SELECT name FROM queue_table)
- Div com `border rounded max-h-48 overflow-y-auto` contendo checkboxes
- Exibe dentro do dialog de edição da fila de retorno

## Boas Práticas para Relatórios

1. **Sempre usar cast seguro** com regex `~ '^\d+$'` antes de converter data1/data2/data3/data4
2. **Filtrar por período** — nunca trazer dados sem filtro de data (performance)
3. **Indexar colunas** — `eventdate`, `event`, `queuename`, `agent`, `callid` precisam de índice
4. **CRÍTICO: Formatar timestamps com TO_CHAR no SQL** — NUNCA retornar `eventdate` ou `calldate` cru para o frontend. O driver `pg` do Node.js interpreta `timestamp without timezone` como UTC, causando deslocamento de 3 horas para dados em horário de Brasília (UTC-3). SEMPRE usar `TO_CHAR(eventdate, 'DD/MM/YYYY HH24:MI:SS') AS data_hora_fmt` no SQL e mapear `row.data_hora_fmt` diretamente no backend. Para filtros de data, usar comparação direta (`WHERE eventdate BETWEEN '20260302' AND '20260302 235959'`), NUNCA `EXTRACT(EPOCH FROM eventdate)`. No frontend, detectar strings já formatadas: `if (/^\d{2}\/\d{2}\/\d{4}/.test(s)) return s;`. PostgreSQL do Asterisk configurado com `timezone = 'America/Sao_Paulo'`. Containers têm `TZ=America/Sao_Paulo` + `/etc/localtime` → `America/Sao_Paulo`
5. **Formatar durações** — Converter segundos para HH:MM:SS no frontend
6. **Excluir eventos internos** — Filtrar `RINGNOANSWER` ao calcular taxa de atendimento
7. **Separar filas** — Cada fila pode ter metas de SLA diferentes
8. **Tratar agentes duplicados** — Um agente pode ter formato PJSIP/1000 ou SIP/1000, normalizar
9. **SQL parametrizado** — Todas as queries devem usar `$1, $2...` para evitar SQL injection
10. **Usar tabelas otimizadas** — `relatorio_hora_voxcall` para volumes, `pausas_operador` para pausas, `t_monitor_voxcall` para chamadas em espera (operador NULL)
11. **Filtro de busca por operador** — Usar ILIKE com `%nome%` para busca parcial case-insensitive
12. **SQL em routes.ts** — Queries SQL complexas devem usar concatenação de strings (`+`), NÃO template literals (`${}`) em esbuild/tsx — risco de truncamento silencioso da classe

## Discador Preditivo (Implementado — 2026-03)

### Arquitetura do Motor de Discagem

O discador preditivo está **implementado e funcional**. Arquivo principal: `server/dialer-engine.ts` (~1400 linhas).

**Fluxo de originação**:
1. Engine verifica operadores disponíveis via `monitor_operador` (fl_pausa=0, hora_logoff IS NULL)
2. Busca registros `pending` na tabela `dialer_mailing` (banco LOCAL Replit PostgreSQL)
3. Origina chamada via **AMI Originate** com `Context: MANAGER`, canal `Local/PHONE@MANAGER`
4. AMI Event Listener monitora eventos (OriginateResponse, Newstate, Hangup) via TCP socket
5. Resultado da chamada atualiza `dialer_mailing.status` e `dialer_call_log`

**Dados armazenados (banco LOCAL — Replit PostgreSQL)**:
- `dialer_campaigns` — campanhas com fila, horários, configurações
- `dialer_mailing` — registros de discagem (phone, status, attempts, campaignId)
- `dialer_call_log` — log detalhado de cada tentativa
- `dialer_stats_hourly` — estatísticas por hora
- `dialer_dnc` — lista Do Not Call

**Dados consultados (banco VPS — PostgreSQL externo)**:
- `monitor_operador` — disponibilidade real-time dos operadores
- `queue_member_table_tela` — mapeamento operador↔fila
- `dialer_queue_log` — eventos de fila filtrados do discador (populada via trigger `trg_dialer_queue_log` no `queue_log`)
- `dialer_agent_performance` — métricas agregadas por operador/campanha/dia (populada via trigger `trg_dialer_agent_performance` no `dialer_queue_log`)
- `t_monitor_voxcall` — registro de atendimento (preenchido automaticamente pelas triggers existentes)

**Cascade de Triggers do Discador no VPS**:
1. `queue_log` → trigger `trg_dialer_queue_log` → popula `dialer_queue_log` (filtra apenas eventos da fila `voxdial` e correlaciona com CDR userfield para extrair campaign_id)
2. `dialer_queue_log` → trigger `trg_dialer_agent_performance` → popula `dialer_agent_performance` (UPSERT por agent/campaign_id/stat_date, processa CONNECT/COMPLETEAGENT/COMPLETECALLER/RINGNOANSWER)

**Tabela `dialer_agent_performance` (métricas)**:
- `agent` (varchar 80) — nome do agente como registrado no queue_log
- `ramal` (varchar 20) — ramal normalizado (sem prefixo SIP/PJSIP)
- `campaign_id` (varchar) — ID da campanha
- `stat_date` (date) — data da estatística
- `total_calls` (int) — CONNECT + RINGNOANSWER (tentativas reais)
- `answered` (int) — apenas CONNECT
- `completed` (int) — COMPLETEAGENT + COMPLETECALLER
- `ring_no_answer` (int) — RINGNOANSWER
- `total_talk_time`, `avg_talk_time`, `max_talk_time` (int, segundos) — de data2 em COMPLETE*
- `total_wait_time`, `avg_wait_time` (int, segundos) — de data1 em CONNECT
- UNIQUE constraint: `dialer_agent_perf_unique (agent, campaign_id, stat_date)`

**Relatório de Operadores do Discador** (`/dialer-reports` aba Operadores):
- Endpoint: `GET /api/dialer/reports/agent-performance?startDate=&endDate=&campaignId=`
- Fonte primária: tabela `dialer_agent_performance` no VPS
- Fallback: query raw no `dialer_queue_log` (quando tabela primária está vazia)
- Ambas conexões via `createCustomDbConnection()` exportada de `server/storage.ts`
- NÃO usa AMI para capturar operadores — dados vêm exclusivamente do PostgreSQL VPS

**Bugs corrigidos (2026-03-26/27)**:
- `isRecordRetryReady()` bloqueava registros com `attempts=0` e `lastAttemptAt` preenchido — corrigido para só verificar intervalo quando `attempts > 0`
- Timezone: usar `Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo' })` para comparações de data
- Registros órfãos em `dialing`: `recoverStaleDialingRecords()` no startup reseta registros travados
- VPS trigger `fn_atualiza_relatorio_operador`: faltava UNIQUE index em `relatorio_operador(data, operador, fila)` — causava ROLLBACK de toda a cascade de triggers, impedindo gravação do CONNECT
- Relatório de Operadores: removida captura AMI (operatorRamal/operatorName do InFlightCall), substituída por trigger PostgreSQL `trg_dialer_agent_performance` para dados consistentes

### Habilitar CEL para captura de canal externo

O campo `t_monitor_voxcall.canal` (canal SIP do tronco externo, ex: `SIP/187.72.45.132-000018ef`) só é preenchido quando o pipeline CEL está ativo:

```
Asterisk CEL (CHAN_START) → INSERT em cel (UNLOGGED) → trigger trg_cel_captura_canal
   → INSERT em canal_chamada (linkedid, canal) → trigger monitor_voxcall() lê no CONNECT
   → UPDATE t_monitor_voxcall.canal
```

**Pré-requisitos no PostgreSQL do extdb (já no schema bootstrap):**
- Tabela `cel` deve ser **UNLOGGED** (não PERMANENT). Validar:
  ```sql
  SELECT relpersistence FROM pg_class WHERE relname='cel';  -- deve ser 'u'
  ```
  Se estiver `'p'`, fazer `DROP TABLE cel CASCADE` e recriar conforme `server/asterisk-schema.sql:984-1006`, depois reaplicar `trg_cel_captura_canal`.
- Trigger `trg_cel_captura_canal` (BEFORE INSERT) + função `fn_cel_captura_canal()` que retorna NULL.
- Tabela `canal_chamada(linkedid PK, canal, created_at)` + trigger de cleanup `trg_canal_chamada_cleanup` (24h).

**Smoke test do pipeline DB:**
```sql
INSERT INTO cel (eventtype, channame, linkedid)
VALUES ('CHAN_START', 'SIP/test-trunk-99999', 'smoke_test_001');
SELECT 'cel' AS tbl, COUNT(*) FROM cel WHERE linkedid='smoke_test_001'      -- esperado 0 (cancelado)
UNION ALL SELECT 'canal_chamada', COUNT(*) FROM canal_chamada WHERE linkedid='smoke_test_001';  -- esperado 1
DELETE FROM canal_chamada WHERE linkedid='smoke_test_001';
```

**Configuração no Asterisk:**

> **IMPORTANTE — Asterisk 11 antigo (CentOS 7, instalações via SVN/source pré-2022):** o `cel_pgsql.so` pode não estar compilado mesmo que o source exista. Verificar com `ls /usr/lib*/asterisk/modules/ | grep cel_`. Se ausente, compilar manualmente:
> ```bash
> # Pré-req: yum install postgresql-devel  (já costuma estar instalado se cdr_pgsql funciona)
> cd /usr/src/asterisk-<versão>
> cp menuselect.makeopts menuselect.makeopts.bak
> sed -i 's/\bcel_pgsql\b//' menuselect.makeopts   # remove da lista de excluídos
> make cel                                          # compila apenas os módulos cel/
> cp cel/cel_pgsql.so /usr/lib64/asterisk/modules/  # ou /usr/lib/asterisk/modules/
> cp menuselect.makeopts.bak menuselect.makeopts    # restaura
> asterisk -rx 'module load cel_pgsql.so'
> asterisk -rx 'core reload'                        # relê cel.conf
> asterisk -rx 'cel show status'                    # deve mostrar "Enabled" + "CEL PGSQL backend"
> ```
> Caso não tenha source, alternativas: instalar pacote (`yum search asterisk-cel`) ou usar `cel_manager.so` (eventos AMI, requer listener custom).

`/etc/asterisk/cel.conf`:
```ini
[general]
enable=yes
apps=all
events=CHAN_START

[manager]
enabled=yes
```

`/etc/asterisk/cel_pgsql.conf` (preferir `cel_pgsql` por ser conexão direta, sem ODBC):
```ini
[global]
hostname=<host_do_extdb>
port=<porta_do_extdb>
dbname=asterisk
user=asterisk
password=<senha>
table=cel
```

Alternativa via ODBC (`cel_odbc.conf` + DSN `asterisk-connector` em `res_odbc.conf`):
```ini
[asterisk]
connection=asterisk
table=cel
usegmtime=no
allowleapsecond=no
```

**Reload e validação:**
```bash
asterisk -rx "module reload cel.so"
asterisk -rx "module reload cel_pgsql.so"   # ou cel_odbc.so
asterisk -rx "cel show status"

# Após uma chamada nova:
psql -c "SELECT COUNT(*) FROM canal_chamada WHERE created_at > now() - interval '5 min';"
# Esperado: > 0
```

**Lookup de protocolo (corrigido 2026-04-18)**: A tabela `protocolo` pode ter 2 rows com o mesmo `callid` (placeholder vazio + valor real `DDMMYYYYHHMMSS`). A função `monitor_voxcall()` precisa filtrar `protocolo IS NOT NULL AND protocolo <> ''` com `ORDER BY protocolo DESC LIMIT 1`. Ver `server/asterisk-schema.sql:407-413`.

### Dados Disponíveis na `retorno_historico`

A tabela `retorno_historico` contém dados históricos úteis para analytics do discador:

**Métricas extraíveis por consulta**:
- Taxa de sucesso por fila: `SELECT fila_origem, COUNT(*) FILTER (WHERE status='ATENDIDO') * 100.0 / COUNT(*) FROM retorno_historico GROUP BY fila_origem`
- Taxa de sucesso por horário: `SELECT EXTRACT(HOUR FROM data_retorno) AS hora, COUNT(*) FILTER (WHERE status='ATENDIDO') * 100.0 / COUNT(*) FROM retorno_historico GROUP BY hora`
- Taxa de sucesso por tentativa: `SELECT tentativa, COUNT(*) FILTER (WHERE status='ATENDIDO') * 100.0 / COUNT(*) FROM retorno_historico GROUP BY tentativa`

**AMI Originate**: Funcional — usa `Context: MANAGER` com canal `Local/PHONE@MANAGER`

## Skills Relacionadas

- **diagnostic-assistant-expert**: Para manutenção do Assistente de Diagnóstico (base de conhecimento, ferramentas, prompts, modelo GPT-4.1)
- **asterisk-ari-expert**: Para desenvolvimento de features ARI (originar chamadas, dashboards, controle de canais)
- **voxfone-telephony-crm**: Para features do CRM (softphone, CDR reports, extensões, agendas, auth)
- **deploy-assistant-vps**: Para deploy em VPS via Docker Compose, nginx, SSL
