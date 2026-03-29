# Estrutura Detalhada das Tabelas - Call Center Asterisk/PostgreSQL

## Tabela `cdr` (Call Detail Records)

### Estrutura Completa

```sql
CREATE TABLE cdr (
    id SERIAL PRIMARY KEY,
    calldate TIMESTAMP NOT NULL DEFAULT NOW(),
    clid VARCHAR(80) NOT NULL DEFAULT '',
    src VARCHAR(80) NOT NULL DEFAULT '',
    dst VARCHAR(80) NOT NULL DEFAULT '',
    dcontext VARCHAR(80) NOT NULL DEFAULT '',
    channel VARCHAR(80) NOT NULL DEFAULT '',
    dstchannel VARCHAR(80) NOT NULL DEFAULT '',
    lastapp VARCHAR(80) NOT NULL DEFAULT '',
    lastdata VARCHAR(80) NOT NULL DEFAULT '',
    duration INTEGER NOT NULL DEFAULT 0,
    billsec INTEGER NOT NULL DEFAULT 0,
    disposition VARCHAR(45) NOT NULL DEFAULT '',
    amaflags INTEGER NOT NULL DEFAULT 0,
    accountcode VARCHAR(20) NOT NULL DEFAULT '',
    uniqueid VARCHAR(150) NOT NULL DEFAULT '',
    userfield VARCHAR(255) NOT NULL DEFAULT '',
    linkedid VARCHAR(150) NOT NULL DEFAULT '',
    peeraccount VARCHAR(80) NOT NULL DEFAULT '',
    sequence INTEGER NOT NULL DEFAULT 0
);
```

### Índices Recomendados

```sql
CREATE INDEX idx_cdr_calldate ON cdr (calldate);
CREATE INDEX idx_cdr_src ON cdr (src);
CREATE INDEX idx_cdr_dst ON cdr (dst);
CREATE INDEX idx_cdr_uniqueid ON cdr (uniqueid);
CREATE INDEX idx_cdr_disposition ON cdr (disposition);
CREATE INDEX idx_cdr_linkedid ON cdr (linkedid);
CREATE INDEX idx_cdr_calldate_disposition ON cdr (calldate, disposition);
```

### Valores de `disposition`

| Valor | Descrição | Quando Ocorre |
|-------|-----------|---------------|
| `ANSWERED` | Chamada atendida | Destino atendeu a chamada |
| `NO ANSWER` | Não atendida | Timeout sem resposta |
| `BUSY` | Ocupado | Destino retornou sinal de ocupado |
| `FAILED` | Falhou | Erro de rede, destino inválido, etc. |
| `CONGESTION` | Congestionamento | Circuitos ocupados |

### Valores de `amaflags`

| Valor | Constante | Descrição |
|-------|-----------|-----------|
| 0 | OMIT | Não registrar |
| 1 | BILLING | Registrar para billing |
| 2 | DOCUMENTATION | Registrar para documentação |
| 3 | DEFAULT | Configuração padrão do sistema |

### Campos Importantes para Relatórios

**`duration` vs `billsec`:**
- `duration` = Tempo total desde o início do ring até o desligamento
- `billsec` = Tempo efetivamente falado (a partir do Answer)
- Para chamadas não atendidas: `billsec = 0` mas `duration > 0`
- Relação: `duration >= billsec` sempre

**`channel` e `dstchannel`:**
- Formato: `TECNOLOGIA/RECURSO-HASH` (ex: `PJSIP/2001-00000042`)
- Para extrair o ramal: `SPLIT_PART(channel, '/', 2)` e depois `SPLIT_PART(resultado, '-', 1)`
- Útil para identificar troncos (quando `channel` contém nome de trunk)

**`lastapp` e `lastdata`:**
- `lastapp = 'Queue'` indica que a chamada passou por uma fila
- `lastapp = 'Dial'` indica discagem direta
- `lastdata` contém os parâmetros (ex: nome da fila, opções de Dial)

**`linkedid`:**
- Chamadas transferidas ou conferências compartilham o mesmo `linkedid`
- Útil para rastrear toda a jornada de uma chamada

### Exemplos de Registros CDR

