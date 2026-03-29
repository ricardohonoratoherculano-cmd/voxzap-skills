---
name: diagnostic-assistant-expert
description: Especialista no Assistente de Diagnóstico VoxCALL — agente de IA com GPT-4.1 que diagnostica e resolve problemas de Asterisk/VoIP/PostgreSQL via SSH, ARI, AMI e banco de dados. Use quando o usuário pedir para modificar, melhorar, depurar ou estender o assistente diagnóstico, incluindo base de conhecimento, ferramentas, prompts, fluxo de diagnóstico, relatórios técnicos, ou qualquer funcionalidade do chat de diagnóstico. Inclui arquitetura completa, referência de ferramentas, base de conhecimento, e padrões de segurança.
---

# Assistente de Diagnóstico VoxCALL — Skill Completa

Skill para desenvolvimento e manutenção do Assistente de Diagnóstico, um agente de IA especializado que diagnostica e resolve problemas em sistemas Asterisk/VoIP/PostgreSQL/Docker em produção.

## Quando Usar

- Modificar ou melhorar o Assistente de Diagnóstico (prompt, ferramentas, KB)
- Adicionar novas ferramentas de diagnóstico
- Expandir a base de conhecimento
- Depurar problemas do próprio assistente (respostas incorretas, tool calls falhando)
- Melhorar a qualidade das respostas ou precisão do diagnóstico
- Implementar novas funcionalidades (relatórios, automações, alertas)
- Ajustar parâmetros do modelo (temperatura, tokens, iterações)

## Arquitetura

### Arquivos Principais

| Arquivo | Responsabilidade |
|---------|-----------------|
| `server/diagnostic-agent.ts` | Lógica do agente: system prompt, tool definitions, tool execution, chat loop |
| `server/diagnostic-knowledge.ts` | Base de conhecimento: system KB, config KB, custom KB, search, context builder |
| `client/src/pages/diagnostic-assistant.tsx` | Frontend: chat UI, histórico, botões de ação |
| `server/routes.ts` | Endpoints API: `/api/diagnostic/chat`, `/api/diagnostic/knowledge/*` |
| `server/openai.ts` | Cliente OpenAI compartilhado |

### Fluxo de Processamento

```
Usuário → POST /api/diagnostic/chat
  → processDiagnosticChat(message, history, userId)
    → buildDiagnosticSystemPrompt()
      → buildDiagnosticContext() ← carrega TODA a base de conhecimento
    → OpenAI GPT-4.1 Chat Completion (com tools)
    → Loop até 15 iterações:
      → Se tool_calls: executeDiagTool() → adiciona resultado → próxima iteração
      → Se text response: retorna ao usuário
```

### Modelo e Parâmetros

- **Modelo**: `gpt-4.1` (melhor instruction following e tool use que gpt-4o)
- **Max completion tokens**: 16384
- **Max iterações de tool loop**: 15
- **Sem temperatura definida** (usa default do modelo)

## Base de Conhecimento

### Três Fontes

1. **System KB** (`buildSystemKnowledge()`): Entradas hardcoded no código, conhecimento estático da plataforma
2. **Config KB** (`loadConfigKnowledge()`): Carregadas dinamicamente dos arquivos JSON de configuração
3. **Custom KB** (`loadCustomKnowledge()`): Entradas criadas pelo usuário via interface, salvas em `diagnostic-kb-custom.json`

### Entradas de Sistema (31 entradas ativas)

