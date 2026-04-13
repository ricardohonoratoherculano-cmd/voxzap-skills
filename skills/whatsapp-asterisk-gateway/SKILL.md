---
name: whatsapp-asterisk-gateway
description: Especialista no gateway WhatsApp Calling → Asterisk via ARI ExternalMedia + werift WebRTC. Use quando precisar implantar, configurar, debugar ou estender a integração de chamadas de voz WhatsApp (Meta Cloud API) com sistemas Asterisk/PBX de clientes. Inclui arquitetura completa do gateway (WebRTC↔RTP, opus@48kHz↔alaw@8kHz, DTMF RFC2833→ARI inject), troubleshooting de áudio, configuração de Asterisk/PJSIP, e checklist de implantação por cliente.
---

# Especialista WhatsApp → Asterisk Gateway (VoxCall Calling)

Skill para implantação e manutenção do gateway que roteia chamadas de voz recebidas pelo WhatsApp Business Calling API diretamente para o Asterisk/PBX do cliente via ARI ExternalMedia, com transcodificação opus↔alaw e DTMF bidirecional.

## Quando Usar

- Implantar o VoxCall Calling Gateway em um novo cliente com Asterisk
- Debugar problemas de áudio (falhas, latência, áudio unidirecional, picotado)
- Debugar DTMF não funcionando (URA não reconhece dígitos)
- Configurar Asterisk/PJSIP para receber chamadas do gateway
- Ajustar transcodificação opus↔alaw
- Analisar logs do gateway para identificar problemas
- Configurar Settings do tenant para ativar o VoxCall
- Estender funcionalidades do gateway (gravação, transferência, etc.)

## Arquitetura do Gateway

```
┌────────────────────┐
│  Cliente WhatsApp   │
│  (App celular)      │
└─────────┬──────────┘
          │ Leg WhatsApp (Meta gerencia)
          ▼
┌────────────────────┐
│  Meta Cloud API     │
│  Webhook: connect   │
│  SDP Offer (opus)   │
└─────────┬──────────┘
          │ HTTPS Webhook + SDP
          ▼
┌────────────────────────────────────────────┐
│  VoxZap Backend (Node.js)                  │
│  voxcall-calling-gateway.service.ts        │
│                                            │
│  ┌──────────────────────────────────────┐  │
│  │  werift RTCPeerConnection            │  │
│  │  - Recebe SDP Offer da Meta          │  │
│  │  - Gera SDP Answer                   │  │
│  │  - Recebe RTP opus@48kHz do WhatsApp │  │
│  │  - Envia RTP opus@48kHz ao WhatsApp  │  │
│  │  - Recebe DTMF RFC2833 (PT=126)      │  │
│  └──────────┬───────────────────────────┘  │
│             │ RTP opus (48kHz)             │
│             ▼                              │
│  ┌──────────────────────────────────────┐  │
│  │  Transcodificação (opusscript)       │  │
│  │  Meta→Ast: opus@48kHz → PCM@48kHz   │  │
│  │           → downsample → PCM@8kHz   │  │
│  │           → G.711 alaw encode        │  │
│  │  Ast→Meta: alaw decode → PCM@8kHz   │  │
│  │           → upsample → PCM@48kHz    │  │
│  │           → opus@48kHz encode        │  │
│  └──────────┬───────────────────────────┘  │
│             │ RTP alaw (8kHz, PT=8)        │
│             ▼                              │
│  ┌──────────────────────────────────────┐  │
│  │  UDP Socket (dgram)                  │  │
│  │  Envia/recebe RTP alaw ao Asterisk   │  │
│  └──────────┬───────────────────────────┘  │
└─────────────┼──────────────────────────────┘
              │ UDP RTP (alaw) via ExternalMedia
              ▼
┌────────────────────────────────────────────┐
│  Asterisk PBX (Cliente)                    │
│  ┌──────────────────────────────────────┐  │
│  │  ARI ExternalMedia Channel           │  │
│  │  format=alaw, connection_type=client │  │
│  └──────────┬───────────────────────────┘  │
│             │                              │
│  ┌──────────┴───────────────────────────┐  │
│  │  ARI Bridge (mixing,dtmf_events)     │  │
│  │  ExternalMedia + Local Channel       │  │
│  └──────────┬───────────────────────────┘  │
│             │                              │
│  ┌──────────┴───────────────────────────┐  │
│  │  Local Channel                       │  │
│  │  Local/s@CONTEXT/n                   │  │
│  │  → Dialplan (URA, filas, ramais)     │  │
│  └──────────────────────────────────────┘  │
└────────────────────────────────────────────┘
```

