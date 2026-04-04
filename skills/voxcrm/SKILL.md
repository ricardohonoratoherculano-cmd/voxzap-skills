---
name: voxcrm
description: Especificação completa do VoxCRM — CRM profissional integrado com VoxZap (WhatsApp) e VoxCall (Telefonia). Use quando precisar criar, modificar ou estender qualquer funcionalidade do CRM, incluindo módulos de Vendas (pipeline Kanban), Cobrança (acordos, parcelas, régua automática), Atendimento (tickets omnichannel), e HelpDesk (base de conhecimento, SLA). Inclui schema Prisma completo, arquitetura, integrações, sidebar, deploy VPS, e fases de implementação.
---

# VoxCRM — CRM Integrado Profissional

Sistema CRM completo para operações de Vendas, Cobrança, Atendimento e HelpDesk, integrado nativamente com VoxZap (WhatsApp Cloud API) e VoxCall (Asterisk ARI/AMI).

## Quando Usar

- Criar ou modificar qualquer módulo do CRM (Vendas, Cobrança, Atendimento, HelpDesk)
- Implementar pipeline Kanban de vendas com drag-and-drop
- Criar sistema de cobrança com régua automática, acordos e parcelas
- Desenvolver tickets omnichannel (WhatsApp + Telefone + Email)
- Implementar base de conhecimento e SLA para HelpDesk
- Integrar CRM com VoxZap (envio/recebimento WhatsApp) ou VoxCall (chamadas, gravações)
- Criar dashboards e relatórios de CRM
- Configurar automações e workflows do CRM
- Deploy do VoxCRM em VPS de cliente

## Visão Geral do Produto

### Posicionamento

VoxCRM é o terceiro produto da família Voxtel, complementando:
- **VoxZap** — Gerenciamento de WhatsApp Business (Cloud API, multi-atendente, chatbot, campanhas)
- **VoxCall** — PABX e Call Center (Asterisk, filas, discador, gravações, relatórios)
- **VoxCRM** — CRM unificado que integra ambos os canais de comunicação

### Modelo de Deploy

- **Single-tenant**: Uma instância por cliente (mesma VPS ou VPS dedicada)
- **Stack**: Node.js/Express + React/TypeScript + Prisma + PostgreSQL
- **Deploy**: Docker Compose na VPS do cliente (mesmo modelo VoxZap/VoxCall)
- **Licenciamento**: Por usuário/mês, módulos ativáveis independentemente

### Módulos

| Módulo | Foco | Integrações Principais |
|--------|------|----------------------|
| **Vendas** | Pipeline comercial, leads, propostas, forecast | VoxZap (follow-up), VoxCall (ligações comerciais) |
| **Cobrança** | Recuperação de crédito, acordos, parcelas, régua | VoxZap (régua automática), VoxCall (discador), ERP externo |
| **Atendimento** | Tickets omnichannel, SLA, satisfação | VoxZap (canal WhatsApp), VoxCall (canal telefone) |
| **HelpDesk** | Base de conhecimento, FAQ, autoatendimento | VoxZap (chatbot), Portal do cliente |

## Arquitetura Técnica

### Stack Tecnológica

```
Frontend:  React 18 + TypeScript + Vite + TailwindCSS + shadcn/ui
Backend:   Node.js + Express + TypeScript
ORM:       Prisma (PostgreSQL)
Auth:      JWT + bcrypt (multi-perfil: admin, supervisor, operador)
Realtime:  Socket.io (notificações, atualizações de pipeline)
Queue:     Bull/BullMQ + Redis (jobs de régua, automações)
Storage:   Local filesystem + S3-compatible (anexos, gravações)
Deploy:    Docker Compose + Nginx + SSL (Let's Encrypt)
```

### Estrutura de Diretórios

```
voxcrm/
├── client/
│   ├── src/
│   │   ├── components/
│   │   │   ├── ui/              # shadcn components
│   │   │   ├── layout/          # Sidebar, Header, Layout
│   │   │   ├── vendas/          # Pipeline, LeadCard, DealForm
│   │   │   ├── cobranca/        # AcordoForm, ParcelaTable, ReguaConfig
│   │   │   ├── atendimento/     # TicketList, TicketDetail, TicketForm
│   │   │   ├── helpdesk/        # ArticleEditor, KnowledgeBase, FAQ
│   │   │   ├── shared/          # ContactCard, ActivityTimeline, FileUpload
│   │   │   └── dashboard/       # KPI Cards, Charts, Widgets
│   │   ├── pages/
│   │   │   ├── dashboard.tsx
│   │   │   ├── vendas/
│   │   │   ├── cobranca/
│   │   │   ├── atendimento/
│   │   │   ├── helpdesk/
│   │   │   ├── contatos/
│   │   │   ├── empresas/
│   │   │   ├── configuracoes/
│   │   │   └── release-notes.tsx
│   │   ├── hooks/
│   │   ├── lib/
│   │   └── App.tsx
│   └── index.html
├── server/
│   ├── routes/
│   │   ├── auth.routes.ts
│   │   ├── contatos.routes.ts
│   │   ├── empresas.routes.ts
│   │   ├── vendas.routes.ts
│   │   ├── cobranca.routes.ts
│   │   ├── atendimento.routes.ts
│   │   ├── helpdesk.routes.ts
│   │   ├── dashboard.routes.ts
│   │   ├── integracoes.routes.ts
│   │   └── configuracoes.routes.ts
│   ├── services/
│   │   ├── voxzap.service.ts       # Integração WhatsApp
│   │   ├── voxcall.service.ts      # Integração Telefonia
│   │   ├── regua.service.ts        # Motor da régua de cobrança
│   │   ├── automacao.service.ts    # Engine de automações
│   │   ├── notificacao.service.ts  # Push + Email + Socket
│   │   ├── sla.service.ts          # Motor de SLA
│   │   └── importacao.service.ts   # Import de carteiras/leads
│   ├── jobs/
│   │   ├── regua.job.ts            # Cron da régua de cobrança
│   │   ├── sla-check.job.ts        # Verificação periódica de SLA
│   │   └── cleanup.job.ts          # Limpeza de dados antigos
│   ├── lib/
│   │   ├── prisma.ts
│   │   ├── auth.ts
│   │   ├── version.ts
│   │   └── logger.ts
│   └── index.ts
├── prisma/
│   └── schema.prisma
├── shared/
│   └── types.ts                    # Tipos compartilhados frontend/backend
├── docker-compose.yml
├── Dockerfile
├── nginx.conf
├── package.json
├── tsconfig.json
└── CHANGELOG.md
```

### Integração com VoxZap

O VoxCRM consome a API REST do VoxZap instalado na mesma VPS (ou VPS parceira) para:

| Funcionalidade | Endpoint VoxZap | Uso no CRM |
|----------------|-----------------|------------|
| Enviar mensagem texto | `POST /api/messages/send` | Follow-up de vendas, cobrança, notificações |
| Enviar template HSM | `POST /api/messages/send-template` | Régua de cobrança, confirmações |
| Enviar mídia | `POST /api/messages/send-media` | Boletos, propostas, anexos |
| Listar conversas | `GET /api/tickets` | Histórico de interações do contato |
| Webhook de mensagem | `POST /voxcrm/webhook/whatsapp` | Receber respostas, atualizar tickets |
| Status de envio | Webhook `message.status` | Confirmar entrega na régua |

Configuração no VoxCRM:
```json
{
  "voxzap": {
    "baseUrl": "http://localhost:8080",
    "apiToken": "${VOXZAP_API_TOKEN}",
    "webhookSecret": "${VOXZAP_WEBHOOK_SECRET}",
    "defaultConnectionId": 1
  }
}
```

Padrão de chamada:
```typescript
import axios from 'axios';

const voxzapApi = axios.create({
  baseURL: process.env.VOXZAP_URL || 'http://localhost:8080',
  headers: { 'Authorization': `Bearer ${process.env.VOXZAP_API_TOKEN}` }
});

async function sendWhatsApp(phone: string, message: string, connectionId?: number) {
  return voxzapApi.post('/api/messages/send', {
    number: phone,
    body: message,
    connectionId: connectionId || 1
  });
}

async function sendTemplate(phone: string, templateName: string, params: string[]) {
  return voxzapApi.post('/api/messages/send-template', {
    number: phone,
    template: templateName,
    params
  });
}
```

