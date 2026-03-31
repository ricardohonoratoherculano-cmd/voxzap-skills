---
name: voxtel-proposal-generator
description: Gerador de Propostas Comerciais da Voxtel Telecomunicações. Use quando o usuário pedir para criar, editar ou gerar propostas comerciais, PDFs de proposta, ou trabalhar com o sistema de propostas da Voxtel. Inclui catálogo completo VoxCall e VoxZap com preços, assistente IA e geração de PDF profissional.
---

# Gerador de Propostas Comerciais — Voxtel Telecomunicações

Sistema completo de geração de propostas comerciais profissionais para a Voxtel Telecomunicações LTDA, com formulário manual, assistente IA e geração de PDF com identidade visual da empresa.

## Arquitetura

```text
artifacts/proposal-generator/     # Frontend React + Vite + Tailwind
├── src/components/proposal/
│   ├── ProposalForm.tsx          # Formulário principal (modo Manual + Assistente IA)
│   ├── AIAssistant.tsx           # Interface do assistente IA
│   ├── ProposalPDF.tsx           # Template PDF com @react-pdf/renderer
│   ├── ProposalPreview.tsx       # Preview do PDF via pdfjs-dist (canvas)
│   └── types.ts                  # TypeScript interfaces + dados padrão
├── public/logo-voxtel.png        # Logo da Voxtel
└── vite.config.ts                # Proxy /api -> API server

artifacts/api-server/             # Backend Express
├── src/routes/ai/
│   ├── index.ts                  # POST /api/ai/generate-proposal (SSE)
│   └── system-prompt.ts          # System prompt com catálogo e preços
└── src/routes/index.ts           # Montagem de rotas

lib/integrations-openai-ai-server/ # Integração OpenAI via Replit AI Integrations
```

## Stack Técnica

| Componente | Tecnologia |
|---|---|
| Frontend | React 19 + Vite + Tailwind CSS |
| PDF | @react-pdf/renderer (geração) + pdfjs-dist@3.11.174 (preview canvas) |
| Backend | Express 5 + TypeScript |
| IA | OpenAI GPT-5.2 via Replit AI Integrations (SSE streaming) |
| Fonte PDF | Inter (CDN fontsource, latin, pesos 400/500/600/700) |
| Ícones | Lucide React |
| Tema | Dark/light mode com classe CSS (localStorage) |

## Identidade Visual Voxtel

- Azul escuro principal: `#0D2E5C`
- Azul intermediário: `#2B6CB0`
- Azul claro/accent: `#4A90C4`
- Logo: `artifacts/proposal-generator/public/logo-voxtel.png`

## Dados da Empresa (Fixos no PDF)

- **Empresa**: Voxtel Telecomunicações LTDA
- **Responsável**: Ricardo Herculano — Diretor Técnico
- **Telefone**: (85) 9 8878.8084 / 3198.9899
- **E-mail**: ricardo@voxtel.biz
- **Cidade padrão**: Fortaleza

## Estrutura do PDF (Páginas)

1. **Capa**: Logo, título "PROPOSTA COMERCIAL", dados do cliente, número da proposta, data, cidade
2. **Carta**: Saudação, apresentação da Voxtel, objetivo da proposta, tabela de itens (descrição, valor unitário, locação, total), totais, considerações, seção "Sobre a Voxtel", assinatura, aceite do cliente

## Catálogo de Produtos e Preços

### VoxCall — Telefonia IP e Call Center

| Produto/Serviço | Unitário (R$) | Locação Mensal (R$) |
|---|---|---|
| Licença VoxCall PABX IP (por ramal) | 0,00 | 59,90 |
| Ramal SIP (softphone ou IP phone) | 0,00 | 39,90 |
| Tronco SIP (canal de voz) | 0,00 | 49,90 |
| URA Inteligente | 0,00 | 199,90 |
| Módulo de Gravação de Chamadas | 0,00 | 149,90 |
| Módulo Call Center (por posição) | 0,00 | 89,90 |
| Módulo Relatórios e Dashboard | 0,00 | 99,90 |
| Módulo Discador Automático (por posição) | 0,00 | 119,90 |
| Fila de Atendimento (por fila) | 0,00 | 69,90 |
| Integração com CRM (Actyon/S4E) | 2.500,00 | 0,00 |
| Telefone IP Yealink T31G | 890,00 | 0,00 |
| Telefone IP Yealink T46U | 1.490,00 | 0,00 |
| Headset USB profissional | 290,00 | 0,00 |
| Gateway FXO/FXS (4 portas) | 1.800,00 | 0,00 |
| Gateway GSM (4 canais) | 3.200,00 | 0,00 |
| Instalação e Configuração PABX | 1.500,00 | 0,00 |
| Treinamento Operacional (até 8h) | 800,00 | 0,00 |
| Suporte Técnico Mensal | 0,00 | 299,90 |

### VoxZap — WhatsApp Business

