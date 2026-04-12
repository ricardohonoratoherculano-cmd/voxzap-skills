---
name: communication-channels-expert
description: Especialista em canais de comunicação omnichannel do VoxZap. Use quando precisar criar, modificar, debugar ou estender qualquer canal de comunicação (WhatsApp WABA, Telegram, Instagram, Messenger, WebChat, Email, Baileys, UazAPI), incluindo gestão de conexões, envio/recebimento de mensagens, webhooks, polling, status, UI de canais (canais.tsx), e roteamento unificado via whatsapp.service.ts. Inclui arquitetura completa, tabela Whatsapps, fluxos de conexão/desconexão, mapeamento de tipos, e padrões de código.
---

# Especialista em Canais de Comunicação - VoxZap

Skill para desenvolvimento e manutenção de todos os canais de comunicação do projeto VoxZap — sistema multi-tenant omnichannel.

## Quando Usar

- Criar um novo tipo de canal de comunicação
- Modificar a lógica de conexão/desconexão de canais existentes
- Adicionar funcionalidades cross-channel (envio, recebimento, status)
- Debugar problemas de conectividade, webhooks ou polling de qualquer canal
- Modificar a UI de gestão de canais (`canais.tsx`)
- Alterar o roteamento de mensagens no `whatsapp.service.ts`
- Trabalhar com a tabela `Whatsapps` (configuração de qualquer canal)
- Implementar novos tipos de mensagem ou mídia em canais existentes

## Tipos de Canal Suportados

| Tipo | Label | Cor Badge | Serviço Backend | Recebimento |
|------|-------|-----------|-----------------|-------------|
| `waba` | WhatsApp Business | Verde | `whatsapp.service.ts` | Webhook Meta |
| `baileys` | WhatsApp Web | Verde-claro | `whatsapp.service.ts` | WebSocket Baileys |
| `telegram` | Telegram | Azul | `telegram via routes.ts` | Webhook Telegram |
| `instagram` | Instagram | Rosa | `instagram.service.ts` | Webhook Meta |
| `messenger` | Messenger | Azul | `messenger.service.ts` | Webhook Meta |
| `webchat` | WebChat | Roxo | `socket.ts` (namespace /webchat) | Socket.io |
| `email` | E-mail | Amber | `email.service.ts` | IMAP Polling |
| `uazapi` | UazAPI | Cinza | `whatsapp.service.ts` | Webhook UazAPI |

## Arquitetura Geral

```
┌─────────────────────────────────────────────────────────────┐
│                     FRONTEND (React/Vite)                    │
│  client/src/pages/canais.tsx       ←  Gestão de Conexões     │
│  client/src/pages/atendimento.tsx  ←  Chat + Renderização    │
└────────────┬──────────────────────────────┬──────────────────┘
             │ REST API                     │ Socket.io
             ▼                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     BACKEND (Express/TypeScript)              │
│  server/routes.ts              ←  Rotas REST + Webhooks      │
│  server/services/              ←  Lógica por canal           │
│  server/websocket/socket.ts    ←  WebSocket / Socket.io      │
│  server/lib/email-crypto.ts    ←  Criptografia de senhas     │
└────────────┬──────────────────────────────┬──────────────────┘
             │ Prisma ORM                   │ APIs Externas
             ▼                              ▼
┌──────────────────┐     ┌──────────────────────────────────────┐
│   PostgreSQL     │     │  Meta Graph API / Telegram Bot API   │
│   (Externo)      │     │  SMTP/IMAP / Socket.io WebChat       │
└──────────────────┘     └──────────────────────────────────────┘
```

## Arquivos-Chave

