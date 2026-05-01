---
name: whatsapp-messaging-expert
description: Especialista em WhatsApp Cloud API e mensageria para o projeto VoxZap. Use quando o usuário pedir para criar, modificar ou debugar qualquer funcionalidade relacionada a envio/recebimento de mensagens WhatsApp, webhooks Meta, templates, mídia, tickets, filas, contatos, renderização de mensagens no chat, Socket.io real-time, ou integração com a Meta Graph API. Inclui referência completa da arquitetura, padrões de código, tabelas do banco, e fluxos end-to-end.
---

# Especialista WhatsApp & Mensageria - VoxZap

Skill para desenvolvimento e manutenção de todas as funcionalidades de mensageria WhatsApp do projeto VoxZap — sistema multi-tenant de gestão de comunicação via WhatsApp Business Cloud API.

## Quando Usar

- Enviar ou receber mensagens de qualquer tipo (texto, mídia, template, interativo, localização, contato, reação)
- Processar ou debugar webhooks da Meta (mensagens recebidas, status de entrega)
- Gerenciar templates de mensagem (criar, editar, deletar, sincronizar)
- Fazer upload/download de mídia (imagens, vídeos, áudios, documentos)
- Gerenciar canais/conexões WhatsApp (WABA)
- Criar ou modificar renderização de mensagens no frontend (chat)
- Implementar lógica de tickets, filas, transferências
- Trabalhar com Socket.io para atualizações em tempo real
- Debugar problemas de entrega, status, ou formatação de mensagens
- Converter áudio para formato compatível com WhatsApp

## Arquitetura Geral

```
┌─────────────────────────────────────────────────────────────┐
│                     FRONTEND (React)                         │
│  client/src/pages/atendimento.tsx  ←  Chat + Ticket UI       │
│  client/src/pages/dashboard.tsx    ←  Métricas (admin)         │
│  client/src/pages/operator-dashboard.tsx ← Métricas (operador) │
│  client/src/pages/channels.tsx     ←  Gestão de Conexões     │
│  client/src/pages/templates.tsx    ←  Gestão de Templates    │
└────────────┬──────────────────────────────┬──────────────────┘
             │ REST API                     │ Socket.io
             ▼                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     BACKEND (Express)                        │
│  server/routes.ts              ←  Todas as rotas REST        │
│  server/websocket/socket.ts    ←  WebSocket / Socket.io      │
│  server/services/              ←  Lógica de negócio          │
│  server/repositories/          ←  Acesso ao banco (Prisma)   │
└────────────┬──────────────────────────────┬──────────────────┘
             │ Prisma ORM                   │ HTTPS
             ▼                              ▼
┌──────────────────┐          ┌────────────────────────────────┐
│   PostgreSQL     │          │  Meta WhatsApp Cloud API       │
│   (Externo)      │          │  graph.facebook.com            │
└──────────────────┘          └────────────────────────────────┘
```

## Arquivos-Chave

| Arquivo | Responsabilidade |
|---------|-----------------|
| `server/services/whatsapp.service.ts` | Envio de mensagens, upload/download de mídia, conexão com Meta API |
| `server/services/webhook.service.ts` | Processamento de webhooks: mensagens recebidas, status de entrega |
| `server/services/template.service.ts` | CRUD de templates via Meta API |
| `server/services/template-ai.service.ts` | Assistente IA para criação/melhoria de templates (LLM multi-provider) |
| `server/routes.ts` | Todas as rotas REST, webhook endpoints, media-proxy |
| `server/websocket/socket.ts` | Socket.io: rooms, broadcast, autenticação JWT |
| `server/repositories/message.repository.ts` | CRUD de mensagens no banco |
| `server/repositories/ticket.repository.ts` | CRUD de tickets, filtros por status/fila |
| `server/repositories/contact.repository.ts` | Contagem de contatos por tenant |
| `server/repositories/whatsapp.repository.ts` | Conexões WhatsApp por tenant |
| `server/repositories/queue.repository.ts` | Filas, associação users-queues |
| `server/repositories/user.repository.ts` | Usuários, presença online/offline |
| `client/src/pages/atendimento.tsx` | Interface de chat, renderização de mensagens, tabs de tickets, drawer IA |
| `client/src/pages/ai-knowledge.tsx` | Página admin para configuração do Assistente IA e gestão de arquivos da base de conhecimento |
| `server/ai-assistant.ts` | Assistente IA com RAG: processamento de documentos, TF-IDF search, chat OpenAI/Gemini |
| `client/src/App.tsx` | Layout principal com modal global do Assistente IA (botão Sparkles no header) |
| `prisma/schema.prisma` | Schema do banco de dados |
| `server/static.ts` | Servindo arquivos estáticos com headers anti-cache |

## Meta WhatsApp Cloud API

### Configuração de Conexão

Cada conexão WhatsApp (tabela `Whatsapps`) armazena:

| Campo | Uso | Descrição |
|-------|-----|-----------|
| `bmToken` | Bearer Token | Token de acesso para autenticação na Meta Graph API |
| `tokenAPI` | Phone Number ID | ID do número de telefone usado nas URLs da API |
| `wabaId` | WABA ID | ID da conta WhatsApp Business para templates e métricas |
| `wabaVersion` | Versão da API | Versão da Graph API (padrão: `v22.0`) |
| `webhookChecked` | Verify Token | Token de verificação para o webhook |

### Construção de URL

```typescript
// Padrão para URL da API de mensagens
const url = `https://graph.facebook.com/${wabaVersion}/${tokenAPI}/messages`;

// Para templates
const url = `https://graph.facebook.com/${wabaVersion}/${wabaId}/message_templates`;

// Para mídia
const url = `https://graph.facebook.com/${wabaVersion}/${tokenAPI}/media`;
```

### Headers Padrão

```typescript
headers: {
  "Authorization": `Bearer ${bmToken}`,
  "Content-Type": "application/json"
}
```

### Teste de Conexão

```typescript
// GET https://graph.facebook.com/{version}/{phoneNumberId}
// Retorna dados do número se o token estiver válido
```

## Tipos de Mensagem

### Tabela de Referência Completa

| Tipo WhatsApp | `mediaType` (DB) | `body` (DB) | Direção | Rendering Frontend |
|---------------|-------------------|-------------|---------|-------------------|
| `text` | `null` | Texto da mensagem | IN/OUT | Texto simples |
| `image` | `image` | `[IMAGE] caption` | IN/OUT | Imagem clicável + caption |
| `video` | `video` | `[VIDEO] caption` | IN/OUT | Player de vídeo + download |
| `audio` | `audio` | `[AUDIO]` | IN/OUT | Player de áudio com ícone Mic |
| `document` | `document` | `[DOCUMENT] filename` | IN/OUT | Botão com FileText + nome + mime |
| `sticker` | `sticker` | `[STICKER]` | IN | Imagem 150px (sem clique para ampliar) |
| `location` | `location` | `📍 Location: lat, lng` | IN | Card com MapPin + link Google Maps |
| `contacts` | `contactMessage` | `📇 ContactName` | IN | Card com avatar + telefone clicável (wa.me) |
| `interactive` | `null` | `[INTERACTIVE] título` | IN/OUT | Texto com prefixo removido |
| `reaction` | `null` | emoji | IN/OUT | Emoji overlay no message referenciado |
| `template` | `null` | `[TEMPLATE] corpo` | OUT | Texto com prefixo removido |
| `unsupported` | `null` | `⚠️ erro Meta` | IN | "Mensagem não suportada pelo WhatsApp Cloud API" |

### Mensagens Enviadas (Outbound)

```typescript
// Texto simples
whatsappService.sendMessage(connection, to, body);

// Template
whatsappService.sendTemplateMessage(connection, to, templateName, languageCode, components);

// Mídia (imagem, vídeo, áudio, documento)
whatsappService.sendMediaMessage(connection, to, mediaType, mediaUrl, caption, filename);

// Botões interativos (máx 3)
whatsappService.sendInteractiveButtons(connection, to, bodyText, buttons);

// Lista interativa
whatsappService.sendInteractiveList(connection, to, headerText, bodyText, buttonText, sections);

// Localização
whatsappService.sendLocationMessage(connection, to, latitude, longitude, name, address);

// Contato
whatsappService.sendContactMessage(connection, to, contacts);

// Reação (emoji em mensagem existente)
whatsappService.sendReactionMessage(connection, to, messageId, emoji);
```

### Mensagens Recebidas (Inbound) - Webhook

O `WebhookService.extractMessageContent(msg)` extrai o conteúdo baseado no `msg.type`:

```typescript
// Resultado da extração:
interface ExtractedContent {
  body: string;        // Texto ou placeholder ([IMAGE], [AUDIO], etc.)
  mediaType?: string;  // image, video, audio, document, sticker, location, contactMessage
  dataJson?: string;   // JSON com metadados (wabaMediaId, coordenadas, contatos)
}
```

#### Fluxo de Extração por Tipo

**Texto:**
```typescript
{ body: msg.text.body, mediaType: null, dataJson: null }
```

**Mídia (image/video/audio/document/sticker):**
```typescript
{
  body: `[${type.toUpperCase()}] ${caption || ''}`,
  mediaType: type,
  dataJson: JSON.stringify({ wabaMediaId: msg[type].id, mime_type: msg[type].mime_type })
}
```

**Localização:**
```typescript
{
  body: `📍 Location: ${lat}, ${lng}`,
  mediaType: "location",
  dataJson: JSON.stringify({ latitude, longitude, name, address })
}
```

**Contatos:**
```typescript
{
  body: `📇 ${contacts[0].name.formatted_name}`,
  mediaType: "contactMessage",
  dataJson: JSON.stringify({ contacts: [...] })
}
```

**Interativo (button_reply / list_reply):**
```typescript
{ body: `[INTERACTIVE] ${title}`, mediaType: null, dataJson: JSON.stringify({ id, title, type }) }
```

**Reação:**
```typescript
{ body: emoji, mediaType: null, dataJson: JSON.stringify({ message_id, emoji }) }
```

**Unsupported (limitação da Meta):**
```typescript
{
  body: `⚠️ ${errorTitle}\n${errorDetails}`,
  mediaType: null,
  dataJson: JSON.stringify({ type: "unsupported", errors: [...] })
}
```

## Fluxo de Mídia

### Upload (Envio para Meta)

```
Arquivo local → uploadMediaToMeta() → mediaId → sendWabaMediaMessage(mediaId)
```

1. Lê o arquivo do disco
2. Cria `FormData` com `messaging_product: "whatsapp"`, `file`, `type`
3. POST para `/{version}/{phoneNumberId}/media`
4. Retorna `mediaId` da Meta
5. Envia mensagem referenciando o `mediaId`

### Download (Recebimento da Meta)

```
wabaMediaId (webhook) → getMediaUrl(mediaId) → downloadMedia(url) → buffer
```

1. Webhook recebe `mediaId` no campo do tipo (ex: `msg.image.id`)
2. `getMediaUrl`: GET `/{version}/{mediaId}` → retorna URL temporária
3. `downloadMedia`: GET na URL temporária com Bearer token → buffer binário

### Proxy de Mídia (Frontend)

```
GET /api/media-proxy/:mediaId?tenantId=X
GET /api/media/:mediaId  (alternativa com Bearer token JWT)
```
- Frontend usa estas rotas para exibir mídia recebida
- Backend faz o download da Meta e retorna o buffer com o content-type correto
- Evita expor tokens da Meta no frontend
- A rota `/api/media/:mediaId` aceita autenticação via Bearer token no header Authorization

### Media Viewer (Visualizador de Mídia)

Existe em 3 páginas com padrão consistente:

| Página | State Variable | data-testid |
|--------|---------------|-------------|
| `painel-atendimentos.tsx` | `spyMediaViewer` | `spy-media-viewer-dialog`, `spy-media-viewer-pdf` |
| `contatos.tsx` | `contactMediaViewer` | `contact-media-viewer-dialog`, `contact-media-viewer-pdf` |
| `atendimento.tsx` | `mediaViewer` | `media-viewer-dialog`, `media-viewer-pdf` |

**State structure:**
```typescript
{
  url: string;          // Blob URL do arquivo
  filename: string;     // Nome do arquivo
  mimeType: string;     // MIME type (ex: "application/pdf")
  type: string;         // "image" | "video" | "audio" | "document"
  loading?: boolean;    // True durante fetch da mídia
  error?: string;       // Mensagem de erro se fetch falhar
}
```

**Fluxo de renderização:**
1. Loading state → Loader2 spinner + "Carregando mídia..."
2. Error state → AlertCircle + mensagem de erro
3. Success → renderiza por tipo:
   - **PDF**: `<iframe>` direto com `min-h-[70vh]` (scroll interno do browser)
   - **Imagem**: `<img>` com `max-h-[70vh] object-contain`
   - **Vídeo**: `<video>` com controls
   - **Áudio**: `<audio>` com controls
   - **Outros documentos**: Card com FileText + botão "Baixar Arquivo"

**Importante:** PDFs usam `<iframe>` (não `<object>`) para garantir scroll nativo do browser. O blob é criado com MIME type explícito:
```typescript
const blob = new Blob([originalBlob], { type: effectiveType });
const url = URL.createObjectURL(blob);
```

**Prefetch de mídia:** Botões de documento sempre são renderizados independente do status de prefetch. Se prefetch falhar silenciosamente, o fetch ocorre on-demand ao clicar.

### Conversão de Áudio

```typescript
// server/routes.ts - convertAudioForWhatsApp()
// webm/wav → MP4/AAC (128k, 44100Hz, mono)
// Usa ffmpeg via child_process
convertAudioForWhatsApp(inputPath: string): Promise<{ outputPath, mimetype: "audio/mp4" }>
```

## Webhook Processing

### Endpoints

```
GET  /api/webhook/whatsapp  →  Verificação (hub.verify_token)
POST /api/webhook/whatsapp  →  Processamento de eventos
```

### Validação de Assinatura

```typescript
// Header: x-hub-signature-256
// Secret: tenant.metaToken (appSecret da Meta)
// Algoritmo: HMAC-SHA256 do body raw
// Comparação: crypto.timingSafeEqual
```

#### Resolução do App Secret (resolveAppSecretFromPayload)

O webhook resolve o App Secret dinamicamente por tenant:
1. Extrai `phoneNumberId` do payload (`metadata.phone_number_id`)
2. Busca a conexão `Whatsapps` pelo `tokenAPI = phoneNumberId`
3. Busca o tenant pela conexão → campo `Tenants.metaToken`
4. Se `metaToken` está configurado (não-vazio e diferente do padrão) → usa como App Secret
5. Se não → fallback para `process.env.META_APP_SECRET` → se não existe → `null` (validation skipped)

**Valor padrão (skip):** Definido como `META_TOKEN_DEFAULT` no código. Consulte o scratchpad do agente para o valor real.

Função `isAppSecretConfigured(metaToken)` retorna `false` se:
- metaToken é null/vazio
- metaToken é igual ao `META_TOKEN_DEFAULT` acima

#### TROUBLESHOOTING: "Invalid signature, rejecting payload"

**Causa mais comum:** O campo `Tenants.metaToken` foi preenchido com um valor que NÃO corresponde ao App Secret real da aplicação Meta. Quando `isAppSecretConfigured()` retorna `true`, a validação HMAC-SHA256 é ativada e todos os webhooks falham com 403.

**Sintoma:** TODAS as mensagens recebidas param de funcionar. Logs mostram:
```
[Webhook] POST received, entries=1
[Webhook] Invalid signature, rejecting payload
POST /api/webhook/whatsapp 403
```

**Diagnóstico:**
```sql
SELECT id, name, "metaToken" FROM "Tenants" WHERE id = 1;
```

**Correção imediata (desbloqueia webhooks):**
```sql
UPDATE "Tenants" SET "metaToken" = '<META_TOKEN_DEFAULT_FROM_SCRATCHPAD>' WHERE id = 1;
```
Isso reseta para o valor padrão, fazendo `isAppSecretConfigured()` retornar `false` e pular a validação.

**Correção definitiva:** Obter o App Secret correto no Meta for Developers → App Settings → Basic → App Secret, e configurar no painel Webhook do VoxZap.

#### rawBody Capture

O `rawBody` é capturado em `server/index.ts` via `express.json({ verify })`:
```typescript
app.use(express.json({
  verify: (req, _res, buf) => { req.rawBody = buf; },
}));
```
O webhook usa `req.rawBody` (Buffer original) para validar a assinatura. Se `rawBody` não existe, faz fallback para `JSON.stringify(req.body)` — que pode diferir do payload original e causar falha de validação.

### Fluxo de Processamento

```
Webhook POST
  ├── Valida assinatura (x-hub-signature-256)
  ├── Identifica tenant pelo phoneNumberId
  └── Para cada entry.changes:
      ├── Status Update (sent/delivered/read/failed)
      │   ├── Atualiza ack na tabela messages
      │   ├── Se failed: salva erro em dataJson
      │   └── Broadcast via Socket.io: MESSAGE_ACK_UPDATE
      │
      └── Nova Mensagem
          ├── Encontra/cria Contato (pelo número)
          ├── ** Intercepta Resposta de Avaliação (qualquer texto) **
          │   ├── Busca ticket closed recente COM OPERADOR (userId NOT NULL, dentro de ratingStoreTime)
          │   ├── IMPORTANTE: A query filtra userId: { not: null } direto no banco
          │   │   para ignorar tickets fechados por bot/#sair
          │   ├── Verifica canal com sendEvaluation=enabled
          │   ├── Verifica tentativas inválidas (Map em memória)
          │   ├── Se válido: salva TicketEvaluations com userId do operador
          │   ├── Se inválido: incrementa tentativas, envia mensagem progressiva
          │   ├── Envia mensagem de confirmação (rating.message)
          │   └── Se já avaliou: envia ratingStoreAttemp
          ├── ** Routing Chain (determina fila + shouldActivateBot) **
          │   ├── 1. Force Wallet: walletUserId direto (se configurado)
          │   ├── 2. Campaign Routing: CampaignContacts com responseRouting (janela 48h)
          │   │   └── Se match: campaignRouted=true, walletQueueId = campaign.queueId
          │   ├── 3. Tag Routing (SEMPRE roda, mesmo com campaign/wallet):
          │   │   ├── Busca ContactTags → TagQueueRoutes (ativas, priority DESC)
          │   │   ├── Se !walletUserId && !campaignRouted: routing completo (tagRouted=true, define fila)
          │   │   └── Se já roteado E tag.skipBot=true: tagSkipBotOnly=true (mantém fila, desativa bot)
          │   ├── 4. VoxCall Routing: busca por número na VoxCall
          │   └── 5. Default: fila padrão da conexão + bot ativo
          ├── Encontra/cria Ticket (status pending)
          │   └── queueId definido pela Routing Chain acima
          ├── Extrai conteúdo (extractMessageContent)
          ├── Salva mensagem no banco
          ├── Atualiza lastMessage do ticket
          ├── Broadcast via Socket.io: NEW_MESSAGE + TICKET_UPDATE
          ├── ** shouldActivateBot check **
          │   ├── Se (tagRouted && tagRoutedSkipBot) || tagSkipBotOnly → shouldActivateBot=false
          │   └── Se connection.aiAgentId → shouldActivateBot=true (default)
          └── ** AI Agent Processing (se shouldActivateBot=true + ticket pending) **
              ├── Re-lê ticket do banco (freshTicket) para checar lastCallChatbot
              ├── Se lastCallChatbot === false: SKIP (bot desativado após transferência)
              ├── Auto-reply loop detection: se últimas 3 msgs incoming idênticas → desativa bot
              ├── messageProcessingQueue.enqueue(ticketId, fn) — serializa pipeline por ticket
              │   ├── Checa transferKeywords → tryTransfer(transferQueueId)
              │   ├── Checa maxBotRetries → tryTransfer(transferQueueId)
              │   ├── processMessageWithAgent() → LLM call
              │   │   ├── Se routingEnabled: injeta bloco ROTEAMENTO INTELIGENTE no system prompt
              │   │   ├── Detecta [TRANSFERIR:intent] → busca rota → tryTransfer(route.targetQueueId)
              │   │   ├── Detecta [TRANSFERIR] → tryTransfer(agent.transferQueueId)
              │   │   └── Limpa tags + "departamento X" residuais da resposta
              │   ├── Envia resposta via WhatsApp (whatsappService.sendMessage)
              │   ├── Persiste mensagem no banco (messageRepository.create)
              │   ├── Atualiza ticket (lastMessage, botRetries, updatedAt)
              │   └── Se transferred: tryTransfer() já cuida de tudo (BH check, status, queueId)
              └── tryTransfer(): businessHoursCheck → transfere se aberto, mensagem de fechamento se fechado (SEMPRE informa o cliente)
