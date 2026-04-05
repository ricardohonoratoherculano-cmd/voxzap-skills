---
name: meta-channels-expert
description: Especialista em canais Meta (WhatsApp WABA, Instagram, Messenger) do VoxZap. Use quando precisar criar, modificar ou debugar funcionalidades relacionadas à Meta Graph API, OAuth Meta Business Login, Instagram Direct, Facebook Messenger, webhooks Meta, tokens de acesso, WABA templates, upload/download de mídia, janela de 24h, Phone Number ID, Page ID, Instagram Business Login, refresh de tokens, ou qualquer integração com graph.facebook.com e graph.instagram.com. Inclui referência completa de endpoints, fluxos OAuth, webhook events, tratamento de erros, e padrões de código.
---

# Especialista Canais Meta - VoxZap

Skill para desenvolvimento e manutenção de todos os canais Meta (WhatsApp Business API, Instagram Direct, Facebook Messenger) do projeto VoxZap.

## Quando Usar

- Configurar ou debugar conexões WhatsApp Business API (WABA)
- Implementar ou modificar fluxo OAuth para Instagram ou Messenger
- Processar webhooks da Meta (mensagens, status, entregas)
- Gerenciar templates HSM (criar, editar, sincronizar)
- Upload/download de mídia via Meta Graph API
- Refresh de tokens de acesso (long-lived tokens)
- Debugar erros Meta (códigos de erro, janela de 24h, rate limits)
- Configurar verificação de webhook (Hub Challenge)
- Trabalhar com Instagram Business Login vs Page-scoped API
- Vincular páginas Facebook ou contas Instagram

## Canais Meta no VoxZap

| Canal | Tipo DB | API Base | Identificador Principal |
|-------|---------|----------|------------------------|
| WhatsApp Business | `waba` | `graph.facebook.com/{version}/{phoneNumberId}` | Phone Number ID |
| Instagram Direct | `instagram` | `graph.facebook.com/{version}` ou `graph.instagram.com` | Page ID / IG Business ID |
| Messenger | `messenger` | `graph.facebook.com/{version}/{pageId}` | Page ID |

## Arquivos-Chave

| Arquivo | Responsabilidade |
|---------|-----------------|
| `server/services/whatsapp.service.ts` | Envio WABA (texto, template, mídia, interativos), upload/download mídia, fetch templates |
| `server/services/webhook.service.ts` | Processamento de webhooks: mensagens recebidas, status de entrega, reações |
| `server/services/instagram.service.ts` | Instagram DM: envio texto/mídia, OAuth, token refresh, Page vs OAuth mode |
| `server/services/messenger.service.ts` | Messenger: envio texto/mídia, OAuth, page subscription, token refresh |
| `server/routes.ts` | Endpoints de webhook, OAuth callbacks, CRUD de conexões |
| `client/src/pages/canais.tsx` | UI de conexão: formulários WABA/IG/Messenger, OAuth buttons |

## Configuração de Conexão por Canal

### WABA (WhatsApp Business API)

Campos na tabela `Whatsapps`:

| Campo | Valor | Uso |
|-------|-------|-----|
| `type` | `"waba"` | Identificador do canal |
| `tokenAPI` | Phone Number ID | ID do número na URL da API |
| `bmToken` | Access Token | Bearer token para autenticação |
| `wabaId` | WABA ID | ID da conta Business para templates |
| `wabaVersion` | `"v22.0"` | Versão da Graph API |
| `webhookChecked` | Verify Token | Token para verificação de webhook |
| `number` | Número telefone | Número formatado para exibição |

### Instagram Direct

| Campo | Valor | Uso |
|-------|-------|-----|
| `type` | `"instagram"` | Identificador do canal |
| `tokenAPI` | Page ID ou IG Business ID | ID para URLs da API |
| `bmToken` | Access Token | Token de acesso (page ou OAuth) |
| `instagramPK` | String | Instagram Profile PK (identificador de sender) |
| `fbObject` | JSON | Metadados da página/conta |

### Messenger

| Campo | Valor | Uso |
|-------|-------|-----|
| `type` | `"messenger"` | Identificador do canal |
| `tokenAPI` | Page ID | ID da página Facebook |
| `bmToken` | Page Access Token | Token da página |
| `number` | Nome da página | Nome para exibição |

## Meta Graph API — Referência

### Headers Padrão (todos os canais)

```typescript
headers: {
  "Authorization": `Bearer ${bmToken}`,
  "Content-Type": "application/json"
}
```

### Construção de URLs

```typescript
// WABA - Mensagens
`https://graph.facebook.com/${wabaVersion}/${tokenAPI}/messages`

