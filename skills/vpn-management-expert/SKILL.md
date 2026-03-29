---
name: vpn-management-expert
description: Especialista em gerenciamento de VPN para integração com redes privadas de clientes. Use quando precisar criar, modificar, debugar ou estender o sistema de VPN Management — incluindo conexão/desconexão OpenVPN via SSH, status polling, teste de conectividade, upload de .ovpn, criptografia de credenciais, e toda a UI de gerenciamento. Inclui modelo Prisma, service completo, 9 endpoints de API, e frontend React.
---

# Sistema de Gerenciamento de VPN — Documentação Completa

## 1. Visão Geral

O sistema de VPN Management permite que o SuperAdmin gerencie conexões VPN OpenVPN em servidores VPS remotos via SSH. É usado para acessar redes privadas de clientes (ex: bancos de dados internos acessíveis apenas via VPN).

### Fluxo Principal
```
SuperAdmin UI → API REST → vpn.service.ts → SSH (ssh2) → VPS Remoto → OpenVPN daemon
```

### Dependências
- `ssh2` — Conexão SSH para executar comandos e upload de arquivos no VPS
- `crypto` — AES-256-CBC para criptografia de credenciais
- `prisma` — ORM para persistência no PostgreSQL

---

## 2. Modelo Prisma

```prisma
model VpnConfigurations {
  id            Int       @id @default(autoincrement())
  tenantId      Int
  name          String    @db.VarChar(255)
  ovpnConfig    String    @db.Text          // Conteúdo .ovpn (encrypted)
  authUser      String?   @db.VarChar(512)  // Usuário VPN (encrypted)
  authPass      String?   @db.VarChar(512)  // Senha VPN (encrypted)
  sshHost       String    @db.VarChar(255)  // Host SSH do VPS
  sshPort       Int       @default(22)      // Porta SSH
  sshUser       String    @default("root") @db.VarChar(255)
  sshPassword   String    @db.VarChar(512)  // Senha SSH (encrypted)
  status        String    @default("disconnected") @db.VarChar(50) // connected|disconnected|error
  vpnIp         String?   @db.VarChar(50)   // IP obtido na VPN (ex: 10.8.0.46)
  lastCheckedAt DateTime? @db.Timestamptz(6)
  createdAt     DateTime  @default(now()) @db.Timestamptz(6)
  updatedAt     DateTime  @default(now()) @db.Timestamptz(6)

  @@index([tenantId], map: "idx_vpn_configurations_tenantid")
  @@map("VpnConfigurations")
}
```

### Campos Importantes
| Campo | Tipo | Encrypted | Descrição |
|-------|------|-----------|-----------|
| `ovpnConfig` | Text | ✅ | Conteúdo completo do arquivo .ovpn |
| `authUser` | VarChar(512) | ✅ | Usuário de autenticação VPN (opcional) |
| `authPass` | VarChar(512) | ✅ | Senha de autenticação VPN (opcional) |
| `sshPassword` | VarChar(512) | ✅ | Senha SSH para acesso ao VPS |
| `status` | VarChar(50) | ❌ | `connected`, `disconnected`, ou `error` |
| `vpnIp` | VarChar(50) | ❌ | IP atribuído pela VPN (ex: 10.8.0.46) |

---

## 3. Criptografia

### Padrão AES-256-CBC
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

### Regras
- **SESSION_SECRET** é padded para exatamente 32 bytes com "0"
- O formato armazenado é `iv_hex:encrypted_hex`
- A mesma implementação é usada em `vpn.service.ts` e `external-db.service.ts`
- Campos criptografados: `ovpnConfig`, `authUser`, `authPass`, `sshPassword`

---

## 4. Service (`server/services/vpn.service.ts`)

### 4.1 Funções SSH Internas

#### `sshExec(cmd, timeout, ssh)` → `ExecResult`
Executa um comando via SSH com timeout. Retorna `{ success, stdout, stderr }`.

#### `sshUpload(content, remotePath, ssh)` → `void`
Upload de arquivo via SFTP para o VPS remoto.

#### `getSshFromConfig(config)` → `SshConfig`
Extrai e decripta as credenciais SSH de uma configuração VPN.

### 4.2 Funções Exportadas

