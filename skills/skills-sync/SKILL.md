---
name: skills-sync
description: Sincronização automática de skills entre projetos via repositório GitHub central (público). Use quando o usuário pedir para "atualizar as skills", "sincronizar skills", "atualizar skills correspondentes", "baixar skills do GitHub", "enviar skills para o GitHub", ou qualquer variação. Executa o script sync-skills.sh automaticamente.
---

# Sincronização de Skills — Repositório Central GitHub

## Quando Ativar

Ative esta skill quando o usuário disser qualquer variação de:
- "Atualize as skills" / "Atualize as skills correspondentes"
- "Sincronize as skills" / "Sincronizar skills"
- "Baixe as skills do GitHub" / "Puxe as skills"
- "Envie as skills para o GitHub" / "Suba as skills"
- "Atualize o repositório de skills"
- "Skills sync" / "Sync skills"

## Repositório Central

- **Repositório:** `ricardohonoratoherculano-cmd/voxzap-skills` (GitHub **público**)
- **Estrutura:** `skills/{nome-da-skill}/SKILL.md`
- **Local no projeto:** `.agents/skills/`
- **Pull (baixar):** Não precisa de token — repo público
- **Push (enviar):** Precisa do token da integração GitHub do Replit

## Instruções de Execução

### Passo 1: Verificar se o script existe

O arquivo `sync-skills.sh` deve existir na raiz do projeto. Se não existir, criar com o conteúdo do script abaixo.

### Passo 2: Executar a sincronização

**Pull (baixar skills do GitHub — funciona sem token):**
```bash
chmod +x sync-skills.sh && ./sync-skills.sh pull
```

**Push (enviar skills para o GitHub — precisa de token):**

O push precisa do token da integração GitHub. Obter via `listConnections('github')` no code_execution, salvar em `/tmp/.gh_token`, e executar:

```javascript
// No code_execution:
const conns = await listConnections('github');
const token = conns[0].settings.access_token;
const { writeFileSync } = await import('fs');
writeFileSync('/tmp/.gh_token', token, { mode: 0o600 });
```

```bash
GITHUB_TOKEN=$(cat /tmp/.gh_token) bash sync-skills.sh push; rm -f /tmp/.gh_token
```

**Se o contexto indica edições locais, fazer push primeiro e depois pull:**
```bash
# Push com token (ver acima), depois:
./sync-skills.sh pull
```

### Passo 3: Confirmar ao usuário

Listar as skills sincronizadas e confirmar o sucesso.

## Comandos Disponíveis

```bash
./sync-skills.sh pull                          # Baixa todas as skills
./sync-skills.sh pull skill-name               # Baixa skill específica
GITHUB_TOKEN=xxx ./sync-skills.sh push         # Envia todas as skills
GITHUB_TOKEN=xxx ./sync-skills.sh push skill-1 # Envia skills específicas
./sync-skills.sh list                          # Lista skills locais
```

## Regras

1. **Sempre executar automaticamente** — não perguntar ao usuário se ele quer executar, apenas faça
2. **Preferir push+pull** quando o contexto indica que houve edições locais
3. **Pull nunca falha** — repo é público, não precisa de autenticação
4. **Push precisa de token** — usar integração GitHub do Replit via `listConnections('github')`
5. **Nunca imprimir o token** — sistema Replit redacta tokens expostos no stdout
6. **Esta skill deve existir em todos os projetos** — ela própria é sincronizada via o repositório central
