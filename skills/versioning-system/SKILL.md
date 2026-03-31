---
name: versioning-system
description: Sistema de versionamento profissional com SemVer, CHANGELOG.md, endpoints de API, página de Release Notes, e badge de versão no sidebar. Use quando o usuário pedir para implementar versionamento, changelog, release notes, controle de versão do projeto, ou histórico de atualizações. Inclui script de version bump, módulo backend, endpoints REST, página frontend React, e integração com sidebar.
---

# Sistema de Versionamento Profissional

## Quando Ativar

Ative esta skill quando o usuário pedir para:
- Implementar versionamento no projeto
- Criar sistema de changelog / release notes
- Controlar versões das atualizações do sistema
- Criar histórico de mudanças do projeto
- Adicionar badge de versão no sidebar/footer
- Gerar notas de release

## Visão Geral

O sistema é composto por 5 componentes:

1. **CHANGELOG.md** — Arquivo de histórico seguindo Keep a Changelog + SemVer
2. **scripts/version-bump.js** — Script CLI para incrementar versão (patch/minor/major)
3. **server/lib/version.ts** — Módulo backend com funções de leitura/escrita de versão e changelog
4. **Endpoints de API** — `GET /api/version`, `GET /api/version/changelog`, `POST /api/version/bump`
5. **Página Release Notes** — Frontend React com visual profissional
6. **Badge no Sidebar** — Versão exibida no footer, clicável para release notes

## Implementação Passo a Passo

### Passo 1: Criar CHANGELOG.md na raiz do projeto

```markdown
# Changelog

Todas as mudanças notáveis deste projeto são documentadas neste arquivo.
Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/),
e este projeto segue [Versionamento Semântico](https://semver.org/lang/pt-BR/).

## [1.0.0] - YYYY-MM-DD

### Adicionado
- Versão inicial do sistema
- (listar features iniciais aqui)
```

### Passo 2: Garantir que `package.json` tenha o campo `version`

```json
{
  "version": "1.0.0"
}
```

### Passo 3: Criar `scripts/version-bump.js`

```javascript
#!/usr/bin/env node
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, "..");

const bumpType = process.argv[2] || "patch";
if (!["patch", "minor", "major"].includes(bumpType)) {
  console.error("Usage: node scripts/version-bump.js [patch|minor|major]");
  process.exit(1);
}

const pkgPath = path.join(rootDir, "package.json");
const pkg = JSON.parse(fs.readFileSync(pkgPath, "utf8"));
const [major, minor, patch] = pkg.version.split(".").map(Number);

let newVersion;
switch (bumpType) {
  case "major":
    newVersion = `${major + 1}.0.0`;
    break;
  case "minor":
    newVersion = `${major}.${minor + 1}.0`;
    break;
  case "patch":
    newVersion = `${major}.${minor}.${patch + 1}`;
    break;
}

pkg.version = newVersion;
fs.writeFileSync(pkgPath, JSON.stringify(pkg, null, 2) + "\n");

const changelogPath = path.join(rootDir, "CHANGELOG.md");
const today = new Date().toISOString().split("T")[0];
const newEntry = `\n## [${newVersion}] - ${today}\n\n### Adicionado\n- \n\n### Melhorado\n- \n\n### Corrigido\n- \n`;

if (fs.existsSync(changelogPath)) {
  const changelog = fs.readFileSync(changelogPath, "utf8");
  const marker = "## [";
  const idx = changelog.indexOf(marker);
  if (idx !== -1) {
    const updated = changelog.slice(0, idx) + newEntry.trimStart() + "\n" + changelog.slice(idx);
    fs.writeFileSync(changelogPath, updated);
  }
}

console.log(`Version bumped: ${major}.${minor}.${patch} -> ${newVersion} (${bumpType})`);
console.log(`Updated: package.json, CHANGELOG.md`);
console.log(`Don't forget to fill in the CHANGELOG.md entry!`);
```

Adicionar script no `package.json`:
```json
{
  "scripts": {
    "version:bump": "node scripts/version-bump.js"
  }
}
```

### Passo 4: Criar `server/lib/version.ts`

```typescript
import fs from "fs";
import path from "path";

