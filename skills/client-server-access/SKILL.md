---
name: client-server-access
description: Acesso operacional do agente Replit aos servidores VPS dos clientes (PlanoClin, Voxzap-Locktec, Voxtel-prod e outros) via SSH com cofre criptografado de credenciais e histórico de interações com busca semântica. Use sempre que o usuário pedir para "acessar o servidor do cliente X", "ver o que está rodando na VPS do X", "executar comando no servidor do X", "lembrar o que fizemos no servidor X", ou referenciar qualquer cliente registrado pelo nome/slug.
---

# Client Server Access — Skill

CLI do agente para acessar VPSes de clientes com cofre AES-256-GCM e histórico de ações pesquisável (embeddings OpenAI quando disponíveis, fallback para palavras-chave).

## Quando ativar

Sempre que o usuário disser algo como:
- "Acesse o servidor da PlanoClin / Locktec / Voxtel ..."
- "Roda `<comando>` na VPS do cliente X"
- "O que tem rodando no servidor do X?"
- "Lembra do que vimos da última vez no X?"
- "Cadastra o servidor do cliente Y"
- "Lista os clientes que eu já cadastrei"

Se o cliente não foi citado, rode `list.mjs` primeiro e pergunte.

## Pré-requisitos (configurar uma vez)

- **Replit Secret `CLIENT_REGISTRY_KEY`** — hex de 64 caracteres (32 bytes). Obrigatório. Sem ele o cofre não abre. **Nunca** colocar como env var compartilhado (vai parar no `.replit` e ser commitado) — sempre como Secret.
- **Replit Secret `OPENAI_API_KEY`** (opcional) — chave OpenAI direta para embeddings semânticos `text-embedding-3-small`. O proxy `AI_INTEGRATIONS_OPENAI_API_KEY` **não** suporta `/embeddings`; quando só ele existe, o sistema cai para busca por palavras-chave (`mode: "keyword"` no output do `search.mjs`).
- Pacote `ssh2` (já no `package.json`).

## Estrutura

```
scripts/clients/
  _lib.mjs        # cripto AES-256-GCM, IO do cofre, embeddings, similaridade
  bootstrap.mjs   # seed inicial (idempotente) — exige env CLIENT_BOOTSTRAP_SSH_PASSWORD
  register.mjs    # cria/atualiza cliente (interativo + flags)
  list.mjs        # lista todos ou um cliente (senhas mascaradas)
  ssh.mjs         # executa comando via SSH e devolve JSON {stdout, stderr, exitCode}
  upload.mjs      # SFTP-upload de arquivo grande (>>10KB) — USAR EM VEZ de base64 inline
  log.mjs         # adiciona acao ao historico (le JSON do stdin)
  search.mjs      # busca top-K acoes similares no historico

.local/
  clients-registry.enc.json                 # cofre AES-256-GCM (gitignored)
  clients-history/<slug>/actions.jsonl      # 1 linha = 1 acao criptografada
  clients-history/<slug>/embeddings.jsonl   # 1 linha = {id, embedding} criptografada
```

## Fluxo padrão (sempre nesta ordem)

1. **Buscar contexto** antes de agir:
   ```bash
   node scripts/clients/search.mjs <slug> "<o que ja sabemos sobre o tema>"
   # ou em todos os clientes:
   node scripts/clients/search.mjs --all "<consulta>"
   ```
2. **Confirmar cliente** se houver dúvida:
   ```bash
   node scripts/clients/list.mjs [<slug>]
   ```
3. **Executar** o comando:
   ```bash
   node scripts/clients/ssh.mjs <slug> '<comando shell>'
   ```
4. **Registrar a ação** no histórico:
   ```bash
   echo '{
     "description": "Inventário inicial de containers no PlanoClin",
     "commands": ["docker ps --format \"{{.Names}}\\t{{.Status}}\""],
     "output": "planoclin-app Up 1h\\nplanoclin-asterisk Up 18h (healthy)\\n...",
     "tags": ["docker", "inventario"],
     "success": true
   }' | node scripts/clients/log.mjs <slug>
   ```

Sempre logar quando: (a) descobrir algo novo, (b) executar mudança, (c) o usuário relatar/resolver problema.

## Transferindo arquivos para a VPS (regra CRÍTICA)

**Decisão rápida** — qual abordagem usar para mover um arquivo do Replit pra VPS?

| Tamanho do arquivo | Ferramenta | Por quê |
|---|---|---|
| `≤ 8 KB` (~snippet, config curto) | `ssh.mjs` com heredoc ou base64 inline | Cabe no `argv` |
| `> 8 KB` (qualquer fonte TS/JS/JSON real) | **`upload.mjs` (SFTP)** | `argv` estoura ("Argument list too long") |

