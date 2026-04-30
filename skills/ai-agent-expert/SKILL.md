# AI Agent Expert - VoxZap

Especialista no sistema de Agentes de IA para atendimento automático ao cliente no VoxZap. Use quando o usuário pedir para criar, modificar, debugar ou estender funcionalidades relacionadas a agentes de IA, incluindo RAG, transcrição de áudio, transferência para fila humana, base de conhecimento, ou qualquer funcionalidade do sistema de agentes IA.

## Arquitetura

### Modelos Prisma

#### AiAgents
Tabela principal dos agentes de IA.
- `id`, `name`, `tenantId` (multi-tenant)
- `provider`: "openai" | "gemini" | "claude" | "deepseek"
- `apiKey`: Chave API do provedor (criptografada em trânsito, mascarada no frontend)
- `model`: ex: "gpt-4o-mini", "gemini-2.0-flash", "claude-sonnet-4-20250514"
- `systemPrompt`: Personalidade, regras, tom do agente
- `maxBotRetries`: Padrão 5 — após N msgs sem resolver, transfere para fila
- `transferQueueId`: FK → Queues — fila para transferência
- `transferKeywords`: JSON array de palavras-chave que disparam transferência
- `transcribeAudio`: boolean — transcrever áudios via Whisper API
- `whisperModel`: Padrão "whisper-1"
- `temperature`, `maxTokens`, `contextMessages`: Parâmetros LLM
- `isActive`: Liga/desliga o agente

#### AiAgentFiles
Arquivos da base de conhecimento por agente.
- `agentId`, `tenantId`, `fileName`, `originalName`, `size`, `type`
- `status`: "processing" | "ready" | "error"
- `chunksCount`: Quantidade de chunks gerados
- Relação cascade com `AiAgentChunks`

#### AiAgentChunks
Chunks indexados para busca TF-IDF.
- `fileId`, `agentId`, `tenantId`, `content`, `tokens`, `metadata`
- Cascade delete com `AiAgentFiles` e `AiAgents`

#### Whatsapps.aiAgentId
Campo FK opcional na tabela `Whatsapps` que vincula um canal a um agente IA.

### Serviço Backend: `server/services/ai-agent.service.ts`

Funções exportadas:
- `processAgentFile(agentId, tenantId, fileId, filePath, originalName)` — Extrai texto (PDF, DOCX, PPTX, TXT, MD, CSV), chunka em ~500 tokens, salva chunks no banco
- `processUrlScrape(agentId, tenantId, url)` — Raspagem profissional de URL com pipeline Cheerio→Readability→Turndown (ver seção "Pipeline de Raspagem Web" abaixo)
- `processMessageWithAgent(agentId, ticketId, tenantId, messageText, contactId, connectionId, contactNumber)` — Fluxo completo: verifica keywords → verifica maxRetries → busca chunks TF-IDF → monta contexto → chama LLM → detecta [TRANSFERIR] → incrementa botRetries
- `testAgentChat(agentId, message, history)` — Chat de teste (sem salvar mensagens)
- `transcribeAudio(apiKey, audioBuffer, whisperModel, provider)` — Transcrição multi-provider: Whisper API (OpenAI) ou Gemini generateContent (Google)
- `checkTransferKeywords(text, keywords)` — Verifica se texto contém keyword de transferência
- `downloadWhatsAppAudio(mediaId, token)` — Baixa áudio do WhatsApp via Graph API

### Integração no Webhook: `server/services/webhook.service.ts`

Método `handleAiAgent()` inserido no `processMessages()`:
1. Executa APÓS mensagem ser salva e ticket atualizado
2. Só processa se `ticket.status === "pending"` E `connection.aiAgentId` existe
3. Fluxo:
   - Se áudio + `transcribeAudio` habilitado → transcreve via Whisper
   - Chama `processMessageWithAgent`
   - Se resposta existe → envia via WhatsApp + salva mensagem bot
   - Se `transferred` → atualiza ticket (status pending, queueId, reseta botRetries)

### Rotas API: `server/routes.ts`

