#!/bin/bash
REPO_URL="https://github.com/ricardohonoratoherculano-cmd/voxzap-skills.git"
SKILLS_DIR=".agents/skills"
TEMP_DIR="/tmp/voxzap-skills-sync"
MODE="${1:-pull}"
SPECIFIC_SKILLS="${@:2}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

show_help() {
  echo "VoxZap Skills Sync — Sincronização com GitHub"
  echo ""
  echo "Uso: ./sync-skills.sh [comando] [skills...]"
  echo ""
  echo "Comandos:"
  echo "  pull     Baixa skills do GitHub para o projeto (padrão)"
  echo "  push     Envia skills do projeto para o GitHub"
  echo "  status   Mostra diferenças entre local e remoto"
  echo "  list     Lista skills disponíveis"
  echo "  help     Mostra esta ajuda"
  echo ""
  echo "Exemplos:"
  echo "  ./sync-skills.sh pull                     # Baixa todas as skills"
  echo "  ./sync-skills.sh pull vpn-management-expert  # Baixa skill específica"
  echo "  ./sync-skills.sh push                     # Envia todas as skills"
  echo "  ./sync-skills.sh push actyon-crm s4e-crm  # Envia skills específicas"
  echo "  ./sync-skills.sh status                   # Mostra diferenças"
  echo ""
  echo "Pré-requisito: Token GitHub configurado em GITHUB_TOKEN ou GH_TOKEN"
}

get_token() {
  if [ -n "$GITHUB_TOKEN" ]; then
    echo "$GITHUB_TOKEN"
  elif [ -n "$GH_TOKEN" ]; then
    echo "$GH_TOKEN"
  else
    echo ""
  fi
}

setup_auth_url() {
  local token
  token=$(get_token)
  if [ -n "$token" ]; then
    echo "https://${token}@github.com/ricardohonoratoherculano-cmd/voxzap-skills.git"
  else
    echo "$REPO_URL"
  fi
}

clone_or_pull_repo() {
  local auth_url
  auth_url=$(setup_auth_url)

  if [ -d "$TEMP_DIR/.git" ]; then
    echo -e "${YELLOW}Atualizando repositório...${NC}"
    cd "$TEMP_DIR" && git pull origin main 2>/dev/null || git pull origin master 2>/dev/null
    cd - > /dev/null
  else
    echo -e "${YELLOW}Clonando repositório...${NC}"
    rm -rf "$TEMP_DIR"
    git clone "$auth_url" "$TEMP_DIR" 2>/dev/null
    if [ $? -ne 0 ]; then
      echo -e "${RED}Erro ao clonar. Verifique o token e as permissões.${NC}"
      exit 1
    fi
  fi
}

do_pull() {
  clone_or_pull_repo

  if [ ! -d "$TEMP_DIR/skills" ]; then
    echo -e "${RED}Diretório 'skills' não encontrado no repositório.${NC}"
    exit 1
  fi

  mkdir -p "$SKILLS_DIR"

  local count=0
  if [ -n "$SPECIFIC_SKILLS" ]; then
    for skill in $SPECIFIC_SKILLS; do
      if [ -d "$TEMP_DIR/skills/$skill" ]; then
        cp -r "$TEMP_DIR/skills/$skill" "$SKILLS_DIR/"
        echo -e "  ${GREEN}✓${NC} $skill"
        count=$((count + 1))
      else
        echo -e "  ${RED}✗${NC} $skill (não encontrada no repositório)"
      fi
    done
  else
    for skill_dir in "$TEMP_DIR/skills"/*/; do
      if [ -d "$skill_dir" ]; then
        skill_name=$(basename "$skill_dir")
        cp -r "$skill_dir" "$SKILLS_DIR/"
        echo -e "  ${GREEN}✓${NC} $skill_name"
        count=$((count + 1))
      fi
    done
  fi

  echo -e "\n${GREEN}$count skill(s) sincronizada(s) do GitHub → projeto${NC}"
}

do_push() {
  clone_or_pull_repo

  mkdir -p "$TEMP_DIR/skills"

  local count=0
  if [ -n "$SPECIFIC_SKILLS" ]; then
    for skill in $SPECIFIC_SKILLS; do
      if [ -d "$SKILLS_DIR/$skill" ]; then
        cp -r "$SKILLS_DIR/$skill" "$TEMP_DIR/skills/"
        echo -e "  ${GREEN}✓${NC} $skill"
        count=$((count + 1))
      else
        echo -e "  ${RED}✗${NC} $skill (não encontrada localmente)"
      fi
    done
  else
    for skill_dir in "$SKILLS_DIR"/*/; do
      if [ -d "$skill_dir" ]; then
        skill_name=$(basename "$skill_dir")
        cp -r "$skill_dir" "$TEMP_DIR/skills/"
        echo -e "  ${GREEN}✓${NC} $skill_name"
        count=$((count + 1))
      fi
    done
  fi

  cd "$TEMP_DIR"
  git add -A
  local changes
  changes=$(git status --porcelain)
  if [ -z "$changes" ]; then
    echo -e "\n${YELLOW}Sem alterações para enviar.${NC}"
    cd - > /dev/null
    return
  fi

  git commit -m "sync: atualizar $count skill(s) - $(date '+%Y-%m-%d %H:%M')"
  git push origin main 2>/dev/null || git push origin master 2>/dev/null

  if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}$count skill(s) enviada(s) para o GitHub${NC}"
  else
    echo -e "\n${RED}Erro ao enviar. Verifique o token e as permissões.${NC}"
  fi
  cd - > /dev/null
}

do_status() {
  clone_or_pull_repo

  echo -e "\n${YELLOW}Skills locais:${NC}"
  for skill_dir in "$SKILLS_DIR"/*/; do
    if [ -d "$skill_dir" ]; then
      echo "  $(basename "$skill_dir")"
    fi
  done

  echo -e "\n${YELLOW}Skills no repositório:${NC}"
  if [ -d "$TEMP_DIR/skills" ]; then
    for skill_dir in "$TEMP_DIR/skills"/*/; do
      if [ -d "$skill_dir" ]; then
        echo "  $(basename "$skill_dir")"
      fi
    done
  else
    echo "  (nenhuma)"
  fi
}

do_list() {
  echo -e "${YELLOW}Skills disponíveis localmente:${NC}"
  for skill_dir in "$SKILLS_DIR"/*/; do
    if [ -d "$skill_dir" ]; then
      local name
      name=$(basename "$skill_dir")
      local desc=""
      if [ -f "$skill_dir/SKILL.md" ]; then
        desc=$(grep "^description:" "$skill_dir/SKILL.md" | head -1 | sed 's/^description: //' | cut -c1-80)
      fi
      echo -e "  ${GREEN}$name${NC}"
      if [ -n "$desc" ]; then
        echo "    $desc"
      fi
    fi
  done
}

case "$MODE" in
  pull)   do_pull ;;
  push)   do_push ;;
  status) do_status ;;
  list)   do_list ;;
  help)   show_help ;;
  *)      show_help ;;
esac
