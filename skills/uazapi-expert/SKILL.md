---
name: uazapi-expert
description: Especialista em UAZAPI / uazapiGO 2.0.1 — gateway WhatsApp Multi-device baseado em Baileys. Use quando precisar criar, modificar, debugar ou estender qualquer integração com servidores UAZAPI (free.uazapi.com, instâncias self-hosted, etc), incluindo conexão (pairing/QR), envio de mensagens (texto, mídia, localização), webhooks (eventos lowercase, action add/remove), e tratamento do bug LID@lid vs chatid. Inclui referência completa dos endpoints do OpenAPI 2.0.1, payload formats, gotchas conhecidos, e padrões de código do `server/services/uazapi.service.ts`.
---

# UAZAPI Expert — Skill

Especialista no protocolo UAZAPI / uazapiGO 2.0.1 para envio e recebimento de mensagens WhatsApp via Baileys. Cobre desde o setup da conexão até troubleshooting de mensagens perdidas.

## Quando ativar

- Criar/modificar `server/services/uazapi.service.ts`
- Debugar webhook UAZAPI (`server/services/webhook.service.ts` — seção "UAZAPI Webhook")
- Configurar/ressincronizar canal UAZAPI no banco (`Whatsapps` com `type='uazapi'`)
- Investigar mensagens não entregues (resposta 200 mas WhatsApp não recebe)
- Investigar contatos com números esquisitos de 15 dígitos (LIDs)
- Adicionar novos tipos de mídia (audio, video, sticker, document)
- Setup de webhook em nova instância

## Documentação oficial

**Spec OpenAPI 3.1.0 da uazapiGO 2.0.1**: `https://docs.uazapi.com/openapi-bundled.json`

Snapshot local: `docs/external-apis/uazapi-openapi-2.0.1.json` (709KB, 126 paths catalogados).

⚠️ **Sempre confiar no spec oficial**, não em tentativa-e-erro. Antes de chutar campo (`Phone` vs `number`, `Body` vs `text`, etc), abrir o spec e procurar o `requestBody.content."application/json".schema`.

```bash
# Buscar definição de um endpoint
node -e "const s=require('./docs/external-apis/uazapi-openapi-2.0.1.json'); console.log(JSON.stringify(s.paths['/send/text'], null, 2))"

# Listar todos os endpoints disponíveis
node -e "const s=require('./docs/external-apis/uazapi-openapi-2.0.1.json'); Object.keys(s.paths).sort().forEach(p => console.log(p))"
```

## Autenticação

Header: `Token: <instance_token>`

Não usa Bearer. O token é criado quando a instância é provisionada (via `/instance/init` ou painel) e fica vinculado a 1 número.

## Conexão (pairing)

```
POST /instance/init
  Headers: Token: <token>
  Body: { "phone": "5585999999999" }   // sem +, sem espaços, com DDI
  Resp: { "instance": { "status": "pairing", "paircode": "ABCD-1234", "qrcode": "..." } }

GET /instance/status
  Resp: { "instance": { "status": "connected"|"disconnected"|"pairing", "owner": "5585...", ... } }

POST /instance/disconnect
  Body: {}                             // logout
```

Status válidos: `connected`, `disconnected`, `pairing`, `connecting`.

## Envio de mensagens — endpoints

### Princípio CRÍTICO: payload é **lowercase**

A UAZAPI 2.0 padronizou todos os campos em snake_case minúsculo. Versões antigas usavam PascalCase (`Phone`, `Body`, `MediaUrl`) — esses NÃO funcionam mais. Sempre lowercase.

### `/send/text`

```json
POST /send/text
{
  "number":  "558588788084",          // só dígitos, com DDI
  "text":    "Olá!",
  "replyid": "ABC123..." // opcional — id da mensagem citada
}
```

### `/send/media` — **endpoint UNIFICADO**

⚠️ **Não existem `/send/image`, `/send/video`, `/send/audio`, `/send/document`, `/send/sticker` separados.** Tudo passa por `/send/media` com o campo `type`:

```json
POST /send/media
{
  "number":   "558588788084",
  "type":     "image",                  // image|video|videoplay|document|audio|myaudio|ptt|sticker
  "file":     "https://.../foto.jpg",   // URL pública OU data URI base64
  "mimetype": "image/jpeg",
  "text":     "legenda opcional",       // caption (image/video/document)
  "docName":  "contrato.pdf"            // só pra document
}
```

Mapeamento de `type`:

| type | Uso |
|---|---|
| `image` | Foto |
| `video` | Vídeo (envia como anexo) |
| `videoplay` | Vídeo com auto-play (PIP no app) |
| `document` | PDF/DOCX/etc — exige `docName` |
| `audio` | Áudio em arquivo (.mp3, .ogg, .opus) |
| `ptt` | Push-to-talk (nota de voz, balão de áudio) |
| `myaudio` | Áudio com avatar customizado |
| `sticker` | Figurinha (.webp) |