## Fluxo Completo de uma Chamada

```
1. Cliente liga pelo WhatsApp → Meta envia webhook "connect" com SDP Offer
2. calling.service.ts detecta calling_voxcall_enabled=true para o tenant
3. voxcall-calling-gateway.service.ts:
   a. Carrega config do tenant (ARI host, port, user, password, context, extension, rtpBindAddress)
   b. Conecta ARI WebSocket (se não conectado)
   c. Cria werift RTCPeerConnection com codecs: PCMU, PCMA, opus, telephone-event
   d. Define SDP Offer da Meta como remoteDescription
   e. Gera SDP Answer
   f. Abre UDP socket para relay RTP
   g. Cria ARI ExternalMedia channel (alaw, RTP, UDP, client, both)
   h. Cria ARI Bridge (mixing,dtmf_events)
   i. Adiciona ExternalMedia ao bridge
   j. Origina Local channel: Local/s@CONTEXT/n (com callerId = WhatsApp caller)
   k. Cria opus encoder+decoder (48kHz mono VOIP)
   l. Configura relays bidirecionais:
      - Ast→Meta: alaw@8kHz → upsample@48kHz → opus encode → werift.sendRtp
      - Meta→Ast: opus decode@48kHz → downsample@8kHz → alaw encode → UDP send
   m. Configura silence keepalive (frames opus de silêncio quando Asterisk para de enviar)
   n. Configura diagnóstico periódico (ICE, connection, DTLS state)
4. Backend retorna SDP Answer ao calling.service.ts
5. calling.service.ts envia pre_accept + accept para Meta API com SDP Answer
6. Áudio bidirecional estabelecido
7. DTMF: WhatsApp envia RFC2833 (PT=126) → werift entrega → ARI inject no Local channel
8. Ao encerrar: cleanupBridge() fecha PC, socket, deleta channels e bridge do ARI
```

## Arquivo Principal

**`server/services/voxcall-calling-gateway.service.ts`**

### Funções Exportadas

| Função | Descrição |
|--------|-----------|
| `loadConfig(tenantId)` | Carrega configuração VoxCall do tenant via Settings |
| `routeCallToVoxcall(callEvent, connection, config)` | Roteia chamada para Asterisk, retorna `{ success, sdpAnswer }` |
| `cleanupBridge(callId)` | Limpa todos os recursos da chamada |
| `testAriConnection(config)` | Testa conectividade ARI, retorna versão do Asterisk |
| `connectAriWebSocket(config)` | Conecta WebSocket ARI para eventos Stasis |
| `disconnectAriWebSocket(config?)` | Desconecta WebSocket ARI |
| `isVoxcallBridgeActive(callId)` | Verifica se bridge está ativa |
| `getActiveBridgeCount()` | Conta bridges ativas |

### Componentes Internos Críticos