| Arquivo | Responsabilidade |
|---------|-----------------|
| `server/routes.ts` | Rotas REST, webhook endpoints, CRUD de conexões |
| `server/services/whatsapp.service.ts` | Factory de envio (roteia por `connection.type`), upload/download mídia Meta |
| `server/services/webhook.service.ts` | Processamento de webhooks inbound (WhatsApp, Instagram, Messenger) |
| `server/services/instagram.service.ts` | Envio/recebimento Instagram DM, OAuth, token refresh |
| `server/services/messenger.service.ts` | Envio/recebimento Messenger, subscription, OAuth |
| `server/services/email.service.ts` | SMTP envio, IMAP polling, parsing de e-mail, criptografia |
| `server/lib/email-crypto.ts` | AES-256-CBC para senhas SMTP/IMAP |
| `server/websocket/socket.ts` | Socket.io: rooms, broadcast, namespace /webchat |
| `client/src/pages/canais.tsx` | UI completa de gestão de canais (criar, editar, conectar, desconectar) |
| `client/src/pages/atendimento.tsx` | Renderização de mensagens de todos os canais no chat |
| `prisma/schema.prisma` | Tabela Whatsapps e modelos relacionados |

## Tabela Whatsapps (Configuração Unificada)

Todos os canais compartilham a mesma tabela `Whatsapps`. Campos usados variam por tipo:

### Campos Comuns (todos os canais)

| Campo | Tipo | Uso |
|-------|------|-----|
| `id` | Int (PK) | ID da conexão |
| `name` | String | Nome exibido na UI |
| `type` | String | Tipo do canal: `waba`, `telegram`, `instagram`, `messenger`, `webchat`, `email`, `baileys`, `uazapi` |
| `status` | String | `CONNECTED`, `DISCONNECTED`, `OPENING` |
| `isActive` | Boolean | Canal ativo/inativo |
| `isDeleted` | Boolean | Soft delete |
| `tenantId` | Int | Tenant proprietário |
| `queueId` | Int? | Fila padrão para tickets novos |
| `chatFlowId` | Int? | Chatflow automático |
| `aiAgentId` | Int? | Agente IA vinculado |
| `farewellMessage` | String? | Mensagem de encerramento |

### Campos por Canal

**WABA (WhatsApp Business API):**
| Campo | Uso |
|-------|-----|
| `tokenAPI` | Phone Number ID |
| `bmToken` | Meta Access Token (Bearer) |
| `wabaId` | WABA Account ID |
| `wabaVersion` | Versão da Graph API (ex: `v22.0`) |
| `webhookChecked` | Verify token do webhook |
| `number` | Número de telefone |

**Telegram:**
| Campo | Uso |
|-------|-----|
| `tokenTelegram` | Bot Father API Token |
| `wabaId` | Username do bot (ex: `meu_bot`) |

**Instagram:**
| Campo | Uso |
|-------|-----|
| `tokenAPI` | Page ID ou Instagram Business ID |
| `bmToken` | Meta Access Token |
| `instagramPK` | Instagram Profile PK (identificador interno) |

**Messenger:**
| Campo | Uso |
|-------|-----|
| `tokenAPI` | Page ID |
| `bmToken` | Page Access Token |
| `number` | Nome da página |

**WebChat:**
| Campo | Uso |
|-------|-----|
| `tokenHook` | Session token único para handshake |
| `fbObject` | JSON com config UI (cor, posição, welcome, título) |

**Email:**
| Campo | Uso |
|-------|-----|
| `smtpConfig` | JSON criptografado: hosts, portas, users, senhas SMTP/IMAP |
| `tokenAPI` | Email do remetente (smtpUser) |
| `number` | Email do remetente |

## Fluxo de Envio de Mensagens (Factory Pattern)

O `whatsapp.service.ts` usa um factory pattern no método `sendMessage`:

```typescript
async sendMessage(connection, ticketId, to, body) {
  switch (connection.type) {
    case "waba":
      return this.sendWabaMessage(connection, to, body);
    case "telegram":
      return this.sendTelegramMessage(connection, to, body);
    case "instagram":
      return this.sendInstagramMessage(connection, ticketId, body);
    case "messenger":
      return this.sendMessengerMessage(connection, ticketId, body);
    case "email":
      return this.sendEmailMessage(connection, ticketId, to, body);
    default:
      return { success: true, messageId: `local_${Date.now()}` };
  }
}
```

