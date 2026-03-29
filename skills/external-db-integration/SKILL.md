---
name: external-db-integration
description: Framework profissional para integração com bancos de dados externos de parceiros/clientes. Use quando precisar configurar, mapear, consultar ou integrar qualquer banco de dados externo (MSSQL, PostgreSQL, MySQL, Oracle) com os sistemas VoxCALL/VoxZAP. Inclui arquitetura de conexão, padrões de segurança, templates de mapeamento, e integração com assistentes de IA.
---

# Framework de Integração com Bancos de Dados Externos

## 1. Visão Geral

A VoxCALL/VoxZAP se posiciona como **integradora de soluções**, conectando seus sistemas de comunicação (PABX, call center, WhatsApp) com os sistemas de gestão dos clientes. Este framework padroniza como cada integração é planejada, implementada e mantida.

### Capacidades da Integração
- **Assistente de IA** que consulta dados do CRM/ERP do cliente em tempo real
- **Screen Pop** — ficha do cliente exibida quando uma ligação entra
- **Discador Automático** — integrado com filas de cobrança do ERP
- **Dashboards Unificados** — dados de telefonia + dados do negócio
- **Relatórios Cruzados** — performance do operador vs resultados do negócio
- **WhatsApp Bot (VoxZAP)** — consulta status de pedido/dívida/cadastro via chat

### Integrações Ativas
| Cliente/Parceiro | Sistema | Banco | Método de Acesso | Skill Específica |
|-------------------|---------|-------|-------------------|------------------|
| Actyon | Smartcob (CRM Cobrança) | MSSQL | Direto (mssql/tedious) — 189.36.205.250:31433 | `actyon-crm` |

---

## 2. Arquitetura de Conexão Multi-Database

### 2.1 Métodos de Acesso Suportados

| Método | Caso de Uso | Stack Técnica | Quando Usar |
|--------|-------------|---------------|-------------|
| **ODBC via SSH** | MSSQL/Oracle em VPS Linux com FreeTDS | `ssh2` → `isql -v <dsn>` | Banco já configurado com ODBC na VPS |
| **Driver Nativo Node.js** | PostgreSQL, MySQL, MSSQL acessível via rede | `pg`, `mysql2`, `mssql` (tedious) | Banco acessível diretamente pela rede |
| **SSH Tunnel + Driver** | Banco em rede privada do cliente | `ssh2` tunnel → driver nativo | Banco sem acesso externo direto |
| **API REST** | Sistemas com API exposta | `axios` / `fetch` | Sistema expõe API HTTP |

### 2.2 Diagrama de Fluxo

```
┌─────────────┐     ┌──────────────┐     ┌─────────────────┐     ┌──────────────┐
│  VoxCALL    │────▶│  VPS Gateway │────▶│  SSH Tunnel /   │────▶│  Banco do    │
│  App Server │     │  (ponte)     │     │  ODBC / Driver  │     │  Cliente     │
└─────────────┘     └──────────────┘     └─────────────────┘     └──────────────┘
      │                                                                 │
      │              ┌──────────────┐                                  │
      └─────────────▶│  Driver      │──────────────────────────────────┘
                     │  Nativo      │   (acesso direto quando possível)
                     └──────────────┘
```

### 2.3 Padrão de Connection Pool

```typescript
interface ConnectionPoolConfig {
  min: number;          // Mínimo de conexões (padrão: 1)
  max: number;          // Máximo de conexões (padrão: 5)
  idleTimeoutMs: number; // Timeout idle (padrão: 30000)
  acquireTimeoutMs: number; // Timeout aquisição (padrão: 10000)
  retries: number;      // Tentativas de reconexão (padrão: 3)
  retryDelayMs: number; // Delay entre tentativas (padrão: 1000)
}

const DEFAULT_POOL: ConnectionPoolConfig = {
  min: 1,
  max: 5,
  idleTimeoutMs: 30000,
  acquireTimeoutMs: 10000,
  retries: 3,
  retryDelayMs: 1000
};
```

### 2.4 Retry com Backoff Exponencial

```typescript
async function withRetry<T>(
  fn: () => Promise<T>,
  maxRetries: number = 3,
  baseDelay: number = 1000
): Promise<T> {
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      return await fn();
    } catch (error) {
      if (attempt === maxRetries) throw error;
      const delay = baseDelay * Math.pow(2, attempt);
      await new Promise(r => setTimeout(r, delay));
    }
  }
  throw new Error('Unreachable');
}
```

---

## 3. Padrão de Configuração

### 3.1 Schema de Configuração JSON

Cada integração de banco externo segue este schema padronizado:

```json
{
  "integrationId": "actyon-smartcob",
  "displayName": "Actyon Smartcob — CRM Cobrança",
  "version": "1.0",
  "status": "active",
  "database": {
    "type": "mssql",
    "host": "${ACTYON_MSSQL_HOST}",
    "port": 1433,
    "database": "dbActyon_Smartcob",
    "username": "${ACTYON_MSSQL_USER}",
    "password": "${ACTYON_MSSQL_PASS}",
    "options": {
      "tdsVersion": "7.3",
      "encrypt": false,
      "trustServerCertificate": true,
      "requestTimeout": 30000,
      "connectionTimeout": 15000
    }
  },
  "accessMethod": {
    "type": "ssh-odbc",
    "ssh": {
      "host": "${VPS_SSH_HOST}",
      "port": 22300,
      "username": "${VPS_SSH_USER}",
      "password": "${VPS_SSH_PASS}"
    },
    "odbc": {
      "dsn": "mssql",
      "driverConfig": "/etc/freetds/freetds.conf",
      "odbcConfig": "/etc/odbc.ini"
    }
  },
  "security": {
    "readOnly": true,
    "queryTimeoutMs": 30000,
    "maxResultRows": 500,
    "rateLimitPerMinute": 30,
    "maskedFields": ["CPF", "CNPJ", "FONE", "CELULAR", "EMAIL"],
    "blockedTables": ["tbparametro", "tboperador"],
    "allowedSchemas": ["dbo"]
  },
  "pool": {
    "min": 1,
    "max": 5,
    "idleTimeoutMs": 30000
  },
  "metadata": {
    "createdAt": "2026-03-01T00:00:00Z",
    "updatedAt": "2026-03-26T00:00:00Z",
    "createdBy": "admin",
    "skillRef": "actyon-crm"
  }
}
```

### 3.2 API CRUD de Integrações

Endpoints para gerenciar configurações de integrações externas:

| Método | Rota | Descrição | Auth |
|--------|------|-----------|------|
| `GET` | `/api/integrations` | Listar todas as integrações | Admin |
| `GET` | `/api/integrations/:id` | Detalhes de uma integração | Admin |
| `POST` | `/api/integrations` | Criar nova integração | Admin |
| `PUT` | `/api/integrations/:id` | Atualizar integração | Admin |
| `DELETE` | `/api/integrations/:id` | Remover integração | Admin |
| `POST` | `/api/integrations/:id/test` | Testar conectividade | Admin |

#### Fluxo de Criação (POST)
1. Receber payload JSON com schema da Seção 3.1
2. Validar campos obrigatórios (tipo, host, database, credenciais)
3. **Testar conectividade** antes de persistir — rejeitar se falhar
4. Criptografar senha (AES-256-GCM)
5. Salvar configuração no banco interno
6. Retornar `201 Created` com ID da integração

#### Payload de Criação (POST /api/integrations)
```json
{
  "integrationId": "novo-cliente-erp",
  "displayName": "Cliente X — ERP",
  "database": {
    "type": "mssql",
    "host": "192.168.1.100",
    "port": 1433,
    "database": "dbClienteX",
    "username": "readonly_user",
    "password": "senha_segura"
  },
  "accessMethod": { "type": "direct" },
  "security": {
    "readOnly": true,
    "queryTimeoutMs": 30000,
    "maxResultRows": 500,
    "maskedFields": ["CPF", "CNPJ"],
    "blockedTables": ["tbusuario", "tbconfig"]
  }
}
```

#### Resposta do Teste (POST /api/integrations/:id/test)
```json
{
  "status": "pass",
  "tests": [
    { "name": "ssh_connection", "status": "pass", "durationMs": 450 },
    { "name": "db_connection", "status": "pass", "durationMs": 1200 },
    { "name": "simple_query", "status": "pass", "durationMs": 85 },
    { "name": "table_count", "status": "pass", "durationMs": 120, "message": "236 tabelas" }
  ]
}
```

### 3.3 Variáveis de Ambiente

Credenciais NUNCA ficam no código ou no JSON de configuração. Sempre usar variáveis de ambiente ou o scratchpad do agente:

| Variável | Descrição | Obrigatória |
|----------|-----------|-------------|
| `{PREFIX}_MSSQL_HOST` | Host do banco MSSQL | Sim |
| `{PREFIX}_MSSQL_PORT` | Porta (padrão: 1433) | Não |
| `{PREFIX}_MSSQL_USER` | Usuário do banco | Sim |
| `{PREFIX}_MSSQL_PASS` | Senha do banco | Sim |
| `{PREFIX}_MSSQL_DB` | Nome do database | Sim |
| `{PREFIX}_SSH_HOST` | Host SSH para tunnel | Se SSH |
| `{PREFIX}_SSH_PORT` | Porta SSH | Se SSH |
| `{PREFIX}_SSH_USER` | Usuário SSH | Se SSH |
| `{PREFIX}_SSH_PASS` | Senha SSH | Se SSH |

> **{PREFIX}** = identificador do cliente em MAIÚSCULAS (ex: `ACTYON`, `CLIENTE_X`)

### 3.3 Criptografia de Senhas em Repouso

Senhas armazenadas em banco de configuração devem usar AES-256-GCM:

```typescript
import { createCipheriv, createDecipheriv, randomBytes } from 'crypto';

const ALGORITHM = 'aes-256-gcm';
const KEY = process.env.ENCRYPTION_KEY; // 32 bytes hex

function encrypt(text: string): { encrypted: string; iv: string; tag: string } {
  const iv = randomBytes(16);
  const cipher = createCipheriv(ALGORITHM, Buffer.from(KEY!, 'hex'), iv);
  let encrypted = cipher.update(text, 'utf8', 'hex');
  encrypted += cipher.final('hex');
  const tag = cipher.getAuthTag().toString('hex');
  return { encrypted, iv: iv.toString('hex'), tag };
}

function decrypt(data: { encrypted: string; iv: string; tag: string }): string {
  const decipher = createDecipheriv(
    ALGORITHM,
    Buffer.from(KEY!, 'hex'),
    Buffer.from(data.iv, 'hex')
  );
  decipher.setAuthTag(Buffer.from(data.tag, 'hex'));
  let decrypted = decipher.update(data.encrypted, 'hex', 'utf8');
  decrypted += decipher.final('utf8');
  return decrypted;
}
```

---

## 4. Implementação Técnica — Métodos de Acesso

### 4.1 MSSQL via SSH + ODBC (isql) — Padrão Atual

Este é o método em produção para o Actyon Smartcob.

#### Pré-requisitos na VPS
- FreeTDS instalado (`/etc/freetds/freetds.conf`)
- unixODBC instalado (`/etc/odbc.ini`)
- DSN configurado e testado manualmente

#### Configuração FreeTDS (`/etc/freetds/freetds.conf`)
```ini
[mssql]
    host = {MSSQL_HOST}
    port = {MSSQL_PORT}
    tds version = 7.3
    client charset = UTF-8
```

#### Configuração ODBC (`/etc/odbc.ini`)
```ini
[mssql]
    Driver          = FreeTDS
    Description     = MSSQL via FreeTDS
    Servername      = mssql
    Database        = {DATABASE_NAME}
```

#### Código de Acesso via SSH + isql