function resolveProjectFile(filename: string): string {
  const fromCwd = path.resolve(process.cwd(), filename);
  if (fs.existsSync(fromCwd)) return fromCwd;
  const fromDirname = path.resolve(__dirname, "../../" + filename);
  if (fs.existsSync(fromDirname)) return fromDirname;
  const fromDirname1 = path.resolve(__dirname, "../" + filename);
  if (fs.existsSync(fromDirname1)) return fromDirname1;
  return fromCwd;
}

let cachedVersion: string | null = null;
let cachedChangelog: string | null = null;

export function getAppVersion(): string {
  if (cachedVersion) return cachedVersion;
  try {
    const pkgPath = resolveProjectFile("package.json");
    const pkg = JSON.parse(fs.readFileSync(pkgPath, "utf8"));
    cachedVersion = pkg.version || "0.0.0";
    return cachedVersion!;
  } catch {
    return "0.0.0";
  }
}

export interface ChangelogEntry {
  version: string;
  date: string;
  sections: { title: string; items: string[] }[];
}

export function parseChangelog(limit = 3): ChangelogEntry[] {
  try {
    const changelogPath = resolveProjectFile("CHANGELOG.md");
    if (!fs.existsSync(changelogPath)) return [];
    const content = cachedChangelog ?? fs.readFileSync(changelogPath, "utf8");
    if (!cachedChangelog) cachedChangelog = content;

    const entries: ChangelogEntry[] = [];
    const versionRegex = /^## \[(.+?)\] - (\d{4}-\d{2}-\d{2})/gm;
    let match;
    const positions: { version: string; date: string; start: number }[] = [];

    while ((match = versionRegex.exec(content)) !== null) {
      positions.push({ version: match[1], date: match[2], start: match.index });
    }

    for (let i = 0; i < Math.min(positions.length, limit); i++) {
      const pos = positions[i];
      const end = i + 1 < positions.length ? positions[i + 1].start : content.length;
      const block = content.slice(pos.start, end);

      const sections: { title: string; items: string[] }[] = [];
      const sectionRegex = /^### (.+)/gm;
      let secMatch;
      const secPositions: { title: string; start: number }[] = [];

      while ((secMatch = sectionRegex.exec(block)) !== null) {
        secPositions.push({ title: secMatch[1], start: secMatch.index + secMatch[0].length });
      }

      for (let j = 0; j < secPositions.length; j++) {
        const sec = secPositions[j];
        const secEnd = j + 1 < secPositions.length ? secPositions[j + 1].start : block.length;
        const secBlock = block.slice(sec.start, secEnd);
        const items = secBlock
          .split("\n")
          .map((l) => l.replace(/^[-*]\s+/, "").trim())
          .filter((l) => l.length > 0 && !l.startsWith("#"));
        if (items.length > 0) {
          sections.push({ title: sec.title, items });
        }
      }

      entries.push({ version: pos.version, date: pos.date, sections });
    }

    return entries;
  } catch {
    return [];
  }
}

export interface ReleaseNotes {
  added: string[];
  improved: string[];
  fixed: string[];
}

