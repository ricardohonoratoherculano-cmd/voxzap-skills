---
name: voxtel-asr-tts
description: Especialista nos serviços Voxtel ASR (transcrição de áudio) e Voxtel TTS (síntese de voz). Use quando precisar integrar, configurar, debugar ou estender transcrição de áudio (speech-to-text) ou geração de voz (text-to-speech) com os servidores Voxtel. Inclui endpoints, autenticação, fluxo assíncrono com webhook, modelos disponíveis, vozes TTS, tratamento de erros, e implementação de referência completa em TypeScript/Express. Parte do ecossistema VoxHUB.
---

# Especialista Voxtel ASR + TTS

Skill para integração com os serviços de transcrição de áudio (ASR) e síntese de voz (TTS) da Voxtel, utilizados no ecossistema VoxHUB.

## Quando Usar

- Integrar transcrição de áudio (speech-to-text) em qualquer projeto
- Integrar síntese de voz (text-to-speech) em qualquer projeto
- Configurar ou debugar a comunicação com os servidores Voxtel ASR/TTS
- Implementar fluxo assíncrono com webhook para transcrições longas
- Criar interfaces frontend para gravação, upload de áudio ou geração de voz
- Migrar de polling para webhook ou vice-versa

---

## Servidores e Autenticação

| Serviço | Base URL | Token (env var) |
|---------|----------|-----------------|
| **ASR** (Transcrição) | `https://asr.voxserver.app.br` | `VOX_ASR_API_TOKEN` |
| **TTS** (Síntese de Voz) | `https://tts.voxserver.app.br` | `OPENAI_API_KEY` |

Autenticação via Bearer token no header `Authorization`:
```
Authorization: Bearer <token>
```

### Variáveis de Ambiente

```env
VOX_ASR_API_TOKEN=<token-asr>
OPENAI_API_KEY=<token-tts>
VOX_ASR_BASE_URL=https://asr.voxserver.app.br   # opcional, override
VOX_TTS_BASE_URL=https://tts.voxserver.app.br    # opcional, override
```

---

## ASR — Transcrição de Áudio (Speech-to-Text)

### Modelos Disponíveis

| Modelo | Descrição |
|--------|-----------|
| `orig_large_v3` | **Recomendado** — Whisper Large V3, melhor qualidade |
| `orig_large_v2` | Whisper Large V2 |
| `orig_large_v1` | Whisper Large V1 |
| `orig_large` | Whisper Large (original) |
| `orig_medium` | Whisper Medium (mais rápido, menor precisão) |
| `orig_medium_en` | Whisper Medium (só inglês) |
| `orig_small` | Whisper Small |
| `orig_small_en` | Whisper Small (só inglês) |
| `orig_base` | Whisper Base |
| `orig_base_en` | Whisper Base (só inglês) |
| `orig_tiny` | Whisper Tiny (mais rápido, menor precisão) |
| `orig_tiny_en` | Whisper Tiny (só inglês) |
| `custom_base_f16` | Modelo customizado (float16) |
| `custom_base_int8` | Modelo customizado (int8, otimizado) |

### Idiomas Suportados

- `pt` — Português Brasileiro
- `en` — Inglês

### Formatos de Áudio Aceitos

WAV, MP3, MP4, M4A, OGG, WebM, FLAC, AAC, GSM, SLN (máximo 25MB)

### Endpoints ASR

#### 1. Transcrição Síncrona (NÃO RECOMENDADO para arquivos grandes)

```
POST /v1/audio/transcriptions
Content-Type: multipart/form-data
Authorization: Bearer <VOX_ASR_API_TOKEN>

Fields:
  file: <arquivo de áudio>
  model: "orig_large_v3"
  language: "pt" (opcional)

Response 200:
{
  "text": "Texto transcrito..."
}
```

**Problema**: Para áudios longos (>90s de processamento), o gateway upstream retorna 504 timeout. Use o fluxo assíncrono com webhook.

#### 2. Transcrição Assíncrona com Webhook (RECOMENDADO)

**Passo 1 — Submeter job:**
```
POST /v1/audio/transcriptions/async
Content-Type: multipart/form-data
Authorization: Bearer <VOX_ASR_API_TOKEN>

Fields:
  file: <arquivo de áudio>
  model: "orig_large_v3"
  language: "pt" (opcional)
  webhook_url: "https://seu-servidor/webhook/asr?secret=<secret>"

Response 200:
{
  "id": "abc123def456",
  "status": "queued"  // ou "cached"
}
```

**Passo 2 — Receber resultado via webhook:**

O ASR faz POST no `webhook_url` quando a transcrição termina:

```json
{
  "job_id": "abc123def456",
  "status": "completed",
  "content_hash": "9f86d081...",
  "metadata": { ... },
  "result": {
    "text": "Texto transcrito...",
    "model": "orig_large_v3",
    "duration": 120.5,
    "latency_seconds": 3.2,
    "rtf": 0.026
  }
}
```

Em caso de falha:
```json
{
  "job_id": "abc123def456",
  "status": "failed",
  "error": "Mensagem de erro"
}
```