```
-- Chamada atendida internamente
calldate: 2024-01-15 10:30:00
src: 2001, dst: 2002, duration: 180, billsec: 165
disposition: ANSWERED, lastapp: Dial
channel: PJSIP/2001-00000001, dstchannel: PJSIP/2002-00000002

-- Chamada para fila atendida
calldate: 2024-01-15 10:35:00
src: 5511999887766, dst: 4000, duration: 300, billsec: 240
disposition: ANSWERED, lastapp: Queue, lastdata: suporte,t,,,180
channel: PJSIP/trunk-in-00000003, dstchannel: PJSIP/1001-00000004

-- Chamada não atendida
calldate: 2024-01-15 10:40:00
src: 5511888776655, dst: 4000, duration: 45, billsec: 0
disposition: NO ANSWER, lastapp: Queue
```

---

## Tabela `queue_log` (Log de Eventos de Fila)

### Estrutura Completa

```sql
CREATE TABLE queue_log (
    id SERIAL PRIMARY KEY,
    eventdate TIMESTAMP NOT NULL DEFAULT NOW(),
    callid VARCHAR(80) NOT NULL DEFAULT '',
    queuename VARCHAR(256) NOT NULL DEFAULT '',
    agent VARCHAR(80) NOT NULL DEFAULT '',
    event VARCHAR(32) NOT NULL DEFAULT '',
    data1 VARCHAR(100) NOT NULL DEFAULT '',
    data2 VARCHAR(100) NOT NULL DEFAULT '',
    data3 VARCHAR(100) NOT NULL DEFAULT '',
    data4 VARCHAR(100) NOT NULL DEFAULT '',
    data5 VARCHAR(100) NOT NULL DEFAULT ''
);
```

### Índices Recomendados

```sql
CREATE INDEX idx_queue_log_eventdate ON queue_log (eventdate);
CREATE INDEX idx_queue_log_callid ON queue_log (callid);
CREATE INDEX idx_queue_log_queuename ON queue_log (queuename);
CREATE INDEX idx_queue_log_agent ON queue_log (agent);
CREATE INDEX idx_queue_log_event ON queue_log (event);
CREATE INDEX idx_queue_log_eventdate_event ON queue_log (eventdate, event);
CREATE INDEX idx_queue_log_eventdate_queue_event ON queue_log (eventdate, queuename, event);
CREATE INDEX idx_queue_log_agent_event ON queue_log (agent, event);
```

### Mapeamento Completo de Eventos e Colunas Dinâmicas

#### Ciclo de Vida de uma Chamada na Fila

```
Chamada entra → ENTERQUEUE → espera → CONNECT → conversa → COMPLETECALLER/COMPLETEAGENT
                                    → ABANDON (se cliente desistir)
                                    → EXITWITHTIMEOUT (se tempo da fila estourar)
                                    → EXITEMPTY (se nenhum agente disponível)
                                    → EXITWITHKEY (se cliente pressionou tecla para sair)
```

#### Detalhamento por Evento

##### ENTERQUEUE — Cliente entrou na fila
```
eventdate: 2024-01-15 10:30:00
callid: 1705312200.42
queuename: suporte
agent: NONE
event: ENTERQUEUE
data1: (vazio ou URL)
data2: 5511999887766 (CallerID do cliente)
data3: 1 (posição na fila)
```

##### CONNECT — Agente atendeu a chamada
```
eventdate: 2024-01-15 10:30:15
callid: 1705312200.42
queuename: suporte
agent: PJSIP/1001
event: CONNECT
data1: 15 (⭐ TEMPO DE ESPERA em segundos - usado para TME e SLA)
data2: 1705312200.43 (uniqueid do canal do agente)
data3: (vazio)
```

##### COMPLETECALLER — Cliente desligou a chamada
```
eventdate: 2024-01-15 10:35:00
callid: 1705312200.42
queuename: suporte
agent: PJSIP/1001
event: COMPLETECALLER
data1: 15 (⭐ TEMPO DE ESPERA em segundos)
data2: 285 (⭐ TEMPO FALADO em segundos - usado para TMA)
data3: 1 (posição original na fila)
```

##### COMPLETEAGENT — Agente desligou a chamada
```
eventdate: 2024-01-15 10:35:00
callid: 1705312200.42
queuename: suporte
agent: PJSIP/1001
event: COMPLETEAGENT
data1: 15 (⭐ TEMPO DE ESPERA em segundos)
data2: 285 (⭐ TEMPO FALADO em segundos - usado para TMA)
data3: 1 (posição original na fila)
```