export function bumpVersion(
  bumpType: "patch" | "minor" | "major",
  releaseNotes: ReleaseNotes,
): { oldVersion: string; newVersion: string } {
  const pkgPath = resolveProjectFile("package.json");
  const pkg = JSON.parse(fs.readFileSync(pkgPath, "utf8"));
  const oldVersion = pkg.version || "0.0.0";
  const [major, minor, patch] = oldVersion.split(".").map(Number);

  let newVersion: string;
  switch (bumpType) {
    case "major":
      newVersion = `${major + 1}.0.0`;
      break;
    case "minor":
      newVersion = `${major}.${minor + 1}.0`;
      break;
    case "patch":
      newVersion = `${major}.${minor}.${patch + 1}`;
      break;
  }

  pkg.version = newVersion;
  fs.writeFileSync(pkgPath, JSON.stringify(pkg, null, 2) + "\n");

  const today = new Date().toISOString().split("T")[0];
  const sections: string[] = [];

  if (releaseNotes.added.length > 0) {
    sections.push(`### Adicionado\n${releaseNotes.added.map((i) => `- ${i}`).join("\n")}`);
  }
  if (releaseNotes.improved.length > 0) {
    sections.push(`### Melhorado\n${releaseNotes.improved.map((i) => `- ${i}`).join("\n")}`);
  }
  if (releaseNotes.fixed.length > 0) {
    sections.push(`### Corrigido\n${releaseNotes.fixed.map((i) => `- ${i}`).join("\n")}`);
  }

  const newEntry = `## [${newVersion}] - ${today}\n\n${sections.join("\n\n")}\n`;

  const changelogPath = resolveProjectFile("CHANGELOG.md");
  if (fs.existsSync(changelogPath)) {
    const changelog = fs.readFileSync(changelogPath, "utf8");
    const marker = "## [";
    const idx = changelog.indexOf(marker);
    if (idx !== -1) {
      const updated = changelog.slice(0, idx) + newEntry + "\n" + changelog.slice(idx);
      fs.writeFileSync(changelogPath, updated);
    }
  }

  cachedVersion = newVersion;
  cachedChangelog = null;

  return { oldVersion, newVersion };
}

export function getFullChangelog(): string {
  try {
    const changelogPath = resolveProjectFile("CHANGELOG.md");
    if (!fs.existsSync(changelogPath)) return "";
    if (!cachedChangelog) {
      cachedChangelog = fs.readFileSync(changelogPath, "utf8");
    }
    return cachedChangelog;
  } catch {
    return "";
  }
}
```

### Passo 5: Adicionar endpoints de API nas rotas

Adicionar no arquivo de rotas do servidor (ex: `server/routes.ts`):

```typescript
import { getAppVersion, parseChangelog, getFullChangelog, bumpVersion } from "./lib/version";

const buildDate = new Date().toISOString();

// GET /api/version — retorna versão atual e últimas changelog entries
app.get("/api/version", (_req, res) => {
  const version = getAppVersion();
  const changelog = parseChangelog(3);
  const environment = process.env.NODE_ENV || "development";
  res.json({ version, buildDate, environment, changelog });
});

// GET /api/version/changelog — retorna changelog completo (JSON ou Markdown)
app.get("/api/version/changelog", (_req, res) => {
  const format = _req.query.format;
  if (format === "json") {
    res.json(parseChangelog(100));
  } else {
    res.type("text/markdown").send(getFullChangelog());
  }
});

// POST /api/version/bump — incrementar versão (requer admin)
app.post("/api/version/bump", authenticateToken, async (req: any, res) => {
  try {
    // Verificar se é admin (adaptar ao seu sistema de auth)
    if (req.user.profile !== "admin" && req.user.profile !== "superadmin") {
      return res.status(403).json({ message: "Acesso restrito a administradores" });
    }

    const bumpType = req.body.bumpType;
    if (!["patch", "minor", "major"].includes(bumpType)) {
      return res.status(400).json({ message: "bumpType deve ser patch, minor ou major" });
    }

    const releaseNotes = req.body.releaseNotes;
    if (!releaseNotes || typeof releaseNotes !== "object") {
      return res.status(400).json({ message: "releaseNotes é obrigatório" });
    }

    const added = Array.isArray(releaseNotes.added) ? releaseNotes.added.filter((s: string) => s.trim()) : [];
    const improved = Array.isArray(releaseNotes.improved) ? releaseNotes.improved.filter((s: string) => s.trim()) : [];
    const fixed = Array.isArray(releaseNotes.fixed) ? releaseNotes.fixed.filter((s: string) => s.trim()) : [];

    if (added.length === 0 && improved.length === 0 && fixed.length === 0) {
      return res.status(400).json({ message: "Preencha pelo menos uma seção das release notes" });
    }

    const result = bumpVersion(bumpType, { added, improved, fixed });
    return res.json({
      success: true,
      oldVersion: result.oldVersion,
      newVersion: result.newVersion,
      message: `Versão atualizada: ${result.oldVersion} → ${result.newVersion}`,
    });
  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : "Erro interno";
    return res.status(500).json({ message: msg });
  }
});
```

### Passo 6: Criar página de Release Notes (React)

Criar `client/src/pages/release-notes.tsx`:

```tsx
import { useQuery } from "@tanstack/react-query";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import { Loader2, Tag, Calendar, Server, Plus, Wrench, Bug } from "lucide-react";