O webhook espera resposta `{ "ok": true }` com status 200.

#### 3. Consultar Status do Job (API externa — alternativa ao webhook)

> **Nota**: Este endpoint é da API externa Voxtel, não implementado localmente. Útil para debug ou implementações sem webhook.

```
GET /v1/audio/transcriptions/jobs/{job_id}
Authorization: Bearer <VOX_ASR_API_TOKEN>

Response 200:
{
  "status": "completed",  // queued, completed, failed, error
  "result": {
    "text": "Texto transcrito...",
    "duration": 120.5,
    "latency_seconds": 3.2
  }
}
```

#### 4. Listar Modelos (API externa)

> **Nota**: Endpoint da API externa Voxtel para consulta de modelos disponíveis.

```
GET /v1/models
Authorization: Bearer <VOX_ASR_API_TOKEN>

Response 200:
{
  "object": "list",
  "data": [
    { "id": "orig_large_v3", "object": "model", "owned_by": "local" },
    ...
  ]
}
```

### Rotas Implementadas vs API Externa

| Rota | Tipo | Descrição |
|------|------|-----------|
| `POST /api/transcribe` | **Implementada** (Express) | Recebe áudio do frontend, submete job async ao ASR, aguarda webhook |
| `POST /api/webhook/asr` | **Implementada** (Express) | Recebe callback do ASR com resultado da transcrição |
| `POST /api/tts` | **Implementada** (Express) | Recebe texto do frontend, proxy para TTS, retorna áudio |
| `POST /v1/audio/transcriptions/async` | **API externa** (Voxtel ASR) | Submissão de job de transcrição assíncrono |
| `POST /v1/audio/transcriptions` | **API externa** (Voxtel ASR) | Transcrição síncrona (não recomendada) |
| `GET /v1/audio/transcriptions/jobs/{id}` | **API externa** (Voxtel ASR) | Consulta status de job (alternativa ao webhook) |
| `GET /v1/models` | **API externa** (Voxtel ASR) | Lista modelos disponíveis |
| `POST /v1/audio/speech` | **API externa** (Voxtel TTS) | Geração de áudio a partir de texto |

### Padrão de Implementação ASR com Webhook (TypeScript/Express)

O fluxo recomendado utiliza webhook com proteção contra race condition:

1. Gerar secret criptográfico único por job
2. Submeter job async com `webhook_url` incluindo o secret como query param
3. Registrar resolver em mapa in-memory (`pendingJobs`)
4. Quando webhook chega, validar secret e resolver a Promise
5. Se webhook chega antes do listener (race condition), cachear em `earlyResults`

```typescript
// Estruturas de controle
const pendingJobs = new Map<string, PendingJob>();  // job_id → {resolve, reject, timer}
const earlyResults = new Map<string, EarlyResult>(); // job_id → resultado antecipado
const webhookSecrets = new Map<string, string>();     // job_id → secret

// Fluxo:
// 1. POST /api/transcribe recebe arquivo do frontend
// 2. Gera secret, monta webhook_url com ?secret=...
// 3. Submete para /v1/audio/transcriptions/async
// 4. Registra secret em webhookSecrets
// 5. Chama waitForWebhook(jobId) — verifica earlyResults, senão cria Promise
// 6. POST /api/webhook/asr recebe callback do ASR
//    - Valida secret via query param
//    - Se pendingJobs tem o job → resolve diretamente
//    - Se não tem (race) → cacheia em earlyResults com TTL de 60s
// 7. Retorna texto ao frontend
```

Referência completa: `artifacts/api-server/src/routes/transcribe.ts`

### Segurança do Webhook ASR

- **Secret por job**: Cada job gera um secret criptográfico de 32 bytes (hex)
- **Validação**: O secret é passado como `?secret=...` na webhook_url e validado no recebimento
- **Replay protection**: Jobs sem secret registrado são rejeitados com 403
- **Cleanup**: Secrets são removidos do mapa após validação bem-sucedida do webhook callback

---

## TTS — Síntese de Voz (Text-to-Speech)

### Formato da API

Compatível com o formato OpenAI TTS (`/v1/audio/speech`).

### Vozes Disponíveis

| Voz | Características |
|-----|----------------|
| `alloy` | Neutra e versátil |
| `echo` | Grave e suave |
| `fable` | Narrativa e expressiva |
| `onyx` | Profunda e autoritativa |
| `nova` | Jovem e energética |
| `shimmer` | Clara e agradável |

### Formatos de Saída

`mp3` (padrão), `opus`, `aac`, `flac`, `wav`, `pcm`

### Endpoint TTS

```
POST /v1/audio/speech
Authorization: Bearer <OPENAI_API_KEY>
Content-Type: application/json

Body:
{
  "model": "tts-1",
  "input": "Texto para converter em áudio",
  "voice": "alloy",
  "response_format": "mp3",   // opcional, padrão: mp3
  "speed": 1.0                // opcional, 0.25 a 4.0
}

Response 200:
Content-Type: audio/mpeg
Body: <dados binários do áudio>
```

