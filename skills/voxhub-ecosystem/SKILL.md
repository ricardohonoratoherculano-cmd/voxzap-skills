---
name: voxhub-ecosystem
description: Guia completo de implantação do Ecossistema Integrado VoxHub (Task #78) — integração entre VoxCALL, VoxZAP e VoxCRM com transcrição de chamadas (Whisper), resumo IA (GPT-4.1), nuvem de palavras, timeline unificada e busca full-text. Use quando for implantar, configurar, debugar ou estender o VoxHub em produção. Inclui checklist de deploy, configuração do VoxCALL (Asterisk), variáveis de ambiente, migração SQL, endpoints de API, e integração com VoxCRM.
---

# Ecossistema Integrado VoxHub — Guia de Implantação

## Visão Geral

O VoxHub é o módulo de integração que unifica dados de todos os sistemas Voxtel:
- **VoxZAP** (WhatsApp, Instagram, Messenger, Telegram, Email, WebChat)
- **VoxCALL** (Telefonia Asterisk — chamadas, transcrições, filas)
- **VoxCRM** (CRM — vendas, cobrança, atendimento)

Funcionalidades:
1. **Transcrição automática de chamadas** via OpenAI Whisper
2. **Resumo inteligente 1-clique** via GPT-4.1
3. **Nuvem de palavras em tempo real** com NLP em português
4. **Timeline unificada** de contatos (cross-plataforma)
5. **Busca global full-text** com PostgreSQL GIN index

## Status da Integração por Sistema

### VoxZAP — INTEGRADO (automático)
As mensagens de todos os canais já são capturadas automaticamente no VoxHub:
- `webhook.service.ts` → WhatsApp, Instagram, Messenger, Telegram (inbound)
- `email.service.ts` → Email (inbound)
- `routes.ts` → Mensagens enviadas pelo operador (outbound, todos os canais)

Função: `voxHubWebhookService.sendWebhookToHub(tenantId, canal, dados)` — fire-and-forget, não impacta o fluxo principal.

### VoxCALL — PRECISA CONFIGURAR
O VoxCALL (Asterisk) precisa enviar webhooks HTTP para o VoxZAP. Veja seção "Configuração do VoxCALL" abaixo.

### VoxCRM — FUTURO
A integração com VoxCRM será feita quando o CRM estiver em produção. Os endpoints de timeline e resumo já suportam dados do CRM via `hub_interactions`.

---

## Checklist de Implantação

### Passo 1: Variáveis de Ambiente (VoxZAP)

Definir no servidor de produção do VoxZAP:

```env
# OBRIGATÓRIO — Chave da OpenAI para Whisper (transcrição) e GPT-4.1 (resumos)
OPENAI_API_KEY=sk-...

# OBRIGATÓRIO — Secret para autenticar webhooks do VoxCALL
# Gerar com: openssl rand -hex 32
VOXCALL_WEBHOOK_SECRET=<secret-seguro-gerado>

# OBRIGATÓRIO — Secret para autenticar webhooks internos do VoxZAP
# Gerar com: openssl rand -hex 32
VOXZAP_WEBHOOK_SECRET=<secret-seguro-gerado>

# OPCIONAL — Hosts permitidos para download de gravações (SSRF protection)
# Se não definido, aceita qualquer host público
VOXCALL_RECORDING_HOSTS=voxtel.voxzap.app.br,gravacoes.voxcall.com.br

# OPCIONAL — Secrets por tenant (para multi-tenant com secrets isolados)
# Formato: VOXCALL_WEBHOOK_SECRET_<tenantId>
# VOXCALL_WEBHOOK_SECRET_1=<secret-tenant-1>
# VOXCALL_WEBHOOK_SECRET_2=<secret-tenant-2>
```

### Passo 2: Migração do Banco de Dados

Executar o SQL no PostgreSQL de produção:

```bash
# Via SSH no servidor de produção
psql -U postgres -d voxzap_production < prisma/migrations/20260405_voxhub_ecosystem/migration.sql
```

Ou via Docker:
```bash
docker exec -i voxzap-postgres psql -U postgres -d voxzap < migration.sql
```

**Tabelas criadas:**
- `call_transcriptions` — Transcrições de chamadas (Whisper)
- `interaction_summaries` — Resumos IA gerados (GPT-4.1)
- `word_cloud_data` — Dados da nuvem de palavras
- `hub_interactions` — Todas as interações unificadas (busca + timeline)

### Passo 3: Deploy do VoxZAP

Fazer deploy normalmente (Docker Compose ou o método usado):
```bash
docker-compose up -d --build voxzap-app
```

### Passo 4: Configuração do VoxCALL (Asterisk)

O VoxCALL precisa enviar webhooks HTTP quando eventos ocorrem. Essa configuração é feita **no projeto do VoxCALL**, não no VoxZAP.

#### Endpoints que o VoxCALL deve chamar:

**1. Chamada Finalizada:**
```
POST https://<dominio-voxzap>/api/hub/webhook/call-completed
Headers:
  x-webhook-secret: <VOXCALL_WEBHOOK_SECRET>
  x-tenant-id: <tenantId>
  Content-Type: application/json

Body:
{
  "event": "call-completed",
  "callId": "1712345678.123",        // uniqueid do Asterisk
  "callerNumber": "5585999999999",
  "agentName": "João Silva",
  "agentExtension": "1001",
  "queueName": "SAC Portaria",
  "duration": 180,                    // duração total em segundos
  "billsec": 120,                     // tempo de conversação
  "disposition": "ANSWERED",          // ANSWERED, NO ANSWER, BUSY, FAILED
  "direction": "INBOUND",             // INBOUND ou OUTBOUND
  "recordingUrl": "https://servidor/gravacoes/1712345678.123.mp3"
}
```

**2. Chamada Abandonada:**
```
POST https://<dominio-voxzap>/api/hub/webhook/call-abandoned
Headers:
  x-webhook-secret: <VOXCALL_WEBHOOK_SECRET>
  x-tenant-id: <tenantId>
  Content-Type: application/json

Body:
{
  "event": "call-abandoned",
  "callId": "1712345678.124",
  "callerNumber": "5585999999999",
  "queueName": "SAC Portaria",
  "waitTime": 45,                     // tempo de espera em segundos
  "position": 3                       // posição na fila quando abandonou
}
```

**3. Status do Agente:**
```
POST https://<dominio-voxzap>/api/hub/webhook/agent-status
Headers:
  x-webhook-secret: <VOXCALL_WEBHOOK_SECRET>
  x-tenant-id: <tenantId>
  Content-Type: application/json

Body:
{
  "event": "agent-status",
  "agentName": "João Silva",
  "agentExtension": "1001",
  "status": "AVAILABLE",              // AVAILABLE, BUSY, PAUSED, LOGGED_OUT
  "queueName": "SAC Portaria",
  "timestamp": "2026-04-05T10:30:00Z"
}
```

#### Implementação no VoxCALL (Node.js/TypeScript):

No projeto VoxCALL, criar um módulo de webhook sender:

```typescript
// Exemplo de implementação no VoxCALL
import axios from "axios";

const VOXZAP_BASE_URL = process.env.VOXZAP_BASE_URL; // ex: https://voxtel.voxzap.app.br
const WEBHOOK_SECRET = process.env.VOXCALL_WEBHOOK_SECRET;

async function sendToVoxHub(
  endpoint: string,
  tenantId: number,
  payload: Record<string, unknown>
): Promise<void> {
  try {
    await axios.post(`${VOXZAP_BASE_URL}/api/hub/webhook/${endpoint}`, payload, {
      headers: {
        "x-webhook-secret": WEBHOOK_SECRET,
        "x-tenant-id": String(tenantId),
        "Content-Type": "application/json",
      },
      timeout: 10000,
    });
  } catch (error) {
    console.error(`[VoxCALL->VoxHub] Webhook ${endpoint} failed:`, error.message);
  }
}

// Chamar após finalizar chamada no Asterisk (AMI/ARI event)
export async function onCallCompleted(callData: CallData, tenantId: number) {
  await sendToVoxHub("call-completed", tenantId, {
    event: "call-completed",
    callId: callData.uniqueid,
    callerNumber: callData.callerid,
    agentName: callData.agentName,
    agentExtension: callData.extension,
    queueName: callData.queue,
    duration: callData.duration,
    billsec: callData.billsec,
    disposition: callData.disposition,
    direction: callData.direction,
    recordingUrl: callData.recordingUrl,
  });
}
```

#### Variáveis de ambiente no VoxCALL:
```env
VOXZAP_BASE_URL=https://voxtel.voxzap.app.br
VOXCALL_WEBHOOK_SECRET=<mesmo-secret-definido-no-voxzap>
```

### Passo 5: Configuração do VoxCRM (Futuro)

Quando o VoxCRM estiver em produção, ele poderá enviar eventos para:

```
POST https://<dominio-voxzap>/api/hub/webhook/channel-message
Headers:
  x-webhook-secret: <VOXZAP_WEBHOOK_SECRET>
  x-tenant-id: <tenantId>

Body:
{
  "channel": "CRM",
  "contactNumber": "5585999999999",
  "body": "Acordo de cobrança registrado - R$ 1.500,00 em 3x",
  "direction": "SYSTEM",
  "agentName": "Maria Santos"
}
```

---

## Arquitetura Técnica

### Arquivos Principais (VoxZAP)

| Arquivo | Função |
|---------|--------|
| `server/services/voxhub.service.ts` | Serviço principal: transcrição, resumo IA, word cloud, timeline, busca |
| `server/services/voxhub-webhook.service.ts` | Processamento de webhooks + função sendWebhookToHub |
| `server/lib/stopwords-ptbr.ts` | Stopwords e tokenização para português brasileiro |
| `server/routes.ts` (seção VoxHub) | 9 endpoints da API REST |
| `client/src/pages/ecossistema.tsx` | Dashboard + nuvem de palavras + resumo IA |
| `client/src/pages/busca-global.tsx` | Busca full-text com filtros |
| `client/src/pages/transcricoes.tsx` | Lista de transcrições de chamadas |
| `prisma/schema.prisma` | Modelos: CallTranscriptions, InteractionSummaries, WordCloudData, HubInteractions |
| `prisma/migrations/20260405_voxhub_ecosystem/migration.sql` | SQL de criação das tabelas |

### Endpoints da API

| Método | Endpoint | Autenticação | Descrição |
|--------|----------|-------------|-----------|
| POST | `/api/hub/webhook/call-completed` | webhook secret | Recebe evento de chamada finalizada |
| POST | `/api/hub/webhook/call-abandoned` | webhook secret | Recebe evento de chamada abandonada |
| POST | `/api/hub/webhook/agent-status` | webhook secret | Recebe mudança de status do agente |
| POST | `/api/hub/webhook/channel-message` | webhook secret | Recebe mensagem de canal externo |
| GET | `/api/hub/dashboard` | JWT token | KPIs e estatísticas do ecossistema |
| GET | `/api/hub/contacts/:id/timeline` | JWT token | Timeline unificada do contato |
| GET | `/api/hub/contacts/:id/summary` | JWT token | Gera resumo IA do contato (1-clique) |
| GET | `/api/hub/wordcloud` | JWT token | Dados da nuvem de palavras |
| GET | `/api/hub/search?q=...` | JWT token | Busca full-text em interações |
| GET | `/api/hub/transcriptions` | JWT token | Lista transcrições de chamadas |
| POST | `/api/hub/transcribe` | JWT token (admin) | Transcreve áudio manualmente |

### Modelo de Dados

```
call_transcriptions
├── id (PK, serial)
├── callId (VARCHAR, unique por tenant)
├── tenantId (INT)
├── contactId (FK → Contacts)
├── transcription (TEXT)
├── summary (TEXT)
├── sentiment (VARCHAR: POSITIVE/NEGATIVE/NEUTRAL)
├── keywords (TEXT[])
├── recordingUrl (TEXT)
└── (agentName, agentExtension, queueName, duration, direction, callerNumber, language)

interaction_summaries
├── id (PK, serial)
├── contactId (FK → Contacts)
├── tenantId (INT)
├── summaryType (VARCHAR)
├── summary (TEXT)
├── highlights (JSONB)
├── sentiment (VARCHAR)
├── actionItems (JSONB)
└── (channels[], totalInteractions, generatedBy, period)

word_cloud_data
├── id (PK, serial)
├── word (VARCHAR)
├── frequency (INT)
├── channel (VARCHAR)
├── tenantId (INT)
├── queueName (VARCHAR, nullable)
├── period (VARCHAR, formato YYYY-MM-DD)
└── UNIQUE INDEX: (word, channel, tenantId, COALESCE(queueName,''), period)

hub_interactions
├── id (PK, serial)
├── contactId (FK → Contacts, nullable)
├── tenantId (INT)
├── channel (VARCHAR: WHATSAPP/INSTAGRAM/MESSENGER/TELEGRAM/EMAIL/TELEFONE/CRM)
├── direction (VARCHAR: INBOUND/OUTBOUND/SYSTEM)
├── content (TEXT)
├── contentType (VARCHAR: text/call/transcription/email)
├── externalId (VARCHAR, para deduplicação)
├── searchVector (TEXT)
└── GIN INDEX: to_tsvector('portuguese', content)
```

### Segurança

- **Webhook auth**: Header `x-webhook-secret` validado com timing-safe compare
- **Per-tenant secrets**: Suporta `VOXCALL_WEBHOOK_SECRET_<tenantId>` com fallback para global
- **Tenant validation**: Verifica existência do tenant no banco antes de processar
- **SSRF protection**: `validateAudioUrl()` bloqueia IPs privados (localhost, 10.x, 192.168.x, 172.x, 169.254.x, ::1)
- **Recording hosts allowlist**: `VOXCALL_RECORDING_HOSTS` para restringir domínios de gravação
- **SQL injection prevention**: Busca full-text usa `$queryRaw` parametrizado (tagged template literals)
- **Tenant isolation**: Todas as queries filtram por `tenantId`

### Fluxo de Dados

```
VoxCALL (Asterisk)
  │ chamada finalizada
  ▼
POST /api/hub/webhook/call-completed
  │ valida secret + tenant
  ▼
processCallCompleted()
  ├── recordInteraction() → hub_interactions (busca + timeline)
  ├── updateWordCloud() → word_cloud_data (nuvem de palavras)
  └── transcribeAudio() (async, fire-and-forget)
        ├── download gravação (SSRF validated)
        ├── OpenAI Whisper → transcrição
        ├── extractKeywords() → palavras-chave
        ├── GPT-4.1 → resumo + sentimento
        ├── save → call_transcriptions
        ├── recordInteraction() → hub_interactions (externalId: callId:transcription)
        └── updateWordCloud() → word_cloud_data
```

```
VoxZAP (mensagem recebida em qualquer canal)
  │
  ▼
sendWebhookToHub(tenantId, canal, dados)
  │ chamada interna direta (fire-and-forget)
  ▼
processChannelMessage()
  ├── resolve contactId via número/email
  ├── recordInteraction() → hub_interactions
  └── updateWordCloud() → word_cloud_data
```

---

## Troubleshooting

### Transcrição não funciona
1. Verificar se `OPENAI_API_KEY` está definida
2. Verificar se a URL de gravação é acessível (testar com `curl`)
3. Verificar se `VOXCALL_RECORDING_HOSTS` permite o host da gravação
4. Verificar logs: `[VoxHub] Transcription` no console

### Webhooks retornando 401
1. Verificar se `VOXCALL_WEBHOOK_SECRET` é igual nos dois sistemas
2. Verificar se o header `x-webhook-secret` está sendo enviado
3. Verificar se o header `x-tenant-id` está presente

### Webhooks retornando 403
1. O tenantId informado não existe no banco do VoxZAP
2. Verificar tabela `tenants` no PostgreSQL

### Nuvem de palavras vazia
1. As interações precisam acumular antes de gerar dados
2. Verificar tabela `word_cloud_data` no banco
3. Cada interação gera palavras para o período (data) atual

### Busca global sem resultados
1. Verificar se existem registros em `hub_interactions`
2. O índice GIN precisa existir: `hub_interactions_content_fts_idx`
3. Busca usa tokenização portuguesa — verificar se os termos buscados fazem sentido

---

## Evolução Futura

- [ ] Implementar job queue com BullMQ/Redis para processamento assíncrono de transcrições
- [ ] Integrar VoxCRM quando estiver em produção
- [ ] Dashboard de analytics avançado (tendências, comparação de períodos)
- [ ] Alertas automáticos baseados em sentimento negativo
- [ ] Exportação de relatórios consolidados (PDF/CSV)
- [ ] Widget de timeline unificada na tela de atendimento do ticket