| Componente | Responsabilidade |
|------------|-----------------|
| `upsample8kTo48k()` | Interpolação linear PCM 8kHz→48kHz (ratio 6x) |
| `downsample48kTo8k()` | Decimação com média ponderada PCM 48kHz→8kHz |
| `alawBufToPcm()` / `pcmBufToAlaw()` | Codec G.711 A-law via lookup tables |
| `linearToAlaw()` | Encode PCM→alaw sample-by-sample |
| `setupAsteriskToMetaRelay()` | Relay alaw→opus (Ast→Meta) com upsample |
| `setupMetaToAsteriskRelay()` | Relay opus→alaw (Meta→Ast) com downsample + DTMF |
| `setupSilenceKeepalive()` | Envia frames opus silence quando Asterisk silencia |
| `generateDtmfAlaw()` | Gera tons DTMF in-band (alaw) via síntese senoidal |
| `injectDtmfViaAri()` | Injeta DTMF no Asterisk via `POST /channels/{id}/dtmf` |

## Transcodificação — Detalhes Técnicos

### Opus 48kHz (Wideband) — OBRIGATÓRIO

O opus DEVE operar a **48kHz** (não 8kHz). Razões:
- WhatsApp/Meta envia opus a 48kHz (padrão WebRTC)
- opusscript a 8kHz produz áudio narrowband (qualidade de telefone antigo)
- Diferença audível: 48kHz = voz clara e natural, 8kHz = voz abafada com artefatos

```typescript
const OPUS_RATE = 48000;
const ALAW_RATE = 8000;
const RESAMPLE_RATIO = OPUS_RATE / ALAW_RATE; // = 6

// Encoder e decoder SEMPRE a 48kHz
opusDecoder = new OS(OPUS_RATE, 1, OS.Application.VOIP);
opusEncoder = new OS(OPUS_RATE, 1, OS.Application.VOIP);
```

### Pipeline Ast→Meta (URA/agente → WhatsApp)

```
Asterisk alaw (160 bytes, 20ms@8kHz)
  → alawBufToPcm() → PCM 16-bit LE (320 bytes, 160 samples@8kHz)
  → upsample8kTo48k() → PCM 16-bit LE (1920 bytes, 960 samples@48kHz)
  → opusEncoder.encode(pcm48k, 960) → opus frame (15-40 bytes)
  → RTP header (12 bytes) + opus payload
  → werift sender.sendRtp()
```

### Pipeline Meta→Ast (WhatsApp → URA/agente)

```
werift onReceiveRtp: opus packet
  → opusDecoder.decode(opusPayload) → PCM 16-bit LE (1920 bytes, 960 samples@48kHz)
  → downsample48kTo8k() → PCM 16-bit LE (320 bytes, 160 samples@8kHz)
  → pcmBufToAlaw() → alaw (160 bytes)
  → RTP header (12 bytes, PT=8) + alaw payload
  → UDP socket.send() ao Asterisk
```

### Resampling

**Upsample 8kHz→48kHz (interpolação linear):**
```typescript
function upsample8kTo48k(pcm8k: Buffer): Buffer {
  // Para cada par de amostras adjacentes, interpola 6 pontos
  // frac = j / 6, sample = s0 + (s1 - s0) * frac
  // Resultado: 160 amostras → 960 amostras
}
```

**Downsample 48kHz→8kHz (média com janela):**
```typescript
function downsample48kTo8k(pcm48k: Buffer): Buffer {
  // Para cada amostra de saída, calcula média de ~6 amostras vizinhas
  // Janela: center ± 2-3 amostras (anti-aliasing simples)
  // Resultado: 960 amostras → 160 amostras
}
```

### Constantes RTP

```typescript
const OPUS_SAMPLES_PER_FRAME = 960;  // 20ms @ 48kHz
const OPUS_SILENCE_FRAME = Buffer.from([0xf8, 0xff, 0xfe]);  // Comfort noise
const SILENCE_INTERVAL_MS = 20;       // Intervalo de keepalive
const SILENCE_GAP_THRESHOLD_MS = 60;  // Threshold para detectar silêncio do Asterisk
```

## DTMF — Arquitetura Completa

### Problema Original

O werift **não entrega pacotes com payload types não registrados**. Sem registrar `telephone-event` como codec, pacotes PT=126 são silenciosamente descartados pelo werift.

### Solução (Validada em Produção)