// WABA - Templates
`https://graph.facebook.com/${wabaVersion}/${wabaId}/message_templates`

// WABA - Mídia (upload)
`https://graph.facebook.com/${wabaVersion}/${tokenAPI}/media`

// WABA - Mídia (download URL)
`https://graph.facebook.com/${wabaVersion}/${mediaId}`

// Instagram (Page-scoped)
`https://graph.facebook.com/${version}/${pageId}/messages`

// Instagram (OAuth/Business Login)
`https://graph.instagram.com/${version}/${igBusinessId}/messages`

// Messenger
`https://graph.facebook.com/${version}/${pageId}/messages`
```

### Teste de Conexão WABA

```typescript
const res = await fetch(`https://graph.facebook.com/${version}/${phoneNumberId}`, {
  headers: { Authorization: `Bearer ${token}` }
});
// 200 OK = token válido; 401/400 = token expirado/inválido
```

## Webhooks Meta

### Endpoints

| Canal | GET (Verificação) | POST (Eventos) |
|-------|-------------------|----------------|
| WABA | `GET /api/webhook/whatsapp` | `POST /api/webhook/whatsapp` |
| Instagram | `GET /api/webhook/instagram` | `POST /api/webhook/instagram` |
| Messenger | `GET /api/webhook/messenger` | `POST /api/webhook/messenger` |

### Verificação (Hub Challenge)

```typescript
app.get("/api/webhook/{tipo}", (req, res) => {
  const mode = req.query["hub.mode"];
  const token = req.query["hub.verify_token"];
  const challenge = req.query["hub.challenge"];

  if (mode === "subscribe" && token === VERIFY_TOKEN) {
    return res.status(200).send(challenge);
  }
  return res.status(403).send("Forbidden");
});
```

O `VERIFY_TOKEN` é armazenado no campo `webhookChecked` da tabela `Tenants`.

### Payload de Webhook — Estrutura

**WABA (object: `whatsapp_business_account`):**
```json
{
  "object": "whatsapp_business_account",
  "entry": [{
    "id": "WABA_ID",
    "changes": [{
      "field": "messages",
      "value": {
        "messaging_product": "whatsapp",
        "metadata": { "phone_number_id": "PHONE_ID" },
        "contacts": [{ "profile": { "name": "..." }, "wa_id": "55..." }],
        "messages": [{ "id": "wamid.xxx", "type": "text", "text": { "body": "..." } }],
        "statuses": [{ "id": "wamid.xxx", "status": "delivered", "timestamp": "..." }]
      }
    }]
  }]
}
```

**Instagram (object: `instagram`):**
```json
{
  "object": "instagram",
  "entry": [{
    "id": "PAGE_OR_IG_ID",
    "messaging": [{
      "sender": { "id": "SENDER_ID" },
      "recipient": { "id": "PAGE_ID" },
      "message": { "mid": "m_xxx", "text": "..." }
    }]
  }]
}
```

**Messenger (object: `page`):**
```json
{
  "object": "page",
  "entry": [{
    "id": "PAGE_ID",
    "messaging": [{
      "sender": { "id": "PSID" },
      "recipient": { "id": "PAGE_ID" },
      "message": { "mid": "m_xxx", "text": "..." }
    }]
  }]
}
```

### Processamento de Webhook (webhook.service.ts)

O `WebhookService` processa cada tipo:

1. **Identificar tenant**: Via `phoneNumberId` (WABA), `pageId` (IG/Messenger)
2. **Extrair conteúdo**: `extractMessageContent(msg)` retorna `{ body, mediaType, dataJson }`
3. **Identificar contato**: Por `wa_id` (WABA), `instagramPK` (IG), `messengerId` (Messenger)
4. **Find/Create Contact**: Busca por número/PK, cria se não existe
5. **Find/Create Ticket**: Busca ticket aberto, cria com status `pending` se não existe
6. **Salvar Message**: Persiste no banco com `fromMe: false`
7. **Broadcast**: Socket.io para rooms do tenant, ticket e usuários atribuídos

### Status de Entrega (WABA)

```typescript
// Valores de status recebidos via webhook:
"sent"      → ack: 1
"delivered" → ack: 2
"read"      → ack: 3
"failed"    → ack: -1 (com error code/title)
```

## OAuth Flows

### Instagram OAuth

```
1. GET /api/instagram/auth?tenantId=X
   → Redireciona para Meta Login:
     https://www.facebook.com/v22.0/dialog/oauth
     ?client_id=APP_ID
     &redirect_uri=CALLBACK_URL
     &scope=instagram_basic,instagram_manage_messages,pages_manage_metadata
     &state=tenantId