```

### Proteção contra Tickets Duplicados (Race Condition)

A Meta pode enviar múltiplos webhooks simultaneamente (mesmo messageId 2x, ou mensagens diferentes do mesmo contato no mesmo instante). Sem proteção, `findOrCreateTicket` cria tickets duplicados.

**3 camadas de proteção em `webhook.service.ts`:**

1. **Deduplicação em memória por messageId** (`recentMessageIds: Set`): Cada messageId é marcado por 30s. Se a Meta envia o mesmo webhook 2x, o segundo é descartado antes de qualquer query ao banco. Log: `"already being processed (in-memory dedup), skipping"`
2. **Mutex por contato** (`contactTicketLocks: Map`): Lock em memória por `tenantId:contactId`. Quando 2 mensagens diferentes do mesmo contato chegam simultaneamente, a segunda espera a primeira criar o ticket. Garante serialização do `findOrCreateTicket` por contato.
3. **Índice parcial único no banco** (`idx_tickets_one_open_per_contact`): `UNIQUE INDEX ON "Tickets" ("contactId", "tenantId", COALESCE("whatsappId", 0)) WHERE status IN ('open','pending','paused')`. Se as camadas 1 e 2 falharem (restart, multi-instância), o PostgreSQL rejeita a criação. O código trata `P2002` fazendo fallback para buscar o ticket existente.

**IMPORTANTE para migração**: O índice é parcial (só tickets ativos). Tickets `closed` (dados históricos) não são afetados — migrações podem importar múltiplos tickets fechados do mesmo contato sem conflito.

### Proteção contra Loop Infinito de Auto-Reply

Quando um contato tem **mensagem automática de ausência** no WhatsApp, cada resposta do bot gera uma auto-reply, que por sua vez dispara nova resposta do bot → loop infinito.

**3 camadas de proteção em `webhook.service.ts`:**

1. **`lastCallChatbot` flag**: Após transferência do bot para humano, seta `lastCallChatbot = false`. O webhook verifica este flag antes de processar com AI Agent. Se `false`, ignora.
2. **Message Processing Queue**: Pipeline completo (LLM + envio + persist + transfer) serializado por ticket via `messageProcessingQueue.enqueue(ticketId, fn)`. Garante processamento sequencial por ticket, evitando race conditions e respostas duplicadas. Substitui o debounce antigo de 5 segundos.
3. **Detecção de auto-reply**: Se as últimas 3 mensagens recebidas (`fromMe: false`) têm body idêntico, detecta como auto-reply e seta `lastCallChatbot = false` automaticamente.

**Campos relevantes na tabela `Tickets`:**

| Campo | Tipo | Uso na proteção |
|-------|------|----------------|
| `lastCallChatbot` | Boolean | `false` = bot desativado para este ticket |
| `botRetries` | Int | Contador de tentativas, resetado após transferência |
| `firstCall` / `lastCall` | Boolean | Flags de controle de primeira/última chamada |

### Webhook Observability (WebhookLogs)

Sistema completo de logging e visualização de todos os eventos recebidos da Meta (WhatsApp Cloud API) para diagnóstico de problemas em produção (mensagens não recebidas, mudanças de formato, erros de assinatura).

#### Tabela `WebhookLogs`

| Campo | Tipo | Descrição |
|-------|------|-----------|
| `id` | Serial PK | ID auto-incremento |
| `tenantId` | Int? | Tenant identificado (null se não encontrado) |
| `connectionId` | Int? | Conexão WhatsApp identificada |
| `eventType` | VarChar(30) | `message`, `status`, `call`, `verification`, `unknown` |
| `direction` | VarChar(10) | `inbound` (padrão) |
| `phoneFrom` | VarChar(30)? | Telefone de origem |
| `phoneTo` | VarChar(30)? | Telefone de destino |
| `waMessageId` | VarChar(200)? | Message ID do WhatsApp |
| `messageType` | VarChar(30)? | Tipo da mensagem (text, image, audio...) |
| `payloadSummary` | Json? | Resumo condensado do payload (sempre gravado) |
| `fullPayload` | Json? | Payload completo (opt-in via setting `webhookStoreFullPayload`) |
| `processingResult` | VarChar(20) | `success`, `error`, `rejected`, `not_found`, `ignored` |
| `errorMessage` | Text? | Mensagem de erro se houver |
| `processingTimeMs` | Int | Tempo de processamento em ms |
| `httpStatusCode` | Int | HTTP status retornado (200, 403, 500) |
| `createdAt` | Timestamptz | Data/hora do evento |

**Índices compostos:** `(tenantId, createdAt)`, `(eventType, createdAt)`

#### Pontos de Logging no Código

```
server/routes.ts:
  saveWebhookLog()             ← Helper fire-and-forget (não bloqueia o webhook)
  buildWebhookPayloadSummary() ← Cria resumo condensado do payload

Pontos de captura:
  GET  /api/webhook/whatsapp   ← Verificação: success ou rejected
  POST /api/webhook/whatsapp   ← Assinatura inválida: rejected
  POST /api/webhook/whatsapp   ← Processamento: success, error, not_found, ignored
  POST /api/webhook/whatsapp   ← Exceção catch: error
```

#### processWebhookPayload — Metadados Retornados

```typescript
interface WebhookProcessingResult {
  eventTypes: string[];      // Tipos de evento processados
  tenantId: number | null;   // Tenant identificado
  connectionId: number | null; // Conexão identificada
  phoneFrom: string | null;  // Telefone de origem
  phoneTo: string | null;    // Telefone de destino (phoneNumberId)
  messageCount: number;      // Quantidade de mensagens
  statusCount: number;       // Quantidade de status updates
  callCount: number;         // Quantidade de chamadas
  waMessageIds: string[];    // IDs de mensagem do WhatsApp
  messageTypes: string[];    // Tipos de mensagem (text, image...)
  errors: string[];          // Erros encontrados
}
```

#### Classificação de `processingResult`

| Valor | Quando |
|-------|--------|
| `success` | Processou mensagens/status/calls sem erro |
| `error` | Erros no processamento (exceto not_found) |
| `not_found` | Nenhuma conexão encontrada para o phoneNumberId |
| `rejected` | Assinatura inválida ou verificação falhou |
| `ignored` | Payload sem mensagens, status ou calls para processar |

#### fullPayload — Opt-in por Tenant

O campo `fullPayload` só é gravado se a setting `webhookStoreFullPayload` estiver ativa para o tenant:

```
Tabela Settings:
  key = "webhookStoreFullPayload"
  value = "true" (ativa) / qualquer outro (desativa, padrão)
  tenantId = ID do tenant
```

Cache em memória por tenant (Map), TTL de 5 minutos. Para `tenantId = null` (evento não identificado), sempre retorna `false`.

#### API Endpoints

```
GET /api/webhook-logs/stats     ← Estatísticas agregadas (admin/superadmin)
GET /api/webhook-logs/entries   ← Lista paginada com filtros (admin/superadmin)
GET /api/webhook-logs/:id       ← Detalhe com payload completo (admin/superadmin)
```

**Filtros disponíveis:** `startDate`, `endDate`, `eventType`, `processingResult`, `search` (busca em phoneFrom, phoneTo, waMessageId, errorMessage)

**Isolamento multi-tenant:**
- Admin: só vê logs do seu tenant (`tenantId = X`)
- SuperAdmin: vê todos os logs
- Logs com `tenantId = null` só são visíveis para SuperAdmin
- Detalhe (`/:id`): bloqueia acesso se tenant não confere

**Queries parametrizadas:** Todas as consultas usam `$queryRawUnsafe` com parâmetros posicionais (`$1`, `$2`...) e whitelist de valores para `eventType` e `processingResult`.

#### Cleanup Automático

```typescript
// Roda a cada 24h, configurável via Settings
// key = "webhookLogRetentionDays", default = 7
cleanupOldWebhookLogs()
setInterval(cleanupOldWebhookLogs, 24 * 60 * 60 * 1000)
```

#### Frontend — Página `/webhook-logs`

- **Rota:** `/webhook-logs` (AdminRoute)
- **Menu:** "Webhook Logs" no grupo system (adminOnly), ícone `Webhook` do lucide-react
- **Arquivo:** `client/src/pages/webhook-logs.tsx`
- **Componentes:**
  - 5 cards de métricas (total, sucesso, erros/rejeitados/not_found, tempo médio, verificações)
  - Tabela com colunas: Data/Hora, Tipo, Tenant, De, Para, Msg Type, Resultado, Tempo, Erro
  - Filtros: busca texto, tipo de evento, resultado, datas
  - Dialog de detalhe com JSON do payload (summary + full se disponível)
  - Paginação

### Sistema de Avaliação Automática (sendEvaluation)

O sistema de avaliação permite enviar automaticamente uma pesquisa de satisfação ao cliente quando um ticket é fechado, e processar a resposta vinculando ao operador que atendeu.

#### Configuração

| Campo | Tabela | Descrição |
|-------|--------|-----------|
| `sendEvaluation` | `Whatsapps` | `"enabled"/"disabled"` - Ativa envio de avaliação por canal |
| `rating` | `Tenants` | JSON com labels e mensagens para cada nota (ex: 1-5) |
| `ratingStore` | `Tenants` | Mensagem de sucesso ao armazenar avaliação |
| `ratingStoreAttemp` | `Tenants` | Mensagem de "última chance" (penúltima tentativa inválida) |
| `ratingStoreError` | `Tenants` | Mensagem de erro ao armazenar |
| `ratingStoreTime` | `Tenants` | Tempo em ms para aceitar resposta (padrão: 3600000 = 1h) |
| `ratingInvalidMessage` | `Tenants` | Mensagem para resposta inválida (suporta `{opcoes}` placeholder) |
| `ratingMaxInvalidAttempts` | `Tenants` | Número máximo de tentativas inválidas (padrão: "3") |
| `evaluationMessage` | `Tenants` | JSON com mensagens de resposta por nota |

#### Fluxo Completo

```
1. Operador fecha ticket (PATCH /api/tickets/:id {status: "closed"})
   ├── Verifica canal: sendEvaluation === "enabled"?
   ├── Busca tenant.rating (labels das notas)
   ├── Monta mensagem: "Avalie de 1 a 5:\n1 - Muito Insatisfeito\n..."
   └── Envia via whatsappService.sendMessage()

2. Cliente responde com QUALQUER mensagem de texto
   ├── Webhook recebe mensagem de texto (qualquer tipo, não apenas numérica)
   ├── handleEvaluationResponse() intercepta ANTES de criar ticket
   │   ├── Busca ticket closed recente COM OPERADOR (updatedAt >= cutoff AND userId IS NOT NULL)
   │   │   └── CRÍTICO: Filtra userId: { not: null } na query para ignorar tickets fechados por bot/#sair
   │   ├── Verifica canal sendEvaluation === "enabled"
   │   ├── Verifica se já existe avaliação (TicketEvaluations)
   │   │   └── Se sim: retorna false (permite fluxo normal)
   │   ├── Verifica tentativas inválidas via Map em memória (invalidRatingAttempts)
   │   │   └── Se count >= maxAttempts: retorna false (permite fluxo normal)
   │   ├── Valida se é número dentro do range configurado em tenant.rating
   │   │   ├── Se VÁLIDO:
   │   │   │   ├── Salva em TicketEvaluations (userId = operador do ticket)
   │   │   │   ├── Envia mensagem de confirmação (rating[n].message ou ratingStore)
   │   │   │   └── Limpa tentativas inválidas do Map
   │   │   └── Se INVÁLIDO (texto, número fora do range, qualquer coisa):
   │   │       ├── Incrementa contador no Map (chave: contactId:ticketId)
   │   │       ├── Se tentativa < maxAttempts-1: envia ratingInvalidMessage com {opcoes}
   │   │       ├── Se tentativa = maxAttempts-1 (penúltima): envia ratingStoreAttemp
   │   │       └── Se tentativa = maxAttempts (última): envia "Máximo de tentativas atingido"
   │   └── Salva mensagem no ticket fechado (não cria novo ticket)
   └── Se handleEvaluationResponse retorna false: segue fluxo normal (findOrCreateTicket)
```

#### Tratamento de Respostas Inválidas

O sistema usa um `Map<string, {count, expiresAt}>` em memória (`invalidRatingAttempts`) para rastrear tentativas inválidas:

- **Chave:** `contactId:ticketId` (via `getInvalidAttemptKey()`)
- **Limpeza automática:** Timer de 5 minutos remove entradas expiradas
- **Persistência:** Em memória — reinício do servidor zera contadores (risco aceitável)
- **Após max tentativas:** A entrada NÃO é deletada do Map (mantém count >= max para que chamadas futuras retornem false imediatamente e permitam fluxo normal de criação de ticket)

Mensagens por tentativa (com maxAttempts=3):
| Tentativa | Mensagem Enviada |
|-----------|-----------------|
| 1ª | `ratingInvalidMessage` com opções válidas |
| 2ª (penúltima) | `ratingStoreAttemp` ("última chance") |
| 3ª (última) | "Número máximo de tentativas atingido. Sua avaliação não foi registrada." |
| 4ª+ | Não intercepta mais — retorna false, mensagem segue fluxo normal |

#### Tabela TicketEvaluations

```prisma
model TicketEvaluations {
  id         Int      @id @default(autoincrement())
  evaluation String   @db.VarChar(255)   // Nota: "1" a "5" (conforme tenant.rating)
  attempts   Int                          // Sempre 1 no primeiro registro
  ticketId   Int                          // Ticket que foi avaliado
  userId     Int?                         // Operador que atendeu (do ticket.userId)
  tenantId   Int
  createdAt  DateTime
  updatedAt  DateTime

  @@unique([ticketId, tenantId])          // UNIQUE constraint impede avaliação duplicada
}
```

**Proteção contra race condition:** O `prisma.ticketEvaluations.create()` está envolvido em try/catch que detecta erro Prisma P2002 (unique violation). Se duas mensagens de avaliação chegarem simultaneamente, a segunda é tratada como sucesso (sem erro para o cliente) em vez de criar duplicata.

#### Marcador "skipped" — Fechamento Forçado Sem Avaliação

Quando o operador fecha um ticket pelo **X vermelho do card** (atendimento) ou pelo **bulk-close do painel admin**, NÃO queremos enviar a pesquisa nem queremos que a próxima mensagem do cliente caia no `handleEvaluationResponse`.

**Problema histórico:** Sem nenhum marcador, `handleEvaluationResponse` continuava interceptando toda mensagem do contato dentro de `ratingStoreTime` (1h padrão), mandando "Resposta inválida" → "Você tem mais uma oportunidade..." → "Número máximo de tentativas atingido", mesmo o ticket tendo sido encerrado SEM cobrança de pesquisa.

**Solução:** Gravar uma linha em `TicketEvaluations` com `evaluation: "skipped"` e `attempts: 0`. Como `handleEvaluationResponse` já checa `existingEvalCheck` e retorna `false` se houver qualquer linha pra aquele ticket, o marcador silencia o fluxo de cobrança permanentemente para aquele encerramento.

**Backend** (`server/routes.ts`):

```ts
// PATCH /api/tickets/:id — schema aceita skipEvaluation
const updateTicketSchema = z.object({
  status: z.enum(["pending", "open", "closed"]).optional(),
  // ... outros campos
  skipEvaluation: z.boolean().optional(),
});

// Após o updatedTicket + broadcast, ANTES do bloco de envio de pesquisa:
if (status === "closed" && skipEvaluation === true && ticket.whatsappId) {
  try {
    await prisma.ticketEvaluations.create({
      data: {
        ticketId,
        tenantId: req.user.tenantId,
        userId: req.user.userId,
        evaluation: "skipped",
        attempts: 0,
        createdAt: new Date(),
        updatedAt: new Date(),
      },
    });
  } catch (skipErr: any) {
    if (skipErr?.code !== "P2002") console.error("...", skipErr);
  }
}

// O bloco de envio de pesquisa (sendEvaluation) também checa skipEvaluation:
if (status === "closed" && ticket.whatsappId && resolveContactRecipient(ticket.contact)) {
  if (skipEvaluation) {
    // pula tudo: não envia farewellMessage nem pesquisa
  } else {
    // envia farewell + pesquisa normalmente
  }
}

// POST /api/tickets/bulk-close — busca IDs antes do updateMany e cria markers
const ticketsToClose = await prisma.tickets.findMany({
  where, select: { id: true, whatsappId: true, userId: true },
});
await prisma.tickets.updateMany({ where, data: { status: "closed", ... } });
const evalMarkers = ticketsToClose
  .filter((t) => t.whatsappId)
  .map((t) => ({
    ticketId: t.id,
    tenantId: req.user.tenantId,
    userId: t.userId ?? req.user.userId,
    evaluation: "skipped",
    attempts: 0,
    createdAt: new Date(),
    updatedAt: new Date(),
  }));
if (evalMarkers.length > 0) {
  await prisma.ticketEvaluations.createMany({ data: evalMarkers, skipDuplicates: true });
}
```

**Frontend** (`client/src/pages/atendimento.tsx`):

```ts
// X vermelho do card passa skipEvaluation=true
const handleCloseTicket = (ticket: Ticket, skipEvaluation = false) => {
  updateTicketMutation.mutate({ id: ticket.id, status: "closed", skipEvaluation });
};
// X vermelho:
<button onClick={() => handleCloseTicket(ticket, true)}>X</button>
// Botão de "Finalizar com pesquisa" no topbar: handleCloseTicket(ticket, false)
```

**Correção retroativa de tickets já fechados sem marker:** Se o usuário reportar "cliente continua recebendo cobrança de pesquisa", inserir manualmente:

```sql
INSERT INTO "TicketEvaluations"
  ("evaluation", "attempts", "ticketId", "userId", "tenantId", "createdAt", "updatedAt")
