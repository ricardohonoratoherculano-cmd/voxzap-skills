---
name: contextual-help-system
description: Implementar sistema de Ajuda Contextual em painel lateral (Sheet shadcn) acionado por botão na TopBar e atalho de teclado "?", igual ao padrão Stripe/Linear/Vercel/Notion. Use quando o usuário pedir para criar ajuda contextual por página, help drawer, painel de ajuda lateral, botão de ajuda no topo, atalho de ajuda, ou replicar o sistema de help do VoxCALL/PlanoClin em outro projeto (VoxZap, VoxHub, etc.). Funciona em qualquer fullstack React + shadcn/ui + wouter.
---

# Sistema de Ajuda Contextual (Sheet lateral)

Implementação completa de ajuda contextual por página: botão na TopBar, atalho global `?`, painel lateral à direita (Sheet), conteúdo direto da página atual sem sair dela. Padrão validado em produção no VoxCALL (clin.voxcall.cc).

## Quando Usar Esta Skill

Ative quando o usuário pedir qualquer variação de:
- "Implementar ajuda contextual por página"
- "Adicionar help drawer / painel de ajuda"
- "Botão de ajuda na TopBar / barra superior"
- "Atalho de ajuda"
- "Replicar/copiar a ajuda do VoxCALL / PlanoClin / clin.voxcall.cc"
- "Modal de ajuda lateral"
- "Help context da página atual"

## Resultado Esperado (UX Final)

1. **Botão "? Ajuda"** na TopBar — só aparece em páginas mapeadas no manual
2. **Tooltip** ao passar o mouse mostra título da seção atual + dica do atalho
3. **Atalho `?`** (ou `Shift+/`) abre/fecha o painel em qualquer página mapeada
4. **Atalho NÃO dispara** dentro de `<input>`, `<textarea>`, `<select>`, `contentEditable`, ou elementos com `role="textbox|combobox|searchbox"`
5. **Sheet lateral à direita** (480px desktop, fullscreen mobile) com:
   - Cabeçalho: ícone + título + descrição "Ajuda contextual desta página"
   - Corpo (scrollável): descrição completa, badge colorida de destaque (Ativo/Como usar/Importante/Dica), rodapé italicizado, dicas de atalhos
   - Footer: botão "Abrir manual completo" (link wouter) + botão "Fechar"
6. **Tecla Esc** fecha (comportamento nativo do Sheet)
7. **Bundle inicial leve**: dados do manual em arquivo separado, TopBar não importa a página inteira do manual

## Pré-Requisitos do Projeto Alvo

Antes de implementar, **verificar obrigatoriamente** (`grep -l` ou `ls`):

| Requisito | Como confirmar |
|-----------|----------------|
| React + TypeScript | `package.json` tem `react` e `typescript` |
| `wouter` para rotas | `import { useLocation, Link } from "wouter"` em algum arquivo existente |
| shadcn/ui instalado | Existe `client/src/components/ui/` ou `src/components/ui/` |
| Componente Sheet | `client/src/components/ui/sheet.tsx` (se não existir, instalar via shadcn-cli ou copiar do projeto VoxCALL) |
| Componentes Tooltip, Button, ScrollArea, Separator | Existem em `components/ui/` |
| `lucide-react` | `package.json` |
| Existe TopBar/Header global | Procurar arquivos como `top-bar.tsx`, `header.tsx`, `app-header.tsx` |
| Existe página de manual (opcional) | Para o botão "Abrir manual completo" funcionar |

Se algum componente shadcn faltar, instalar antes:
```bash
npx shadcn-ui@latest add sheet tooltip button scroll-area separator
```

## Arquivos a Criar/Modificar

```
client/src/
├── lib/
│   └── manual-data.tsx          ← NOVO. Tipos + dados do manual + helpers
├── components/
│   ├── page-help-button.tsx     ← NOVO. Botão na TopBar + atalho ?
│   ├── page-help-dialog.tsx     ← NOVO. Sheet lateral
│   └── top-bar.tsx              ← EDITAR. Adicionar <PageHelpButton />
└── pages/
    └── manual.tsx               ← EDITAR. Importar de @/lib/manual-data (se já existe)
```