### Integração com VoxCall

O VoxCRM consome a API ARI/AMI do Asterisk (via padrões definidos na skill `asterisk-ari-expert`) para:

| Funcionalidade | Interface | Uso no CRM |
|----------------|-----------|------------|
| Click-to-call | ARI `POST /channels` | Ligar para contato direto do CRM |
| Histórico de chamadas | PostgreSQL `cdr` table | Timeline de interações do contato |
| Gravações | ARI `GET /recordings/stored/{name}/file` | Ouvir gravação vinculada ao contato |
| Screen pop | WebSocket ARI events | Abrir ficha do contato quando liga entra |
| Status do ramal | ARI `GET /endpoints/PJSIP/{ext}` | Mostrar disponibilidade do operador |
| Transferência | AMI `Redirect` / `Atxfer` | Transferir chamada para outro operador |

Configuração:
```json
{
  "voxcall": {
    "ariHost": "${ARI_HOST}",
    "ariPort": 8088,
    "ariUser": "${ARI_USER}",
    "ariPassword": "${ARI_PASSWORD}",
    "ariProtocol": "http",
    "amiPort": 25038,
    "amiUser": "${AMI_USER}",
    "amiPassword": "${AMI_PASSWORD}",
    "dbHost": "${ASTERISK_DB_HOST}",
    "dbPort": 5432,
    "dbUser": "${ASTERISK_DB_USER}",
    "dbPassword": "${ASTERISK_DB_PASSWORD}",
    "dbName": "asterisk"
  }
}
```

**REGRA OBRIGATÓRIA**: Sempre usar `context: 'MANAGER'` em todas as ações ARI e AMI. Nunca usar `from-internal`.

## Schema Prisma Completo

### Core — Usuários, Contatos, Empresas

```prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

// ============================================
// CORE: Autenticação e Configuração
// ============================================

model User {
  id            Int       @id @default(autoincrement())
  name          String
  email         String    @unique
  password      String
  profile       Profile   @default(OPERADOR)
  phone         String?
  extension     String?
  avatar        String?
  isActive      Boolean   @default(true)
  lastLogin     DateTime?
  createdAt     DateTime  @default(now())
  updatedAt     DateTime  @updatedAt

  assignedLeads     Lead[]        @relation("AssignedTo")
  createdLeads      Lead[]        @relation("CreatedBy")
  deals             Deal[]
  tickets           Ticket[]      @relation("TicketAssigned")
  ticketsCreated    Ticket[]      @relation("TicketCreated")
  cobrancas         Cobranca[]
  activities        Activity[]
  comments          Comment[]
  articles          Article[]

  @@map("users")
}

enum Profile {
  ADMIN
  SUPERVISOR
  OPERADOR
}

model Config {
  id        Int      @id @default(autoincrement())
  key       String   @unique
  value     String
  group     String   @default("general")
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt

  @@map("configs")
}

// ============================================
// CORE: Contatos e Empresas
// ============================================

model Contact {
  id            Int       @id @default(autoincrement())
  name          String
  email         String?
  phone         String?
  cellphone     String?
  whatsapp      String?
  cpf           String?
  cnpj          String?
  birthDate     DateTime?
  gender        String?
  address       String?
  city          String?
  state         String?
  zipCode       String?
  notes         String?
  source        String?
  tags          String[]  @default([])
  customFields  Json?
  isActive      Boolean   @default(true)
  createdAt     DateTime  @default(now())
  updatedAt     DateTime  @updatedAt

  companyId     Int?
  company       Company?  @relation(fields: [companyId], references: [id])

  leads         Lead[]
  deals         Deal[]
  tickets       Ticket[]
  cobrancas     Cobranca[]
  activities    Activity[]
  interactions  Interaction[]

  @@index([phone])
  @@index([cellphone])
  @@index([whatsapp])
  @@index([cpf])
  @@index([cnpj])
  @@index([companyId])
  @@map("contacts")
}

model Company {
  id            Int       @id @default(autoincrement())
  name          String
  tradeName     String?
  cnpj          String?   @unique
  email         String?
  phone         String?
  website       String?
  industry      String?
  size          CompanySize?
  address       String?
  city          String?
  state         String?
  zipCode       String?
  notes         String?
  isActive      Boolean   @default(true)
  createdAt     DateTime  @default(now())
  updatedAt     DateTime  @updatedAt

  contacts      Contact[]
  leads         Lead[]
  deals         Deal[]
  tickets       Ticket[]

  @@map("companies")
}

enum CompanySize {
  MEI
  ME
  EPP
  MEDIO
  GRANDE
}

// ============================================
// MÓDULO: VENDAS (Pipeline Kanban)
// ============================================

model Pipeline {
  id          Int       @id @default(autoincrement())
  name        String
  description String?
  isDefault   Boolean   @default(false)
  isActive    Boolean   @default(true)
  sortOrder   Int       @default(0)
  createdAt   DateTime  @default(now())
  updatedAt   DateTime  @updatedAt

  stages      Stage[]
  deals       Deal[]

  @@map("pipelines")
}

model Stage {
  id          Int       @id @default(autoincrement())
  name        String
  color       String    @default("#6366f1")
  sortOrder   Int       @default(0)
  probability Int       @default(0)
  isWon       Boolean   @default(false)
  isLost      Boolean   @default(false)
  rottingDays Int?
  isActive    Boolean   @default(true)
  createdAt   DateTime  @default(now())
  updatedAt   DateTime  @updatedAt

  pipelineId  Int
  pipeline    Pipeline  @relation(fields: [pipelineId], references: [id])

  deals       Deal[]

  @@index([pipelineId])
  @@map("stages")
}

model Lead {
  id            Int        @id @default(autoincrement())
  title         String
  description   String?
  value         Decimal?   @db.Decimal(15, 2)
  source        LeadSource @default(MANUAL)
  status        LeadStatus @default(NOVO)
  score         Int        @default(0)
  expectedClose DateTime?
  lostReason    String?
  tags          String[]   @default([])
  customFields  Json?
  createdAt     DateTime   @default(now())
  updatedAt     DateTime   @updatedAt

  contactId     Int
  contact       Contact    @relation(fields: [contactId], references: [id])
  companyId     Int?
  company       Company?   @relation(fields: [companyId], references: [id])
  assignedToId  Int?
  assignedTo    User?      @relation("AssignedTo", fields: [assignedToId], references: [id])
  createdById   Int
  createdBy     User       @relation("CreatedBy", fields: [createdById], references: [id])

  deal          Deal?
  activities    Activity[]

  @@index([contactId])
  @@index([assignedToId])
  @@index([status])
  @@map("leads")
}

enum LeadSource {
  MANUAL
  WHATSAPP
  TELEFONE
  WEBSITE
  INDICACAO
  CAMPANHA
  IMPORTACAO
}

enum LeadStatus {
  NOVO
  QUALIFICADO
  DESCARTADO
  CONVERTIDO
}

model Deal {
  id            Int        @id @default(autoincrement())
  title         String
  value         Decimal    @db.Decimal(15, 2)
  currency      String     @default("BRL")
  probability   Int        @default(0)
  expectedClose DateTime?
  closedAt      DateTime?
  wonAt         DateTime?
  lostAt        DateTime?
  lostReason    String?
  notes         String?
  tags          String[]   @default([])
  customFields  Json?
  sortOrder     Int        @default(0)
  createdAt     DateTime   @default(now())
  updatedAt     DateTime   @updatedAt

  contactId     Int
  contact       Contact    @relation(fields: [contactId], references: [id])
  companyId     Int?
  company       Company?   @relation(fields: [companyId], references: [id])
  pipelineId    Int
  pipeline      Pipeline   @relation(fields: [pipelineId], references: [id])
  stageId       Int
  stage         Stage      @relation(fields: [stageId], references: [id])
  userId        Int
  user          User       @relation(fields: [userId], references: [id])
  leadId        Int?       @unique
  lead          Lead?      @relation(fields: [leadId], references: [id])

  products      DealProduct[]
  activities    Activity[]
  proposals     Proposal[]

  @@index([stageId])
  @@index([pipelineId])
  @@index([userId])
  @@index([contactId])
  @@map("deals")
}

model DealProduct {
  id          Int      @id @default(autoincrement())
  quantity    Int      @default(1)
  unitPrice   Decimal  @db.Decimal(15, 2)
  discount    Decimal  @default(0) @db.Decimal(5, 2)
  total       Decimal  @db.Decimal(15, 2)
  createdAt   DateTime @default(now())

  dealId      Int
  deal        Deal     @relation(fields: [dealId], references: [id], onDelete: Cascade)
  productId   Int
  product     Product  @relation(fields: [productId], references: [id])

  @@index([dealId])
  @@map("deal_products")
}

model Product {
  id          Int      @id @default(autoincrement())
  name        String
  description String?
  sku         String?  @unique
  unitPrice   Decimal  @db.Decimal(15, 2)
  category    String?
  isActive    Boolean  @default(true)
  createdAt   DateTime @default(now())
  updatedAt   DateTime @updatedAt

  dealProducts DealProduct[]

  @@map("products")
}

model Proposal {
  id            Int            @id @default(autoincrement())
  number        String         @unique
  title         String
  description   String?
  value         Decimal        @db.Decimal(15, 2)
  discount      Decimal        @default(0) @db.Decimal(5, 2)
  finalValue    Decimal        @db.Decimal(15, 2)
  validUntil    DateTime
  status        ProposalStatus @default(RASCUNHO)
  pdfUrl        String?
  sentAt        DateTime?
  viewedAt      DateTime?
  acceptedAt    DateTime?
  rejectedAt    DateTime?
  rejectedReason String?
  createdAt     DateTime       @default(now())
  updatedAt     DateTime       @updatedAt

  dealId        Int
  deal          Deal           @relation(fields: [dealId], references: [id])

  @@index([dealId])
  @@map("proposals")
}

enum ProposalStatus {
  RASCUNHO
  ENVIADA
  VISUALIZADA
  ACEITA
  REJEITADA
  EXPIRADA
}

// ============================================
// MÓDULO: COBRANÇA
// ============================================

model Carteira {
  id          Int      @id @default(autoincrement())
  name        String
  description String?
  credorName  String?
  tipo        CarteiraTipo @default(PROPRIA)
  isActive    Boolean  @default(true)
  createdAt   DateTime @default(now())
  updatedAt   DateTime @updatedAt

  cobrancas   Cobranca[]

  @@map("carteiras")
}

enum CarteiraTipo {
  PROPRIA
  TERCEIRIZADA
  JUDICIAL
}

model Cobranca {
  id              Int            @id @default(autoincrement())
  protocol        String         @unique
  originalValue   Decimal        @db.Decimal(15, 2)
  currentValue    Decimal        @db.Decimal(15, 2)
  dueDate         DateTime
  daysPastDue     Int            @default(0)
  status          CobrancaStatus @default(PENDENTE)
  priority        CobrancaPriority @default(NORMAL)
  contractNumber  String?
  invoiceNumber   String?
  description     String?
  notes           String?
  tags            String[]       @default([])
  customFields    Json?
  lastContactAt   DateTime?
  nextContactAt   DateTime?
  promiseDate     DateTime?
  promiseValue    Decimal?       @db.Decimal(15, 2)
  reguaStepId     Int?
  externalRef     String?
  createdAt       DateTime       @default(now())
  updatedAt       DateTime       @updatedAt

  contactId       Int
  contact         Contact        @relation(fields: [contactId], references: [id])
  carteiraId      Int
  carteira        Carteira       @relation(fields: [carteiraId], references: [id])
  userId          Int?
  user            User?          @relation(fields: [userId], references: [id])

  acordos         Acordo[]
  reguaLogs       ReguaLog[]
  activities      Activity[]

  @@index([contactId])
  @@index([carteiraId])
  @@index([status])
  @@index([dueDate])
  @@index([externalRef])
  @@map("cobrancas")
}

enum CobrancaStatus {
  PENDENTE
  EM_NEGOCIACAO
  ACORDO_FECHADO
  PAGO
  PARCIALMENTE_PAGO
  INADIMPLENTE
  JUDICIAL
  PRESCRITO
  CANCELADO
}

enum CobrancaPriority {
  BAIXA
  NORMAL
  ALTA
  URGENTE
}

model Acordo {
  id              Int          @id @default(autoincrement())
  number          String       @unique
  originalValue   Decimal      @db.Decimal(15, 2)
  discountPercent Decimal      @default(0) @db.Decimal(5, 2)
  discountValue   Decimal      @default(0) @db.Decimal(15, 2)
  finalValue      Decimal      @db.Decimal(15, 2)
  entryValue      Decimal?     @db.Decimal(15, 2)
  installments    Int          @default(1)
  status          AcordoStatus @default(VIGENTE)
  signedAt        DateTime     @default(now())
  brokenAt        DateTime?
  brokenReason    String?
  notes           String?
  createdAt       DateTime     @default(now())
  updatedAt       DateTime     @updatedAt

  cobrancaId      Int
  cobranca        Cobranca     @relation(fields: [cobrancaId], references: [id])

  parcelas        Parcela[]

  @@index([cobrancaId])
  @@map("acordos")
}

enum AcordoStatus {
  VIGENTE
  QUITADO
  QUEBRADO
  CANCELADO
}

model Parcela {
  id          Int           @id @default(autoincrement())
  number      Int
  value       Decimal       @db.Decimal(15, 2)
  dueDate     DateTime
  paidAt      DateTime?
  paidValue   Decimal?      @db.Decimal(15, 2)
  status      ParcelaStatus @default(PENDENTE)
  boletoUrl   String?
  boletoCode  String?
  pixCode     String?
  notes       String?
  createdAt   DateTime      @default(now())
  updatedAt   DateTime      @updatedAt

  acordoId    Int
  acordo      Acordo        @relation(fields: [acordoId], references: [id])

  @@index([acordoId])
  @@index([dueDate])
  @@index([status])
  @@map("parcelas")
}

enum ParcelaStatus {
  PENDENTE
  PAGA
  ATRASADA
  CANCELADA
}

model Regua {
  id            Int      @id @default(autoincrement())
  name          String
  description   String?
  isActive      Boolean  @default(true)
  createdAt     DateTime @default(now())
  updatedAt     DateTime @updatedAt

  carteiraId    Int?
  steps         ReguaStep[]

  @@map("reguas")
}

model ReguaStep {
  id              Int          @id @default(autoincrement())
  name            String
  daysOffset      Int
  channel         ReguaChannel
  templateName    String?
  templateParams  String[]     @default([])
  messageBody     String?
  sortOrder       Int          @default(0)
  isActive        Boolean      @default(true)
  createdAt       DateTime     @default(now())
  updatedAt       DateTime     @updatedAt

  reguaId         Int
  regua           Regua        @relation(fields: [reguaId], references: [id])

  logs            ReguaLog[]

  @@index([reguaId])
  @@map("regua_steps")
}

enum ReguaChannel {
  WHATSAPP
  SMS
  EMAIL
  TELEFONE
  WHATSAPP_TEMPLATE
}

model ReguaLog {
  id          Int          @id @default(autoincrement())
  status      ReguaLogStatus @default(ENVIADO)
  sentAt      DateTime     @default(now())
  deliveredAt DateTime?
  readAt      DateTime?
  repliedAt   DateTime?
  errorMsg    String?
  messageId   String?
  createdAt   DateTime     @default(now())

  cobrancaId  Int
  cobranca    Cobranca     @relation(fields: [cobrancaId], references: [id])
  stepId      Int
  step        ReguaStep    @relation(fields: [stepId], references: [id])

  @@index([cobrancaId])
  @@index([stepId])
  @@map("regua_logs")
}

enum ReguaLogStatus {
  PENDENTE
  ENVIADO
  ENTREGUE
  LIDO
  RESPONDIDO
  ERRO
}

// ============================================
// MÓDULO: ATENDIMENTO (Tickets Omnichannel)
// ============================================

model TicketQueue {
  id          Int      @id @default(autoincrement())
  name        String
  description String?
  color       String   @default("#6366f1")
  slaMinutes  Int?
  isActive    Boolean  @default(true)
  sortOrder   Int      @default(0)
  createdAt   DateTime @default(now())
  updatedAt   DateTime @updatedAt

  tickets     Ticket[]

  @@map("ticket_queues")
}

model Ticket {
  id            Int          @id @default(autoincrement())
  protocol      String       @unique
  subject       String
  description   String?
  channel       TicketChannel @default(INTERNO)
  status        TicketStatus @default(ABERTO)
  priority      TicketPriority @default(MEDIA)
  category      String?
  subcategory   String?
  tags          String[]     @default([])
  rating        Int?
  ratingComment String?
  slaDeadline   DateTime?
  slaBreached   Boolean      @default(false)
  firstResponseAt DateTime?
  resolvedAt    DateTime?
  closedAt      DateTime?
  reopenedAt    DateTime?
  externalRef   String?
  customFields  Json?
  createdAt     DateTime     @default(now())
  updatedAt     DateTime     @updatedAt

  contactId     Int
  contact       Contact      @relation(fields: [contactId], references: [id])
  companyId     Int?
  company       Company?     @relation(fields: [companyId], references: [id])
  queueId       Int?
  queue         TicketQueue? @relation(fields: [queueId], references: [id])
  assignedToId  Int?
  assignedTo    User?        @relation("TicketAssigned", fields: [assignedToId], references: [id])
  createdById   Int
  createdBy     User         @relation("TicketCreated", fields: [createdById], references: [id])
  parentId      Int?
  parent        Ticket?      @relation("TicketParent", fields: [parentId], references: [id])
  children      Ticket[]     @relation("TicketParent")

  comments      Comment[]
  activities    Activity[]

  @@index([contactId])
  @@index([assignedToId])
  @@index([queueId])
  @@index([status])
  @@index([slaDeadline])
  @@map("tickets")
}

enum TicketChannel {
  WHATSAPP
  TELEFONE
  EMAIL
  CHAT
  INTERNO
  PORTAL
}

enum TicketStatus {
  ABERTO
  EM_ANDAMENTO
  AGUARDANDO_CLIENTE
  AGUARDANDO_TERCEIRO
  RESOLVIDO
  FECHADO
  REABERTO
}

enum TicketPriority {
  BAIXA
  MEDIA
  ALTA
  URGENTE
}

model Comment {
  id          Int         @id @default(autoincrement())
  body        String
  isInternal  Boolean     @default(false)
  attachments String[]    @default([])
  createdAt   DateTime    @default(now())
  updatedAt   DateTime    @updatedAt

  ticketId    Int
  ticket      Ticket      @relation(fields: [ticketId], references: [id])
  userId      Int
  user        User        @relation(fields: [userId], references: [id])

  @@index([ticketId])
  @@map("comments")
}

// ============================================
// MÓDULO: HELPDESK (Base de Conhecimento)
// ============================================

model ArticleCategory {
  id          Int       @id @default(autoincrement())
  name        String
  slug        String    @unique
  description String?
  icon        String?
  sortOrder   Int       @default(0)
  isPublic    Boolean   @default(true)
  createdAt   DateTime  @default(now())
  updatedAt   DateTime  @updatedAt

  parentId    Int?
  parent      ArticleCategory?  @relation("CategoryParent", fields: [parentId], references: [id])
  children    ArticleCategory[] @relation("CategoryParent")
  articles    Article[]

  @@map("article_categories")
}

model Article {
  id          Int           @id @default(autoincrement())
  title       String
  slug        String        @unique
  body        String
  excerpt     String?
  status      ArticleStatus @default(RASCUNHO)
  isPublic    Boolean       @default(false)
  isFeatured  Boolean       @default(false)
  viewCount   Int           @default(0)
  helpfulYes  Int           @default(0)
  helpfulNo   Int           @default(0)
  tags        String[]      @default([])
  publishedAt DateTime?
  createdAt   DateTime      @default(now())
  updatedAt   DateTime      @updatedAt

  categoryId  Int
  category    ArticleCategory @relation(fields: [categoryId], references: [id])
  authorId    Int
  author      User            @relation(fields: [authorId], references: [id])

  @@index([categoryId])
  @@index([slug])
  @@index([status])
  @@map("articles")
}

enum ArticleStatus {
  RASCUNHO
  PUBLICADO
  ARQUIVADO
}

// ============================================
// SHARED: Atividades, Interações, Anexos
// ============================================

model Activity {
  id          Int          @id @default(autoincrement())
  type        ActivityType
  title       String
  description String?
  dueDate     DateTime?
  completedAt DateTime?
  metadata    Json?
  createdAt   DateTime     @default(now())
  updatedAt   DateTime     @updatedAt

  userId      Int
  user        User         @relation(fields: [userId], references: [id])
  contactId   Int?
  contact     Contact?     @relation(fields: [contactId], references: [id])
  leadId      Int?
  lead        Lead?        @relation(fields: [leadId], references: [id])
  dealId      Int?
  deal        Deal?        @relation(fields: [dealId], references: [id])
  cobrancaId  Int?
  cobranca    Cobranca?    @relation(fields: [cobrancaId], references: [id])
  ticketId    Int?
  ticket      Ticket?      @relation(fields: [ticketId], references: [id])

  @@index([userId])
  @@index([contactId])
  @@index([dealId])
  @@index([cobrancaId])
  @@index([ticketId])
  @@map("activities")
}

enum ActivityType {
  LIGACAO
  WHATSAPP
  EMAIL
  REUNIAO
  TAREFA
  NOTA
  VISITA
  PROPOSTA_ENVIADA
  ACORDO_FECHADO
  PAGAMENTO_RECEBIDO
}

model Interaction {
  id            Int             @id @default(autoincrement())
  channel       InteractionChannel
  direction     InteractionDirection
  content       String?
  duration      Int?
  recordingUrl  String?
  externalId    String?
  metadata      Json?
  createdAt     DateTime        @default(now())

  contactId     Int
  contact       Contact         @relation(fields: [contactId], references: [id])

  @@index([contactId])
  @@index([createdAt])
  @@map("interactions")
}

enum InteractionChannel {
  WHATSAPP
  TELEFONE
  EMAIL
  CHAT
  SMS
}

enum InteractionDirection {
  INBOUND
  OUTBOUND
}
```

