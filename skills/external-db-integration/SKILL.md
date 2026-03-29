---
name: external-db-integration
description: Framework profissional para integração com bancos de dados externos de parceiros/clientes. Use quando precisar configurar, mapear, consultar ou integrar qualquer banco de dados externo (MSSQL, PostgreSQL, MySQL, Oracle) com os sistemas VoxCALL/VoxZAP. Inclui arquitetura de conexão, padrões de segurança, templates de mapeamento, e integração com assistentes de IA.
---

# Framework de Integração com Bancos de Dados Externos

## 1. Visão Geral

O sistema de External DB Integrations permite ao SuperAdmin configurar e consultar bancos de dados externos (CRM/ERP de clientes) de forma segura, com criptografia de credenciais, validação de queries, mascaramento de dados sensíveis, e rate limiting.

### Capacidades
- **Consulta em tempo real** a bancos MSSQL de clientes/parceiros
- **Browser de schema** — lista tabelas, colunas, foreign keys
- **Query executor** seguro — somente SELECT, com mascaramento automático
- **3 métodos de acesso** — direto, SSH tunnel, VPN + SSH tunnel
- **Integração com Assistente de IA** — queries automáticas via chat

### Integrações Ativas
| Cliente/Parceiro | Sistema | Banco | Método de Acesso | Skill Específica |
|-------------------|---------|-------|-------------------|------------------|
| Actyon | Smartcob (CRM Cobrança) | MSSQL | Direto — 189.36.205.250:31433 | `actyon-crm` |
| S4E/Ortoclin | Izysoft (Discador) | MSSQL | VPN — 172.22.138.24:1433 via VPN PlanoClin_S4E | `s4e-crm` |

---

## 2. Modelo Prisma

```prisma
model ExternalIntegrations {
  id              Int       @id @default(autoincrement())
  tenantId        Int
  name            String    @db.VarChar(255)
  slug            String    @db.VarChar(100)       // Identificador único por tenant
  dbType          String    @default("mssql") @db.VarChar(50)
  host            String    @db.VarChar(512)
  port            Int       @default(1433)
  database        String    @db.VarChar(255)
  username        String    @db.VarChar(512)
  password        String    @db.VarChar(512)        // ENCRYPTED (AES-256-CBC)
  accessMethod    String    @default("direct") @db.VarChar(50) // direct|ssh-tunnel|vpn
  sshHost         String?   @db.VarChar(255)
  sshPort         Int?      @default(22)
  sshUser         String?   @db.VarChar(255)
  sshPassword     String?   @db.VarChar(512)        // ENCRYPTED
  vpnConfigId     Int?                               // FK → VpnConfigurations.id
  options         String?   @db.Text                 // JSON: requestTimeout, connectTimeout, encrypt
  status          String    @default("inactive") @db.VarChar(50) // inactive|active|error
  lastTestedAt    DateTime? @db.Timestamptz(6)
  lastTestResult  String?   @db.VarChar(50)          // pass|fail
  createdAt       DateTime  @default(now()) @db.Timestamptz(6)
  updatedAt       DateTime  @default(now()) @db.Timestamptz(6)

  @@unique([tenantId, slug], map: "idx_external_integrations_tenant_slug")
  @@index([tenantId], map: "idx_external_integrations_tenantid")
  @@map("ExternalIntegrations")
}
```

### Campos Importantes
| Campo | Encrypted | Descrição |
|-------|-----------|-----------|
| `password` | ✅ | Senha do banco externo |
| `sshPassword` | ✅ | Senha SSH (para ssh-tunnel direto, sem VPN) |
| `slug` | ❌ | Unique por tenant: `[tenantId, slug]` |
| `accessMethod` | ❌ | `direct`, `ssh-tunnel`, ou `vpn` |
| `vpnConfigId` | ❌ | Referência a VpnConfigurations (para método `vpn`) |
| `options` | ❌ | JSON com opções MSSQL (requestTimeout, connectTimeout, encrypt) |

---

## 3. Criptografia AES-256-CBC