| ID | Categoria | Conteúdo |
|----|-----------|----------|
| `sys-architecture` | Arquitetura | Containers, Docker Compose, volumes |
| `sys-two-databases` | Banco de Dados | 2 PostgreSQL separados (asterisk vs voxcall) |
| `sys-timezone` | Infraestrutura | Timezone America/Sao_Paulo, /etc/localtime |
| `sys-dialplan-safety` | Infraestrutura | Regras de edição do dialplan, proteções |
| `sys-pjsip` | PJSIP | Templates, NAT, formato obrigatório |
| `sys-audio-troubleshoot` | Troubleshooting | Sem áudio, unidirecional, cortando |
| `sys-registration-troubleshoot` | Troubleshooting | Registro SIP, erros 401/403/408 |
| `sys-docker-troubleshoot` | Troubleshooting | Containers, PostgreSQL, configs |
| `sys-dns-resolver` | Troubleshooting | DNS em Docker, res_resolver_unbound |
| `sys-firewall-security` | Segurança | VoxGuard v1.2 (Docker/native dual mode), portas, nftables |
| `sys-queues-callcenter` | Call Center | Filas, eventos, KPIs |
| `sys-access-patterns` | Acesso | SSH, Docker exec, PostgreSQL, ARI |
| `sys-common-issues` | Troubleshooting | Problemas comuns e soluções rápidas |
| `sys-default-credentials` | Credenciais | Onde ficam, carregamento automático |
| `sys-asterisk-cli-reference` | Asterisk CLI | Comandos core, pjsip, dialplan, queue, module |
| `sys-asterisk-dialplan-deep` | Dialplan | Sintaxe, variáveis, aplicações, padrões |
| `sys-asterisk-pjsip-deep` | PJSIP | Templates completos, transports, trunks, NAT |
| `sys-sip-protocol-deep` | Protocolo SIP | Métodos, códigos, headers, fluxos |
| `sys-rtp-media-deep` | Mídia/RTP | Codecs, qualidade (MOS), conversão GSM→MP3 |
| `sys-nat-networking-deep` | Rede/NAT | STUN/TURN/ICE, NAT types, tcpdump |
| `sys-postgresql-deep` | PostgreSQL | CDR queries, queue_log, manutenção |
| `sys-linux-docker-deep` | Linux/Docker | Administração de servidor VoIP |
| `sys-queue-callcenter-deep` | Call Center | Configuração avançada, KPIs, diagnóstico |
| `sys-asterisk-recordings-deep` | Gravações | MixMonitor, GSM→MP3, troubleshooting |
| `sys-odbc-realtime` | ODBC/Realtime | Configuração ODBC com PostgreSQL |
| `sys-asterisk-security` | Segurança | Ataques, VoxGuard v1.2 (auto-detect Docker/native, nftables, email alerts), boas práticas |
| `sys-webrtc-troubleshoot` | WebRTC | Configuração, STUN/TURN, diagnóstico |
| `sys-ami-ari-deep` | ARI/AMI | Referência completa das interfaces |
| `sys-troubleshoot-methodology` | Metodologia | Checklists para cada tipo de problema |
| `sys-transfer-types` | Transferência | Blind/attended, AMI actions |
| `sys-ura-ivr` | URA/IVR | Configuração e troubleshooting |

### Entradas de Configuração (carregadas de arquivos JSON)

| ID | Arquivo Fonte | Conteúdo |
|----|---------------|----------|
| `config-ssh` | `ssh-config.json` | Credenciais SSH da VPS |
| `config-ssh-asterisk` | `ssh-config-asterisk.json` | SSH do servidor Asterisk |
| `config-database` | `db-config.json` | PostgreSQL do Asterisk |
| `config-ari` | `ari-config.json` | ARI (REST API) |
| `config-ami` | `ami-config.json` | AMI (Manager Interface) |
| `config-sip-webrtc` | `sip-webrtc-config.json` | SIP/WebRTC/STUN/TURN |
| `config-smtp` | `smtp-config.json` | Email SMTP |
| `config-system` | `system-settings.json` | Configurações gerais |
| `config-recordings` | `asterisk-recordings-config.json` | Gravações |

### Segurança de Credenciais

- Config KB usa `maskPassword()` para mascarar senhas no contexto do prompt
- Senhas são truncadas: `abc*****` (3 chars visíveis + asteriscos)
- System KB **NUNCA** deve conter credenciais hardcoded (movidas para config)
- Custom KB é salva em arquivo JSON (pode conter dados sensíveis — cuidado)

### Como Adicionar Entradas de Sistema

Editar `buildSystemKnowledge()` em `server/diagnostic-knowledge.ts`:

```typescript
{
  id: 'sys-novo-topico',
  category: 'Categoria',
  title: 'Título Descritivo',
  content: [
    'CONTEÚDO DO CONHECIMENTO:',
    '',
    'Informações estruturadas...',
  ].join('\n'),
  tags: ['tag1', 'tag2', 'tag3'],
  source: 'system',
},
```

**Regras para novas entradas:**
- `id` deve começar com `sys-` e ser único
- `tags` devem incluir termos de busca relevantes (acentuados e sem acento)
- `content` deve ser auto-contido (não referenciar outras entradas)
- NUNCA incluir credenciais (senhas, tokens, API keys) em system KB
- Preferir formato de lista com hierarquia visual (===, ---, •)

## Ferramentas (Tools)

### Definições em `DIAG_TOOL_DEFINITIONS`