```typescript
import { Client as SSHClient } from 'ssh2';

interface IsqlResult {
  columns: string[];
  rows: Record<string, string>[];
  rowCount: number;
  error?: string;
}

function parseIsqlOutput(output: string): IsqlResult {
  const lines = output.split('\n');
  const columns: string[] = [];
  const rows: Record<string, string>[] = [];
  let headerParsed = false;

  for (const line of lines) {
    const trimmed = line.trim();

    // Skip non-data lines
    if (!trimmed.startsWith('|')) continue;
    if (trimmed.startsWith('+-')) continue;
    if (trimmed.includes('Connected!')) continue;
    if (trimmed.includes('sql-statement')) continue;
    if (trimmed.includes('help [')) continue;
    if (trimmed.includes('quit')) continue;
    if (trimmed.includes('rows affected')) continue;
    if (trimmed.includes('SQLRowCount')) continue;

    const parts = trimmed
      .split('|')
      .map(s => s.trim())
      .filter(s => s.length > 0);

    if (parts.length === 0) continue;

    if (!headerParsed) {
      columns.push(...parts);
      headerParsed = true;
      continue;
    }

    const row: Record<string, string> = {};
    parts.forEach((val, i) => {
      if (i < columns.length) {
        row[columns[i]] = val;
      }
    });
    rows.push(row);
  }

  return { columns, rows, rowCount: rows.length };
}

function sanitizeForShell(sql: string): string {
  // Allowlist: letras, números, espaços, operadores SQL seguros
  // Remove: $, `, \, backticks, subshell operators
  const cleaned = sql
    .replace(/[`$\\]/g, '')           // Remove shell metacharacters
    .replace(/\$\([^)]*\)/g, '')      // Remove command substitution $()
    .replace(/;\s*(DROP|DELETE|INSERT|UPDATE|ALTER|EXEC|TRUNCATE)/gi, '') // Remove destructive chaining
    .trim();

  // Validação final: deve começar com SELECT
  if (!/^\s*SELECT/i.test(cleaned)) {
    throw new Error('Apenas SELECT é permitido');
  }

  return cleaned;
}

async function executeIsqlQuery(
  sshConfig: { host: string; port: number; username: string; password: string },
  dsn: string,
  dbUser: string,
  dbPass: string,
  sql: string,
  timeoutMs: number = 30000
): Promise<IsqlResult> {
  return new Promise((resolve, reject) => {
    const conn = new SSHClient();
    let timedOut = false;

    const timer = setTimeout(() => {
      timedOut = true;
      conn.end();
      reject(new Error(`Query timeout after ${timeoutMs}ms`));
    }, timeoutMs);

    conn.on('ready', () => {
      // CRITICAL: Proteção contra shell injection
      // 1. Validar query (somente SELECT)
      // 2. Usar stdin via stream ao invés de echo+interpolação
      // 3. Sanitizar com allowlist de caracteres
      const safeSql = sanitizeForShell(sql);
      const cmd = `isql -v ${dsn} ${dbUser} ${dbPass} 2>/dev/null`;

      conn.exec(cmd, { pty: false }, (err, stream) => {
        if (err) {
          clearTimeout(timer);
          conn.end();
          return reject(err);
        }

        // Enviar SQL via stdin (evita shell interpolation)
        stream.write(safeSql + '\n');
        stream.end();

        let stdout = '';
        let stderr = '';

        stream.on('data', (data: Buffer) => { stdout += data.toString(); });
        stream.stderr.on('data', (data: Buffer) => { stderr += data.toString(); });
        stream.on('close', () => {
          clearTimeout(timer);
          conn.end();
          if (timedOut) return;

          if (stderr && stderr.includes('ERROR')) {
            return resolve({ columns: [], rows: [], rowCount: 0, error: stderr });
          }

          resolve(parseIsqlOutput(stdout));
        });
      });
    });

    conn.on('error', (err) => {
      clearTimeout(timer);
      reject(err);
    });

    conn.connect(sshConfig);
  });
}
```

#### Regras Críticas do isql
1. **Sem `GO`** — isql não aceita `GO` no final das queries
2. **Saída delimitada por `|`** — parser deve tratar pipes
3. **Sem interatividade** — sempre usar `echo "SQL" | isql`
4. **Aspas no SQL** — escapar `"` dentro do comando echo
5. **Sem ponto-e-vírgula terminal** — remover `;` do final da query
6. **Timeout** — queries longas devem ter timeout explícito
7. **Redirect stderr** — usar `2>/dev/null` para suprimir warnings do FreeTDS

### 4.2 Driver Nativo Node.js — PostgreSQL

```typescript
import { Pool, PoolConfig } from 'pg';

function createPgPool(config: {
  host: string; port: number; database: string;
  user: string; password: string;
}): Pool {
  const poolConfig: PoolConfig = {
    host: config.host,
    port: config.port,
    database: config.database,
    user: config.user,
    password: config.password,
    max: 5,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 10000,
    statement_timeout: 30000,
  };
  return new Pool(poolConfig);
}

async function queryPg(pool: Pool, sql: string, params: any[] = []) {
  const client = await pool.connect();
  try {
    const result = await client.query(sql, params);
    return { columns: result.fields.map(f => f.name), rows: result.rows, rowCount: result.rowCount };
  } finally {
    client.release();
  }
}
```

### 4.3 Driver Nativo Node.js — MSSQL (tedious)

```typescript
import * as sql from 'mssql';

async function createMssqlPool(config: {
  host: string; port: number; database: string;
  user: string; password: string;
}): Promise<sql.ConnectionPool> {
  const pool = new sql.ConnectionPool({
    server: config.host,
    port: config.port,
    database: config.database,
    user: config.user,
    password: config.password,
    options: {
      encrypt: false,
      trustServerCertificate: true,
      requestTimeout: 30000,
      connectionTimeout: 15000,
    },
    pool: { min: 1, max: 5, idleTimeoutMillis: 30000 },
  });
  await pool.connect();
  return pool;
}

async function queryMssql(pool: sql.ConnectionPool, query: string, params?: Record<string, any>) {
  const request = pool.request();
  if (params) {
    for (const [key, value] of Object.entries(params)) {
      request.input(key, value);
    }
  }
  const result = await request.query(query);
  return {
    columns: result.recordset.columns ? Object.keys(result.recordset.columns) : [],
    rows: result.recordset,
    rowCount: result.rowCount ?? result.recordset.length,
  };
}
```

### 4.4 Driver Nativo Node.js — MySQL

```typescript
import mysql from 'mysql2/promise';

async function createMysqlPool(config: {
  host: string; port: number; database: string;
  user: string; password: string;
}): Promise<mysql.Pool> {
  return mysql.createPool({
    host: config.host,
    port: config.port,
    database: config.database,
    user: config.user,
    password: config.password,
    waitForConnections: true,
    connectionLimit: 5,
    queueLimit: 0,
    connectTimeout: 10000,
  });
}

async function queryMysql(pool: mysql.Pool, sql: string, params: any[] = []) {
  const [rows, fields] = await pool.execute(sql, params);
  return {
    columns: (fields as mysql.FieldPacket[]).map(f => f.name),
    rows: rows as Record<string, any>[],
    rowCount: Array.isArray(rows) ? rows.length : 0,
  };
}
```

### 4.5 SSH Tunnel + Driver Nativo

Para bancos em rede privada do cliente:

```typescript
import { Client as SSHClient } from 'ssh2';
import net from 'net';

interface TunnelConfig {
  sshHost: string;
  sshPort: number;
  sshUser: string;
  sshPass: string;
  remoteHost: string;
  remotePort: number;
  localPort: number;
}

function createSSHTunnel(config: TunnelConfig): Promise<{ server: net.Server; close: () => void }> {
  return new Promise((resolve, reject) => {
    const sshClient = new SSHClient();

    sshClient.on('ready', () => {
      const server = net.createServer((sock) => {
        sshClient.forwardOut(
          sock.remoteAddress || '127.0.0.1',
          sock.remotePort || 0,
          config.remoteHost,
          config.remotePort,
          (err, stream) => {
            if (err) { sock.end(); return; }
            sock.pipe(stream).pipe(sock);
          }
        );
      });

      server.listen(config.localPort, '127.0.0.1', () => {
        resolve({
          server,
          close: () => {
            server.close();
            sshClient.end();
          }
        });
      });
    });

    sshClient.on('error', reject);
    sshClient.connect({
      host: config.sshHost,
      port: config.sshPort,
      username: config.sshUser,
      password: config.sshPass,
    });
  });
}

// Uso: criar tunnel, depois conectar driver nativo em 127.0.0.1:{localPort}
```

### 4.6 Acesso via API REST

```typescript
import axios, { AxiosInstance } from 'axios';

interface ApiConfig {
  baseUrl: string;
  apiKey?: string;
  bearerToken?: string;
  timeoutMs: number;
}

function createApiClient(config: ApiConfig): AxiosInstance {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
  };
  if (config.apiKey) headers['X-API-Key'] = config.apiKey;
  if (config.bearerToken) headers['Authorization'] = `Bearer ${config.bearerToken}`;

  return axios.create({
    baseURL: config.baseUrl,
    timeout: config.timeoutMs,
    headers,
  });
}
```

---

## 5. Mapeamento Automático de Schema

### 5.1 Queries de Descoberta por Tipo de Banco

#### MSSQL — Descoberta de Tabelas
```sql
SELECT TABLE_NAME, TABLE_TYPE
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_NAME
```

#### MSSQL — Colunas de uma Tabela
```sql
SELECT
  COLUMN_NAME,
  DATA_TYPE,
  CHARACTER_MAXIMUM_LENGTH,
  IS_NULLABLE,
  COLUMN_DEFAULT
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = '{TABLE_NAME}'
ORDER BY ORDINAL_POSITION
```

#### MSSQL — Foreign Keys
```sql
SELECT
  fk.name AS FK_NAME,
  tp.name AS PARENT_TABLE,
  cp.name AS PARENT_COLUMN,
  tr.name AS REFERENCED_TABLE,
  cr.name AS REFERENCED_COLUMN
FROM sys.foreign_keys fk
  INNER JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
  INNER JOIN sys.tables tp ON fkc.parent_object_id = tp.object_id
  INNER JOIN sys.columns cp ON fkc.parent_object_id = cp.object_id AND fkc.parent_column_id = cp.column_id
  INNER JOIN sys.tables tr ON fkc.referenced_object_id = tr.object_id
  INNER JOIN sys.columns cr ON fkc.referenced_object_id = cr.object_id AND fkc.referenced_column_id = cr.column_id
ORDER BY tp.name, fk.name
```

#### MSSQL — Stored Procedures
```sql
SELECT ROUTINE_NAME, ROUTINE_TYPE, CREATED, LAST_ALTERED
FROM INFORMATION_SCHEMA.ROUTINES
WHERE ROUTINE_TYPE = 'PROCEDURE'
ORDER BY ROUTINE_NAME
```

#### MSSQL — Contagem de Registros
```sql
SELECT
  t.NAME AS TABLE_NAME,
  p.rows AS ROW_COUNT
FROM sys.tables t
  INNER JOIN sys.partitions p ON t.object_id = p.object_id
WHERE p.index_id IN (0, 1)
ORDER BY p.rows DESC
```

#### MSSQL — Views
```sql
SELECT TABLE_NAME, VIEW_DEFINITION
FROM INFORMATION_SCHEMA.VIEWS
ORDER BY TABLE_NAME
```

#### PostgreSQL — Descoberta de Tabelas
```sql
SELECT tablename, schemaname
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY tablename
```

#### PostgreSQL — Colunas
```sql
SELECT
  column_name,
  data_type,
  character_maximum_length,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_name = '{TABLE_NAME}'
  AND table_schema = 'public'
ORDER BY ordinal_position
```

#### PostgreSQL — Foreign Keys
```sql
SELECT
  tc.constraint_name,
  tc.table_name AS parent_table,
  kcu.column_name AS parent_column,
  ccu.table_name AS referenced_table,
  ccu.column_name AS referenced_column
FROM information_schema.table_constraints tc
  JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
  JOIN information_schema.constraint_column_usage ccu
    ON tc.constraint_name = ccu.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
ORDER BY tc.table_name
```

#### MySQL — Descoberta de Tabelas
```sql
SELECT TABLE_NAME, TABLE_TYPE, TABLE_ROWS
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = DATABASE()
ORDER BY TABLE_NAME
```

#### MySQL — Colunas
```sql
SELECT
  COLUMN_NAME,
  DATA_TYPE,
  CHARACTER_MAXIMUM_LENGTH,
  IS_NULLABLE,
  COLUMN_DEFAULT
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = '{TABLE_NAME}'
ORDER BY ORDINAL_POSITION
```

#### MySQL — Foreign Keys
```sql
SELECT
  CONSTRAINT_NAME,
  TABLE_NAME AS PARENT_TABLE,
  COLUMN_NAME AS PARENT_COLUMN,
  REFERENCED_TABLE_NAME,
  REFERENCED_COLUMN_NAME
FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE
WHERE TABLE_SCHEMA = DATABASE()
  AND REFERENCED_TABLE_NAME IS NOT NULL
ORDER BY TABLE_NAME
```

### 5.2 Template de Geração de Documentação

Ao mapear um novo banco, gerar a skill específica seguindo este template:

```markdown
---
name: {client-system-name}
description: {Descrição do sistema e do banco}
---

# {Sistema} — Mapeamento do Banco de Dados

## Visão Geral
- Sistema: {nome}
- Propósito: {descrição}
- Banco: {tipo} / {nome do database}
- Escala: {X} tabelas, {Y} SPs, {Z} registros principais

## Conexão
| Parâmetro | Valor |
|-----------|-------|
| Tipo | {MSSQL/PostgreSQL/MySQL} |
| Host | ${ENV_VAR_HOST} |
| Database | {nome} |
| Usuário | ${ENV_VAR_USER} |
| Senha | ${ENV_VAR_PASS} |

## Domínio
{Descrição do domínio de negócio}

## Glossário
| Termo | Significado |
|-------|------------|
| ... | ... |

## Mapeamento de Tabelas

### {tabela} ({N} colunas) — {Descrição}
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|-----------|
| ... | ... | ... | ... | ... |

## Relacionamentos (ERD Textual)
{tabela_a}.{coluna} → {tabela_b}.{coluna}

## Stored Procedures
| Procedure | Finalidade |
|-----------|-----------|
| ... | ... |

## Queries Prontas para o Assistente
### {Cenário de Consulta}
```sql
SELECT TOP 100 ...
```

## Segurança
- Somente SELECT
- Tabelas bloqueadas: ...
- Campos mascarados: ...
```

---

## 6. Camada de Abstração para Assistente de IA

### 6.1 Queries Parametrizadas (Anti-SQL-Injection)

**REGRA ABSOLUTA:** Nunca concatenar valores do usuário diretamente na query SQL.

```typescript
// ERRADO — vulnerável a SQL injection
const sql = `SELECT * FROM tbdevedor WHERE CPF = '${userInput}'`;

// CORRETO — parametrizado (driver nativo)
const sql = `SELECT * FROM tbdevedor WHERE CPF = @cpf`;
const params = { cpf: userInput };

// CORRETO — parametrizado (isql via sanitização)
function sanitizeForIsql(value: string): string {
  return value.replace(/['";\-\-\/\*\\]/g, '').substring(0, 100);
}
const safeCpf = sanitizeForIsql(userInput);
const sql = `SELECT TOP 100 DEVEDOR_ID, NOME FROM tbdevedor WHERE CPF = '${safeCpf}'`;
```

### 6.2 Limite Automático de Resultados

Toda query DEVE incluir limitação de linhas:

| Banco | Sintaxe | Exemplo |
|-------|---------|---------|
| MSSQL | `SELECT TOP {N}` | `SELECT TOP 100 * FROM tbdevedor` |
| PostgreSQL | `LIMIT {N}` | `SELECT * FROM tbdevedor LIMIT 100` |
| MySQL | `LIMIT {N}` | `SELECT * FROM tbdevedor LIMIT 100` |
| Oracle | `FETCH FIRST {N} ROWS ONLY` | `SELECT * FROM tbdevedor FETCH FIRST 100 ROWS ONLY` |

Limites padrão:
- **Assistente de IA:** TOP 100 (máximo 500)
- **Screen Pop:** TOP 1
- **Discador:** TOP 1000
- **Relatórios:** TOP 5000

### 6.3 Mascaramento de Dados Sensíveis

```typescript
interface MaskingRule {
  field: string;
  pattern: RegExp;
  mask: (value: string) => string;
}

const MASKING_RULES: MaskingRule[] = [
  {
    field: 'CPF',
    pattern: /^\d{11}$/,
    mask: (v) => `${v.substring(0, 3)}.***.***.${v.substring(9, 11)}`
  },
  {
    field: 'CNPJ',
    pattern: /^\d{14}$/,
    mask: (v) => `${v.substring(0, 2)}.***.***/****-${v.substring(12, 14)}`
  },
  {
    field: 'FONE',
    pattern: /^\d{10,11}$/,
    mask: (v) => `(${v.substring(0, 2)}) ****-${v.substring(v.length - 4)}`
  },
  {
    field: 'EMAIL',
    pattern: /.+@.+/,
    mask: (v) => {
      const [local, domain] = v.split('@');
      return `${local.substring(0, 2)}***@${domain}`;
    }
  },
];

function applyMasking(rows: Record<string, any>[], rules: MaskingRule[]): Record<string, any>[] {
  return rows.map(row => {
    const masked = { ...row };
    for (const rule of rules) {
      for (const key of Object.keys(masked)) {
        if (key.toUpperCase().includes(rule.field) && masked[key] && typeof masked[key] === 'string') {
          if (rule.pattern.test(masked[key])) {
            masked[key] = rule.mask(masked[key]);
          }
        }
      }
    }
    return masked;
  });
}
```

### 6.4 Formatação para Linguagem Natural

```typescript
function formatResultForAI(result: IsqlResult, locale: string = 'pt-BR'): string {
  if (result.rows.length === 0) return 'Nenhum resultado encontrado.';

  const lines: string[] = [];
  lines.push(`Encontrado(s) ${result.rows.length} resultado(s):\n`);

  for (const row of result.rows) {
    const parts: string[] = [];
    for (const [key, value] of Object.entries(row)) {
      const label = columnToLabel(key);
      const formatted = formatValue(key, value, locale);
      parts.push(`${label}: ${formatted}`);
    }
    lines.push(`- ${parts.join(' | ')}`);
  }

  return lines.join('\n');
}

function columnToLabel(column: string): string {
  const MAP: Record<string, string> = {
    'DEVEDOR_ID': 'ID',
    'NOME': 'Nome',
    'CPF': 'CPF',
    'DATA_NASCIMENTO': 'Nascimento',
    'VALOR_ORIGINAL': 'Valor Original',
    'DATA_VENCIMENTO': 'Vencimento',
    'NUMERO_CONTRATO': 'Contrato',
    'SITUACAO_ID': 'Situação',
    'CONT_ID': 'Contratante',
  };
  return MAP[column] || column.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
}

function formatValue(column: string, value: any, locale: string): string {
  if (value === null || value === undefined || value === '') return '—';

  if (column.startsWith('DATA_') || column.startsWith('DT_')) {
    const d = new Date(value);
    return isNaN(d.getTime()) ? String(value) : d.toLocaleDateString(locale);
  }

  if (column.startsWith('VALOR_') || column.startsWith('PERC_')) {
    const n = parseFloat(value);
    return isNaN(n) ? String(value) : n.toLocaleString(locale, { minimumFractionDigits: 2 });
  }

  return String(value);
}
```

### 6.5 Cache de Resultados

```typescript
interface CacheEntry {
  data: any;
  timestamp: number;
  ttlMs: number;
}

class QueryCache {
  private cache = new Map<string, CacheEntry>();

  get(key: string): any | null {
    const entry = this.cache.get(key);
    if (!entry) return null;
    if (Date.now() - entry.timestamp > entry.ttlMs) {
      this.cache.delete(key);
      return null;
    }
    return entry.data;
  }

  set(key: string, data: any, ttlMs: number = 300000): void {
    this.cache.set(key, { data, timestamp: Date.now(), ttlMs });
  }

  invalidate(pattern?: string): void {
    if (!pattern) { this.cache.clear(); return; }
    for (const key of this.cache.keys()) {
      if (key.includes(pattern)) this.cache.delete(key);
    }
  }
}

// TTLs recomendados por tipo de dado:
// - Dados cadastrais (nome, endereço): 5 min (300000ms)
// - Dados de referência (tabelas lookup): 30 min (1800000ms)
// - Dados financeiros (saldos, títulos): 1 min (60000ms)
// - Totalizadores/contagens: 10 min (600000ms)
```

### 6.6 Tratamento de Tipos de Dados

| Tipo SQL | Formatação PT-BR | Exemplo |
|----------|------------------|---------|
| `datetime` / `smalldatetime` | `DD/MM/YYYY HH:MM:SS` | `26/03/2026 14:30:00` |
| `date` | `DD/MM/YYYY` | `26/03/2026` |
| `numeric` / `decimal` | `#.###,##` | `1.234,56` |
| `money` | `R$ #.###,##` | `R$ 1.234,56` |
| `bit` | `Sim` / `Não` | `Sim` |
| `char(1)` S/N | `Sim` / `Não` | `Sim` |
| `varchar` CPF | `###.***.***-##` | `123.***.***-01` |
| `varchar` CNPJ | `##.***.***/****-##` | `12.***.***/****-01` |
| `varchar` telefone | `(##) ****-####` | `(11) ****-1234` |
| `NULL` | `—` | `—` |

---

## 7. Segurança

### 7.1 Regras Obrigatórias

1. **Somente SELECT** — NUNCA executar INSERT, UPDATE, DELETE, DROP, ALTER, TRUNCATE, EXEC em banco de cliente
2. **Validação de query** — toda query deve passar por validação antes da execução:

```typescript
function validateQuery(sql: string): { valid: boolean; reason?: string } {
  const upper = sql.toUpperCase().trim();

  const FORBIDDEN = ['INSERT', 'UPDATE', 'DELETE', 'DROP', 'ALTER', 'TRUNCATE',
    'EXEC', 'EXECUTE', 'CREATE', 'GRANT', 'REVOKE', 'MERGE', 'xp_', 'sp_'];

  for (const keyword of FORBIDDEN) {
    const pattern = new RegExp(`\\b${keyword}\\b`, 'i');
    if (pattern.test(upper)) {
      return { valid: false, reason: `Operação proibida: ${keyword}` };
    }
  }

  if (!upper.startsWith('SELECT')) {
    return { valid: false, reason: 'Apenas SELECT é permitido' };
  }

  return { valid: true };
}
```

3. **Whitelist de tabelas** — só permitir acesso a tabelas autorizadas
4. **Campos mascarados** — CPF, CNPJ, telefone, email sempre mascarados na resposta
5. **Timeout por query** — máximo 30 segundos
6. **Rate limiting** — máximo 30 queries por minuto por conexão
7. **Logging** — toda query executada deve ser logada com timestamp, usuário, duração

### 7.2 Rate Limiter

```typescript
class RateLimiter {
  private requests: number[] = [];
  private maxPerMinute: number;

  constructor(maxPerMinute: number = 30) {
    this.maxPerMinute = maxPerMinute;
  }

  canExecute(): boolean {
    const now = Date.now();
    this.requests = this.requests.filter(t => now - t < 60000);
    if (this.requests.length >= this.maxPerMinute) return false;
    this.requests.push(now);
    return true;
  }
}
```

### 7.3 Logging de Queries

```typescript
interface QueryLog {
  timestamp: string;
  integrationId: string;
  query: string;
  params?: Record<string, any>;
  durationMs: number;
  rowCount: number;
  userId?: string;
  error?: string;
}

function logQuery(log: QueryLog): void {
  const sanitized = {
    ...log,
    query: log.query.substring(0, 500),
    params: log.params ? Object.fromEntries(
      Object.entries(log.params).map(([k, v]) => [k, typeof v === 'string' && v.length > 20 ? '***' : v])
    ) : undefined,
  };
  console.log(`[EXTERNAL-DB] ${JSON.stringify(sanitized)}`);
}
```

### 7.4 Tabelas Bloqueadas (Padrão)

Tabelas de configuração/sistema do cliente que NUNCA devem ser consultadas:

| Categoria | Exemplos |
|-----------|----------|
| Configuração | `tbparametro`, `tbconfig`, `tbsettings` |
| Usuários/Auth | `tboperador`, `tbusuario`, `tbuser`, `tblogin` |
| Logs internos | `tblog_sistema`, `tbaudit` |
| Permissões | `tbpermissao`, `tbrole`, `tbacl` |
| Senhas/Tokens | qualquer tabela com colunas `SENHA`, `PASSWORD`, `TOKEN`, `SECRET` |

---

## 8. Integração com Funcionalidades VoxCALL

### 8.1 Screen Pop — Identificação de Chamador

Quando uma chamada entra, buscar dados do caller no CRM do cliente:

```typescript
interface ScreenPopData {
  found: boolean;
  caller: string;
  name?: string;
  document?: string;
  status?: string;
  lastContact?: string;
  pendingAmount?: number;
  customFields?: Record<string, any>;
}

async function screenPopLookup(
  phoneNumber: string,
  integrationId: string
): Promise<ScreenPopData> {
  const cleanPhone = phoneNumber.replace(/\D/g, '');
  const ddd = cleanPhone.length >= 10 ? cleanPhone.substring(0, 2) : '';
  const number = cleanPhone.length >= 10 ? cleanPhone.substring(2) : cleanPhone;

  // Query parametrizada — adaptar conforme schema do cliente
  const sql = `SELECT TOP 1
    d.DEVEDOR_ID, d.NOME, d.CPF, d.SITUACAO,
    (SELECT TOP 1 DATA_ACIONAMENTO FROM tbacionamento a
     WHERE a.DEVEDOR_ID = d.DEVEDOR_ID
     ORDER BY DATA_ACIONAMENTO DESC) AS ULTIMO_CONTATO,
    (SELECT SUM(VALOR_ORIGINAL) FROM tbtitulo t
     WHERE t.DEVEDOR_ID = d.DEVEDOR_ID AND t.SITUACAO NOT IN ('P','C')) AS SALDO
  FROM tbdevedor d
  INNER JOIN tbdevedor_fone f ON d.DEVEDOR_ID = f.DEVEDOR_ID
  WHERE f.DDD = @ddd AND f.FONE = @number`;

  const params = { ddd, number };
  // Executar via queryMssql(pool, sql, params) — 100% parametrizado
  // NUNCA usar interpolação: WHERE f.DDD = '${ddd}' ← PROIBIDO
  return { found: true, caller: phoneNumber, name: '...' };
}
```

### 8.2 Discador Automático — Lista de Contatos

Buscar lista de devedores para discagem automática:

```typescript
async function getDialerList(
  integrationId: string,
  filters: {
    contratanteId?: number;
    faixaAtraso?: { min: number; max: number };
    valorMinimo?: number;
    limit?: number;
  }
): Promise<Array<{ phone: string; name: string; debtorId: number; amount: number }>> {
  // Usar query parametrizada — NUNCA interpolar valores do usuário
  // Para driver nativo (mssql/tedious):
  const params: Record<string, any> = {};
  const conditions: string[] = [];

  if (filters.contratanteId) {
    conditions.push('d.CONT_ID = @contratanteId');
    params.contratanteId = filters.contratanteId;
  }
  if (filters.faixaAtraso) {
    conditions.push('DATEDIFF(DAY, t.DATA_VENCIMENTO, GETDATE()) BETWEEN @atrasoMin AND @atrasoMax');
    params.atrasoMin = filters.faixaAtraso.min;
    params.atrasoMax = filters.faixaAtraso.max;
  }
  if (filters.valorMinimo) {
    conditions.push('t.VALOR_ORIGINAL >= @valorMinimo');
    params.valorMinimo = filters.valorMinimo;
  }

  const where = conditions.length > 0 ? 'AND ' + conditions.join(' AND ') : '';

  const sql = `SELECT TOP 1000
    f.DDD + f.FONE AS TELEFONE,
    d.NOME,
    d.DEVEDOR_ID,
    SUM(t.VALOR_ORIGINAL) AS VALOR_TOTAL
  FROM tbdevedor d
    INNER JOIN tbdevedor_fone f ON d.DEVEDOR_ID = f.DEVEDOR_ID
    INNER JOIN tbtitulo t ON d.DEVEDOR_ID = t.DEVEDOR_ID
  WHERE f.SE_ATIVO = 'S' AND t.SITUACAO NOT IN ('P','C') ${where}
  GROUP BY f.DDD, f.FONE, d.NOME, d.DEVEDOR_ID
  ORDER BY VALOR_TOTAL DESC`;

  // Executar via queryMssql(pool, sql, params) — parametrizado
  return [];
}
```

### 8.3 Report Assistant — Queries Cruzadas

Combinar dados do CRM com dados de telefonia:

```typescript
// Exemplo: Performance do operador vs acordos fechados
// Query 1 — dados de telefonia (PostgreSQL interno)
const telefoniaQuery = `
  SELECT agent, COUNT(*) as total_calls,
    AVG(EXTRACT(EPOCH FROM (calldate + duration * INTERVAL '1 second') - calldate)) as avg_duration
  FROM cdr
  WHERE calldate >= CURRENT_DATE - INTERVAL '30 days'
  GROUP BY agent
`;

// Query 2 — dados do CRM (MSSQL externo)
const crmQuery = `
  SELECT TOP 500
    a.OPERADOR_ID,
    COUNT(DISTINCT a.ACORDO_ID) AS TOTAL_ACORDOS,
    SUM(a.VALOR_ACORDO) AS VALOR_TOTAL
  FROM tbacordo a
  WHERE a.DATA >= DATEADD(DAY, -30, GETDATE())
  GROUP BY a.OPERADOR_ID
`;

// Cruzar resultados no backend Node.js
function crossReference(telefoniaData: any[], crmData: any[]): any[] {
  return telefoniaData.map(tel => {
    const crm = crmData.find(c => c.OPERADOR_ID === tel.agent);
    return {
      operador: tel.agent,
      totalLigacoes: tel.total_calls,
      duracaoMedia: tel.avg_duration,
      totalAcordos: crm?.TOTAL_ACORDOS || 0,
      valorAcordos: crm?.VALOR_TOTAL || 0,
      conversao: crm ? ((crm.TOTAL_ACORDOS / tel.total_calls) * 100).toFixed(1) + '%' : '0%',
    };
  });
}
```

### 8.4 Agent Panel — Dados na Tela do Operador

Exibir ficha completa do devedor durante atendimento:

```typescript
interface AgentPanelData {
  debtor: {
    id: number;
    name: string;
    document: string;
    phones: Array<{ type: string; number: string; active: boolean }>;
    addresses: Array<{ street: string; city: string; state: string }>;
  };
  debts: Array<{
    contractNumber: string;
    originalValue: number;
    currentValue: number;
    dueDate: string;
    status: string;
  }>;
  agreements: Array<{
    id: string;
    date: string;
    value: number;
    installments: number;
    status: string;
  }>;
  lastActions: Array<{
    date: string;
    action: string;
    operator: string;
    note: string;
  }>;
}
```

### 8.5 WhatsApp Bot (VoxZAP) — Consulta via Chat

```typescript
interface BotQuery {
  intent: 'status_divida' | 'segunda_via' | 'acordo' | 'cadastro';
  identifier: string; // CPF ou número de contrato
}

async function handleBotQuery(query: BotQuery): Promise<string> {
  switch (query.intent) {
    case 'status_divida':
      return await getDebtStatus(query.identifier);
    case 'segunda_via':
      return await getSecondCopy(query.identifier);
    case 'acordo':
      return await getAgreementInfo(query.identifier);
    case 'cadastro':
      return await getRegistrationInfo(query.identifier);
  }
}
```

---

## 9. Checklist de Nova Integração

### Fase 1 — Coleta e Preparação
- [ ] Identificar tipo de banco (MSSQL, PostgreSQL, MySQL, Oracle)
- [ ] Coletar credenciais de acesso (host, porta, database, usuário, senha)
- [ ] Determinar método de acesso (direto, SSH tunnel, ODBC, API)
- [ ] Verificar requisitos de rede (firewall, VPN, whitelist de IP)
- [ ] Definir variáveis de ambiente (`{PREFIX}_*`)
- [ ] Obter aprovação formal do cliente para acesso somente-leitura

### Fase 2 — Conectividade
- [ ] Testar ping/telnet ao host do banco
- [ ] Testar conexão SSH (se aplicável)
- [ ] Testar conexão ao banco com credenciais
- [ ] Verificar charset/encoding (UTF-8)
- [ ] Medir latência da conexão
- [ ] Configurar pool de conexões

### Fase 3 — Mapeamento do Schema
- [ ] Executar queries de descoberta de tabelas
- [ ] Mapear colunas de cada tabela relevante
- [ ] Identificar foreign keys e relacionamentos
- [ ] Identificar tabelas de referência (lookup)
- [ ] Contar registros por tabela
- [ ] Listar stored procedures disponíveis
- [ ] Listar views disponíveis

### Fase 4 — Documentação
- [ ] Criar skill específica do banco (`.agents/skills/{client-system}/SKILL.md`)
- [ ] Documentar domínio de negócio e glossário
- [ ] Documentar todas as tabelas com colunas completas
- [ ] Documentar relacionamentos (ERD textual)
- [ ] Criar queries prontas para o Assistente de IA (mínimo 10 cenários)
- [ ] Definir tabelas bloqueadas e campos mascarados

### Fase 5 — Integração VoxCALL
- [ ] Configurar Screen Pop (busca por telefone)
- [ ] Configurar queries para o Discador (se aplicável)
- [ ] Configurar queries para o Report Assistant
- [ ] Configurar dados para o Agent Panel
- [ ] Configurar consultas para o WhatsApp Bot (se aplicável)

### Fase 6 — Segurança e Testes
- [ ] Validar que apenas SELECT é permitido
- [ ] Testar mascaramento de dados sensíveis
- [ ] Configurar rate limiting
- [ ] Configurar logging de queries
- [ ] Testar timeout de queries
- [ ] Testar failover/retry

### Fase 7 — Entrega
- [ ] Teste end-to-end de todas as integrações
- [ ] Documentar runbook operacional
- [ ] Treinar equipe operacional
- [ ] Monitoramento em produção por 48h
- [ ] Handoff ao cliente

---

## 10. Teste de Conectividade

### Script de Teste Automatizado

```typescript
interface ConnectivityTestResult {
  integrationId: string;
  timestamp: string;
  tests: Array<{
    name: string;
    status: 'pass' | 'fail' | 'skip';
    durationMs: number;
    message: string;
  }>;
  overall: 'pass' | 'fail';
}

async function testConnectivity(config: any): Promise<ConnectivityTestResult> {
  const results: ConnectivityTestResult = {
    integrationId: config.integrationId,
    timestamp: new Date().toISOString(),
    tests: [],
    overall: 'pass',
  };

  // Teste 1: SSH (se aplicável)
  if (config.accessMethod?.ssh) {
    const sshTest = await testSSH(config.accessMethod.ssh);
    results.tests.push(sshTest);
  }

  // Teste 2: Conexão ao banco
  const dbTest = await testDatabaseConnection(config);
  results.tests.push(dbTest);

  // Teste 3: Query simples
  const queryTest = await testSimpleQuery(config);
  results.tests.push(queryTest);

  // Teste 4: Contagem de tabelas
  const tableTest = await testTableCount(config);
  results.tests.push(tableTest);

  // Teste 5: Latência
  const latencyTest = await testLatency(config);
  results.tests.push(latencyTest);

  results.overall = results.tests.every(t => t.status === 'pass') ? 'pass' : 'fail';
  return results;
}
```

---

## 11. Troubleshooting

### Problemas Comuns

| Problema | Causa Provável | Solução |
|----------|---------------|---------|
| `Connection refused` | Firewall bloqueando porta | Verificar regras de firewall, whitelist IP da VPS |
| `Login failed` | Credenciais incorretas | Verificar usuário/senha, testar manualmente |
| `Timeout` | Query muito pesada | Adicionar índice, usar TOP/LIMIT, otimizar WHERE |
| `Character encoding` | Charset incompatível | Configurar `client charset = UTF-8` no FreeTDS |
| `SSL required` | Banco exige SSL | Adicionar `encrypt: true` na configuração |
| `isql: command not found` | unixODBC não instalado | `apt install unixodbc` na VPS |
| `[FreeTDS] Unable to connect` | Versão TDS incorreta | Testar `tds version = 7.3` ou `7.4` |
| `Adaptive Server connection failed` | Host/porta incorretos | Verificar config em `/etc/freetds/freetds.conf` |
| `Cannot open database` | Database não existe | Verificar nome exato do database |
| `Read-only access denied` | Permissões insuficientes | Solicitar ao DBA: `GRANT SELECT ON SCHEMA::dbo TO [user]` |

### Comandos de Diagnóstico

```bash
# Testar conectividade SSH
ssh -p {PORT} {USER}@{HOST} "echo OK"

# Testar ODBC
isql -v {DSN} {USER} {PASS} <<< "SELECT 1"

# Verificar config FreeTDS
tsql -C
cat /etc/freetds/freetds.conf

# Verificar DSN ODBC
odbcinst -j
cat /etc/odbc.ini

# Testar conectividade de rede
telnet {HOST} {PORT}
nc -zv {HOST} {PORT}
```

---

## 12. Referência Rápida — Comandos do Agente

Quando o agente precisar trabalhar com um banco externo, seguir esta sequência:

### Consulta Simples
1. Identificar a integração (qual cliente/sistema)
2. Carregar a skill específica do banco
3. Construir query SQL parametrizada com TOP/LIMIT
4. Validar query (sem INSERT/UPDATE/DELETE)
5. Executar via método de acesso configurado
6. Aplicar mascaramento de dados sensíveis
7. Formatar resposta para linguagem natural

### Nova Integração
1. Ler esta skill (framework)
2. Seguir checklist da Seção 9
3. Usar queries de descoberta da Seção 5
4. Gerar skill específica usando template da Seção 5.2
5. Testar conectividade (Seção 10)
6. Configurar integrações VoxCALL (Seção 8)

### Regras de Ouro
- **NUNCA** executar queries destrutivas em banco de cliente
- **SEMPRE** usar TOP/LIMIT em toda query
- **SEMPRE** mascarar CPF, CNPJ, telefone, email
- **SEMPRE** usar variáveis de ambiente para credenciais
- **SEMPRE** validar a query antes de executar
- **NUNCA** expor credenciais em logs ou respostas
- **SEMPRE** logar queries executadas com timestamp e duração