| Rota | Método | Descrição |
|------|--------|-----------|
| `/api/ai-agents` | GET | Lista agentes do tenant |
| `/api/ai-agents/:id` | GET | Detalhes do agente |
| `/api/ai-agents` | POST | Cria agente |
| `/api/ai-agents/:id` | PUT | Atualiza agente |
| `/api/ai-agents/:id` | DELETE | Remove agente (desvincula canais) |
| `/api/ai-agents/:id/files` | POST | Upload de arquivo (multipart) |
| `/api/ai-agents/:id/files/:fileId` | DELETE | Remove arquivo e chunks |
| `/api/ai-agents/:id/test-chat` | POST | Chat de teste |
| `/api/ai-agents/:id/test-audio` | POST | Chat de teste com áudio (multipart) |
| `/api/ai-agents/:id/scrape-url` | POST | Raspagem profissional de URL para base de conhecimento |
| `/api/ai-agents/:id/analyze-knowledge` | POST | Analisa base e sugere prompt otimizada |

### Frontend: `client/src/pages/agentes-ia.tsx`

Página de gestão com:
- Lista de agentes em cards (nome, provedor, modelo, status, arquivos, fila)
- Dialog de criar/editar com 3 tabs:
  - **Configuração**: Nome, provedor, modelo, API key, prompt, temperatura, etc.
  - **Base de Conhecimento**: Upload/delete de arquivos com status + campo URL para raspagem web + botão "Analisar Base" para gerar prompt otimizada
  - **Teste**: Chat integrado para testar respostas (texto + gravação de áudio com MediaRecorder)
- Delete com AlertDialog de confirmação
- Select de Agente IA no dialog de edição de canal (`canais.tsx`)

### Sidebar
Item "Agentes IA" com ícone `Bot` (lucide-react), adminOnly.

### Pipeline de Raspagem Web (URL Scraping)

Função `scrapeUrlToMarkdown(url)` em `ai-agent.service.ts` implementa raspagem profissional de nível comparável a Firecrawl/Jina Reader:

```
URL → fetch (User-Agent Chrome real)
  → Cheerio: pré-limpeza HTML (20+ seletores de ruído)
  → @mozilla/readability: extração automática de conteúdo principal
  → Turndown + GFM: conversão HTML→Markdown (preserva títulos, listas, tabelas)
  → chunkText(): divide em chunks de ~500 tokens
  → Salva chunks no banco
```

#### Etapas do Pipeline:
1. **Validação de segurança** (`isUrlSafe`): bloqueia localhost, IPs privados (10.x, 172.16-31.x, 192.168.x), metadata endpoints, protocolos não-HTTP
2. **Fetch**: User-Agent real de Chrome, headers Accept-Language pt-BR, timeout 30s, limite 10MB
3. **Cheerio pré-limpeza**: remove `<script>`, `<style>`, `<nav>`, `<footer>`, `<header>`, `<aside>`, cookie banners, ads, modals, popups, breadcrumbs, search forms, elementos hidden
4. **@mozilla/readability**: mesmo motor do Firefox Reader View — identifica automaticamente o "artigo" principal da página, descartando sidebar/menu/footer
5. **Fallback em 3 níveis** (se Readability falha):
   - CSS selectors: `main`, `article`, `[role=main]`, `#content`, `.content`, `.entry-content`, etc.
   - Next.js SSR: extrai dados de `<script id="__NEXT_DATA__">` para sites SPA com SSR
   - Body completo: último recurso com log de aviso
6. **Turndown + GFM plugin**: converte HTML→Markdown preservando:
   - Hierarquia de títulos (h1-h6 → `#`, `##`, etc.)
   - Listas (ordenadas e não-ordenadas)
   - **Tabelas HTML → Markdown tables** (via `turndown-plugin-gfm`)
   - Strikethrough
   - Links com URL preservada
7. **Limpeza final**: remove imagens sem alt, links vazios, espaços excessivos

#### Constantes:
- `BROWSER_USER_AGENT`: Chrome 131 real
- `NOISE_SELECTORS`: 20+ seletores CSS de ruído
- `MAIN_CONTENT_SELECTORS`: seletores CSS para conteúdo principal (fallback)
- `MAX_RESPONSE_SIZE`: 10MB