> Se o projeto não tem manual completo, `manual-data.tsx` ainda é necessário porque é a fonte de dados que o botão consulta. A página `manual.tsx` é opcional.

## Implementação Passo a Passo

### Passo 1 — Criar `client/src/lib/manual-data.tsx`

Arquivo com tipos, helpers e o array `sections` contendo os itens do manual mapeados por rota (`href`).

**Estrutura mínima** (adapte os itens ao projeto alvo — cada `href` deve corresponder a uma rota existente):

```typescript
import {
  BookOpen, Search, MessageCircle, Users, Settings as SettingsIcon,
  Phone, Bot, Shield, type LucideIcon,
} from "lucide-react";

export interface ManualItem {
  icon: LucideIcon;
  title: string;
  description: string;
  highlight?: { label: "Ativo" | "Como usar" | "Importante" | "Dica"; text: string };
  footer?: string;
  href?: string;
}

export interface ManualSection {
  key: string;
  title: string;
  subtitle: string;
  icon: LucideIcon;
  color: string;
  description: string;
  items: ManualItem[];
}

export const sections: ManualSection[] = [
  {
    key: "atendimento",
    title: "Atendimento",
    subtitle: "Tickets e conversas",
    icon: MessageCircle,
    color: "text-blue-500",
    description: "Tudo sobre atendimento de tickets e conversas WhatsApp.",
    items: [
      {
        icon: MessageCircle,
        title: "Página de Atendimento",
        description: "Lista de tickets em aberto, conversas ativas, transferência entre filas e operadores.",
        highlight: { label: "Como usar", text: "Selecione um ticket à esquerda para ver a conversa." },
        href: "/atendimento",
      },
      // ... outros itens com href apontando para rotas reais
    ],
  },
  // ... outras seções
];

export function highlightStyle(label: string): string {
  switch (label) {
    case "Ativo":      return "bg-emerald-500/10 border-emerald-500/30 text-emerald-700 dark:text-emerald-300";
    case "Como usar":  return "bg-blue-500/10 border-blue-500/30 text-blue-700 dark:text-blue-300";
    case "Importante": return "bg-amber-500/10 border-amber-500/30 text-amber-700 dark:text-amber-300";
    case "Dica":       return "bg-violet-500/10 border-violet-500/30 text-violet-700 dark:text-violet-300";
    default:           return "bg-muted border-border text-foreground";
  }
}

export function highlightIcon(label: string): string {
  switch (label) {
    case "Ativo":      return "●";
    case "Como usar":  return "→";
    case "Importante": return "!";
    case "Dica":       return "✦";
    default:           return "•";
  }
}

export function findManualEntry(pathname: string): { section: ManualSection; item: ManualItem } | null {
  for (const section of sections) {
    for (const item of section.items) {
      if (item.href && pathname === item.href) {
        return { section, item };
      }
    }
  }
  return null;
}
```

**Regras críticas para `findManualEntry`**:
- Match **exato** por `pathname === item.href` (não usar `startsWith` — gera falsos positivos)
- Para rotas com parâmetros (ex: `/tickets/:id`), criar item com `href: "/tickets"` e adicionar lógica `pathname.startsWith(item.href + "/")` apenas se necessário
- Retornar `null` quando não houver match → o botão da TopBar simplesmente não renderiza

### Passo 2 — Criar `client/src/components/page-help-dialog.tsx`

Conteúdo **literal** (copie e cole; ajuste apenas o `import` do `@/` se o alias for diferente):

