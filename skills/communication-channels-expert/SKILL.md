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
| WebChat | Texto simples | Sem rendering especial |

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