### Índices de Performance Recomendados

```sql
CREATE INDEX CONCURRENTLY idx_contacts_phone ON contacts(phone) WHERE phone IS NOT NULL;
CREATE INDEX CONCURRENTLY idx_contacts_whatsapp ON contacts(whatsapp) WHERE whatsapp IS NOT NULL;
CREATE INDEX CONCURRENTLY idx_cobrancas_status_due ON cobrancas(status, "dueDate");
CREATE INDEX CONCURRENTLY idx_deals_stage_pipeline ON deals("stageId", "pipelineId");
CREATE INDEX CONCURRENTLY idx_tickets_status_sla ON tickets(status, "slaDeadline") WHERE status NOT IN ('FECHADO', 'RESOLVIDO');
CREATE INDEX CONCURRENTLY idx_activities_user_date ON activities("userId", "createdAt" DESC);
CREATE INDEX CONCURRENTLY idx_interactions_contact_date ON interactions("contactId", "createdAt" DESC);
```

## Módulo Vendas — Pipeline Kanban

### Funcionalidades

1. **Pipeline Kanban** — Visualização drag-and-drop de deals por estágio
2. **Gestão de Leads** — Captação, qualificação, scoring, conversão
3. **Deals/Oportunidades** — Valores, probabilidade, forecast, produtos
4. **Propostas Comerciais** — Geração PDF, envio por WhatsApp/Email, tracking de abertura
5. **Forecast** — Previsão de receita ponderada por probabilidade
6. **Relatórios** — Funil de conversão, performance por vendedor, tempo no estágio

### Pipeline Kanban — Frontend

```tsx
interface PipelineViewProps {
  pipelineId: number;
}

// Usar @dnd-kit/core para drag-and-drop
// Cada coluna = Stage
// Cada card = Deal (título, valor, contato, dias no estágio, próxima atividade)
// Ações do card: mover estágio, editar, won, lost
// Header da coluna: nome do estágio, count, valor total
// Footer: + Adicionar deal
```

