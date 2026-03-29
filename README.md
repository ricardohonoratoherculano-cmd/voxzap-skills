# VoxZap Skills — Repositório Central

  Repositório central de skills para projetos VoxZap/VoxCALL.
  Skills são documentações especializadas que permitem ao agente IA reproduzir ou modificar funcionalidades em qualquer projeto.

  ## Skills Disponíveis

  | Skill | Descrição |
  |-------|-----------|
  | actyon-crm | Especialista no banco de dados Actyon Smartcob |
  | ai-agent-expert | Especialista em agentes de IA |
  | assistente-ia-rag | Assistente de IA com RAG |
  | asterisk-ari-expert | Especialista em Asterisk REST Interface |
  | asterisk-callcenter-expert | Especialista em Call Center com Asterisk/PostgreSQL |
  | deploy-assistant-vps | Deploy de aplicações Node.js em VPS via Docker |
  | diagnostic-assistant-expert | Assistente de Diagnóstico VoxCALL |
  | external-db-integration | Integração com bancos de dados externos |
  | remote-db-diagnostic | Diagnóstico remoto de PostgreSQL |
  | s4e-crm | Especialista no banco de dados S4E/Izysoft |
  | voxfone-telephony-crm | Sistema CRM de telefonia VoxFone |
  | vpn-management-expert | Gerenciamento de VPN para redes privadas |
  | whatsapp-calling-expert | WhatsApp Business Calling API |
  | whatsapp-messaging-expert | WhatsApp Cloud API e mensageria |

  ## Como Usar

  ### 1. Conectar GitHub no Replit
  No projeto Replit, adicionar a integração GitHub (connector).

  ### 2. Configurar Token
  Obter um Personal Access Token (PAT) do GitHub com permissão `repo` e configurar como variável de ambiente:
  ```bash
  export GITHUB_TOKEN="ghp_xxxx"
  ```

  ### 3. Sincronizar
  Copiar o script `sync-skills.sh` para a raiz do projeto e executar:

  ```bash
  # Baixar todas as skills do GitHub
  ./sync-skills.sh pull

  # Baixar skill específica
  ./sync-skills.sh pull vpn-management-expert

  # Enviar skills atualizadas para o GitHub
  ./sync-skills.sh push

  # Enviar skills específicas
  ./sync-skills.sh push actyon-crm s4e-crm

  # Ver status
  ./sync-skills.sh status

  # Listar skills
  ./sync-skills.sh list
  ```

  ## Estrutura
  ```
  skills/
    actyon-crm/
      SKILL.md
    vpn-management-expert/
      SKILL.md
    external-db-integration/
      SKILL.md
    ...
  ```

  Cada skill contém um `SKILL.md` (obrigatório) e opcionalmente arquivos auxiliares.

  ## Sync Script
  O arquivo `sync-skills.sh` pode ser copiado para qualquer projeto Replit. Ele sincroniza skills entre o projeto local (`.agents/skills/`) e este repositório (`skills/`).
  