| Ferramenta | Descrição | Parâmetros |
|-----------|-----------|------------|
| `execute_asterisk_command` | Executa comando no CLI do Asterisk via `docker exec` | `command` (string) |
| `execute_system_command` | Executa comando Linux na VPS via SSH | `command` (string) |
| `query_database` | Executa SELECT no PostgreSQL do Asterisk | `query` (string, apenas SELECT) |
| `check_network` | Teste de rede (ping, traceroute, DNS, portas) | `type`, `target`, `port?` |
| `edit_asterisk_config` | Edita arquivo de config do Asterisk via sed | `file`, `old_value`, `new_value` |
| `restart_docker_service` | Reinicia container Docker | `service` |
| `generate_technical_report` | Gera relatório técnico formatado | `issue`, `findings`, `recommendations` |
| `lookup_system_info` | Consulta a base de conhecimento | `query` |
| `add_dialplan_entry` | Adiciona rota DID ao dialplan com segurança | `config_file`, `entry_content` |

### Proteções de Segurança Implementadas

**`edit_asterisk_config`:**
- Bloqueia arquivos protegidos: `extensions.conf`, `asterisk.conf`, `modules.conf`
- Bloqueia edições multi-linha (conteúdo com `\n`)
- Valida contagem de linhas após edição
- Faz backup antes de editar

**`execute_system_command`:**
- Bloqueia comandos destrutivos: `rm -rf /`, `mkfs`, `dd`, `shutdown`, `reboot`
- Bloqueia escrita em `extensions.conf` (via sed, echo, cat, tee, etc.)
- Timeout de 30s para evitar comandos que travem

**`add_dialplan_entry`:**
- Verifica duplicatas antes de inserir
- Faz backup do arquivo original
- Valida o dialplan após inserção (`dialplan reload` + `dialplan show`)
- Apenas para arquivos incluídos (não edita `extensions.conf`)

**`query_database`:**
- Apenas queries SELECT (bloqueia INSERT, UPDATE, DELETE, DROP, ALTER)
- Usa conexão dedicada (`withExternalPgDiag()`)

### Como Adicionar Nova Ferramenta

1. Adicionar definição em `DIAG_TOOL_DEFINITIONS` (formato OpenAI function calling):
```typescript
{
  type: "function" as const,
  function: {
    name: "nova_ferramenta",
    description: "Descrição clara do que faz",
    parameters: {
      type: "object",
      properties: {
        param1: { type: "string", description: "Descrição" },
      },
      required: ["param1"],
    },
  },
},
```

2. Adicionar case em `executeDiagTool()`:
```typescript
case 'nova_ferramenta':
  return await novaFerramentaImpl(args as NovaFerramentaArgs);
```

3. Implementar a função com tratamento de erro robusto
4. Documentar no system prompt (seção FERRAMENTAS DISPONÍVEIS)

## System Prompt

### Estrutura

```
1. Apresentação do papel (especialista técnico)
2. Base de conhecimento completa (injetada por buildDiagnosticContext)
3. Regras de acesso (SSH, DB, ARI, AMI)
4. Regra dos dois bancos de dados
5. Metodologia de diagnóstico (5 passos)
6. Cadeia de pensamento obrigatória
7. 18 regras operacionais
8. Formato de resposta
9. Descrição das ferramentas
```

### Cadeia de Pensamento (Chain of Thought)

O prompt exige que antes de qualquer ação que modifique configuração:
1. Explique ao usuário o que vai fazer e por quê
2. Mostre a alteração específica
3. Aguarde confirmação para ações destrutivas
4. Verifique o resultado após execução

**Nota:** Esta é enforcement por prompt, não por código. Para enforcement real, seria necessário adicionar lógica de confirmação no `executeDiagTool()`.

## Regras Críticas (Obrigatórias)

### Docker
- VoxCALL app: `docker compose -p voxcall -f docker-compose.yml`
- Asterisk: `docker compose -p voxcall-asterisk -f docker-compose.asterisk.yml`
- NUNCA `docker compose` sem `-p` e `-f`
- NUNCA `--remove-orphans`
- NUNCA adicionar `mem_limit`, `cpus` ou `deploy.resources.limits` — containers devem acessar 100% dos recursos da VPS dinamicamente

### Docker Resource Priority (OOM)
Prioridade de proteção contra OOM killer (menor = mais protegido):
- `voxcall-asterisk`: **-1000** (protegido — nunca encerrado)
- `voxcall-asterisk-db`: **-900** (último recurso)
- `voxcall-db`: **-500** (prioridade média)
- `voxcall-app`: **300** (primeiro a ser encerrado, reinicia automaticamente)
- Performance: `shm_size` 512mb (Asterisk DB), 256mb (VoxCALL DB); `ulimits` nofile/nproc=65536 (Asterisk)