### Estágios Padrão (Pipeline Default)

| Estágio | Probabilidade | Cor | Rotting Days |
|---------|--------------|-----|--------------|
| Prospecção | 10% | #94a3b8 | 7 |
| Qualificação | 25% | #6366f1 | 5 |
| Proposta | 50% | #f59e0b | 3 |
| Negociação | 75% | #f97316 | 3 |
| Fechamento | 90% | #22c55e | 2 |
| Ganho | 100% | #16a34a | - |
| Perdido | 0% | #ef4444 | - |

### API Endpoints — Vendas

| Método | Rota | Descrição |
|--------|------|-----------|
| GET | `/api/vendas/pipelines` | Listar pipelines |
| POST | `/api/vendas/pipelines` | Criar pipeline |
| GET | `/api/vendas/pipelines/:id` | Pipeline com estágios e deals |
| PUT | `/api/vendas/pipelines/:id` | Atualizar pipeline |
| GET | `/api/vendas/leads` | Listar leads (paginado, filtros) |
| POST | `/api/vendas/leads` | Criar lead |
| PUT | `/api/vendas/leads/:id` | Atualizar lead |
| POST | `/api/vendas/leads/:id/convert` | Converter lead em deal |
| GET | `/api/vendas/deals` | Listar deals (paginado, filtros) |
| POST | `/api/vendas/deals` | Criar deal |
| PUT | `/api/vendas/deals/:id` | Atualizar deal |
| PUT | `/api/vendas/deals/:id/stage` | Mover deal de estágio (Kanban) |
| POST | `/api/vendas/deals/:id/won` | Marcar como ganho |
| POST | `/api/vendas/deals/:id/lost` | Marcar como perdido |
| GET | `/api/vendas/deals/:id/timeline` | Timeline do deal |
| GET | `/api/vendas/forecast` | Forecast de receita |
| GET | `/api/vendas/funnel` | Dados do funil de conversão |
| GET | `/api/vendas/proposals` | Listar propostas |
| POST | `/api/vendas/proposals` | Criar proposta |
| POST | `/api/vendas/proposals/:id/send` | Enviar proposta (WhatsApp/Email) |
| GET | `/api/vendas/products` | Listar produtos/serviços |
| POST | `/api/vendas/products` | Criar produto |

## Módulo Cobrança — Recuperação de Crédito

### Funcionalidades

1. **Gestão de Carteiras** — Carteiras próprias, terceirizadas, judiciais
2. **Cobranças** — Registro de débitos com status, prioridade, aging
3. **Acordos** — Negociação com desconto, parcelamento, entrada
4. **Parcelas** — Controle de pagamento, boleto, PIX
5. **Régua de Cobrança** — Automação multicanal por dias de atraso
6. **Importação de Carteira** — CSV/Excel com mapeamento de colunas
7. **Integração ERP** — Sincronização com sistemas externos (Actyon, S4E, etc.)
8. **Relatórios** — Aging, recuperação, performance do operador

### Régua de Cobrança — Motor

A régua de cobrança é executada por um job periódico (Bull/BullMQ) que:

1. Busca cobranças ativas com status PENDENTE ou INADIMPLENTE
2. Para cada cobrança, calcula `daysPastDue = today - dueDate`
3. Busca a régua associada à carteira
4. Para cada step da régua, verifica se `daysOffset` bate com `daysPastDue`
5. Verifica se já foi executado (evita duplicação via `ReguaLog`)
6. Executa o disparo pelo canal configurado (WhatsApp, SMS, Email, Telefone)
7. Registra o log com status

```typescript
// server/jobs/regua.job.ts
async function processRegua() {
  const cobrancas = await prisma.cobranca.findMany({
    where: { status: { in: ['PENDENTE', 'INADIMPLENTE'] } },
    include: { carteira: { include: { /* regua */ } }, contact: true }
  });

  for (const cobranca of cobrancas) {
    const daysPastDue = differenceInDays(new Date(), cobranca.dueDate);
    const regua = await getActiveReguaForCarteira(cobranca.carteiraId);
    if (!regua) continue;

    for (const step of regua.steps) {
      if (step.daysOffset !== daysPastDue) continue;

      const alreadySent = await prisma.reguaLog.findFirst({
        where: { cobrancaId: cobranca.id, stepId: step.id }
      });
      if (alreadySent) continue;

      await executeReguaStep(step, cobranca);
    }
  }
}

async function executeReguaStep(step: ReguaStep, cobranca: CobrancaWithContact) {
  try {
    switch (step.channel) {
      case 'WHATSAPP':
        await sendWhatsApp(cobranca.contact.whatsapp!, step.messageBody!);
        break;
      case 'WHATSAPP_TEMPLATE':
        await sendTemplate(cobranca.contact.whatsapp!, step.templateName!, step.templateParams);
        break;
      case 'EMAIL':
        await sendEmail(cobranca.contact.email!, step.messageBody!);
        break;
      case 'TELEFONE':
        // Agendar callback para operador
        await scheduleCallback(cobranca);
        break;
    }

    await prisma.reguaLog.create({
      data: { cobrancaId: cobranca.id, stepId: step.id, status: 'ENVIADO' }
    });
  } catch (error) {
    await prisma.reguaLog.create({
      data: { cobrancaId: cobranca.id, stepId: step.id, status: 'ERRO', errorMsg: error.message }
    });
  }
}
```

### Régua Padrão (Template)

| Passo | Dias Atraso | Canal | Mensagem |
|-------|-------------|-------|----------|
| 1 | -3 | WhatsApp Template | Lembrete: vencimento em 3 dias |
| 2 | 0 | WhatsApp Template | Hoje vence sua fatura |
| 3 | +1 | WhatsApp | Fatura vencida ontem. Regularize. |
| 4 | +3 | WhatsApp | Débito pendente há 3 dias. |
| 5 | +7 | Telefone | Ligação do operador |
| 6 | +15 | WhatsApp Template | Último aviso antes de negativação |
| 7 | +30 | Email | Notificação formal de inadimplência |

### Importação de Carteira (CSV/Excel)

```typescript
// Mapeamento de colunas flexível
interface ImportMapping {
  contactName: string;      // Coluna do CSV -> Contact.name
  contactPhone: string;     // -> Contact.phone
  contactCpf?: string;      // -> Contact.cpf
  contactEmail?: string;    // -> Contact.email
  originalValue: string;    // -> Cobranca.originalValue
  dueDate: string;          // -> Cobranca.dueDate
  contractNumber?: string;  // -> Cobranca.contractNumber
  invoiceNumber?: string;   // -> Cobranca.invoiceNumber
  description?: string;     // -> Cobranca.description
}

// Processo de importação:
// 1. Upload do arquivo
// 2. Preview das primeiras 10 linhas
// 3. UI de mapeamento de colunas (drag-and-drop)
// 4. Validação (CPF, telefone, valor, data)
// 5. Importação com upsert de contato (por CPF ou telefone)
// 6. Relatório: importados, duplicados, erros
```

### API Endpoints — Cobrança

| Método | Rota | Descrição |
|--------|------|-----------|
| GET | `/api/cobranca/carteiras` | Listar carteiras |
| POST | `/api/cobranca/carteiras` | Criar carteira |
| GET | `/api/cobranca/cobrancas` | Listar cobranças (paginado, filtros, aging) |
| POST | `/api/cobranca/cobrancas` | Criar cobrança |
| PUT | `/api/cobranca/cobrancas/:id` | Atualizar cobrança |
| GET | `/api/cobranca/cobrancas/:id` | Detalhe da cobrança com timeline |
| POST | `/api/cobranca/acordos` | Criar acordo (com parcelas) |
| PUT | `/api/cobranca/acordos/:id` | Atualizar acordo |
| POST | `/api/cobranca/acordos/:id/break` | Quebrar acordo |
| POST | `/api/cobranca/parcelas/:id/pay` | Registrar pagamento de parcela |
| GET | `/api/cobranca/reguas` | Listar réguas |
| POST | `/api/cobranca/reguas` | Criar régua com steps |
| PUT | `/api/cobranca/reguas/:id` | Atualizar régua |
| POST | `/api/cobranca/import` | Importar carteira (CSV/Excel) |
| GET | `/api/cobranca/aging` | Relatório de aging |
| GET | `/api/cobranca/recovery` | Relatório de recuperação |