```typescript
import { Link } from "wouter";
import { BookOpen, ExternalLink, X } from "lucide-react";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetDescription,
  SheetClose,
} from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Separator } from "@/components/ui/separator";
import { cn } from "@/lib/utils";
import {
  type ManualItem,
  highlightStyle,
  highlightIcon,
} from "@/lib/manual-data";

interface PageHelpDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  pathname: string;
  item: ManualItem;
}

export default function PageHelpDialog({
  open,
  onOpenChange,
  pathname,
  item,
}: PageHelpDialogProps) {
  const Icon = item.icon;
  const manualUrl = `/manual?goto=${encodeURIComponent(pathname)}`;

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent
        side="right"
        className="w-full sm:max-w-md md:max-w-lg p-0 flex flex-col gap-0"
        data-testid="page-help-dialog"
      >
        <SheetHeader className="px-6 pt-6 pb-4 border-b border-border">
          <div className="flex items-start gap-3">
            <div className="rounded-lg bg-blue-500/10 p-2 shrink-0">
              <Icon className="w-5 h-5 text-blue-500" />
            </div>
            <div className="flex-1 min-w-0">
              <SheetTitle className="text-base leading-snug text-left" data-testid="page-help-title">
                {item.title}
              </SheetTitle>
              <SheetDescription className="text-xs text-muted-foreground mt-1 text-left">
                Ajuda contextual desta página
              </SheetDescription>
            </div>
          </div>
        </SheetHeader>

        <ScrollArea className="flex-1">
          <div className="px-6 py-5 space-y-4">
            <p
              className="text-sm text-foreground/90 leading-relaxed whitespace-pre-line"
              data-testid="page-help-description"
            >
              {item.description}
            </p>

            {item.highlight && (
              <div
                className={cn(
                  "rounded-md border px-3 py-2.5 text-xs flex items-start gap-2",
                  highlightStyle(item.highlight.label),
                )}
                data-testid="page-help-highlight"
              >
                <span className="mt-0.5">{highlightIcon(item.highlight.label)}</span>
                <span className="leading-relaxed">
                  <span className="font-semibold">{item.highlight.label}:</span>{" "}
                  {item.highlight.text}
                </span>
              </div>
            )}

            {item.footer && (
              <>
                <Separator />
                <p className="text-xs text-muted-foreground/80 italic leading-relaxed">
                  {item.footer}
                </p>
              </>
            )}

            <Separator />
            <div className="text-xs text-muted-foreground space-y-1.5">
              <div className="flex items-center gap-2">
                <kbd className="px-1.5 py-0.5 text-[10px] font-mono rounded bg-muted border border-border">?</kbd>
                <span>Abrir esta ajuda em qualquer página</span>
              </div>
              <div className="flex items-center gap-2">
                <kbd className="px-1.5 py-0.5 text-[10px] font-mono rounded bg-muted border border-border">Esc</kbd>
                <span>Fechar</span>
              </div>
            </div>
          </div>
        </ScrollArea>

        <div className="px-6 py-4 border-t border-border flex items-center justify-between gap-2 shrink-0">
          <Button
            asChild
            variant="outline"
            size="sm"
            className="gap-1.5"
            onClick={() => onOpenChange(false)}
            data-testid="page-help-open-manual"
          >
            <Link href={manualUrl}>
              <BookOpen className="w-3.5 h-3.5" />
              Abrir manual completo
              <ExternalLink className="w-3 h-3 opacity-60" />
            </Link>
          </Button>
          <SheetClose asChild>
            <Button variant="ghost" size="sm" className="gap-1.5" data-testid="page-help-close">
              <X className="w-3.5 h-3.5" />
              Fechar
            </Button>
          </SheetClose>
        </div>
      </SheetContent>
    </Sheet>
  );
}
```

**ATENÇÃO — anti-patterns que o code review pegou e foram corrigidos**:
- O botão "Abrir manual completo" **DEVE** usar `<Button asChild><Link>...</Link></Button>` — colocar `<Link>` dentro de `<Button>` sem `asChild` gera HTML inválido (`<a><button>`)
- Se o projeto alvo não tiver página `/manual`, mude `manualUrl` para um link relevante ou remova o botão "Abrir manual completo" (mantenha só o "Fechar")

### Passo 3 — Criar `client/src/components/page-help-button.tsx`

Conteúdo **literal**:

```typescript
import { useState, useEffect, useMemo } from "react";
import { useLocation } from "wouter";
import { HelpCircle } from "lucide-react";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { findManualEntry } from "@/lib/manual-data";
import PageHelpDialog from "@/components/page-help-dialog";

export default function PageHelpButton() {
  const [pathname] = useLocation();
  const [open, setOpen] = useState(false);

  const entry = useMemo(() => {
    if (pathname === "/manual") return null;
    return findManualEntry(pathname);
  }, [pathname]);

  const hasEntry = !!entry;

  useEffect(() => {
    if (!hasEntry) return;
    const handler = (e: KeyboardEvent) => {
      const target = e.target as HTMLElement | null;
      if (target) {
        const tag = target.tagName;
        if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return;
        if (target.isContentEditable) return;
        const role = target.getAttribute("role");
        if (role === "textbox" || role === "combobox" || role === "searchbox") return;
      }
      if (e.key === "?" || (e.shiftKey && e.key === "/")) {
        e.preventDefault();
        setOpen((v) => !v);
      }
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [hasEntry]);

  if (!entry) return null;

  return (
    <>
      <Tooltip>
        <TooltipTrigger asChild>
          <button
            type="button"
            onClick={() => setOpen(true)}
            className="flex items-center gap-1.5 text-muted-foreground hover:text-blue-500 transition-colors cursor-pointer"
            aria-label={`Abrir ajuda: ${entry.item.title}`}
            data-testid="page-help-button"
          >
            <HelpCircle className="h-4 w-4" />
            <span className="text-xs font-medium hidden md:inline">Ajuda</span>
          </button>
        </TooltipTrigger>
        <TooltipContent side="bottom" className="max-w-xs">
          <div className="text-xs">
            <div className="font-semibold mb-0.5">Ajuda desta página</div>
            <div className="text-muted-foreground">{entry.item.title}</div>
            <div className="text-muted-foreground/70 mt-1">
              Atalho: <kbd className="px-1 py-0.5 text-[10px] font-mono rounded bg-muted border border-border">?</kbd>
            </div>
          </div>
        </TooltipContent>
      </Tooltip>

      <PageHelpDialog
        open={open}
        onOpenChange={setOpen}
        pathname={pathname}
        item={entry.item}
      />
    </>
  );
}
```

**ATENÇÃO — anti-patterns que o code review pegou e foram corrigidos**:
- `useEffect` deve depender de `[hasEntry]` (boolean estável), **NUNCA** de `[entry]` (objeto). Se a TopBar tiver um clock que renderiza a cada segundo, depender de `entry` recria o listener 1×/segundo (memory churn invisível).
- `entry` **DEVE** ser `useMemo` por `pathname`, não computado direto — evita re-execução do `findManualEntry` em cada render.
- Filtro de contexto de digitação **DEVE** incluir SELECT, contentEditable e roles `textbox/combobox/searchbox` além de INPUT/TEXTAREA. Combobox shadcn usa `role="combobox"` num `<button>` e dispararia o atalho sem esse filtro.

### Passo 4 — Editar a TopBar do projeto

Localizar o arquivo da barra superior (`top-bar.tsx`, `header.tsx`, `app-header.tsx`) e adicionar:

```typescript
import PageHelpButton from "@/components/page-help-button";

// dentro do JSX, na seção direita (antes do botão de chat / notificação / user-menu):
<PageHelpButton />
```

O `PageHelpButton` retorna `null` quando a página não tem entry no manual, então é seguro renderizar globalmente.

### Passo 5 — Se já existe página de manual

Se o projeto já tem `pages/manual.tsx` com tipos e dados próprios, refatore para importar de `@/lib/manual-data`:

```typescript
import {
  type ManualItem,
  type ManualSection,
  sections,
  findManualEntry,
  highlightStyle,
  highlightIcon,
} from "@/lib/manual-data";
```

**E REMOVA** os ícones lucide herdados que não são mais usados na renderização da página. Mantenha apenas os 4–6 ícones realmente usados pelo componente da página (no VoxCALL: `BookOpen, Search, ExternalLink, Lock`).

Para identificar o que é usado:
```bash
sed -n '<linha_apos_imports>,$p' client/src/pages/manual.tsx | tr -c '[:alnum:]_' '\n' | sort -u > /tmp/used.txt
# Comparar com os imports atuais
```

