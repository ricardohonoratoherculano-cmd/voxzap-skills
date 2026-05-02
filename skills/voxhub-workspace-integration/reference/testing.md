# Procedimento de Teste End-to-End

## Pré-requisitos

- Node 18+ instalado.
- `curl` e `jq`.
- `VOXHUB_SHARED_SECRET` definida no ambiente (mesma do VoxCRM).
- O serviço (VoxCall ou VoxZap) rodando localmente ou em URL acessível.

## 1. Gerar um Token de Teste (sem precisar do VoxCRM rodando)

Crie um arquivo temporário `gen-token.mjs`:

```javascript
import jwt from "jsonwebtoken";

const SECRET = process.env.VOXHUB_SHARED_SECRET;
if (!SECRET) {
  console.error("Defina VOXHUB_SHARED_SECRET");
  process.exit(1);
}

const KIND = process.argv[2] ?? "voxcall"; // "voxcall" ou "voxzap"

const basePayload = {
  iss: "voxcrm",
  aud: KIND,
  sub: "42",
  email: "agente@empresa.com",
  name: "João Silva",
  profile: "OPERADOR",
};

const payload = KIND === "voxcall"
  ? { ...basePayload, extension: "1042" }
  : { ...basePayload, tenantId: 5, operatorId: 12 };

const token = jwt.sign(payload, SECRET, { algorithm: "HS256", expiresIn: "15m" });
console.log(token);
```

Uso:
```bash
npm install jsonwebtoken
export VOXHUB_SHARED_SECRET="$(openssl rand -hex 32)"
node gen-token.mjs voxcall   # gera token VoxCall
node gen-token.mjs voxzap    # gera token VoxZap
```

## 2. Bateria de Testes — VoxCall

```bash
BASE="https://voxcall.suaempresa.com"  # ou http://localhost:PORT
SECRET="$VOXHUB_SHARED_SECRET"

# T1 — Health correto
curl -i -H "X-Workspace-Secret: $SECRET" "$BASE/api/workspace/health"
# Esperado: 200 OK + {"status":"ok",...}

# T2 — Health sem segredo
curl -i "$BASE/api/workspace/health"
# Esperado: 401

# T3 — Health com segredo errado
curl -i -H "X-Workspace-Secret: wrong" "$BASE/api/workspace/health"
# Esperado: 401

# T4 — auth-token sem body
curl -i -X POST -H "Content-Type: application/json" "$BASE/api/workspace/auth-token"
# Esperado: 400

# T5 — auth-token com token malformado
curl -i -X POST \
  -H "Content-Type: application/json" \
  -d '{"token":"abc"}' \
  "$BASE/api/workspace/auth-token"
# Esperado: 401 + {"error":"jwt malformed"}

# T6 — auth-token com token assinado por outro segredo
WRONG_TOKEN=$(VOXHUB_SHARED_SECRET=$(openssl rand -hex 32) node gen-token.mjs voxcall)
curl -i -X POST \
  -H "Content-Type: application/json" \
  -d "{\"token\":\"$WRONG_TOKEN\"}" \
  "$BASE/api/workspace/auth-token"
# Esperado: 401 + {"error":"invalid signature"}

# T7 — auth-token com token de aud errada (token VoxZap mandado pro VoxCall)
ZAP_TOKEN=$(node gen-token.mjs voxzap)
curl -i -X POST \
  -H "Content-Type: application/json" \
  -d "{\"token\":\"$ZAP_TOKEN\"}" \
  "$BASE/api/workspace/auth-token"
# Esperado: 401 + {"error":"jwt audience invalid..."}

# T8 — auth-token com token válido mas extension inexistente
# (o gen-token usa "1042" — se não existir no banco, deve retornar 401)
GOOD_TOKEN=$(node gen-token.mjs voxcall)
curl -i -X POST \
  -H "Content-Type: application/json" \
  -d "{\"token\":\"$GOOD_TOKEN\"}" \
  "$BASE/api/workspace/auth-token"
# Esperado se 1042 não existe: 401 + {"error":"ramal 1042 não encontrado..."}
# Esperado se 1042 existe e ativo: 200 + {token, user, expiresAt}

# T9 — auth-token com token expirado
# (modifique gen-token.mjs para expiresIn: "-1m" e gere)
EXPIRED=$(node gen-token-expired.mjs voxcall)
curl -i -X POST -H "Content-Type: application/json" \
  -d "{\"token\":\"$EXPIRED\"}" "$BASE/api/workspace/auth-token"
# Esperado: 401 + {"error":"jwt expired"}
```

## 3. Bateria de Testes — VoxZap

Mesmos casos T1–T9 trocando `aud` para `"voxzap"` e adicionando:

```bash
# T10 — operators sem segredo
curl -i "$BASE/api/workspace/operators"
# Esperado: 401

# T11 — operators com segredo correto
curl -s -H "X-Workspace-Secret: $SECRET" "$BASE/api/workspace/operators" | jq
# Esperado: 200 + {"data":[{"id":..,"tenantId":..,"name":..,...}]}
```

## 4. Teste Integrado com VoxCRM Real

1. **No VoxCRM:** acessar `Plataforma → Conexões` (precisa SUPERADMIN ou ADMIN).
2. **Criar conexão:**
   - Plataforma: VoxCall (ou VoxZap)
   - Nome: "Teste Local"
   - Base URL: `https://voxcall.suaempresa.com` (sem `/api/...`)
   - Segredo: o mesmo que está em `VOXHUB_SHARED_SECRET`
   - Conexão ativa: ✓
3. **Verificar** que o card mostra **ONLINE** logo após salvar (auto health-check).
4. **No VoxCRM:** `Plataforma → Mapeamento` — selecionar um usuário e:
   - VoxCall: preencher um ramal que existe (`extension` no DB do VoxCall).
   - VoxZap: selecionar um operador no dropdown (que veio do `/operators`).
5. **Logar como esse usuário** (não SUPERADMIN — use OPERADOR).
6. **DevTools → Network** — observar a chamada `GET /api/workspace/me` ao logar. Verificar:
   - `bundle.voxcall.token` ou `bundle.voxzap.token` deve ter um JWT.
   - `platforms.voxcall.status` ou `platforms.voxzap.status` deve ser `"ONLINE"`.
7. **(Quando Fase B/C estiverem prontas)** — disparar uma ação que chame o `/auth-token` da plataforma alvo e confirmar 200.

## 5. Checklist de Aceite Final

- [ ] T1 a T9 (T10/T11 só VoxZap) passam conforme o esperado.
- [ ] Health check do VoxCRM passa para ONLINE em <1s após salvar conexão.
- [ ] Token expirado é rejeitado com 401 (não 500).
- [ ] Token de outra audience é rejeitado com 401 (não 500).
- [ ] Token assinado por outro segredo é rejeitado com 401 (não 500).
- [ ] Login legado (username/senha direto) continua funcionando.
- [ ] Nenhum log contém o segredo em texto puro.
- [ ] Nenhum log contém o JWT bruto.
- [ ] Variável `VOXHUB_SHARED_SECRET` é obrigatória em produção (boot falha sem ela).
