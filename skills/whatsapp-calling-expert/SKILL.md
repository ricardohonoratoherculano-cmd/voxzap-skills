---
name: whatsapp-calling-expert
description: Especialista em WhatsApp Business Calling API para integração de chamadas de voz via WhatsApp Cloud API. Use quando o usuário pedir para implementar, modificar ou debugar funcionalidades relacionadas a chamadas de voz WhatsApp, incluindo recebimento de chamadas (UIC), chamadas iniciadas pelo negócio (BIC), WebRTC/SDP negotiation, webhook de chamadas, permissões de chamada, e integração com o sistema de atendimento do VoxZap. Inclui referência completa dos endpoints, fluxos, eventos webhook, limites, e arquitetura BYOV (Bring-Your-Own-VoIP).
---

# Especialista WhatsApp Calling API - VoxZap

Skill para desenvolvimento e manutenção de todas as funcionalidades de chamadas de voz via WhatsApp Cloud API no projeto VoxZap — sistema multi-tenant de gestão de comunicação.

## Quando Usar

- Implementar recebimento de chamadas de voz (UIC - User-Initiated Call)
- Implementar chamadas iniciadas pelo negócio (BIC - Business-Initiated Call)
- Processar webhooks de chamadas (connect, terminate, missed, permission_reply)
- Configurar WebRTC/SDP negotiation no backend
- Criar interface de chamada no frontend (atender, rejeitar, encerrar)
- Gerenciar permissões de chamada BIC
- Debugar problemas de áudio, SDP, ICE candidates, STUN/TURN
- Registrar histórico de chamadas no ticket
- Integrar chamadas com Socket.io para notificações em tempo real

## Contexto do Projeto VoxZap

- **Stack**: Node.js/Express + TypeScript (backend), React + Vite (frontend)
- **Mensageria**: Já integrado com Meta WhatsApp Cloud API para mensagens
- **Tempo Real**: Socket.io com rooms por tenant, usuário e ticket
- **Webhook**: Endpoint existente em `/api/webhook/whatsapp` (processar campo `calls`)
- **Banco**: PostgreSQL via Prisma ORM
- **Experiência WebRTC**: Projeto irmão VoxFone usa SIP.js para WebRTC

## Arquitetura da Calling API

### Modelo "Bring-Your-Own-VoIP" (BYOV)

A Meta gerencia a leg WhatsApp (conexão com o app do cliente). O VoxZap gerencia a leg VoIP (conexão WebRTC com o operador no navegador).

```
┌─────────────────────────┐
│  Cliente WhatsApp (App)  │
└───────────┬─────────────┘
            │ Leg WhatsApp (Meta gerencia)
            ▼
┌─────────────────────────┐
│  Meta Cloud API          │
│  graph.facebook.com      │
└───────────┬─────────────┘
            │ Webhook HTTPS + SDP Offer
            ▼
┌─────────────────────────┐
│  VoxZap Backend          │
│  - Webhook handler       │
│  - Signaling relay       │
│  - pre_accept/accept API │
│  - Socket.io broadcast   │
└───────────┬─────────────┘
            │ Socket.io (SDP Offer + ICE servers)
            ▼
┌─────────────────────────┐
│  Operador (Navegador)    │
│  - RTCPeerConnection     │
│  - SDP Answer generation │
│  - Microfone + Speaker   │
│  - Controles de chamada  │
│  - GlobalCallProvider    │
└─────────────────────────┘
```

### Fluxo Completo: Chamada Recebida (UIC)