### `/send/location`

```json
POST /send/location
{
  "number":    "558588788084",
  "latitude":  -3.7319,
  "longitude": -38.5267,
  "name":     "Voxtel HQ",       // opcional
  "address":  "Av. Sta. Maria"   // opcional
}
```

### `/send/contact`, `/send/menu`, `/send/carousel`, `/send/status`

Ver spec — todos seguem o padrão `number` + payload tipado.

## Webhook — configuração

### Endpoint

```
POST /webhook
{
  "url":                 "https://meudominio.com/api/webhook/uazapi/<tenantId>/<connId>",
  "enabled":             true,
  "events":              ["messages", "messages_update", "connection", "presence"],
  "excludeMessages":     [],
  "addUrlEvents":        false,         // se true, sufixa /eventName na url (NÃO usar)
  "addUrlTypesMessages": false,
  "action":              "add"          // add | remove | replace
}
```

### Eventos válidos (LOWERCASE)

`messages`, `messages_update`, `connection`, `presence`, `chats`, `groups`, `contacts`, `call`

⚠️ Versões antigas aceitavam PascalCase (`Message`, `ReadReceipt`, `Connection`) — **não funcionam mais**. Use lowercase.

### Validação rápida do webhook

```bash
TOKEN='<token>'
curl -s -H "Token: $TOKEN" https://free.uazapi.com/webhook   # GET para ver config atual
```

## Webhook — formato do payload recebido

```json
{
  "event": "messages",
  "type":  "message",
  "instance": { "id": "...", "name": "...", "owner": "5585..." },
  "message": {
    "chatid":           "558588788084@s.whatsapp.net",   // ✅ JID REAL — usar este
    "sender":           "246449686184160@lid",            // ⚠️ LID privacy-protected — NÃO USAR
    "id":               "558588788084:3AE40EC5...",
    "messageid":        "3AE40EC5...",
    "fromMe":           false,
    "messageTimestamp": 1777078368000,                    // ⚠️ MS na UAZAPI (Baileys usa S)
    "type":             "ExtendedTextMessage",
    "text":             "Boa noite",
    "content": { "text": "Boa noite", "contextInfo": {} },
    "owner":            "5585...",
    "isGroup":          false
  }
}
```

## ⚠️ Gotchas conhecidos (BUGS RESOLVIDOS — não reintroduzir!)

### 1. LID vs chatid — sempre priorizar `chatid`

Quando WhatsApp Privacy está ativa no celular, o campo `sender` vem como `<15-dígitos>@lid` (Linked ID privacy-protected) — **NÃO é número de telefone**. Salvá-lo como contato gera registros impossíveis de mensagear (UAZAPI responde 200 mas mensagem nunca chega).

**Sempre extrair na ordem:**
```ts
const isLid = (v) => typeof v === "string" && v.includes("@lid");
const candidates = [
  m.chatid, m.ChatId, m.remoteJid, m.key?.remoteJid,
  m.from, m.From,
  m.sender, m.key?.participant,   // ← último recurso
];
const rawSender = candidates.find(v => v && !isLid(v)) || "";
```

Detecção de contato corrompido no banco:
```sql
SELECT id, name, number FROM "Contacts" WHERE LENGTH(number) >= 15;
-- Se algum tem 15 dígitos, é LID. Apagar e recriar via webhook.
```

Confirmar se é LID via API:
```bash
curl -s -H "Token: $TOKEN" -H "Content-Type: application/json" \
  -X POST -d '{"numbers":["123132987871472"]}' \
  https://free.uazapi.com/chat/check
# Se retornar isInWhatsapp:false e jid:"" → não é número, é LID
```

### 2. Timestamp em milissegundos

Baileys puro usa segundos (10 dígitos). UAZAPI envia em **milissegundos (13 dígitos)**. Detectar pelo tamanho:

```ts
let ts = Number(m.messageTimestamp);
if (ts > 1e12) ts = Math.floor(ts / 1000);  // converte ms → s
const date = new Date(ts * 1000);
```

### 3. `markAsRead` aceita SÓ `id`

```json
POST /message/markread
{ "id": ["msg_id_1", "msg_id_2"] }
```

NÃO mandar `ChatPhone`, `SenderPhone`, `chat_id`, etc. A UAZAPI ignora ou retorna 400.

### 4. Endpoints obsoletos que NÃO existem mais