interface ChangelogSection {
  title: string;
  items: string[];
}

interface ChangelogEntry {
  version: string;
  date: string;
  sections: ChangelogSection[];
}

interface VersionInfo {
  version: string;
  buildDate: string;
  environment: string;
}

function getSectionIcon(title: string) {
  const lower = title.toLowerCase();
  if (lower.includes("adicionado") || lower.includes("added")) return <Plus className="h-4 w-4 text-green-500" />;
  if (lower.includes("melhorado") || lower.includes("changed") || lower.includes("improved")) return <Wrench className="h-4 w-4 text-blue-500" />;
  if (lower.includes("corrigido") || lower.includes("fixed")) return <Bug className="h-4 w-4 text-red-500" />;
  return <Tag className="h-4 w-4 text-muted-foreground" />;
}

function getSectionColor(title: string) {
  const lower = title.toLowerCase();
  if (lower.includes("adicionado") || lower.includes("added")) return "bg-green-500/10 text-green-700 dark:text-green-400";
  if (lower.includes("melhorado") || lower.includes("changed") || lower.includes("improved")) return "bg-blue-500/10 text-blue-700 dark:text-blue-400";
  if (lower.includes("corrigido") || lower.includes("fixed")) return "bg-red-500/10 text-red-700 dark:text-red-400";
  return "bg-muted text-muted-foreground";
}

