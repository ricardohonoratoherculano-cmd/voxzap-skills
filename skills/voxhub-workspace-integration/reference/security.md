# Segurança — VoxHub Workspace

## Geração de Chaves

### Segredo compartilhado por conexão

```bash
openssl rand -hex 32
```

- 32 bytes (256 bits) = 64 caracteres hexadecimais.
- **Único por instalação**. Ambientes diferentes (dev/staging/prod) devem ter segredos diferentes.
- **Único por kind**. Conexão VoxCall e conexão VoxZap, mesmo na mesma instalação, têm segredos diferentes.

## Onde Armazenar

| Local | Forma | Quem acessa |
|---|---|---|
| **VoxCRM** (este lado) | Criptografado AES-256-GCM em `platform_connections.shared_secret` (chave: `WORKSPACE_SECRET_KEY`) | Apenas o backend do VoxCRM, nunca exposto ao browser |
| **VoxCall / VoxZap** (outro lado) | Variável de ambiente `VOXHUB_SHARED_SECRET` | Apenas o backend |

> **NUNCA** comite segredos no git. **NUNCA** retorne em endpoints. **NUNCA** logue em texto puro.

## Comparação de Segredos

Sempre use `crypto.timingSafeEqual` (Node) ou equivalente. Comparação `===` em string vaza o tempo de comparação e permite **timing attacks** em larga escala (especialmente comum em segredos curtos).

```typescript
// ❌ ERRADO
if (provided === expected) { ... }

// ✅ CORRETO
const a = Buffer.from(provided, "utf8");
const b = Buffer.from(expected, "utf8");
if (a.length === b.length && crypto.timingSafeEqual(a, b)) { ... }
```

## Validação de JWT

Use sempre uma biblioteca consagrada (`jsonwebtoken` no Node, `pyjwt` em Python, etc). **NUNCA** decodifique e valide manualmente.

Configure os 3 verificadores obrigatórios:

```typescript
jwt.verify(token, secret, {
  algorithms: ["HS256"],   // ← previne ataque "alg: none" e confusão HS↔RS
  issuer:    "voxcrm",     // ← previne aceitar token de outro issuer
  audience:  "voxcall",    // ← previne reuso de token entre VoxCall/VoxZap
});
```

> O ataque "alg: none" é histórico e ainda recorrente. Sempre fixar `algorithms` em allowlist.

## TTL e Renovação

- Token cross-platform: **15 minutos** (definido pelo VoxCRM, não negociável).
- Sessão local emitida pelo `/auth-token`: **TTL padrão da plataforma** (tipicamente 8h ou similar).
- O frontend do VoxCRM renova o bundle 60s antes de expirar.
- **Não tente cachear o token cross-platform** no servidor da plataforma além da request — ele é one-shot.

## Rotação de Segredos

Procedimento sem downtime:

1. Gerar segredo novo: `openssl rand -hex 32`.
2. **No VoxCRM:** atualizar a conexão (campo "Novo Segredo Compartilhado") e salvar.
3. **No VoxCall/VoxZap:** atualizar `VOXHUB_SHARED_SECRET` no ambiente e fazer rolling restart.
4. Health check no VoxCRM já dispara automaticamente após o update da conexão — confirmar ONLINE.

> Se houver janela em que os dois lados ficam dessincronizados, tokens emitidos com o segredo antigo serão rejeitados (HTTP 401). Os usuários ativos receberão 401 nas chamadas até o próximo refresh do bundle (até 30s). Aceitável para a maioria dos cenários.

## Logs e Auditoria

**Logar:**
- Tentativas de health check com segredo errado (IP, UA).
- Tentativas de `/auth-token` rejeitadas (motivo, IP, UA, claim `sub` se decodificável).
- Sucessos de `/auth-token` (userId resolvido, IP).

**NUNCA logar:**
- O segredo compartilhado (em qualquer formato).
- O token JWT bruto.
- O payload decodificado completo (apenas claims relevantes para auditoria).

## Modelo de Ameaça — Resumo

| Ameaça | Mitigação |
|---|---|
| Atacante intercepta o segredo | TLS obrigatório (HTTPS) em produção |
| Atacante força um token (alg: none) | Allowlist `algorithms: ["HS256"]` |
| Atacante reusa token de VoxCall no VoxZap | Validação de `aud` |
| Atacante usa token expirado | Validação automática de `exp` na lib JWT |
| Timing attack no segredo | `timingSafeEqual` |
| Vazamento via log | Política de logging acima |
| Vazamento via response | Nunca retornar o segredo, mesmo para admin |

## Headers de Resposta Recomendados

```typescript
res.setHeader("Cache-Control", "no-store");
res.setHeader("X-Content-Type-Options", "nosniff");
```

Para `/auth-token` especialmente — a resposta contém o JWT da sessão local e não pode ser cacheada por proxy.