| ❌ NÃO usar | ✅ Usar |
|---|---|
| `/chat/send/text` | `/send/text` |
| `/chat/send/image` | `/send/media` (type:"image") |
| `/chat/send/video` | `/send/media` (type:"video") |
| `/chat/send/audio` | `/send/media` (type:"audio" ou "ptt") |
| `/chat/send/document` | `/send/media` (type:"document") |
| `/chat/markread` | `/message/markread` |

### 5. Free vs paid — limites

`free.uazapi.com` tem rate limit (~1 msg/seg) e instabilidades esporádicas. Para produção, usar instância paga (`api.uazapi.com` com plan) ou self-hosted Docker (`docker pull uazapi/uazapi`).

## Implementação no codebase

### Service principal

`server/services/uazapi.service.ts` — singleton exportado como `uazapiService` com métodos:

```ts
class UazapiService {
  buildBaseUrl(wppUser: string): string                                                  // wppUser = "free" → "https://free.uazapi.com"
  async getInstanceStatus(conn): Promise<{ status, owner, paircode, qrcode }>
  async startPairing(conn, phone): Promise<{ paircode, qrcode }>
  async disconnect(conn): Promise<void>
  async setWebhook(conn, webhookUrl, events?): Promise<{ success, error? }>
  async sendText(conn, recipient, body, quotedMsgId?): Promise<UazapiSendResult>
  async sendMedia(conn, recipient, filePath, fileName, mimeType, mediaType, caption?): Promise<UazapiSendResult>
  async sendLocation(conn, recipient, lat, lon, name?, address?): Promise<UazapiSendResult>
  async markAsRead(conn, _chatPhone, messageIds: string[]): Promise<{ success, error? }>
  async downloadMedia(conn, remoteUrl, mediaType): Promise<string>
}

interface UazapiConnection { token: string; baseUrl: string; }
interface UazapiSendResult { success: boolean; messageId?: string; error?: string; }
```

### Webhook handler

`server/services/webhook.service.ts` — função `handleUazapiWebhook` (busca por `[UAZAPI Webhook]` no arquivo).

Rota: `POST /api/webhook/uazapi/:tenantId/:connectionId` em `server/routes.ts`.

### Tabela `Whatsapps` (Prisma)

Para canal UAZAPI:
- `type` = `"uazapi"`
- `wppUser` = subdomínio (ex: `"free"`, `"api"`, `"meu-cliente"`)
- `wppPassword` = token (`Token:` header)
- `number` = `owner` da instância (preenchido após connect)
- `status` = espelha `instance.status`

## Padrão de testes manuais (curl)

```bash
TOKEN='<token>'
BASE='https://free.uazapi.com'

# 1) Instance status
curl -s -H "Token: $TOKEN" $BASE/instance/status | jq .

# 2) Setar webhook
curl -s -H "Token: $TOKEN" -H "Content-Type: application/json" -X POST $BASE/webhook -d '{
  "url":"https://meu.dominio.com/api/webhook/uazapi/1/1",
  "enabled":true,
  "events":["messages","messages_update","connection","presence"],
  "addUrlEvents":false,
  "action":"add"
}' | jq .

# 3) Enviar texto
curl -s -H "Token: $TOKEN" -H "Content-Type: application/json" -X POST $BASE/send/text \
  -d '{"number":"5585999999999","text":"teste"}' | jq .

# 4) Verificar se número existe no WhatsApp (ANTES de enviar)
curl -s -H "Token: $TOKEN" -H "Content-Type: application/json" -X POST $BASE/chat/check \
  -d '{"numbers":["5585999999999"]}' | jq .
```

## Fluxo de troubleshooting

```
Mensagem não chegou no destino?
│
├── 1. Status da instância: /instance/status → "connected"?
│   └── Não → reconectar (QR/pairing)
│
├── 2. Owner conferido?
│   └── owner == número de envio? → Sim → vai pra "Mensagens pessoais", não pra inbox normal
│
├── 3. /chat/check no número destino → isInWhatsapp:true?
│   └── Não → número errado (provável LID) → checar Contacts.number, deletar e recriar
│
├── 4. POST /send/text retornou 200 com chatid e messageid?
│   └── Sim → UAZAPI aceitou, problema é fora (rate limit / WhatsApp Privacy do destino)
│   └── Não → ler resposta JSON pro erro
│
└── 5. Esperou ack pelo webhook messages_update?
    └── ack: 1=server, 2=delivered, 3=read, 4=played
```

## Skill correlatas

- `communication-channels-expert` — visão geral dos canais (UAZAPI é um deles)
- `whatsapp-messaging-expert` — WhatsApp Cloud API (BYOV / Meta direto), DIFERENTE do UAZAPI
- `client-server-access` — para deploy/debug de UAZAPI em VPS de clientes