2. GET /api/instagram/callback?code=XXX&state=tenantId
   → Troca code por short-lived token
   → Troca short-lived por long-lived token (60 dias)
   → Lista páginas do usuário
   → Obtém Instagram Business Account vinculada
   → Salva na tabela Whatsapps
```

**Endpoints de Token:**
```typescript
// Short-lived → Long-lived
`https://graph.facebook.com/v22.0/oauth/access_token
  ?grant_type=fb_exchange_token
  &client_id=${APP_ID}
  &client_secret=${APP_SECRET}
  &fb_exchange_token=${shortLivedToken}`

// Refresh long-lived (antes de expirar)
`https://graph.facebook.com/v22.0/oauth/access_token
  ?grant_type=fb_exchange_token
  &client_id=${APP_ID}
  &client_secret=${APP_SECRET}
  &fb_exchange_token=${currentToken}`
```

### Messenger OAuth

```
1. GET /api/messenger/auth?tenantId=X
   → Redireciona para Meta Login com scope:
     pages_messaging, pages_manage_metadata, pages_read_engagement

2. GET /api/messenger/callback?code=XXX&state=tenantId
   → Troca code por token
   → Lista páginas do usuário
   → Para cada página: obtém Page Access Token
   → Subscreve página aos webhooks: subscribePageWebhook(pageId, pageToken)
   → Salva na tabela Whatsapps
```

### Subscription de Página (Messenger)

```typescript
// POST /{pageId}/subscribed_apps
await fetch(`https://graph.facebook.com/v22.0/${pageId}/subscribed_apps`, {
  method: "POST",
  headers: { Authorization: `Bearer ${pageToken}` },
  body: JSON.stringify({
    subscribed_fields: ["messages", "messaging_postbacks", "messaging_optins"]
  })
});
```

### Token Refresh Automático

Ambos os serviços (Instagram e Messenger) possuem método `refreshToken`:

```typescript
// instagram.service.ts → refreshToken(connectionId)
// messenger.service.ts → refreshToken(connectionId)
// Rota: POST /api/instagram/refresh-tokens (bulk para todos do tenant)
```

Tokens long-lived expiram em ~60 dias. Recomendação: agendar refresh a cada 50 dias.

## Envio de Mensagens por Canal

### WABA — Texto

```typescript
const payload = {
  messaging_product: "whatsapp",
  to: recipientPhone,  // formato: 5511999999999
  type: "text",
  text: { body: messageText }
};
await fetch(`https://graph.facebook.com/${version}/${phoneNumberId}/messages`, {
  method: "POST",
  headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
  body: JSON.stringify(payload)
});
```

### WABA — Template

```typescript
const payload = {
  messaging_product: "whatsapp",
  to: recipientPhone,
  type: "template",
  template: {
    name: "template_name",
    language: { code: "pt_BR" },
    components: [{ type: "body", parameters: [{ type: "text", text: "valor" }] }]
  }
};
```

### WABA — Mídia

```typescript
// Upload mídia para Meta
const formData = new FormData();
formData.append("messaging_product", "whatsapp");
formData.append("file", fileBuffer, { filename, contentType: mimeType });
const uploadRes = await fetch(`https://graph.facebook.com/${version}/${phoneId}/media`, {
  method: "POST",
  headers: { Authorization: `Bearer ${token}` },
  body: formData
});
const { id: mediaId } = await uploadRes.json();

// Enviar mensagem com mediaId
const payload = {
  messaging_product: "whatsapp",
  to: phone,
  type: "image", // ou video, audio, document
  image: { id: mediaId, caption: "legenda" }
};
```

### Instagram — Texto

```typescript
// Page-scoped
const url = `https://graph.facebook.com/v22.0/${pageId}/messages`;
const payload = { recipient: { id: recipientId }, message: { text: messageText } };