1. **Registrar telephone-event no werift:**
```typescript
const offerDtmfPT = (() => {
  const m = sdp.match(/a=rtpmap:(\d+)\s+telephone-event\//i);
  return m ? parseInt(m[1]) : 126;
})();

const pc = new werift.RTCPeerConnection({
  codecs: {
    audio: [
      { mimeType: "audio/PCMU", clockRate: 8000, channels: 1, payloadType: 0 },
      { mimeType: "audio/PCMA", clockRate: 8000, channels: 1, payloadType: 8 },
      { mimeType: "audio/opus", clockRate: 48000, channels: 2, payloadType: 111 },
      { mimeType: "audio/telephone-event", clockRate: 8000, channels: 1, payloadType: offerDtmfPT },
    ],
  },
});
```

2. **Detectar dígito do RFC2833 payload:**
```typescript
// RFC 2833 payload: [eventCode, endBit|volume, duration_hi, duration_lo]
const eventCode = payload[0];  // 0-15 (0-9, *, #, A-D)
const endBit = (payload[1] & 0x80) !== 0;
```

3. **Injetar via ARI no primeiro START:**
```typescript
// Apenas no primeiro pacote de cada novo dígito
if (eventCode !== currentDtmfEvent) {
  currentDtmfEvent = eventCode;
  injectDtmfViaAri(DTMF_LABELS[eventCode]);  // "1", "2", "*", "#", etc.
}

// ARI inject:
POST /channels/{localChannelId}/dtmf
Body: { dtmf: "1", duration: 250, between: 100 }
```

4. **In-band backup**: Gera tons DTMF alaw via síntese senoidal e envia ao Asterisk junto com o ARI inject.

### DTMF Labels

```typescript
const DTMF_LABELS = {
  0: "0", 1: "1", 2: "2", 3: "3", 4: "4", 5: "5",
  6: "6", 7: "7", 8: "8", 9: "9", 10: "*", 11: "#",
  12: "A", 13: "B", 14: "C", 15: "D",
};
```

## Silence Keepalive

Quando o Asterisk para de enviar RTP (ex: entre áudios da URA), o gateway envia frames opus de silêncio para manter a sessão WebRTC ativa e evitar que a Meta desconecte por timeout.

**Características:**
- Usa os mesmos contadores `opusOutSeq`/`opusOutTs` do áudio real (sem descontinuidade)
- Threshold: 60ms sem pacotes do Asterisk
- Intervalo: 20ms (50 frames/segundo)
- SSRC fixo: 0x56585A50 ("VXZP")
- Quando áudio real volta, `silenceActive = false` automaticamente

## Configuração do Tenant (Settings)

| Chave | Descrição | Exemplo |
|-------|-----------|---------|
| `calling_voxcall_enabled` | Ativa gateway VoxCall (`enabled`/`disabled`) | `enabled` |
| `calling_voxcall_ari_host` | IP/hostname do Asterisk | `72.60.151.235` |
| `calling_voxcall_ari_port` | Porta ARI HTTP | `8088` |
| `calling_voxcall_ari_user` | Usuário ARI | `admin` |
| `calling_voxcall_ari_password` | Senha ARI | `senhaSegura` |
| `calling_voxcall_ari_protocol` | Protocolo ARI (`http`/`https`) | `http` |
| `calling_voxcall_context` | Contexto Asterisk para chamadas | `ENTRADA_OPERADORA` |
| `calling_voxcall_extension` | Extensão inicial do dialplan | `s` |
| `calling_voxcall_rtp_bind` | IP externo do servidor VoxZap para RTP | `178.156.253.166` |

**IMPORTANTE**: `calling_voxcall_rtp_bind` deve ser o IP pelo qual o Asterisk consegue alcançar o servidor VoxZap. Se ambos estão na mesma rede, pode ser o IP interno. Se estão em redes diferentes, deve ser o IP público do VoxZap.

## Configuração do Asterisk (Pré-requisitos)