| Função | Descrição | Parâmetros |
|--------|-----------|------------|
| `list(tenantId)` | Lista todas as VPNs do tenant | `tenantId: number` |
| `getById(id, tenantId)` | Busca VPN por ID (tenant-scoped) | `id, tenantId` |
| `create(data)` | Cria nova configuração VPN | Todos os campos (encrypt automático) |
| `update(id, tenantId, data)` | Atualiza configuração | Campos parciais (re-encrypt se alterado) |
| `remove(id, tenantId)` | Remove VPN e limpa VPS | Kill OpenVPN + remove arquivos remotos |
| `connect(id, tenantId)` | Conecta a VPN | Retorna `{ success, message, vpnIp? }` |
| `disconnect(id, tenantId)` | Desconecta a VPN | Kill processo + limpa PID |
| `getStatus(id, tenantId)` | Verifica status atual | Retorna `{ status, vpnIp, log }` |
| `testConnectivity(id, tenantId, host, port)` | Testa acesso a host:port via VPN | Usa `/dev/tcp` |
| `getLogs(id, tenantId, lines)` | Obtém logs do OpenVPN | `tail -n` do log remoto |

### 4.3 Fluxo de Conexão (connect)

```
1. Buscar configuração no banco (tenant-scoped)
2. Verificar se OpenVPN está instalado → instalar se necessário
3. Criar diretório /etc/openvpn/voxzap/ no VPS
4. Processar arquivo .ovpn:
   a. Adicionar route-nopull (evita hijack do gateway)
   b. Adicionar pull-filter ignore "redirect-gateway"
   c. Adicionar pull-filter ignore "route 0.0.0.0"
5. Upload do .ovpn via SFTP
6. Se authUser/authPass: criar arquivo .auth e configurar auth-user-pass
7. Matar processo OpenVPN anterior (se existir)
8. Iniciar OpenVPN em daemon mode:
   openvpn --config vpn_{id}.ovpn --daemon vpn_{id} --log /var/log/openvpn_vpn_{id}.log --writepid /var/run/openvpn_vpn_{id}.pid
9. Aguardar 8 segundos
10. Verificar 3x se processo está ativo (kill -0)
11. Capturar IP da interface tun (tun0, tun1, tun2)
12. Atualizar status no banco: connected + vpnIp
```

### 4.4 Paths Remotos no VPS
| Path | Descrição |
|------|-----------|
| `/etc/openvpn/voxzap/vpn_{id}.ovpn` | Arquivo de configuração OpenVPN |
| `/etc/openvpn/voxzap/vpn_{id}.auth` | Arquivo de autenticação (user/pass) |
| `/var/run/openvpn_vpn_{id}.pid` | PID file do daemon |
| `/var/log/openvpn_vpn_{id}.log` | Log do OpenVPN |

### 4.5 Segurança do .ovpn
O sistema automaticamente adiciona ao .ovpn:
```
route-nopull
pull-filter ignore "redirect-gateway"
pull-filter ignore "route 0.0.0.0"
```
Isso **impede** que a VPN sequestre o gateway padrão do VPS, garantindo que apenas o tráfego para a rede privada do cliente passe pela VPN.

---

## 5. API Routes

**Base path:** `/api/vpn-configs`
**Autenticação:** `authenticateToken` middleware (JWT)
**Autorização:** SuperAdmin only (`isSuperAdmin` check)
**Tenant-scoping:** `tenantId` extraído do JWT payload

### Endpoints

| Método | Rota | Descrição | Body/Params |
|--------|------|-----------|-------------|
| `GET` | `/api/vpn-configs` | Listar todas as VPNs | — |
| `POST` | `/api/vpn-configs` | Criar nova VPN | `{ name, ovpnConfig, authUser?, authPass?, sshHost, sshPort, sshUser, sshPassword }` |
| `PUT` | `/api/vpn-configs/:id` | Atualizar VPN | Campos parciais |
| `DELETE` | `/api/vpn-configs/:id` | Remover VPN | — |
| `POST` | `/api/vpn-configs/:id/connect` | Conectar VPN | — |
| `POST` | `/api/vpn-configs/:id/disconnect` | Desconectar VPN | — |
| `GET` | `/api/vpn-configs/:id/status` | Verificar status | — |
| `POST` | `/api/vpn-configs/:id/test-connectivity` | Testar conectividade | `{ host, port }` |
| `GET` | `/api/vpn-configs/:id/logs` | Obter logs | `?lines=50` (query param) |