##### ABANDON — Cliente desistiu da espera
```
eventdate: 2024-01-15 10:31:30
callid: 1705312200.42
queuename: suporte
agent: NONE
event: ABANDON
data1: 1 (posição quando desistiu)
data2: 1 (posição original)
data3: 90 (⭐ TEMPO DE ESPERA antes de desistir - paciência do cliente)
```

##### RINGNOANSWER — Agente não atendeu o ring
```
eventdate: 2024-01-15 10:30:10
callid: 1705312200.42
queuename: suporte
agent: PJSIP/1002
event: RINGNOANSWER
data1: 15000 (⚠️ tempo de ring em MILISSEGUNDOS, não segundos)
```

##### TRANSFER / BLINDTRANSFER / ATTENDEDTRANSFER — Transferências
```
event: BLINDTRANSFER
data1: 2003 (extensão destino)
data2: from-internal (contexto)
data3: 15 (tempo de espera)
data4: 120 (tempo falado)
```

##### EXITWITHTIMEOUT — Saiu por timeout da fila
```
event: EXITWITHTIMEOUT
data1: 1 (posição)
data2: 1 (posição original)
data3: 180 (tempo de espera até timeout)
```

##### EXITEMPTY — Saiu porque fila ficou vazia
```
event: EXITEMPTY
data1: 1 (posição)
data2: 1 (posição original)
data3: 45 (tempo de espera)
```

##### EXITWITHKEY — Saiu pressionando tecla
```
event: EXITWITHKEY
data1: 1 (tecla pressionada)
data2: 2 (posição na fila)
```

##### PAUSE / UNPAUSE — Pausas do agente
```
-- Agente entrou em pausa
event: PAUSE
agent: PJSIP/1001
queuename: suporte (ou "all" se PAUSEALL)
data1: almoco (motivo da pausa, se configurado)

-- Agente saiu da pausa
event: UNPAUSE
agent: PJSIP/1001
queuename: suporte
data1: almoco (motivo da pausa)
```

##### AGENTLOGIN / AGENTLOGOFF — Login e Logoff
```
-- Login
event: AGENTLOGIN
agent: PJSIP/1001
data1: PJSIP/1001 (canal)

-- Logoff
event: AGENTLOGOFF
agent: PJSIP/1001
data1: PJSIP/1001 (canal)
data2: 28800 (tempo logado em segundos = 8 horas)
```

---

## Tabela `monitor_operador` (Customizada VoxCALL)

Tabela de estado em tempo real dos operadores do call center. Cada operador tem **um único registro** que é atualizado continuamente pelo sistema (não é histórico).

### Estrutura Completa

```sql
CREATE TABLE monitor_operador (
    id SERIAL PRIMARY KEY,
    operador VARCHAR(80) NOT NULL DEFAULT '',
    ramal VARCHAR(20) NOT NULL DEFAULT '',
    fl_pausa INTEGER NOT NULL DEFAULT 0,
    tipo_pausa VARCHAR(80) NOT NULL DEFAULT '',
    hora_entra_pausa TIMESTAMP,
    hora_sai_pausa TIMESTAMP,
    hora_login TIMESTAMP,
    hora_logoff TIMESTAMP,
    id_agentes_tela INTEGER NOT NULL DEFAULT 0,
    ultimo_atendimento TIMESTAMP,
    fl_atendimento VARCHAR(20) NOT NULL DEFAULT '',
    atendidas INTEGER NOT NULL DEFAULT 0
);
```

### Índices Recomendados

```sql
CREATE UNIQUE INDEX idx_monitor_operador_operador ON monitor_operador (operador);
CREATE INDEX idx_monitor_operador_ramal ON monitor_operador (ramal);
CREATE INDEX idx_monitor_operador_fl_pausa ON monitor_operador (fl_pausa);
CREATE INDEX idx_monitor_operador_hora_login ON monitor_operador (hora_login);
```

### Detalhamento das Colunas

