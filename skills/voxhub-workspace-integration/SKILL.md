---
name: voxhub-workspace-integration
description: Implementa o lado servidor (VoxCall e/ou VoxZap) da integração SSO unificada com o VoxCRM (VoxHub Workspace). Use quando o agente estiver trabalhando dentro do projeto VoxCall ou VoxZap e precisar expor os endpoints `/api/workspace/health`, `/api/workspace/auth-token` e (só VoxZap) `/api/workspace/operators` para que o VoxCRM atue como Identity Provider central. Inclui contrato exato dos JWTs HS256, código pronto em Node/Express + TypeScript, validação de claims, mapeamento de usuários e procedimento de teste end-to-end com curl.
---

# VoxHub Workspace Integration — Lado Servidor (VoxCall / VoxZap)

## Quando Ativar

Ative esta skill quando estiver no projeto **VoxCall** ou **VoxZap** e o usuário pedir qualquer variação de:

- "Integrar VoxCall/VoxZap com VoxCRM"
- "Implementar o SSO do VoxHub"
- "Expor os endpoints do workspace"
- "Implementar /api/workspace/health"
- "Validar token vindo do VoxCRM"
- "Conectar com o IdP central"
- "Fase A do VoxHub do lado servidor"

**NÃO ativar** quando estiver no projeto VoxCRM — lá a integração já está pronta (Task #10 mergeada).

## Contexto: O que é o VoxHub Workspace

O **VoxCRM** é o **Identity Provider central** (Opção C — Workspace Unificado). Ele autentica o usuário com email + senha, emite seu próprio JWT (8h) e, em paralelo, emite **tokens cross-platform** (HS256, 15 minutos) que o frontend usa para chamar VoxCall e VoxZap diretamente.

```
Usuário → Login no VoxCRM → JWT VoxCRM + bundle { voxcall, voxzap }
                          → frontend chama VoxCall/VoxZap com os tokens do bundle
                          → VoxCall/VoxZap validam o token e abrem sessão local
```

**Sua missão (deste lado):** expor os endpoints que o VoxCRM precisa, validar os JWTs que ele emite, e devolver uma sessão local da plataforma.

## Os 3 Endpoints que Você Precisa Implementar

| Endpoint | Quem chama | Propósito | Obrigatório? |
|---|---|---|---|
| `GET /api/workspace/health` | VoxCRM (server-to-server) | Health check com segredo compartilhado | **SIM** |
| `POST /api/workspace/auth-token` | Frontend (browser) | Trocar JWT do VoxCRM por sessão local | **SIM** |
| `GET /api/workspace/operators` | VoxCRM (server-to-server) | Lista operadores para mapeamento | **SIM no VoxZap, não existe no VoxCall** |

Detalhes completos do contrato em [reference/contract.md](reference/contract.md).

## Procedimento de Implementação

Siga **na ordem**. Não pule passos — cada um valida o anterior.

### Passo 1 — Configurar segredo compartilhado

1. Garantir que existe a env `VOXHUB_SHARED_SECRET` (ou nome equivalente já adotado no projeto).
2. Documentar que o valor deve ser gerado com `openssl rand -hex 32` e ser **idêntico** ao cadastrado em `Plataforma → Conexões` do VoxCRM.
3. Em produção, falhar no boot se a env não estiver definida.

### Passo 2 — Implementar `GET /api/workspace/health`

Endpoint simples, sem dependência de banco. Validar header `X-Workspace-Secret` por **comparação em tempo constante** (`crypto.timingSafeEqual`).

Código pronto: ver [reference/voxcall-impl.md](reference/voxcall-impl.md) (idem para VoxZap).

### Passo 3 — Implementar `POST /api/workspace/auth-token`

1. Receber `{ token: string }` no body.
2. Validar HS256 com `VOXHUB_SHARED_SECRET`.
3. Validar claims: `iss === "voxcrm"`, `aud === "voxcall"` (ou `"voxzap"`), `exp > now`.
4. Resolver usuário local pelos claims:
   - **VoxCall:** procurar ramal pelo claim `extension`.
   - **VoxZap:** procurar operador por `tenantId` + `operatorId`.
5. Retornar a sessão local no formato que a plataforma já usa (cookie/JWT próprio + dados do user).
6. Se token inválido/expirado/sem mapeamento: HTTP 401.

Código pronto: ver [reference/voxcall-impl.md](reference/voxcall-impl.md) e [reference/voxzap-impl.md](reference/voxzap-impl.md).

### Passo 4 — (Só VoxZap) Implementar `GET /api/workspace/operators`

Listar operadores ativos com `{ id, tenantId, name, email, active }`. Mesma autenticação por `X-Workspace-Secret`.

### Passo 5 — Testar com curl

Procedimento completo em [reference/testing.md](reference/testing.md). Em resumo:

1. `curl -i -H 'X-Workspace-Secret: <secret>' https://<sua-base>/api/workspace/health` → deve retornar 200.
2. No VoxCRM, `Plataforma → Conexões → Verificar` deve mudar para **ONLINE** em <1s.
3. Logar como agente no VoxCRM, abrir DevTools e verificar que `useWorkspace()` carrega o bundle.
4. Tentar uma ação que dispare uso do token (softphone/chat) e confirmar que o `/auth-token` retorna a sessão.

## Regras Inegociáveis

1. **HS256 com o mesmo segredo**. Não use RS256, não derive a chave. Pegue exatamente o valor de `VOXHUB_SHARED_SECRET`.
2. **Comparar segredos em tempo constante** com `crypto.timingSafeEqual`. Comparação `===` em string vaza tempo.
3. **TTL do token: 15 minutos**. O frontend renova proativamente — não tente estender.
4. **Validar `iss` e `aud`** sempre. Token de VoxCall não pode ser aceito no VoxZap (e vice-versa).
5. **Sessão local emitida pelo `/auth-token` deve ter TTL longo** (típico: o mesmo da sessão legada da plataforma). O JWT VoxCRM é só a "porta de entrada".
6. **Mapeamento ausente = HTTP 401**, não 500. É um cenário esperado, não um bug.
7. **Nunca retornar o segredo em nenhum endpoint**. Mesmo para admin local.
8. **Logar tentativas inválidas** com IP + user-agent para auditoria, mas sem incluir o token bruto.

## Compatibilidade com Login Legado

A integração SSO é **additive**. O endpoint legado de login da plataforma (e.g. `POST /auth/login` com username/senha local) continua funcionando para os 4 clientes standalone que existem hoje. O `/api/workspace/auth-token` é uma porta de entrada **adicional**, não substitui nada.

## Estrutura de Arquivos Sugerida

```
src/
├── routes/
│   └── workspace.ts          # rotas /api/workspace/*
├── services/
│   └── voxhub.service.ts     # validação de JWT + resolução de user
├── middleware/
│   └── workspace-secret.ts   # valida X-Workspace-Secret
└── config/
    └── voxhub.ts             # env VOXHUB_SHARED_SECRET + validação no boot
```

## Referências

- [reference/contract.md](reference/contract.md) — Contrato exato dos endpoints e dos JWTs (claims, headers, status codes).
- [reference/voxcall-impl.md](reference/voxcall-impl.md) — Código pronto para o VoxCall (Node/Express/TS).
- [reference/voxzap-impl.md](reference/voxzap-impl.md) — Código pronto para o VoxZap (Node/Express/TS) + endpoint /operators.
- [reference/security.md](reference/security.md) — Geração de chaves, rotação de segredos, mitigação de ataques.
- [reference/testing.md](reference/testing.md) — Procedimento de teste end-to-end com curl + checklist de validação.

## Definition of Done

- [ ] `GET /api/workspace/health` responde 200 com segredo correto e 401 com segredo errado.
- [ ] `POST /api/workspace/auth-token` aceita JWT válido e retorna sessão local.
- [ ] `POST /api/workspace/auth-token` rejeita JWT com `iss` errado, `aud` errado, expirado ou assinado com segredo diferente.
- [ ] (VoxZap) `GET /api/workspace/operators` retorna `{ data: [...] }` com operadores ativos.
- [ ] Env `VOXHUB_SHARED_SECRET` é obrigatória em produção (boot falha se ausente).
- [ ] No VoxCRM, a conexão correspondente aparece como **ONLINE**.
- [ ] Login legado direto na plataforma continua funcionando.
- [ ] Tentativas inválidas geram log de auditoria com IP+UA (sem o token).
