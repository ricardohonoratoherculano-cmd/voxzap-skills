# Implementação Lado VoxCall — Código Pronto (Node.js + Express + TypeScript)

> Cole esses arquivos no projeto VoxCall ajustando apenas:
> - Path do banco (Prisma/Sequelize/Knex/etc) para resolver o ramal.
> - Função que cria a sessão local (já existe no fluxo de login legado).

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
  expectedAudience: "voxcall" as const,
};
```

## 2. Middleware — `src/middleware/workspace-secret.ts`

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

export interface VoxhubVoxcallClaims extends JwtPayload {
  iss: "voxcrm";
  aud: "voxcall";
  sub: string;
  email: string;
  name: string;
  profile: string;
  extension: string;
}

export class VoxhubTokenError extends Error {
  constructor(public readonly reason: string) {
    super(reason);
  }
}

export function verifyVoxhubToken(token: string): VoxhubVoxcallClaims {
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

  const claims = decoded as VoxhubVoxcallClaims;
  if (!claims.extension || typeof claims.extension !== "string") {
    throw new VoxhubTokenError("claim extension ausente");
  }

  return claims;
}
```

## 4. Rotas — `src/routes/workspace.ts`

```typescript
import { Router } from "express";
import { requireWorkspaceSecret } from "../middleware/workspace-secret";
import { verifyVoxhubToken, VoxhubTokenError } from "../services/voxhub.service";
import { findExtensionByNumber } from "../services/extension.service"; // sua função existente
import { issueLocalSession } from "../services/auth.service";          // sua função existente

const router = Router();

router.get("/health", requireWorkspaceSecret, (_req, res) => {
  res.json({
    status: "ok",
    service: "voxcall",
    version: process.env.APP_VERSION ?? "dev",
    uptime_s: Math.floor(process.uptime()),
  });
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

    const extension = await findExtensionByNumber(claims.extension);
    if (!extension || !extension.active) {
      console.warn("[voxhub] auth-token: ramal não encontrado", {
        extension: claims.extension,
        userId: claims.sub,
        ip,
      });
      return res.status(401).json({
        error: `ramal ${claims.extension} não encontrado ou inativo`,
      });
    }

    const session = await issueLocalSession({
      userId: extension.userId,
      extension: extension.number,
      source: "voxhub",
      voxcrmUserId: claims.sub,
      voxcrmEmail: claims.email,
    });

    return res.json({
      token: session.token,
      user: {
        id: extension.userId,
        name: claims.name,
        email: claims.email,
        extension: extension.number,
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

## 5. Registrar no app principal — `src/app.ts` (ou `index.ts`)

```typescript
import workspaceRouter from "./routes/workspace";
// ...
app.use("/api/workspace", workspaceRouter);
```

## 6. `findExtensionByNumber` — exemplo (Prisma)

> Use o ORM/driver que o VoxCall já tem. Esse é só um esqueleto.

```typescript
import { prisma } from "../lib/prisma";

export async function findExtensionByNumber(number: string) {
  return prisma.extension.findFirst({
    where: { number, active: true },
    select: { id: true, number: true, userId: true, active: true },
  });
}
```

## 7. `issueLocalSession` — adaptar ao fluxo legado

Use exatamente a mesma função que o login normal do VoxCall já chama (que monta o JWT/cookie da sessão local). O ponto-chave é: **não reinvente sessão**, reutilize a infra que já existe.

```typescript
// Exemplo se o VoxCall já tem auth.service com createSessionForUser()
export async function issueLocalSession(input: {
  userId: number;
  extension: string;
  source: "voxhub";
  voxcrmUserId: string;
  voxcrmEmail: string;
}) {
  const user = await prisma.user.findUniqueOrThrow({ where: { id: input.userId } });
  const session = await createSessionForUser(user, {
    source: input.source,
    metadata: { voxcrmUserId: input.voxcrmUserId, voxcrmEmail: input.voxcrmEmail },
  });
  return session; // { token: string, expiresAt: string }
}
```

## 8. Variáveis de Ambiente

```bash
# .env
VOXHUB_SHARED_SECRET=<output de openssl rand -hex 32>
NODE_ENV=production
```

## 9. Dependências

```bash
npm install jsonwebtoken
npm install -D @types/jsonwebtoken
```

(Express, Prisma, etc — já presentes no projeto.)

## 10. Validação Manual

```bash
# 1) Health check com segredo correto
curl -i \
  -H "X-Workspace-Secret: $VOXHUB_SHARED_SECRET" \
  https://voxcall.suaempresa.com/api/workspace/health

# Esperado: HTTP 200 + {"status":"ok",...}

# 2) Health check com segredo errado
curl -i \
  -H "X-Workspace-Secret: wrong" \
  https://voxcall.suaempresa.com/api/workspace/health

# Esperado: HTTP 401

# 3) Token inválido
curl -i -X POST \
  -H "Content-Type: application/json" \
  -d '{"token":"abc"}' \
  https://voxcall.suaempresa.com/api/workspace/auth-token

# Esperado: HTTP 401 + {"error":"jwt malformed"}
```

Para gerar um token de teste válido, use o snippet em [testing.md](testing.md).