O mesmo padrão aplica-se a `sendMediaMessage` para envio de mídia.

## Fluxo de Recebimento de Mensagens

### Via Webhook (WABA, Instagram, Messenger, Telegram)

```
API Externa → POST /api/webhook/{tipo} → WebhookService
  → Identificar tenant/conexão pelo token no payload
  → Extrair conteúdo (texto, mídia, localização, etc.)
  → Find/Create Contact
  → Find/Create Ticket (status: pending/open)
  → Salvar Message no banco
  → Broadcast via Socket.io (rooms: tenant, ticket, user)
```

### Via Polling (Email)

```
EmailService.startImapPolling(connectionId)
  → setInterval → pollImap()
    → Conectar IMAP → Buscar e-mails não lidos
    → Para cada e-mail:
      → Parse com mailparser
      → Detectar duplicatas por emailMessageId
      → Find/Create Contact (por email)
      → Find/Create Ticket
      → Salvar attachments em /uploads
      → Salvar Message (body: [EMAIL] subject\n\nbody)
      → Sanitizar HTML server-side (DOMPurify+JSDOM)
      → Broadcast via Socket.io
```

### Via Socket.io (WebChat)

```
Cliente Widget → socket.emit('webchat:message')
  → Namespace /webchat → Handler
    → Find/Create Contact → Find/Create Ticket → Save Message
    → Broadcast para rooms do tenant/ticket
```

## Fluxo de Conexão/Desconexão

### Conectar Canal

1. **UI**: Formulário em `canais.tsx` com campos específicos por tipo
2. **API**: `POST /api/whatsapps` (criação) ou endpoint específico (ex: `/api/email/connect`)
3. **Validação**: Teste de credenciais antes de salvar (ex: Meta token, SMTP+IMAP, Telegram getMe)
4. **Persistência**: Salvar na tabela `Whatsapps` com `status: "CONNECTED"`
5. **Ativação**: Iniciar polling (email), registrar webhook (telegram), etc.

### Desconectar Canal

1. **UI**: Botão "Desconectar" no card do canal
2. **API**: `DELETE /api/whatsapps/:id` ou `POST /api/{tipo}/disconnect`
3. **Ação**: Soft delete (`isDeleted: true`) ou `status: "DISCONNECTED"`
4. **Cleanup**: Parar polling, remover webhook, etc.

## UI de Canais (canais.tsx)

### typeConfig — Definição de Tipos

```typescript
const typeConfig: Record<string, { label: string; color: string }> = {
  waba:      { label: "WhatsApp Business", color: "bg-green-100 text-green-700..." },
  baileys:   { label: "WhatsApp Web",      color: "bg-emerald-100..." },
  telegram:  { label: "Telegram",          color: "bg-blue-100..." },
  instagram: { label: "Instagram",         color: "bg-pink-100..." },
  messenger: { label: "Messenger",         color: "bg-sky-100..." },
  webchat:   { label: "WebChat",           color: "bg-purple-100..." },
  email:     { label: "E-mail",            color: "bg-amber-100..." },
};
```

### Estrutura do Card de Canal

Cada canal renderiza:
- Ícone do canal (lucide-react ou react-icons)
- Badge com tipo e cor
- Informações específicas (email, phone, bot username, etc.)
- Status indicator (verde/vermelho)
- Botões de ação (editar, desconectar, reconectar)
- Info panel com detalhes técnicos (Token, WABA ID, SMTP status, etc.)

### Formulário de Criação/Edição

O `formData` useState contém todos os campos de todos os canais. Campos email:
```
smtpHost, smtpPort, smtpUser, smtpPass, smtpSecure,
imapHost, imapPort, imapUser, imapPass, imapSecure,
pollingInterval, fromName
```

Campos webchat:
```
webchatColor, webchatPosition, webchatTitle, webchatSubtitle
```

## WebChat — Arquitetura Completa