### 1. ARI habilitado (`/etc/asterisk/ari.conf`)

```ini
[general]
enabled = yes
pretty = yes

[admin]
type = user
read_only = no
password = senhaSegura
```

### 2. HTTP habilitado (`/etc/asterisk/http.conf`)

```ini
[general]
enabled = yes
bindaddr = 0.0.0.0
bindport = 8088
```

### 3. PJSIP com alaw (`/etc/asterisk/pjsip.conf`)

```ini
; Endpoints devem permitir alaw
[endpoint_defaults](!)
allow = !all,alaw,opus
dtmf_mode = rfc4733

; RTP
[global]
type = global

[transport-udp]
type = transport
protocol = udp
bind = 0.0.0.0:5060

; IMPORTANTE: strictrtp=no para aceitar RTP de ExternalMedia
```

### 4. RTP sem strict (`/etc/asterisk/rtp.conf`)

```ini
[general]
strictrtp = no
; OU strictrtp = comedia (mais seguro, aprende IP do primeiro pacote)
```

### 5. Stasis app registrado

O gateway usa app `voxzap-wa-bridge`. Não precisa de configuração especial — o ARI registra o app automaticamente quando o WebSocket se conecta.

### 6. Dialplan (exemplo)

```ini
[ENTRADA_OPERADORA]
exten => s,1,Answer()
 same => n,Goto(URAPRINCIPAL,s,1)

[URAPRINCIPAL]
exten => s,1,Background(menu-principal)
 same => n,WaitExten(5)

exten => 1,1,Goto(VENDAS,s,1)
exten => 2,1,Goto(SUPORTE,s,1)
exten => i,1,Goto(ATENDIMENTO_GERAL,s,1)

[VENDAS]
exten => s,1,Dial(PJSIP/ramal1&PJSIP/ramal2,30)
```

## Checklist de Implantação por Cliente

### Pré-requisitos no Asterisk do Cliente

- [ ] ARI habilitado com usuário e senha
- [ ] HTTP habilitado na porta 8088 (ou customizada)
- [ ] Porta ARI acessível pelo servidor VoxZap (firewall)
- [ ] `strictrtp = no` ou `strictrtp = comedia` em rtp.conf
- [ ] Codec `alaw` permitido nos endpoints PJSIP
- [ ] Dialplan com contexto e extensão para receber chamadas
- [ ] Firewall: portas RTP UDP (10000-20000) abertas para IP do VoxZap

### Configuração no VoxZap

- [ ] Ativar `calling_voxcall_enabled = enabled`
- [ ] Configurar `calling_voxcall_ari_host` com IP do Asterisk
- [ ] Configurar credenciais ARI (user, password, port, protocol)
- [ ] Definir `calling_voxcall_context` (ex: `ENTRADA_OPERADORA`)
- [ ] Definir `calling_voxcall_extension` (geralmente `s`)
- [ ] Definir `calling_voxcall_rtp_bind` com IP público/acessível do VoxZap
- [ ] Testar conexão ARI pela UI (botão "Testar Conexão")

### Teste de Validação

- [ ] Ligar pelo WhatsApp → URA toca no caller
- [ ] DTMF funciona → pressionar opção da URA navega corretamente
- [ ] Áudio bidirecional → agente e caller ouvem um ao outro
- [ ] Chamada longa (10+ min) → áudio estável sem falhas
- [ ] Desligar → recursos limpos (bridge, channels deletados)

## Troubleshooting

### Problema: Áudio não chega (unidirecional ou sem áudio)

**Diagnóstico:**
```bash
docker logs voxzap-app --since 5m 2>&1 | grep 'VoxCall-GW.*count'
```

**Causas comuns:**
1. **Firewall bloqueando RTP**: Abrir portas UDP no Asterisk para IP do VoxZap
2. **`strictrtp = yes`**: Asterisk descarta RTP de IPs desconhecidos. Mudar para `no` ou `comedia`
3. **`calling_voxcall_rtp_bind` errado**: Deve ser IP pelo qual Asterisk alcança VoxZap
4. **Asterisk não envia para ExternalMedia**: Verificar se ExternalMedia channel está no bridge