export default function ReleaseNotesPage() {
  const { data: versionInfo, isLoading: versionLoading } = useQuery<VersionInfo>({
    queryKey: ["/api/version"],
  });

  const { data: changelog, isLoading: changelogLoading } = useQuery<ChangelogEntry[]>({
    queryKey: ["/api/version/changelog", "json"],
    queryFn: async () => {
      const res = await fetch("/api/version/changelog?format=json");
      if (!res.ok) throw new Error("Failed to fetch changelog");
      return res.json();
    },
  });

  const isLoading = versionLoading || changelogLoading;

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-[60vh]">
        <Loader2 className="h-8 w-8 animate-spin text-primary" />
      </div>
    );
  }

  return (
    <div className="p-6 max-w-4xl mx-auto space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Release Notes</h1>
          <p className="text-muted-foreground mt-1">Histórico completo de versões e mudanças do sistema</p>
        </div>
        <div className="flex items-center gap-3">
          <Badge variant="outline" className="flex items-center gap-1.5 px-3 py-1">
            <Tag className="h-3.5 w-3.5" />
            v{versionInfo?.version}
          </Badge>
          <Badge variant="secondary" className="flex items-center gap-1.5 px-3 py-1">
            <Server className="h-3.5 w-3.5" />
            {versionInfo?.environment}
          </Badge>
        </div>
      </div>

      <Separator />

      {changelog?.map((entry) => (
        <Card key={entry.version} className="overflow-hidden">
          <CardHeader className="pb-3">
            <div className="flex items-center justify-between">
              <CardTitle className="flex items-center gap-2">
                <Badge variant="default" className="text-sm px-3 py-0.5">
                  v{entry.version}
                </Badge>
              </CardTitle>
              <span className="flex items-center gap-1.5 text-sm text-muted-foreground">
                <Calendar className="h-3.5 w-3.5" />
                {entry.date}
              </span>
            </div>
          </CardHeader>
          <CardContent className="space-y-4">
            {entry.sections.map((section, secIdx) => (
              <div key={secIdx}>
                <div className="flex items-center gap-2 mb-2">
                  {getSectionIcon(section.title)}
                  <span className={`text-xs font-semibold uppercase tracking-wider px-2 py-0.5 rounded ${getSectionColor(section.title)}`}>
                    {section.title}
                  </span>
                </div>
                <ul className="space-y-1.5 ml-6">
                  {section.items.map((item, itemIdx) => (
                    <li key={itemIdx} className="text-sm text-muted-foreground flex items-start gap-2">
                      <span className="mt-1.5 h-1.5 w-1.5 rounded-full bg-muted-foreground/40 shrink-0" />
                      {item}
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </CardContent>
        </Card>
      ))}

      {(!changelog || changelog.length === 0) && (
        <Card>
          <CardContent className="py-8 text-center text-muted-foreground">
            Nenhum registro de versão disponível.
          </CardContent>
        </Card>
      )}
    </div>
  );
}
```

### Passo 7: Registrar rota no App.tsx

```tsx
import ReleaseNotesPage from "@/pages/release-notes";

// Dentro do Router/Switch:
<Route path="/release-notes" component={ReleaseNotesPage} />
```

### Passo 8: Adicionar badge de versão no Sidebar

No componente de sidebar, adicionar no footer:

```tsx
import { useQuery } from "@tanstack/react-query";

// Dentro do componente:
const { data: versionData } = useQuery<{ version: string }>({
  queryKey: ["/api/version"],
});
const appVersion = versionData?.version;

// No JSX do footer do sidebar:
{appVersion && (
  <Link href="/release-notes">
    <div className="text-[10px] text-center text-muted-foreground/50 hover:text-muted-foreground transition-colors cursor-pointer">
      v{appVersion}
    </div>
  </Link>
)}
```

## Uso via CLI

```bash
# Incrementar patch (1.0.0 -> 1.0.1)
npm run version:bump patch

# Incrementar minor (1.0.0 -> 1.1.0)
npm run version:bump minor

# Incrementar major (1.0.0 -> 2.0.0)
npm run version:bump major
```

Após executar, editar o CHANGELOG.md para preencher os itens da nova versão.

## Uso via API

```bash
# Consultar versão atual
GET /api/version

# Consultar changelog (JSON)
GET /api/version/changelog?format=json

# Consultar changelog (Markdown)
GET /api/version/changelog

# Incrementar versão programaticamente (requer auth admin)
POST /api/version/bump
{
  "bumpType": "minor",
  "releaseNotes": {
    "added": ["Nova feature X", "Nova feature Y"],
    "improved": ["Performance do módulo Z"],
    "fixed": ["Bug na tela de login"]
  }
}
```

## Dependências

- **Backend:** Node.js, Express (ou framework similar), `fs`, `path`
- **Frontend:** React, TanStack Query, Shadcn UI (Badge, Card, Separator), lucide-react
- **Formato:** Keep a Changelog + Versionamento Semântico (SemVer)

## Adaptações por Projeto

- Ajustar o middleware de autenticação (`authenticateToken`) conforme o sistema de auth do projeto
- Ajustar a verificação de perfil admin (`req.user.profile`) conforme o modelo de permissões
- Adaptar os componentes UI (Shadcn, etc.) conforme a stack do projeto
- A rota `/release-notes` pode ser restrita a admin/superadmin conforme necessidade

## Regras

1. Sempre manter o CHANGELOG.md atualizado ao fazer bump de versão
2. Seguir SemVer: major (breaking), minor (nova feature), patch (correção)
3. Cada entrada de changelog deve ter pelo menos uma seção preenchida (Adicionado, Melhorado ou Corrigido)
4. O badge de versão no sidebar deve ser clicável e levar à página de release notes
