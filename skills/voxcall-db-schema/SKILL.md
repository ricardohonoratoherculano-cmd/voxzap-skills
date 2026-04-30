# VoxCALL Database Schema — Asterisk PostgreSQL

Referência completa do banco de dados PostgreSQL do Asterisk/VoxCALL hospedado no VPS (`modelo.voxtel.app.br:25432`, db=`asterisk`).

## Bootstrap Automático

O sistema `server/db-bootstrap.ts` executa automaticamente na inicialização do servidor:
- Lê `server/asterisk-schema.sql` (arquivo pg_dump completo)
- Converte para DDL idempotente (IF NOT EXISTS / CREATE OR REPLACE)
- Cria tabelas, sequences, funções, triggers e índices ausentes
- Não altera objetos existentes (seguro para rodar repetidamente)

### APIs de Bootstrap (superadmin only)
- `GET /api/db-bootstrap/status` — Verifica quais objetos existem/faltam
- `POST /api/db-bootstrap/run` — Executa o bootstrap manualmente

## Tabelas Principais (160 total)

### Core Asterisk/VoIP
| Tabela | Descrição |
|--------|-----------|
| `cdr` | Call Detail Records — registro de todas as chamadas. PK: `cdr_pkey` (serial). Campos: calldate, clid, src, dst, dcontext, channel, dstchannel, lastapp, lastdata, duration, billsec, disposition, amaflags, accountcode, uniqueid, userfield, did, linkedid |
| `cel` | Channel Event Logging — eventos detalhados do canal |
| `queue_log` | Log de filas do Asterisk. PK: `id` (serial). Campos: time (varchar), callid, queuename, agent, event, data, data1-data5, eventdate (timestamp). **SEMPRE use eventdate (timestamp) para filtros, NUNCA time (varchar)** |
| `queue_log_master` | Backup/master do queue_log |
| `queue_member_table` | Membros de filas do Asterisk (tabela real). uniqueid (serial PK), membername, queue_name, interface, penalty, paused, state_interface, comments |
| `queue_member_table_tela` | Gestão de membros (interface web). Mesmos campos + lógica de penalty |
| `queue_table` | Configuração de filas. name (PK), musiconhold, announce, context, timeout, retry, etc |
| `queue_retorno_config` | Configuração de retorno por fila. PK: queue_name. ativo, tempo_espera_min, prioridade |
| `sip_ramais` | Ramais SIP — todos os campos SIP (name, host, secret, context, etc) |
| `voicemail` | Caixas postais |
| `extensions` | Extensões do dialplan |

### Monitor/Operador
| Tabela | Descrição |
|--------|-----------|
| `monitor_operador` | Status em tempo real dos operadores. PK: id (serial). operador, ramal, fila, status, modo, canal, chamada_uniqueid, codgravacao, protocolo, telefone |
| `monitor_voxcall` | Monitor de chamadas VoxCALL |
| `t_monitor_voxcall` | Monitor VoxCALL (com REPLICA IDENTITY FULL). callid, operador, telefone, codgravacao, protocolo, fila, ramal, espera, hora_atendimento, canal |
| `relatorio_operador` | Relatório diário por operador/fila. PK: id (serial). UNIQUE(data, operador, fila). atendidas, ignoradas, transferidas, tempo_total/max/min_atendimento |
| `pausas_operador` | Histórico de pausas. PK: id_pausa (serial). operador, ramal, fila, tipo_pausa, motivo_pausa, data_pausa, hora_inicio, hora_fim, duracao_segundos |
| `relatorio_hora_voxcall` | Relatório por hora |
| `registros_gerais` | Registros gerais consolidados. PK: id (serial) |

### Retorno de Chamadas
| Tabela | Descrição |
|--------|-----------|
| `retorno_clientes` | Clientes para retorno automático. PK: id (serial). telefone, fila_origem, data_abandono, callid_original, tentativas, status, operador, data_retorno |
| `retorno_historico` | Histórico de retornos. PK: id (serial). Mesmos campos + resultado |

### Discador Preditivo (Task #16)
| Tabela | Descrição |
|--------|-----------|
| `dialer_campaigns` | Campanhas do discador. PK: id (serial). name, queue, status, max_concurrent, dial_ratio, etc |
| `dialer_mailing` | Mailing das campanhas. PK: id (serial). campaign_id (FK), phone, client_name, status |
| `dialer_call_logs` | Log de discagens. PK: id (serial). campaign_id, mailing_id, channel, uniqueid, status, duration |
| `dialer_operator_sessions` | Sessões dos operadores. PK: id (serial). operator, extension, queue, status |
| `cliente_voxdial` | Clientes do discador VoxDial. PK: id_erp_crm |
| `voxdial` | Configuração VoxDial. PK: id (serial) |
| `voxdial_mailling` | Mailing VoxDial (17 telefones) |
| `voxdial_mailling4` | Mailing VoxDial (4 telefones) |