### Problema: Áudio picotado/com falhas

**Diagnóstico:**
```bash
docker logs voxzap-app --since 5m 2>&1 | grep 'VoxCall-GW.*DIAG'
# Verificar astSilenceMs — valores > 100ms indicam perda de pacotes
```

**Causas comuns:**
1. **Opus a 8kHz em vez de 48kHz**: DEVE ser 48kHz. Verificar log "Opus codec instances created (48000Hz)"
2. **Sem resampling**: Se o opus está a 48kHz mas não faz upsample/downsample, o áudio fica corrompido
3. **Latência de rede**: VoxZap muito distante do Asterisk. Idealmente < 50ms RTT
4. **CPU alta**: Transcodificação consome CPU. Verificar load do container
5. **Silence→audio transition**: Se silenceKeepalive usa contadores separados, causa glitch na transição

### Problema: DTMF não funciona (URA não reconhece dígitos)

**Diagnóstico:**
```bash
docker logs voxzap-app --since 5m 2>&1 | grep 'VoxCall-GW.*DTMF'
# Deve mostrar "DTMF RFC2833 START digit=X" e "ARI DTMF injected"

# No Asterisk:
asterisk -rx "core set verbose 5"
# Deve mostrar "DTMF begin 'X' received" e "DTMF end 'X' received"
```

**Causas comuns:**
1. **telephone-event não registrado no werift**: Pacotes PT=126 são descartados silenciosamente
2. **PT errado**: SDP Offer pode usar PT diferente de 126. Extrair com regex do SDP
3. **ARI inject no canal errado**: Deve injetar no `localChannelId` (não no ExternalMedia channel)
4. **Bridge sem dtmf_events**: Bridge deve ser criada com `type: "mixing,dtmf_events"`
5. **Asterisk dtmf_mode**: PJSIP endpoint deve usar `dtmf_mode = rfc4733` ou `auto`

### Problema: Chamada cai imediatamente

**Diagnóstico:**
```bash
docker logs voxzap-app --since 5m 2>&1 | grep 'VoxCall-GW.*error\|VoxCall-GW.*failed'
```

**Causas comuns:**
1. **ARI não conectado**: WebSocket ARI falhou. Verificar credenciais e conectividade
2. **ExternalMedia não suportado**: Asterisk precisa do módulo `res_ari_external_media`
3. **Local channel falha**: Contexto/extensão inexistente no dialplan
4. **werift não carrega**: Pacote werift ou dependências faltando no container

### Problema: Chamada termina após 30-60s

**Causas comuns:**
1. **Meta timeout**: SDP Answer não foi enviado a tempo. Pre_accept + accept devem ser rápidos
2. **ICE failure**: werift não consegue estabelecer ICE. Verificar logs de ICE state
3. **Silence timeout da Meta**: Se nenhum RTP é enviado ao Meta, a sessão expira. Silence keepalive deve estar ativo

## Logs Importantes para Diagnóstico

| Log Pattern | Significado |
|-------------|-------------|
| `Opus codec instances created (48000Hz)` | Codec criado corretamente a 48kHz |
| `Asterisk RTP endpoint detected: X.X.X.X:YYYY` | Asterisk começou a enviar RTP |
| `RTP Ast→Meta count: N, sendFails=0, transcodeFails=0` | Relay funcionando, 0 erros |
| `DTMF RFC2833 START digit="X"` | DTMF detectado do WhatsApp |
| `ARI DTMF injected digit="X"` | DTMF injetado no Asterisk com sucesso |
| `DIAG: ice=connected, conn=connected, dtls=connected` | Conexão WebRTC saudável |
| `astSilenceMs=N` | Tempo desde último pacote do Asterisk (< 20ms = normal) |
| `Asterisk silent for Nms, starting silence keepalive` | Asterisk parou de enviar, keepalive ativado |