// OAuth (Instagram Business Login)
const url = `https://graph.instagram.com/v22.0/${igBusinessId}/messages`;
const payload = { recipient: { id: recipientId }, message: { text: messageText } };
```

### Instagram — Mídia

```typescript
const payload = {
  recipient: { id: recipientId },
  message: {
    attachment: {
      type: "image", // image, video, audio, file
      payload: { url: publicMediaUrl, is_reusable: true }
    }
  }
};
```

### Messenger — Texto

```typescript
const url = `https://graph.facebook.com/v22.0/${pageId}/messages`;
const payload = {
  recipient: { id: psid },
  messaging_type: "RESPONSE",
  message: { text: messageText }
};
```

### Messenger — Mídia

```typescript
const payload = {
  recipient: { id: psid },
  messaging_type: "RESPONSE",
  message: {
    attachment: {
      type: "image",
      payload: { url: publicMediaUrl, is_reusable: true }
    }
  }
};
```

## Tratamento de Erros Meta

### Códigos de Erro Comuns

| Código | Significado | Ação |
|--------|-------------|------|
| `131047` | Janela de 24h fechada | Alertar operador, sugerir template |
| `131048` | Spam rate limit | Aguardar e retry |
| `131049` | Limite de mensagens | Verificar tier do número |
| `190` | Token expirado | Refresh token ou reconectar OAuth |
| `100` | Parâmetro inválido | Verificar payload |
| `10` | Permissão negada | Verificar scopes do token |
| `(-1)` | Erro de rede | Retry com backoff |

### Janela de 24h (WABA)

O WhatsApp Business API exige que conversas sejam iniciadas por template após 24h sem interação:

```typescript
// No frontend (atendimento.tsx), erro 131047 é detectado:
if (errorCode === 131047 || errorMessage.includes("24")) {
  toast({ title: "Janela de 24h fechada", description: "Use um template para reabrir" });
}
```

## Contatos Meta — Identificação

### Mapeamento Sender → Contact

| Canal | Campo Sender | Campo Contact DB | Busca |
|-------|-------------|-----------------|-------|
| WABA | `wa_id` (phone) | `number` | Busca por número normalizado |
| Instagram | `sender.id` | `instagramPK` | Busca por `instagramPK` |
| Messenger | `sender.id` | `messengerId` | Busca por `messengerId` |

### Profile Fetch

```typescript
// Instagram — obter nome do sender
const profileRes = await fetch(
  `https://graph.facebook.com/${senderId}?fields=name,profile_pic&access_token=${token}`
);

// Messenger — obter nome do sender
const profileRes = await fetch(
  `https://graph.facebook.com/${psid}?fields=first_name,last_name,profile_pic&access_token=${token}`
);
```

## WABA Templates

### Sincronização

```typescript
// Listar templates da WABA
const url = `https://graph.facebook.com/${version}/${wabaId}/message_templates`;
const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
const { data } = await res.json();
// data = [{ name, language, status, components, ... }]
```

### Status de Template

| Status | Significado |
|--------|-------------|
| `APPROVED` | Aprovado, pode ser enviado |
| `PENDING` | Em análise pela Meta |
| `REJECTED` | Rejeitado |
| `DISABLED` | Desabilitado |

### Criação via API

```typescript
const url = `https://graph.facebook.com/${version}/${wabaId}/message_templates`;
const payload = {
  name: "template_name",
  language: "pt_BR",
  category: "MARKETING", // ou UTILITY, AUTHENTICATION
  components: [
    { type: "BODY", text: "Olá {{1}}, sua compra #{{2}} foi confirmada." }
  ]
};
```

## Frontend — UI Meta (canais.tsx)

### WABA — Formulário

Campos: `tokenAPI` (Phone Number ID), `bmToken` (Access Token), `wabaId` (WABA ID), `wabaVersion`, `number`.
Botão "Testar Conexão" faz GET ao Graph API para validar token.

### Instagram — Conexão

Dois modos:
1. **OAuth**: Botão "Conectar com Instagram" → redireciona para `/api/instagram/auth`
2. **Manual**: Campos para Page ID e Access Token

### Messenger — Conexão

1. **OAuth**: Botão "Conectar com Facebook" → redireciona para `/api/messenger/auth`
2. **Manual**: Campos para Page ID e Page Access Token

### Info Panels nos Cards

```typescript
// WABA
<InfoPanel>
  Phone ID: {tokenAPI}
  WABA ID: {wabaId}
  Versão API: {wabaVersion}
  Token: Configurado/Pendente
</InfoPanel>

// Instagram
<InfoPanel>
  Page ID: {tokenAPI}
  Token: Configurado/Pendente
</InfoPanel>

// Messenger
<InfoPanel>
  Página: {number || tokenAPI}
  Page ID: {tokenAPI}
  Token: Configurado/Pendente
</InfoPanel>
```

## Variáveis de Ambiente

| Variável | Uso |
|----------|-----|
| `FACEBOOK_APP_ID` | App ID do Meta Developer |
| `FACEBOOK_APP_SECRET` | App Secret |
| `BACKEND_URL` | URL pública do backend (para OAuth callbacks) |
| `FRONTEND_URL` | URL do frontend (redirect pós-OAuth) |

## Skills Relacionadas

- `communication-channels-expert` — Visão geral de todos os canais
- `whatsapp-messaging-expert` — Detalhes profundos de mensageria WhatsApp
- `whatsapp-calling-expert` — Chamadas de voz via WhatsApp