VALUES ('skipped', 0, <ticket_id>, <user_id>, <tenant_id>, NOW(), NOW())
ON CONFLICT ("ticketId", "tenantId") DO NOTHING;
```

#### Código-Chave

- **Envio ao fechar:** `server/routes.ts` → `PATCH /api/tickets/:id` (bloco `if status === "closed"`)
- **Recebimento da resposta:** `server/services/webhook.service.ts` → `handleEvaluationResponse()`
- **Interceptação no webhook:** `server/services/webhook.service.ts` → linha ~389 (todas as mensagens de texto são verificadas, não apenas numéricas)
- **Mensagem inválida com opções:** `server/services/webhook.service.ts` → `buildInvalidRatingMessage()` (substitui `{opcoes}` pelas opções configuradas)
- **Configuração de notas:** `client/src/pages/avaliacoes.tsx` → Tab "Configurar Avaliações"
- **Relatório:** `client/src/pages/avaliacoes.tsx` → Tab "Listar Avaliações" (filtros por data/nota/operador)

#### Armadilhas Conhecidas

- **NUNCA buscar "qualquer ticket fechado mais recente"** — sempre filtrar `userId: { not: null }` na query. Tickets fechados por bot/#sair (sem operador) não têm avaliação pendente. Se um ticket bot aparecer como mais recente (ex: por bug de timezone), a avaliação é ignorada e um novo ticket é criado indevidamente.
- **Ordenação por `updatedAt`** — o `updatedAt` pode ter inconsistências se o PostgreSQL não estiver com timezone=UTC e o Prisma enviar timestamps sem marcador UTC. Sempre garantir que o PostgreSQL use `timezone='UTC'` (ver skill deploy-assistant-vps seção 15).
- **Avaliação só é enviada para tickets fechados por operador** — o bloco de envio em `PATCH /api/tickets/:id` já verifica `closedTicket.userId`, mas a interceptação da resposta (`handleEvaluationResponse`) também DEVE filtrar por `userId IS NOT NULL` na query do banco.

### Valores de ACK (Status de Entrega)

| Valor | Status | Ícone Frontend |
|-------|--------|---------------|
| `0` | Pendente (enviando) | Relógio |
| `1` | Enviado (sent) | ✓ simples |
| `2` | Entregue (delivered) | ✓✓ cinza |
| `3` | Lido (read) | ✓✓ azul |
| `-1` | Falha (failed) | ✗ vermelho |

## Normalização de Telefone Brasileiro (Nono Dígito)

### Regra do 9° Dígito

Todos os celulares brasileiros usam o nono dígito (9) desde Nov/2016 em todos os DDDs. A Meta Cloud API aceita ambos os formatos e normaliza internamente. O sistema sempre envia COM o nono dígito para garantir entrega.

| Formato | Comprimento | Regra |
|---------|-------------|-------|
| `55` + DDD + `9XXXXXXXX` | 13 dígitos | COM nono dígito (formato padrão) |
| `55` + DDD + `XXXXXXXX` | 12 dígitos | SEM nono dígito (formato alternativo para retry) |

### Função `normalizeBrazilianPhone()`

Centralizada em: `server/lib/phone-utils.ts` (importada por todos os serviços)

```typescript
function normalizeBrazilianPhone(phone: string): string {
  // 1. Remove não-dígitos e adiciona DDI 55 se necessário (10 ou 11 dígitos → 55 + número)
  // 2. Se número local tem 8 dígitos e não começa com 0 (fixo): ADICIONA o 9
  // NUNCA remove o nono dígito — a Meta normaliza do lado deles
}
```

### Função `getAlternatePhoneNumber()`

Gera o número no formato alternativo (com/sem o 9) para busca de contatos e retry de envio:
- Se tem 9 dígitos locais começando com 9 → gera versão SEM o 9 (12 dígitos)
- Se tem 8 dígitos locais → gera versão COM o 9 (13 dígitos)

### Função `buildPhoneSearchNumbers()`

Centralizada em: `server/lib/phone-utils.ts`. Gera TODAS as variantes de busca para um número de telefone, garantindo match com contatos armazenados em qualquer formato (legado ou normalizado).

Para o número `5585976020655`, gera:
1. `5585976020655` — normalizado completo (13 dígitos)
2. `558576020655` — sem nono dígito (12 dígitos)
3. `85976020655` — sem DDI, com nono dígito (11 dígitos)
4. `8576020655` — sem DDI, sem nono dígito (10 dígitos)
5. O número raw original (se diferente dos acima)

**Isso é essencial para contatos migrados (ex: Locktec) que podem estar armazenados sem o DDI `55`.** Sem essas variantes sem DDI, o webhook não encontra o contato existente e cria um duplicado, causando tickets duplicados.

### Retry Automático no Envio (`sendToMeta`)

Se o envio falhar com erro de destinatário (códigos 131026, 100, subcodes 2388055, 1245301, ou mensagem contendo "recipient"), o sistema automaticamente:
1. Gera o número alternativo (sem 9° dígito) via `getAlternatePhoneNumber()`
2. Tenta enviar novamente com o formato alternativo
3. Se o retry funcionar, retorna sucesso normalmente

### Busca de Contatos Anti-Duplicação

Na recepção de mensagens (`findOrCreateContact` em `webhook.service.ts`) e chamadas (`calling.service.ts`):
1. Normaliza o número recebido via `normalizeBrazilianPhone()`
2. Gera todas as variantes via `buildPhoneSearchNumbers()` (com/sem DDI, com/sem nono dígito)
3. Busca no banco por TODAS as variações usando `{ in: searchNumbers }`
4. Se encontrar contato com número no formato antigo, atualiza automaticamente para o formato normalizado
5. Evita criação de contatos duplicados para o mesmo número

### Auto-Normalização na Nova Conversa

O endpoint `POST /api/new-conversation`, quando recebe um `contactId` de contato existente:
1. Verifica se o número do contato está normalizado
2. Se não estiver (ex: sem DDI `55`), normaliza automaticamente
3. Verifica conflito antes de atualizar (proteção anti-duplicata com check Prisma P2002)
4. Log: `[NewConversation] Auto-normalizing contact X number from Y to Z`

### IMPORTANTE

- A normalização é aplicada em TODOS os pontos de envio (texto, template, mídia, interativo, localização, contato, reação)
- A normalização NÃO se aplica a números internacionais (sem DDI 55)
- Números de telefone fixo (começam com 0) são mantidos como estão
- A rota `POST /api/contacts/check-ninth-digit` existe para correção em massa de contatos existentes
- NUNCA remover o nono dígito na normalização — a Meta aceita ambos os formatos e faz a normalização interna
- `buildPhoneSearchNumbers()` DEVE gerar variantes sem DDI para compatibilidade com dados migrados de sistemas legados

## Contatos (Contacts)

### Rotas de Contatos

| Rota | Ação |
|------|------|
| `GET /api/contacts?page=N&search=X&walletUserId=Y&tagId=Z` | Listar contatos paginados com busca e filtros |
| `POST /api/contacts` | Criar novo contato (name, number, email, tenantId) |
| `GET /api/contacts/:id` | Detalhes do contato com ContactWallets, ContactTags, ContactCustomFields |
| `PUT /api/contacts/:id` | Atualizar contato |
| `DELETE /api/contacts/:id` | Excluir contato + cascateia tickets, mensagens, anotações etc. (ver "Exclusão de Contato") |
| `GET /api/contacts/:id/messages` | Histórico de mensagens do contato (paginado, todas as fontes) |
| `GET /api/contacts/export` | Exportar CSV com BOM (Excel-compatible) |
| `POST /api/contacts/check-ninth-digit` | Verificar/adicionar 9° dígito em números brasileiros |
| `POST /api/contacts/remove-duplicates` | Remover contatos duplicados |
| `POST /api/contacts/group-by-lid` | Agrupar contatos por LID WhatsApp |

### Busca em Tempo Real

A busca (`search` query param) pesquisa em: `name`, `number`, `email`, `pushname`, `firstName`, `lastName`, `businessName`, `cpf`, `lid`. Usa `contains` com `mode: "insensitive"` (case-insensitive). Frontend usa debounce de 400ms.

### Colunas Configuráveis (Frontend)

16 colunas toggle salvas em `localStorage("voxzap-contacts-columns")`:
- Padrão visíveis: foto, contato, numero, email, tickets, status, atualizacao, acoes
- Opcionais: lidWhatsapp, primeiroNome, sobrenome, empresa, carteira, etiquetas, cpf, aniversario

### IMPORTANTE - Ordem de Rotas no Express

Rotas estáticas (`/api/contacts/export`, `/api/contacts/check-ninth-digit`, etc.) e `POST /api/contacts` DEVEM ser registradas ANTES de `/api/contacts/:id` para evitar que Express interprete "export" como um `:id`.

### Exclusão de Contato (DELETE /api/contacts/:id)

Excluir um contato é **destrutivo total**: remove o contato em si E todo o histórico vinculado (tickets, mensagens, anotações, campanhas, etiquetas, custom fields, transcrições, summaries de IA, etc.).

#### Mapa de FKs de `Contacts` → relações

A maioria dos modelos referencia `Contacts` com `onDelete: Cascade` e cascateia automaticamente:
- `Tickets` (Cascade) → cujos children também cascateiam: `Messages`, `MessagesOffLine`, `LogTickets`, `MessageUpserts`, `TicketActionLogs`, `TicketShareds`, `TicketParticipants`, `OperatorKanbanTickets`
- `BirthdayMessagesSents`, `CampaignContacts`, `ContactCustomFields`, `ContactTags`, `ContactUpserts`, `ContactWallets`, `Messages`(direto), `MessagesOffLine`(direto), `Opportunitys` — todos Cascade

Modelos que apontam pra `Contacts` (ou pra `Tickets` filhos) com **`Restrict`** (default ou explícito) **bloqueiam o delete** se não forem limpos antes:
- `AutoReplyLogs.contactId` (Restrict)
- `AutoReplyLogs.ticketId` (default = Restrict)
- `UserMessagesLog.ticketId` (default = Restrict)
- `CallTranscriptions.contactId` (default = Restrict, relation field `contact`)
- `InteractionSummaries.contactId` (default = Restrict, relation field `contact`)

#### Padrão correto do endpoint

```ts
app.delete("/api/contacts/:id", authenticateToken, async (req: any, res) => {
  try {
    const tenantId = req.user.tenantId;
    const id = parseInt(req.params.id);
    if (!Number.isFinite(id)) return res.status(400).json({ message: "ID inválido" });

    const contact = await prisma.contacts.findFirst({
      where: { id, tenantId }, select: { id: true, name: true },
    });
    if (!contact) return res.status(404).json({ message: "Contato nao encontrado" });

    await prisma.$transaction(async (tx) => {
      const tickets = await tx.tickets.findMany({
        where: { contactId: id, tenantId }, select: { id: true },
      });
      const ticketIds = tickets.map((t) => t.id);

      // Restrict FKs em Tickets — limpar antes do cascade
      if (ticketIds.length > 0) {
        await tx.userMessagesLog.deleteMany({ where: { ticketId: { in: ticketIds } } });
        await tx.autoReplyLogs.deleteMany({ where: { ticketId: { in: ticketIds } } });
      }
      // Restrict FKs em Contacts
      await tx.callTranscriptions.deleteMany({ where: { contactId: id } });
      await tx.interactionSummaries.deleteMany({ where: { contactId: id } });
      await tx.autoReplyLogs.deleteMany({ where: { contactId: id } });

      // Agora seguro — cascade cuida do resto
      await tx.contacts.delete({ where: { id } });
    }, { timeout: 60000, maxWait: 5000 });

    return res.json({ success: true, message: "Contato excluído" });
  } catch (error) {
    console.error("[Contacts] Delete error:", error);
    return res.status(500).json({ message: "Erro ao excluir contato" });
  }
});
```

**Sempre** elevar o timeout do `$transaction` para contatos com muitos tickets/mensagens — o default de 5s estoura facilmente em base grande (Locktec tem contatos com 1k+ mensagens).

### Ações na Tabela de Contatos (Frontend)

Em `client/src/pages/contatos.tsx` cada linha tem 4 ícones na coluna "Ações", todos envolvidos em `<Tooltip>` (o `TooltipProvider` é global em `App.tsx`, não precisa wrap local):

| Ícone | Tooltip | Ação |
|-------|---------|------|
| `Eye` | "Ver informações" | `setSelectedContactId(contact.id)` — abre painel lateral de detalhes |
| `Edit` | "Editar contato" | `handleOpenEdit(contact.id)` — abre dialog de edição |
| `Ban` (verde se bloqueado, vermelho caso contrário) | "Bloquear contato" / "Desbloquear contato" | `blockMutation.mutate(...)` |
| `Trash2` (vermelho) | "Excluir contato" | `setDeleteContactTarget({ id, name })` — abre `AlertDialog` de confirmação |

**Padrão de confirmação (AlertDialog):** o delete usa um state `deleteContactTarget` separado do state genérico `confirmAction` (que é usado pra ações em massa como "Remover Duplicados"). O AlertDialog tem botão "Excluir" em vermelho (`bg-red-600 hover:bg-red-700`), e a `AlertDialogCancel` fica desabilitada enquanto `deleteContactMutation.isPending`.

```tsx
<AlertDialog
  open={!!deleteContactTarget}
  onOpenChange={(open) => { if (!open && !deleteContactMutation.isPending) setDeleteContactTarget(null); }}
>
  <AlertDialogContent data-testid="dialog-delete-contact">
    <AlertDialogHeader>
      <AlertDialogTitle>Excluir contato?</AlertDialogTitle>
      <AlertDialogDescription>
        Tem certeza que deseja excluir <strong>{deleteContactTarget?.name}</strong>?
        Esta ação remove o contato e todos os dados vinculados ... e não pode ser desfeita.
      </AlertDialogDescription>
    </AlertDialogHeader>
    <AlertDialogFooter>
      <AlertDialogCancel disabled={deleteContactMutation.isPending}>Cancelar</AlertDialogCancel>
      <AlertDialogAction
        onClick={() => deleteContactTarget && deleteContactMutation.mutate(deleteContactTarget.id)}
        disabled={deleteContactMutation.isPending}
        className="bg-red-600 hover:bg-red-700 focus:ring-red-600"
      >
        Excluir
      </AlertDialogAction>
    </AlertDialogFooter>
  </AlertDialogContent>
</AlertDialog>
```

## Tickets

### Status e Transições

```
                    ┌──────────────┐
   Webhook ────────►│   PENDING    │◄──── Transferência para fila
                    └──────┬───────┘
                           │ Operador aceita
                           ▼
                    ┌──────────────┐
                    │    OPEN      │◄──── Transferência para usuário
                    └──────┬───────┘
                           │ Operador finaliza
                           ▼
                    ┌──────────────┐
                    │   CLOSED     │
                    └──────────────┘
