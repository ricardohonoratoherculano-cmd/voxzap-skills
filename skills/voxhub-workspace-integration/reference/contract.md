# Contrato Exato — VoxHub Workspace API

> Este arquivo é a fonte da verdade do contrato HTTP entre VoxCRM ↔ VoxCall/VoxZap.
> Versão: 1.1 (alinhada à Task #10 do VoxCRM, mergeada em 2026-05-02).

---

## 1. Headers de Autenticação Server-to-Server

Toda chamada do **VoxCRM → VoxCall/VoxZap** carrega:

| Header | Valor | Uso |
|---|---|---|
| `X-Workspace-Secret` | Segredo compartilhado em texto puro (32 bytes hex) | Autenticação |
| `X-VoxHub-Source` | `"VoxCRM"` | Telemetria/log |

Ambos os headers viajam em conexões TLS (HTTPS). O segredo **nunca** é exposto ao browser.

---

## 2. Endpoints Detalhados

### 2.1 `GET /api/workspace/health`

**Quem chama:** VoxCRM (server-to-server, job de health check a cada 5min + sob demanda).

**Request:**
```http
GET /api/workspace/health HTTP/1.1
Host: voxcall.suaempresa.com
X-Workspace-Secret: 7f3a...d2e1
X-VoxHub-Source: VoxCRM
```

**Responses:**

| Código | Quando | Body |
|---|---|---|
| `200` | Segredo OK + serviço saudável | `{ "status": "ok", "version": "1.2.3", "uptime_s": 12345 }` |
| `401` | Segredo ausente ou inválido | `{ "error": "invalid workspace secret" }` |
| `503` | Segredo OK mas serviço degradado (ex: DB fora) | `{ "status": "degraded", "reason": "database unreachable" }` |

> O VoxCRM trata `200` como ONLINE, `401`/`403` como ERROR (segredo errado), `5xx`/timeout como OFFLINE.

---

### 2.2 `POST /api/workspace/auth-token`

**Quem chama:** Frontend do VoxCRM (browser) ou serviços que precisam abrir uma sessão local na plataforma.

**Request:**
```http
POST /api/workspace/auth-token HTTP/1.1
Host: voxcall.suaempresa.com
Content-Type: application/json

{ "token": "eyJhbGciOiJIUzI1NiI..." }
```

**Procedimento de validação (na ordem):**

1. Verificar assinatura HS256 com `VOXHUB_SHARED_SECRET`. Se falhar → 401.
2. Decodificar payload. Verificar `exp > now()`. Se expirado → 401.
3. Verificar `iss === "voxcrm"`. Se diferente → 401.
4. Verificar `aud === "voxcall"` (no VoxCall) ou `aud === "voxzap"` (no VoxZap). Se diferente → 401.
5. Resolver usuário local:
   - **VoxCall:** `extension` deve corresponder a um ramal cadastrado e ativo no PJSIP/Asterisk.
   - **VoxZap:** o par (`tenantId`, `operatorId`) deve corresponder a um operador cadastrado e ativo.
6. Se nenhum match → 401 com mensagem clara (ex: `"ramal 1042 não encontrado"`).
7. Se OK: emitir sessão local (cookie/JWT da plataforma) com TTL padrão da plataforma (não os 15min do JWT do VoxCRM).

**Responses:**

| Código | Quando | Body |
|---|---|---|
| `200` | Tudo OK | `{ "token": "<jwt local>", "user": { ... }, "expiresAt": "..." }` (formato livre) |
| `401` | Qualquer falha de validação acima | `{ "error": "<mensagem clara>" }` |

> Mensagens de erro podem ser específicas (`"token expirado"`, `"ramal não encontrado"`, `"audience inválida"`) — isso ajuda muito no debug e não vaza nada sensível porque o atacante já precisaria do segredo para gerar um token assinado.

---

### 2.3 `GET /api/workspace/operators` (somente VoxZap)

**Quem chama:** VoxCRM (admin → tela de Mapeamento).

**Request:**
```http
GET /api/workspace/operators HTTP/1.1
Host: voxzap.suaempresa.com
X-Workspace-Secret: 7f3a...d2e1
X-VoxHub-Source: VoxCRM
```

**Response 200:**
```json
{
  "data": [
    { "id": 12, "tenantId": 5, "name": "João Silva",   "email": "joao@empresa.com",  "active": true  },
    { "id": 13, "tenantId": 5, "name": "Maria Souza",  "email": "maria@empresa.com", "active": true  },
    { "id": 14, "tenantId": 5, "name": "Antigo Op",    "email": null,                "active": false }
  ]
}
```

> Inclua operadores inativos — a UI do VoxCRM filtra/marca conforme necessidade.

**Response 401:** segredo inválido.

---

## 3. Estrutura dos JWTs Emitidos pelo VoxCRM

### 3.1 Token VoxCall

```json
{
  "iss": "voxcrm",
  "aud": "voxcall",
  "sub": "42",
  "email": "agente@empresa.com",
  "name": "João Silva",
  "profile": "OPERADOR",
  "extension": "1042",
  "iat": 1714665600,
  "exp": 1714666500
}
```

### 3.2 Token VoxZap

```json
{
  "iss": "voxcrm",
  "aud": "voxzap",
  "sub": "42",
  "email": "agente@empresa.com",
  "name": "João Silva",
  "profile": "OPERADOR",
  "tenantId": 5,
  "operatorId": 12,
  "iat": 1714665600,
  "exp": 1714666500
}
```

### 3.3 Claims — Significado e Tipos

| Claim | Tipo | Origem | Uso na sua plataforma |
|---|---|---|---|
| `iss` | string | sempre `"voxcrm"` | Validar literal |
| `aud` | string | `"voxcall"` ou `"voxzap"` | Validar literal (tem que bater com sua plataforma) |
| `sub` | string | ID do usuário no VoxCRM | Apenas referência — **não use** para resolver usuário local |
| `email` | string | Email do usuário | Pode ser usado para fallback de mapeamento |
| `name` | string | Nome completo | Apenas display |
| `profile` | string | `SUPERADMIN`, `ADMIN`, `OPERADOR`, etc. | Mapear para perfil interno se necessário |
| `extension` | string | Ramal Asterisk (só VoxCall) | **Resolver usuário local** |
| `tenantId` | number | Tenant do operador (só VoxZap) | **Parte do par para resolver operador** |
| `operatorId` | number | ID do operador (só VoxZap) | **Parte do par para resolver operador** |
| `iat` | number (epoch s) | Quando foi emitido | Pode ignorar, JWT lib valida |
| `exp` | number (epoch s) | Expira em (iat + 900s) | Pode ignorar, JWT lib valida |

### 3.4 Algoritmo e Headers JWT

- **alg:** `HS256` (HMAC-SHA256) — fixo, não negociável.
- **typ:** `JWT` (default).
- **Assinatura:** HMAC-SHA256 do header.payload com a chave `VOXHUB_SHARED_SECRET` em **bytes UTF-8** da string hex (não decodificar hex em bytes — usar a string como está).

---

## 4. Status Codes — Tabela Resumida

| Cenário | Código |
|---|---|
| Segredo correto + tudo OK | `200` |
| Segredo ausente | `401` |
| Segredo presente mas errado | `401` |
| Token JWT malformado | `401` |
| Token JWT com assinatura inválida | `401` |
| Token JWT expirado | `401` |
| Token JWT com `iss` errado | `401` |
| Token JWT com `aud` errado | `401` |
| Mapeamento de usuário não encontrado | `401` (mensagem específica) |
| Erro interno (DB fora) | `500` |
| Body JSON malformado | `400` |
| Service-to-service desligado temporariamente | `503` |

> **Não use `403`** para casos de autenticação. Reserve `403` para casos onde o usuário **está** autenticado mas não tem permissão (não se aplica a esses endpoints).

---

## 5. Compatibilidade

- O frontend do VoxCRM espera **exatamente** esses paths e bodies. Mudar nomes ou status codes quebra a integração.
- Adicionar campos novos na response do `/auth-token` é seguro (frontend ignora extras).
- Adicionar headers extras na request é seguro (você pode logar mas não precisa validar).