```
1. Cliente toca ícone de chamada no WhatsApp
2. Meta envia webhook: { field: "calls", value: { event: "connect", call_id, sdp (SDP Offer), from } }
3. Backend VoxZap:
   a. Identifica tenant pelo phone_number_id
   b. Carrega ICE servers do tenant (STUN + TURN da Settings table)
   c. Emite INCOMING_CALL via Socket.io para operadores do tenant (com sdpOffer + iceServers)
   d. Inicia ringtone (Web Audio API oscillator) + Browser Notification
4. Operador clica "Atender" no CallOverlay (qualquer página):
   a. Navegador cria RTCPeerConnection com iceServers
   b. Define remote description (SDP Offer da Meta)
   c. Gera SDP Answer
   d. Emite accept_call via Socket.io com { callId, sdpAnswer }
5. Backend envia para Meta:
   POST /{version}/{phone-number-id}/calls
   Body: { messaging_product: "whatsapp", call_id, action: "pre_accept", session: { sdp: "<SDP_ANSWER>", sdp_type: "answer" } }
6. Backend confirma:
   POST /{version}/{phone-number-id}/calls
   Body: { messaging_product: "whatsapp", call_id, action: "accept", session: { sdp: "<SDP_ANSWER>", sdp_type: "answer" } }
7. Áudio bidirecional estabelecido (WebRTC no navegador)
8. Ao desligar (qualquer lado):
   POST /{version}/{phone-number-id}/calls
   Body: { messaging_product: "whatsapp", call_id, action: "terminate" }
```

### Fluxo Completo: Chamada Iniciada pelo Negócio (BIC) — LIVE-VALIDATED

```
1. Pré-requisito: Template aprovado pela Meta com botão VOICE_CALL
   - Nome configurável via Settings: calling_bic_template (default: "retorno_voxzap")
   - Template deve ter categoria MARKETING e botão type: "VOICE_CALL"
   - IMPORTANTE: Ao deletar template, Meta impõe cooldown de 4 semanas para reusar o nome
2. Operador clica "Ligar" (PhoneCall icon) no chat header
3. Frontend checa permissão: GET /api/calls/permission/{contactNumber}
4. Se !granted, envia template de permissão:
   POST /api/calls/request-permission
   Body: { contactNumber, connectionId }
   - Backend usa CallingService.requestCallPermission() que:
     a. Lê template name de Settings (calling_bic_template) ou usa fallback "retorno_voxzap"
     b. Envia template com componente VOICE_CALL:
        POST /{version}/{phone-number-id}/messages
        Body: { messaging_product: "whatsapp", to, type: "template",
                template: { name, language: { code: "pt_BR" },
                components: [{ type: "button", sub_type: "VOICE_CALL", index: 0, parameters: [] }] } }
     c. sub_type DEVE ser "VOICE_CALL" (uppercase) — NÃO "voice_call_permission"
5. Cliente recebe template com botão "Ligar" no WhatsApp
6. Cliente clica "Ligar" → webhook permission_reply (permission: "granted")
7. Permissão válida por 7 dias
8. Se granted, operador pode iniciar chamada: POST /api/calls/initiate
9. Meta conecta ao cliente e envia webhook com SDP Offer
10. Mesmo fluxo de SDP Answer + pre_accept + accept
```

## Endpoints da Meta (Calling)

### Ações de Chamada

```
POST https://graph.facebook.com/{version}/{phone-number-id}/calls
Authorization: Bearer {bmToken}
Content-Type: application/json
```

| Ação | Body | Quando Usar |
|------|------|-------------|
| `pre_accept` | `{ messaging_product: "whatsapp", call_id, action: "pre_accept", session: { sdp: "<SDP_ANSWER>", sdp_type: "answer" } }` | Enviar SDP Answer após receber Offer |
| `accept` | `{ messaging_product: "whatsapp", call_id, action: "accept", session: { sdp: "<SDP_ANSWER>", sdp_type: "answer" } }` | Confirmar atendimento da chamada |
| `terminate` | `{ messaging_product: "whatsapp", call_id, action: "terminate" }` | Encerrar chamada |

> **IMPORTANTE**: Os campos `messaging_product` e `session` (com `sdp` e `sdp_type`) são obrigatórios em `pre_accept` e `accept`. Usar `sdp` como campo direto (fora de `session`) causa erro `"Missing session parameter"` (code 131009).

### Iniciar Chamada (BIC)

```
POST https://graph.facebook.com/{version}/{phone-number-id}/calls
Body: { to: "+5511999999999", type: "voice" }
```