### Validações nas Rotas
- **POST (create):** Valida `tenantId` pertence ao usuário; requer `name`, `sshHost`, `sshPassword`
- **PUT (update):** Valida ownership via `tenantId` antes de atualizar
- **DELETE:** Kill processo remoto + remove arquivos antes de deletar do banco
- **test-connectivity:** Sanitiza `host` (remove chars especiais), limita `port` a 1-65535

---

## 6. Frontend (`client/src/pages/vpn-management.tsx`)

### Componentes Principais
- **VPN Cards:** Lista de VPNs com status (badge colorido), IP, último check
- **Formulário de Criação/Edição:** Campos para nome, SSH, upload de .ovpn, credenciais VPN
- **Botões de Ação:** Conectar, Desconectar, Testar Conectividade, Ver Logs
- **Modal de Logs:** Exibe últimas linhas do log OpenVPN

### Estado e Polling
- **Status polling:** A cada 10 segundos para VPNs com status `connected`
- **Loading states:** Spinner durante operações de connect/disconnect
- **Toast notifications:** Sucesso/erro para todas as operações

### Upload de .ovpn
O frontend permite upload do arquivo .ovpn que é lido como texto e enviado no campo `ovpnConfig` do body.

### Cores de Status
| Status | Cor | Badge |
|--------|-----|-------|
| `connected` | Verde | `bg-green-100 text-green-800` |
| `disconnected` | Cinza | `bg-gray-100 text-gray-800` |
| `error` | Vermelho | `bg-red-100 text-red-800` |

---

## 7. Integração com External DB

O sistema de VPN é usado pelo sistema de External DB Integrations para acessar bancos em redes privadas:

```
ExternalIntegrations.accessMethod = "vpn"
ExternalIntegrations.vpnConfigId → VpnConfigurations.id
```

### Fluxo VPN → DB
```
1. External DB verifica accessMethod === "vpn"
2. Busca VpnConfigurations pelo vpnConfigId (tenant-scoped)
3. Verifica se status === "connected"
4. Usa sshHost/sshPort/sshUser/sshPassword da VPN para criar SSH tunnel
5. Cria port forwarding local (127.0.0.1:random → host:port do DB)
6. Conecta MSSQL via localhost:randomPort
```

### Validação Cross-Tenant
A função `resolveVpnSshConfig(vpnConfigId, tenantId)` em `external-db.service.ts` valida que a VPN pertence ao mesmo tenant da integração, impedindo acesso cross-tenant.

---

## 8. Troubleshooting

### VPN não conecta
1. Verificar se OpenVPN está instalado no VPS: `which openvpn`
2. Verificar logs: `GET /api/vpn-configs/:id/logs`
3. Verificar se o arquivo .ovpn é válido
4. Verificar se as credenciais SSH estão corretas

### VPN conecta mas DB não funciona
1. Testar conectividade: `POST /api/vpn-configs/:id/test-connectivity` com host e port do DB
2. Verificar se `route-nopull` está no .ovpn (deve estar)
3. Verificar se a rota para a rede do DB está sendo pushada pelo servidor VPN

### Status inconsistente
O polling a cada 10s na UI verifica o PID do processo OpenVPN. Se o processo morreu, o status é atualizado para `disconnected` automaticamente.

---

## 9. Checklist para Novo Projeto

Para reimplementar este sistema em outro projeto:

1. **Prisma:** Adicionar modelo `VpnConfigurations` ao schema
2. **Dependências:** `ssh2` (+ `@types/ssh2`)
3. **Service:** Copiar `server/services/vpn.service.ts`
4. **Routes:** Adicionar 9 endpoints em `/api/vpn-configs`
5. **Frontend:** Criar página de gerenciamento com formulário e polling
6. **Menu:** Adicionar entrada no menu de SuperAdmin
7. **Env:** Garantir `SESSION_SECRET` está definido (usado na criptografia)

---

## 10. Centralização de Skills — Repositório Git

Esta skill é mantida no repositório central de skills:
- **Repositório:** `ricardohonoratoherculano-cmd/voxzap-skills` (GitHub privado)
- **Sync:** Use `sync-skills.sh` na raiz do projeto para atualizar skills de/para o repositório
- **Estrutura:** Cada skill em seu diretório: `skills/{nome}/SKILL.md`