### ✅ Forma correta para arquivos grandes

```bash
node scripts/clients/upload.mjs <slug> <localPath> <remotePath>
# ex:
node scripts/clients/upload.mjs voxzap-voxtel \
  server/services/uazapi.service.ts \
  /opt/tenants/voxzap-voxtel/source/server/services/uazapi.service.ts
# saída: {"ok":true,"bytes":14518,"remotePath":"..."}
```

`upload.mjs` usa o canal SFTP do `ssh2` (que reusa a mesma autenticação do cofre AES-256-GCM), sem prompt de senha, sem limite de argv.

### ❌ Anti-padrões (NÃO repetir)

```bash
# ❌ scp direto — pede senha interativa, quebra os scripts não-tty
scp -P 22300 file root@host:/path           # → "password:" prompt → travamento

# ❌ base64 inline em arg — estoura para arquivos > ~8 KB
B64=$(base64 -w 0 file_grande.ts)
node scripts/clients/ssh.mjs slug "echo '$B64' | base64 -d > /path"
# → "Argument list too long" (exit code 126)

# ❌ heredoc via ssh.mjs — escape de aspas/dolar fica intratável
node scripts/clients/ssh.mjs slug "cat > /path <<'EOF'
... conteúdo com aspas e $vars ...
EOF"
# → frágil, qualquer aspa no source vira shell injection
```

### Limites operacionais

- `ssh.mjs` tem `SSH_TIMEOUT_MS=60000` por padrão. Para builds Docker (>2 min), aumente:
  `SSH_TIMEOUT_MS=180000 node scripts/clients/ssh.mjs slug 'docker compose up -d --build app'`
- Mesmo se o `SSH_TIMEOUT_MS` estourar, o comando **continua rodando na VPS**. Pra confirmar, faça uma segunda chamada `ssh.mjs slug "docker ps"`.

### Executar SQL multi-statement em Postgres dockerizado

**Padrão obrigatório** quando precisar rodar uma análise SQL com `\echo`, múltiplas queries, CTEs longas ou backslash-commands (`\x`, `\pset`, `\d`) num Postgres em container (ex: `voxzap-locktec-db`, `voxzap-voxtel-db`):

```bash
# 1) Escreva o SQL local em .local/tmp/<nome>.sql
# 2) Upload via SFTP
node scripts/clients/upload.mjs <slug> .local/tmp/forensic.sql /tmp/forensic.sql

# 3) docker cp + psql -f (saída direto pro stdout do ssh.mjs)
node scripts/clients/ssh.mjs <slug> 'docker cp /tmp/forensic.sql <slug>-db:/tmp/q.sql \
  && docker exec <slug>-db psql -U <user> -d <db> -f /tmp/q.sql 2>&1'
```

**Por que NÃO usar heredoc inline**: heredocs com `\echo`, aspas duplas escapadas e `\\"colName\\"` passados pelo `argv` do `ssh.mjs` frequentemente chegam vazios no `docker exec -- psql` — vimos casos onde a query rodou (`exitCode=0`, `durationMs ~2s`) mas o `stdout` veio vazio porque o pipe stdin se perdeu na cadeia ssh→docker→psql. Anti-padrão real:

```bash
# ❌ Heredoc multi-statement com \echo — falha silenciosa frequente
node scripts/clients/ssh.mjs slug "docker exec slug-db psql -U user -d db <<'SQL'
\echo === BLOCO 1 ===
SELECT ...
SQL"
# → exitCode=0, stdout vazio, sem erro
```

**Se a saída ficar truncada pelo wrapper JSON do ssh.mjs** (queries que devolvem >100 linhas):

```bash
# Salva no servidor, baixa só a parte relevante
node scripts/clients/ssh.mjs slug 'docker exec slug-db psql -U user -d db -f /tmp/q.sql > /tmp/out.txt 2>&1; wc -l /tmp/out.txt'
node scripts/clients/ssh.mjs slug 'cat /tmp/out.txt' > .local/tmp/out.json
node -e "console.log(require('./.local/tmp/out.json').stdout)" | head -200
```

**Backup ANTES de qualquer DELETE/UPDATE em produção**: convenção é salvar em `/opt/tenants/<slug>/backups/<tabela>-pre-<motivo>-<YYYYMMDD>.sql`:

```bash
node scripts/clients/ssh.mjs <slug> 'mkdir -p /opt/tenants/<slug>/backups && \
  docker exec <slug>-db pg_dump -U <user> -d <db> -t '"'"'"<Tabela>"'"'"' \
  --data-only --column-inserts > /opt/tenants/<slug>/backups/<tabela>-pre-<motivo>-$(date +%Y%m%d).sql'
```

