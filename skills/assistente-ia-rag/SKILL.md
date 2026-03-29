# Assistente IA RAG — Analisador de Base de Conhecimento

## Objetivo
Metodologia para analisar documentos da base de conhecimento de um Agente de IA e gerar uma Prompt de Sistema otimizada, contextualizada com o conteúdo real dos arquivos e URLs raspadas.

## Quando Usar
- Quando o admin faz upload de documentos na base de conhecimento do agente
- Quando o admin raspa URLs (web scraping) para ingestão na base de conhecimento
- Quando o agente não está respondendo adequadamente às perguntas dos clientes
- Para gerar/refinar a Prompt de Sistema automaticamente com base no conteúdo dos documentos

## Metodologia de Análise

### 1. Coleta de Chunks
- Buscar todos os `AiAgentChunks` do agente no banco de dados
- Concatenar o conteúdo com separadores para manter contexto
- Respeitar limites de tokens do modelo (truncar se necessário)

### 2. Meta-Prompt de Análise
O meta-prompt enviado ao LLM deve solicitar:
- **Resumo**: Identificar o tipo de negócio, entidades principais, cenários de atendimento
- **Prompt Sugerida**: Gerar uma prompt de sistema completa e contextualizada
- **Sugestões de Melhoria**: Indicar lacunas na base de conhecimento

### 3. Estrutura da Prompt Sugerida
A prompt gerada deve conter:
- Persona do assistente (nome, tom, personalidade)
- Descrição do negócio/empresa
- Regras de atendimento
- Cenários mapeados e como responder
- Palavras-chave de transferência
- Formato das respostas
- Limitações e escopo

## Template de Meta-Prompt

```
Você é um especialista em criar prompts de sistema para assistentes virtuais de atendimento ao cliente via WhatsApp.

Analise o conteúdo da base de conhecimento abaixo e gere:

1. **RESUMO** (máx 200 palavras): O que a base contém — tipo de negócio, entidades principais, cenários de atendimento, informações chave.

2. **PROMPT DE SISTEMA SUGERIDA**: Uma prompt completa e otimizada para um assistente WhatsApp que usa essa base de conhecimento. A prompt deve:
   - Definir persona (nome, tom, estilo)
   - Descrever o negócio/empresa com base no conteúdo
   - Listar regras claras de atendimento
   - Mapear cenários identificados e como responder
   - Incluir instrução para usar [TRANSFERIR] quando não souber responder
   - Definir formato de respostas (breve, WhatsApp-friendly)
   - Instruir a responder APENAS com base na base de conhecimento

3. **SUGESTÕES DE MELHORIA** (lista com bullets): O que está faltando na base que melhoraria o atendimento — informações ausentes, cenários não cobertos, dados incompletos.

## BASE DE CONHECIMENTO:

{chunks_content}
```

## Limites de Tokens por Provider
- OpenAI (GPT-4o): ~128k context, usar até 80k para chunks
- Gemini 1.5: ~1M context, usar até 200k para chunks
- Claude 3.5: ~200k context, usar até 100k para chunks
- DeepSeek: ~64k context, usar até 40k para chunks

## Fontes de Dados para a Base de Conhecimento

### Upload de Arquivos
- Formatos suportados: PDF, DOCX, PPTX, TXT, MD, CSV
- Extração de texto via `pdf-parse`, `officeparser`
- Chunks de ~500 tokens

### Raspagem de URL (Web Scraping Profissional)
- Pipeline: `Cheerio` (pré-limpeza) → `@mozilla/readability` (extração conteúdo principal) → `Turndown + GFM` (HTML→Markdown com tabelas)
- SSRF protection: bloqueia URLs privadas/localhost
- Limite: 10MB por página, timeout 30s
- Fallback: CSS selectors → Next.js `__NEXT_DATA__` → body
- Entradas salvas com `AiAgentFiles.type = ".url"`
- Detalhes completos na skill `ai-agent-expert`, seção "Pipeline de Raspagem Web"

## Arquivos Relevantes
- `server/services/ai-agent.service.ts` — funções `analyzeKnowledgeBase()`, `processUrlScrape()`, `scrapeUrlToMarkdown()`
- `server/routes.ts` — endpoints `POST /api/ai-agents/:id/analyze-knowledge`, `POST /api/ai-agents/:id/scrape-url`
- `client/src/pages/agentes-ia.tsx` — botão "Analisar Base" + modal de resultado + campo URL + botão "Raspar URL"

## Formato de Resposta do Endpoint
```json
{
  "summary": "Resumo do conteúdo da base...",
  "suggestedPrompt": "Você é Ana Clara, assistente virtual da empresa...",
  "improvements": ["Adicionar horário de funcionamento", "Incluir política de cancelamento", ...]
}
```