## Dependências npm

| Pacote | Versão | Uso |
|--------|--------|-----|
| `werift` | ^0.19+ | WebRTC stack server-side (peer connection, RTP, DTLS, ICE) |
| `opusscript` | ^0.0.8 | Opus encoder/decoder (WASM, sem dependências nativas) |
| `ws` | ^8+ | WebSocket client para ARI |

**NUNCA usar `wrtc`** — é abandonado e não compila em muitos ambientes. Usar `werift` (puro TypeScript).

## Integração com calling.service.ts

O `calling.service.ts` é o orquestrador que decide se a chamada vai para:
1. **WebRTC no navegador** (signaling relay — atendimento humano direto)
2. **VoxCall Gateway** (Asterisk/PBX — URA, filas, roteamento avançado)

```typescript
// Em calling.service.ts → handleIncomingCall():
const voxcallConfig = await voxcallCallingGateway.loadConfig(tenantId);
if (voxcallConfig) {
  // Rota para Asterisk via gateway
  const result = await voxcallCallingGateway.routeCallToVoxcall(callEvent, connection, voxcallConfig);
  if (result.success && result.sdpAnswer) {
    await sendCallAction(connection, call_id, "pre_accept", result.sdpAnswer);
    await sendCallAction(connection, call_id, "accept", result.sdpAnswer);
    return; // Chamada gerenciada pelo Asterisk
  }
}
// Fallback: WebRTC no navegador (signaling relay)
```

## Lições Aprendidas (Produção)

### werift e telephone-event
- werift **descarta silenciosamente** pacotes com payload types não registrados nos codecs
- Registrar `audio/telephone-event` com o PT extraído do SDP Offer da Meta é **obrigatório** para DTMF
- O PT padrão é 126, mas SEMPRE extrair do SDP: `a=rtpmap:(\d+)\s+telephone-event\/`

### Opus 48kHz vs 8kHz
- Opus a 8kHz funciona mas produz áudio **narrowband** (qualidade de telefone fixo antigo)
- Opus a 48kHz é o padrão WebRTC e produz áudio **wideband** (qualidade HD)
- O resampling 8kHz↔48kHz é obrigatório porque Asterisk usa alaw@8kHz
- Interpolação linear para upsample e média com janela para downsample são suficientes para VoIP

### ARI ExternalMedia
- `connection_type: "client"` = Asterisk conecta ao nosso socket (Asterisk inicia envio de RTP)
- `direction: "both"` = bidirecional
- `format: "alaw"` = G.711 A-law (não ulaw)
- O Asterisk detecta automaticamente nosso endpoint quando recebe o primeiro pacote RTP

### Silence Keepalive
- Usar os mesmos contadores `opusOutSeq`/`opusOutTs` do áudio real evita descontinuidades
- Contadores separados causam "glitch" audível na transição silêncio→áudio
- Frame de silêncio opus: `[0xf8, 0xff, 0xfe]` (3 bytes, comfort noise)
- SSRC fixo `0x56585A50` ("VXZP") para consistência

### Performance (16+ min chamada sem falhas)
- 0 `sendFails`, 0 `transcodeFails` em chamadas longas
- `astSilenceMs` consistente entre 1-20ms (excelente)
- ~500 pacotes a cada 10 segundos (50 pps = 20ms/frame)
- CPU: transcodificação opus é leve com opusscript (WASM)

## Referências Cruzadas com Outras Skills

| Skill | Relação |
|-------|---------|
| `whatsapp-calling-expert` | API Meta, webhooks, SDP negotiation, BIC |
| `asterisk-ari-expert` | Referência completa da API ARI REST |
| `voxcall-native-asterisk-deploy` | Deploy do VoxCALL em VPS com Asterisk nativo |
| `communication-channels-expert` | Gestão de conexões WhatsApp |