```typescript
import crypto from "crypto";

function getEncryptionKey(): string {
  const secret = process.env.SESSION_SECRET;
  if (!secret) throw new Error("SESSION_SECRET environment variable is required");
  return secret.padEnd(32, "0").substring(0, 32);
}

const IV_LENGTH = 16;

function encrypt(text: string): string {
  const iv = crypto.randomBytes(IV_LENGTH);
  const cipher = crypto.createCipheriv("aes-256-cbc", Buffer.from(getEncryptionKey()), iv);
  let encrypted = cipher.update(text, "utf8", "hex");
  encrypted += cipher.final("hex");
  return iv.toString("hex") + ":" + encrypted;
}

function decrypt(text: string): string {
  try {
    const parts = text.split(":");
    if (parts.length !== 2) return text;
    const iv = Buffer.from(parts[0], "hex");
    const decipher = crypto.createDecipheriv("aes-256-cbc", Buffer.from(getEncryptionKey()), iv);
    let decrypted = decipher.update(parts[1], "hex", "utf8");
    decrypted += decipher.final("utf8");
    return decrypted;
  } catch {
    return text;
  }
}
```

**Formato armazenado:** `iv_hex:encrypted_hex`
**Chave:** `SESSION_SECRET` padded com "0" para 32 bytes
**Mesma implementação** em `vpn.service.ts` e `external-db.service.ts`

---

## 4. Import do MSSQL — BUG CRÍTICO

### ⚠️ NUNCA usar `import * as sql from "mssql"`

Com `tsx` (ESM mode), o `import *` coloca todos os exports sob `default`, causando:
```
TypeError: sql.ConnectionPool is not a constructor
```

### ✅ Import correto:
```typescript
import mssqlModule from "mssql";
const sql = mssqlModule;
```

Isso garante que `sql.ConnectionPool`, `sql.VarChar`, etc., funcionem corretamente.

---

## 5. Métodos de Acesso

### 5.1 Direct
Conexão direta ao MSSQL via rede pública.
```
App → mssql driver → host:port → DB
```
**Quando usar:** Banco acessível pela internet (ex: Actyon em 189.36.205.250:31433)

### 5.2 SSH Tunnel
SSH tunnel via `ssh2` com port forwarding local.
```
App → ssh2 → VPS → net.createServer(localPort) → forwardOut → host:port → DB
```
**Quando usar:** Banco em rede privada, acessível via SSH no VPS do cliente

### 5.3 VPN (VPN + SSH Tunnel)
Primeiro conecta VPN (via VpnConfigurations), depois usa SSH tunnel pela VPN.
```
App → VPN(OpenVPN no VPS) → SSH tunnel → host:port → DB
```
**Quando usar:** Banco em rede totalmente isolada (ex: S4E em 172.22.138.24)

### Fluxo de Resolução
```typescript
async function resolveVpnSshConfig(vpnConfigId: number | null, tenantId: number) {
  if (!vpnConfigId) return null;
  const vpnConfig = await prisma.vpnConfigurations.findFirst({
    where: { id: vpnConfigId, tenantId }  // ← TENANT-SCOPED (cross-tenant protection)
  });
  if (!vpnConfig) throw new Error("VPN não encontrada ou não pertence ao seu tenant");
  if (vpnConfig.status !== "connected") throw new Error("VPN não está conectada");
  return {
    sshHost: vpnConfig.sshHost,
    sshPort: vpnConfig.sshPort,
    sshUser: vpnConfig.sshUser,
    sshPassword: decrypt(vpnConfig.sshPassword),
  };
}
```

### SSH Tunnel Implementation
```typescript
const localPort = 30000 + Math.floor(Math.random() * 10000);

const server = net.createServer((socket) => {
  sshClient.forwardOut("127.0.0.1", localPort, config.host, config.port, (err, stream) => {
    if (err) { socket.end(); return; }
    stream.pipe(socket);
    socket.pipe(stream);
    stream.on("close", () => socket.destroy());
    socket.on("close", () => stream.destroy());
  });
});

server.listen(localPort, "127.0.0.1", async () => {
  const pool = new sql.ConnectionPool({
    server: "127.0.0.1",
    port: localPort,
    // ... config
  });
  await pool.connect();
});
```

### Connection Pool Config
```typescript
const pool = new sql.ConnectionPool({
  server: host,
  port: port,
  database: database,
  user: username,
  password: password,
  options: {
    encrypt: false,
    trustServerCertificate: true,
    requestTimeout: 30000,
    connectTimeout: 15000,
  },
  pool: { min: 1, max: 3, idleTimeoutMillis: 30000 },
});
```