### Enviar Template de Permissão (BIC) — VALIDATED

```
POST https://graph.facebook.com/{version}/{phone-number-id}/messages
Body: {
  messaging_product: "whatsapp",
  to: "+5511999999999",
  type: "template",
  template: {
    name: "retorno_voxzap",  // Configurável via Settings: calling_bic_template
    language: { code: "pt_BR" },
    components: [
      {
        type: "button",
        sub_type: "VOICE_CALL",   // DEVE ser uppercase
        index: 0,
        parameters: []
      }
    ]
  }
}
```

### Configuração BIC (Settings table por tenant)

| Chave | Descrição | Default |
|-------|-----------|---------|
| `calling_bic_template` | Nome do template aprovado pela Meta com botão VOICE_CALL | `retorno_voxzap` |
| `calling_turn_url` | URL do servidor TURN (ex: `turn:server.com:3478`) | STUN público do Google |
| `calling_turn_username` | Username do TURN server | vazio |
| `calling_turn_credential` | Credential do TURN server | vazio |
| `rejectCalls` | Recusar chamadas automaticamente (`enabled`/`disabled`) | `disabled` |
| `rejectCallsMessage` | Mensagem enviada ao chamador quando chamada é rejeitada | `As chamadas de voz e vídeo estão desabilitadas para esse WhatsApp, favor enviar uma mensagem de texto.` |

Configurável na UI: Configurações → Chamadas de Voz (WhatsApp)
Backend ALLOWED_SETTING_KEYS em routes.ts deve incluir estas chaves para o PUT /api/settings/bulk funcionar.

### Recusar Chamadas Automaticamente (Auto-Reject)

Quando `rejectCalls` está `enabled`, **toda chamada recebida é rejeitada antes de entrar no fluxo normal**.

**Fluxo:**
1. Webhook recebe evento `connect` (chamada recebida)
2. `handleIncomingCall` verifica `getTenantSettings(tenantId)["rejectCalls"]`
3. Se `enabled`:
   a. Envia `terminate` action via Meta API (`sendCallAction(connection, call_id, "terminate")`)
   b. Verifica resultado (`terminateResult.success`) e loga sucesso/falha
   c. Envia mensagem de rejeição via WhatsApp (`sendRejectCallMessage`)
   d. Retorna imediatamente — **NÃO cria ticket, NÃO notifica operadores, NÃO registra call log**
4. Se `disabled`: fluxo normal de chamada continua

**Método `sendRejectCallMessage`**: Similar a `sendMissedCallAutoMessage` — envia texto simples via Graph API usando `bmToken` da conexão.

**UI**: Card "Recusar chamadas no WhatsApp" com toggle Switch + Textarea condicional (aparece só quando ativado) + botão Salvar.

### Template VOICE_CALL — Requisitos Meta

- Categoria: MARKETING (obrigatório para templates com VOICE_CALL)
- Deve ter componente BUTTONS com botão type: "VOICE_CALL"
- O botão gera automaticamente link "Ligar" no WhatsApp do cliente
- Ao deletar template, Meta impõe cooldown de ~4 semanas antes de reusar o mesmo nome
- Template criado via POST /api/templates com body incluindo buttons: [{ type: "VOICE_CALL", text: "Ligar" }]

## Eventos de Webhook

O webhook recebe eventos no campo `calls` (deve ser assinado separadamente de `messages`).

| Evento | Descrição | Dados |
|--------|-----------|-------|
| `connect` | Chamada recebida (UIC) ou BIC conectada | `call_id`, `from`, `sdp` (SDP Offer) |
| `terminate` | Chamada encerrada | `call_id`, `reason` |
| `missed` | Chamada não atendida (timeout) | `call_id`, `from` |
| `permission_reply` | Resposta ao pedido BIC | `permission` ("granted"/"denied"), `from` |

### Estrutura do Webhook de Chamada