## Módulo Atendimento — Tickets Omnichannel

### Funcionalidades

1. **Tickets** — Abertura via WhatsApp, Telefone, Email, Portal, Manual
2. **Filas** — Distribuição automática por departamento/especialidade
3. **SLA** — Tempo de primeira resposta, tempo de resolução, escalação
4. **Classificação** — Categoria, subcategoria, tags, prioridade
5. **Comentários** — Internos (entre agentes) e públicos (para o cliente)
6. **Satisfação** — Pesquisa CSAT após fechamento
7. **Relatórios** — TMA, TME, SLA compliance, volume por canal

### SLA — Motor

```typescript
// server/services/sla.service.ts
interface SLAPolicy {
  firstResponseMinutes: number;
  resolutionMinutes: number;
  escalationMinutes: number;
  businessHoursOnly: boolean;
  businessHours: { start: string; end: string; days: number[] };
}

const DEFAULT_SLA: Record<TicketPriority, SLAPolicy> = {
  URGENTE: {
    firstResponseMinutes: 15,
    resolutionMinutes: 120,
    escalationMinutes: 30,
    businessHoursOnly: false,
    businessHours: { start: '08:00', end: '18:00', days: [1,2,3,4,5] }
  },
  ALTA: {
    firstResponseMinutes: 60,
    resolutionMinutes: 480,
    escalationMinutes: 120,
    businessHoursOnly: true,
    businessHours: { start: '08:00', end: '18:00', days: [1,2,3,4,5] }
  },
  MEDIA: {
    firstResponseMinutes: 240,
    resolutionMinutes: 1440,
    escalationMinutes: 480,
    businessHoursOnly: true,
    businessHours: { start: '08:00', end: '18:00', days: [1,2,3,4,5] }
  },
  BAIXA: {
    firstResponseMinutes: 480,
    resolutionMinutes: 2880,
    escalationMinutes: 1440,
    businessHoursOnly: true,
    businessHours: { start: '08:00', end: '18:00', days: [1,2,3,4,5] }
  }
};

// Job que roda a cada minuto verificando SLA
async function checkSLABreaches() {
  const openTickets = await prisma.ticket.findMany({
    where: {
      status: { notIn: ['FECHADO', 'RESOLVIDO'] },
      slaBreached: false,
      slaDeadline: { lte: new Date() }
    }
  });

  for (const ticket of openTickets) {
    await prisma.ticket.update({
      where: { id: ticket.id },
      data: { slaBreached: true }
    });
    // Notificar supervisor
    await notifyEscalation(ticket);
  }
}
```

### Criação de Ticket via WhatsApp (Webhook)

Quando uma nova mensagem chega no VoxZap sem ticket aberto:

```typescript
// Webhook do VoxZap -> VoxCRM
app.post('/voxcrm/webhook/whatsapp', async (req, res) => {
  const { from, body, messageId, connectionId } = req.body;

  // Buscar ou criar contato
  let contact = await prisma.contact.findFirst({
    where: { OR: [{ whatsapp: from }, { cellphone: from }, { phone: from }] }
  });
  if (!contact) {
    contact = await prisma.contact.create({
      data: { name: from, whatsapp: from, source: 'WHATSAPP' }
    });
  }

  // Buscar ticket aberto do contato
  let ticket = await prisma.ticket.findFirst({
    where: {
      contactId: contact.id,
      status: { notIn: ['FECHADO', 'RESOLVIDO'] },
      channel: 'WHATSAPP'
    }
  });

  if (!ticket) {
    // Criar novo ticket
    const protocol = generateProtocol(); // YYYYMMDDHHMMSS + random
    ticket = await prisma.ticket.create({
      data: {
        protocol,
        subject: `WhatsApp: ${body.substring(0, 100)}`,
        description: body,
        channel: 'WHATSAPP',
        status: 'ABERTO',
        priority: 'MEDIA',
        contactId: contact.id,
        createdById: 1 // system user
      }
    });
  }

  // Adicionar mensagem como comentário
  await prisma.comment.create({
    data: {
      body,
      ticketId: ticket.id,
      userId: 1, // system user
      isInternal: false
    }
  });

  // Registrar interação
  await prisma.interaction.create({
    data: {
      channel: 'WHATSAPP',
      direction: 'INBOUND',
      content: body,
      externalId: messageId,
      contactId: contact.id
    }
  });

  res.json({ ok: true });
});
```

### API Endpoints — Atendimento

| Método | Rota | Descrição |
|--------|------|-----------|
| GET | `/api/atendimento/tickets` | Listar tickets (paginado, filtros) |
| POST | `/api/atendimento/tickets` | Criar ticket |
| GET | `/api/atendimento/tickets/:id` | Detalhe do ticket |
| PUT | `/api/atendimento/tickets/:id` | Atualizar ticket |
| PUT | `/api/atendimento/tickets/:id/assign` | Atribuir ticket |
| PUT | `/api/atendimento/tickets/:id/status` | Mudar status |
| POST | `/api/atendimento/tickets/:id/comments` | Adicionar comentário |
| POST | `/api/atendimento/tickets/:id/rate` | Avaliação de satisfação |
| GET | `/api/atendimento/queues` | Listar filas |
| POST | `/api/atendimento/queues` | Criar fila |
| GET | `/api/atendimento/sla-report` | Relatório de SLA |
| GET | `/api/atendimento/volume` | Volume por canal/período |

## Módulo HelpDesk — Base de Conhecimento

### Funcionalidades

1. **Categorias** — Hierárquicas (pai/filho), com ícone e ordenação
2. **Artigos** — Editor rich text (Markdown ou WYSIWYG), tags, status de publicação
3. **Busca** — Full-text search nos artigos
4. **Métricas** — Visualizações, "foi útil?" (helpfulYes/helpfulNo)
5. **Portal Público** — Base acessível sem login para clientes
6. **Integração Chatbot** — VoxZap pode consultar artigos para responder automaticamente
7. **FAQ** — Artigos marcados como featured para perguntas frequentes

### API Endpoints — HelpDesk

| Método | Rota | Descrição |
|--------|------|-----------|
| GET | `/api/helpdesk/categories` | Listar categorias (árvore) |
| POST | `/api/helpdesk/categories` | Criar categoria |
| PUT | `/api/helpdesk/categories/:id` | Atualizar categoria |
| GET | `/api/helpdesk/articles` | Listar artigos (paginado, filtros) |
| POST | `/api/helpdesk/articles` | Criar artigo |
| GET | `/api/helpdesk/articles/:id` | Detalhe do artigo |
| PUT | `/api/helpdesk/articles/:id` | Atualizar artigo |
| POST | `/api/helpdesk/articles/:id/publish` | Publicar artigo |
| POST | `/api/helpdesk/articles/:id/helpful` | Registrar "foi útil?" |
| GET | `/api/helpdesk/search` | Busca full-text |
| GET | `/api/helpdesk/faq` | Artigos featured (FAQ) |
| GET | `/api/helpdesk/public/categories` | Categorias (portal público) |
| GET | `/api/helpdesk/public/articles/:slug` | Artigo por slug (portal público) |

## Core — Contatos, Empresas, Dashboard

### API Endpoints — Core

| Método | Rota | Descrição |
|--------|------|-----------|
| POST | `/api/auth/login` | Login (JWT) |
| POST | `/api/auth/logout` | Logout |
| GET | `/api/auth/me` | Usuário logado |
| GET | `/api/contatos` | Listar contatos (paginado, busca) |
| POST | `/api/contatos` | Criar contato |
| GET | `/api/contatos/:id` | Detalhe do contato (com timeline unificada) |
| PUT | `/api/contatos/:id` | Atualizar contato |
| DELETE | `/api/contatos/:id` | Desativar contato |
| GET | `/api/contatos/:id/timeline` | Timeline unificada (atividades + interações) |
| GET | `/api/empresas` | Listar empresas |
| POST | `/api/empresas` | Criar empresa |
| GET | `/api/empresas/:id` | Detalhe da empresa (com contatos) |
| PUT | `/api/empresas/:id` | Atualizar empresa |
| GET | `/api/dashboard` | KPIs gerais |
| GET | `/api/dashboard/vendas` | KPIs de vendas |
| GET | `/api/dashboard/cobranca` | KPIs de cobrança |
| GET | `/api/dashboard/atendimento` | KPIs de atendimento |
| GET | `/api/activities` | Listar atividades do usuário |
| POST | `/api/activities` | Criar atividade |
| PUT | `/api/activities/:id` | Atualizar atividade |