## Validação Final

Após implementação:

1. **HMR/build sem erros**: rodar `npm run dev`, abrir o app, conferir console limpo
2. **Botão aparece** na TopBar em uma rota mapeada (ex: `/atendimento`)
3. **Botão NÃO aparece** em rotas não mapeadas
4. **Clique no botão** abre o Sheet à direita
5. **Tecla `?`** abre/fecha (com foco fora de input)
6. **Tecla `?` dentro de input** NÃO dispara
7. **Tecla `Esc`** fecha
8. **Botão "Abrir manual completo"** navega para `/manual?goto=...` (ou link configurado) e fecha o Sheet
9. **Curl de produção**: `curl -sS -o /dev/null -w '%{http_code}\n' https://<dominio>/<rota_mapeada>` deve retornar `200`

## Padrão Visual de Referência

Este sistema replica o padrão usado por:
- Stripe Dashboard (botão "?" canto superior direito → drawer lateral)
- Linear (Cmd+K + "?")
- Vercel Dashboard
- Notion (atalho "?")
- Salesforce Lightning Experience (botão "?" no header)
- HubSpot (drawer de help contextual)

Largura padrão: **~480px (Sheet `sm:max-w-md md:max-w-lg`)**, lado direito, animação slide-in.

## Adaptações por Projeto

### VoxZap (multi-tenant WhatsApp)
- TopBar provável em `client/src/components/header.tsx` ou similar — confirmar com `grep -rn "useChatContext\|MessageCircle" client/src/components/`
- Rotas a mapear: `/atendimento`, `/dashboard`, `/operator-dashboard`, `/channels`, `/templates`, `/users`, `/queues`, `/contacts`, `/ai-knowledge`, `/reports`
- Como é multi-tenant, **não** colocar dados específicos de tenant no `manual-data.tsx` — só descrições funcionais genéricas
- Se não houver página `/manual`, simplificar o footer do Sheet removendo o botão "Abrir manual completo"

### VoxHub e outros
- Mesmo padrão. Mapear rotas reais antes de escrever os items.

## Arquivos de Referência (originais validados em produção VoxCALL)

| Arquivo no VoxCALL | Função |
|---|---|
| `client/src/lib/manual-data.tsx` | 687 linhas. Tipos + 13 sections + findManualEntry. Pode ser usado como ponto de partida e adaptado |
| `client/src/components/page-help-button.tsx` | 75 linhas. Botão da TopBar |
| `client/src/components/page-help-dialog.tsx` | 140 linhas. Sheet lateral |
| `client/src/components/top-bar.tsx` | Linha 51: `<PageHelpButton />` na seção direita |
| `client/src/pages/manual.tsx` | 303 linhas. Re-importa de `manual-data` |

Sistema deployado em `clin.voxcall.cc` (prod) — HTTP 200 em `/manual`, `/dialer-campaigns`, `/pjsip-extensions`, etc.

## Anti-Patterns (NÃO fazer)

1. **NÃO** colocar tipos e dados do manual dentro de `pages/manual.tsx` e importar `pages/manual` da TopBar — isso puxa a página inteira no bundle global
2. **NÃO** depender de `[entry]` no `useEffect` do listener — depender de `[hasEntry]` (boolean)
3. **NÃO** colocar `<Link>` dentro de `<Button>` sem `asChild` — usar `<Button asChild><Link>...</Link></Button>`
4. **NÃO** filtrar apenas INPUT/TEXTAREA no listener — incluir SELECT, contentEditable e roles textbox/combobox/searchbox
5. **NÃO** usar `pathname.startsWith(href)` em `findManualEntry` — usar `===` (evita falsos positivos com `/users` matchando `/users/123`)
6. **NÃO** abrir o Sheet via navegação (`setLocation('/manual?...')`) — usar state local e o componente Sheet, mantendo o usuário na página atual
7. **NÃO** esquecer de remover ícones lucide mortos depois do refator de `manual.tsx` — code review pega isso