### Segurança/Usuários
| Tabela | Descrição |
|--------|-----------|
| `sec_users` | Usuários do sistema. PK: login. pswd, name, email, active, priv_admin |
| `sec_groups` | Grupos de permissão. PK: group_id (serial) |
| `sec_apps` | Aplicações/módulos. PK: app_name |
| `sec_groups_apps` | Permissões grupo×app. PK: (group_id, app_name). priv_access/insert/delete/update/export/print |
| `sec_users_groups` | Associação usuário×grupo. PK: (login, group_id) |
| `seg_usuarios` / `seg_usuarios_voxcall` | Usuários de segurança |
| `login_voxcall_menus` | Menus acessíveis por usuário. PK: id (serial) |

### CRM/Vendas (VoxCRM)
| Tabela | Descrição |
|--------|-----------|
| `tb_contacts` | Contatos. PK: contact_id (serial) |
| `tb_organizations` | Organizações. PK: organization_id (serial) |
| `tb_deals` | Negócios. PK: deals_id (serial) |
| `tb_sellers` | Vendedores. PK: sellers_id (serial) |
| `tb_activities` | Atividades. PK: activities_id (serial) |
| `tb_products` | Produtos. PK: product_id (serial) |
| `tb_emails` | Emails enviados. PK: email_id (serial) |
| `tb_files` | Arquivos anexados. PK: files_id (serial) |

### Billing/Tarifação
| Tabela | Descrição |
|--------|-----------|
| `clientebilling` | Clientes de billing |
| `linhabilling` | Linhas de billing |
| `planobilling` | Planos de billing |
| `projetobilling` | Projetos de billing |
| `tabelabilling` | Tabela de tarifas |
| `tarifador` | Tarifador |

### Configuração/Diversos
| Tabela | Descrição |
|--------|-----------|
| `callback` | Callbacks agendados. PK: id (serial) |
| `agendamento` | Agendamentos. PK: id (serial) |
| `scripts_atendimento` | Scripts de atendimento. PK: id (serial). UNIQUE(nome) |
| `pesquisa_satisfacao` | Pesquisa de satisfação. PK: id (serial). Schema legacy do Asterisk: colunas genéricas `vago1..vago4`. **`vago1` = uniqueid da chamada original** (FK lógica para `cdr.uniqueid` e `t_monitor_voxcall.callid`); **`vago2` = sub-nota** (string). NÃO existe coluna `motivo`. Trigger BEFORE/AFTER INSERT `enriquece_pesquisa_satisfacao` faz lookup em `t_monitor_voxcall.callid = NEW.vago1` para popular `fila`/`operador` (que entram vazios pelo módulo C da URA *100@MANAGER). Para puxar duração da chamada no relatório use subquery correlata `(SELECT MAX(billsec)::int FROM cdr WHERE uniqueid = p.vago1)` — o MAX evita duplicação quando o uniqueid tem múltiplas pernas no CDR. |
| `servidor_manager` | Servidores gerenciados. PK: id (serial) |
| `webcall` | WebCall click-to-call. PK: id_webcall (serial) |
| `portabilidade` | Portabilidade numérica |
| `cadastro_ramais` | Cadastro de ramais |

## Funções PostgreSQL (13 total)

| Função | Trigger? | Descrição |
|--------|----------|-----------|
| `fn_atualiza_relatorio_operador()` | Sim (queue_log AFTER INSERT) | Atualiza relatorio_operador com contadores de atendidas/ignoradas/transferidas e tempos |
| `funcao_registros_gerais()` | Sim (queue_log AFTER INSERT) | Consolida dados em registros_gerais |
| `funcao_registros_gerais_cdr()` | Sim (cdr AFTER INSERT) | Consolida dados CDR em registros_gerais |
| `monitor_voxcall()` | Sim (queue_log AFTER INSERT) | Atualiza monitor VoxCALL em tempo real |
| `fn_normaliza_transferencia()` | Sim (queue_log BEFORE INSERT) | Marca transferências com data5='TRANSFERENCIA' |
| `fn_sincronizar_penalty()` | Sim (queue_member_table BEFORE INSERT) | Sincroniza penalty da tela para tabela real |
| `fn_sync_monitor_to_queue()` | Sim (monitor_operador AFTER DELETE/UPDATE) | Sincroniza monitor com fila |
| `fn_auto_queueid_protocolo()` | Sim (queue_log AFTER INSERT) | Gera protocolo automático |
| `fn_corrige_data2_prefixo()` | Sim (retorno_clientes BEFORE INSERT/UPDATE) | Remove prefixo '00' do telefone |
| `trg_registra_pausa()` | Sim (monitor_operador AFTER INSERT/UPDATE) | Registra pausas em pausas_operador |
| `fn_cel_captura_canal()` | Sim (cel AFTER INSERT) | Captura canal do CEL |
| `fn_canal_chamada_cleanup()` | Sim (canal_chamada, periódico) | Limpa canais antigos |
| `gerar_senha()` | Não | Gera senha aleatória 6 dígitos |
| `get_unique_code()` | Não | Retorna timestamp como código único |
| `pause_queue()` | Não | Pausa/despausa agente na fila |