### Limites

- **Texto**: máximo 4096 caracteres por requisição
- **Velocidade**: 0.25x a 4.0x
- **Modelo**: `tts-1` (padrão)

### Padrão de Implementação TTS (TypeScript/Express)

```typescript
router.post("/tts", async (req, res) => {
  const { input, voice, response_format, speed } = req.body;
  const apiKey = process.env.OPENAI_API_KEY;
  const baseUrl = process.env.VOX_TTS_BASE_URL || "https://tts.voxserver.app.br";

  const response = await fetch(`${baseUrl}/v1/audio/speech`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "tts-1",
      input: input.trim(),
      voice: voice || "alloy",
      response_format: response_format || "mp3",
      speed: speed || 1.0,
    }),
  });

  const arrayBuffer = await response.arrayBuffer();
  res.setHeader("Content-Type", response.headers.get("content-type") || "audio/mpeg");
  res.send(Buffer.from(arrayBuffer));
});
```

Referência completa: `artifacts/api-server/src/routes/tts.ts`

---

## Tratamento de Erros (Códigos Padronizados)

O backend retorna `errorCode` que o frontend traduz conforme o idioma selecionado:

**ASR (Transcrição):**

| Código | Descrição | HTTP Status |
|--------|-----------|-------------|
| `TIMEOUT` | Webhook não respondeu a tempo (10min) | 504 |
| `FILE_TOO_LARGE` | Arquivo excede 25MB | 413 |
| `SERVICE_UNAVAILABLE` | API indisponível ou token inválido | 500 |
| `UNSUPPORTED_FORMAT` | Formato de áudio não suportado | 400 |
| `NO_FILE` | Nenhum arquivo enviado | 400 |

**TTS (Síntese de Voz):**

| Código | Descrição | HTTP Status |
|--------|-----------|-------------|
| `NO_INPUT` | Texto TTS vazio | 400 |
| `INPUT_TOO_LONG` | Texto TTS excede 4096 chars | 400 |
| `TTS_FAILED` | Erro na API TTS upstream | 400/502 |
| `RATE_LIMITED` | Muitas requisições (429 upstream) | 429 |
| `SERVICE_UNAVAILABLE` | API indisponível ou token inválido | 500 |

---

## Frontend — Padrões de Implementação

### Hook useTranscribe (React)

```typescript
const formData = new FormData();
formData.append("file", audioBlob, filename);
formData.append("language", language); // "pt" ou "en"

const response = await fetch(`${BASE_URL}api/transcribe`, {
  method: "POST",
  body: formData,
});
const result = await response.json(); // { text: "..." }
```

### Hook useTTS (React)

```typescript
const response = await fetch(`${BASE_URL}api/tts`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ input: text, voice: "alloy", response_format: "mp3" }),
});
const blob = await response.blob();
const audioUrl = URL.createObjectURL(blob);
// IMPORTANTE: URL.revokeObjectURL(audioUrl) no cleanup/unmount
```

### Internacionalização

Todas as mensagens de erro e textos da interface devem ser localizados:
- Idioma padrão: `pt` (Português Brasileiro)
- Idioma alternativo: `en` (Inglês)
- Persistir seleção no `localStorage`

---

## Integração com VoxHUB

Este serviço integra-se ao ecossistema VoxHUB:

- **VoxCALL**: Usa ASR para transcrição automática de chamadas telefônicas (Asterisk)
- **VoxZAP**: Usa ASR para transcrever áudios de WhatsApp, Telegram, etc.
- **VoxCRM**: Futura integração para transcrição de reuniões e chamadas de vendas
- **VoxTranscription**: App standalone de transcrição + TTS (este projeto)

Para integração com VoxHUB, consulte a skill `voxhub-ecosystem`.

---

## Troubleshooting

### Transcrição retorna 504 Timeout
- Usar fluxo assíncrono com webhook em vez de síncrono
- Verificar se o `webhook_url` é acessível externamente
- Aumentar `JOB_TIMEOUT_MS` se necessário (padrão: 600s)

### Webhook retorna 403
- Verificar se o secret foi registrado antes do webhook chegar
- Verificar se o query param `?secret=` está presente na URL
- Verificar proteção contra race condition (cache de resultados antecipados)

### TTS retorna 404
- Verificar se está usando `tts.voxserver.app.br` (NÃO `asr.voxserver.app.br`)
- O servidor ASR não tem endpoint de TTS — são servidores separados

### TTS retorna 401
- Verificar se `OPENAI_API_KEY` está configurada corretamente
- O token TTS é diferente do token ASR (`VOX_ASR_API_TOKEN`)

### Áudio gerado vazio ou corrompido
- Verificar `Content-Type` na resposta
- Garantir que o frontend trata o response como blob, não JSON
- Verificar se `URL.revokeObjectURL` não está sendo chamado antes do playback

### Transcrição retorna texto vazio
- O áudio pode não conter fala inteligível
- Verificar se o idioma (`language`) está correto para o áudio
- Testar com modelo diferente (ex: `orig_medium` para testes rápidos)