### Arquivos Principais
| Arquivo | Função |
|---------|--------|
| `server/public-webchat/widget.js` | Widget embeddable (JS puro, ~1700 linhas). Renderiza chat, mídia, upload, avaliação, sessão, Socket.io |
| `server/services/webchat.service.ts` | Sessões, tickets, contatos, cooldown, integração AI Agent |
| `server/websocket/socket.ts` | Namespace `/webchat` — handshake, mensagens, avaliação, AI Agent processing |
| `server/routes.ts` | REST API webchat, fechamento de ticket (farewell + avaliação), ghost cleanup |

### Fluxo de Sessão WebChat
1. Widget carrega → conecta Socket.io `/webchat` com `channelToken`
2. `init_session` → backend cria/encontra contato + ticket (com `lastCallChatbot: true` se AI Agent configurado)
3. `session_ready` → widget mostra chat (ou pre-chat form se configurado)
4. Mensagens trocadas via `visitor_message` / `operator_message`
5. Operador fecha ticket → farewell + avaliação (se ativa) + `webchat:ticket_closed`

### Integração com AI Agent
O WebChat segue o **mesmo fluxo** dos outros canais para AI Agent:
- Se o canal (`Whatsapps`) tem `aiAgentId` configurado, o ticket é criado com `lastCallChatbot: true`
- Após salvar mensagem do visitante, `handleWebchatAiAgent()` em `socket.ts`:
  - Verifica `connection.aiAgentId`, ticket `pending`, `lastCallChatbot`
  - Valida agente ativo com API key
  - Detecção de loop (mesma mensagem repetida N vezes)
  - Usa `messageProcessingQueue` + `processMessageWithAgent()`
  - Salva resposta do bot como mensagem, emite `operator_message` ao visitante
  - Broadcast `NEW_MESSAGE` para operadores
  - Trata transferência para fila humana e cenários de fallback
- Resposta da IA chega ao widget via evento `operator_message` (mesmo canal que mensagens de operador humano)

### Ghost Ticket Prevention
Tickets fantasma (vazios, sem mensagens) eram criados quando o widget reconectava após fechamento:
- **Cooldown guard** em `webchat.service.ts`: `initSession()` verifica se último ticket webchat foi fechado nos últimos 5 min; retorna `sessionEnded: true` em vez de criar ticket novo
- **forceNew flag**: Quando visitante clica "Iniciar nova conversa", envia `forceNew: true` que pula o cooldown
- **Ghost cleanup job**: A cada 30 min, fecha tickets webchat com status `pending`, sem mensagens (`lastMessage: null`), >5 min de idade
- **Socket handler**: Quando `sessionEnded`, seta `ticketId = null`, emite `session_ready` + `webchat:ticket_closed`, não faz broadcast `NEW_TICKET`
- **Widget state**: `sessionEnded` persistido em localStorage; `sendMessage` bloqueado; `visitor_message` no server rejeitado quando `!socket.data.ticketId`

### Fluxo de Fechamento de Ticket
Quando operador fecha ticket webchat (PATCH `/api/tickets/:id`):
1. Status atualizado para `closed` no banco
2. `broadcastTicketUpdate` para painel do operador
3. **Mensagem de despedida** (`farewellMessage`) enviada via `whatsappService.sendMessage` → `emitToWebchatSession` `operator_message`
4. **Avaliação** (se `sendEvaluation === "enabled"`):
   - Mensagem de avaliação enviada como `operator_message`
   - 1.5s depois: `webchat:awaiting_evaluation` emitido com `options` (rating configurado no tenant)
   - Widget mostra UI de avaliação com **botões estrela** interativos + "Pular avaliação"
   - Visitante clica estrela → `webchat:submit_evaluation` → server salva em `TicketEvaluations` → mensagem de agradecimento → 2s depois `webchat:ticket_closed`
   - Timeout de 60s: se visitante não avaliar, `webchat:ticket_closed` emitido automaticamente
5. **Sem avaliação**: `webchat:ticket_closed` emitido após 1.5s
6. Widget: substitui input por footer "Atendimento encerrado" + botão "Iniciar nova conversa" (mantém mensagens visíveis)