#### Dependências:
- `cheerio` — Parser HTML server-side rápido
- `@mozilla/readability` — Algoritmo Readability do Firefox
- `turndown` — Conversor HTML→Markdown
- `turndown-plugin-gfm` — Plugin GFM (tabelas, strikethrough)
- `jsdom` — DOM virtual necessário pelo Readability

#### Entradas de URL no banco:
- `AiAgentFiles.type = ".url"` — Identifica entradas de raspagem vs upload
- `AiAgentFiles.originalName` — Contém a URL original completa
- `AiAgentFiles.fileName` — `scrape_{timestamp}.md`

### Transcrição de Áudio Multi-Provider

Função `transcribeAudio(apiKey, audioBuffer, whisperModel, provider)`:
- **provider="openai"** (padrão): usa `transcribeWithWhisper()` → OpenAI Whisper API
- **provider="gemini"**: usa `transcribeWithGemini()` → Google Gemini `generateContent` com áudio base64

No webhook, o provider é determinado pelo `agent.provider` do agente IA vinculado ao canal.

## Fluxo de Processamento

```
Mensagem WhatsApp chega → webhook
  ├── Encontra/Cria Contato
  ├── Intercepta Avaliação (0-5)
  ├── FindOrCreate Ticket
  ├── Business Hours check (se novo ticket)
  ├── Extrai conteúdo da mensagem
  ├── Salva mensagem incoming
  ├── Atualiza ticket (lastMessage, unread)
  ├── Broadcast via WebSocket
  └── SE ticket.status === "pending" E connection.aiAgentId:
      ├── Carrega agente do banco
      ├── SE áudio + transcribeAudio → Whisper API
      ├── Verifica keywords de escape → transfere
      ├── Verifica maxBotRetries → transfere
      ├── Busca chunks TF-IDF (base do agente)
      ├── Monta contexto: systemPrompt + chunks + histórico
      ├── Chama LLM (OpenAI/Gemini/Claude/DeepSeek)
      ├── SE resposta contém [TRANSFERIR] → transfere
      ├── Envia resposta via WhatsApp
      ├── Salva mensagem bot (fromMe: true)
      ├── Broadcast via WebSocket
      └── Incrementa botRetries no ticket
```

## Arquivos de Upload
Armazenados em `uploads/ai-agents/` com nomes `{timestamp}-{originalName}`.

## Provedores Suportados
- **OpenAI**: Via SDK oficial, modelos GPT-4o, GPT-4o-mini, GPT-3.5-turbo
- **Gemini**: Via `@google/generative-ai`, modelos Gemini 2.0/1.5
- **Claude**: Via API REST direta (Anthropic), modelos Claude 3.5/4
- **DeepSeek**: Via OpenAI SDK com baseURL customizada

## Uso Compartilhado do Provedor LLM

A configuração de provedor LLM do `AiAgents` é reutilizada pelo **Assistente IA para Templates** (`server/services/template-ai.service.ts`). Este serviço:
- Auto-detecta o provedor/apiKey/modelo a partir do primeiro registro `AiAgents` ativo do tenant
- Rota `GET /api/templates/ai-check` verifica disponibilidade do LLM
- Rota `POST /api/templates/ai-generate` gera/melhora templates usando o mesmo provedor
- Suporta modo criação (gerar novo template) e modo edição (analisar rejeitados e sugerir melhorias)
- Ver documentação completa na skill `whatsapp-messaging-expert` → "Assistente IA para Templates"

## Sistema de Recomendações do Administrador

Campo `recommendations` (TEXT nullable) na tabela `AiAgents` que permite ao administrador definir regras de prioridade máxima que prevalecem sobre QUALQUER instrução do system prompt ou da base de conhecimento.

### Arquitetura

- **Campo no banco**: `AiAgents.recommendations` (TEXT, nullable)
- **Frontend**: Textarea "Recomendações para a Prompt" na aba "Base de Conhecimento", abaixo da lista de arquivos e acima do botão "Analisar Base"
- **Persistência**: Salvo junto com o agente no PUT `/api/ai-agents/:id`
- **Carregamento**: Populado ao abrir o dialog de edição do agente

