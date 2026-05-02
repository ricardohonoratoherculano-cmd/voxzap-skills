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