### Eventos Socket.io WebChat
| Evento | Direção | Payload | Descrição |
|--------|---------|---------|-----------|
| `init_session` | Client→Server | `{ sessionId?, visitorName?, visitorEmail?, forceNew? }` | Inicia/retoma sessão |
| `session_ready` | Server→Client | `{ sessionId, ticketId }` | Sessão pronta |
| `visitor_message` | Client→Server | `{ body }` | Mensagem do visitante |
| `operator_message` | Server→Client | `{ id, body, fromMe, createdAt }` | Mensagem do operador/bot |
| `message_ack` | Server→Client | `{ messageId }` | Confirmação de recebimento |
| `webchat_config` | Server→Client | `{ color, title, ... }` | Configuração visual do widget |
| `webchat:ticket_closed` | Server→Client | `{ reason }` | Ticket encerrado |
| `webchat:awaiting_evaluation` | Server→Client | `{ ticketId, userId, options[] }` | Solicita avaliação |
| `webchat:submit_evaluation` | Client→Server | `{ ticketId, rating, userId }` | Envia nota |

### Tipos de Mídia WebChat
| Tipo | Body Pattern | mediaUrl | dataJson |
|------|-------------|----------|----------|
| Imagem | `[IMAGE] url` | URL do arquivo | `{ fileName, fileSize, mimeType }` |
| Áudio | `[AUDIO] url` | URL do arquivo (.webm) | `{ fileName, fileSize, mimeType: "audio/webm" }` |
| Documento | `[DOCUMENT] url` | URL do arquivo | `{ fileName, fileSize, mimeType }` |

### Upload Flow
1. Widget: input `file` ou `MediaRecorder` (webm/opus) → valida client-side (10MB, tipos permitidos)
2. `socket.emit('webchat:message', { type: 'media', file: base64, ...metadata })`
3. Backend: `webchat.service.ts` salva arquivo em disco, cria mensagem com `mediaType: "document"|"image"|"audio"`, `mediaUrl`, `dataJson`
4. `socket.emit` broadcast para operador + visitor

### Widget Rendering (JS Puro)
- **Imagens**: `<img>` com click-to-open, sem filename redundante
- **Áudio**: Custom player (`new Audio()`) com botão play/pause, barra de progresso clicável, tempo atual/total
- **Documentos**: Card com ícone SVG, badge de extensão (PDF/DOCX/etc), nome, tamanho, botão download
- **Bolhas**: Visitante = fundo escuro `#1a1a2e`, texto `#f0f2f5` | Operador = fundo `#f0f2f5`, texto `#1a1a2e`
- **Dark mode**: CSS via `@media(prefers-color-scheme:dark)` com estilos específicos para todos componentes
- **Avaliação**: Estrelas interativas com hover highlight, "Pular avaliação", dark mode completo

### Widget State Machine
```
INIT → PRE_CHAT (se formulário configurado) → CHAT_ACTIVE → AWAITING_EVALUATION (se ativo) → SESSION_ENDED
                                                    ↓                                              ↓
                                              TICKET_CLOSED (sem avaliação)              INICIAR_NOVA_CONVERSA
                                                    ↓                                              ↓
                                              SESSION_ENDED ────────────────────────────→ INIT (forceNew)
```
States persistidos em `localStorage`: `sessionId`, `sessionEnded`, `preChatCompleted`, `visitorName`, `visitorEmail`

### Painel do Operador (atendimento.tsx)
- `renderMedia()` normaliza `"file"` → `"document"` para compatibilidade
- `AudioPlayer` componente React customizado: play/pause, progress bar seek, velocidade (1x/1.5x/2x), download MP3 via `/api/download/audio/:filename`
- Imagens e documentos renderizados inline com thumbnails e download links

### Endpoint de Download de Áudio
```
GET /api/download/audio/:filename
```
Converte `.webm` → `.mp3` via ffmpeg (`/usr/bin/ffmpeg` no container). Requer autenticação.

## Normalização de Telefone para Todos os Canais

Todos os canais que recebem números de telefone (WABA, Baileys, UazAPI, Telegram) utilizam o módulo centralizado `server/lib/phone-utils.ts`:

| Função | Uso |
|--------|-----|
| `normalizeBrazilianPhone()` | Adiciona DDI `55` e nono dígito se necessário |
| `getAlternatePhoneNumber()` | Gera variante com/sem nono dígito para retry |
| `buildPhoneSearchNumbers()` | Gera TODAS as variantes para busca anti-duplicação (com/sem DDI, com/sem 9º dígito) |
| `validateBrazilianPhone()` | Validação completa com DDD check |

**`buildPhoneSearchNumbers()`** é essencial para evitar tickets duplicados: gera variantes sem DDI `55` para encontrar contatos migrados de sistemas legados (ex: Locktec/ZPro) que podem estar armazenados sem o prefixo internacional.

O endpoint `POST /api/new-conversation` auto-normaliza o número do contato existente quando selecionado via `contactId`, corrigindo progressivamente contatos legados.

## Padrões para Adicionar Novo Canal

1. **Schema**: Identificar campos necessários na tabela `Whatsapps` (ou adicionar novo campo JSON)
2. **Service**: Criar `server/services/novo-canal.service.ts` com métodos: `sendMessage`, `testConnection`, polling/webhook handler
3. **Routes**: Adicionar rotas em `server/routes.ts` (connect, disconnect, webhook, status)
4. **Factory**: Adicionar case no `sendMessage` e `sendMediaMessage` do `whatsapp.service.ts`
5. **Webhook**: Registrar handler ou iniciar polling no boot
6. **Frontend**: Adicionar tipo em `typeConfig`, formulário específico, card info panel
7. **Renderização**: Se mensagens têm formato especial, adicionar handler em `atendimento.tsx`
8. **Segurança**: Rotas admin-only, criptografia de credenciais, tenant isolation

## Renderização de Mensagens por Canal (atendimento.tsx)

| Canal | Prefixo Body | Rendering Especial |
|-------|-------------|-------------------|
| WABA | `[IMAGE]`, `[VIDEO]`, `[AUDIO]`, `[DOCUMENT]`, `[STICKER]`, `[TEMPLATE]`, `[INTERACTIVE]` | Componentes de mídia, player de áudio, cards de localização/contato |
| Telegram | Mesmo padrão WABA | Mesmo rendering |
| Instagram | Mesmo padrão | Badge rosa no ticket list |
| Messenger | Mesmo padrão | Badge azul no ticket list |
| Email | `[EMAIL] subject\n\nbody` | Header com assunto + Mail icon, HTML sanitizado, anexos com Paperclip links |
| WebChat | `[IMAGE]`, `[AUDIO]`, `[DOCUMENT]` | Rich media: custom audio player (play/pause, progress bar, seek, speed control, MP3 download via ffmpeg), file card com badge de extensão (PDF/DOCX etc), imagem expandível. Widget.js renderiza mídia com JS puro (custom `new Audio()` player, sem `<audio>` nativo). Upload via Socket.io com validação client-side (10MB, tipos permitidos). Bolhas: visitante = fundo escuro (#1a1a2e), operador = fundo claro (#f0f2f5). Arquivos servidos de `server/public-webchat/`. `dataJson` armazena `fileName`, `fileSize`, `mimeType`. Download de áudio como MP3 via endpoint `/api/download/audio/:filename` (ffmpeg webm→mp3). |

## Controle de Acesso

- **Criar/Editar/Excluir canais**: Restrito a `admin` e `superadmin`
- **Enviar mensagens**: Qualquer operador com acesso ao ticket
- **Webhooks**: Públicos (validados por verify token)
- **Status/Config**: Autenticado + tenant isolation

## Skills Relacionadas

- `whatsapp-messaging-expert` — Detalhes profundos de mensageria WhatsApp
- `whatsapp-calling-expert` — Chamadas de voz via WhatsApp
- `meta-channels-expert` — Instagram, Messenger, OAuth Meta
- `voxfone-telephony-crm` — Canal de telefonia VoIP/SIP