## Triggers (12 total)

| Trigger | Tabela | Evento | Função |
|---------|--------|--------|--------|
| `executa_funcao_registros_gerais_cdr` | cdr | AFTER INSERT | funcao_registros_gerais_cdr() |
| `executa_t_monitor_voxcall` | queue_log | AFTER INSERT | monitor_voxcall() |
| `trg_atualiza_relatorio_operador` | queue_log | AFTER INSERT | fn_atualiza_relatorio_operador() |
| `trg_auto_queueid_protocolo` | queue_log | AFTER INSERT | fn_auto_queueid_protocolo() |
| `trg_normaliza_transferencia` | queue_log | BEFORE INSERT | fn_normaliza_transferencia() |
| `trg_registros_gerais` | queue_log | AFTER INSERT | funcao_registros_gerais() |
| `trg_before_insert_update_retorno_clientes` | retorno_clientes | BEFORE INSERT/UPDATE | fn_corrige_data2_prefixo() |
| `trg_busca_penalty_antes_de_inserir` | queue_member_table | BEFORE INSERT | fn_sincronizar_penalty() |
| `trg_sync_monitor_to_queue` | monitor_operador | AFTER DELETE/UPDATE | fn_sync_monitor_to_queue() |
| `trigger_salva_historico_pausas` | monitor_operador | AFTER INSERT/UPDATE | trg_registra_pausa() |
| `trg_cel_captura_canal` | cel | AFTER INSERT | fn_cel_captura_canal() |
| `trg_canal_chamada_cleanup` | canal_chamada | periódico | fn_canal_chamada_cleanup() |

## Índices Importantes

### queue_log (performance crítica)
- `idx_queue_log_eventdate` — filtro por data (USE SEMPRE eventdate, nunca time)
- `idx_queue_log_event` — filtro por tipo de evento
- `idx_queue_log_queuename` — filtro por fila
- `idx_queue_log_callid` — busca por callid
- `idx_queue_log_time` — índice no campo time (varchar)

### cdr
- `idx_cdr_calldate` — filtro por data
- `idx_cdr_src` — filtro por origem
- `idx_cdr_dst` — filtro por destino
- `idx_cdr_disposition` — filtro por resultado
- `idx_cdr_uniqueid` — busca por uniqueid

### relatorio_operador
- `idx_relatorio_operador_data_operador` — busca por data+operador
- `idx_relatorio_operador_data_fila` — busca por data+fila
- `idx_relatorio_operador_operador` — busca por operador
- UNIQUE constraint em (data, operador, fila)

### pausas_operador
- `idx_pausas_data` — filtro por data_pausa
- `idx_pausas_operador` — filtro por operador

### retorno_historico
- `idx_retorno_hist_data_abandono` — filtro por data abandono
- `idx_retorno_hist_fila_origem` — filtro por fila
- `idx_retorno_hist_operador` — filtro por operador
- `idx_retorno_hist_status_data` — filtro por status+data
- `idx_retorno_hist_tel_status` — filtro por telefone+status

## Regras Obrigatórias

1. **SEMPRE** use `ql.eventdate` (timestamp) para filtros no queue_log, NUNCA `ql.time` (varchar)
2. **SEMPRE** use `TO_CHAR(eventdate, 'DD/MM/YYYY HH24:MI:SS')` para formatação de datas
3. **SEMPRE** use `context: 'MANAGER'` em ações ARI/AMI
4. **DB Routing**: `withExternalPg` para WRITES + relatórios; `withReplicaPg` para Dashboard reads
5. **Timezone**: O banco usa timezone do servidor (America/Sao_Paulo)
6. O campo `data` em queue_log pode conter o operador (em eventos CONNECT, RINGNOANSWER) ou tempo de espera
7. Transferências são marcadas com `data5 = 'TRANSFERENCIA'` pelo trigger
