# Implementação Lado VoxZap — Código Pronto (Node.js + Express + TypeScript)

> Idêntico ao VoxCall em estrutura, com 2 diferenças:
> 1. `aud === "voxzap"` em vez de `voxcall`.
> 2. Resolução de usuário usa par `(tenantId, operatorId)` em vez de `extension`.
> 3. Tem o endpoint extra `GET /api/workspace/operators`.

---

## 1. Configuração — `src/config/voxhub.ts`

```typescript
const VOXHUB_SHARED_SECRET = process.env.VOXHUB_SHARED_SECRET;

if (!VOXHUB_SHARED_SECRET) {
  if (process.env.NODE_ENV === "production") {
    throw new Error(
      "VOXHUB_SHARED_SECRET não definida. " +
      "Gere com: openssl rand -hex 32 e configure no VoxCRM (Plataforma → Conexões)."
    );
  }
  console.warn("[voxhub] VOXHUB_SHARED_SECRET não definida — modo dev");
}

export const voxhubConfig = {
  sharedSecret: VOXHUB_SHARED_SECRET ?? "dev-only-insecure-secret",
  expectedIssuer: "voxcrm",
  expectedAudience: "voxzap" as const,
};
```

## 2. Middleware — `src/middleware/workspace-secret.ts`

(Idêntico ao VoxCall — copiar o arquivo.)

```typescript
import { Request, Response, NextFunction } from "express";
import { timingSafeEqual } from "node:crypto";
import { voxhubConfig } from "../config/voxhub";

export function requireWorkspaceSecret(
  req: Request,
  res: Response,
  next: NextFunction
) {
  const provided = req.header("x-workspace-secret") ?? "";
  const expected = voxhubConfig.sharedSecret;

  if (provided.length !== expected.length) {
    return res.status(401).json({ error: "invalid workspace secret" });
  }

  const a = Buffer.from(provided, "utf8");
  const b = Buffer.from(expected, "utf8");
  if (a.length !== b.length || !timingSafeEqual(a, b)) {
    return res.status(401).json({ error: "invalid workspace secret" });
  }

  next();
}
```

## 3. Service — `src/services/voxhub.service.ts`

```typescript
import jwt, { JwtPayload } from "jsonwebtoken";
import { voxhubConfig } from "../config/voxhub";

export interface VoxhubVoxzapClaims extends JwtPayload {
  iss: "voxcrm";
  aud: "voxzap";
  sub: string;
  email: string;
  name: string;
  profile: string;
  tenantId: number;
  operatorId: number;
}

export class VoxhubTokenError extends Error {
  constructor(public readonly reason: string) {
    super(reason);
  }
}

export function verifyVoxhubToken(token: string): VoxhubVoxzapClaims {
  let decoded: JwtPayload | string;
  try {
    decoded = jwt.verify(token, voxhubConfig.sharedSecret, {
      algorithms: ["HS256"],
      issuer: voxhubConfig.expectedIssuer,
      audience: voxhubConfig.expectedAudience,
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : "token inválido";
    throw new VoxhubTokenError(msg);
  }

  if (typeof decoded === "string" || !decoded) {
    throw new VoxhubTokenError("payload inválido");
  }

  const claims = decoded as VoxhubVoxzapClaims;
  if (typeof claims.tenantId !== "number" || typeof claims.operatorId !== "number") {
    throw new VoxhubTokenError("claims tenantId/operatorId ausentes ou inválidos");
  }

  return claims;
}
```

## 4. Rotas — `src/routes/workspace.ts`

```typescript
import { Router } from "express";
import { requireWorkspaceSecret } from "../middleware/workspace-secret";
import { verifyVoxhubToken, VoxhubTokenError } from "../services/voxhub.service";
import { findOperator, listOperators } from "../services/operator.service"; // suas funções
import { issueLocalSession } from "../services/auth.service";              // sua função

const router = Router();

router.get("/health", requireWorkspaceSecret, (_req, res) => {
  res.json({
    status: "ok",
    service: "voxzap",
    version: process.env.APP_VERSION ?? "dev",
    uptime_s: Math.floor(process.uptime()),
  });
});

router.get("/operators", requireWorkspaceSecret, async (_req, res) => {
  try {
    const data = await listOperators();
    res.json({ data });
  } catch (err) {
    console.error("[voxhub] operators error:", err);
    res.status(500).json({ error: "erro ao listar operadores" });
  }
});

router.post("/auth-token", async (req, res) => {
  const { token } = (req.body ?? {}) as { token?: string };
  const ip = req.ip ?? null;
  const ua = req.header("user-agent") ?? null;

  if (!token || typeof token !== "string") {
    return res.status(400).json({ error: "campo token obrigatório" });
  }

  try {
    const claims = verifyVoxhubToken(token);

    const operator = await findOperator(claims.tenantId, claims.operatorId);
    if (!operator || !operator.active) {
      console.warn("[voxhub] auth-token: operador não encontrado", {
        tenantId: claims.tenantId,
        operatorId: claims.operatorId,
        userId: claims.sub,
        ip,
      });
      return res.status(401).json({
        error: `operador ${claims.tenantId}:${claims.operatorId} não encontrado ou inativo`,
      });
    }

    const session = await issueLocalSession({
      operatorId: operator.id,
      tenantId: operator.tenantId,
      source: "voxhub",
      voxcrmUserId: claims.sub,
      voxcrmEmail: claims.email,
    });

    return res.json({
      token: session.token,
      user: {
        id: operator.id,
        tenantId: operator.tenantId,
        name: claims.name,
        email: claims.email,
        profile: claims.profile,
      },
      expiresAt: session.expiresAt,
    });
  } catch (err) {
    if (err instanceof VoxhubTokenError) {
      console.warn("[voxhub] auth-token: token inválido", {
        reason: err.reason,
        ip,
        ua,
      });
      return res.status(401).json({ error: err.reason });
    }
    console.error("[voxhub] auth-token: erro interno", err);
    return res.status(500).json({ error: "erro interno" });
  }
});

export default router;
```

## 5. Service de Operadores — `src/services/operator.service.ts`

```typescript
import { prisma } from "../lib/prisma";

export async function findOperator(tenantId: number, operatorId: number) {
  return prisma.operator.findFirst({
    where: { id: operatorId, tenantId, active: true },
    select: { id: true, tenantId: true, name: true, email: true, active: true },
  });
}

export async function listOperators() {
  return prisma.operator.findMany({
    where: {},
    orderBy: [{ tenantId: "asc" }, { name: "asc" }],
    select: { id: true, tenantId: true, name: true, email: true, active: true },
  });
}
```

> Adapte o nome do model (`Operator`, `User`, etc) à realidade do schema do VoxZap.

## 6. Registrar no app principal

```typescript
import workspaceRouter from "./routes/workspace";
app.use("/api/workspace", workspaceRouter);
```

## 7. Variáveis de Ambiente

```bash
VOXHUB_SHARED_SECRET=<output de openssl rand -hex 32>
NODE_ENV=production
```

## 8. Validação Manual

```bash
# 1) Health
curl -i \
  -H "X-Workspace-Secret: $VOXHUB_SHARED_SECRET" \
  https://voxzap.suaempresa.com/api/workspace/health

# 2) Operadores
curl -s \
  -H "X-Workspace-Secret: $VOXHUB_SHARED_SECRET" \
  https://voxzap.suaempresa.com/api/workspace/operators | jq

# Esperado: { "data": [ {id, tenantId, name, ...}, ... ] }
```