| Produto/Serviço | Unitário (R$) | Locação Mensal (R$) |
|---|---|---|
| Licença VoxZap WhatsApp Business API (por número) | 0,00 | 299,90 |
| Canal WhatsApp adicional | 0,00 | 149,90 |
| Agente de Atendimento WhatsApp (por agente) | 0,00 | 49,90 |
| Chatbot VoxZap (fluxo automatizado) | 0,00 | 199,90 |
| Agente de IA com RAG (base de conhecimento) | 0,00 | 399,90 |
| Módulo de Campanhas em Massa | 0,00 | 249,90 |
| Integração com Sistema de Tickets | 2.000,00 | 0,00 |
| Integração com E-commerce | 3.500,00 | 0,00 |
| Configuração e Ativação WhatsApp API | 990,00 | 0,00 |
| Treinamento VoxZap (até 4h) | 500,00 | 0,00 |

### Serviços Complementares

| Serviço | Valor (R$) |
|---|---|
| Consultoria em Telecomunicações (hora técnica) | 250,00 |
| Cabeamento Estruturado (ponto) | 180,00 |
| Configuração de Rede/Switch (por unidade) | 350,00 |
| Visita Técnica | 200,00 |
| Projeto de Infraestrutura de Telecomunicações | 3.000,00 |

## Assistente IA

### Endpoint

`POST /api/ai/generate-proposal` — SSE streaming

- **Modelo**: GPT-5.2 via Replit AI Integrations
- **Env vars (automáticas)**: `AI_INTEGRATIONS_OPENAI_BASE_URL`, `AI_INTEGRATIONS_OPENAI_API_KEY`
- **max_completion_tokens**: 8192

### Fluxo

1. Usuário seleciona aba "Assistente IA" no formulário
2. Descreve a proposta em linguagem natural (ex: "10 ramais VoIP + URA + WhatsApp para empresa X")
3. Backend envia prompt + system prompt ao OpenAI via SSE
4. Frontend acumula tokens e exibe em tempo real
5. Ao finalizar, JSON é parseado e campos do formulário são preenchidos automaticamente
6. Usuário é redirecionado para aba "Manual" para revisar e ajustar

### Formato de Resposta da IA

```json
{
  "clientName": "string",
  "clientCompany": "string",
  "clientContact": "string",
  "objective": "string",
  "items": [
    {
      "description": "string",
      "unitPrice": 0,
      "rentalPrice": 0,
      "totalPrice": 0
    }
  ],
  "considerations": "string",
  "validityDays": 15,
  "city": "Fortaleza"
}
```

### Regras de Cálculo

- Itens com locação mensal: `unitPrice=0`, `rentalPrice=valor`, `totalPrice=0`
- Itens de compra única: `unitPrice=valor`, `rentalPrice=0`, `totalPrice=valor*qtd`
- Sempre incluir instalação/configuração e treinamento quando apropriado

## TypeScript Interfaces

```typescript
interface ProposalItem {
  id: string;
  description: string;
  unitPrice: number;
  rentalPrice: number;
  totalPrice: number;
}

interface ProposalData {
  clientName: string;
  clientCompany: string;
  clientContact: string;
  objective: string;
  items: ProposalItem[];
  considerations: string;
  validityDays: number;
  city: string;
  proposalDate: string;
  responsibleName: string;
  responsibleTitle: string;
  responsiblePhone: string;
  responsibleEmail: string;
}
```

## Notas Técnicas Importantes

### PDF Preview

- Usar **pdfjs-dist@3.11.174** (somente v3 — v4+ tem breaking changes)
- Worker: `pdfjs-dist/build/pdf.worker.js`
- Preview renderiza páginas para canvas → converte para PNG (data URL)
- Blob URLs e iframes diretos com PDF são bloqueados pelo proxy Replit

### Buffer Polyfill

O `@react-pdf/renderer` requer `Buffer` no browser. Polyfill em `main.tsx`:

```typescript
import { Buffer } from "buffer";
declare global { interface Window { Buffer: typeof Buffer } }
window.Buffer = Buffer;
```

### Vite Proxy

Em dev, `/api` é proxied para o API server:

```typescript
proxy: {
  "/api": {
    target: `http://0.0.0.0:${process.env.API_PORT || "8080"}`,
    changeOrigin: true,
  },
}
```

### Font Registration (PDF)

```typescript
const weights = [400, 500, 600, 700];
weights.forEach((w) =>
  Font.register({
    family: "Inter",
    src: `https://cdn.jsdelivr.net/fontsource/fonts/inter@latest/latin-${w}-normal.ttf`,
    fontWeight: w,
  })
);
```

## Manutenção

### Atualizar Preços

Editar `artifacts/api-server/src/routes/ai/system-prompt.ts` — as tabelas de preço estão no system prompt da IA.

### Atualizar Textos Fixos do PDF

Editar `artifacts/proposal-generator/src/components/proposal/ProposalPDF.tsx`:
- Carta introdutória: buscar por "Prezados" (~linha 443)
- Seção "Sobre a Voxtel": buscar por "aboutSection" (~linha 601)

### Adicionar Novos Produtos

1. Adicionar na tabela do system prompt (`system-prompt.ts`)
2. A IA automaticamente incluirá nas propostas geradas

### Alterar Dados do Responsável

Editar `artifacts/proposal-generator/src/components/proposal/types.ts` → `defaultProposalData`