### Dashboard — KPIs por Módulo

**Vendas**:
- Deals em aberto (count + valor total)
- Win rate (% ganhos / total fechados)
- Forecast do mês (soma ponderada por probabilidade)
- Tempo médio no pipeline
- Top vendedores (ranking por valor ganho)

**Cobrança**:
- Total em aberto (valor)
- Taxa de recuperação (valor recuperado / valor em aberto)
- Aging distribution (0-30, 31-60, 61-90, 90+ dias)
- Acordos vigentes vs quebrados
- Performance por operador

**Atendimento**:
- Tickets abertos
- SLA compliance (%)
- CSAT médio
- Tempo médio de primeira resposta
- Volume por canal (WhatsApp, Telefone, Email)

## Sidebar e Navegação

### Estrutura do Menu

```typescript
const sidebarMenu = [
  {
    group: 'Principal',
    items: [
      { icon: 'LayoutDashboard', label: 'Dashboard', path: '/dashboard' },
      { icon: 'Users', label: 'Contatos', path: '/contatos' },
      { icon: 'Building2', label: 'Empresas', path: '/empresas' },
    ]
  },
  {
    group: 'Vendas',
    module: 'VENDAS',
    items: [
      { icon: 'Kanban', label: 'Pipeline', path: '/vendas/pipeline' },
      { icon: 'Target', label: 'Leads', path: '/vendas/leads' },
      { icon: 'Handshake', label: 'Negócios', path: '/vendas/deals' },
      { icon: 'FileText', label: 'Propostas', path: '/vendas/propostas' },
      { icon: 'TrendingUp', label: 'Forecast', path: '/vendas/forecast' },
      { icon: 'Package', label: 'Produtos', path: '/vendas/produtos' },
    ]
  },
  {
    group: 'Cobrança',
    module: 'COBRANCA',
    items: [
      { icon: 'Wallet', label: 'Carteiras', path: '/cobranca/carteiras' },
      { icon: 'Receipt', label: 'Cobranças', path: '/cobranca/cobrancas' },
      { icon: 'FileSignature', label: 'Acordos', path: '/cobranca/acordos' },
      { icon: 'CalendarClock', label: 'Parcelas', path: '/cobranca/parcelas' },
      { icon: 'Workflow', label: 'Régua', path: '/cobranca/regua' },
      { icon: 'Upload', label: 'Importação', path: '/cobranca/importacao' },
    ]
  },
  {
    group: 'Atendimento',
    module: 'ATENDIMENTO',
    items: [
      { icon: 'Ticket', label: 'Tickets', path: '/atendimento/tickets' },
      { icon: 'ListTodo', label: 'Filas', path: '/atendimento/filas' },
      { icon: 'Clock', label: 'SLA', path: '/atendimento/sla' },
      { icon: 'BarChart3', label: 'Relatórios', path: '/atendimento/relatorios' },
    ]
  },
  {
    group: 'HelpDesk',
    module: 'HELPDESK',
    items: [
      { icon: 'BookOpen', label: 'Artigos', path: '/helpdesk/artigos' },
      { icon: 'FolderTree', label: 'Categorias', path: '/helpdesk/categorias' },
      { icon: 'HelpCircle', label: 'FAQ', path: '/helpdesk/faq' },
      { icon: 'Search', label: 'Busca', path: '/helpdesk/busca' },
    ]
  },
  {
    group: 'Configurações',
    items: [
      { icon: 'Settings', label: 'Geral', path: '/configuracoes' },
      { icon: 'Users2', label: 'Usuários', path: '/configuracoes/usuarios' },
      { icon: 'Plug', label: 'Integrações', path: '/configuracoes/integracoes' },
      { icon: 'ScrollText', label: 'Release Notes', path: '/release-notes' },
    ]
  }
];
```

### Visibilidade por Módulo

Cada grupo com `module` só aparece se o módulo estiver ativo na configuração do tenant:

```typescript
const activeModules = await prisma.config.findMany({
  where: { group: 'modules', value: 'true' }
});
const enabledModules = activeModules.map(c => c.key);

// Filtrar menu
const filteredMenu = sidebarMenu.filter(group =>
  !group.module || enabledModules.includes(group.module)
);
```

## Deploy VPS — Docker Compose

### docker-compose.yml

```yaml
version: '3.8'

services:
  voxcrm-app:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: voxcrm-app
    restart: unless-stopped
    ports:
      - "3100:3100"
    environment:
      - NODE_ENV=production
      - PORT=3100
      - DATABASE_URL=postgresql://voxcrm:${DB_PASSWORD}@voxcrm-db:5432/voxcrm
      - JWT_SECRET=${JWT_SECRET}
      - VOXZAP_URL=${VOXZAP_URL}
      - VOXZAP_API_TOKEN=${VOXZAP_API_TOKEN}
      - REDIS_URL=redis://voxcrm-redis:6379
    depends_on:
      - voxcrm-db
      - voxcrm-redis
    volumes:
      - ./uploads:/app/uploads
    networks:
      - voxcrm-network

  voxcrm-db:
    image: postgres:15-alpine
    container_name: voxcrm-db
    restart: unless-stopped
    environment:
      - POSTGRES_USER=voxcrm
      - POSTGRES_PASSWORD=${DB_PASSWORD}
      - POSTGRES_DB=voxcrm
    volumes:
      - voxcrm-pgdata:/var/lib/postgresql/data
    ports:
      - "5433:5432"
    networks:
      - voxcrm-network

  voxcrm-redis:
    image: redis:7-alpine
    container_name: voxcrm-redis
    restart: unless-stopped
    volumes:
      - voxcrm-redis-data:/data
    networks:
      - voxcrm-network

volumes:
  voxcrm-pgdata:
  voxcrm-redis-data:

networks:
  voxcrm-network:
    driver: bridge
```

### Dockerfile

```dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npx prisma generate
RUN npm run build

FROM node:20-alpine AS runner
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/package.json ./
EXPOSE 3100
CMD ["sh", "-c", "npx prisma migrate deploy && node dist/server/index.js"]
```

### Nginx (Host — não Docker)

Adicionar bloco no nginx do host (mesmo padrão VoxZap/VoxCall):

```nginx
server {
    listen 443 ssl http2;
    server_name crm.cliente.voxzap.app.br;

    ssl_certificate /etc/letsencrypt/live/crm.cliente.voxzap.app.br/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/crm.cliente.voxzap.app.br/privkey.pem;

    location / {
        proxy_pass http://localhost:3100;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }

    location /uploads/ {
        alias /home/voxcrm/uploads/;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
}
```

### Script de Deploy

```bash
#!/bin/bash
# deploy-voxcrm.sh — Executar na VPS do cliente

set -e

INSTALL_DIR="/home/voxcrm"
REPO_URL="https://github.com/ricardohonoratoherculano-cmd/voxcrm.git"
BRANCH="main"

echo "=== VoxCRM Deploy ==="

# Clone ou pull
if [ -d "$INSTALL_DIR" ]; then
  cd "$INSTALL_DIR" && git pull origin $BRANCH
else
  git clone -b $BRANCH "$REPO_URL" "$INSTALL_DIR"
  cd "$INSTALL_DIR"
fi

# Criar .env se não existir
if [ ! -f .env ]; then
  echo "DB_PASSWORD=$(openssl rand -base64 32)" > .env
  echo "JWT_SECRET=$(openssl rand -base64 64)" >> .env
  echo "VOXZAP_URL=http://localhost:8080" >> .env
  echo "VOXZAP_API_TOKEN=" >> .env
  echo "Preencha VOXZAP_API_TOKEN no .env"
fi

# Build e start
docker compose build
docker compose up -d

# Aguardar banco
sleep 5

# Migrations
docker compose exec voxcrm-app npx prisma migrate deploy

# SSL (se domínio configurado)
DOMAIN=$(grep SERVER_NAME .env 2>/dev/null | cut -d= -f2)
if [ -n "$DOMAIN" ]; then
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m admin@voxtel.com.br
fi

echo "=== VoxCRM Deploy Concluído ==="
echo "Acesse: https://${DOMAIN:-localhost}:3100"
```