```

### Rotas de Ticket

| Rota | Ação |
|------|------|
| `GET /api/tickets?status=X` | Listar tickets filtrados por status |
| `GET /api/tickets/:id` | Detalhes do ticket com contato, usuário, fila |
| `PATCH /api/tickets/:id` | Atualizar status (aceitar, finalizar) |
| `POST /api/tickets/:id/transfer` | Transferir para outro usuário ou fila |
| `GET /api/tickets/:id/messages` | Mensagens do ticket (paginado) |
| `GET /api/tickets/:id/protocol` | Retorna o protocolo do ticket `{ protocol: string \| null }` |

### Protocolo Automático de Atendimento

Cada ticket recebe um **número de protocolo** automaticamente na criação. O formato é configurável pelo admin:

| Setting Key | Descrição | Default |
|-------------|-----------|---------|
| `protocolPrefix` | Prefixo (ex: `VX`, `ATD`) | vazio |
| `protocolIncludeDate` | Inclui data YYYYMMDD no protocolo | `enabled` |
| `protocolDigits` | Quantidade de dígitos do ID (4-10) | `6` |

**Exemplo de protocolo:** `VX20260329000042` (prefix=VX, date=20260329, ticketId=42 com 6 dígitos)

**Arquivos-chave:**
- `server/lib/protocol.ts` — `generateProtocol(tenantId, ticketId)` e `getTicketProtocol(ticketId, tenantId)`
- Tabela `TicketProtocols` — `id`, `protocol`, `ticketId`, `userId`, `tenantId`, `createdAt`, `updatedAt`

**Geração automática:**
- `webhook.service.ts` — após `prisma.tickets.create()` no fluxo de mensagem recebida
- `calling.service.ts` — após criação de ticket para chamadas de voz (2 pontos: incoming e missed)
- Envolvido em try/catch (non-fatal) para não bloquear criação do ticket

**Exibição:**
- Chat header (`atendimento.tsx`) — query `GET /api/tickets/:id/protocol`, exibe ao lado do telefone
- Relatórios (`relatorios.tsx`) — coluna "Protocolo" na tabela e filtro de busca por protocolo
- Exports CSV/PDF — protocolo incluído automaticamente

### Mensagem de Despedida (Farewell) e Variáveis

A farewell é enviada ao cliente quando o ticket é fechado. Configurada por canal na tabela `Whatsapps.farewellMessage`.

**Variáveis disponíveis no template:**
| Variável | Valor |
|----------|-------|
| `{{nome}}` | Nome/pushname do contato |
| `{{numero}}` | Número do contato |
| `{{ticket}}` | ID do ticket |
| `{{protocolo}}` | Número de protocolo do ticket |
| `{{canal}}` | Nome do canal WhatsApp |
| `{{fila}}` | Nome da fila do ticket |
| `{{atendente}}` | Nome do operador que atendeu |
| `{{data}}` | Data atual (dd/mm/yyyy) |
| `{{hora}}` | Hora atual (HH:mm) |

**Protocolo automático na farewell:**
- Se o template **contém** `{{protocolo}}`: substituído pelo valor real
- Se o template **não contém** `{{protocolo}}`: o sistema **anexa automaticamente** `\nProtocolo: XXXXX` ao final da mensagem
- Isso garante que o cliente sempre recebe o protocolo, independente da configuração do template

**Pontos de envio da farewell:**
1. `PATCH /api/tickets/:id` (status → closed) — fechamento manual pelo operador (`routes.ts`)
2. `closeKeyWord` detection — auto-close por palavra-chave no webhook (`webhook.service.ts`)

**Substituição de variáveis:**
- Função `replaceMessageVariables()` em `webhook.service.ts` (usada no closeKeyWord)
- Substituição inline em `routes.ts` (usada no fechamento manual)
- Ambos buscam o protocolo real via `getTicketProtocol()` com fallback para formato data+id

### Fechamento de Ticket (closedAt)

**IMPORTANTE — `closedAt` deve ser definido em TODOS os caminhos de fechamento:**

| Caminho | Arquivo | closedAt |
|---------|---------|----------|
| Fechamento manual (PATCH) | `ticket.repository.ts` → `updateStatus()` | `BigInt(Date.now())` |
| closeKeyWord auto-close | `webhook.service.ts` | `BigInt(Date.now())` |
| Auto-close tickets inativos | `routes.ts` → `autoCloseIdleTickets()` | `BigInt(Date.now())` |
| Bulk close | `routes.ts` → `POST /api/tickets/bulk-close` | `BigInt(Date.now())` |

### Roteamento Automático por Tag

Contatos com tags específicas são automaticamente direcionados para filas mapeadas, ignorando o bot/IA.

**Tabela:** `TagQueueRoutes` — `id`, `tagId`, `queueId`, `tenantId`, `skipBot`, `isActive`, `createdAt`, `updatedAt`

**Constraint:** `@@unique([tagId, tenantId])` — uma tag só pode ser mapeada para uma fila por tenant.

**Rotas API:**
| Rota | Ação |
|------|------|
| `GET /api/tag-queue-routes` | Lista mapeamentos do tenant |
| `POST /api/tag-queue-routes` | Cria mapeamento (admin-only, valida tag e fila do tenant) |
| `PUT /api/tag-queue-routes/:id` | Atualiza (queueId, skipBot, isActive) com validação tenant |
| `DELETE /api/tag-queue-routes/:id` | Remove mapeamento com validação tenant |

**Fluxo no webhook (`findOrCreateTicket`):**

A verificação de tags roda **SEMPRE**, independente de campaign/wallet routing:

1. Busca tags do contato via `ContactTags`
2. Verifica `TagQueueRoutes` ativas para essas tags (filtra tag/queue ativas, ordenadas por `priority DESC`)
3. **Se NÃO há campaign/wallet routing:** tag routing completo — define `tagRouted=true`, `walletQueueId`, `tagRoutedSkipBot`, e `tagRoutedGreeting`
4. **Se JÁ há campaign/wallet routing E a tag tem `skipBot=true`:** ativa `tagSkipBotOnly=true` — mantém a fila da campanha/wallet mas desativa o bot
5. Na decisão de ativar bot: `if ((tagRouted && tagRoutedSkipBot) || tagSkipBotOnly)` → `shouldActivateBot = false`

**Variáveis chave:**
- `tagRouted` — tag routing completo (sem campaign/wallet)
- `tagSkipBotOnly` — tag override de skipBot quando campaign/wallet já roteou (CRÍTICO: não substitui a fila, apenas desativa o bot)
- `tagRoutedSkipBot` — valor do campo `skipBot` da TagQueueRoute encontrada
- `tagRoutedGreeting` — mensagem de saudação da rota (só enviada em tag routing completo)

**Logs de diagnóstico:**
- `[Webhook] Tag routing: contact X has tag "Y" -> queue "Z" (id=N, skipBot=B, priority=P)` — routing completo
- `[Webhook] Tag routing skipBot: contact X has tag "Y" with skipBot=true (campaign/wallet routed, applying skipBot only)` — apenas skipBot
- `[Webhook] Bot skipped due to tag routing for contact X` — bot efetivamente desativado
- `[Webhook] Bot skipped due to tag routing for contact X (skipBot only, queue from other source)` — bot desativado, fila veio da campanha/wallet

**Ordem de prioridade no roteamento:**
`Force Wallet` > `Campaign Routing (48h window)` > `Tag Routing (fila)` > `VoxCall Routing` > `Fila padrão + Bot`

**IMPORTANTE:** Tag `skipBot` é um **override transversal** — mesmo que a fila venha de Campaign ou Wallet routing, a tag com `skipBot=true` desativa o bot. A tag NÃO substitui a fila quando campaign/wallet já definiram uma.

**LogTickets:** Cria entrada `type: "tagRouting"` com `queueId` quando o roteamento por tag completo é ativado.

**UI Admin:** Card "Roteamento por Tag" em `configuracoes.tsx` — lista mapeamentos, adiciona/remove, toggle ativo/inativo, toggle "Pular Bot", prioridade numérica, mensagem de saudação.

### Transferência

```typescript
POST /api/tickets/:id/transfer
Body: { userId?: number, queueId?: number }

// Se userId: atribui ao usuário, status → open
// Se queueId: atribui à fila, userId → null, status → pending
// Broadcast: TICKET_TRANSFER via Socket.io
```

**LogTickets na transferência:**
- Cria `type: "transfered"` com `userId` do operador que transferiu (remetente)
- Se `targetUserId` informado: cria `type: "receivedTransfer"` com `userId` do operador que recebeu
- Ambos registram `queueId` e `tenantId`

**canAccessTicket após transferência:**
- Após transferência, o ticket.userId muda para o novo operador
- `canAccessTicket()` verifica `ticket.userId === user.userId` como check prioritário — operador que recebeu a transferência tem acesso imediato, independente de pertencer à fila

### Permissão de Canal vs Permissão de Fila (UserWhatsapps × UsersQueues)

São **dois vínculos independentes** e frequentemente confundidos. Tela de operadores (`client/src/pages/operadores.tsx`) mostra **apenas as filas** — o vínculo de canal hoje **não tem UI no projeto** e fica invisível ao admin.

| Vínculo | Tabela | Cardinalidade | Função |
|---|---|---|---|
| **Operador ↔ Fila** | `UsersQueues` | M:N (`userId`, `queueId`) | Roteia novos tickets / distribuição automática para o operador |
| **Operador ↔ Canal** | `UserWhatsapps` (id, userId, whatsappId, isActive, createdAt, updatedAt) | M:N | **Permissão de visibilidade** dos atendimentos do canal |
| **Canal → Fila padrão** | `Whatsapps.queueId` (NULLABLE) | **1:1** | Fila default para novos tickets entrando naquele canal — NÃO é permissão |
| **Canal ↔ Filas** (M:N) | **NÃO EXISTE** | — | Não há tabela `QueueWhatsapps` no schema atual |

**Implicações operacionais:**

1. **Não há UI nem endpoint para criar/editar `UserWhatsapps` no VoxZap** — `rg "UserWhatsapps" server/` só retorna leituras na flag `restrictHistoryToOperatorChannels`. A configuração foi herdada de seeds/migrações iniciais e só pode ser ajustada por SQL direto no banco.

2. **Vínculos órfãos do seed inicial são comuns**: no onboarding do Locktec, todos os operadores foram vinculados a múltiplos canais na mesma data/hora (script de bootstrap), independente de quais filas eles atendiam. Isso gera operadores de cobrança com vínculo a canal Locktec (e vice-versa) — alimenta a sensação de "vazamento cross-canal" mesmo quando a permissão técnica está correta.

3. **Flag `restrictHistoryToOperatorChannels`** (Settings, default off; `server/routes.ts` ~L2068 e ~L2763) é o único ponto que usa `UserWhatsapps` para gating: quando ativada, o histórico cross-ticket de `/api/tickets/:id/messages` e `/api/contacts/:id/messages` é filtrado para tickets cujo `whatsappId` pertença aos canais vinculados ao operador (`UserWhatsapps.isActive=true`). O ticket atual sempre é visível; admin/super passam direto.

4. **Para auditar/corrigir vínculos por SQL**: classifique os operadores por `UsersQueues` (filas que ele atende) e compare com `UserWhatsapps` (canais que ele pode ver). Se houver descompasso (operador só atende fila X mas tem vínculo a canal Y onde fila X não roteia), revogue. Caso real documentado: forensic do ticket #212280 (Locktec, abr/2026) — `Andreza Maria` (filas Cobrança Receptiva + Cobrança Ativa) tinha vínculo a Locktec **e** CobrancaAtiva no `UserWhatsapps`; o vínculo Locktec foi removido (DELETE do registro). Mesma correção aplicada em Juliana Figueiredo e Mariana Barbosa.

5. **Sempre fazer backup antes de mexer em UserWhatsapps em produção**:
   ```bash
   docker exec <client>-db pg_dump -U voxzap -d voxzap \
     -t '"UserWhatsapps"' --data-only --column-inserts \
     > /opt/tenants/<client>/backups/userwhatsapps-pre-fix-$(date +%Y%m%d).sql
   ```

### Tabs da Interface (atendimento.tsx)

| Tab | Status | Descrição |
|-----|--------|-----------|
| Atendendo | `open` | Tickets atribuídos ao operador logado |
| Aguardando | `pending` | Tickets na fila esperando aceitação |
| Finalizados | `closed` | Histórico de tickets encerrados |

## Socket.io - Tempo Real

### Rooms (Canais)

| Room | Formato | Uso |
|------|---------|-----|
| Tenant | `tenant:{tenantId}` | Atualizações globais do tenant |
| Usuário | `user:{userId}` | Notificações pessoais |
| Ticket | `ticket:{ticketId}` | Mensagens de um ticket específico |
| Fila | `queue:{queueId}` | Atualizações de fila específica |

### Eventos Principais

| Evento | Direção | Payload | Uso |
|--------|---------|---------|-----|
| `NEW_MESSAGE` | Server→Client | Mensagem completa | Nova mensagem (in/out) |
| `MESSAGE_ACK_UPDATE` | Server→Client | `{ messageId, ack }` | Atualização de status de entrega |
| `TICKET_UPDATE` | Server→Client | Ticket atualizado | Mudança de status/atribuição |
| `TICKET_TRANSFER` | Server→Client | Dados de transferência | Ticket transferido |
| `CONNECTION_UPDATE` | Server→Client | Status da conexão | Conexão WABA mudou status |
| `USER_STATUS` | Server→Client | `{ userId, status, isOnline }` | Presença do operador |
| `join_ticket` | Client→Server | `ticketId` | Entrar na room do ticket |
| `leave_ticket` | Client→Server | `ticketId` | Sair da room do ticket |

### Autenticação WebSocket

```typescript
// Handshake com JWT no auth
io.use((socket, next) => {
  const token = socket.handshake.auth.token;
  // Valida JWT e extrai userId, tenantId
  // Auto-join: tenant:{tenantId}, user:{userId}
});
```

## Repositórios (Repository Pattern)

### MessageRepository

```typescript
findByTicketId(ticketId, tenantId, options?: { page, limit })  // Paginado, ordenado por timestamp
findRecent(tenantId, limit)                                      // Mensagens recentes
countToday(tenantId)                                              // Contagem de hoje
create(data)                                                      // Criar mensagem
updateAck(messageId, ack)                                         // Atualizar status de entrega
```

### TicketRepository

```typescript
findMany(filters: { status, userId, queueId, tenantId, page, limit })  // Filtrado e paginado
findById(id, tenantId)                                                   // Com relações (contact, user, queue)
countByStatus(tenantId)                                                  // Contagem por status
updateStatus(id, tenantId, status, userId?)                              // Mudar status
updateLastMessage(id, tenantId, lastMessage)                             // Atualizar preview
```

### WhatsappRepository

```typescript
findByTenantId(tenantId)    // Todas conexões do tenant
findById(id, tenantId)      // Conexão específica
countConnected(tenantId)    // Quantas conectadas (status=CONNECTED)
```

### QueueRepository

```typescript
findMany(tenantId)                        // Listar filas com usuários
findById(id, tenantId)                    // Fila específica
create(data) / update(id, tenantId, data) / delete(id, tenantId)  // CRUD
setQueueUsers(queueId, tenantId, userIds) // Associar usuários
findByUserId(userId, tenantId)            // Filas do usuário
getUserIdsForQueue(queueId)               // Usuários da fila
```

#### Exclusão de Filas — FK Constraints
O método `delete(id, tenantId)` precisa limpar TODAS as referências FK antes de deletar a fila:
1. `Tickets.queueId` → set null (Prisma `updateMany`)
2. `Messages.queueId` → set null (**raw SQL** `$executeRawUnsafe` — coluna existe no banco de produção mas NÃO está no schema Prisma)
3. `StepsReplyActions.queueId` → set null (Prisma `updateMany`, `onDelete: Restrict`)
4. `Whatsapps.queueIdImportMessages` → set null (Prisma `updateMany`)
5. `UsersQueues` → deleteMany (Prisma, `onDelete: Cascade` mas feito explicitamente)
6. `LogTickets.queueId` e `QueueSchedules.queueId` → auto-handled (`onDelete: Cascade`)

**ATENÇÃO**: A tabela `Messages` no banco de produção tem coluna `queueId` com FK para `Queues`, mas essa coluna **não está mapeada no schema Prisma**. Por isso usa-se raw SQL:
```typescript
await prisma.$executeRawUnsafe(
  `UPDATE "Messages" SET "queueId" = NULL WHERE "queueId" = $1`,
  id,
);
```

### UserRepository

```typescript
findByEmail(email)                          // Login (inclui tenant)
findById(id)                                // Por ID (inclui tenant)
updatePresence(userId, status, isOnline)    // Atualizar presença
setOnline(userId)                           // Conexão WebSocket/login — PRESERVA status "pause"
setOffline(userId)                          // Desconexão WebSocket — PRESERVA status "pause"
findOperatorsWithStats(tenantId)            // Operadores com contagem de tickets
```

## Schema do Banco (Prisma)

### Messages

```prisma
model Messages {
  id          String   @id @default(uuid())
  body        String
  ack         Int      @default(0)
  read        Boolean  @default(false)
  fromMe      Boolean  @default(false)
  mediaType   String?
  mediaUrl    String?
  dataJson    String?              // JSON: wabaMediaId, coordenadas, contatos, erros
  timestamp   BigInt
  ticketId    Int
  contactId   Int
  tenantId    Int
  ticket      Tickets  @relation(...)
  contact     Contacts @relation(...)
  tenant      Tenants  @relation(...)
}
```

### Tickets

```prisma
model Tickets {
  id              Int      @id @default(autoincrement())
  status          String   @default("pending")   // pending, open, closed
  lastMessage     String?
  unreadMessages  Int      @default(0)
  contactId       Int
  userId          Int?                            // null = não atribuído
  whatsappId      Int
  queueId         Int?                            // null = sem fila
  tenantId        Int
  contact         Contacts   @relation(...)
  user            Users?     @relation(...)
  whatsapp        Whatsapps  @relation(...)
  queue           Queues?    @relation(...)
  messages        Messages[]
}
```

### Contacts

```prisma
model Contacts {
  id             Int      @id @default(autoincrement())
  name           String
  number         String                            // Único por tenant
  profilePicUrl  String?
  email          String?
  isGroup        Boolean  @default(false)
  tenantId       Int
}
```

### Whatsapps (Conexões)

```prisma
model Whatsapps {
  id            Int      @id @default(autoincrement())
  name          String
  status        String   @default("DISCONNECTED")  // CONNECTED, DISCONNECTED, OPENING
  number        String?
  isDefault     Boolean  @default(false)
  isActive      Boolean  @default(true)
  isDeleted     Boolean  @default(false)            // Soft-delete
  type          String   @default("whatsapp")
  bmToken       String?                              // Bearer Token Meta
  tokenAPI      String?                              // Phone Number ID
  wabaId        String?                              // WABA ID
  wabaVersion   String?  @default("v22.0")
  webhookChecked String?                             // Verify Token
  queueId       Int?                                 // Fila padrão para novos tickets
  tenantId      Int
}
```

## Renderização no Frontend (atendimento.tsx)

### Função renderMedia(message)

Renderiza tipos de mídia padrão com base em `message.mediaType`:

```typescript
switch (mediaType) {
  case "image":
  case "sticker":
    // <img> clicável, sticker max-w-[150px], image max-w-[280px]
    // Clique abre mediaViewer (exceto sticker)

  case "video":
    // <video> com controls + botão de download

  case "audio":
    // <audio> com controls + ícone Mic

  case "document":
    // Botão com FileText + nome do arquivo + mime type
}
```

### Tipos Especiais (fora do renderMedia)

```typescript
// Template
if (message.body?.startsWith("[TEMPLATE]"))
  // Remove prefixo e exibe corpo

// Interativo
if (message.body?.startsWith("[INTERACTIVE]") || message.body?.startsWith("[LIST]"))
  // Remove prefixo e exibe título

// Localização (mediaType === "location")
// Parseia dataJson → { latitude, longitude, name, address }
// Renderiza: Card com MapPin grande + link "Abrir no Google Maps"
// Link: https://www.google.com/maps?q={lat},{lng}

// Contato (mediaType === "contactMessage")
// Parseia dataJson → { contacts: [{ name: { formatted_name }, phones: [{ phone }] }] }
// Renderiza: Card com Contact2 icon + nome + telefone clicável
// Link telefone: https://wa.me/{phone_limpo}

// Unsupported (body === "[UNSUPPORTED]" || body?.startsWith("⚠️"))
// Renderiza: Info icon + "Mensagem não suportada pelo WhatsApp Cloud API" (itálico)
```

### Media URL Construction

```typescript
// Para mídia recebida (tem wabaMediaId no dataJson):
const mediaUrl = `/api/media-proxy/${wabaMediaId}?tenantId=${tenantId}`;

// Para mídia enviada (tem mediaUrl direto):
const mediaUrl = message.mediaUrl;
```

## Templates WABA

### Serviço (template.service.ts)

```typescript
// Listar templates
GET /{version}/{wabaId}/message_templates
Headers: Authorization: Bearer {bmToken}

// Criar template
POST /{version}/{wabaId}/message_templates
Body: { name, language, category, components: [...] }

// Editar template
POST /{version}/{templateId}
Body: { components: [...] }

// Deletar template
DELETE /{version}/{wabaId}/message_templates?name={templateName}
```

### Rotas Internas (Multi-Canal WABA)

Cada cliente pode ter **N conexões WABA** ao mesmo tempo (ex: WABA principal + WABA secundário com outro número). As rotas internas aceitam `whatsappId` opcional e roteiam para o WABA correto via `templateService.getConnectionForTemplates(tenantId, whatsappId)`.

| Rota | Onde vai `whatsappId` | Quando obrigatório |
|------|----------------------|--------------------|
| `GET /api/templates?whatsappId=N` | Query string | Opcional — sem ele pega o **primeiro WABA com `status=CONNECTED`** (`findFirst`) |
| `POST /api/templates` | Body | Opcional — mesma fallback |
| `PUT /api/templates/:id` | Body | Opcional — mesma fallback |
| `DELETE /api/templates/:name?whatsappId=N` | Query string | Opcional — mesma fallback |

```ts
// server/services/template.service.ts → getConnectionForTemplates()
const where: any = { tenantId, type: "waba", isDeleted: false, isActive: true,
                     wabaId: { not: null }, bmToken: { not: null } };
