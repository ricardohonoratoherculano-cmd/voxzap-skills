---
name: skills-sync
description: Sincronização automática de skills entre projetos via repositório GitHub central. Use quando o usuário pedir para "atualizar as skills", "sincronizar skills", "atualizar skills correspondentes", "baixar skills do GitHub", "enviar skills para o GitHub", ou qualquer variação. Executa o script sync-skills.sh automaticamente.
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

- **Repositório:** `ricardohonoratoherculano-cmd/voxzap-skills` (GitHub privado)
- **Estrutura:** `skills/{nome-da-skill}/SKILL.md`
- **Local no projeto:** `.agents/skills/`

## Instruções de Execução

### Passo 1: Verificar se o script existe

Verificar se `sync-skills.sh` existe na raiz do projeto. Se não existir, criar com o conteúdo abaixo:

```bash
#!/bin/bash
set -euo pipefail

REPO_URL="https://github.com/ricardohonoratoherculano-cmd/voxzap-skills.git"
SKILLS_DIR=".agents/skills"
TEMP_DIR="/tmp/voxzap-skills-sync"
MODE="${1:-pull}"
SPECIFIC_SKILLS="${@:2}"

clone_or_pull_repo() {
  if [ -d "$TEMP_DIR/.git" ]; then
    cd "$TEMP_DIR" && git pull origin main 2>/dev/null || git pull origin master 2>/dev/null
    cd - > /dev/null
  else
    rm -rf "$TEMP_DIR"
    git clone "$REPO_URL" "$TEMP_DIR" 2>/dev/null
    if [ $? -ne 0 ]; then
      echo "Erro ao clonar. Verifique se o GitHub está conectado."
      exit 1
    fi
  fi
}

do_pull() {
  clone_or_pull_repo
  mkdir -p "$SKILLS_DIR"
  local count=0
  if [ -n "${SPECIFIC_SKILLS:-}" ]; then
    for skill in $SPECIFIC_SKILLS; do
      if [ -d "$TEMP_DIR/skills/$skill" ]; then
        cp -r "$TEMP_DIR/skills/$skill" "$SKILLS_DIR/"
        echo "  ✓ $skill"
        count=$((count + 1))
      else
        echo "  ✗ $skill (não encontrada)"
      fi
    done
  else
    for skill_dir in "$TEMP_DIR/skills"/*/; do
      if [ -d "$skill_dir" ]; then
        skill_name=$(basename "$skill_dir")
        cp -r "$skill_dir" "$SKILLS_DIR/"
        echo "  ✓ $skill_name"
        count=$((count + 1))
      fi
    done
  fi
  echo "$count skill(s) sincronizada(s) do GitHub → projeto"
  rm -rf "$TEMP_DIR"
}

do_push() {
  clone_or_pull_repo
  mkdir -p "$TEMP_DIR/skills"
  local count=0
  if [ -n "${SPECIFIC_SKILLS:-}" ]; then
    for skill in $SPECIFIC_SKILLS; do
      if [ -d "$SKILLS_DIR/$skill" ]; then
        cp -r "$SKILLS_DIR/$skill" "$TEMP_DIR/skills/"
        echo "  ✓ $skill"
        count=$((count + 1))
      fi
    done
  else
    for skill_dir in "$SKILLS_DIR"/*/; do
      if [ -d "$skill_dir" ]; then
        skill_name=$(basename "$skill_dir")
        cp -r "$skill_dir" "$TEMP_DIR/skills/"
        echo "  ✓ $skill_name"
        count=$((count + 1))
      fi
    done
  fi
  cd "$TEMP_DIR"
  git add -A
  local changes
  changes=$(git status --porcelain)
  if [ -z "$changes" ]; then
    echo "Sem alterações para enviar."
    cd - > /dev/null
    return
  fi
  git commit -m "sync: atualizar $count skill(s) - $(date '+%Y-%m-%d %H:%M')"
  git push origin main 2>/dev/null || git push origin master 2>/dev/null
  echo "$count skill(s) enviada(s) para o GitHub"
  cd - > /dev/null
}

case "$MODE" in
  pull)  do_pull ;;
  push)  do_push ;;
  *)     do_pull ;;
esac
```

### Passo 2: Verificar integração GitHub

A integração GitHub do Replit deve estar conectada neste projeto. Se não estiver:
1. Propor a integração GitHub ao usuário
2. Aguardar a conexão ser estabelecida

### Passo 3: Executar a sincronização

Determinar a direção com base no contexto:

**Se o usuário criou/editou skills neste projeto e quer atualizar o repositório:**
```bash
chmod +x sync-skills.sh && ./sync-skills.sh push
```

**Se o usuário quer baixar skills atualizadas do repositório (padrão):**
```bash
chmod +x sync-skills.sh && ./sync-skills.sh pull
```

**Se o contexto não é claro, fazer ambos:**
```bash
chmod +x sync-skills.sh && ./sync-skills.sh push && ./sync-skills.sh pull
```

### Passo 4: Confirmar ao usuário

Listar as skills sincronizadas e confirmar o sucesso.

## Regras

1. **Sempre executar automaticamente** — não perguntar ao usuário se ele quer executar, apenas faça
2. **Preferir push+pull** quando o contexto indica que houve edições locais
3. **Se o git clone falhar**, verificar se a integração GitHub está conectada e propor reconectar
4. **Esta skill deve existir em todos os projetos** — ela própria é sincronizada via o repositório central