| Coluna | Tipo | Descrição | Exemplos |
|--------|------|-----------|----------|
| `id` | serial | ID auto-incremento | 162430 |
| `operador` | varchar | Nome de usuário do operador | NAJILA, GLEICY.LIMA, CENTRE1 |
| `ramal` | varchar | Ramal associado ao operador | 118, 104, 800, 701 |
| `fl_pausa` | integer | Flag: 0 = disponível, 1 = em pausa | 0, 1 |
| `tipo_pausa` | varchar | Motivo da pausa | Banheiro, SUPERVISAO, Almoço, (vazio) |
| `hora_entra_pausa` | timestamp | Quando entrou na pausa | 2026-02-23 15:52:32 |
| `hora_sai_pausa` | timestamp | Quando saiu da última pausa | 2026-02-23 15:40:41 |
| `hora_login` | timestamp | Login do operador | 2026-02-23 09:01:41 |
| `hora_logoff` | timestamp | Logoff (NULL = ainda logado) | NULL |
| `id_agentes_tela` | integer | ID na tela de supervisão | 0 |
| `ultimo_atendimento` | timestamp | Último atendimento | 2026-02-23 15:43:57 |
| `fl_atendimento` | varchar | Em atendimento agora | (geralmente vazio) |
| `atendidas` | integer | Total atendidas desde o login | 28, 33, 41 |

### Lógica de Estados do Operador

```
LOGADO e DISPONÍVEL:    hora_logoff IS NULL AND fl_pausa = 0
LOGADO e EM PAUSA:      hora_logoff IS NULL AND fl_pausa = 1
DESLOGADO:              hora_logoff IS NOT NULL
SUPERVISOR:             tipo_pausa = 'SUPERVISAO'
EM ATENDIMENTO:         ultimo_atendimento recente (últimos segundos)
OCIOSO:                 fl_pausa = 0 AND ultimo_atendimento é antigo
```

### Exemplo de Registro Real

```
id: 162430
operador: NAJILA
ramal: 118
fl_pausa: 0              → Disponível
tipo_pausa: (vazio)       → Sem motivo de pausa
hora_entra_pausa: 13:14   → Última vez que entrou em pausa
hora_sai_pausa: 14:26     → Saiu da pausa às 14:26
hora_login: 09:01         → Logou às 9h01
hora_logoff: NULL         → Ainda logada
ultimo_atendimento: 15:43 → Último atendimento às 15:43
atendidas: 28             → 28 chamadas atendidas hoje
```

---

## Tabela `t_monitor_voxcall` (Customizada VoxCALL)

Registro de cada atendimento individual com dados enriquecidos. Diferente do `queue_log` que registra eventos, esta tabela registra **cada atendimento completo** com informações consolidadas.

### Estrutura Completa

```sql
CREATE TABLE t_monitor_voxcall (
    callid VARCHAR(80) NOT NULL DEFAULT '',
    operador VARCHAR(80) NOT NULL DEFAULT '',
    telefone VARCHAR(40) NOT NULL DEFAULT '',
    codgravacao VARCHAR(80) NOT NULL DEFAULT '',
    protocolo VARCHAR(40) NOT NULL DEFAULT '',
    fila VARCHAR(80) NOT NULL DEFAULT '',
    ramal VARCHAR(20) NOT NULL DEFAULT '',
    espera VARCHAR(20) NOT NULL DEFAULT '',
    hora_atendimento TIMESTAMP,
    canal VARCHAR(80) NOT NULL DEFAULT ''
);
```

### Índices Recomendados

```sql
CREATE INDEX idx_t_monitor_callid ON t_monitor_voxcall (callid);
CREATE INDEX idx_t_monitor_operador ON t_monitor_voxcall (operador);
CREATE INDEX idx_t_monitor_telefone ON t_monitor_voxcall (telefone);
CREATE INDEX idx_t_monitor_protocolo ON t_monitor_voxcall (protocolo);
CREATE INDEX idx_t_monitor_fila ON t_monitor_voxcall (fila);
CREATE INDEX idx_t_monitor_hora ON t_monitor_voxcall (hora_atendimento);
```

### Detalhamento das Colunas

| Coluna | Tipo | Descrição | Exemplos |
|--------|------|-----------|----------|
| `callid` | varchar | ID da chamada (liga com queue_log e cdr) | 1771873319.16517 |
| `operador` | varchar | Nome do operador (liga com monitor_operador) | VALDECLEIDE, GLEICY.LIMA |
| `telefone` | varchar | Número do cliente | 81992940294, 8134533365 |
| `codgravacao` | varchar | Código para localizar gravação | 1771873319.16517 |
| `protocolo` | varchar | Número de protocolo (YYYYMMDDHHMMSS) | 20260223160301 |
| `fila` | varchar | Fila de atendimento | Beneficiario, MaisOdonto |
| `ramal` | varchar | Ramal do operador | 116, 124, 121 |
| `espera` | varchar | Tempo que aguardou na fila (segundos) | 1, 5, (vazio) |
| `hora_atendimento` | timestamp | Horário do atendimento | 2026-02-23 16:03:07 |
| `canal` | varchar | Canal SIP (inclui IP do tronco) | SIP/187.72.45.132-000018ef |