if (whatsappId) where.id = whatsappId;
else where.status = "CONNECTED";
return prisma.whatsapps.findFirst({ where, select: { id, wabaId, bmToken, wabaVersion, name } });
```

#### Armadilha: cliente "não vê todos os templates"

Se o cliente reporta que faltam templates na tela, **quase sempre** é porque tem mais de uma conexão WABA cadastrada e a tela só estava puxando do primeiro `CONNECTED` (sem filtro de canal). Os templates "sumidos" são na verdade de outro `wabaId`. Solução: confirmar quantos canais WABA o tenant tem e usar o seletor de canal na tela (ver Frontend Multi-Canal abaixo).

### Tela de Templates (Frontend Multi-Canal)

`client/src/pages/templates.tsx` precisa rotear todas as chamadas para o canal WABA selecionado:

```tsx
// 1. Carrega lista de canais WABA
const { data: whatsappsData } = useQuery<{ connections: Array<{
  id: number; name: string; type: string; status: string; wabaId: string | null;
}> }>({ queryKey: ["/api/whatsapps"] });

const wabaChannels = (whatsappsData?.connections || []).filter(c => c.type === "waba" && c.wabaId);

// 2. State + auto-select do primeiro CONNECTED (fallback: primeiro da lista)
const [selectedWhatsappId, setSelectedWhatsappId] = useState<number | null>(null);
useEffect(() => {
  if (selectedWhatsappId !== null || wabaChannels.length === 0) return;
  const firstConnected = wabaChannels.find(c => c.status === "CONNECTED");
  setSelectedWhatsappId((firstConnected || wabaChannels[0]).id);
}, [wabaChannels, selectedWhatsappId]);

// 3. Query principal: queryKey inclui o whatsappId, enabled aguarda auto-select
const { data } = useQuery<TemplatesResponse>({
  queryKey: ["/api/templates", { whatsappId: selectedWhatsappId ?? undefined }],
  enabled: selectedWhatsappId !== null,
});

// 4. Mutations passam whatsappId:
//    POST/PUT → no body: { ..., whatsappId: selectedWhatsappId }
//    DELETE  → na URL: `/api/templates/${name}?whatsappId=${selectedWhatsappId}`