```json
{
  "object": "whatsapp_business_account",
  "entry": [{
    "id": "<WABA_ID>",
    "changes": [{
      "field": "calls",
      "value": {
        "event": "connect",
        "call_id": "<CALL_ID>",
        "from": "<PHONE_NUMBER>",
        "phone_number_id": "<PHONE_NUMBER_ID>",
        "sdp": "<SDP_OFFER_STRING>",
        "timestamp": "<UNIX_TIMESTAMP>"
      }
    }]
  }]
}
```

## Limites e Restrições

| Limite | Produção | Sandbox |
|--------|----------|---------|
| Chamadas conectadas/dia | 10 | 100 |
| Pedidos permissão BIC/dia | 1 | 25 |
| Pedidos permissão BIC/semana | 2 | 100 |
| Chamadas simultâneas (max) | 1.000 | 1.000 |

### Restrições Importantes

- WhatsApp-to-PSTN **NÃO** é suportado (somente VoIP)
- BIC bloqueado em: EUA, Canadá, Turquia, Egito, Vietnã, Nigéria
- Timeout para atender chamada: 30-60 segundos
- Após 4 chamadas BIC não atendidas: permissão revogada
- Versão mínima recomendada da Graph API: v21.0

## Pré-requisitos da Meta

- Conta Meta Business verificada
- Limite mínimo de 2.000 conversas business-initiated em 24h
- Webhook inscrito no campo `calls`
- Número registrado na Cloud API
- Access Token com permissão `whatsapp_business_messaging`
- HTTPS obrigatório para webhook

## Precificação

| Tipo | Custo |
|------|-------|
| UIC (cliente liga) | Gratuito |
| BIC (negócio liga) | ~US$ 0,01/min (varia por país, blocos de 6s) |
| Infraestrutura TURN | Variável (por conta do negócio) |

## Integração com Infraestrutura Existente do VoxZap

### Webhook (server/routes.ts)

O endpoint `/api/webhook/whatsapp` já processa mensagens. Deve ser estendido para processar `field: "calls"`:

```typescript
// No handler do webhook, além de field === "messages":
if (change.field === "calls") {
  const callEvent = change.value;
  switch (callEvent.event) {
    case "connect":
      // Nova chamada recebida
      await handleIncomingCall(callEvent, connection, tenantId);
      break;
    case "terminate":
      // Chamada encerrada
      await handleCallTerminated(callEvent, tenantId);
      break;
    case "missed":
      // Chamada perdida
      await handleMissedCall(callEvent, connection, tenantId);
      break;
    case "permission_reply":
      // Resposta de permissão BIC
      await handlePermissionReply(callEvent, tenantId);
      break;
  }
}
```

### Socket.io (server/websocket/socket.ts)

Novos eventos para chamadas:

| Evento | Direção | Payload | Uso |
|--------|---------|---------|-----|
| `INCOMING_CALL` | Server→Client | `{ callId, from, contactName, ticketId, iceServers }` | Chamada recebida (iceServers incluem STUN + TURN do tenant) |
| `CALL_ACCEPTED` | Server→Client | `{ callId, operatorId }` | Chamada atendida |
| `CALL_ENDED` | Server→Client | `{ callId, reason, duration }` | Chamada encerrada |
| `CALL_MISSED` | Server→Client | `{ callId, from }` | Chamada perdida |
| `CALL_ERROR` | Server→Client | `{ callId, error }` | Erro na chamada |
| `CALL_PERMISSION_UPDATE` | Server→Client | `{ contactNumber, permission }` | Atualização de permissão BIC (permission: "granted"/"denied") |
| `accept_call` | Client→Server | `{ callId, sdpAnswer }` | Operador aceita chamada (inclui SDP Answer gerado no navegador) |
| `reject_call` | Client→Server | `{ callId }` | Operador rejeita chamada |

### WebRTC — Browser-Side (Signaling Relay Pattern)

O backend NÃO cria RTCPeerConnection. Ele atua como relay de sinalização:

1. Backend recebe SDP Offer da Meta via webhook
2. Backend emite INCOMING_CALL via Socket.io (com sdpOffer e iceServers)
3. Navegador (CallOverlay) cria RTCPeerConnection, gera SDP Answer
4. Navegador emite accept_call com sdpAnswer via Socket.io
5. Backend envia pre_accept + accept para Meta API com o sdpAnswer