### Função `applyRecommendationsOverride()`

Localizada em `server/services/ai-agent.service.ts`. Recebe o system prompt base e as recomendações, retorna o prompt com bloco de OVERRIDE no topo.

Comportamento:
1. Se `recommendations` é null/vazio → retorna system prompt inalterado
2. Se preenchido → divide as recomendações por vírgula, ponto-e-vírgula ou quebra de linha
3. Formata cada recomendação como regra numerada
4. Injeta bloco `### ⚠️ OVERRIDE DO ADMINISTRADOR ###` no TOPO do system prompt
5. Inclui instruções explícitas de que estas regras prevalecem sobre qualquer conflito

### Onde é Aplicado

As recomendações são injetadas em **3 pontos**:

1. **`processMessageWithAgent()`** — Atendimento real via WhatsApp
2. **`testAgentChat()`** — Aba "Teste" no frontend
3. **`analyzeKnowledgeBase()`** — Análise da base de conhecimento (meta-prompt para gerar suggestedPrompt)

### Máscaras de Formatação Brasileiras

Quando o administrador usa termos como "mascare", "formate" ou "aplique máscara" nas recomendações, o sistema inclui instruções detalhadas para o LLM sobre o formato correto. O bloco de override contém exemplos concretos para cada tipo de dado brasileiro.

#### Referência de Máscaras (formato correto):

| Tipo | Formato Mascarado | Exemplo Bruto → Formatado |
|------|-------------------|---------------------------|
| **Telefone fixo** | `(DDD) XXXX-XXXX` | "8 5, 3 1 1 1, 1 1 0 0" → "(85) 3111-1100" |
| **Celular** | `(DDD) XXXXX-XXXX` | "85 98888 7777" → "(85) 98888-7777" |
| **Telefone c/ país** | `+55 (DDD) XXXX-XXXX` | "+55 85 3111 1100" → "+55 (85) 3111-1100" |
| **CPF** | `XXX.XXX.XXX-XX` | "12345678901" → "123.456.789-01" |
| **CNPJ** | `XX.XXX.XXX/XXXX-XX` | "12345678000190" → "12.345.678/0001-90" |
| **CEP** | `XXXXX-XXX` | "60130000" → "60130-000" |
| **RG** | `XX.XXX.XXX-X` | "123456789" → "12.345.678-9" |
| **Data** | `DD/MM/AAAA` | "2026-03-20" → "20/03/2026" |
| **Valor monetário** | `R$ X.XXX,XX` | "1500.50" → "R$ 1.500,50" |
| **Placa veículo** | `XXX-XXXX` (Mercosul) | "ABC1D23" → "ABC-1D23" |

#### Importante — "Mascarar" ≠ "Esconder"

No contexto brasileiro, "mascarar" um telefone ou CPF significa **formatar com a máscara padrão** (parênteses, pontos, traços), mostrando TODOS os dígitos. NÃO significa esconder dígitos com asteriscos.

- ✅ Correto: "(85) 3111-1100" (todos os dígitos visíveis, formatado com máscara)
- ❌ Errado: "(85) ****-1100" (dígitos escondidos com asteriscos)
- ❌ Errado: "8 5, 3 1 1 1, 1 1 0 0" (sem máscara, formato TTS soletrado)

#### Como Adicionar Novos Tipos de Máscara

Para adicionar suporte a novos tipos de dados brasileiros, edite a função `applyRecommendationsOverride()` em `server/services/ai-agent.service.ts`. Adicione o novo formato no bloco de ATENÇÃO, seguindo o padrão:
```
- Se uma regra diz "mascare [TIPO]", formate no padrão [FORMATO] mostrando todos os dígitos. Exemplo: "[BRUTO]" DEVE aparecer como "[FORMATADO]".
```

## Segurança
- API Key nunca enviada ao frontend (mascarada como "••••••" + últimos 4 chars)
- Na atualização, API key só é alterada se valor não estiver vazio e não começar com "••••"
- Isolamento multi-tenant em todas as queries