---

## 6. Segurança

### 6.1 Validação de Query (SELECT only)
```typescript
function validateSelectOnly(query: string): void {
  const normalized = query.trim();
  // Bloqueia múltiplos statements
  if (/;\s*\S/.test(normalized)) throw new Error("Múltiplos statements não são permitidos");

  const upper = normalized.replace(/;+\s*$/, "").toUpperCase().trim();
  // Somente SELECT ou WITH (CTE)
  if (!upper.startsWith("SELECT") && !upper.startsWith("WITH"))
    throw new Error("Somente queries SELECT são permitidas");

  // Bloqueia operações destrutivas
  if (/\b(DROP|DELETE|INSERT|UPDATE|ALTER|EXEC|EXECUTE|TRUNCATE|CREATE|GRANT|REVOKE)\b/i.test(normalized))
    throw new Error("Operação proibida detectada");

  // Bloqueia SELECT INTO
  if (/\bINTO\b/i.test(normalized)) throw new Error("SELECT INTO não é permitido");

  // Bloqueia comentários SQL (possíveis bypasses)
  if (/--/.test(normalized) || /\/\*/.test(normalized))
    throw new Error("Comentários SQL não são permitidos");

  // Bloqueia tabelas sensíveis
  for (const blocked of BLOCKED_TABLES) {
    if (upper.includes(blocked.toUpperCase()))
      throw new Error(`Acesso à tabela '${blocked}' não é permitido`);
  }
}
```

### 6.2 Tabelas Bloqueadas
```typescript
const BLOCKED_TABLES = [
  "tboperador", "tbparametro", "tbusuario", "tbconfig",
  "sysdiagrams", "sys.", "INFORMATION_SCHEMA.",
];
```

### 6.3 Mascaramento de Dados Sensíveis
```typescript
const SENSITIVE_COLUMNS = [
  "CPF", "CNPJ", "FONE", "CELULAR", "EMAIL", "TELEFONE",
  "RG", "SENHA", "PASSWORD", "TOKEN", "SECRET",
];
```

**Regras de mascaramento:**
| Tipo | Formato | Exemplo |
|------|---------|---------|
| CPF/CNPJ | `XXX***XX` | `123***89` |
| Fone/Celular | `XX****XXXX` | `11****5678` |
| Email | `X***@domain` | `j***@email.com` |
| Outros | `***` | `***` |

### 6.4 Rate Limiting
```typescript
const RATE_LIMIT_PER_MINUTE = 30;
// Key: `${integrationId}-${userId}`
// Janela: 60 segundos (sliding window)
```

### 6.5 Query Audit Logging
```
[ExternalDB] integration=1 user=5 duration=85ms success=true query="SELECT TOP 10..." at=2026-03-28T...
```

### 6.6 Retry com Backoff Exponencial
```typescript
async function withRetry<T>(fn: () => Promise<T>, maxRetries = 2, baseDelay = 1000): Promise<T> {
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try { return await fn(); }
    catch (error: any) {
      if (attempt === maxRetries) throw error;
      await new Promise(r => setTimeout(r, baseDelay * Math.pow(2, attempt)));
    }
  }
  throw new Error("Unreachable");
}
```

### 6.7 TOP automático
Se a query não contém `TOP`, o sistema injeta `SELECT TOP {maxRows}` automaticamente:
```typescript
if (!/\bTOP\b/i.test(finalQuery)) {
  finalQuery = finalQuery.replace(/^SELECT\s/i, `SELECT TOP ${maxRows} `);
}
```

---

## 7. Service (`server/services/external-db.service.ts`)

### Funções Exportadas