```typescript
// Backend (calling.service.ts) — relay only
async acceptCall(callId: string, sdpAnswer: string, connection: ConnectionInfo) {
  // AMBOS pre_accept e accept requerem session com SDP (validado em produção)
  await this.sendCallAction(connection, callId, "pre_accept", sdpAnswer);
  await this.sendCallAction(connection, callId, "accept", sdpAnswer);
}

// sendCallAction envia para Meta API:
// Body: { messaging_product: "whatsapp", call_id, action, session: { sdp, sdp_type: "answer" } }
// Para "terminate": omite session

// Frontend (call-context.tsx / call-overlay.tsx) — WebRTC happens here
const pc = new RTCPeerConnection({ iceServers });
await pc.setRemoteDescription({ type: "offer", sdp: sdpOffer });
const answer = await pc.createAnswer();
await pc.setLocalDescription(answer);
socket.emit("accept_call", { callId, sdpAnswer: answer.sdp });
```

### Frontend: Componente de Chamada (atendimento.tsx)

```typescript
// Socket.io listener para chamada recebida
useEffect(() => {
  socket.on('INCOMING_CALL', (data) => {
    setIncomingCall(data);
    // Mostrar modal/notificação de chamada recebida
  });
  
  socket.on('CALL_ENDED', (data) => {
    setActiveCall(null);
    // Atualizar UI
  });
  
  return () => {
    socket.off('INCOMING_CALL');
    socket.off('CALL_ENDED');
  };
}, [socket]);

// Atender chamada
const handleAcceptCall = () => {
  socket.emit('accept_call', { callId: incomingCall.callId });
  setActiveCall(incomingCall);
  setIncomingCall(null);
};

// Rejeitar chamada
const handleRejectCall = () => {
  socket.emit('reject_call', { callId: incomingCall.callId });
  setIncomingCall(null);
};
```

## Roadmap de Implementação

### Fase 1: Receber Chamadas (UIC) — ✅ LIVE-VALIDATED (32s call)
- Processar webhook `calls` com eventos `connect`, `terminate`, `missed`
- WebRTC SDP negotiation com Meta API (signaling-only relay)
- `pre_accept` e `accept` AMBOS requerem `session: { sdp, sdp_type: "answer" }` — validado em produção
- Notificação global de chamada recebida (Socket.io INCOMING_CALL + Browser Notification API)
- CallOverlay global via GlobalCallProvider context (renderiza em qualquer página)
- Ringtone audível (Web Audio API oscillator 440Hz)
- Áudio bidirecional via WebRTC no navegador
- Registro de chamadas no histórico do ticket (mediaType: "call_log")
- STUN/TURN configurável por tenant (Settings: calling_turn_url, calling_turn_username, calling_turn_credential)
- ICE servers passados dinamicamente via INCOMING_CALL event
- Socket singleton pattern (use-socket.ts) para evitar conexões duplicadas

### Fase 2: Iniciar Chamadas (BIC) — ✅ LIVE-VALIDATED
- Botão "Ligar" (PhoneCall icon) no chat header do atendimento
- Fluxo automático de solicitar permissão de chamada via template com botão VOICE_CALL
- Template name configurável via Settings: `calling_bic_template` (default: "retorno_voxzap")
- Template deve ter categoria MARKETING e botão type: "VOICE_CALL", sub_type: "VOICE_CALL" (uppercase)
- Webhook `permission_reply` processado e armazenado
- Permissões rastreadas na tabela CallLogs (callStatus: permission_granted/permission_denied)
- Permissão válida por 7 dias
- API: POST /api/calls/initiate, POST /api/calls/request-permission, GET /api/calls/permission/:contactNumber
- CallingService: getCallPermission(), initiateCall(), requestCallPermission(), handlePermissionReply()
- Configurações TURN e template BIC editáveis na UI: Configurações → Chamadas de Voz (WhatsApp)
- ALLOWED_SETTING_KEYS no routes.ts inclui: calling_bic_template, calling_turn_url, calling_turn_username, calling_turn_credential
- apiRequest<T> retorna JSON já parseado — NUNCA chamar .json() no resultado