### Formato do Protocolo

O protocolo é um identificador único gerado com timestamp:
```
Formato: YYYYMMDDHHmmSS
Exemplo: 20260223160301 → 2026-02-23 16:03:01
```
Este número é informado ao cliente como referência do atendimento.

### Exemplo de Registro Real

```
callid: 1771873319.16517
operador: VALDECLEIDE
telefone: 81992940294
codgravacao: 1771873319.16517
protocolo: 20260223160301
fila: Beneficiario
ramal: 116
espera: 1                      → Cliente esperou 1 segundo
hora_atendimento: 16:03:07
canal: SIP/187.72.45.132-000018ef
```

---

## Relação entre as 4 Tabelas

### Chaves de Ligação

```
cdr.uniqueid = queue_log.callid = t_monitor_voxcall.callid
t_monitor_voxcall.operador = monitor_operador.operador
```

### Diagrama de Relação

```
┌─────────────────────────────┐     ┌──────────────────────────────┐
│         cdr                 │     │        queue_log             │
├─────────────────────────────┤     ├──────────────────────────────┤
│ uniqueid ─────────────────────────── callid                     │
│ calldate                    │     │ eventdate                         │
│ src (origem)                │     │ queuename                    │
│ dst (destino)               │     │ agent                        │
│ duration                    │     │ event                        │
│ billsec                     │     │ data1 (dinâmico)             │
│ disposition                 │     │ data2 (dinâmico)             │
│ channel                     │     │ data3 (dinâmico)             │
│ dstchannel                  │     │ data4 (dinâmico)             │
│ lastapp                     │     │ data5 (dinâmico)             │
└──────────┬──────────────────┘     └──────────────┬───────────────┘
           │ 1 registro/chamada          N registros/chamada
           │                                        │
           │ uniqueid = callid          callid = callid
           │                                        │
┌──────────┴────────────────────────────────────────┴──────────────┐
│                    t_monitor_voxcall                              │
├──────────────────────────────────────────────────────────────────┤
│ callid ← liga com cdr.uniqueid e queue_log.callid               │
│ operador ← liga com monitor_operador.operador                   │
│ telefone, codgravacao, protocolo                                │
│ fila, ramal, espera, hora_atendimento, canal                    │
└──────────────────────────┬───────────────────────────────────────┘
                           │ 1 registro/atendimento
                           │
                           │ operador = operador
                           │
              ┌────────────┴──────────────┐
              │    monitor_operador       │
              ├───────────────────────────┤
              │ operador (único por agente)│
              │ ramal, fl_pausa            │
              │ tipo_pausa                 │
              │ hora_login, hora_logoff    │
              │ ultimo_atendimento         │
              │ atendidas                  │
              └───────────────────────────┘
                    1 registro/operador
```

### Importante sobre os JOINs

- `cdr` tem **1 registro** por chamada, `queue_log` tem **N registros** (eventos)
- `t_monitor_voxcall` tem **1 registro por atendimento** — só chamadas efetivamente atendidas
- `monitor_operador` tem **1 registro por operador** — estado atual, não histórico
- Ao cruzar com `queue_log`, filtrar por evento específico para evitar duplicação
- Nem toda chamada no CDR tem registros no queue_log (só as que passaram pela fila)
- O `callid` no queue_log pode ter valor `NONE` para eventos de agente (PAUSE, LOGIN)
- `t_monitor_voxcall` só contém chamadas atendidas — não tem abandonos ou timeouts

### Formato do `eventdate` no queue_log

Dependendo da versão do Asterisk e configuração do `queue_log` realtime:
- Pode ser **timestamp**: `2024-01-15 10:30:00`
- Pode ser **epoch Unix**: `1705312200`
- Pode ser **varchar ISO**: `2024-01-15T10:30:00.000-0300`

Ao criar queries, considere:
```sql
-- Se for timestamp nativo
WHERE eventdate >= '2024-01-15'::timestamp

-- Se for epoch como texto
WHERE TO_TIMESTAMP(eventdate::bigint) >= '2024-01-15'::timestamp

-- Se for varchar ISO
WHERE eventdate::timestamp >= '2024-01-15'::timestamp
```