### Certificado SSL/WSS Automático no Deploy
O deploy do Asterisk agora configura automaticamente o certificado SSL para WebRTC (WSS porta 8089):
- `docker-compose.asterisk.yml` monta `/etc/letsencrypt:/etc/letsencrypt:ro` no container
- Deploy script detecta se existe cert Let's Encrypt para o domínio configurado
- Se existe: configura `http.conf` com paths corretos (`/etc/letsencrypt/live/<dominio>/`)
- Se não existe: gera certificado auto-assinado como fallback
- Pós-deploy: aplica config dentro do container, faz `core reload`, verifica porta 8089
- Também atualiza `external_media_address`/`external_signaling_address` no `pjsip_wizard.conf` com IP externo
- **Pré-requisito**: SSL do VoxCALL (Step 7) deve ser instalado ANTES do deploy do Asterisk

### Dois Bancos de Dados
- `voxcall-asterisk-db`: user=`asterisk`, db=`asterisk`, porta 25432 (CDR, queue_log)
- `voxcall-db`: user=`voxcall`, db=`voxcall`, porta 5432 (app data)
- NUNCA `-U postgres` (role não existe)

### Dialplan
- `extensions.conf` contém APENAS `#include` — NUNCA editar diretamente
- Usar `add_dialplan_entry` para rotas DID
- `edit_asterisk_config` bloqueia arquivos protegidos
- Sempre verificar resultado com `dialplan show` após edição

### Queue_log
- SEMPRE usar `ql.eventdate` (timestamp), NUNCA `ql.time` (varchar)

### Arquitetura Trigger-Based (Migração 2026-03-14)
- TODA lógica de monitoramento de filas é feita via triggers no PostgreSQL
- O dialplan (filas.conf) é simplificado: apenas Queue(), MixMonitor(), Playback()
- NÃO há mais System(psql...), AGI scripts PHP, ou ODBC writes para monitoramento
- 5 triggers ativos no queue_log:
  - `trg_registros_gerais` → `funcao_registros_gerais()`: INSERT/UPDATE registros_gerais
  - `trg_auto_queueid_protocolo` → `fn_auto_queueid_protocolo()`: queueid + protocolo
  - `executa_t_monitor_voxcall` → `monitor_voxcall()`: t_monitor_voxcall + relatorios
  - `trg_atualiza_relatorio_operador` → `fn_atualiza_relatorio_operador()`: relatorio_operador
  - `trg_normaliza_transferencia` → `fn_normaliza_transferencia()`: normaliza transferências
- Scripts AGI deprecated: InsertMonitorAgi.php, InsertMonitorPhp.php
- ODBC deprecated: QUEUEID_INSERT/DELETE, PROTOCOLO_INSERT (func_odbc.conf)

### ARI/AMI
- SEMPRE usar `context: 'MANAGER'` em todas as operações

### SQL em routes.ts
- Usar concatenação de string (`+`), NUNCA template literals

## Skills Relacionadas

- **asterisk-ari-expert**: Para desenvolvimento de features ARI (originar chamadas, dashboards, controle de canais)
- **asterisk-callcenter-expert**: Para relatórios de call center, KPIs, queries de queue_log e CDR
- **voxfone-telephony-crm**: Para features do CRM (softphone, CDR reports, extensões, agendas, auth)
- **deploy-assistant-vps**: Para deploy em VPS via Docker Compose, nginx, SSL

## Troubleshooting do Próprio Assistente

### Respostas incorretas ou "inventadas"
- Verificar se a base de conhecimento tem informação relevante
- Adicionar entradas mais específicas ao system KB
- Aumentar max_completion_tokens se respostas estão truncadas

### Tool calls falhando
- Verificar logs do servidor: `docker logs voxcall-app`
- Verificar se SSH está acessível (ssh-config.json)
- Verificar se PostgreSQL está rodando (db-config.json)
- Verificar se ARI/AMI estão acessíveis

### Assistente muito lento
- GPT-4.1 é mais lento que GPT-4o-mini
- O system prompt é grande (~100k chars com toda a KB)
- Considerar implementar busca relevante em vez de injetar tudo
- Reduzir max_iterations se problemas simples não precisam de 15 iterações

### Assistente não usa ferramentas
- Verificar se DIAG_TOOL_DEFINITIONS está correto
- Verificar se o modelo suporta function calling
- O system prompt deve incentivar uso proativo de ferramentas