### Fase 3: Recursos Avançados — FUTURO
- Transferência de chamada entre operadores
- Gravação de chamadas
- Histórico e relatórios de chamadas
- IVR (menu de voz interativo)
- Integração com filas de atendimento

## Arquivos-Chave (Implementados)

| Arquivo | Responsabilidade |
|---------|-----------------|
| `server/services/calling.service.ts` | Serviço principal — UIC (handleIncomingCall, acceptCall, terminateCall) + BIC (initiateCall, requestCallPermission, getCallPermission, handlePermissionReply) + Auto-Reject (sendRejectCallMessage) |
| `server/services/webhook.service.ts` | Processamento de webhooks — campo `calls` (connect, terminate, missed, permission_reply) |
| `server/routes.ts` | API routes para chamadas (/api/calls/*) e TURN config |
| `client/src/contexts/call-context.tsx` | GlobalCallProvider — estado global de chamadas, socket listeners, ringtone |
| `client/src/components/call-overlay.tsx` | UI de chamada recebida e chamada ativa (renderiza globalmente) |
| `client/src/hooks/use-socket.ts` | Socket singleton compartilhado (evita conexões duplicadas) |
| `client/src/pages/atendimento.tsx` | Botão "Ligar" no chat header para BIC |
| `client/src/pages/documentacao-calling.tsx` | Documentação admin da Calling API |
| `client/src/App.tsx` | GlobalCallProvider wraps AuthenticatedLayout |
| `prisma/schema.prisma` | CallLogs table — armazena chamadas e permissões BIC |

## Dependências

**NÃO é necessário `wrtc` ou `werift` no backend!**
O VoxZap usa pattern "signaling relay" — WebRTC roda apenas no navegador (RTCPeerConnection nativo do browser).
O backend apenas retransmite SDP entre Meta e frontend via Socket.io.

Pacotes já instalados no projeto que são relevantes:
- `socket.io` / `socket.io-client` — comunicação em tempo real
- `axios` — chamadas à Meta Graph API

## Padrões de Código

### Convenção de Naming para Eventos

```typescript
// Socket.io events (chamadas)
const CALL_EVENTS = {
  INCOMING_CALL: 'INCOMING_CALL',
  CALL_ACCEPTED: 'CALL_ACCEPTED',
  CALL_ENDED: 'CALL_ENDED',
  CALL_MISSED: 'CALL_MISSED',
} as const;
```

### Armazenamento de Chamadas Ativas

```typescript
// Map em memória para chamadas ativas no backend (signaling relay — SEM RTCPeerConnection)
const activeCalls = new Map<string, {
  callId: string;
  from: string;
  tenantId: number;
  connectionId: number;
  phoneNumberId: string;
  sdpOffer: string;
  operatorId?: number;
  startedAt?: Date;
}>();
```

### Registro de Chamada no Banco

Ao encerrar uma chamada, registrar como mensagem no ticket:

```typescript
// Mensagem de sistema no ticket
await messageRepository.create({
  body: `📞 Chamada de voz ${duration > 0 ? `(${formatDuration(duration)})` : '(perdida)'}`,
  fromMe: false,
  ack: 3,
  mediaType: null,
  ticketId,
  contactId,
  tenantId,
  timestamp: BigInt(Date.now()),
  dataJson: JSON.stringify({
    type: 'voice_call',
    callId,
    duration,
    direction: 'inbound', // ou 'outbound'
    status: duration > 0 ? 'answered' : 'missed'
  })
});
```

## Lições Aprendidas (Live Validation)

### SDP Session Format (Crítico)
- `pre_accept` e `accept` AMBOS requerem `session: { sdp, sdp_type: "answer" }`
- Enviar `sdp` como campo direto (fora de `session`) causa erro `"Missing session parameter"` (code 131009)
- `terminate` NÃO precisa de session — apenas `{ messaging_product, call_id, action: "terminate" }`

### Template BIC
- Template com botão VOICE_CALL deve usar `sub_type: "VOICE_CALL"` (uppercase exato)
- Usar `sub_type: "voice_call_permission"` causa erro
- Categoria MARKETING é obrigatória para templates com VOICE_CALL
- Ao deletar template da Meta, há cooldown de ~4 semanas para reusar o mesmo nome
- Template `retorno_voxzap` (id: 1946654022603123) está aprovado e em produção

### WebRTC / Áudio — LIVE-VALIDATED (77s call, stable)
- Backend NÃO precisa de wrtc/werift — signaling relay é suficiente
- RTCPeerConnection roda apenas no navegador
- ICE servers (STUN + TURN) devem ser passados no evento INCOMING_CALL via Socket.io
- TURN configurável por tenant na tabela Settings
- **TURN TCP fallback automático:** `call-overlay.tsx` auto-expande URLs `turn:host:port` adicionando `turn:host:port?transport=tcp` como fallback — essencial para redes celulares que bloqueiam UDP
- **ICE gathering timeout:** 5 segundos (não 3s!) — relay candidates do TURN demoram mais para serem coletados; timeout curto faz o SDP Answer ser enviado sem relay candidates
- **ICE restart automático:** ao detectar `disconnected`, chama `pc.restartIce()` antes de mostrar toast de erro; resets no `connected`/`completed`
- **ICE candidate logging:** `onicecandidate` loga tipo (host/srflx/relay), protocolo (udp/tcp), endereço e porta — essencial para diagnóstico
- **SDP Answer size indicator:** SDP com ~827 bytes = apenas STUN (sem relay); ~962 bytes = STUN + TURN relay candidates incluídos — confirma que TURN está funcionando
- **coturn requer verbose logging** para diagnosticar sessões: adicionar `verbose` no `/etc/turnserver.conf`
- **Seed automático:** `seedDefaultSettings()` em `server/seed.ts` cria `calling_turn_url`, `calling_turn_username`, `calling_turn_credential` (vazios) para tenant 1 em novas instalações — STUN fallback funciona com valores vazios

### Conexão / getConnection (Crítico)
- `getConnection(connectionId, tenantId)` agora tem fallback automático:
  1. Tenta buscar a conexão especificada (pelo `connectionId` do ticket)
  2. Se não encontrar ou se a conexão não tiver `bmToken`, busca outra conexão ativa do mesmo tenant que tenha `bmToken` e `tokenAPI`
  3. Isso é necessário porque tickets podem estar em conexões "waba" (ex: Homologação) que não têm bmToken para chamadas
- Erro "Conexão não encontrada" ocorre quando NENHUMA conexão do tenant tem `bmToken`
- O `bmToken` é obrigatório para chamar a Meta Graph API (diferente do `tokenAPI` que é o phone_number_id)
- Frontend envia `connectionId: selectedTicket.whatsappId` — pode ser uma conexão sem capacidade de chamadas

### Frontend Patterns
- `apiRequest<T>` retorna JSON já parseado — NUNCA chamar `.json()` no resultado
- Token auth: `JSON.parse(localStorage.getItem("voxzap-auth") || "{}").state?.token`
- Tema: NUNCA usar cores hex; usar classes semânticas (exceção: charts e PDF)
- Shared menu: `client/src/lib/menu-config.ts`

## Links de Referência

- [Documentação Oficial - Calling API](https://developers.facebook.com/docs/whatsapp/cloud-api/calling/)
- [WhatsApp Cloud API - Visão Geral](https://developers.facebook.com/docs/whatsapp/cloud-api/)
- [Blog WhatsApp Business - Calling](https://business.whatsapp.com/blog/whatsapp-business-calling-api)
- [Guia WebRTC Integration](https://webrtc.ventures/2025/11/how-to-integrate-the-whatsapp-business-calling-api-with-webrtc-to-enable-customer-voice-calls/)