| Função | Descrição | Parâmetros |
|--------|-----------|------------|
| `listIntegrations(tenantId)` | Lista todas as integrações | Tenant-scoped |
| `getIntegration(id, tenantId)` | Busca por ID | Passwords mascaradas na saída |
| `createIntegration(tenantId, data)` | Cria nova integração | Encrypt de password/sshPassword |
| `updateIntegration(id, tenantId, data)` | Atualiza integração | Fecha conexão ativa antes |
| `deleteIntegration(id, tenantId)` | Remove integração | Fecha conexão + deleta |
| `testConnectivity(id, tenantId)` | Testa conexão | 3 testes: connection, query, table_count |
| `getSchema(id, tenantId)` | Lista tabelas | Filtra tabelas bloqueadas |
| `getTableColumns(id, tenantId, table)` | Colunas de uma tabela | Via INFORMATION_SCHEMA |
| `getTableForeignKeys(id, tenantId, table)` | Foreign keys | Via sys.foreign_keys |
| `executeQuery(id, tenantId, query, maxRows, userId)` | Executa SELECT | Rate limit + validação + mascaramento |
| `seedDefaultIntegrations(tenantId)` | Seed integrações padrão | Actyon + S4E |

### Active Connections Cache
```typescript
const activeConnections = new Map<number, {
  pool: sql.ConnectionPool;
  sshClient?: SSHClient;
  localServer?: net.Server;
}>();
```
Conexões são reutilizadas entre requests. Fechadas quando a integração é atualizada ou deletada.

### Output Masking
Todas as funções que retornam integrações mascaram `password` e `sshPassword` como `"***"`.

---

## 8. API Routes

**Base path:** `/api/external-integrations`
**Autenticação:** `authenticateToken` (JWT)
**Autorização:** SuperAdmin only
**Tenant-scoping:** `tenantId` do JWT

### Endpoints

| Método | Rota | Descrição | Body/Params |
|--------|------|-----------|-------------|
| `GET` | `/api/external-integrations` | Listar integrações | — |
| `GET` | `/api/external-integrations/:id` | Detalhes | — |
| `POST` | `/api/external-integrations` | Criar | `{ name, slug, dbType, host, port, database, username, password, accessMethod, ssh*, vpnConfigId?, options? }` |
| `PUT` | `/api/external-integrations/:id` | Atualizar | Campos parciais |
| `DELETE` | `/api/external-integrations/:id` | Remover | — |
| `POST` | `/api/external-integrations/:id/test` | Testar conectividade | — |
| `GET` | `/api/external-integrations/:id/schema` | Listar tabelas | — |
| `GET` | `/api/external-integrations/:id/columns/:table` | Colunas de tabela | `:table` = nome da tabela |
| `GET` | `/api/external-integrations/:id/foreign-keys/:table` | Foreign keys | `:table` = nome da tabela |
| `POST` | `/api/external-integrations/:id/query` | Executar query | `{ query, maxRows? }` |

### Resposta do Teste
```json
{
  "success": true,
  "tests": [
    { "name": "db_connection", "status": "pass", "durationMs": 1200 },
    { "name": "simple_query", "status": "pass", "durationMs": 85 },
    { "name": "table_count", "status": "pass", "durationMs": 120, "message": "236 tabelas" }
  ]
}
```

---

## 9. Seed de Integrações Padrão

```typescript
interface DefaultIntegration {
  name: string;
  slug: string;
  dbType: string;
  host: string;
  port: number;
  database: string;
  username: string;
  password: string;
  accessMethod: string;
  sshHost: string | null;
  sshPort: number;
  sshUser: string | null;
  sshPassword: string | null;
  vpnConfigId: number | null;
}
```

**Integrações padrão no seed:**
1. **Actyon Smartcob** — `direct`, 189.36.205.250:31433, dbActyon_Smartcob
2. **S4E Izysoft** — `vpn`, 172.22.138.24:1433, Izysoft, vpnConfigId auto-linked

O seed busca automaticamente o primeiro VpnConfigurations do tenant para linkar com a S4E.

---

## 10. Frontend (`client/src/pages/external-integrations.tsx`)

### Componentes
- **Cards de integração:** Status, nome, tipo, host, método de acesso
- **Formulário de criação/edição:** Campos dinâmicos baseados no `accessMethod`
- **Schema Browser:** Lista tabelas → click para ver colunas → click para ver FKs
- **Query Executor:** Editor SQL com botão executar, resultado em tabela paginada
- **Teste de conectividade:** Botão com resultados em lista de checks

### Campos condicionais no formulário
| accessMethod | Campos visíveis |
|--------------|----------------|
| `direct` | host, port, database, username, password |
| `ssh-tunnel` | + sshHost, sshPort, sshUser, sshPassword |
| `vpn` | + vpnConfigId (select das VPNs do tenant) |

---

## 11. Integração com VPN Management