**Convenção de nomes nos containers VoxZap multi-tenant**: `<slug>-app` (Node) e `<slug>-db` (Postgres). Credenciais default herdadas do template: usuário `voxzap`, banco `voxzap`. Tabelas em camelCase com aspas duplas obrigatórias (`"Tickets"`, `"UserWhatsapps"`); colunas datetime tipo `bigint` em ms (use `to_timestamp(col/1000) AT TIME ZONE 'America/Sao_Paulo'` para legibilidade).

## Cadastrar novo cliente

Interativo (recomendado):
```bash
node scripts/clients/register.mjs
# responde os prompts: nome, descricao, tags, host, porta, usuario, senha, etc.
```

Não-interativo (CI / batch):
```bash
CLIENT_SSH_PASSWORD='<senha>' node scripts/clients/register.mjs \
  --name "Cliente XYZ" --host 1.2.3.4 --port 22 --user root \
  --description 'VPS dedicada' --tags producao,vpn-required \
  --notes 'requer VPN OpenVPN antes do SSH'
```

A senha **nunca** deve ir em `--password` no shell history se possível — use prompt interativo ou env `CLIENT_SSH_PASSWORD`.

## Comandos destrutivos

`ssh.mjs` bloqueia por padrão estes padrões: `rm -rf /`, `mkfs`, `dd if=`, `shutdown`, `reboot`, `halt`, `poweroff`, `drop database/table`, `truncate table`, `systemctl stop|disable|mask`, `docker [compose] rm|down|stop|kill`, `docker system prune`, `killall`, `kill -9`, redirect para `/dev/sd*`.

Para executar mesmo assim:
1. **Sempre confirmar com o usuário em linguagem natural** antes — explicar o que será feito e por quê.
2. Re-executar com `CONFIRM_DESTRUCTIVE=yes` no env do comando.
3. **Logar imediatamente** no histórico do cliente após o sucesso.

A regex é "redutor de acidentes", não barreira de segurança real (truques de shell podem burlar). A confirmação humana é o controle de verdade.

## Convenções

- **Slug**: kebab-case sem acento. Ex.: `planoclin`, `voxzap-locktec`, `voxtel-prod`.
- **Tags úteis**: `multi-tenant`, `producao`, `homologacao`, `voxcall`, `voxzap`, `voxtel`, `asterisk`, `whatsapp`, `vpn-required`.
- **`description`** no log: 1 frase descrevendo o que foi feito.
- **`commands`**: array com os comandos exatos executados (sem senhas).
- **`output`**: trecho relevante da saída (será truncado em ~8KB).
- **`tags`**: 2-5 tags estáveis para categorizar.

## Não logar

- Senhas, tokens, chaves privadas, hashes bcrypt.
- Dados pessoais de contatos (telefones, emails) salvo necessidade técnica.
- Output bruto longo de queries — só o resumo / contagem.

## Segurança

- Cofre escrito com mode `0600`, write-then-rename atômico.
- AES-256-GCM com IV aleatório de 12 bytes por registro, auth tag verificada no decrypt.
- `getKey()` exige hex estrito de 64 chars (regex), sem truncamento silencioso.
- Senhas mascaradas em todo output (`maskClient` retorna `********`).
- Comandos SSH via lib `ssh2` (não invoca `sshpass` — a senha não vaza em `ps`).
- `.gitignore` bloqueia `.local/clients-registry.enc.json` e `.local/clients-history/`.
- O secret `CLIENT_REGISTRY_KEY` deve estar no painel de Secrets do Replit, **nunca** em env vars compartilhadas (que vão para `.replit` e são commitadas).

## Clientes seed (bootstrap)

Todos no servidor multi-tenant `eveo1` (`177.104.171.145:22300`, user `root`):
- `planoclin` — VoxCALL + Asterisk (com tunel reverso ARI para `pabx-izzy`)
- `voxzap-locktec` — VoxZap (WhatsApp Cloud API), migração ZPro
- `voxtel-prod` — Voxtel institucional / gerador de propostas (stack IA: llm/asr/tts/postgres)

Re-bootstrap (idempotente):
```bash
CLIENT_BOOTSTRAP_SSH_PASSWORD='<senha-compartilhada>' node scripts/clients/bootstrap.mjs
```

## Skills relacionadas

- `multi-tenant-server` — provisionamento dos tenants no eveo1.
- `vpn-management-expert` — clientes que exigem VPN antes do SSH.
- `remote-db-diagnostic` — diagnóstico de PostgreSQL via SSH.
- `diagnostic-assistant-expert` — assistente in-app que faz algo análogo via UI no VoxCALL.