// 5. Topbar tem o <Select> de canal (só renderiza se >0 canais):
{wabaChannels.length > 0 && (
  <Select value={String(selectedWhatsappId)} onValueChange={(v) => setSelectedWhatsappId(parseInt(v))}>
    <SelectTrigger data-testid="select-waba-channel"><SelectValue placeholder="Canal WABA" /></SelectTrigger>
    <SelectContent>
      {wabaChannels.map(c => (
        <SelectItem key={c.id} value={String(c.id)}>
          {c.name}{c.status !== "CONNECTED" && " (desconectado)"}
        </SelectItem>
      ))}
    </SelectContent>
  </Select>
)}
```

**Pontos críticos:**
- O `queryKey: ["/api/templates", { whatsappId: ... }]` aproveita o `getQueryFn` global (`client/src/lib/queryClient.ts` linha 124) que serializa o segundo elemento do array como query string automaticamente. Por isso NÃO precisa montar URL manualmente nem definir `queryFn` próprio.
- `enabled: selectedWhatsappId !== null` evita um fetch sem filtro antes do auto-select acontecer (que pegaria do primeiro CONNECTED no backend e depois recarregaria — flicker).
- Na invalidação `queryClient.invalidateQueries({ queryKey: ["/api/templates"] })` o React Query usa **prefix match** por padrão, então invalida todas as variantes (todos os canais), o que é o desejado quando uma mutation acontece em um canal específico.
- Canais desconectados também aparecem no dropdown (com sufixo "(desconectado)") porque o `wabaId` continua válido — útil pra ver/limpar templates de canais desativados.

### Envio de Template

```typescript
// Payload para Meta API
{
  messaging_product: "whatsapp",
  to: phoneNumber,
  type: "template",
  template: {
    name: templateName,
    language: { code: languageCode },
    components: [
      {
        type: "body",
        parameters: [
          { type: "text", text: "valor1" },
          { type: "text", text: "valor2" }
        ]
      }
    ]
  }
}
```

### ⚠️ Armadilhas e Correções Críticas no Envio de Template

**Lições aprendidas em produção Locktec (2026-04-21).** Toda implementação nova deve respeitar:

#### 1. `parameter_format`: POSITIONAL vs NAMED
A Meta tem dois formatos de placeholder no body de templates:

| Formato | Sintaxe no template | Como enviar parâmetros |
|---|---|---|
| `POSITIONAL` (legado) | `{{1}}`, `{{2}}` | `{ type: "text", text: "valor" }` na ordem |
| `NAMED` (novo) | `{{nome_var}}` | `{ type: "text", parameter_name: "nome_var", text: "valor" }` |

**Templates NAMED enviados como POSITIONAL falham com erro `(#132000)`**. O campo a inspecionar é `template.parameter_format` retornado por `GET /message_templates`.

#### 2. Busca de template por nome NÃO é exata
A Meta API faz **busca por prefixo** em `?name=`. Exemplo: `?name=teste` retorna **tanto `teste` quanto `testes`**. Pegar `data.data[0]` cegamente envia parâmetros do template errado.

**Sempre filtrar localmente:**
```typescript
const template = data.data.find(
  (t: any) => t.name === templateName && (!language || t.language === language)
);
if (!template) {
  console.warn(`[WABA] Template not found exactly: ${templateName}/${language}`);
  return null;
}
```

#### 3. Auto-geração de parâmetros (`fetchTemplateComponents`)
Ao auto-gerar parâmetros padrão (ex: "Cliente") quando o frontend não passou explicitamente, a função deve:

```typescript
const isNamed = template.parameter_format === "NAMED";
const buildParams = (text: string) => {
  if (isNamed) {
    const named = Array.from(text.matchAll(/\{\{([a-zA-Z_][\w]*)\}\}/g)).map(m => m[1]);
    if (named.length === 0) return null;
    const unique = Array.from(new Set(named));
    return unique.map(name => ({ type: "text", parameter_name: name, text: "Cliente" }));
  }
  const matches = text.match(/\{\{(\d+)\}\}/g);
  if (!matches) return null;
  const varCount = Math.max(...matches.map(m => parseInt(m.replace(/\{|\}/g, ""))));
  return Array.from({ length: varCount }, () => ({ type: "text", text: "Cliente" }));
};
```

**Templates com 0 placeholders devem retornar `null`** (não enviar componente body vazio). Se enviar `parameters: []` ou parâmetros sobrando, Meta rejeita com:
```
(#132000) Number of parameters does not match the expected number of params
details: 'body: number of localizable_params (N) does not match the expected number of params (M)'
```

#### 4. Falhas de template NÃO devem ser silenciosas
No endpoint `POST /api/tickets/new-conversation` (e similares), NUNCA fazer:
```typescript
// ❌ ERRADO: catch silencioso retorna 201 e operador não vê erro
try {
  await whatsappService.sendTemplateMessage(...);
} catch (e) { console.error(e); }
return res.status(201).json({ ticket });
```

**Padrão correto:**
```typescript
// ✅ Capturar erro do template e devolver no response
let templateError: string | null = null;
try {
  const result = await whatsappService.sendTemplateMessage(...);
  if (result.success) {
    await messageRepository.create({ ... });
  } else {
    templateError = result.error || "Falha ao enviar template";
    console.error(`[NewConversation] Template "${templateName}" rejected:`, result.error);
  }
} catch (e: any) {
  templateError = e?.message || "Erro inesperado";
}
return res.status(201).json({ ticket, existing: false, templateError });
```

**Frontend exibe toast destrutivo quando `templateError` está presente:**
```tsx
if (result.templateError) {
  toast({
    title: "Ticket criado, mas template falhou",
    description: `Meta rejeitou: ${result.templateError}`,
    variant: "destructive",
    duration: 10000,
  });
}
```

#### 5. Códigos de erro comuns no envio de template

| Code | Causa | Ação |
|---|---|---|
| `132000` | Número de params não bate | Verificar `parameter_format` e contar `{{...}}` reais |
| `132001` | Template não existe (ou em rascunho) | Status precisa ser `APPROVED` |
| `132005` | Texto traduzido é muito longo | Reduzir parâmetros |
| `132007` | Template pausado por baixa qualidade | Aguardar Meta reativar |
| `131056` | Pair-rate-limit (mesmo número) | Backoff 30-60s |

#### 6. Validar resposta da Meta — não confiar em `status: 200`
Mesmo retornando 200, o body pode ter `error`. Sempre checar:
```typescript
const data = await res.json();
if (!res.ok || data.error) {
  return { success: false, error: data.error?.message || `HTTP ${res.status}` };
}
```

#### 7. ❗ Frontend: NUNCA ler o body de uma `Response` duas vezes
Bug recorrente em `client/src/lib/queryClient.ts` — `throwIfResNotOk`:

```typescript
// ❌ ERRADO: se .json() falha, .text() lança "body stream already read"
try {
  const json = await res.json();
  errorMessage = json.message || ...;
} catch {
  const text = await res.text(); // ← STREAM JÁ CONSUMIDO
  if (text) errorMessage = text;
}
```

Sintoma para o usuário final: toast vermelho `"Erro ao enviar mensagem — Failed to execute 'text' on 'Response': body stream already read"` mascarando o erro real do servidor (ex: janela 24h, validação Zod, 401, etc).

**Padrão correto** — ler como text uma vez e tentar parsear:
```typescript
async function throwIfResNotOk(res: Response) {
  if (!res.ok) {
    let errorMessage = res.statusText;
    try {
      const text = await res.text();
      if (text) {
        try {
          const json = JSON.parse(text);
          errorMessage = json.message || json.error || text;
        } catch {
          errorMessage = text;
        }
      }
    } catch { /* mantém statusText */ }
    throw new Error(errorMessage);
  }
}
```

Alternativa: `res.clone().json()` antes do primeiro consumo. Mas o padrão acima é mais simples e cobre todos os casos (HTML de erro do nginx, body vazio, JSON malformado, etc).

## Assistente IA para Templates

### Arquitetura

O sistema possui um assistente de IA integrado aos modais de criação e edição de templates, implementado em:

- **Backend**: `server/services/template-ai.service.ts`
- **Frontend**: Componente `TemplateAIAssistant` em `client/src/pages/templates.tsx`
- **Rotas**: `GET /api/templates/ai-check` e `POST /api/templates/ai-generate`

### Modos de Operação

#### Modo Criação (create)
- Ativado no modal "Criar Template" quando LLM está disponível
- Faz perguntas contextuais por categoria (Marketing/Utility/Authentication)
- Gera template com nome, cabeçalho, corpo e rodapé
- Botão "Aplicar no Formulário" preenche os campos automaticamente

#### Modo Edição (edit)
- Ativado no modal "Editar Template" via botão "Melhorar com Assistente IA"
- Recebe o template existente (nome, status, conteúdo) como contexto
- Analisa possíveis motivos de rejeição pela Meta
- Lista problemas encontrados e gera versão melhorada
- Mantém o mesmo nome do template original

### Detecção de Provedor LLM

```typescript
// Auto-detecta do registro AiAgents do tenant
GET /api/templates/ai-check → { available: boolean, provider?: string, model?: string }

// Verifica na tabela AiAgents:
// - provider: "openai" | "gemini" | "claude" | "deepseek"
// - apiKey: chave da API do provedor
// - model: modelo específico a usar
```

### API de Geração

```typescript
POST /api/templates/ai-generate
Body: {
  category: "MARKETING" | "UTILITY" | "AUTHENTICATION",
  language: "pt_BR" | "en_US" | "es",
  messages: [{ role: "user" | "assistant", content: string }]
}
Response: { response: string }
// O response contém texto + JSON delimitado por [TEMPLATE_JSON]...[/TEMPLATE_JSON]
```

### Extração de Template no Frontend

```typescript
// O frontend extrai o JSON do template usando delimitadores:
const jsonMatch = response.match(/\[TEMPLATE_JSON\]([\s\S]*?)\[\/TEMPLATE_JSON\]/);
// Resultado: { name, headerText, bodyText, footerText }
```

### Prompt do Sistema

O prompt em `TEMPLATE_SYSTEM_PROMPT` inclui:
- Regras da Meta para templates (limites de caracteres, variáveis, regras por categoria)
- Perguntas guiadas por categoria
- Motivos comuns de rejeição pela Meta (conteúdo promocional em Utility, linguagem enganosa, CAPS LOCK, etc.)
- Fluxo estruturado para modo edição (analisar → listar problemas → gerar versão melhorada → explicar mudanças)
- Validação pós-LLM (renumeração de variáveis, remoção de variáveis do footer, limites de caracteres)

### Validação Pós-Geração (Backend)

```typescript
// Em validateAndFixTemplate():
// 1. Renumera variáveis sequencialmente: {{1}}, {{2}}, {{3}}
// 2. Remove variáveis do footer (não permitido pela Meta)
// 3. Trunca header em 60 chars, body em 1024 chars, footer em 60 chars
// 4. Limita header a 1 variável
```

### Estado no Frontend

```typescript
// Modal de Criação:
showAIAssistant: boolean     // controla visibilidade do assistente no modal de criação
aiAssistantKey: number       // força remount ao reabrir

// Modal de Edição:
showEditAIAssistant: boolean // controla visibilidade do assistente no modal de edição

// TemplateAIAssistant aceita:
mode: "create" | "edit"      // modo de operação
existingTemplate?: {         // dados do template para modo edit
  name, status, headerText, bodyText, footerText
}
```

## Multi-Tenancy

### JWT Payload & authenticateToken

O middleware `authenticateToken` decodifica o JWT e popula `req.user` com o payload gerado por `authService.buildAuthPayload()`:

```typescript
// server/services/auth.service.ts
buildAuthPayload(user) {
  return {
    userId: user.id,      // ← ATENÇÃO: é "userId", NÃO "id"
    tenantId: user.tenantId,
    email: user.email,
    profile: user.profile,
    tokenVersion: user.tokenVersion,
  };
}
```

**REGRA CRÍTICA:** Nas rotas protegidas com `authenticateToken`, SEMPRE use:
- `req.user.userId` — para o ID do usuário (NUNCA `req.user.id`, que retorna `undefined`)
- `req.user.tenantId` — para o ID do tenant
- `req.user.profile` — para o perfil/role do usuário

**Bug comum:** Usar `req.user.id` em vez de `req.user.userId` faz queries SQL receberem `undefined`, ignorando o filtro de usuário e retornando dados de todo o tenant.

### Cache em Rotas Autenticadas

Rotas que retornam dados específicos do usuário logado devem usar o middleware `noCache` para evitar que o ETag do Express sirva dados de um usuário para outro:

```typescript
const noCache = (_req: any, res: any, next: any) => {
  res.set("Cache-Control", "private, no-store, no-cache, must-revalidate");
  res.set("Pragma", "no-cache");
  res.removeHeader("ETag");
  next();
};

app.get("/api/rota-por-usuario", authenticateToken, noCache, async (req, res) => { ... });
```

No frontend, queries React Query que dependem do usuário devem incluir `userId` na `queryKey`:
```typescript
const userId = user?.id;
useQuery({ queryKey: ["/api/dashboard/operator/stats", userId, filterKey], ... });
```

### Isolamento de Dados

- Todas as tabelas possuem `tenantId`
- Todas as queries filtram por `tenantId`
- JWT contém `userId` e `tenantId` — extraídos em cada request via `req.user.userId` e `req.user.tenantId`
- WebSocket rooms são segregadas por tenant

### Global Tenant Selector (Superadmin)

O superadmin pode visualizar dados de qualquer tenant via seletor global no sidebar. O padrão de implementação é:

**Frontend:**
- Zustand store `use-tenant.ts` persiste tenant selecionado em localStorage (`voxzap-tenant`)
- `effectiveTenantId` é computado em cada página e passado como `?tenantId=X` em todas as chamadas API
- Queries devem incluir `effectiveTenantId` na `queryKey` para invalidação correta

**Backend:**
- `resolveDashboardTenantId(req)` — resolve tenantId efetivo (superadmin pode override via query param, outros usam `req.user.tenantId`)
- `isExternalTenantRequest(req)` — verifica se é requisição para tenant externo (diferente do tenant do usuário logado)
- `withExternalPg(callback)` — executa SQL raw no banco externo via `pg.Client`. Retorna `null` se DB indisponível

**Padrão de rota com banco externo:**
```typescript
app.get("/api/recurso/:id", authenticateToken, async (req, res) => {
  const tenantId = resolveDashboardTenantId(req);
  
  if (isExternalTenantRequest(req)) {
    const extResult = await withExternalPg(async (client) => {
      const result = await client.query(
        `SELECT * FROM "Tabela" WHERE id = $1 AND "tenantId" = $2`,
        [id, tenantId]
      );
      if (result.rows.length === 0) return { found: false as const };
      return { found: true as const, data: result.rows[0] };
    });
    
    if (extResult) {
      if (!extResult.found) return res.status(404).json({ message: "Não encontrado" });
      return res.json(extResult.data);
    }
    // extResult === null → DB indisponível, fallback para Prisma
  }
  
  // Prisma fallback
  const data = await prisma.tabela.findFirst({ where: { id, tenantId } });
  return res.json(data);
});
```

**IMPORTANTE — Sentinel Pattern:**
- `withExternalPg` retorna `null` quando o banco externo está indisponível
- Se o callback retornar `null`, `withExternalPg` também retorna `null` — ambíguo!
- Use `{ found: boolean }` como wrapper para distinguir "não encontrado" de "DB indisponível"
- Nunca retorne `null` diretamente do callback quando "não encontrado" é uma possibilidade

**Colunas que podem não existir no banco externo:**
- `isInternal` na tabela `Messages` — não existe no schema externo Locktec
- Sempre verificar compatibilidade de colunas ao escrever SQL raw para banco externo

**Rotas já implementadas com suporte externo:**
- `/api/dashboard/stats` — KPIs do dashboard
- `/api/contacts` — lista de contatos com filtros
- `/api/contacts/:id` — detalhe do contato (com tickets, tags, wallets, custom fields)
- `/api/contacts/:id/messages` — mensagens do contato (paginado)
- `/api/reports/tickets` — relatórios de tickets (list, CSV, PDF)
- Todas as rotas de dashboard (attendances, evaluations, queues)

### Roles de Usuário

| Role | Permissões |
|------|-----------|
| `superadmin` | Acesso total, gerencia tenants, pode visualizar dados de qualquer tenant |
| `admin` | Gerencia conexões, filas, usuários do tenant. Pode espiar qualquer ticket (spy mode read-only). Backend permite interação, mas frontend exige "Assumir atendimento" primeiro |
| `supervisor` | Pode espiar qualquer ticket (spy mode). Se `removeSupPrivileges=enabled`, é tratado como operador comum |
| `user` | Apenas tickets próprios (userId match) + pendentes das suas filas (para aceitar) |

### Controle de Acesso a Tickets

Dois níveis de controle — **acesso** (visualizar) e **interação** (enviar mensagem, fechar, pausar, transferir):

```typescript
// canAccessTicket(user, ticket) — controle de VISUALIZAÇÃO
// admin/superadmin: acesso a todos
// supervisor (não-demotido): acesso a todos do tenant
// user: apenas se ticket.userId === userId OU ticket.queueId nas suas filas

// canInteractWithTicket(user, ticket) — controle de INTERAÇÃO (mensagens, ações)
// Primeiro verifica ownership: ticket.userId === user.userId → true
// Depois verifica admin bypass: isAdminLikeUser(user, supDemoted) → true
// Caso contrário → false (operador não-dono é bloqueado)

// isAdminLikeUser(user, supDemoted) — helper de perfil
// admin || superadmin || (supervisor && !supDemoted)
```

### Isolamento de Tickets por Operador

Padrão profissional de isolamento (como Zendesk/Freshdesk):

**Backend:**
- Operadores (`profile=user`) só veem tickets próprios + pendentes das suas filas (forçado via `userIdOrUnassigned`)
- `canInteractWithTicket()` protege todas as rotas de envio de mensagem (texto, mídia, template, interativo, localização, contato, reação) e ações (PATCH status, transferência, fila)
- PATCH ticket com `isAcceptingPending` bypass: permite qualquer operador aceitar ticket pendente/sem dono (usa `canAccessTicket` em vez de `canInteractWithTicket`)
- Admin/supervisor bypass no backend (safety net) — podem interagir via API
- Notas internas usam `canAccessTicket` (nível de visualização, não interação)

**Frontend (`atendimento.tsx`):**
- `isTicketOwner`: `selectedTicket.userId === user.id` (strict, null = não dono)
- `isAdminLike`: admin/superadmin/supervisor (respeitando `removeSupPrivileges`)
- `isSpyMode`: admin vendo ticket de outro operador (userId !== null e !== user.id)
- `canInteract = isTicketOwner` — frontend read-only para todos que não são donos
- Spy mode: banner azul com "Visualizando atendimento de [Nome]" + botão "Assumir atendimento"
- Badge "Espião" no header do ticket em spy mode
- Campo de digitação e botões de ação ocultos quando `!canInteract`
- Botões de ação inline na lista: apenas para tickets do próprio operador
- Botão "Aceitar" em tickets pendentes: sempre visível (sem guarda de `canInteract`)
- `TICKET_UPDATE` via Socket.io: deseleciona ticket se aceito por outro operador

### Isolamento de Mensagens entre Tickets do Mesmo Contato (CRÍTICO)

**Bug histórico (corrigido 2026-04, Locktec):** `GET /api/tickets/:id/messages` retornava TODAS as mensagens do contato (mesma `contactId`) — quando um operador tinha 2+ tickets abertos em paralelo do mesmo contato (ex: cliente conversando com Comercial e Suporte ao mesmo tempo), as mensagens vazavam entre os tickets.

**Regra correta** (`server/routes.ts` em `GET /api/tickets/:id/messages`):
```typescript
// Mensagens do ticket atual + mensagens de tickets FECHADOS do mesmo contato (histórico)
where: {
  OR: [
    { ticketId: ticketId },                              // ticket atual
    { ticket: { contactId, status: 'closed' } },         // histórico fechado
  ],
  tenantId,
}
```

NUNCA filtrar apenas por `contactId` sem cláusula de status. O histórico fechado é mostrado para contexto, mas conversas paralelas em andamento ficam isoladas — comportamento esperado em ferramentas profissionais (Zendesk/Intercom).

## Presença do Operador

```typescript
// Auto-online: no login e conexão WebSocket
// IMPORTANTE: setOnline() PRESERVA status "pause" — se operador está pausado,
// apenas marca isOnline=true sem alterar status/pausedAt/currentPauseReasonId.
// O broadcast WebSocket envia status correto ("pause" ou "online").
userRepository.setOnline(userId);

// Auto-offline: no logout e desconexão WebSocket
// IMPORTANTE: setOffline() PRESERVA status "pause" — se operador está pausado,
// apenas marca isOnline=false sem alterar status para "offline".
userRepository.setOffline(userId);

// Status manual: online, offline, pause
PATCH /api/users/:id/presence
Body: { status: "online" | "offline" | "pause" }
// Quando status="pause", requer pauseReasonId no body
```

### Sistema de Pausa do Operador

O sistema de pausa é um controle profissional que impede operadores pausados de receberem novos tickets:

**Tabelas Prisma:**
- `PauseReasons` — Motivos de pausa configuráveis (nome, ícone, cor, ativo, ordem)
- `UserPauseHistory` — Histórico completo (userId, pauseReasonId, startedAt, endedAt, duration)
- `Users.status` — "online" | "offline" | "pause"
- `Users.pausedAt` — timestamp do início da pausa
- `Users.currentPauseReasonId` — FK para PauseReasons

**Bloqueio em 3 camadas:**
1. **Distribuição automática** (`webhook.service.ts`): Antes de atribuir ticket, verifica `assignedUser.status !== "pause"`. Se pausado, ticket fica `pending` com `userId=null`.
2. **Aceite manual** (`PATCH /api/tickets/:id`): Quando operador tenta aceitar ticket pending, verifica status. Se pausado → 403 "Você está em pausa. Retome o atendimento para aceitar novos tickets."
3. **Persistência de pausa** (`user.repository.ts`): `setOnline()`/`setOffline()` verificam status antes de atualizar. Se "pause", apenas mudam `isOnline` sem resetar pausa. Reconexão WebSocket, refresh de página e login NÃO removem a pausa.

**Frontend (sidebar):**
- Botão de pausa no sidebar com dialog de seleção de motivo
- Timer em tempo real mostrando duração da pausa
- Badge visual de status (online/offline/pausa) no sidebar
- Toast de erro quando operador pausado tenta aceitar ticket

**Endpoints:**
```
GET    /api/pause-reasons                — Lista motivos ativos
POST   /api/pause-reasons                — Cria motivo (admin)
PUT    /api/pause-reasons/:id            — Edita motivo
DELETE /api/pause-reasons/:id            — Remove motivo
PATCH  /api/users/:id/presence           — Altera status (online/offline/pause)
GET    /api/users/pause-history          — Histórico de pausas com filtros
GET    /api/users/operators              — Operadores com stats (inclui pausa)
```

## Padrões de UI das Páginas

### Relatório de Tickets (`client/src/pages/relatorios.tsx`)
- **Tabela compacta com 13 colunas**: Ticket, Protocolo, Nome, Número, Status, Fila, Canal, Carteira, Criação, Fechamento, Atend. Início, Atend. Encerrou, Aval.
- **Layout**: `table-fixed w-full min-w-[1100px]` com `overflow-x-auto` no container
- **Fonte**: `text-[11px]` em todas as células, `px-2` de padding reduzido
- **Protocolo**: Exibe apenas os últimos 8 caracteres (`ticket.protocol?.slice(-8)`) com `title` tooltip completo
- **Truncamento**: Colunas Nome, Fila, Canal, Atendentes usam `truncate` com `title` tooltip
- **Header "Avaliação"** abreviado para "Aval." para economizar espaço
- **Larguras fixas** por coluna (60px–110px) para garantir que tudo cabe na viewport
- **Filtros superiores**: Data Início/Fim, Status, Fila, Atendente, Canal, Protocolo, Número
- **Busca local na tabela**: Input de filtro que filtra client-side nos resultados carregados
- **Paginação**: Server-side, controlada por query params `page` e `limit`
- **Exportação**: Botões CSV e PDF no header da página
- **Dashboard safe fetch**: Usa `fetchJson` helper (verifica `r.ok`) em vez de `.then(r => r.json())`. Sempre guarda `.map()` com `Array.isArray()`.
- **Botão Espiar** (ícone Eye): ao lado do número do ticket, abre modal Dialog com histórico de mensagens do ticket sem sair da página de relatórios
- **Modal Espiar Ticket**: Dialog com header (contato, status, fila, datas, operadores) + histórico de mensagens com scroll infinito reverso, formatação WhatsApp (`formatWhatsAppText`), separadores de data, indicadores de mídia. Mesmo padrão do spy modal da página de Contatos
- **formatWhatsAppText**: Função local que converte `*bold*`, `_italic_`, `~strikethrough~`, `` ```code``` `` em elementos React (strong, em, del, code)

#### LogTickets — Registro Completo de Eventos do Ticket
A tabela `LogTickets` registra todos os eventos do ciclo de vida de um ticket:

| Tipo | Quando | userId |
|------|--------|--------|
| `open` | PATCH status: pending/paused → open (operador aceita) | Operador que aceitou |
| `closed` | PATCH status: → closed (operador encerra) | Operador que encerrou |
| `transfered` | POST transfer (remetente) | Operador que transferiu |
| `receivedTransfer` | POST transfer (destinatário) | Operador que recebeu |
| `autoClose` | Cron de idle close | null (sistema) |

- **Relatório** consulta LogTickets para preencher:
  - "Atend. Início" = primeiro log `type='open'` (ORDER BY createdAt ASC) → `openMap`
  - "Atend. Encerrou" = primeiro log `type='closed'` (ORDER BY createdAt DESC) → `closeMap`
  - Fallback: `t.userName` (usuário atual do ticket) se nenhum log existir
- **IMPORTANTE**: Sem os logs de `open`/`closed`, transferências mostram o último operador em ambas as colunas (bug corrigido)

### Dashboard Admin (`client/src/pages/dashboard.tsx`)
- Usa `fetchJson` helper que verifica `r.ok` antes de parsear JSON (evita crash em 401/403)
- Todas as chamadas `.map()` protegidas com `Array.isArray()` guard
- KPI cards, tabelas de atendimento/avaliação por operador e departamento, gráfico de atendimento por hora
- **Tema claro/escuro**: Todas as cores usam variáveis CSS do tema — NUNCA usar hex hardcoded (#0b1121, #111827, etc.)
  - Containers: `bg-background` (página), `bg-card` (cards/tabelas)
  - Bordas: `border-border`, `border-input` (em inputs/selects)
  - Texto: `text-foreground` (principal), `text-muted-foreground` (secundário/labels)
  - Dropdowns: `bg-popover`, `text-popover-foreground`, `focus:bg-accent`
  - Hover em linhas de tabela: `hover:bg-muted/50`
  - Recharts: `stroke="hsl(var(--border))"`, `stroke="hsl(var(--muted-foreground))"`, tooltip `backgroundColor: "hsl(var(--card))"`, `color: "hsl(var(--foreground))"`
  - Exceções permitidas: cores de acento fixas (indigo-600, emerald-400, etc.) em botões de ação e ícones de KPI
  - Textos com contraste dual: usar `text-indigo-600 dark:text-indigo-300` quando cor de acento precisa de variação

### Dashboard Operador (`client/src/pages/operator-dashboard.tsx`)

Roteamento baseado em perfil via componente `SmartDashboard` em `App.tsx`:
- `profile="admin"` ou `profile="superadmin"` → `DashboardPage` (admin)
- `profile="user"` (operador) → `OperatorDashboardPage` (pessoal)

**Frontend:**
- KPI cards em grid responsivo: tickets abertos, pendentes, finalizados hoje/mês, mensagens enviadas, TMA, avaliações (quantidade e média no período/mês/geral), tickets aguardando resposta
- Área de saudação com nome do operador + badge de status online/offline (`stats.isOnline`)
- Gráfico de atendimentos por hora (Recharts BarChart)
- Lista de avaliações recentes com estrelas e nome do contato
- Lista de tickets ativos (abertos/pendentes) com tempo de espera, fila e link para atendimento
- Gráfico de desempenho diário (últimos 7 dias) — barras de tickets finalizados e mensagens
- Filtros: data início/fim + período rápido (Hoje/Semana/Mês)

**Backend** (`server/services/dashboard.service.ts`):
- `getOperatorStats(tenantId, userId, filters)` — KPIs pessoais incluindo `isOnline`, `status`, `evaluationsAvgTotal`
- `getOperatorAttendancesByHour(tenantId, userId, filters)` — distribuição horária
- `getOperatorRecentEvaluations(tenantId, userId, limit)` — últimas avaliações com nome do contato
- `getOperatorActiveTickets(tenantId, userId)` — tickets abertos/pendentes com dados do contato e fila
- `getOperatorDailyPerformance(tenantId, userId)` — últimos 7 dias (finalizados + mensagens)

**Rotas API:**
- `GET /api/dashboard/operator/stats`
- `GET /api/dashboard/operator/attendances-by-hour`
- `GET /api/dashboard/operator/recent-evaluations`
- `GET /api/dashboard/operator/active-tickets`
- `GET /api/dashboard/operator/daily-performance`

**Types** (`shared/schema.ts`):
- `OperatorDashboardStats` — campos: `openTickets`, `pendingTickets`, `closedTickets`, `closedToday`, `closedMonth`, `totalMessages`, `avgAttendanceTime`, `evaluationsToday`, `evaluationsMonth`, `evaluationsAvg`, `evaluationsAvgMonth`, `evaluationsAvgTotal`, `ticketsToday`, `ticketsMonth`, `isOnline`, `status`
- `OperatorEvaluationItem` — `ticketId`, `contactName`, `evaluation`, `createdAt`
- `OperatorActiveTicket` — `ticketId`, `contactName`, `contactNumber`, `status`, `queueName`, `createdAt`, `lastMessageAt`
- `OperatorDailyPerformance` — `date`, `closed`, `messages`

**IMPORTANTE — `closedAt` é BigInt:**
- Coluna `Tickets.closedAt` armazena timestamp Unix em **milissegundos** como `BigInt`
- Em SQL raw: usar `to_timestamp("closedAt"/1000)` para converter para timestamp
- Em Prisma: usar `BigInt(date.getTime())` para comparações (ex: `closedAt: { gte: BigInt(periodStart.getTime()) }`)
- NUNCA usar `"closedAt"::date` (falha: cannot cast bigint to date)

### Sidebar Tenant Selector (`client/src/components/app-sidebar.tsx`)
- SelectTrigger: `bg-background border-input text-foreground`
- SelectContent: `bg-popover border-border`
- SelectItem: `text-popover-foreground focus:bg-accent`
- Label "Tenant": `text-muted-foreground`

### Regra Geral de Tema (TODAS as páginas)
- **PROIBIDO**: `bg-[#hex]`, `border-[#hex]`, `text-white` (em contexto de tema), `text-gray-*` para texto genérico
- **OBRIGATÓRIO**: usar classes de tema do Tailwind (`bg-background`, `bg-card`, `text-foreground`, `text-muted-foreground`, `border-border`, `border-input`, `bg-popover`, `focus:bg-accent`)
- **CSS variables disponíveis** em `client/src/index.css`: `:root` (light) e `.dark` (dark) — `--background`, `--foreground`, `--card`, `--border`, `--muted-foreground`, `--popover`, `--input`, `--accent`
- **Recharts/SVG**: usar `hsl(var(--variavel))` em props inline (stroke, fill, contentStyle)
- **Cores de acento** (indigo, emerald, amber, etc.) são OK para ícones, badges, e botões de ação específicos

### Contatos (`client/src/pages/contatos.tsx`)
- Toolbar com busca, filtros (Wallet, Tag), botão adicionar, ações em massa
- Modal "Espiar Contato" estilo WhatsApp com histórico completo de conversas e visualizador de mídia inline (contactMediaViewer)
- Modal "Editar/Criar Contato" com campos completos
- Painel lateral direito com detalhes do contato
- Token JWT lido diretamente do localStorage (`voxzap-auth`) para chamadas de mídia
- Spy dialog usa o mesmo padrão de histórico WhatsApp das outras páginas (ver seção "Padrão de Histórico de Conversas WhatsApp" abaixo)

## Padrão de Histórico de Conversas WhatsApp

Todas as 4 páginas com visualização de mensagens usam o mesmo padrão consistente de histórico estilo WhatsApp:

| Página | Arquivo | Contexto |
|--------|---------|----------|
| Atendimento | `atendimento.tsx` | Chat principal do ticket ativo |
| Painel de Atendimentos | `painel-atendimentos.tsx` | Spy mode (admin/supervisor espiam tickets) |
| Contatos | `contatos.tsx` | Spy dialog "Espiar Contato" (histórico completo do contato) |
| Relatórios | `relatorios.tsx` | Spy dialog "Espiar Ticket" (histórico de mensagens do ticket) |

### Backend - API de Mensagens Paginada

```
GET /api/contacts/:id/messages?page=1&limit=50
GET /api/tickets/:id/messages?page=1&limit=50
```

Resposta:
```typescript
{
  messages: Message[];   // Ordenadas DESC (mais recentes primeiro)
  total: number;
  page: number;
  totalPages: number;
  hasMore?: boolean;
}
```

O backend SEMPRE retorna mensagens de TODOS os tickets do contato (histórico completo cross-ticket), não apenas do ticket ativo. A query agrupa por contactId e busca mensagens de todos os tickets associados.

### Frontend - Padrão de Reverse Infinite Scroll

**Conceito:** Mensagens são exibidas em ordem cronológica (mais antiga no topo, mais recente embaixo). O scroll reverso carrega páginas mais antigas quando o usuário rola para o topo.

**State e refs necessários:**
```typescript
const [messagesPage, setMessagesPage] = useState(1);
const [messages, setMessages] = useState<any[]>([]);
const [isLoadingMore, setIsLoadingMore] = useState(false);
const [hasMore, setHasMore] = useState(false);
const containerRef = useRef<HTMLDivElement>(null);
const scrollHeightBefore = useRef<number>(0);
```

**Effect de acumulação de mensagens:**
```typescript
useEffect(() => {
  if (!selectedId) {
    setMessages([]);
    setMessagesPage(1);
    setHasMore(false);
    setIsLoadingMore(false);
    scrollHeightBefore.current = 0;
    return;
  }
  // Fallback: reset isLoadingMore se query falhou
  if (!loading && isLoadingMore && !data?.messages) {
    setIsLoadingMore(false);
  }
  if (data?.messages) {
    const sorted = [...data.messages].reverse(); // DESC → ASC (cronológico)
    setHasMore((data.totalPages || 1) > messagesPage);
    if (messagesPage === 1) {
      setMessages(sorted);
    } else {
      // Prepend: mensagens mais antigas vão ao topo
      setMessages(prev => {
        const existingIds = new Set(prev.map(m => m.id));
        const unique = sorted.filter(m => !existingIds.has(m.id));
        return [...unique, ...prev];
      });
      // Restaurar posição de scroll
      requestAnimationFrame(() => {
        const container = containerRef.current;
        if (container && scrollHeightBefore.current > 0) {
          container.scrollTop = container.scrollHeight - scrollHeightBefore.current;
          scrollHeightBefore.current = 0;
        }
        setIsLoadingMore(false);
      });
    }
  }
}, [data, loading, isLoadingMore, selectedId, messagesPage]);
```

**Auto-scroll para o final (page 1):**
```typescript
useEffect(() => {
  if (messages.length > 0 && messagesPage === 1) {
    setTimeout(() => {
      const container = containerRef.current;
      if (container) container.scrollTop = container.scrollHeight;
    }, 100);
  }
}, [messages.length, messagesPage]);
```

**Handler de scroll reverso:**
```typescript
const handleScroll = useCallback(() => {
  const container = containerRef.current;
  if (!container) return;
  if (container.scrollTop < 80 && hasMore && !isLoadingMore && !loading) {
    setIsLoadingMore(true);
    scrollHeightBefore.current = container.scrollHeight;
    setMessagesPage(p => p + 1);
  }
}, [hasMore, isLoadingMore, loading]);
```

### Frontend - Separadores de Data

Cada mensagem é envolvida em `<Fragment>` com separador de data condicional:

```tsx
{messages.map((msg, idx) => {
  const msgDate = new Date(msg.createdAt);
  const prevMsg = idx > 0 ? messages[idx - 1] : null;
  const prevDate = prevMsg ? new Date(prevMsg.createdAt) : null;
  const showDateSep = !prevDate || msgDate.toDateString() !== prevDate.toDateString();

  let dateSepLabel = "";
  if (showDateSep) {
    const today = new Date();
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    if (msgDate.toDateString() === today.toDateString()) dateSepLabel = "Hoje";
    else if (msgDate.toDateString() === yesterday.toDateString()) dateSepLabel = "Ontem";
    else dateSepLabel = format(msgDate, "d 'de' MMMM 'de' yyyy", { locale: ptBR });
  }

  return (
    <Fragment key={msg.id}>
      {showDateSep && (
        <div className="flex items-center justify-center my-3">
          <div className="bg-muted/90 dark:bg-slate-700/90 text-muted-foreground text-xs px-4 py-1.5 rounded-full shadow-sm font-medium">
            {dateSepLabel}
          </div>
        </div>
      )}
      {/* Bubble da mensagem */}
    </Fragment>
  );
})}
```

**Imports necessários:**
```typescript
import { Fragment } from "react";
import { format } from "date-fns";
import { ptBR } from "date-fns/locale";
```

### JSX do Container

```tsx
<div ref={containerRef} onScroll={handleScroll} className="flex-1 overflow-y-auto min-h-0">
  {isLoadingMore && (
    <div className="flex justify-center py-2">
      <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
    </div>
  )}
  {/* Messages map with date separators */}
</div>
```

### Reset de Estado no Fechamento

Ao fechar o dialog/mudar de contato, SEMPRE resetar todos os estados:
```typescript
setMessagesPage(1);
setIsLoadingMore(false);
setHasMore(false);
// O effect com selectedId=null cuida de limpar messages e scrollHeightBefore
```

### Polling (Opcional)

- `atendimento.tsx`: page 1 faz polling a cada 5s (`refetchInterval: 5000`) para mensagens live
- `painel-atendimentos.tsx`: page 1 faz polling a cada 5s
- `contatos.tsx`: sem polling (spy read-only, não precisa de live updates)

## Padrões de Código

### Adicionando Novo Tipo de Mensagem

1. **Webhook** (`server/services/webhook.service.ts`):
   - Adicionar case em `extractMessageContent()` para o novo tipo
   - Definir `body`, `mediaType`, `dataJson`

2. **Envio** (`server/services/whatsapp.service.ts`):
   - Adicionar método `send{Type}Message()` se necessário
   - Seguir padrão: montar payload → `sendToMeta()` → retornar `waMessageId`

3. **Rota** (`server/routes.ts`):
   - Adicionar endpoint ou case no POST `/api/messages/send`
   - Salvar mensagem via `messageRepository.create()`
   - Broadcast via Socket.io

4. **Frontend** (`client/src/pages/atendimento.tsx`):
   - Adicionar condição no rendering de mensagens
   - Se mídia: adicionar case em `renderMedia()`
   - Se especial: adicionar condição fora do `renderMedia()`

### Adicionando Nova Rota REST

```typescript
// server/routes.ts
app.get("/api/recurso", authMiddleware, async (req, res) => {
  const { tenantId } = req.user!;  // Sempre filtrar por tenant
  const data = await repository.findMany(tenantId);
  res.json(data);
});
```

### Broadcasting via Socket.io

```typescript
// server/websocket/socket.ts ou dentro de routes/services
const io = getIO();  // Singleton do Socket.io

// Para todo o tenant
io.to(`tenant:${tenantId}`).emit("EVENT_NAME", payload);

// Para um ticket específico
io.to(`ticket:${ticketId}`).emit("NEW_MESSAGE", message);

// Para um usuário específico
io.to(`user:${userId}`).emit("NOTIFICATION", data);
```

## Deploy VPS

### Processo de Atualização

1. Modificar arquivos no Replit
2. Upload via SSH (base64 chunked, 20KB chunks)
3. Rebuild: `cd /opt/voxzap && docker compose up -d --build --force-recreate app`

### Upload Helper Pattern

```bash
# Primeiro chunk (sobrescreve)
echo -n 'BASE64_CHUNK_1' > /tmp/file.b64

# Chunks subsequentes (append)
echo -n 'BASE64_CHUNK_2' >> /tmp/file.b64

# Decodificar e mover
base64 -d /tmp/file.b64 > /opt/voxzap/caminho/arquivo.ts && rm /tmp/file.b64
```

### Headers Anti-Cache

O `server/static.ts` configura headers para prevenir cache do HTML:

```typescript
// HTML: no-cache, no-store, must-revalidate
// Assets (.js/.css): Vite gera hashes no nome, cache seguro
```

## Limitações Conhecidas

1. **Stickers animados do iPhone**: Meta Cloud API envia como `type: "unsupported"` — limitação da plataforma, não é bug
2. **Mídia recebida**: URLs temporárias da Meta expiram — devem ser consumidas via proxy
3. **Templates**: Precisam de aprovação da Meta antes de usar
4. **Rate limits**: Meta impõe limites por número e por WABA
5. **Webhooks**: Precisam responder 200 em menos de 20s ou Meta reenvia

## Menu Permissions (Permissões de Menu)

SuperAdmin configures which menu items each role can see via `/menu-permissions` page. Follows the same pattern as VoxCALL.

### Architecture
- **Backend**: `GET/PUT /api/menu-permissions` in `server/routes.ts` — uses `Settings` table with key `menu-permissions`
- **Storage**: JSON `Record<string, string[]>` (role → array of allowed URL paths) per tenant
- **Frontend Page**: `client/src/pages/menu-permissions.tsx` — role tabs (Usuário/Supervisor/Administrador), grouped checkboxes by Menu Principal/Sistema
- **Sidebar Integration**: `client/src/components/app-sidebar.tsx` fetches `/api/menu-permissions`, `isItemAllowed(url)` filters visible items
- **Default behavior**: When no config exists for a role, all items are visible
- **SuperAdmin**: Always sees everything, regardless of config
- **4 Roles**: `user` (Usuário), `supervisor` (Supervisor), `admin` (Administrador), `superadmin` (Super Admin)

### Key Rules
- `superadminOnly` items are always hidden from non-superadmin regardless of menu-permissions config
- The `isItemAllowed` check runs AFTER the hardcoded role checks (`adminOnly`, `supervisorOnly`)
- PUT requires `superadmin` profile
- GET is available to any authenticated user (needed for sidebar filtering)
- **Empty group hiding**: If all items in a sidebar group (e.g. "Sistema") are filtered out, the entire group label is hidden (IIFE pattern with `if (visibleItems.length === 0) return null`)

## Layout da Página de Atendimento (atendimento.tsx)

A página de atendimento usa um layout de 3 colunas flexbox com painéis opcionais:

```
┌──────────────┬────────────────────────┬─────────────┐
│  Ticket List │      Chat Area         │  Dados do   │
│  w-[340px]   │      flex-1 min-w-0    │  Contato    │
│  shrink-0    │                        │  w-72       │
│              │                        │  shrink-0   │
└──────────────┴────────────────────────┴─────────────┘
```

### Container Principal
- `flex h-[calc(100vh-4rem)] gap-3 p-4`

### Colunas
| Coluna | Classe | Largura | Comportamento |
|--------|--------|---------|---------------|
| Ticket List (esquerda) | `w-[340px] shrink-0 flex flex-col` | 340px fixa | Lista de tickets com scroll vertical |
| Chat (centro) | `flex-1 min-w-0 flex flex-col` | Flexível | `min-w-0` permite encolher quando painéis laterais abrem |
| Dados do Contato (direita) | `w-72 shrink-0 flex flex-col` | 288px fixa | Condicional: `isContactPanelOpen && selectedTicket` |
| Assistente IA (drawer) | `w-80 shrink-0 flex flex-col` | 320px fixa | Condicional: `isAiDrawerOpen` |

### Padrão de Toggle dos Painéis Laterais
- **Botão de abrir painel de contato**: Renderizado condicionalmente `{!isContactPanelOpen && (...)}` no header do chat — **desaparece** quando o painel está aberto
- **Botão X de fechar**: Dentro do próprio painel de contato (`CardHeader`) — único controle de fechar
- **Razão**: Evita confusão visual de dois ícones (toggle + X) sobrepostos quando o painel está aberto
- **AI Drawer**: Toggle sempre visível (Sparkles) no header do chat, alterna entre estados

### Botões de Ação no Painel de Contato
- "Editar Contato": `w-full justify-start`
- "Lido" / "Não Lido": **Lado a lado** em `flex gap-1.5` com `flex-1 text-xs` cada
- "Logs do Ticket": `w-full justify-start`

### Ticket Cards na Sidebar
- Container: `div.divide-y.w-full`
- Cada ticket: `div[role="button"]` com `overflow-hidden`
- Scroll: `div.h-full.overflow-y-auto.overflow-x-hidden` (NÃO usar `<ScrollArea>`)
- Avatar: `h-9 w-9 shrink-0`
- Conteúdo: `flex-1 min-w-0` com `truncate` nos textos
- Badges: `flex flex-wrap gap-1`

## Troubleshooting

### Mensagem não chega no frontend
1. Verificar logs do webhook: `docker compose logs -f app | grep webhook`
2. Verificar se Socket.io broadcast está funcionando
3. Verificar se o tenant/ticket está correto

### Mídia não carrega
1. Verificar se `bmToken` está válido
2. Verificar rota `/api/media-proxy/:mediaId` ou `/api/media/:mediaId`
3. Verificar se `wabaMediaId` está no `dataJson`
4. Verificar console do browser por warnings `[SpyPrefetch]`, `[ContactPrefetch]`, `[SpyViewer]`, `[ContactViewer]`
5. Verificar se o token JWT está presente no Authorization header (Bearer token)
6. Se o viewer abre mas fica em branco: verificar se o Blob foi criado com MIME type explícito
7. Para PDFs: verificar se usa `<iframe>` (não `<object>`) — `<object>` causa problemas de scroll

### Template não envia
1. Verificar status do template (deve ser APPROVED)
2. Verificar se `languageCode` está correto
3. Verificar se número de parâmetros coincide com o template

### Status de entrega não atualiza
1. Verificar webhook de status (`statuses` no payload)
2. Verificar se `updateAck` está sendo chamado
3. Verificar broadcast `MESSAGE_ACK_UPDATE`

## Assistente IA com RAG (Knowledge Base)

### Arquitetura

O sistema de Assistente IA permite que operadores consultem uma base de conhecimento configurada pelo administrador, usando modelos de IA (OpenAI ou Gemini).

```
┌─────────────────────────────────────────────────────────────┐
│  ADMIN configura → ai-knowledge.tsx                         │
│    - Escolhe provedor (OpenAI / Gemini)                     │
│    - Insere API key (mascarada no frontend)                 │
│    - Seleciona modelo                                       │
│    - Upload de documentos (PDF, DOCX, PPTX, TXT, MD)       │
│                                                             │
│  OPERADOR consulta → Modal global (App.tsx) ou              │
│                       Drawer lateral (atendimento.tsx)       │
│    - Faz perguntas sobre a base de conhecimento             │
│    - Recebe respostas formatadas com links clicáveis        │
└─────────────────────────────────────────────────────────────┘
```

### Arquivos Principais

| Arquivo | Responsabilidade |
|---------|-----------------|
| `server/ai-assistant.ts` | Processamento de documentos, chunking, TF-IDF search, chat OpenAI/Gemini |
| `client/src/pages/ai-knowledge.tsx` | Página admin: config LLM + upload de arquivos (adminOnly) |
| `client/src/App.tsx` | Modal global de chat IA (Dialog) no AuthenticatedLayout |
| `client/src/pages/atendimento.tsx` | Drawer lateral de chat IA (botão Sparkles no header do chat) |
| `uploads/ai-knowledge/` | Diretório de arquivos e configs (bloqueado do static serving) |

### Configuração (Admin)

- Armazenada em `uploads/ai-knowledge/ai-assistant-config.json`
- Campos: `provider` (openai/gemini), `apiKey`, `model`
- API key NUNCA enviada ao frontend (mascarada com `••••••••últimos4`)
- Sentinelas `__keep__` / `__current__` tratadas no backend via `loadConfig()`
- Apenas `admin` e `superadmin` podem configurar

### Modelos Suportados

**OpenAI**: gpt-4o, gpt-4o-mini, gpt-4-turbo, gpt-3.5-turbo
**Gemini**: gemini-2.0-flash (padrão), gemini-2.0-flash-lite, gemini-1.5-pro, gemini-1.5-flash

> **IMPORTANTE**: Evitar modelos preview com datas (ex: `gemini-2.0-flash-preview-04-17`) pois expiram.

### Rotas API

| Método | Rota | Descrição | Auth |
|--------|------|-----------|------|
| POST | `/api/ai-assistant/chat` | Chat com o assistente | Qualquer usuário |
| POST | `/api/ai-assistant/upload` | Upload de arquivo de conhecimento | Admin |
| GET | `/api/ai-assistant/files` | Listar arquivos | Admin |
| DELETE | `/api/ai-assistant/files/:id` | Remover arquivo | Admin |
| GET | `/api/ai-assistant/config` | Obter config LLM (key mascarada) | Admin |
| PUT | `/api/ai-assistant/config` | Salvar config LLM | Admin |
| POST | `/api/ai-assistant/test-connection` | Testar API key | Admin |

### Processamento de Documentos

1. Upload via multer (limite 10MB)
2. Extração de texto: `pdf-parse` (PDF), `officeparser` (DOCX/PPTX), direto (TXT/MD)
3. Chunking: blocos de ~500 palavras com overlap de 50 palavras
4. Indexação TF-IDF: termos indexados por chunk para busca rápida
5. Índice salvo em `uploads/ai-knowledge/ai-knowledge-index.json`

### Formatação de Respostas

As respostas da IA são formatadas usando componentes React:
- `cleanMarkdown()`: Remove formatação markdown (bold, italic, code, headers, referências de arquivo)
- `FormatAiMessage`: Renderiza parágrafos com `space-y-2`, indentação para listas
- `RenderLineWithLinks`: Detecta URLs e links markdown, renderiza como `<a>` clicáveis (azul, nova aba)

### Interface de Chat

**Modal Global** (App.tsx - AuthenticatedLayout):
- Botão Sparkles dourado no header principal
- Dialog com chat, botão limpar (Eraser) e fechar (X) separados
- Acessível de qualquer página, para todos os usuários
- `[&>button]:hidden` oculta o X padrão do Dialog

**Drawer no Atendimento** (atendimento.tsx):
- Botão Sparkles no header do chat
- Painel lateral (w-80, shrink-0) com chat do assistente
- Estado local: `isAiDrawerOpen`, `aiMessages`, `aiInput`, `aiLoading`

### Sidebar

- Item "Base de Conhecimento IA" com ícone `BrainCircuit`
- `adminOnly: true` — só aparece para admin/superadmin
- URL: `/ai-knowledge`

### Segurança

- Diretório `uploads/ai-knowledge` bloqueado do static serving (retorna 403)
- API key nunca trafega do backend para o frontend
- Upload limitado a 10MB
- Formatos aceitos: `.pdf`, `.docx`, `.pptx`, `.txt`, `.md`

### Roteamento Inteligente com RAG (Task #43)

Sistema de classificação de intenções que direciona transferências para filas específicas com base na análise semântica da conversa.

#### Arquivos-Chave
| Arquivo | Responsabilidade |
|---------|-----------------|
| `server/services/ai-agent.service.ts` | Lógica de classificação, tags `[TRANSFERIR:intent]`, `tryTransfer()` helper |
| `server/services/business-hours.service.ts` | Verificação de horário antes de qualquer transferência |
| `server/services/message-queue.service.ts` | Fila sequencial por ticket (LLM + envio + persist + transfer no mesmo lock) |
| `server/routes.ts` | CRUD de rotas: GET/POST/PUT/DELETE `/api/ai-agents/:id/routes` |
| `client/src/pages/agentes-ia.tsx` | UI: aba "Roteamento" + aba "Teste" com info de routing |
| `migrations/043_ai_agent_routes.sql` | Migration: coluna `routingEnabled` + tabela `AiAgentRoutes` |

#### Schema
```sql
-- Tabela AiAgentRoutes
id SERIAL PRIMARY KEY,
agentId INT NOT NULL REFERENCES "AiAgents"(id) ON DELETE CASCADE,
tenantId INT NOT NULL REFERENCES "Tenants"(id),
intentName VARCHAR(255) NOT NULL,
intentDescription VARCHAR(500),
targetQueueId INT NOT NULL REFERENCES "Queues"(id),
priority INT DEFAULT 0,
isActive BOOLEAN DEFAULT true,
createdAt TIMESTAMP DEFAULT NOW(),
updatedAt TIMESTAMP DEFAULT NOW()

-- Coluna em AiAgents
routingEnabled BOOLEAN DEFAULT false
```

#### Fluxo de Classificação
```
Mensagem do cliente → processMessageWithAgent()
  → LLM responde com tag:
    ├── [TRANSFERIR:intent_name] → busca rota por intentName
    │   ├── Rota encontrada → tryTransfer(route.targetQueueId)
    │   └── Rota não encontrada → tryTransfer(agent.transferQueueId) [fallback]
    ├── [TRANSFERIR] (sem intent) → tryTransfer(agent.transferQueueId)
    └── Sem tag → incrementa botRetries
```

#### tryTransfer() Helper
Centraliza TODA lógica de transferência (keywords, maxBotRetries, routing, plain tag):
1. Checa `businessHoursService.checkBusinessHours(queueId, tenantId)`
2. Se aberto → transfere (status=pending, atribui queueId, lastCallChatbot=false)
3. Se fechado → **SEMPRE** envia a mensagem de fechamento ao cliente (da exceção ou horário padrão), mantém no bot
   - NÃO existe mais o parâmetro `showClosedMessage` — a mensagem é sempre enviada
   - A mensagem vem de: exceção (QueueScheduleExceptions.message) > mensagem padrão da fila > fallback genérico

#### Limpeza de Respostas
Ao remover tags `[TRANSFERIR]` e `[TRANSFERIR:intent]`, também remove trechos residuais gerados pela IA:
- "para o departamento X"
- "ao departamento X"
- "no departamento X"
- "departamento X"

#### Message Processing Queue
Pipeline completo serializado por ticket via `messageProcessingQueue.enqueue(ticketId, fn)`:
- LLM call → envio WhatsApp → persist message → ticket update → transfer (se aplicável)
- Sequencial por ticket, paralelo entre tickets diferentes
- Substitui debounce antigo de 5s

#### API de Rotas
| Método | Rota | Descrição |
|--------|------|-----------|
| GET | `/api/ai-agents/:id/routes` | Lista rotas + routingEnabled |
| POST | `/api/ai-agents/:id/routes` | Salva rotas + toggle routingEnabled (replace all) |
| PUT | `/api/ai-agents/:id/routes/:routeId` | Atualiza rota individual |
| DELETE | `/api/ai-agents/:id/routes/:routeId` | Remove rota |
| GET | `/api/ai-agents/:id/routes/check-hours` | Verifica horário de fila (queueId param) |
| POST | `/api/ai-agents/:id/analyze-intents` | Analisa base de conhecimento com RAG e sugere intenções |

#### Padrão Intent Matching
```typescript
// Normalização: lowercase + trim + espaços→underscores
const normalize = (s: string) => s.trim().toLowerCase().replace(/\s+/g, "_");
// Match: normalize(tag_intent) === normalize(route.intentName)
```

---

## Sistema de Campanhas WhatsApp

Sistema completo de disparo em massa de templates WhatsApp com dashboard de acompanhamento em tempo real.

### Arquitetura

| Arquivo | Responsabilidade |
|---------|-----------------|
| `server/services/campaign.service.ts` | Envio de campanhas: processamento de contatos, disparo de templates, controle de ritmo |
| `server/routes.ts` | Rotas REST de campanhas (CRUD, start, pause, resume, cancel, contacts, export) |
| `client/src/pages/campanhas.tsx` | Lista de campanhas + Dashboard de acompanhamento |
| `prisma/schema.prisma` | Modelos `Campaigns` e `CampaignContacts` |

### Modelo de Dados

#### Campaigns
| Campo | Tipo | Descrição |
|-------|------|-----------|
| `id` | Serial PK | ID auto-incremento |
| `name` | String | Nome da campanha |
| `status` | String | `pending`, `scheduled`, `sending`, `paused`, `completed`, `cancelled` |
| `templateName` | String | Nome do template aprovado |
| `templateLanguage` | String | Idioma do template |
| `templateCategory` | String | Categoria do template |
| `templateComponents` | Json | Componentes do template (header, body, buttons) |
| `whatsappId` | Int | FK → Whatsapps (canal de envio) |
| `tenantId` | Int | FK → Tenants |
| `totalContacts` | Int | Total de contatos na campanha |
| `sentCount` | Int | Contatos enviados com sucesso |
| `failedCount` | Int | Contatos com falha |
| `start` | DateTime (NOT NULL) | Data/hora de início (agendamento ou execução) |
| `completedAt` | DateTime? | Data/hora de conclusão |
| `responseRouting` | Json? | Roteamento de respostas: `{type, queueId, aiAgentId, windowHours, autoTagId}` |

#### CampaignContacts
| Campo | Tipo | Descrição |
|-------|------|-----------|
| `id` | Serial PK | ID auto-incremento |
| `campaignId` | Int | FK → Campaigns |
| `contactId` | Int? | FK → Contacts (opcional) |
| `messageRandom` | String | Identificador único do envio |
| `messageId` | String? | Message ID retornado pela Meta (wamid) |
| `status` | String | `pending`, `sent`, `delivered`, `read`, `replied`, `failed` |
| `errorReason` | String? | Mensagem de erro se falhou |
| `variables` | Json? | Variáveis personalizadas do template |
| `ack` | Int | Acknowledgement level |

### Status Machine

```
pending/scheduled → Iniciar → sending
sending → Pausar → paused
sending → Cancelar → cancelled
sending → (todos enviados) → completed
paused → Retomar → sending
paused → Cancelar → cancelled
```

### Ações por Status

| Status | Ações Disponíveis |
|--------|-------------------|
| `pending` / `scheduled` | Iniciar, Editar, Duplicar |
| `sending` | Pausar, Cancelar |
| `paused` | Retomar, Cancelar |
| `completed` / `cancelled` | Duplicar, Exportar |

### Endpoints API

| Método | Rota | Descrição |
|--------|------|-----------|
| GET | `/api/campaigns` | Lista campanhas do tenant |
| GET | `/api/campaigns/:id` | Detalhes da campanha |
| POST | `/api/campaigns` | Cria campanha |
| PATCH | `/api/campaigns/:id` | Atualiza campanha (usa `$queryRawUnsafe` para UPDATE) |
| DELETE | `/api/campaigns/:id` | Remove campanha |
| POST | `/api/campaigns/:id/start` | Inicia disparo |
| POST | `/api/campaigns/:id/pause` | Pausa disparo |
| POST | `/api/campaigns/:id/resume` | Retoma disparo |
| POST | `/api/campaigns/:id/cancel` | Cancela disparo |
| GET | `/api/campaigns/:id/contacts` | Lista contatos paginados |
| POST | `/api/campaigns/:id/contacts` | Adiciona contatos (array JSON) |
| GET | `/api/campaigns/:id/export` | Exporta relatório CSV |

**IMPORTANTE — Route ordering:** Rotas específicas (`/start`, `/pause`, `/resume`, `/cancel`, `/contacts`, `/export`) devem ser registradas ANTES da rota genérica `/:id` para evitar que Express interprete "start" como um ID.

### Dashboard (campanhas.tsx)

- **Lista**: Cards com nome, status, progresso, botões de ação
- **Dashboard**: Navegação automática ao clicar "Iniciar", barra de progresso, lista de contatos paginada
- **WebSocket**: Evento `CAMPAIGN_PROGRESS` para progresso em tempo real durante envio. liveProgress é limpo 2s após campanha completar para não sobrescrever dados da API
- **Polling automático**: A tela atualiza automaticamente em TODOS os estados:
  - `sending`: 3s (detail) / 5s (contacts)
  - `scheduled`: 10s (detecta auto-start pelo scheduler)
  - `completed`/`cancelled`/`paused`: 15s (captura delivered/read/replied updates)
- **Contadores calculados em tempo real**: Os cards (Enviados, Entregues, Lidos) são calculados via `groupBy` nos status reais dos `CampaignContacts` (não via incrementos acumulados no campo da campanha). Lógica cumulativa:
  - `sentCount` = sent + delivered + read + replied
  - `deliveredCount` = delivered + read + replied
  - `readCount` = read + replied
  - `repliedCount` = replied apenas
  - `failedCount` = failed apenas
- **Status dos contatos**: `pending` → `sent` → `delivered` → `read` → `replied` (ou `failed`). Cada status tem badge colorido no dashboard
- **Filtro de contatos**: Dropdown com Pendentes, Enviados, Entregues, Lidos, Respondidos, Falharam
- **Aviso de horário comercial**: Quando campanha tem `respectBusinessHours=true` e está fora do horário, mostra card amarelo "Aguardando horário comercial"
- **Campanha agendada**: Botão "Antecipar Envio" (amber) com confirmação, card informativo azul com horário programado
- **Campos de tempo em segundos**: Os campos de throttle (pausa entre lotes, delay min/max) são exibidos em segundos na UI mas armazenados em milissegundos no backend

### Seleção de Canal (getConnection)

O `getConnection()` em `campaign.service.ts` seleciona o canal de envio na seguinte ordem de prioridade:
1. `channelRotation` (round-robin entre múltiplos canais)
2. `campaign.sessionId` (canal específico selecionado)
3. Canal com `isDefault: true` do tenant
4. **Fallback**: qualquer canal WABA conectado do tenant (`type: "waba", status: "CONNECTED"`)

### Rastreamento de Respostas (webhook)

Quando um contato responde a uma mensagem de campanha:
1. O webhook busca `CampaignContacts` com status `sent/delivered/read` do mesmo contato, dentro da `windowHours` (48h default)
2. Atualiza o status do contato para `replied` e incrementa `repliedCount`
3. Se `responseRouting` está configurado, aplica roteamento (fila/agente IA) e auto-tag
4. O rastreamento funciona independente de `responseRouting` estar configurado

### Status updates da Meta (webhook)

Quando a Meta envia status updates (`delivered`, `read`):
- Busca `CampaignContacts` pelo `messageId` com status anterior válido
- `delivered`: aceita contatos com status `sent`
- `read`: aceita contatos com status `sent`, `delivered` ou `replied` (caso resposta chegue antes do read)
- Se contato já tem status `replied`, o `readCount` é incrementado mas o status permanece `replied` (não rebaixa)

### IMPORTANTE — queryClient e IDs no path

O `queryClient` padrão do VoxZap trata `queryKey[1]` como **query params object** (não path segment). Para rotas com ID no path (`/api/campaigns/123`), SEMPRE usar `queryFn` explícita:

```typescript
useQuery({
  queryKey: ["/api/campaigns", campaignId],
  queryFn: () => fetch(`/api/campaigns/${campaignId}`).then(r => r.json()),
});
```

**NÃO usar** apenas `queryKey: ["/api/campaigns", campaignId]` sem `queryFn` — o fetcher padrão construirá a URL como `/api/campaigns?0=1&1=2&...` (errado).

### Rate Limit & Resiliência (Arquitetura em 3 Camadas)

Implementado em produção (Locktec, 2026-04) após operadores baterem em `429` por compartilharem IP NAT corporativo.

**Camadas:**
1. **Nginx (anti-DDoS de borda)** — `api_limit 500 r/s burst=1000` por IP. Rate em `/opt/tenants/nginx/conf.d/00-rate-limit.conf`, burst no `tenant_<id>.conf`. Login fica em `5 r/m burst=3`.
2. **Express por usuário** — `server/middleware/rate-limit.ts`, 60 req/s por `userId` (responde `429` com header `Retry-After`). Plugado dentro de `authenticateToken` e respeita `X-Tenant-Id` (override de superadmin). Skip em `/api/health`, `/api/login`, `/api/auth`, `/api/webhook`, `/api/socket.io`.
3. **Express por tenant** — mesmo middleware, 1000 req/s por `tenantId`. In-memory `Map`, fail-open (se o middleware quebra, libera).

**Frontend (`client/src/lib/queryClient.ts`):**
- `fetchWithRetry` respeita `Retry-After` e faz até 2 retries com jitter — **APENAS para GET/HEAD** (mutations seguem sem retry para preservar idempotência).
- Em `429` ou resposta HTML do nginx, mensagem humanizada em PT-BR (nada de HTML cru no toast).

**Frontend (`client/src/hooks/use-socket.ts`):**
- `scheduleInvalidatePrefix(prefix, 250ms)` e `scheduleInvalidateTicketMessages(ticketId, 200ms)` coalescem rajadas de `invalidateQueries` disparadas pelos handlers (`handleNewMessage`, `handleTicketUpdate`, `handleNewTicket`, `handleTicketTransfer`, `handleTicketMessage`).
- NUNCA chamar `queryClient.invalidateQueries({ predicate: key.startsWith('/api/tickets') })` direto dentro de handler de socket — usar os helpers, senão ressurge o problema de N refetchs por segundo.

**Variáveis de ambiente** (defaults em `rate-limit.ts`):
```
USER_RATE_LIMIT=60        USER_RATE_WINDOW_MS=1000
TENANT_RATE_LIMIT=1000    TENANT_RATE_WINDOW_MS=1000
```

### PATCH com $queryRawUnsafe

O campo `start` (DateTime NOT NULL) causa conflitos com Prisma `.update()`. O PATCH da campanha usa `$queryRawUnsafe` com SQL direto:

```typescript
await prisma.$queryRawUnsafe(`UPDATE "Campaigns" SET ... WHERE id = $1`, id);
```

### Contatos em Modo Edição

Contatos são **read-only** em modo edição. O upload de contatos só é permitido na criação da campanha. Na edição, os contatos existentes são exibidos mas não podem ser modificados.

---

## Integração VoxCall → WhatsApp

Sistema que monitora chamadas abandonadas no VoxCall (Asterisk) e envia automaticamente templates WhatsApp para retorno ao cliente.

### Arquitetura
- **Serviço**: `server/services/voxcall-integration.service.ts` — polling periódico no PostgreSQL externo do VoxCall
- **Tabela monitorada**: `retorno_clientes` (evento `ABANDON` do dia atual, excluindo números já atendidos/retornados)
- **Envio**: Usa `whatsappService.sendTemplateMessage()` com o canal WABA configurado
- **Deduplicação**: Tabela `VoxcallAbandonedLogs` com unique index em `(integrationId, callId)`
- **Roteamento de resposta**: `webhook.service.ts` verifica se contato tem log recente (24h) de envio VoxCall e aplica roteamento customizado (fila/operador/agente IA/chatflow)

### Endpoints API
| Método | Rota | Descrição |
|--------|------|-----------|
| GET | `/api/voxcall-integration` | Busca config do tenant |
| POST/PUT | `/api/voxcall-integration` | Salva/atualiza config |
| POST | `/api/voxcall-integration/toggle` | Liga/desliga integração |
| POST | `/api/voxcall-integration/test-connection` | Testa conexão com DB externo |
| POST | `/api/voxcall-integration/send-test` | Envio avulso de template para teste |
| GET | `/api/voxcall-integration/approved-templates/:channelId` | Lista templates aprovados do canal |
| GET | `/api/voxcall-integration/status` | Status operacional + estatísticas |
| GET | `/api/voxcall-integration/logs` | Logs de envio paginados |

### Modelos Prisma
- **VoxcallIntegrations** — config por tenant: credenciais DB (senha criptografada AES-256-CBC), canal WABA, template, intervalo de polling, filtro de filas, whitelist de telefones, roteamento de resposta (queueId/userId/aiAgentId/chatFlowId), lastCheckAt
- **VoxcallAbandonedLogs** — log de cada envio: callId, phoneNumber, queueName, status (sent/error), waMessageId, errorMessage

### Frontend
- Página: `client/src/pages/voxcall-integration.tsx` (rota `/voxcall-integration`)
- Sidebar: item "VoxCall" com ícone PhoneMissed, adminOnly
- Features: formulário de config, teste de conexão, seletor de templates aprovados, whitelist, envio avulso de teste, dashboard de status, logs de envio

---

## Configurações do Tenant (Empresa)

### Horário de Atendimento da Empresa
Configuração global de horário comercial do tenant, acessível em **Configurações** (primeira seção da página).

#### Hierarquia de Horários
1. **Fila** (`Queues.businessHours`) — se a fila tem horário próprio configurado, ele tem prioridade
2. **Tenant** (`Tenants.businessHours`) — fallback quando a fila não tem horário configurado
3. Se nenhum tem horário → atendimento 24h

#### Estrutura no Banco
```typescript
// Tenants table
businessHours: JSON | null  // null = 24h (desativado)
messageBusinessHours: string | null  // Mensagem automática fora do horário

// Formato do JSON (array de 7 dias):
[
  { day: 0, hr1: "08:00", hr2: "12:00", hr3: "14:00", hr4: "18:00", type: "C", label: "Domingo" },
  // type: "O" = aberto, "C" = fechado
  // hr1-hr2 = turno 1, hr3-hr4 = turno 2
]
```

#### API Endpoints
| Método | Rota | Descrição |
|--------|------|-----------|
| GET | `/api/tenant/business-hours` | Busca horário + mensagem do tenant |
| PUT | `/api/tenant/business-hours` | Salva horário + mensagem (admin only) |

#### Frontend
- Componente: `TenantBusinessHoursCard` em `client/src/pages/configuracoes.tsx`
- Toggle para ativar/desativar horário
- Configuração individual por dia da semana (dois turnos)
- Campo de mensagem automática para fora do horário

#### Verificação no Webhook
```
Mensagem recebida → isNewTicket?
  → businessHoursService.checkBusinessHours(ticket.queueId, tenantId)
    → Verifica fila primeiro (se tem businessHours)
    → Fallback para tenant (se fila não tem)
    → Se fora do horário → substitui variáveis ({{nome}}, {{numero}}, {{fila}}) → envia como auto-reply
    → NÃO bloqueia o bot (bot continua processando normalmente)
```

#### Substituição de Variáveis em Mensagens Automáticas
Todas as mensagens automáticas do webhook (fora do horário, greeting de tag routing) passam por substituição de variáveis antes do envio:
- `{{nome}}` → `contact.name`
- `{{numero}}` → `contact.number`
- `{{fila}}` → nome da fila atribuída ao ticket (quando aplicável)
- Substituição é case-insensitive (regex `/\{\{nome\}\}/gi`)
- Código em `webhook.service.ts`, no bloco `isNewTicket` (off-hours) e no bloco `tagRoutedGreeting`

### Configurações de Resiliência do Bot
Armazenadas via `getTenantSettings()` / `PUT /api/settings/:key` na tabela `Settings`.

#### Settings Keys e Defaults
| Key | Tipo | Default | Descrição |
|-----|------|---------|-----------|
| `fallbackQueueId` | string (ID) | `""` (nenhuma) | Fila fallback quando bot não consegue transferir |
| `botFailureMessage` | string | `"Desculpe, estou com dificuldades técnicas..."` | Mensagem enviada ao cliente quando LLM falha |
| `closedQueueBehavior` | `"keep_bot"` \| `"send_anyway"` \| `"use_fallback"` | `"keep_bot"` | Comportamento quando fila-alvo está fechada |
| `loopDetectionThreshold` | string (número) | `"3"` | Número de transferências repetidas antes de detectar loop |
| `staleTicketAlertEnabled` | `"enabled"` \| `"disabled"` | `"disabled"` | Ativa alerta de ticket parado (sem resposta humana) |
| `staleTicketAlertMinutes` | string (número) | `"30"` | Minutos sem resposta para disparar alerta |
| `reactivateBotOnReopen` | `"enabled"` \| `"disabled"` | `"enabled"` (default implícito) | Se bot deve reativar para contatos que já tiveram tickets anteriores |
| `maxOffHoursMessages` | string (número) | `"0"` (ilimitado) | Limite de mensagens fora do horário por contato/dia |

#### IMPORTANTE: Default do reactivateBotOnReopen
Quando `reactivateBotOnReopen` não está salvo no banco (vazio), o sistema trata como `"enabled"` — ou seja, **o bot é ativado por padrão** para todos os novos tickets, mesmo de contatos recorrentes. O código usa:
```typescript
const reactivateSetting = walletSettings.reactivateBotOnReopen || "enabled";
```

#### Frontend
- Página: `client/src/pages/configuracoes.tsx`
- Seção "Bot & Automação" com 6 cards de configuração
- Seção "Horário de Atendimento da Empresa" como primeiro card da página

#### Arquivos-Chave
| Arquivo | Responsabilidade |
|---------|-----------------|
| `server/lib/tenant-settings.ts` | `getTenantSettings()` — lê settings do banco com cache |
| `server/services/webhook.service.ts` | Usa `reactivateBotOnReopen` na criação de tickets (linha ~996) |
| `server/services/ai-agent.service.ts` | Usa `closedQueueBehavior`, `fallbackQueueId`, `botFailureMessage`, `loopDetectionThreshold` |
| `server/services/business-hours.service.ts` | `checkBusinessHours()` — verifica fila → fallback tenant |
| `client/src/pages/configuracoes.tsx` | UI de todas as configurações + `TenantBusinessHoursCard` |