Quando `accessMethod = "vpn"`:
1. O campo `vpnConfigId` referencia `VpnConfigurations.id`
2. A VPN deve estar com `status = "connected"` para funcionar
3. A função `resolveVpnSshConfig()` valida tenant ownership (cross-tenant protection)
4. As credenciais SSH da VPN são usadas para criar o tunnel

**Fluxo completo VPN → DB:**
```
1. Verificar VPN status === "connected" (tenant-scoped)
2. Extrair sshHost/sshPort/sshUser/sshPassword da VPN
3. Criar SSH tunnel (127.0.0.1:randomPort → dbHost:dbPort)
4. Conectar MSSQL via localhost:randomPort
5. Executar query
```

---

## 12. Schema Discovery Queries

### Listar Tabelas (MSSQL)
```sql
SELECT
  t.TABLE_SCHEMA as [schema],
  t.TABLE_NAME as [name],
  p.rows as [rowCount]
FROM INFORMATION_SCHEMA.TABLES t
LEFT JOIN sys.partitions p ON p.object_id = OBJECT_ID(t.TABLE_SCHEMA + '.' + t.TABLE_NAME)
  AND p.index_id IN (0, 1)
WHERE t.TABLE_TYPE = 'BASE TABLE'
ORDER BY t.TABLE_SCHEMA, t.TABLE_NAME
```

### Colunas (MSSQL)
```sql
SELECT
  COLUMN_NAME as [name],
  DATA_TYPE as [type],
  CHARACTER_MAXIMUM_LENGTH as [maxLength],
  IS_NULLABLE as [nullable]
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = @tableName
ORDER BY ORDINAL_POSITION
```

### Foreign Keys (MSSQL)
```sql
SELECT
  fk.name AS [name],
  COL_NAME(fkc.parent_object_id, fkc.parent_column_id) AS [column],
  OBJECT_NAME(fkc.referenced_object_id) AS [referencedTable],
  COL_NAME(fkc.referenced_object_id, fkc.referenced_column_id) AS [referencedColumn]
FROM sys.foreign_keys fk
INNER JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
WHERE OBJECT_NAME(fk.parent_object_id) = @tableName
ORDER BY fk.name, fkc.constraint_column_id
```

---

## 13. Troubleshooting

### "ConnectionPool is not a constructor"
→ Bug do import ESM. Usar `import mssqlModule from "mssql"; const sql = mssqlModule;`

### Conexão via VPN falha
1. Verificar se VPN está `connected`: `GET /api/vpn-configs/:id/status`
2. Testar conectividade: `POST /api/vpn-configs/:id/test-connectivity` com host e port do DB
3. Verificar se `route-nopull` está no .ovpn

### "Rate limit excedido"
→ Aguardar 60 segundos. Limite: 30 req/min por (integrationId, userId)

### Tabela não aparece no Schema Browser
→ Pode estar na lista de `BLOCKED_TABLES`. Verificar se é: tboperador, tbparametro, tbusuario, tbconfig, sysdiagrams

### Dados aparecem mascarados
→ Normal. Colunas com CPF, CNPJ, FONE, EMAIL, etc. são mascaradas automaticamente.

---

## 14. Checklist para Novo Projeto

1. **Prisma:** Adicionar modelo `ExternalIntegrations` ao schema
2. **Dependências:** `mssql`, `ssh2` (+ types)
3. **Service:** Copiar `server/services/external-db.service.ts`
4. **IMPORTANTE:** Usar import correto do mssql (seção 4)
5. **Routes:** Adicionar 10 endpoints em `/api/external-integrations`
6. **Frontend:** Criar página com cards, formulário, schema browser, query executor
7. **Seed:** Implementar `seedDefaultIntegrations()` com integrações padrão
8. **Env:** Garantir `SESSION_SECRET` está definido
9. **VPN (se necessário):** Implementar skill `vpn-management-expert` primeiro

---

## 15. Centralização de Skills — Repositório Git

Esta skill é mantida no repositório central de skills:
- **Repositório:** `ricardohonoratoherculano-cmd/voxzap-skills` (GitHub privado)
- **Sync:** Use `sync-skills.sh` na raiz do projeto para atualizar skills de/para o repositório
- **Estrutura:** Cada skill em seu diretório: `skills/{nome}/SKILL.md`