## Fases de Implementação

### Fase 1 — Foundation (2-3 semanas)

- [ ] Setup do projeto (Vite + Express + Prisma + PostgreSQL)
- [ ] Schema Prisma: User, Config, Contact, Company
- [ ] Autenticação JWT (login, registro, perfis)
- [ ] Layout base: Sidebar, Header, tema dark/light
- [ ] CRUD de Contatos com busca e paginação
- [ ] CRUD de Empresas vinculadas a contatos
- [ ] Timeline de atividades do contato
- [ ] Sistema de versionamento (CHANGELOG, Release Notes)
- [ ] Docker Compose + Dockerfile + deploy script

### Fase 2 — Módulo Vendas (2-3 semanas)

- [ ] Schema Prisma: Pipeline, Stage, Lead, Deal, Product, Proposal
- [ ] Pipeline Kanban com drag-and-drop (@dnd-kit)
- [ ] CRUD de Leads com qualificação e scoring
- [ ] Conversão Lead -> Deal
- [ ] CRUD de Deals no pipeline
- [ ] Produtos/Serviços vinculados a deals
- [ ] Forecast de receita
- [ ] Geração e envio de propostas
- [ ] Dashboard de Vendas (funil, win rate, top sellers)

### Fase 3 — Módulo Cobrança (3-4 semanas)

- [ ] Schema Prisma: Carteira, Cobranca, Acordo, Parcela, Regua, ReguaStep, ReguaLog
- [ ] CRUD de Carteiras
- [ ] CRUD de Cobranças com aging
- [ ] Negociação de Acordos com parcelamento
- [ ] Controle de Parcelas (vencimento, pagamento)
- [ ] Motor da Régua de Cobrança (Bull job)
- [ ] Integração VoxZap (envio automático pela régua)
- [ ] Importação de carteira CSV/Excel
- [ ] Dashboard de Cobrança (aging, recuperação)

### Fase 4 — Módulo Atendimento (2-3 semanas)

- [ ] Schema Prisma: TicketQueue, Ticket, Comment
- [ ] CRUD de Tickets com filas
- [ ] Motor de SLA com verificação periódica
- [ ] Comentários internos e públicos
- [ ] Webhook VoxZap -> criação automática de ticket
- [ ] Screen Pop com VoxCall (chamada entrante abre ficha)
- [ ] Pesquisa de satisfação (CSAT)
- [ ] Dashboard de Atendimento (SLA, volume, CSAT)

### Fase 5 — Módulo HelpDesk (1-2 semanas)

- [ ] Schema Prisma: ArticleCategory, Article
- [ ] Editor de artigos (Markdown/WYSIWYG)
- [ ] Categorias hierárquicas
- [ ] Portal público (leitura sem login)
- [ ] Busca full-text
- [ ] Métricas (views, helpful)
- [ ] FAQ (artigos featured)

### Fase 6 — Integrações Avançadas (2-3 semanas)

- [ ] Click-to-call no CRM (ARI)
- [ ] Histórico de chamadas do contato (CDR)
- [ ] Gravações vinculadas ao contato
- [ ] Integração com ERP externo (Actyon, S4E)
- [ ] Automações (workflows visuais)
- [ ] Notificações push (Socket.io)
- [ ] API pública do VoxCRM (para integrações terceiras)

## Padrões de Código

### Backend — Rotas

```typescript
// Padrão: validar com Zod, usar Prisma, retornar tipado
import { z } from 'zod';

const createContactSchema = z.object({
  name: z.string().min(2),
  email: z.string().email().optional(),
  phone: z.string().optional(),
  cellphone: z.string().optional(),
  whatsapp: z.string().optional(),
  cpf: z.string().optional(),
  companyId: z.number().optional(),
});

router.post('/api/contatos', authenticateToken, async (req, res) => {
  const parsed = createContactSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ errors: parsed.error.flatten() });
  }
  const contact = await prisma.contact.create({ data: parsed.data });
  return res.status(201).json(contact);
});
```

### Frontend — Queries

```typescript
// Padrão: useQuery com tipo, queryKey hierárquico
import { useQuery, useMutation } from '@tanstack/react-query';
import { queryClient, apiRequest } from '@/lib/queryClient';

function useContacts(page: number, search?: string) {
  return useQuery({
    queryKey: ['/api/contatos', { page, search }],
  });
}

function useCreateContact() {
  return useMutation({
    mutationFn: (data: CreateContactInput) =>
      apiRequest('POST', '/api/contatos', data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['/api/contatos'] });
    }
  });
}
```

### Formulários

```typescript
// Padrão: react-hook-form + zodResolver + shadcn Form
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { Form, FormField, FormItem, FormLabel, FormControl, FormMessage } from '@/components/ui/form';

function ContactForm({ onSubmit }: { onSubmit: (data: any) => void }) {
  const form = useForm({
    resolver: zodResolver(createContactSchema),
    defaultValues: { name: '', email: '', phone: '' }
  });

  return (
    <Form {...form}>
      <form onSubmit={form.handleSubmit(onSubmit)}>
        <FormField control={form.control} name="name" render={({ field }) => (
          <FormItem>
            <FormLabel>Nome</FormLabel>
            <FormControl><Input {...field} data-testid="input-contact-name" /></FormControl>
            <FormMessage />
          </FormItem>
        )} />
        {/* ... demais campos */}
        <Button type="submit" data-testid="button-save-contact">Salvar</Button>
      </form>
    </Form>
  );
}
```

## Referências Cruzadas (Skills Relacionadas)

| Skill | Uso no VoxCRM |
|-------|---------------|
| `whatsapp-messaging-expert` | Envio/recebimento de mensagens, templates HSM, webhook, Socket.io |
| `voxfone-telephony-crm` | Click-to-call, CDR, gravações, softphone, extensões |
| `asterisk-ari-expert` | API ARI para originar chamadas, monitorar canais, WebSocket |
| `asterisk-callcenter-expert` | KPIs de call center, queue_log, relatórios, SLA telefônico |
| `actyon-crm` | Referência de schema de CRM de cobrança (236 tabelas, padrões) |
| `s4e-crm` | Referência de integração com sistema de discagem S4E |
| `external-db-integration` | Framework de conexão com bancos externos (MSSQL, PostgreSQL) |
| `deploy-assistant-vps` | Deploy via Docker Compose, nginx, SSL, SSH |
| `versioning-system` | CHANGELOG, release notes, version bump, badge no sidebar |
| `vpn-management-expert` | VPN para acessar rede privada do cliente (integração ERP) |

## Convenções e Regras

1. **Idioma**: Interface 100% em Português do Brasil
2. **Moeda**: BRL (R$) com Decimal(15,2) — nunca usar float para valores monetários
3. **Data/Hora**: Armazenar em UTC, exibir em America/Sao_Paulo (Brasília)
4. **Telefone**: Formato E.164 no banco (+5511999999999), formato visual no frontend
5. **CPF/CNPJ**: Armazenar sem máscara, validar com algoritmo, exibir com máscara
6. **Paginação**: Padrão 25 itens por página, offset-based
7. **Busca**: Case-insensitive, busca parcial (ILIKE %termo%)
8. **Logs**: winston com levels (error, warn, info, debug), rotação diária
9. **Testes**: data-testid em todos os elementos interativos
10. **Segurança**: Sanitizar inputs, parametrizar queries (Prisma faz isso), rate limiting
11. **Contexto Asterisk**: SEMPRE `context: 'MANAGER'` em ARI e AMI — nunca outro contexto
12. **Segredos**: NUNCA hardcodar credenciais no código ou configurações — usar variáveis de ambiente (`${VAR}`) para todos os tokens, senhas, API keys e secrets
