---
name: voxfone-telephony-crm
description: Expert patterns for building and modifying the VoxFone CRM telephony system. Use when adding features, fixing bugs, or extending any part of the softphone, CDR reports, Asterisk integration, SIP/WebRTC, audio playback/download, extension management, agendas, or database configuration. Covers authentication, recording retrieval, report filters, and all UI/UX conventions.
---

# VoxFone Telephony CRM System Skill

This skill captures the architecture, patterns, and conventions of the VoxFone CRM telephony system — a full-stack web application integrating SIP/WebRTC softphone, Asterisk PBX, external PostgreSQL CDR database, call recording retrieval/conversion, and contact management.

## Architecture Overview

- **Frontend:** React + TypeScript + Vite, Tailwind CSS + Shadcn UI, `wouter` routing, `@tanstack/react-query` v5
- **Backend:** Node.js + Express + TypeScript, Drizzle ORM (local PostgreSQL), `pg` library (external PostgreSQL)
- **Telephony:** SIP.js (WebRTC), connecting to Asterisk via WSS
- **Audio:** FFmpeg for GSM→MP3 conversion, HTML5 Audio API for playback
- **Auth:** Dual system — Admin (email/password) + Extension (SIP credentials), session stored in localStorage + `X-Admin-Session` header

## Key Files Map

| Area | Files |
|------|-------|
| Schema | `shared/schema.ts` |
| Routes | `server/routes.ts` |
| Storage | `server/storage.ts` |
| Admin Auth | `server/adminAuth.ts`, `client/src/hooks/useAuth.ts` |
| Extension Auth | `server/extensionAuth.ts` |
| Query Client | `client/src/lib/queryClient.ts` |
| SIP Context | `client/src/contexts/SipContext.tsx`, `client/src/contexts/ExtensionSipContext.tsx` |
| Chat Context | `client/src/contexts/ChatContext.tsx` |
| CDR Reports | `client/src/pages/CDRReportsSimple.tsx` |
| Softphone | `client/src/pages/softphone.tsx`, `client/src/pages/ExtensionSoftphone.tsx` |
| Floating Softphone | `client/src/components/floating-softphone.tsx`, `client/src/components/sip-auto-register.tsx` |
| Config Pages | `DatabaseConfig.tsx`, `AsteriskConfig.tsx`, `SipConfigurationFixed.tsx` |
| Agendas | `GlobalAgenda.tsx`, `PersonalAgenda.tsx` |
| Extensions | `ExtensionManagementImproved.tsx` |
| Ramais PBX | `client/src/pages/ramais-pbx.tsx` |
| Deploy Assistant | `client/src/pages/deploy-assistant.tsx`, `server/dockerGenerator.ts` |
| Backup & Restore | `client/src/pages/backup.tsx`, `server/backup-scheduler.ts` |
| Report Assistant | `client/src/pages/report-assistant.tsx`, `server/report-agent.ts`, `server/report-knowledge.ts` |
| Diagnostic Assistant | `client/src/pages/diagnostic-assistant.tsx`, `server/diagnostic-agent.ts` |
| Sidebar | `client/src/components/sidebar.tsx` |
| Routing | `client/src/App.tsx` |

## Authentication Pattern

### Dual Auth System
1. **Admin users** — login via `/api/admin/login` with email/password. Session stored in memory (server) and `localStorage` key `voxfone-admin-session` (client).
2. **Extension users** — login via `/api/extension/login` with extension number/password. Session stored via `extensionSession` cookie.

### Session Header Injection
Replit iframe blocks third-party cookies. All fetch calls automatically include `X-Admin-Session` header via a global fetch interceptor in `client/src/main.tsx`:

```typescript
const originalFetch = window.fetch;
window.fetch = function(input, init) {
  const sessionId = localStorage.getItem('voxfone-admin-session');
  if (sessionId) {
    const headers = new Headers(init?.headers || {});
    if (!headers.has('X-Admin-Session')) {
      headers.set('X-Admin-Session', sessionId);
    }
    init = { ...init, headers };
  }
  return originalFetch.call(window, input, init);
};
```

### Auth Middlewares
- `requireAdminAuth` — checks `X-Admin-Session` header first, then `adminSession` cookie
- `requireAnyAuth` — checks admin header, admin cookie, then extension cookie
- `requireExtensionAuth` — checks `extensionSession` cookie
- Always add header check BEFORE cookie check in any new middleware

### Role Hierarchy (4 Levels)
The system has 4 user roles with hierarchical permissions:
1. **`user`** — Basic access: Dashboard, Ramais PBX, Relatórios
2. **`supervisor`** — User + Softphone, Gravações, Gerenciamento (Ramais, Troncos, Filas, Operadores, Membros)
3. **`administrator`** — Supervisor + Configurações, Backup, Gerenciar Usuários, Assistente IA, Planos de Discagem
4. **`superadmin`** — Full access; only role that can create/edit/delete other SuperAdmins

**Hierarchical Protection (Backend)**:
- `requireRole(["administrator", "superadmin"])` on `/api/users` CRUD routes
- POST/PUT: if `role === "superadmin"` and requester isn't superadmin → 403
- PUT: if target user is superadmin and requester isn't superadmin → 403
- DELETE: if target user is superadmin and requester isn't superadmin → 403

**Frontend Protection**:
- `canManageUser(currentRole, targetRole)` hides edit/delete buttons when not allowed
- SuperAdmin option in role dropdown only visible when current user is superadmin
- Sidebar `requiredRole` arrays include `"superadmin"` in all sections

### Menu Permissions (SuperAdmin-managed)
SuperAdmin configures which menu items each role can see via `/menu-permissions` page. Config saved to `menu-permissions.json` as `Record<string, string[]>` (role → array of allowed href paths). When no config exists, all items are visible (default behavior). SuperAdmin always sees everything.

**How it works**:
- Backend: `GET/PUT /api/menu-permissions` — GET is public (any auth), PUT requires `superadmin` role
- Sidebar (`sidebar.tsx`): Fetches `menuPermissions` via React Query, `isItemAllowed(href)` checks if item is in the role's allowed list
- Home page (`home.tsx`): Same filtering applied to the welcome page menu cards
- Items with `superadminOnly: true` are hidden from non-superadmin users regardless of permissions

Key files: `client/src/pages/menu-permissions.tsx`, `client/src/components/sidebar.tsx`, `client/src/pages/home.tsx`, `server/routes.ts`

**IMPORTANT — Keeping permissions in sync**: Whenever a new page or sidebar entry is added to the system, it MUST also be added to the `allMenuItems` array in `client/src/pages/menu-permissions.tsx` in the corresponding section (Painel Principal, Relatórios, Supervisor, Discador, PBXIP, Administrador). The sections in this array must mirror the sidebar sections in `sidebar.tsx`. Failing to add new items here means SuperAdmin cannot control access to those pages.

**Sidebar section auto-hide**: The sidebar (`sidebar.tsx`) checks `hasVisibleItems` before rendering each section. If no items in a section are permitted for the current user's role, the section title and separator are hidden entirely. This applies to all sections including Discador, PBXIP, etc.

### SuperAdmin Seeding
The SuperAdmin user is created/updated automatically on every server start via `seedSuperAdmin()` in `server/seed.ts`. Credentials come from environment variables:
- `SUPERADMIN_PASSWORD` (secret, required) — if not set, superadmin creation is skipped
- `SUPERADMIN_EMAIL` (env var, default: `superadmin@voxtel.biz`)
- `SUPERADMIN_USERNAME` (env var, default: `superadmin`)

If the user already exists, the password is updated from the env var and role is ensured to be `superadmin`.
**Important**: Seed only updates `passwordHash` and `isActive` — it does NOT overwrite `sipExtension` or `sipPassword`.

### Email & Password Recovery
SMTP configuration page at `/smtp-config` (ADMINISTRADOR section). Config saved to `smtp-config.json` with fields: `host`, `port`, `secure`, `ignoreTLS`, `user`, `password`, `from`, `fromName`. The `ignoreTLS` option sets `tls: { rejectUnauthorized: false }` for servers with self-signed or mismatched certificates.

**Password recovery flow**:
1. User clicks "Esqueci minha senha" on login page
2. `POST /api/auth/forgot-password` with email → creates token in `password_reset_tokens` table (1-hour expiry)
3. Email sent via nodemailer with reset link: `/reset-password?token=...`
4. `POST /api/auth/reset-password` with token + new password → validates token (not used, not expired, user active), updates password, marks token as used

Key files: `client/src/pages/smtp-config.tsx`, `client/src/pages/reset-password.tsx`, `client/src/pages/login.tsx`, `server/routes.ts`

### Home Page (Welcome)
After login, users land on `/` (Home page) instead of Dashboard. Shows all menu options organized by section with icons and descriptions, filtered by role and menu permissions. Dashboard moved to `/dashboard`.

Key file: `client/src/pages/home.tsx`

## CDR Reports Pattern

### CRITICAL: Timestamp Formatting Rule (TO_CHAR — No JavaScript Date)
**NEVER** pass raw `eventdate` or `calldate` from PostgreSQL to the frontend. The `pg` Node.js driver interprets `timestamp without timezone` as UTC, causing a **3-hour shift** for Brazil (UTC-3) data.

**ALWAYS** use `TO_CHAR()` in SQL to format timestamps directly in PostgreSQL:
```sql
-- For display columns:
TO_CHAR(ql.eventdate, 'DD/MM/YYYY HH24:MI:SS') AS data_hora_fmt
TO_CHAR(cdr.calldate, 'DD/MM/YYYY HH24:MI:SS') AS calldate_fmt
TO_CHAR(eventdate, 'HH24:MI:SS') AS hora
TO_CHAR(eventdate::date, 'DD/MM/YYYY') AS dia

-- For date range filtering (direct comparison, NO EPOCH):
WHERE ql.eventdate BETWEEN '20260302' AND '20260302 235959'
-- NEVER: WHERE EXTRACT(EPOCH FROM ql.eventdate) BETWEEN ...
```

**Backend mapping**: Use the pre-formatted string directly:
```typescript
// CORRECT:
dataHora: row.data_hora_fmt || ''
calldate: row.calldate_fmt || row.calldate

// WRONG — causes timezone shift:
dataHora: this.formatDateTime(row.eventdate)
dataHora: new Date(row.eventdate).toLocaleString()
```

**Frontend guards**: If receiving a pre-formatted `DD/MM/YYYY` string, detect it and skip re-parsing:
```typescript
if (/^\d{2}\/\d{2}\/\d{4}/.test(dateStr)) return dateStr;
```

**Applies to ALL reports**: attended calls, abandoned calls, CDR viewer, queue_log viewer, retorno pendentes, Report Assistant templates, and AI-generated custom queries.

### CRITICAL: Timestamp Formatting in Node.js (when SQL TO_CHAR is not viable)

When you must format a `Date` (or `timestamptz`) on the Node side — for instance because the value comes from a join, a cache, or a non-trivial pipeline — **NEVER** use the `getUTC*` family (`getUTCDate`, `getUTCHours`, …) and **NEVER** call `.toLocaleString()` without an explicit `timeZone`. Both produce a +3h drift versus the platform's official timezone (`America/Sao_Paulo`).

Use the centralized helpers in `server/utils/datetime.ts`:
```typescript
import { formatBRDateTime, formatBRDate, formatBRTime, SAO_PAULO_TZ } from "./utils/datetime";

// dd/MM/yyyy HH:mm:ss em America/Sao_Paulo
hora_login: formatBRDateTime(row.hora_login),  // Date | string | number | null -> string | null
dia:        formatBRDate(row.eventdate),
hora:       formatBRTime(row.eventdate),
```

The helpers wrap `Intl.DateTimeFormat` with `timeZone: 'America/Sao_Paulo'`, so the output is the same horário visto pelo Asterisk, pelo `psql` e pelos relatórios — independentemente do fuso do container Node ou do navegador do usuário.

**Real bug fixed (referência)**: `server/routes.ts` formatava `hora_login` em `/api/callcenter/operators-status` com `getUTCDate/getUTCHours/...`. Como o `pg` driver entrega o timestamp como instante UTC (`08:05` em SP = `11:05Z`), a coluna "HORA LOGIN" da dashboard mostrava 11:05 em vez de 08:05. Substituído por `formatBRDateTime(row.hora_login)`. Aplique o mesmo padrão em qualquer novo endpoint que devolva `Date` para o frontend.

### Report Filter Convention
All report pages follow this filter pattern:
- **Date range:** Two date inputs (`startDate`, `endDate`), **ALWAYS defaulting to current date** (`new Date().toISOString().split('T')[0]`). NEVER use date subtraction (e.g. `-7` days, `-30` days) for defaults.
- **Source/Destination:** Text inputs for extension numbers
- **Disposition filter:** Dropdown with options: ALL, ANSWERED, NO ANSWER, BUSY, FAILED
- **Pagination:** `limit` (default 10) and `offset` parameters
- **Total count:** Separate query for total record count to support pagination UI

### CDR Data Flow
```
Frontend (filters) → GET /api/cdr/records?startDate=X&endDate=Y&src=Z&limit=10&offset=0
  → storage.getCdrRecords(filters)
    → getDatabaseCredentials() → find active external DB
    → testDatabaseConnection() → verify connectivity (8s timeout)
    → pg.Client connect to external PostgreSQL (SSL: rejectUnauthorized: false)
    → SELECT from cdr table with filters
    → Map rows to CdrRecord type
  → storage.getCdrTotalCount(filters) → separate COUNT query
  → Response: { records: CdrRecord[], total: number }
```

### CDR Record Type
```typescript
{
  id: string;          // uniqueid from CDR
  src: string;         // source extension
  dst: string;         // destination number
  disposition: string; // ANSWERED | NO ANSWER | BUSY | FAILED
  duration: number;    // total duration in seconds
  billsec: number;     // billable seconds
  calldate: string;    // ISO date string
  channel: string;     // PJSIP/1053-XXXXXXXX
  dstchannel: string;  // PJSIP/vitahome-XXXXXXXX
  userfield: string;   // "GRAVANDO" indicates recording exists
  uniqueid: string;    // unique call identifier (e.g., "1749596725.560")
}
```

### Extension CDR Isolation (Mandatory Filter)
Extension users (ramal login) MUST only see their own calls. This is enforced at the backend level:

**Backend enforcement** (`server/routes.ts`):
- `GET /api/extension/cdr` and `GET /api/extension/cdr/export` both extract the ramal from `req.extensionUser.extension` (or `sipConfig.sipUser` for admin)
- `sipExtension` is passed as mandatory filter to `storage.getCdrRecords(filters)` and `getCdrTotalCount(filters)`
- SQL generated: `WHERE (src = $ramal OR dst = $ramal)` — shows only calls where the extension is origin OR destination
- If ramal cannot be identified, returns HTTP 400 ("Ramal não identificado")
- Response includes `extension` field: `{ records, total, extension: "1051" }`

**Frontend auto-load** (`client/src/components/ExtensionCdrReports.tsx`):
- On mount, reads `sessionStorage.getItem('extensionUser')` to get extension number
- Sets default date range to last 7 days and auto-triggers query (`shouldQuery = true`)
- Shows badge "Ramal XXXX" in the report title via `<Badge>` component
- Results count shows "(ramal XXXX)" indicator
- "Limpar Filtros" resets dates to last 7 days but keeps query active (doesn't disable auto-query)
- Users can still filter by src/dst for additional refinement (e.g., calls to a specific number)

**Admin CDR route** (`GET /api/cdr/records`) does NOT apply this filter — admins see all records.

### Report Table Convention
- Use Shadcn `<Table>` component
- Status badges with colors: green=ANSWERED, red=NO ANSWER/FAILED, yellow=BUSY
- Action buttons per row: Play, Download, Details
- Responsive: collapse columns on mobile, show essential info only
- Include `data-testid` on all interactive elements

## Audio Recording System

### Recording Config
Config stored in `asterisk-recordings-config.json` at project root:
```json
{
  "baseUrl": "http://server/voxmax/gravacoes",
  "authType": "none|basic|bearer",
  "username": "", "password": "", "bearerToken": ""
}
```
Managed via `/api/asterisk-recordings/config` (GET/PUT) and `/api/asterisk-recordings/test` (POST).

### Recording Retrieval
The `/api/cdr/audio/:uniqueid` endpoint tries multiple paths with 8s timeout per attempt:
1. Primary: `{baseUrl}/{uniqueid}.gsm`
2. Fallbacks: `.wav`, `.mp3`, `monitor/{uniqueid}.gsm`, `monitor/{uniqueid}.wav`
3. Auth headers applied per config (`Basic` or `Bearer`)
4. Detailed logging: `[audio] Buscando ...`, `[audio] ENCONTRADO/NÃO ENCONTRADO`

### Recordings Infrastructure (nginx + Docker volumes)
- nginx config includes `location /voxmax/gravacoes/` with `alias /var/spool/asterisk/monitor/` for direct file serving
- docker-compose.yml mounts `asterisk_recordings` external volume (read-only) in the nginx container
- Recording files at `/var/spool/asterisk/monitor/{uniqueid}.gsm` (Docker volume `voxcall-asterisk_asterisk_recordings`)
- URL pattern: `https://domain/voxmax/gravacoes/{uniqueid}.gsm`
- App container (`voxcall-app`) requires FFmpeg for GSM→MP3 conversion: `RUN apk add --no-cache ffmpeg` in Dockerfile

### GSM to MP3 Conversion
FFmpeg installed in app container (`apk add --no-cache ffmpeg`). Conversion with explicit format and codec:
```typescript
const ffmpeg = spawn('ffmpeg', [
  '-y', '-f', 'gsm', '-i', gsmFile,
  '-acodec', 'libmp3lame',
  '-ab', '128k',
  '-ar', '44100',    // 44.1kHz for browser compatibility
  '-ac', '1',        // Mono
  mp3File
]);
```
- Stderr captured and logged on failure: `[audio] ffmpeg falhou (code X): ...`
- Success logged: `[audio] ffmpeg conversao OK`
- **Fallback**: If ffmpeg fails, tries fetching `.wav` or `.mp3` versions from server
- If all fail: returns 415 error with descriptive message
- Response headers: `Content-Type: audio/mpeg`, `Content-Length`, `Cache-Control: public, max-age=3600`

### Frontend Audio Playback
```typescript
const response = await fetch(`/api/cdr/audio/${uniqueid}`, {
  credentials: 'include',
  headers: { 'Accept': 'audio/*' }
});
// Validate response
if (contentType.includes('application/json')) throw new Error(errData.message);
if (blob.size === 0) throw new Error('Arquivo de audio vazio');
// Play via blob URL
const audioUrl = URL.createObjectURL(blob);
const audio = new Audio(audioUrl);
audio.addEventListener('error', () => { /* handle unsupported format */ });
await audio.play();
```
- Always use blob approach (not direct URL) to include auth headers
- Validates content-type (rejects JSON error responses) and blob size
- Audio element error listener catches unsupported formats
- Track `currentPlayingId` state to show visual indicator on active row
- Player files: `recordings-operators.tsx` (by operator), `recordings.tsx` (by extension)

### Frontend Audio Download
```typescript
// If audio already loaded, reuse blob; otherwise fetch fresh
if (blobUrlRef.current) { blob = await fetch(blobUrlRef.current).then(r => r.blob()); }
else { blob = await fetch(`/api/cdr/audio/${callid}`, { credentials: 'include' }).then(r => r.blob()); }
const a = document.createElement('a');
a.href = URL.createObjectURL(blob);
a.download = `gravacao_${operador}_${telefone}_${dataHora}.mp3`;
a.click();
```
- Server also has `/api/cdr/download/:uniqueid` endpoint that internally calls `/api/cdr/audio/` and sets `Content-Disposition: attachment`

## SIP/WebRTC Softphone Pattern

### Per-User SIP Credentials
Each user has their own SIP extension and password stored in the `users` table:
- `sipExtension` (text, nullable) — the user's SIP ramal number (e.g., "1050")
- `sipPassword` (text, nullable) — the user's SIP password (plain text, stored securely)

**Two API endpoints for SIP config**:
- `GET /api/sip-webrtc/config` — **per-user** endpoint (used by softphone auto-register). Merges global server settings (sipServer, wssPort, STUN/TURN, enabled) with the logged-in user's `sipExtension`/`sipPassword`. If user has no `sipExtension`, returns empty `extension`/`password` and softphone won't register.
- `GET /api/sip-webrtc/config/global` — **admin-only** endpoint. Returns raw global config from `sip-webrtc-config.json` for the admin config page (`/sip-webrtc-config`). NEVER use this for softphone auto-register.

**Security rules**:
- `sipPassword` is NEVER exposed in `req.session.user`, `GET /api/auth/me`, or `GET /api/users` responses
- Only `sipExtension` (not password) is visible in user listings and session data
- `sipPassword` is only accessible via `GET /api/sip-webrtc/config` (per-user, requires auth) for softphone registration

**User form (users.tsx)**:
- Fields: "Ramal SIP" (`sipExtension`) and "Senha SIP" (`sipPassword`)
- When `sipExtension` is empty string, it's sent as `null` to clear the field
- When `sipPassword` is empty on edit, it's omitted from the request (preserves existing password)
- Dialog has `max-h-[90vh] overflow-y-auto` for scrolling on small screens

### SIP Auto-Register (sip-auto-register.tsx)
- Fetches `/api/sip-webrtc/config` with `staleTime: 30000` and `refetchInterval: 30000` (polls every 30s)
- Only registers if: `enabled=true`, `sipServer` present, `extension` non-empty, not already registered/connecting
- Tracks `lastExtensionRef` to detect extension changes — if extension changes while registered, unregisters first then re-registers
- When user saves SIP data in users form, `queryClient.invalidateQueries({ queryKey: ["/api/sip-webrtc/config"] })` forces immediate refresh

### Dashboard Softphone Integration
- "Ouvir no Softphone (Ramal XXXX)" toggle in supervisor actions modal
- When ON: Monitorar/Intercalar/Conferência execute directly using user's `sipExtension` without manual ramal prompt
- Uses `sipExtension` from user session data (not from SIP config endpoint)

### SIP.js Configuration
```typescript
const userAgent = new SIP.UserAgent({
  uri: SIP.UserAgent.makeURI(`sip:${sipUser}@${sipServer}`),
  transportOptions: {
    server: `wss://${sipServer}:${wssPort}/ws`
  },
  authorizationUsername: sipUser,
  authorizationPassword: sipPassword,
  sessionDescriptionHandlerFactoryOptions: {
    peerConnectionConfiguration: {
      iceServers: [{ urls: 'stun:stun.l.google.com:19302' }]
    },
    constraints: {
      audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false },
      video: false
    }
  }
});
```

### Call Flow
1. **Outbound:** Create `SIP.Inviter` → `inviter.invite()` → Track state changes → Attach remote media stream to `<audio>` element
2. **Inbound:** `onInvite` delegate → Show incoming call modal → `invitation.accept()` or `invitation.reject()`
3. **DTMF:** Send via `SIP.INFO` method
4. **Auto-reconnect:** On transport disconnect, retry after 5 seconds

### SIP Context Pattern
Two separate contexts:
- `SipContext` — for admin users (full features)
- `ExtensionSipContext` — for extension users (limited to softphone + agenda)

Both provide: `register()`, `unregister()`, `makeCall(number)`, `hangUp()`, `answer()`, `sendDtmf(digit)`, `toggleMute()`

### Global Floating Softphone
- **Component**: `client/src/components/floating-softphone.tsx`
- **Behavior**: `SipProvider` at `App.tsx` level; `SipAutoRegister` auto-registers; `FloatingSoftphone` renders on all pages except `/softphone`
- **States**: minimized (pill with status icon + ramal/duration) and expanded (full controls with answer/reject/mute/hangup)
- **Draggable**: Uses `useDraggable()` hook with Pointer Events API for drag-and-drop repositioning
  - Position saved to `localStorage` key `voxcall-softphone-pos`
  - Clamped to viewport bounds on drag and window resize
  - Drag handle: title bar (expanded) or entire pill (minimized)
  - Buttons/inputs excluded from drag via `closest()` guard
  - `hasMoved` ref prevents click-through after drag gesture
- **Icons**: `Square` (maximize/open full page), `Minus` (minimize), `GripHorizontal` (drag hint in expanded title bar)
- **Incoming call alerts**: Title bar flash (`setInterval` 800ms), browser `Notification` when tab is hidden, auto-expand on incoming

## External Database Connection Pattern

### Dynamic Client Pattern
```typescript
async getCdrRecords(filters) {
  const credentials = await this.getDatabaseCredentials(); // Get active config
  if (credentials) {
    const isConnected = await this.testDatabaseConnection(credentials);
    if (isConnected) {
      const client = new pg.Client({
        host: credentials.host,
        port: credentials.port,
        database: credentials.database,
        user: credentials.username,
        password: credentials.password,
        ssl: credentials.ssl ? { rejectUnauthorized: false } : false,
        connectionTimeoutMillis: 8000
      });
      await client.connect();
      // ... execute query ...
      await client.end();
    }
  }
  // Fallback to local DB if external fails
}
```

### Key Rules
- Always test connectivity before querying (8-second timeout)
- Always close `client.end()` after use (no connection pooling for external)
- SSL with `rejectUnauthorized: false` for self-signed certs
- Only ONE active database credential at a time (deactivate others on activation)
- Graceful fallback to local database on external failure

## Config File Persistence (Docker Production)

All JSON config files are stored in a persistent Docker volume (`app_configs`) mounted at `/app/config/` in production. In development, configs are stored in `process.cwd()`.

**Config files:** `db-config.json`, `db-replica-config.json`, `ari-config.json`, `ami-config.json`, `ssh-config.json`, `sip-webrtc-config.json`, `smtp-config.json`, `asterisk-recordings-config.json`, `menu-permissions.json`, `system-settings.json`, `backup-schedule.json`

**Helper function** `getConfigDir()` (defined in `routes.ts`, `agent.ts`, `storage.ts`, `ssh-terminal.ts`, `backup-scheduler.ts`):
```typescript
function getConfigDir(): string {
  if (process.env.NODE_ENV === 'production') {
    return path.join(process.cwd(), 'config');
  }
  return process.cwd();
}
```

**RULE:** NEVER use `path.join(process.cwd(), 'some-config.json')` directly. Always use `path.join(getConfigDir(), 'some-config.json')`.

**Frontend cache invalidation:** All save mutations in `settings.tsx` MUST call `queryClient.invalidateQueries({ queryKey: ["/api/endpoint"] })` in `onSuccess` to ensure fresh data when navigating back to the page.

## Asterisk Configuration Pattern

### Recording URL Config
Stored in `asterisk-recordings-config.json` (separate from ARI config):
- `baseUrl`: Base URL for recordings (e.g., `http://server/voxmax/gravacoes`)
- `authType`: `none`, `basic`, or `bearer`
- `username`/`password`: For basic auth
- `bearerToken`: For bearer auth
- Managed via dedicated config page and API endpoints (`/api/asterisk-recordings/config`)

### Auth Headers for Recording Fetch
```typescript
const headers = {};
if (config.authType === 'basic') {
  headers['Authorization'] = `Basic ${btoa(username + ':' + password)}`;
} else if (config.authType === 'bearer') {
  headers['Authorization'] = `Bearer ${config.bearerToken}`;
}
```

## Agenda/Contacts Pattern

### Two Scopes
1. **Global Agenda** — shared across all users, stored in `global_agenda` table
2. **Personal Agenda** — per SIP extension, stored in `personal_agenda` table, filtered by `sip_extension`

### Contact Fields
```typescript
{ phoneNumber, contactName, company, email, notes, createdBy }
```

### Click-to-Call
Both agendas integrate with SIP context to allow direct calling:
```typescript
const { makeCall } = useSipContext();
<Button onClick={() => makeCall(contact.phoneNumber)}>Ligar</Button>
```

## Queue Management Pattern (Gerenciar Filas)

### Architecture
- **Page**: `client/src/pages/queues-management.tsx` at route `/queues-management`
- **Backend**: CRUD endpoints at `/api/queues-config` using `withExternalPg` helper
- **Table**: `queue_table` in external Asterisk PostgreSQL (all varchar columns)
- **Security**: `QUEUE_TABLE_COLUMNS` whitelist array in `server/routes.ts` prevents SQL column injection

### CRUD Pattern
```
GET /api/queues-config → SELECT * FROM queue_table ORDER BY name
POST /api/queues-config → INSERT (filtered by QUEUE_TABLE_COLUMNS whitelist)
PUT /api/queues-config/:name → UPDATE (only whitelisted columns with data[k] !== undefined)
DELETE /api/queues-config/:name → DELETE FROM queue_table WHERE name = $1
```

### UI Features
- **Tabbed Modal Form**: 5 tabs (Geral, Tempos, Capacidade, Anúncios, Avançado) covering all 40 queue_table fields
- **Table Headers**: Portuguese labels with descriptive `title` tooltips on hover
- **Form Tooltips**: All form field labels have `title` attribute with detailed explanations (via `FormField` component with `hint` prop mapped to `title`)
- **Help Manual**: "Manual" button opens comprehensive ScrollArea dialog with `HelpItem` and `HelpItemCompact` components — organized by section with examples, tips, and strategy options
- **Clone Feature**: When creating, a `Select` dropdown loads all settings from an existing queue (cloneFrom function) — name field stays empty for user input
- **Delete Confirmation**: `AlertDialog` with explicit confirmation (replaces native `confirm()`) — red "Excluir Fila" button with loading spinner
- **Toast Duration**: All toasts use `duration: 1000` (1 second auto-dismiss)

### Key Components
- `FormField({ label, children, hint })` — renders Label with `title={hint}` and cursor-help
- `YesNoSelect({ value, onChange })` — reusable yes/no dropdown
- `HelpItem({ field, technical, description, example, tip, options })` — detailed help card
- `HelpItemCompact({ field, technical, description })` — compact help row for audio fields

### Important Rules
- No auto-seeding — data only modified via user action
- Name field disabled when editing (primary key cannot change)
- Clone dropdown only shown when creating AND queues exist
- QUEUE_TABLE_COLUMNS whitelist must match actual DB columns

## UI/UX Conventions

### Page Layout
- Sidebar (desktop) / Bottom nav (mobile) for navigation
- Main content area with header (page title + action buttons)
- Cards for configuration forms
- Tables for data listing (CDR, users, extensions)

### Form Pattern
- Shadcn `Form` + `react-hook-form` + `zodResolver`
- Toast notifications for success/error feedback (`useToast` from `@/hooks/use-toast`)
- Loading states via `isPending` on mutations
- Destructive actions (delete) use `AlertDialog` with explicit confirmation instead of native `confirm()`
- Toast duration: use `duration: 1000` for quick auto-dismiss (1 second)

### Table Pattern
- Column headers should have Portuguese labels with descriptive `title` tooltips on hover
- Form field labels use `title` attribute for tooltip explanations (cursor-help style)

### Status Indicators
- Connection status: green dot = connected, red dot = disconnected
- Call status: ringing (yellow), connected (green), ended (gray)
- Recording indicator: `userfield === "GRAVANDO"` means recording available

### Language
All UI labels in Portuguese (pt-BR). Maintain this convention for any new features.

## Adding New Features Checklist

1. **Schema first** — Define tables/types in `shared/schema.ts`
2. **Storage interface** — Add methods to `IStorage` in `server/storage.ts`
3. **Implement storage** — Add to `DatabaseStorage` class
4. **API routes** — Add to `server/routes.ts` with appropriate auth middleware
5. **Frontend page** — Create in `client/src/pages/`, register in `App.tsx`
6. **Sidebar entry** — Add to `Sidebar.tsx` with permission check
7. **Permission** — Add new permission string to admin user's permissions array
8. **Test** — Verify auth works (header + cookie), test with real data

## Dashboard — Ações no Ramal (ARI Actions Modal)

- **Trigger**: Clique no ramal na tabela "Gráfico da Operação" do dashboard
- **Modal**: Dialog com 7 botões de ação para o ramal selecionado
- **Ações ARI via Dialplan** (contexto `MANAGER`, requerem canal ativo + `ramalSupervisor` no body):
  - **Monitorar**: `POST /api/ari/channels/:ramal/spy` → Originate `*1369{ramal}` — ChanSpy com flag `q` (só escuta)
  - **Intercalar**: `POST /api/ari/channels/:ramal/whisper` → Originate `*1370{ramal}` — ChanSpy com flags `qw` (whisper)
  - **Conferência**: `POST /api/ari/channels/:ramal/conference` → Originate `*1371{ramal}` — ChanSpy com flags `qB` (barge, conferência a 3)
- **Desligar Canal**: `POST /api/ari/channels/:ramal/hangup` — DELETE no canal ativo via ARI
- **Ações DB** (tabela `monitor_operador`, campo `ramal` como referência):
  - **Pausar**: `POST /api/ari/channels/:ramal/pause` — SET fl_pausa=1
  - **Despausar**: `POST /api/ari/channels/:ramal/unpause` — SET fl_pausa=0
  - **Deslogar**: `POST /api/ari/channels/:ramal/logout` — DELETE FROM monitor_operador
- **Trigger DB `trg_sync_monitor_to_queue`**: Sincroniza `monitor_operador` → `queue_member_table` automaticamente:
  - Pausar (fl_pausa=1) → `queue_member_table.paused = '1'` em todas as filas do operador
  - Despausar (fl_pausa=0) → `queue_member_table.paused = '0'` em todas as filas
  - Deslogar (DELETE) → remove operador de `queue_member_table` (todas as filas)
- **IMPORTANTE**: Para ChanSpy via ARI, usar `context`+`extension` no Originate, NUNCA `app` (Stasis faz o canal cair)
- **Helpers reutilizáveis**: `loadAriConfig()`, `ariRequest()`, `findChannelByRamal()` em `server/routes.ts`

## Dashboard — Visual Pattern (MANDATORY for ALL Dashboard Pages)

All dashboard and monitoring pages (Dashboard Principal, Discador, Filas, etc.) MUST follow this exact visual pattern for consistency. This is the authoritative reference — never invent custom layouts.

### Page Structure
```tsx
<div className="flex flex-col h-full">
  <header className="bg-card border-b border-border px-6 py-4">
    {/* Title row + filter controls + action buttons */}
  </header>
  <main className="flex-1 overflow-auto p-6">
    {/* Content: KPI cards, operator cards, charts, tables */}
  </main>
</div>
```

### Header Bar
- Background: `bg-card border-b border-border px-6 py-4`
- Left side: Icon + title (`text-xl font-semibold`)
- Right side: Filter controls (Select/Dropdown with Filter icon), live indicator badge, Refresh button (`RefreshCw` icon)
- Live indicator: `<Badge variant="outline">` with pulsing green dot (`animate-pulse`) + "Ao vivo: Xs"
- Refresh button: `<Button variant="outline" size="sm">` with `RefreshCw` icon, shows `animate-spin` while loading

### KPI Cards (Metrics)
```tsx
<div className="grid grid-cols-2 md:grid-cols-4 gap-4">
  <Card>
    <CardContent className="p-4">
      <div className="flex items-center gap-2 mb-2">
        <Icon className="h-4 w-4 text-muted-foreground" />
        <span className="text-sm text-muted-foreground">{label}</span>
      </div>
      <div className="text-3xl font-bold">{value}</div>
      <p className="text-xs text-muted-foreground mt-1">{subtitle}</p>
    </CardContent>
  </Card>
</div>
```
- Number size: `text-3xl font-bold` (ALWAYS — never smaller for primary metrics)
- Icon + label on top row: `h-4 w-4 text-muted-foreground` + `text-sm text-muted-foreground`
- Descriptive subtitle below: `text-xs text-muted-foreground mt-1`
- Grid: `grid-cols-2 md:grid-cols-4` (4 columns on desktop, 2 on mobile)
- For progress bars (SLA, Taxa de Contato): colored bar below the number using `bg-gradient-to-r` or inline width

### Operator Status Cards (Summary Row)
```tsx
<Card className="border-l-4 border-l-{color}-500/30">
  <CardContent className="p-3 flex items-center gap-3">
    <div className="w-9 h-9 rounded-lg bg-{color}-500/15 flex items-center justify-center">
      <Icon className="h-5 w-5 text-{color}-500" />
    </div>
    <div>
      <div className="text-2xl font-bold">{count}</div>
      <div className="text-xs text-muted-foreground">{label}</div>
    </div>
  </CardContent>
</Card>
```
- Left colored border: `border-l-4 border-l-{color}-500/30`
- Icon in colored circle: `w-9 h-9 rounded-lg bg-{color}-500/15` with icon `text-{color}-500`
- Colors by status: blue=Logados, green=Livres, red=Ocupados, orange=Chamando, yellow=Pausa, purple=Espera
- Grid: `grid-cols-3 md:grid-cols-6`

### Tables
```tsx
<div className="border border-border rounded-lg overflow-hidden">
  <table className="w-full text-sm">
    <thead>
      <tr className="bg-muted/50">
        <th className="px-3 py-2 text-left text-xs font-medium text-muted-foreground uppercase tracking-wider">
          {header}
        </th>
      </tr>
    </thead>
    <tbody className="divide-y divide-border">
      <tr className="hover:bg-muted/30 transition-colors">
        <td className="px-3 py-2">{value}</td>
      </tr>
    </tbody>
  </table>
</div>
```
- Header: `bg-muted/50`, text `uppercase tracking-wider text-xs font-medium text-muted-foreground`
- Body: `divide-y divide-border`, rows with `hover:bg-muted/30 transition-colors`
- Container: `border border-border rounded-lg overflow-hidden`
- Optional header badge count: `<Badge variant="secondary" className="text-xs">{count}</Badge>`

### Custom Bar Charts (Horizontal)
Instead of recharts, use CSS-based horizontal bars for simple distribution charts:
```tsx
<div className="space-y-2">
  {data.map(item => (
    <div key={item.label} className="flex items-center gap-2">
      <span className="text-xs text-muted-foreground w-12">{item.label}</span>
      <div className="flex-1 bg-muted/30 rounded-full h-5 overflow-hidden">
        <div
          className="h-full bg-primary/70 rounded-full"
          style={{ width: `${percentage}%` }}
        />
      </div>
      <span className="text-xs font-medium w-8 text-right">{item.value}</span>
    </div>
  ))}
</div>
```

### Loading State
```tsx
<main className="flex-1 flex items-center justify-center">
  <div className="text-center">
    <RefreshCw className="h-8 w-8 animate-spin text-primary mx-auto mb-2" />
    <p className="text-muted-foreground">Carregando dados...</p>
  </div>
</main>
```

### Error State
```tsx
<main className="flex-1 flex items-center justify-center">
  <Card className="max-w-md">
    <CardContent className="p-6 text-center">
      <AlertTriangle className="h-8 w-8 text-destructive mx-auto mb-2" />
      <p className="text-destructive font-medium">Erro ao carregar dados</p>
      <Button variant="outline" size="sm" onClick={refetch} className="mt-3">
        Tentar Novamente
      </Button>
    </CardContent>
  </Card>
</main>
```

### FormField Tooltips (for Management Pages)
Management/config pages use `TooltipProvider` (delayDuration=200) with `HelpCircle` icon for field descriptions:
```tsx
<TooltipProvider delayDuration={200}>
  <Tooltip>
    <TooltipTrigger asChild>
      <HelpCircle className="h-[13px] w-[13px] text-muted-foreground hover:text-blue-400 cursor-help" />
    </TooltipTrigger>
    <TooltipContent side="top" className="max-w-xs">
      <p className="text-xs">{description}</p>
    </TooltipContent>
  </Tooltip>
</TooltipProvider>
```

## Dashboard — Features

### Section Visibility Toggles
Supervisors can show/hide individual Dashboard sections via a Settings2 (gear) icon popover in the header bar. Preferences persist in `localStorage` key `dashboard-sections`.

- **Interface**: `DashboardSections` — 9 boolean fields: `kpiCards`, `operatorCards`, `queueAlert`, `retornoDetail`, `queueSummary`, `slaGauges`, `hourlyChart`, `agentPerformance`, `operationChart`
- **Default**: All sections visible (`true`)
- **Labels**: `sectionLabels` record maps each key to a user-friendly Portuguese label
- **Loader**: `loadSections()` reads from localStorage with fallback to defaults
- **UI**: `Popover` with `Checkbox` for each section, rendered in the header next to filter/refresh buttons
- **Rendering**: Each section wrapped in `{sections.xxx && (...)}` conditional

### Time Formatting Helpers
Two formatting functions in `dashboard.tsx`:
- `formatTime(seconds)` → `HH:MM:SS` — used in tables (Filas, Agentes, exports)
- `formatTimeShort(seconds)` → `MM:SS` — used in KPI cards (TME, TMA) for compact display

### Operator Status Cards
A second row of 6 compact cards below KPI cards, showing real-time operator counts from `operatorsStatus` data:
- **Logados** (blue) — total `operatorsStatus.length`
- **Livres** (green) — `status === 'LIVRE'`
- **Ocupados** (red) — `status === 'OCUPADO'`
- **Chamando** (orange) — `status === 'CHAMANDO'`
- **Em Pausa** (yellow) — `status.startsWith('PAUSA')`
- **Em Espera** (purple) — `data.em_espera` value

Grid: `grid-cols-3 md:grid-cols-6`. Only shown when `operatorsStatus` has data and `sections.operatorCards` is true.

### PDF and Excel Export
Two buttons in the Dashboard header: **PDF** (Download icon) and **Excel** (FileSpreadsheet icon). Both export only the sections currently visible (respecting `sections` toggles).

- **PDF** (`handleExportPDF`): Uses `jsPDF` (landscape) + `jspdf-autotable`. Generates color-coded tables:
  - KPI summary (blue header)
  - Queue breakdown (green header)
  - Agent performance (purple header)
  - Hourly distribution (gray header)
  - Operator status list (orange header)
  - Auto page-break when `startY > 150/170`
  - File: `dashboard-callcenter-YYYY-MM-DD.pdf`
- **Excel** (`handleExportExcel`): Uses `@/lib/xlsxShim` (ExcelJS wrapper). Generates multi-sheet workbook:
  - Sheet "Resumo KPI" — totals with merged title row
  - Sheet "Filas" — queue breakdown
  - Sheet "Agentes" — agent performance
  - Sheet "Operadores" — operator status list
  - Sheet "Por Hora" — hourly distribution
  - File: `dashboard-callcenter-YYYY-MM-DD.xlsx`
- Loading states: `isPdfGenerating`, `isExcelGenerating` — disable buttons during generation

### Status Time Alerts (Gráfico da Operação)
Supervisors can configure time-based visual alerts for operator statuses. When an operator exceeds the configured threshold, the entire table row pulses with a colored background.

- **Interface**: `StatusAlertConfig` — `enabled: boolean`, `livreMinutos: number`, `pausaMinutos: number`, `ocupadoMinutos: number`
- **Persistence**: `localStorage` key `dashboard-status-alerts` — per-browser/per-user config
- **UI**: Bell icon button in the Gráfico da Operação card header (right side). Opens a `Popover` with:
  - `Switch` to enable/disable alerts globally
  - 3 `Input` fields (type number) for LIVRE, PAUSA, OCUPADO thresholds in minutes
  - Value `0` = no alert for that status
- **Timer**: `alertNow` state updated every 1s via `setInterval` (only when `config.enabled`)
- **Alert logic**: `getAlertRowClass(status, timestampEstado, now, config)` computes elapsed time vs threshold:
  - LIVRE exceeded → `bg-green-500/20 animate-pulse`
  - OCUPADO exceeded → `bg-red-500/20 animate-pulse`
  - PAUSA exceeded → `bg-yellow-500/20 animate-pulse`
- **Row rendering**: Each `<tr>` gets `className={hover:bg-muted/30 ${rowAlert}}` — alert class overrides default with pulsing background while preserving hover
- Bell icon border turns yellow when alerts are enabled (`border-yellow-500/50 text-yellow-400`)

### Expand/Scroll Toggle (Gráfico da Operação)
The table has a toggle button to switch between a fixed-height scrollable view and a full-height expanded view showing all operators.

- **State**: `expandOperationChart` (`useState(false)`) — `false` = scroll mode (default), `true` = show all
- **UI**: `Maximize2`/`Minimize2` icon button in the card header, next to the Bell (alerts) button
- **Behavior**: When collapsed (`false`), the table wrapper has `max-h-[500px] overflow-y-auto` for scroll. When expanded (`true`), `max-h` is removed and the table grows to fit all rows.
- **Tooltip**: "Visualizar todos" (expand) / "Limitar altura (scroll)" (collapse)

## Call Center Reports

### Operator Search Filter Pattern (Standard)
All report pages that filter by operator use a **text input search** field (NOT a dropdown/select). This is the mandatory pattern:

**Frontend Pattern:**
```typescript
// State: text input, empty string default
const [searchOperator, setSearchOperator] = useState("");

// Fetch: append "search" param when non-empty
if (searchOperator.trim()) params.append("search", searchOperator.trim());

// Export/Print text: show filter applied or "Todos os Operadores"
const operatorText = searchOperator.trim()
  ? 'Filtro: ' + searchOperator.trim()
  : 'Todos os Operadores';

// UI: Input field with Enter-to-search
<div>
  <Label className="text-xs">Pesquisar Operador</Label>
  <Input
    type="text"
    placeholder="Digite o nome..."
    value={searchOperator}
    onChange={e => setSearchOperator(e.target.value)}
    onKeyDown={e => { if (e.key === 'Enter') handleGenerateReport(); }}
    className="w-48 h-9"
  />
</div>
```

**Backend Route Pattern:**
```typescript
const { queue, operator, search, page, limit, export: exportAll } = req.query;
const operatorOrSearch = (search as string)?.trim() || (operator as string);
// Pass operatorOrSearch to storage method
```

**Storage Pattern (SQL):**
```sql
-- Always use ILIKE for partial matching
AND column ILIKE '%' || $param || '%'
```

**Rules:**
- NEVER use a `<Select>` dropdown for operator filtering — always use `<Input>` text field
- NEVER use `agent-names` query to fetch operator list for dropdowns — it is no longer needed for operator filters
- The queue filter still uses a `<Select>` dropdown (loaded from `/api/reports/queue-names`)
- The queue `<Select>` onValueChange should be `setQueueName` directly (no need to reset operator on queue change)
- The `search` query param maps to ILIKE in SQL; the old `operator`/`agent` params are kept for backward compatibility but `search` takes priority
- Exception: **Abandoned calls** report (`abandoned-calls.tsx`) does NOT have operator search — it filters only by queue

**Pages using this pattern:**
- `attended-calls.tsx` — Chamadas Atendidas
- `general-operator-by-queue.tsx` — Geral por Operador (Por Fila)
- `pauses-by-operator.tsx` — Pausas por Operador
- `recordings-operators.tsx` — Gravações por Operador
- `login-logoff-synthetic.tsx` — Login/Logoff Sintético
- `login-logoff-analytical.tsx` — Login/Logoff Analítico
- `sla-by-operator.tsx` — SLA por Operador

### Relatório Geral por Operador
- **Routes**: `/general-operator` (Por Operador), `/general-operator-by-queue` (Por Fila)
- **Endpoints**: `GET /api/reports/general-operator/:startDate/:endDate`, `GET /api/reports/general-operator-by-queue/:startDate/:endDate`
- **Source**: Pre-aggregated `relatorio_operador` table + `queue_log` (login/logoff) + `pausas_operador` (pausas)
- **Filters**: Date range, queue, operator search (ILIKE text input)
- **Columns**: Operador, Atendidas, Ignoradas, Transferidas, Login, Logoff, Pausas, Tempos (total/max/med/min atendimento, logado, pausa, ocioso)
- **Exports**: Print (iframe), PDF (jsPDF+autoTable), Excel (XLSX)
- **Headers**: Blue theme (`bg-blue-700/600`), grouped (Quantidade | Tempos)
- **Transfer times**: ATTENDEDTRANSFER/BLINDTRANSFER `data4` now summed into tempo_total/max/min_atendimento via trigger

### Relatório SLA por Operador
- **Route**: `/sla-by-operator`
- **Endpoint**: `GET /api/reports/sla-by-operator/:startDate/:endDate`
- **Source**: `queue_log` CONNECT events — `data1` = wait time (seconds)
- **Filters**: Date range, queue, operator search (ILIKE text input), SLA seconds (configurable, default 20s)
- **Columns**: Operador, Total Atendidas, Dentro SLA, Fora SLA, % SLA (color-coded bar), T.Méd. Espera, T.Máx. Espera
- **Color logic**: % SLA ≥ 80% green, ≥ 60% yellow, < 60% red (both text and progress bar)
- **Exports**: Print, PDF, Excel

### Database Triggers (External PostgreSQL)

**Queue Monitoring Triggers (queue_log AFTER INSERT)** — migrated from dialplan/AGI/ODBC on 2026-03-14:
- **`trg_registros_gerais`** → `funcao_registros_gerais()`: INSERT into `registros_gerais` on ENTERQUEUE (with auto-generated protocolo DDMMYYYYHH24MISS), UPDATE on CONNECT/COMPLETE/ABANDON/etc. Previously, the initial INSERT was done via `System(psql...)` in the dialplan.
- **`trg_auto_queueid_protocolo`** → `fn_auto_queueid_protocolo()`: INSERT into `queueid` and `protocolo` tables on ENTERQUEUE, DELETE from `queueid` on finalization events. Replaces ODBC functions QUEUEID_INSERT/DELETE and PROTOCOLO_INSERT.
- **`executa_t_monitor_voxcall`** → `monitor_voxcall()`: On ENTERQUEUE inserts into `t_monitor_voxcall`, `relatorio_hora_voxcall`, `retorno_clientes`. On CONNECT updates `operador`, `hora_atendimento`, `espera`, `ramal` (from `monitor_operador` table — contains correct ramal from agent login), `protocolo` (from `protocolo` table), `canal` (external SIP channel from `canal_chamada` table). Replaces AGI script InsertMonitorAgi.php.
- **`trg_cel_captura_canal`** → `fn_cel_captura_canal()`: BEFORE INSERT on `cel` (UNLOGGED TABLE). Captures external SIP channel (`channame`) on CHAN_START event into `canal_chamada(linkedid, canal)`. Returns NULL to cancel the INSERT — `cel` table never grows (zero storage cost). `canal_chamada` is auto-cleaned after 24h via `trg_canal_chamada_cleanup`.

**Other Triggers:**
- **`trg_normaliza_transferencia`** (BEFORE INSERT on `queue_log`): Sets `data5 = 'TRANSFERENCIA'` for ATTENDEDTRANSFER/BLINDTRANSFER (Asterisk defaults `data5 = 'SAIU'`)
- **`trg_atualiza_relatorio_operador`** (AFTER INSERT on `queue_log`): UPSERT into `relatorio_operador` — counts + time metrics (data2 for COMPLETE*, data4 for transfers)
- **`trg_sync_monitor_to_queue`** (AFTER UPDATE/DELETE on `monitor_operador`): Syncs pause/logout to `queue_member_table`
- **`executa_funcao_registros_gerais_cdr`** (AFTER INSERT on `cdr`): Updates `registros_gerais` with CDR data, cleans `t_monitor_voxcall`, marks `retorno_clientes`
- **SQL reference**: `docs/sql-triggers-external-db.sql`

### Dialplan Queue Architecture (filas.conf)

After migration (2026-03-14), queue contexts in `filas.conf` are simplified:
```
[QueueContext]
exten => s,1,NoOp(#### NUMERO CHAMADOR ${CALLERID(num)} ####)
        same => n,Set(__TRANSFER_CONTEXT=TRANSFERENCIA)
        same => n,MixMonitor(/var/spool/asterisk/monitor/${CHANNEL(uniqueid)}.gsm,b)
        same => n,Playback(ligacaoGravada)
        same => n,Queue(QueueName,Tt)

exten => h,1,Set(QUEUELOG_SAIU()=${UNIQUEID})
exten => h,2,Set(VOXCALLLOG_DELETE()=${UNIQUEID})
exten => h,3,Set(OPERADOR_DATAHORA()=${MEMBERNAME})
```

**Removed from dialplan** (now handled by PostgreSQL triggers):
- `System(psql -U asterisk ...)` — registros_gerais INSERT → `trg_registros_gerais`
- `SET(QUEUEID_INSERT()=...)` / `SET(QUEUEID_DELETE()=...)` — queueid management → `trg_auto_queueid_protocolo`
- `SET(PROTOCOLO_INSERT()=...)` — protocolo table → `trg_auto_queueid_protocolo`
- `SET(DATA=${CONSULTA_DATA()})` / `SET(HORA=${CONSULTA_HORA()})` — date/time for protocolo → auto-generated in trigger
- `InsertMonitorAgi.php` (AGI) — t_monitor_voxcall update → `monitor_voxcall()` CONNECT handler
- `MONITOR_VOXCALL_DELETE()` (ODBC hangup) — t_monitor_voxcall cleanup → handled by triggers on ABANDON/COMPLETE/etc + CDR trigger

**Still in dialplan** (not migrated):
- `QUEUELOG_SAIU()` — marks queue_log data5='SAIU' (hangup tracking)
- `VOXCALLLOG_DELETE()` — cleans voxcalllog table
- `OPERADOR_DATAHORA()` — updates operator timestamp

### Discador Preditivo (Implementado — 2026-03)

**Páginas do frontend** (seção DISCADOR na sidebar, visível para administrator/superadmin):
- `/dialer-dashboard` — Dashboard com status do engine, estatísticas em tempo real
- `/dialer-campaigns` — Gerenciamento de campanhas (CRUD, fila vinculada, horários, retry rules)
- `/dialer-mailing` — Listas de discagem (upload CSV, status de registros, DNC)
- `/dialer-reports` — Relatórios do discador (abas: Resumo, Tentativas, Operadores)

**Arquivos principais**:
- `server/dialer-engine.ts` (~1400 linhas) — Motor de discagem com AMI Originate
- `client/src/pages/dialer-dashboard.tsx` — Dashboard do discador
- `client/src/pages/dialer-campaigns.tsx` — Campanhas
- `client/src/pages/dialer-mailing.tsx` — Listas de discagem
- `client/src/pages/dialer-reports.tsx` — Relatórios do discador

**Tabelas no banco LOCAL (Replit PostgreSQL)** — definidas em `shared/schema.ts`:
- `dialer_campaigns` — campanhas (nome, fila, horários, max_concurrent, retry rules)
- `dialer_mailing` — registros de discagem (phone, status, attempts, campaignId)
- `dialer_call_log` — log de cada tentativa (duration, disposition, channel)
- `dialer_stats_hourly` — estatísticas agregadas por hora
- `dialer_dnc` — lista Do Not Call (phone, reason, campaignId)

**Tabelas no banco VPS (PostgreSQL externo)** — definidas em `server/asterisk-schema.sql`:
- `dialer_queue_log` — eventos de fila filtrados do discador (populada via trigger `trg_dialer_queue_log` no `queue_log`)
- `dialer_agent_performance` — métricas agregadas por operador/campanha/dia (populada via trigger `trg_dialer_agent_performance` no `dialer_queue_log`)

**Cascade de Triggers do Discador no VPS**:
1. `queue_log` → `trg_dialer_queue_log` → `dialer_queue_log` (filtra fila `voxdial`, correlaciona CDR userfield → campaign_id)
2. `dialer_queue_log` → `trg_dialer_agent_performance` → `dialer_agent_performance` (UPSERT agent/campaign_id/stat_date; CONNECT/COMPLETEAGENT/COMPLETECALLER/RINGNOANSWER)

**Integração com VPS**:
- Chamadas originadas via AMI → geram eventos queue_log (ENTERQUEUE, CONNECT, COMPLETE) → triggers VPS preenchem `t_monitor_voxcall` + `dialer_queue_log` + `dialer_agent_performance` automaticamente
- `monitor_operador` consultado para verificar disponibilidade de operadores
- Relatório de Operadores do Discador usa `dialer_agent_performance` (primário) ou `dialer_queue_log` (fallback) — NÃO usa AMI
- O campo `canal` em `t_monitor_voxcall` é populado pela trigger `monitor_voxcall()` no CONNECT, que lê de `canal_chamada` (alimentada pela trigger CEL `fn_cel_captura_canal` em CHAN_START). Ver seção "Habilitar CEL para captura de canal externo" na skill `asterisk-callcenter-expert` para os configs `cel.conf` / `cel_pgsql.conf` que habilitam o pipeline.

**API endpoints** (role: administrator/superadmin):
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/dialer/engine/status` | Status do engine (running, stats) |
| POST | `/api/dialer/engine/start` | Iniciar engine |
| POST | `/api/dialer/engine/stop` | Parar engine |
| GET | `/api/dialer/queues` | Listar filas Asterisk |
| GET | `/api/dialer/triggers-status` | Status das triggers do discador |
| GET | `/api/dialer/dnc` | Listar DNC |
| POST | `/api/dialer/dnc` | Adicionar DNC |
| DELETE | `/api/dialer/dnc/:id` | Remover DNC |
| GET | `/api/dialer/reports/agent-performance` | Relatório de operadores (startDate, endDate, campaignId) |
| GET | `/api/dialer/reports/summary` | Resumo geral do discador |
| GET | `/api/dialer/reports/attempts` | Relatório de tentativas |

### Roteamento Asterisk por campanha (Implementado — 2026-04, Super Admin)

Por padrão, `originateCall()` em `server/dialer-engine.ts` envia AMI Originate com `Application: Queue` + `Data: <queueName>,tT,,,30` — chamada cai direto na fila assim que o cliente atende. Para casos como AMD (detecção de URA), mensagem inicial ou roteamento condicional, cada campanha pode opcionalmente ser configurada para ir primeiro a um exten do dialplan, que decide quando entregar à fila.

**Schema novo em `dialer_campaigns`** (aditivo, default mantém comportamento atual):
- `originate_mode` text NOT NULL DEFAULT 'queue' — `'queue'` ou `'dialplan'`
- `dialplan_context` text NULL — ex: `AMD_COBRANCA`
- `dialplan_exten` text NULL — ex: `9991`
- `dialplan_variables` jsonb NULL — `{"CAMPO1": "{{cpf}}", "CAMPO2": "{{nome}}"}`

**Originate quando `originate_mode='dialplan'`**:
```
Channel:  LOCAL/<DDD+phone>@MANAGER/n
Context:  <dialplan_context>
Exten:    <dialplan_exten>
Priority: 1
Variable: CDR(userfield)=DISCADOR,DIALER_*=...,CAMPO1=<resolvido>,CAMPO2=<resolvido>
```
O dialplan então roda `AMD()`, branch `HUMAN`/`MACHINE`, e só cai em `Queue(...)` quando for humano.

**Placeholders disponíveis em `dialplanVariables`** (resolvidos pelo `resolveDialplanVariables()` em `dialer-engine.ts`):
- `{{nome}}`, `{{name}}` — record.name
- `{{cpf}}`, `{{codcli}}`, `{{cod_cli}}` — record.codCli
- `{{foco_id}}`, `{{foco}}` — record.focoId
- `{{ddd}}` — record.ddd
- `{{phone}}`, `{{telefone}}` — record.phone
- `{{full_phone}}` — DDD+phone
- `{{mailing_id}}` — record.id
- Qualquer chave (lowercase) presente em `record.extraData`

**UI**: aba colapsável "Roteamento Asterisk" no modal de criar/editar campanha em `client/src/pages/dialer-campaigns.tsx`, **renderizada APENAS** quando `useAuth().user.role === 'superadmin'`. Inclui radio queue/dialplan, inputs Context/Exten, lista key/value de variáveis com botão "+", e preview do Originate.

**Defesas de segurança (CRÍTICO — AMI protocol injection)**:
1. **Zod backend** em `shared/schema.ts` `insertDialerCampaignSchema`:
   - `originateMode`: enum `["queue", "dialplan"]`
   - `dialplanContext`/`dialplanExten`: regex `^[A-Za-z0-9_-]{1,64}$`
   - `dialplanVariables`: keys via `^[A-Za-z_][A-Za-z0-9_()]{0,63}$`, values sem `\r\n`, máx 500 chars
   - `superRefine`: se mode=dialplan, context+exten obrigatórios
2. **Guard server-side** em `server/routes.ts` `stripDialplanFieldsIfNotSuperAdmin()`: nas rotas POST/PUT `/api/dialer/campaigns`, se `req.user.role !== 'superadmin'`, os 4 campos são removidos do body antes do parse — impossibilita escalation por API direta.
3. **Defesa em profundidade no engine** `sanitizeAmiToken()`: re-aplica regex `^[A-Za-z0-9_-]{1,64}$` em `dialplanContext`/`dialplanExten` antes de escrever no socket AMI; aborta o originate se algo passou.
4. **`escapeAmiVarValue()`**: remove `\r\n,` dos values e trunca a 200 chars antes de juntar via `,`.

**Padrão para futuras adições no AMI Originate**: NUNCA passe valor de input do usuário direto pra `Context`/`Exten`/`Channel` sem sanitização. AMI é protocolo line-based — `\r\n` em qualquer field permite injetar `Action: Hangup` ou outros comandos.

### Bugs corrigidos (2026-03-26/27)

- `isRecordRetryReady()`: bloqueava registros com attempts=0 e lastAttemptAt preenchido — corrigido para só verificar intervalo quando attempts > 0
- Timezone: usar `Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo' })` para comparações de data
- Registros órfãos: `recoverStaleDialingRecords()` no startup reseta registros travados em `dialing`
- UNIQUE index faltando em `relatorio_operador(data, operador, fila)` na VPS — causava ROLLBACK de toda a cascade de triggers
- Relatório de Operadores: removida captura AMI (operatorRamal/operatorName), substituída por trigger PostgreSQL `trg_dialer_agent_performance`

**Pipeline CEL → canal_chamada → t_monitor_voxcall.canal**:
- Tabela `cel` no PG do extdb DEVE ser `UNLOGGED` (a trigger BEFORE INSERT `trg_cel_captura_canal` retorna NULL, então `cel` nunca cresce — armazenamento zero). Validar com:
  ```sql
  SELECT relpersistence FROM pg_class WHERE relname='cel';  -- deve retornar 'u' (UNLOGGED)
  ```
- Se `cel` estiver como `'p'` (PERMANENT), fazer `DROP TABLE cel CASCADE` e recriar conforme `server/asterisk-schema.sql:984-1006` + reaplicar a trigger `trg_cel_captura_canal`.
- Configurar `cel.conf` + backend (`cel_pgsql.conf` ou `cel_odbc.conf`) no Asterisk apontando para o mesmo PG do extdb. Ver skill `asterisk-callcenter-expert` seção "Habilitar CEL para captura de canal externo".

**Lookup de protocolo no CONNECT (corrigido 2026-04-18)**: A função `monitor_voxcall()` busca protocolo em `protocolo` table. A tabela pode ter 2 rows com mesmo `callid`: um placeholder vazio + o valor real `DDMMYYYYHHMMSS` gerado por `fn_auto_queueid_protocolo`. O SELECT precisa filtrar `protocolo IS NOT NULL AND protocolo <> ''` com `ORDER BY protocolo DESC LIMIT 1` para garantir que pega o não-vazio. Ver `server/asterisk-schema.sql:407-413`.

### Report UI Conventions
- Headers: `bg-blue-700` (group row), `bg-blue-600` (column row), white text
- Tooltips on all column headers (Radix `TooltipProvider`, `max-w-[320px]`)
- Pagination: 10 records/page, Primeira/Anterior/Próxima/Última buttons
- Export buttons: Imprimir, PDF, Excel (right-aligned, only shown when data loaded)
- Enter key on search/filter inputs triggers report generation
- All time values formatted as HH:MM:SS via `formatSeconds()`
- Toast duration: 1000ms

### Report Assistant UI (`report-assistant.tsx`)
- **Layout**: Resizable sidebar (200-500px, drag handle on right border) + main content area
- **Sidebar**: Collapsible via PanelLeftClose/PanelLeftOpen toggle. Contains: Nova Conversa button, Sugestões Rápidas (quick action chips), Histórico (conversation list with individual delete buttons + "Limpar" bulk delete)
- **Templates header**: Collapsible via "Ocultar/Mostrar Templates" toggle. Shows 9 categories with expandable template grids
- **Fullscreen mode**: Maximize2/Minimize2 toggle — uses `fixed inset-0 z-50` to overlay entire viewport, wider content area (max-w-7xl vs max-w-5xl)
- **Messages area**: Plain `div` with `overflow-y-auto` (NOT ScrollArea — Radix ScrollArea breaks programmatic scrollTo). Auto-scrolls on new messages with `setTimeout + scrollTo({ behavior: 'smooth' })`
- **Export buttons on ALL reports**: CSV, PDF, Print always shown when `msg.data.rows && msg.data.columns` (both template and custom query results)
- **PDF export**: Opens new window with styled HTML (blue headers, zebra rows, landscape @page, VoxCALL branding), auto-triggers print dialog after 300ms
- **Delete conversation**: Individual lixeira icon always visible (opacity-based, not hidden). Bulk "Limpar" with sequential API calls + error handling + toast feedback

### Report Export Rule (CRITICAL)
- Export (PDF/Excel/Print) calls the **same** backend query as display — NEVER use a simplified/hardcoded query for exports.
- Frontend sends `?export=all` to skip pagination; the storage method must use the **exact same SQL** with computed columns (e.g., `retorno` via CDR lookup) regardless of whether pagination is applied.
- Pattern: `storage.getXxxReport(startDate, endDate, queue, agent)` without `limit`/`offset` → same query, no `LIMIT` clause.

## Ramais PBX (Real-Time Extension Monitor)

### Architecture
- **Page**: `client/src/pages/ramais-pbx.tsx` at route `/ramais-pbx`
- **Sidebar**: PAINEL PRINCIPAL section, below Dashboard
- **Endpoint**: `GET /api/ari/extensions-status` in `server/routes.ts`
- **Data source**: 100% ARI (no database) — `/ari/endpoints` + `/ari/channels`

### Status Logic
| Condition | Status | Color |
|-----------|--------|-------|
| Endpoint offline | Offline | Gray |
| Online, no active channel | Livre | Green |
| Online, channel state "Up" | Ocupado | Red |
| Online, channel state "Ringing" | Chamando | Yellow |

### Timer Pattern (Shared with Dashboard)
- Server-side `ramalStatusCache` in `routes.ts` records `Date.now()` when status changes per ramal
- Sends `timestamp_estado` to frontend
- Frontend `LiveClock` computes `Date.now() - timestamp_estado` locally (same clock = no timezone mismatch)
- DO NOT use ARI `creationtime` for elapsed time (Asterisk server may have different timezone from browser)
- Asterisk container is configured with `TZ=America/Sao_Paulo` and `/etc/localtime` symlink (Asterisk reads `/etc/localtime`, NOT TZ env var)

### UI Features
- Grid: responsive 1-5 columns
- Cards: color-coded border/icon per status, shows caller number when busy
- Filter badges: Todos/Ocupados/Chamando/Livres/Offline (combinable clicks)
- Search field with clear button (X)
- Only 2-4 digit numeric extensions shown (regex `/^\d{2,4}$/`)
- Sorted ascending by ramal number
- Polling: React Query `refetchInterval: 5000`
- Summary badges at top with counts per status

### Key Rules
- Filter only numeric 2-4 digit extensions (excludes trunks, non-extension accounts)
- `ramalStatusCache` persists across polls — only updates timestamp when status actually changes

## AI Conversational Agent (Assistente IA)

### Architecture
- **Page**: `client/src/pages/agent-chat.tsx` at route `/agent-chat`
- **Backend**: `server/agent.ts` (processAgentChat), `server/openai.ts` (OpenAI client)
- **Model**: GPT-5.2 via Replit AI Integrations (`AI_INTEGRATIONS_OPENAI_BASE_URL` + `AI_INTEGRATIONS_OPENAI_API_KEY`)
- **Knowledge Base**: `server/knowledge-base.json` (~96 entries)

### Knowledge Base Flow
1. User message received → search KB entries by keyword matching (score = matched keywords count)
2. Score ≥ 6 → return direct answer from KB (zero LLM tokens, badge "Base local" green)
3. Score ≥ 4 → inject KB context into system prompt, then call LLM
4. Score < 4 → normal LLM call

### Action Detection (KB Bypass)
- `ACTION_VERBS` (derruba, pausar, deslogar, etc.) → always bypass KB (needs LLM tool execution)
- `QUERY_VERBS` (lista, mostra, verifica) → only bypass KB if text also contains `\b\d{3,5}\b` (specific ramal number)

### Tool System (13 tools)
- **ARI tools**: hangup_channel, list_active_channels, spy/whisper_channel, pause/unpause/logout_operator, get_endpoint_details
- **DB tools**: query_operator_status, list_queues, query_queue_stats
- **SSH tools**: execute_asterisk_cli, execute_linux_command (with dangerous command blocking)

### Caching
- In-memory tool result cache with TTL (1-5 min per tool type)
- Cached facts injected into system prompt as "MEMÓRIA ATUAL"
- "Atualizar dados" button force-clears cache
- History limited to last 20 messages (token savings)

### Persistence
- Conversation history in `agentConversations` table (local PostgreSQL)
- Endpoints: `POST /api/agent/chat`, `POST /api/agent/clear-cache`, `GET/DELETE /api/agent/conversations`

### Scope Restriction
- Only answers Asterisk/Linux/VoxCALL topics
- Rejects off-topic questions to save tokens

## VPS Deployment & Docker

### Deploy Assistant (UI)
- **Page**: `client/src/pages/deploy-assistant.tsx` at route `/deploy-vps`
- **Sidebar**: ADMINISTRADOR section, `superadminOnly: true`, icon Rocket
- **Docker Generator**: `server/dockerGenerator.ts` — generates Dockerfile, docker-compose.yml, nginx.conf, .env
- **Backend Routes**: `POST /api/admin/ssh/deploy/{action}` in `server/routes.ts`, all protected with `requireAuth`
- **SSH Execution**: `executeDeployCommand()` with configurable timeout (up to 600s for builds)
- **SFTP Upload**: `uploadFileViaSftp()` for source code upload
- **File Transfer**: Base64 encoding via `writeFileB64()` to prevent shell injection

**7 Deploy Steps:**
1. Verificar VPS — OS, recursos, Docker, porta 443
2. Instalar Docker — Docker Engine + Compose
3. Gerar Arquivos — Dockerfile, compose, nginx, .env (via base64 SSH)
4. Upload Source — tar + SFTP upload do código fonte
5. Build & Deploy — `docker compose up -d --build`
6. Verificar Status — `docker compose ps`
7. Certificado SSL — Let's Encrypt HTTPS via certbot

**Dual-Mode Nginx:** `docker` (3 containers: app+db+nginx) vs `existing` (2 containers: app+db, app on localhost)

**Docker Resource Priority:** No CPU/memory hard limits — containers access 100% of VPS resources dynamically. Priority via `oom_score_adj`:
- `voxcall-asterisk`: -1000 (protected), `voxcall-asterisk-db`: -900, `voxcall-db`: -500, `voxcall-app`: 300 (first killed)
- `shm_size`: 512mb (Asterisk DB), 256mb (VoxCALL DB); `ulimits` nofile/nproc=65536 (Asterisk)
- NEVER add `mem_limit`/`cpus`/`deploy.resources.limits` — see `deploy-assistant-vps` skill for full documentation

### Replication Assistant (UI)
- **Page**: `client/src/pages/replication-assistant.tsx` at route `/replication-assistant`
- **Sidebar**: ADMINISTRADOR section, `superadminOnly: true`, icon DatabaseZap
- **Backend Routes**: `POST /api/admin/replication/{action}` in `server/routes.ts`, protected with `requireAuth` + `requireRole(["superadmin"])`
- **Config Files**: Reads `db-config.json` (primary) and `db-replica-config.json` (replica) for connection details
- **Connection**: Direct PostgreSQL connections via `pg.Client` (NOT SSH — connects directly to databases)
- **Terminal**: Same UX pattern as Deploy Assistant (colored output lines, auto-scroll, line counter, clear button)

**5 Replication Steps:**
1. Verificar Primário — wal_level, version, publications, replication users
2. Verificar Réplica — version, subscriptions, tables
3. Configurar Primário — `ALTER SYSTEM SET wal_level = logical`, create replication user + PUBLICATION (requires PG restart)
4. Configurar Réplica — `CREATE SUBSCRIPTION` pointing to primary (copy_data=true)
5. Verificar Status — pg_stat_replication + pg_stat_subscription + lag

**Management Section:**
- Quick status indicator (active/inactive with lag info)
- "Status Detalhado" button (runs step 5)
- "Parar Replicação" button (drops subscription + publication)
- Configurable: replication user/password, tables to replicate (checkboxes + custom input)

**Settings Integration:**
- Settings page shows "Replicação Ativa" or "Sem Replicação" badge on replica card
- Link "Abrir Assistente de Replicação" in the replica settings card
- `GET /api/admin/replication/quick-status` returns `{ active, lag, tables }` (lightweight, polled every 60s)

**Automatic Replica Usage:**
- `withReplicaPg()` in routes.ts: used by dashboard, callcenter, operator status, CDR, reports
- `createReplicaDbConnection()` in storage.ts: used by all storage read methods
- Both fall back to primary if replica is unavailable or fails

**Container Management (Deploy):** Status, Logs, Restart, Stop buttons
**SSL:** Let's Encrypt via certbot (webroot mode), separate button with domain + email

### Backup & Restore (`client/src/pages/backup.tsx`)
- **Page**: `client/src/pages/backup.tsx` at route `/backup`
- **Sidebar**: ADMINISTRADOR section, icon Archive
- **Backend**: `server/backup-scheduler.ts` (cron scheduling), backup endpoints in `server/routes.ts`
- **Config File**: `backup-schedule.json` (scheduler config, persisted on server)

**SSH Configuration (integrated):**
- Collapsible SSH config card at top of page (same fields as Deploy VPS: Host, Port, User, Password)
- Save via `PUT /api/ssh/config` → persists to `ssh-config.json`
- Test via `POST /api/ssh/test` → saves + runs test command on VPS
- Auto-loads saved config on page mount via `GET /api/ssh/config` (password masked as `********`)
- When SSH is configured: shows green badge with host:port, card collapsed by default
- When not configured: shows yellow badge, card expanded for initial setup
- Credentials persist across page navigation (saved server-side in `ssh-config.json`)

**Backup Operations (all use saved SSH config — no creds sent in request body):**
- `POST /api/admin/docker-backup/create` — creates full backup (Asterisk configs + PostgreSQL dump + recordings)
- `POST /api/admin/docker-backup/list` — lists backups in `/opt/voxcall/backups/`
- `POST /api/admin/docker-backup/delete` — removes backup directory
- `POST /api/admin/docker-backup/restore` — restores configs, database, recordings into Docker containers
- `POST /api/admin/docker-backup/download` — packs + streams backup as .tar.gz via SFTP
- `POST /api/admin/docker-backup/upload` — receives .tar.gz via multer, uploads via SFTP, extracts on VPS
- All endpoints: `requireAuth` + `requireRole(["superadmin"])`
- All use `extractSshConfig(req.body) || loadSshConfigForDeploy()` fallback pattern
- Upload: strict filename sanitization (`path.basename` + regex `[^a-zA-Z0-9._-]` + must end `.tar.gz`)
- Backup name validation: regex `^backup_[\d-T]+$`

**Backup Scheduler (`server/backup-scheduler.ts`):**
- `node-cron` based scheduling, timezone `America/Sao_Paulo`
- Configurable: frequency (daily/weekly/monthly), time, day of week/month
- Retention policy: auto-remove old backups exceeding max count
- Execution history: last 50 runs stored in `backup-schedule.json`
- `isRunning` flag protected by `try/finally` to always reset
- Retention uses quoted paths with strict regex validation for security
- Endpoints: `GET/PUT /api/admin/backup-schedule`, `POST /api/admin/backup-schedule/run-now`
- Initialized at server startup via `initBackupScheduler()` in `registerRoutes()`

**UI Layout (3-column grid):**
- Left (col-span-2): Backup list with per-item Download, Restore, Delete buttons + AlertDialog confirmations
- Right: Scheduling card (enable/disable, frequency, time, retention) + Status & History card
- Header: Upload Backup + Criar Backup buttons (only shown when SSH is configured)

**IMPORTANT — Deploy Assistant cleanup:**
- Backup/scheduling sections were REMOVED from `deploy-assistant.tsx` — they exist ONLY in `/backup`
- Deploy Assistant no longer has: backup state variables, backup functions, scheduling UI, AlertDialogs for backup
- Deploy Assistant retains: SSH connection fields (local state only, NOT persisted), deploy steps, container management, Asterisk Docker management, terminal

### Default Admin Credentials
- **Email**: `admin@voxtel.biz`
- **Password**: `RiCa$0808`
- **User ID**: `admin-manual`
- Configurable via `SUPERADMIN_EMAIL` and `SUPERADMIN_PASSWORD` environment variables
- Created automatically by `init-default-data.js` when no admin users exist in the database
- Admin login redirect: after successful login, redirects to `/users` (admin panel), NOT `/` (softphone)
- Default credential detection: `server/routes.ts` compares login against `process.env.SUPERADMIN_EMAIL`/`SUPERADMIN_PASSWORD` (not hardcoded) and sets `mustChangePassword` flag
- **Security**: Never log passwords in plaintext — `init-default-data.js` only logs email, not password

### HTTPS / SSL (Required for WebRTC)
WebRTC requires HTTPS for microphone access and media streams. All VPS deployments MUST use HTTPS.

**Certificate setup on VPS:**
1. Install certbot: `apt-get install -y certbot`
2. Generate certificate: `certbot certonly --webroot -w /var/lib/letsencrypt -d DOMAIN --non-interactive --agree-tos --email admin@voxtel.biz`
3. Certificates stored at `/etc/letsencrypt/live/DOMAIN/` on the host
4. Mounted read-only into nginx container: `/etc/letsencrypt:/etc/letsencrypt:ro`
5. Auto-renewal handled by certbot systemd timer

**Nginx HTTPS config pattern:**
```nginx
server {
    listen 80;
    server_name DOMAIN;
    location /.well-known/acme-challenge/ { root /var/lib/letsencrypt; }
    location / { return 301 https://$host$request_uri; }
}
server {
    listen 443 ssl http2;
    server_name DOMAIN;
    ssl_certificate /etc/letsencrypt/live/DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options SAMEORIGIN always;
    location / {
        proxy_pass http://app:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
}
```

### Docker Compose Architecture — Dual Mode

**Mode 1: Docker Nginx** (`nginxMode: 'docker'`) — for fresh VPS with no web server on port 443
- Three containers: voxfone-app (Node.js, port 5000), voxfone-db (PostgreSQL 16), voxfone-nginx (nginx:alpine, ports 80/443)
- Certificate mount (NOT Docker volumes): `/etc/letsencrypt:/etc/letsencrypt:ro`, `/var/lib/letsencrypt:/var/lib/letsencrypt:ro`
- SSL via certbot webroot at `/var/lib/letsencrypt`

**Mode 2: Existing Nginx** (`nginxMode: 'existing'`) — for VPS with Nginx/Apache already on port 443
- Two containers: voxfone-app (Node.js, exposed on `127.0.0.1:appPort`), voxfone-db (PostgreSQL 16)
- No nginx container; app binds to `127.0.0.1:PORT` only (not exposed externally)
- Site config generated by `generateNginxSiteConf()` and installed at `/etc/nginx/sites-available/DOMAIN`
- Symlink to `/etc/nginx/sites-enabled/` + `nginx -t && systemctl reload nginx`
- proxy_pass points to `http://127.0.0.1:PORT` (host network, not Docker network)
- SSL via certbot webroot at `/var/www/html`

**Port 443 auto-detection:**
- `checkPort443` command runs `ss -tlnp | grep :443` + checks for nginx/apache on host
- Frontend parses output: `PORTA_443_LIVRE` = free, otherwise occupied
- If occupied, UI auto-selects "existing" mode and shows yellow badge with service name

**SSL route:** `POST /api/admin/ssh/deploy/install-ssl` `{ domain, email, nginxMode }`
- Docker mode: `certbot certonly --webroot -w /var/lib/letsencrypt` + restarts nginx container
- Existing mode: `certbot certonly --webroot -w /var/www/html` + reloads host nginx

### Docker Generator (`server/dockerGenerator.ts`)
Generates deployment files:
- `generateDockerfile()` — Node.js 20-alpine single-stage build with FFmpeg (`RUN apk add --no-cache ffmpeg`)
- `generateDockerCompose(config)` — 3-container setup with HTTPS nginx (Docker mode)
- `generateDockerComposeNoNginx(config)` — 2-container setup, app on `127.0.0.1:PORT` (Existing mode)
- `generateNginxConf(domain)` — HTTPS nginx config for Docker container
- `generateNginxSiteConf(domain, appPort)` — nginx site config for host nginx (proxy_pass to localhost)
- `generateEnvFile(config)` — production environment variables
- `getDeployCommands()` — predefined SSH commands including `checkPort443`, `generateSslCertDocker()`, `generateSslCertHost()`, `installNginxSite()`
- `generateAsteriskDockerfile()` — Multi-stage Asterisk 22 build with ODBC, PJSIP, codecs
- `generateAsteriskDockerCompose(config)` — Asterisk + PostgreSQL with `/etc/letsencrypt` volume mount
- `generateAsteriskDeployScript(projectDir, config)` — Full deploy script with auto SSL cert detection, `http.conf` config, PJSIP external IP update, post-deploy WSS verification
- `sanitizeForShell()`, `sanitizeDomainForShell()`, `sanitizeIpForShell()` — Defense-in-depth input sanitization for shell script generation

**Template string rules for nginx variables:**
- `$host`, `$request_uri`, `$http_upgrade`, `$remote_addr` etc. do NOT need escaping in JS template strings (no `{` after `$`)
- Only escape `${...}` when it conflicts with JS template interpolation
- WRONG: `\\$host` (produces literal `\$host`)
- CORRECT: `$host` (produces `$host`)

### Deploy Assistant (`client/src/pages/DeployAssistant.tsx`)
Admin page at `/admin/deploy` with 6-step guided flow:
1. Check VPS (OS, resources, Docker installed)
2. Install Docker (if needed)
3. Generate files (Dockerfile, docker-compose.yml, nginx.conf, .env)
4. Upload source code (base64 file transfer via SSH)
5. Build & Deploy (`docker compose up -d --build`)
6. Verify status (container health)

Plus interactive SSH terminal for manual commands (with height-constrained scroll, line counter, and "Limpar" button).

**Update existing deployment (code changes only):**
When only code changed (no infrastructure/config changes), run only:
- Step 4 — Upload source code
- Step 5 — Build & Deploy
Steps 1-3 and 6 are NOT needed for simple code updates.

**Full deploy (first time or infra changes):**
Run all 6 steps in order.

**Key patterns:**
- Protected by `deploy_vps` permission via `requireDeployPermission` middleware
- SSH execution: `storage.executeSshCommand(configId, command)` returns `{ success, stdout, stderr, exitCode }`
- File transfer: base64 encoding to prevent heredoc injection (`echo 'BASE64' | base64 -d > filepath`)
- Input sanitization: domain/ports validated before use in SSH commands
- Deploy routes: `POST /api/admin/ssh/deploy/*` (check-requirements, install-docker, generate-files, build-and-start, status, logs, stop, restart)

### Dockerfile Runtime Stage
The Dockerfile runtime stage MUST use `npm ci` (NOT `npm ci --omit=dev`) because `server/vite.ts` imports vite at the module top-level. The esbuild bundler uses `--packages=external`, so vite must be available at runtime.

### `server/replitAuth.ts` in Docker
When `REPLIT_DOMAINS` is not set, the auth module logs a warning instead of throwing an error. This prevents the app from crashing in Docker environments. `REPLIT_DOMAINS` must be set in docker-compose.yml environment to the deployment domain.

### Data Sync (Replit → VPS)
When deploying, data from the Replit database should be synced to the VPS database:
- Admin user (users table)
- SIP configurations
- Database credentials (external Asterisk DB)
- SSH configurations
- Asterisk configurations (recording URL)
- Extension users and passwords

Use `docker exec voxfone-db psql -U voxfone -d voxfone -c "SQL"` to run queries on VPS database.

### VPS Database Password
The PostgreSQL password in docker-compose.yml must match the actual database user password. If they diverge (e.g., after regenerating docker-compose.yml), fix with:
```bash
docker exec voxfone-db psql -U voxfone -d voxfone -c "ALTER USER voxfone WITH PASSWORD 'new_password';"
```

## Agent Panel (Painel do Agente)

### Architecture
- **Files**: `client/src/pages/agent-panel.tsx`, `client/src/pages/agent-login.tsx`, `client/src/hooks/useAgentAuth.ts`
- **Auth**: Separate session `req.session.agentSession` (`{id, operador, ramal, script, sipExtension?, sipPassword?}`), middleware `requireAgentAuth`
- **Theme**: Supports light/dark mode via `ThemeProvider` (`client/src/contexts/theme-context.tsx`). Default is dark. Toggle button (Sun/Moon icon) in the tabs bar next to Chat tab. All structural colors use CSS variables (`bg-background`, `bg-card`, `bg-secondary`, `text-foreground`, `text-muted-foreground`, `border-border`, etc.) — NOT hardcoded grays. Status colors (green/red/yellow/blue) remain hardcoded as they are semantic. Admin sidebar also has theme toggle at bottom
- **Welcome bar**: Top bar shows "Bem-vindo(a), {operador}" (left) and `LiveClock` component with full date + time updating every second (right)
- **Login validations**: (1) Checks password, (2) Checks if ramal is in use by another operator in `monitor_operador` — returns 409 with operator name if so, (3) Cancels any pending auto-logout timer for the operator
- **Login SIP credential hydration**: On login, `POST /api/agent/login` queries `agentes_tela` including `sip_ramal`/`sip_senha` columns. If saved credentials exist, they are loaded into the session (`sipExtension`/`sipPassword`), enabling auto-registration of the softphone without reconfiguration.
- **Login ARI confirmation**: After successful login, fire-and-forget ARI Originate to `await buildEndpoint(ramal)` (resolves to `PJSIP/{ramal}` or `SIP/{ramal}` based on toggle) with extension `*13891` context `MANAGER` plays `agent-loginok` audio to confirm correct ramal
- **Channel tech toggle (PJSIP vs SIP)**: All endpoint construction MUST use `await buildEndpoint(ramal)` from `server/asterisk-config.ts` — NEVER hardcode `` `PJSIP/${ramal}` `` or `` `SIP/${ramal}` ``. The helper reads the persisted config at `<configDir>/asterisk-config.json` (default `PJSIP`, 30s versioned cache, configurable via Settings UI / `PUT /api/asterisk/channel-tech` superadmin only). Affects: queue_member_table inserts (login + ring-then-sleep), supervisão (spy/whisper), Originate (dial), bulk extension endpoints, `/api/ari/extensions-status` (filter, regex, technology field). When adding any new code that talks to Asterisk endpoints, use `buildEndpoint(ramal)` and remember that it returns `Promise<string>` — must be awaited.
- **Logout cache clear**: `logoutAgent()` in `useAgentAuth.ts` calls `queryClient.clear()` to wipe all React Query cache, ensuring fresh data (especially `timestamp_estado` for timer) on next login
- **Copy-to-clipboard**: Telefone, Cód.Gravação, and Protocolo fields in the status table are clickable when they have a value — copies to clipboard with toast feedback ("Telefone copiado!" etc.). Cursor changes to pointer and text highlights blue on hover
- **Change password**: KeyRound button in bottom bar opens Dialog with current/new/confirm password fields, show/hide toggles. `POST /api/agent/change-password` reads from REPLICA, writes to PRIMARY `agentes_tela`
- **Consult-cancel (Retornar Consulta)**: PhoneIncoming button (emerald green) between Consultar and Desligar. `POST /api/agent/consult-cancel` finds the `Local/...;1` channel in the operator's ARI bridge and does AMI `Hangup` on it — this cancels the Atxfer consultation and Asterisk seamlessly returns the operator to the original client without re-ringing the operator's extension. Important: do NOT hangup the operator's PJSIP channel (that causes re-ring)
- **Transfer/Hangup cleanup**: Both `POST /api/agent/transfer` and `POST /api/agent/hangup` fire-and-forget `DELETE FROM t_monitor_voxcall WHERE ramal = $1` via `withExternalPg` after the main action to prevent stale dashboard data. **`POST /api/agent/transfer-satisfacao` (Pesquisa de Satisfação) intentionally does NOT delete** — the Postgres trigger `trg_enriquece_pesquisa_satisfacao` reads that row to enrich the survey insert.
- **CRITICAL — Blind transfer channel discovery (do NOT use `t_monitor_voxcall.canal` for AMI Redirect)**: For dialer-originated calls (`Originate Local/{phone}@MANAGER` + `Application=Queue`), the channel name stored in `t_monitor_voxcall.canal` is `Local/...;1` — the **internal Local Channel side pointing back into the dialer's Manager dialplan**, NOT the external client trunk. Doing `AMI Redirect` on that side leaves the customer leg orphaned and the call drops. **Always discover the real client channel via ARI** using the helper `findClientChannelForRamal(ramal)` in `server/routes.ts` (defined ~line 2351): it lists `/channels` + `/bridges`, finds the operator channel (`PJSIP/{ramal}-...` state=Up), gets the bridge peer; if peer is a Local channel (`;1`/`;2`) it walks to the sibling (replace `;1`↔`;2`), gets the peer in the sibling's bridge, repeats up to depth 4, and returns the first non-Local channel (the actual PJSIP/SIP/IAX trunk leg of the customer). Both `POST /api/agent/transfer` and `POST /api/agent/transfer-satisfacao` use this helper.

### Tabs
| Tab | Description |
|-----|-------------|
| Cadastro | Client registration form |
| Ligações Atendidas | Attended calls today (queue_log COMPLETEAGENT/COMPLETECALLER by operator) |
| Ligações Abandonadas | Abandoned calls today (queue_log ABANDON by operator's queues via `queue_member_table_tela`) |
| VoxPhone | Full WebRTC softphone (SIP.js) with sub-tabs: Telefone + Configurações |
| Gravações | Call recordings with audio player, date range + phone filters |

### Call List Tabs Pattern (Attended, Abandoned, Recordings)
All three tabs follow the same pattern:
- **No auto-load**: Data only loads when user clicks "Pesquisar" button
- **Manual fetch**: `useState` + `fetch()` (NOT react-query) — consistent with VoxCALL report pages
- **Pagination**: 10 records per page, buttons: Primeiro/Anterior/[X/Y]/Próxima/Último
- **Backend response**: `{ records: [], total: number }` with `?page=X&limit=10`
- **Clickable phone numbers**: Cyan colored, triggers `dialMutation.mutate(telefone)` via ARI Originate
- **Queue filtering**: Abandoned + Recordings use `queue_member_table_tela` to find operator's queues

### Recordings Tab Specifics
- **Endpoint**: `GET /api/agent/calls/recordings?page=&limit=&startDate=&endDate=&phone=`
- **Filters**: Date range (with `[color-scheme:dark]` for native calendar icon), phone number
- **Audio**: `AgentAudioPlayer` component (dark-themed, embedded in agent-panel.tsx)
  - Play/Pause/Stop, Seek bar, Skip ±5s, Speed (0.5x-2x), Volume/Mute, Download
  - Uses `/api/cdr/audio/:uniqueid` with blob approach + auth headers
  - Only one active player at a time (`activeAudio` state)
- **Columns**: Horário, Telefone (clickable), Fila, Duração, Desconectado (OPERADOR/CLIENTE badge), Gravação
- **Query**: DISTINCT ON (callid) from queue_log + cdr, filtered by operator's queues + date range + phone

### VoxPhone Tab (Embedded Softphone)
The VoxPhone tab provides a full WebRTC softphone inside the agent panel, reusing the existing `SipContext` (`useSip()` hook). It has two internal sub-tabs:

**Sub-tab "Telefone"** (default):
- Dial pad (3x4 grid: 1-9, *, 0, #) with DTMF support during active calls
- Number input with backspace/clear buttons
- Registration status indicator (green=Registrado, yellow=Conectando, red=Desconectado) with colored dot
- Badge showing current ramal when registered
- Incoming call card: green pulsing icon, caller number, Answer/Reject buttons
- Connected call card: timer (`formatTime`), remote number, Mute/Hangup buttons
- Ringing card: yellow bouncing icon, number, Hangup button
- Auto-answer toggle (`Switch` component) with `sip.setAutoAnswer`
- When disconnected: shows "Configurar Ramal" button linking to config sub-tab

**Sub-tab "Configurações"**:
- Ramal input + Senha input (with show/hide toggle via Eye/EyeOff icons)
- "Salvar e Registrar" button: saves credentials via `POST /api/agent/sip-credentials` (persisted to `agentes_tela.sip_ramal/sip_senha` in DB), fetches global config via `GET /api/agent/sip-config`, then calls `sip.register()` with merged config
- If already registered with same ramal, shows "Ramal já está registrado" and switches to Telefone
- If changing ramal, calls `sip.unregister()` first, waits 1s, then re-registers
- Shows success/error messages below the button

**Auto-registration on load**:
- `useEffect` fetches saved credentials (`GET /api/agent/sip-credentials`) and global config (`GET /api/agent/sip-config`)
- Credentials are persisted in `agentes_tela.sip_ramal/sip_senha` — survive logout/login cycles. On login, `POST /api/agent/login` loads them into session automatically.
- If credentials exist AND SIP is not already registered/connecting, calls `sip.register()` automatically
- Guarded by `sipConfigLoaded` flag to run only once

**Incoming Call Alert System** (works outside VoxPhone tab):
- **Floating draggable card**: Shows when `callStatus === "incoming"` AND operator is NOT on VoxPhone tab OR is in PAUSA status. Card is 220px wide, green bg, draggable (pointer events), with Answer/Reject buttons and "Ir para VoxPhone" link
- **Browser Notification API**: Requests permission on mount. Shows `Notification("Chamada Recebida - VoxCALL")` when tab is hidden during incoming call. Auto-dismisses on tab focus
- **Title bar flashing**: Alternates browser tab title between "☎ Chamada Recebida! - {number}" and original title every 800ms during incoming calls
- **Ringtone**: Web Audio API oscillator at 425Hz (Brazilian telephony standard) with cadence pattern: 2 bursts of 0.4s on / 0.2s off, then 4s silence, repeating. Properly cleaned up (oscillator stop + AudioContext close) when call ends
- **Visibility change handler**: Shows/hides browser notification based on `document.visibilitychange` event

**SIP Context wrapping**: `AgentPanel` is wrapped with `<SipProvider>` in `App.tsx` (separate from admin's SipProvider)

**Double registration prevention**:
- Auto-load skips registration if `sip.isRegistered || sip.isConnecting`
- "Salvar e Registrar" checks if already registered with same extension
- SipContext suppresses "REGISTER request already in progress" errors (treated as non-error)

### Audio Auth
The `/api/cdr/audio/:uniqueid` endpoint accepts BOTH user sessions (`req.session.user`) AND agent sessions (`req.session.agentSession`). This allows recordings to be played from both the admin reports and the agent panel.

### Agent Panel Endpoints
| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/api/agent/calls/attended` | agentAuth | Attended calls today, paginated (page/limit) |
| GET | `/api/agent/calls/abandoned` | agentAuth | Abandoned calls today (by operator's queues), paginated |
| GET | `/api/agent/calls/recordings` | agentAuth | Recordings with date range/phone filter, paginated |
| POST | `/api/agent/dial` | agentAuth | ARI Originate call (context: MANAGER) |
| POST | `/api/agent/answer` | agentAuth | ARI answer ringing channel |
| POST | `/api/agent/hangup` | agentAuth | ARI DELETE channel + fire-and-forget DELETE from `t_monitor_voxcall` |
| POST | `/api/agent/transfer` | agentAuth | Blind transfer — `findClientChannelForRamal(ramal)` (ARI) + AMI `Redirect` to `Context: MANAGER` + fire-and-forget DELETE from `t_monitor_voxcall`. Does NOT use `t_monitor_voxcall.canal` (would drop dialer calls) |
| POST | `/api/agent/transfer-satisfacao` | agentAuth | Blind transfer to `*100@MANAGER` (Pesquisa de Satisfação URA) — same `findClientChannelForRamal` helper. Does NOT delete from `t_monitor_voxcall` (trigger `trg_enriquece_pesquisa_satisfacao` needs the row) |
| POST | `/api/agent/consult` | agentAuth | AMI Atxfer (attended transfer) |
| POST | `/api/agent/consult-cancel` | agentAuth | Cancel Atxfer consultation — finds Local channel in operator's bridge via ARI, AMI Hangup on it |
| POST | `/api/agent/change-password` | agentAuth | Change operator password (reads REPLICA, writes PRIMARY `agentes_tela`) |
| GET | `/api/agent/sip-config` | agentAuth | Global SIP config from `sip-webrtc-config.json` (sipServer, wssPort, STUN/TURN, enabled) |
| GET | `/api/agent/sip-credentials` | agentAuth | Per-operator SIP credentials — reads from session first, falls back to `agentes_tela.sip_ramal/sip_senha` via REPLICA DB and hydrates session |
| POST | `/api/agent/sip-credentials` | agentAuth | Save per-operator SIP credentials to session AND persists to `agentes_tela` table via PRIMARY DB (`UPDATE agentes_tela SET sip_ramal, sip_senha WHERE nome`) |
| GET | `/api/agent/script` | agentAuth | Script linked to operator's campaign (matches `scripts_atendimento.nome` with `agentSession.script`) |

### Scripts de Atendimento (Supervisor)
| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/api/scripts/init-table` | admin/superadmin | Creates `scripts_atendimento` table in external DB |
| GET | `/api/scripts` | supervisor+ | List all scripts (optional `?tipo=` and `?ativo=` filters) |
| GET | `/api/scripts/:id` | supervisor+ | Get script by ID |
| POST | `/api/scripts` | supervisor+ | Create new script |
| PUT | `/api/scripts/:id` | supervisor+ | Update script |
| DELETE | `/api/scripts/:id` | supervisor+ | Delete script |

**Table `scripts_atendimento`** (external PostgreSQL):
- `id` SERIAL PK, `nome` VARCHAR(100) UNIQUE, `tipo` VARCHAR(50), `saudacao` TEXT, `identificacao` TEXT, `desenvolvimento` TEXT, `objecoes` TEXT, `fechamento` TEXT, `observacoes` TEXT, `ativo` BOOLEAN, `criado_em` TIMESTAMP, `atualizado_em` TIMESTAMP

**Script ↔ Campaign Link**: The `nome` field in `scripts_atendimento` must match the `tipo` value from `agentes_tela` (which the operator selects as "Script" during login). The agent panel fetches the script by matching `agentSession.script` with `scripts_atendimento.nome`.

**Supervisor Page** (`/scripts-management`): CRUD interface with table listing, modal form with 6 structured sections (Saudação, Identificação, Desenvolvimento, Objeções, Fechamento, Observações), type filter, search, init table button.

**Agent Panel Script Tab**: Collapsible accordion sections with color-coded icons. Only shows sections that have content. Fetches on panel load via `GET /api/agent/script`.

### Tipos de Pausas (Supervisor)
| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/api/pause-types` | requireAuth | List all pause types from `pausas` table |
| POST | `/api/pause-types` | supervisor+ | Create new pause type (duplicate name validation, case-insensitive) |
| PUT | `/api/pause-types/:id` | supervisor+ | Update pause type name |
| DELETE | `/api/pause-types/:id` | supervisor+ | Delete pause type |

**Table `pausas`** (external PostgreSQL):
- `id` NUMERIC, `pausa` TEXT
- No auto-increment sequence — ID generated via `MAX(id)+1` on insert

**Integration with Operator Panel**: The existing `GET /api/agent/pause-reasons` endpoint reads from `pausas` table (`SELECT pausa FROM pausas ORDER BY pausa`). When pause types are created/edited/deleted via the management page, the operator's pause dropdown is updated automatically (cache invalidation on both `/api/pause-types` and `/api/agent/pause-reasons` query keys).

**Supervisor Page** (`/pause-types`): CRUD interface with table listing (ID, Name, Actions), search filter, create/edit dialog, delete confirmation. Located in sidebar under "Membros das Filas" in SUPERVISOR section.

### Chat Interno (Real-time Messaging)
| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/api/chat/contacts` | chatAuth | List contacts with last message, unread count, online status |
| GET | `/api/chat/messages/:recipientId` | chatAuth | Message history with recipient (paginated, 50/page) |
| PUT | `/api/chat/messages/read/:senderId` | chatAuth | Mark all messages from sender as read |
| POST | `/api/chat/upload` | chatAuth | Upload file attachment (max 10MB, Multer) |
| GET | `/api/chat/uploads/:filename` | public | Serve uploaded file |
| GET | `/api/chat/unread-count` | chatAuth | Total unread message count |

**Table `chat_messages`** (local PostgreSQL via Drizzle ORM):
- `id` VARCHAR PK (UUID), `senderId`, `senderName`, `senderRole`, `receiverId`, `receiverName`, `receiverRole`, `content` TEXT, `messageType` (text/file), `fileName`, `fileUrl`, `fileSize`, `fileMimeType`, `isRead` BOOLEAN, `createdAt` TIMESTAMP

**Socket.IO Events** (path `/socket.io`, auth via shared express-session):
- `send_message` → saves to DB, emits `new_message` to sender + receiver
- `typing` / `stop_typing` → emits `user_typing` / `user_stop_typing` to receiver
- `mark_read` → updates DB, emits `messages_read` to sender
- `update_status` → updates online user status, broadcasts `presence_update`
- `presence_update` → broadcast of all online users with status

**Auth**: `requireChatAuth` accepts both admin sessions (X-Admin-Session header or cookie) and agent sessions. Agent IDs are prefixed with `agent-` to avoid collision with admin UUIDs.

**Global ChatProvider** (`client/src/contexts/ChatContext.tsx`):
- Wraps `AdminLayout` in `App.tsx` — Socket.IO connects automatically on admin login (user appears online immediately)
- Tracks `unreadCount`, `onlineUsers`, `connected`, `chatActiveRef`
- `chatActiveRef` (MutableRefObject<boolean>) — set `true` by `internal-chat.tsx` on mount, `false` on unmount; suppresses badge increment when admin is viewing chat
- TopBar (`client/src/components/top-bar.tsx`) shows MessageCircle icon with animated red badge (unread count); click navigates to `/internal-chat`
- `internal-chat.tsx` reuses global socket from ChatProvider (no duplicate connection)

**Agent Panel Chat** (`client/src/pages/agent-panel.tsx`):
- Agent panel has "Chat" tab with unread badge on tab header
- Uses refs (`chatSelectedRef`, `chatActiveTabRef`, `chatMyIdRef`) to avoid stale closures in Socket.IO `new_message` listener
- When chat tab is active AND a contact is selected: incoming messages auto-mark as read (no badge increment), calls `PUT /api/chat/messages/read/:senderId` + emits `mark_read`
- When chat tab is NOT active or different contact selected: increments `chatUnreadTotal` + updates per-contact `unreadCount`
- `selectChatContact` resets unread for that contact, marks messages read via API + socket
- `loadChatContacts` (30s polling) respects active chat: if chat tab is open with a contact selected, forces that contact's `unreadCount = 0` before computing total
- Switching to chat tab auto-triggers mark-read for currently selected contact

**Auto-logout on Disconnect** (Socket.IO `disconnect` event in `server/routes.ts`):
- When an agent's socket disconnects (browser closed, internet dropped), a 15-second grace period timer starts
- If the agent reconnects within 15s (page refresh, brief drop), the timer is canceled — no logout
- If the agent does NOT reconnect within 15s, auto-logout executes: `DELETE FROM monitor_operador WHERE operador = $1`
- `agentDisconnectTimers` Map is declared at `registerRoutes` function scope (NOT inside Socket.IO block) so both Socket.IO handlers and `POST /api/agent/login` share the same Map
- `POST /api/agent/login` cancels any pending timer for that operator via `clearTimeout` + `delete` before INSERT/UPDATE — prevents the race condition where a new login is immediately followed by a stale auto-logout timer deleting the fresh `monitor_operador` record
- Double-checks `chatOnlineUsers` before executing — if agent reconnected via different path, skips logout
- Logs `[auto-logout]` prefix for debugging

**Pages**: Admin at `/internal-chat` (sidebar "Chat Interno" in SUPERVISOR section). Agent panel has "Chat" tab with unread badge.

## Database Routing Map (Primary vs Replica)

### Connection Helpers

| Helper | Location | Connects To | Usage |
|--------|----------|-------------|-------|
| `withExternalPg(fn)` | `server/routes.ts` | PRIMARY (`db-config.json`) | All WRITE operations (INSERT/UPDATE/DELETE) |
| `withReplicaPg(fn)` | `server/routes.ts` | REPLICA (`db-replica-config.json`) → fallback to PRIMARY | READ operations (Dashboard, Operator Panel, Config listings) |
| `createCustomDbConnection()` | `server/storage.ts` | PRIMARY (`db-config.json`) pool | Reports/CDR in storage.ts methods |
| `createReplicaDbConnection()` | `server/storage.ts` | REPLICA pool → fallback to `createCustomDbConnection()` | Currently unused (all storage.ts reports use `createCustomDbConnection`) |

**Rule**: All writes go to PRIMARY. Dashboard/Operator Panel reads go to REPLICA. Reports/CDR reads go to PRIMARY (via storage.ts).

### Routing by Screen/Feature

#### Dashboard (`/dashboard`)
| Endpoint | Connection | Operation | Tables |
|----------|------------|-----------|--------|
| `GET /api/callcenter/dashboard` | REPLICA | SELECT | `t_monitor_voxcall`, `monitor_operador`, `queue_log`, `relatorio_hora_voxcall`, `relatorio_operador`, `retorno_historico` |
| `GET /api/callcenter/operators-status` | REPLICA | SELECT | `monitor_operador`, `t_monitor_voxcall` |
| `GET /api/callcenter/queues` | REPLICA | SELECT | `queue_table` |

**Dashboard "Retornadas" card**: Reads from `retorno_historico` table (COUNT WHERE DATE(data_retorno) = today) instead of queue_log CONNECT events — the previous approach incorrectly counted all answered calls as returns.

#### Operator Panel (`/agent-panel`)
| Endpoint | Connection | Operation | Tables |
|----------|------------|-----------|--------|
| `GET /api/agent/operators` | REPLICA | SELECT | `agentes_tela` |
| `GET /api/agent/campaigns` | REPLICA | SELECT | `agentes_tela` (DISTINCT tipo) |
| `POST /api/agent/login` (read agent) | REPLICA | SELECT | `agentes_tela` |
| `POST /api/agent/login` (write session) | PRIMARY | INSERT/UPDATE | `monitor_operador`, `queue_member_table` |
| `POST /api/agent/logout` | PRIMARY | DELETE | `monitor_operador` |
| `POST /api/agent/pause` | PRIMARY | UPDATE | `monitor_operador` |
| `POST /api/agent/unpause` | PRIMARY | UPDATE | `monitor_operador` |
| `GET /api/agent/status` | REPLICA | SELECT | `monitor_operador`, `t_monitor_voxcall` |
| `GET /api/agent/calls/attended` | REPLICA | SELECT | `queue_log`, `cdr` |
| `GET /api/agent/calls/abandoned` | REPLICA | SELECT | `queue_log` |
| `GET /api/agent/calls/recordings` | REPLICA | SELECT | `cdr` |
| `GET /api/agent/pause-reasons` | REPLICA | SELECT | `pausas` |
| `GET /api/agent/script` | REPLICA | SELECT | `scripts_atendimento` |
| `POST /api/agent/transfer` | PRIMARY | DELETE (fire-and-forget after Redirect) | `t_monitor_voxcall` (channel discovery via ARI, NOT DB) |
| `POST /api/agent/transfer-satisfacao` | — | (no DB write — survey trigger needs the row) | ARI+AMI only |
| `POST /api/agent/hangup` | PRIMARY | DELETE (fire-and-forget) | `t_monitor_voxcall` |
| `POST /api/agent/consult-cancel` | — | ARI list channels/bridges + AMI Hangup | (no DB, ARI+AMI only) |
| `POST /api/agent/change-password` | REPLICA+PRIMARY | SELECT + UPDATE | `agentes_tela` |
| `POST /api/agent/login` (ramal check) | REPLICA | SELECT | `monitor_operador` |
| Socket.IO auto-logout (15s timer) | PRIMARY | DELETE | `monitor_operador` |

#### Retorno (Callback) — Agent Panel
| Endpoint | Connection | Operation | Tables |
|----------|------------|-----------|--------|
| `GET /api/agent/retorno-info` | REPLICA | SELECT | `queue_retorno_config` |
| `GET /api/agent/retorno-pendentes` | REPLICA | SELECT | `retorno_clientes` |
| `POST /api/agent/retorno-discar` (reads) | REPLICA | SELECT | `monitor_operador`, `pausas_operador`, `retorno_clientes` |
| `POST /api/agent/retorno-discar` (writes) | PRIMARY | UPDATE/INSERT | `retorno_clientes`, `retorno_historico` |
| `POST /api/agent/retorno-pular` (reads) | REPLICA | SELECT | `retorno_clientes` |
| `POST /api/agent/retorno-pular` (writes) | PRIMARY | UPDATE/INSERT | `retorno_clientes`, `retorno_historico` |

#### Supervisor Actions (via Dashboard)
| Endpoint | Connection | Operation | Tables |
|----------|------------|-----------|--------|
| `POST /api/ari/channels/:ramal/pause` | PRIMARY | UPDATE | `monitor_operador` |
| `POST /api/ari/channels/:ramal/unpause` | PRIMARY | UPDATE | `monitor_operador` |
| `POST /api/ari/channels/:ramal/logout` | PRIMARY | DELETE | `monitor_operador` |

#### Queue Management (`/queues-management`)
| Endpoint | Connection | Operation | Tables |
|----------|------------|-----------|--------|
| `GET /api/queues-config` | REPLICA | SELECT | `queue_table` |
| `POST /api/queues-config` | PRIMARY | INSERT | `queue_table` |
| `PUT /api/queues-config/:name` | PRIMARY | UPDATE | `queue_table` |
| `DELETE /api/queues-config/:name` | PRIMARY | DELETE | `queue_table`, `queue_member_table_tela`, `queue_member_table` |

#### Operator Config (`/operators-management`)
| Endpoint | Connection | Operation | Tables |
|----------|------------|-----------|--------|
| `GET /api/operators-config` | REPLICA | SELECT | `agentes_tela` |
| `POST /api/operators-config` | PRIMARY | INSERT | `agentes_tela` |
| `PUT /api/operators-config/:id` | PRIMARY | UPDATE | `agentes_tela` |
| `DELETE /api/operators-config/:id` | PRIMARY | DELETE | `agentes_tela` |

#### Queue Members (`/queue-members`)
| Endpoint | Connection | Operation | Tables |
|----------|------------|-----------|--------|
| `GET /api/queue-members` | REPLICA | SELECT | `queue_member_table_tela` |
| `POST /api/queue-members` | PRIMARY | INSERT | `queue_member_table_tela` |
| `PUT /api/queue-members/:uniqueid` | PRIMARY | UPDATE | `queue_member_table_tela` |
| `DELETE /api/queue-members/:uniqueid` | PRIMARY | DELETE | `queue_member_table_tela` |

#### Retorno Config (`/retorno-config`)
| Endpoint | Connection | Operation | Tables |
|----------|------------|-----------|--------|
| `GET /api/queues-retorno-config` | REPLICA | SELECT | `queue_retorno_config` |
| `POST /api/queues-retorno-config` | PRIMARY | INSERT | `queue_retorno_config` |
| `PUT /api/queues-retorno-config/:name` | PRIMARY | UPDATE | `queue_retorno_config` |
| `DELETE /api/queues-retorno-config/:name` | PRIMARY | DELETE | `queue_retorno_config` |

#### Scripts de Atendimento (`/scripts-management`)
| Endpoint | Connection | Operation | Tables |
|----------|------------|-----------|--------|
| `GET /api/scripts` | REPLICA | SELECT | `scripts_atendimento` |
| `GET /api/scripts/:id` | REPLICA | SELECT | `scripts_atendimento` |
| `POST /api/scripts` | PRIMARY | INSERT | `scripts_atendimento` |
| `PUT /api/scripts/:id` | PRIMARY | UPDATE | `scripts_atendimento` |
| `DELETE /api/scripts/:id` | PRIMARY | DELETE | `scripts_atendimento` |
| `POST /api/scripts/init-table` | PRIMARY | CREATE TABLE | `scripts_atendimento` |

#### Tipos de Pausas (`/pause-types`)
| Endpoint | Connection | Operation | Tables |
|----------|------------|-----------|--------|
| `GET /api/pause-types` | REPLICA | SELECT | `pausas` |
| `POST /api/pause-types` | PRIMARY | INSERT | `pausas` |
| `PUT /api/pause-types/:id` | PRIMARY | UPDATE | `pausas` |
| `DELETE /api/pause-types/:id` | PRIMARY | DELETE | `pausas` |

#### Reports & CDR (via `storage.ts` — ALL use PRIMARY)
All report endpoints use `createCustomDbConnection()` in `storage.ts`, which connects directly to the PRIMARY database. This is intentional — reports need consistent, up-to-date data.

| Endpoint Pattern | Connection | Tables |
|------------------|------------|--------|
| `GET /api/cdr/records` | PRIMARY | `cdr` |
| `GET /api/cdr/operator-records` | PRIMARY | `cdr`, `queue_log` |
| `GET /api/reports/general-operator/:s/:e` | PRIMARY | `queue_log`, `relatorio_operador`, `pausas_operador` |
| `GET /api/reports/general-operator-by-queue/:s/:e` | PRIMARY | `queue_log`, `relatorio_operador`, `pausas_operador` |
| `GET /api/reports/sla-by-operator/:s/:e` | PRIMARY | `queue_log` |
| `GET /api/reports/attended-calls/:s/:e` | PRIMARY | `queue_log`, `cdr` |
| `GET /api/reports/abandoned-calls/:s/:e` | PRIMARY | `queue_log` |
| `GET /api/reports/calls-by-hour/:s/:e` | PRIMARY | `queue_log` |
| `GET /api/reports/queue-totals/:s/:e` | PRIMARY | `queue_log` |
| `GET /api/reports/pauses-by-operator/:s/:e` | PRIMARY | `queue_log` |
| `GET /api/reports/pauses-by-queue/:s/:e` | PRIMARY | `queue_log` |
| `GET /api/reports/login-logoff-*` | PRIMARY | `queue_log` |
| `GET /api/reports/service-level/:s/:e/:q` | PRIMARY | `queue_log` |
| `GET /api/reports/hold-time/:s/:e/:q` | PRIMARY | `queue_log` |
| `GET /api/reports/abandonment/:s/:e/:q` | PRIMARY | `queue_log` |
| `GET /api/reports/agent-performance/:s/:e/:q/:a` | PRIMARY | `queue_log` |
| `GET /api/reports/call-volume/:s/:e/:q` | PRIMARY | `queue_log` |
| `GET /api/reports/queue-comparison/:s/:e` | PRIMARY | `queue_log` |
| `POST /api/admin/fix-relatorio-trigger` | PRIMARY | `relatorio_operador`, triggers |
| `GET /api/admin/debug-retorno` | PRIMARY | `retorno_clientes`, `retorno_historico` |

### 14 Replicated Tables

These tables are replicated from PRIMARY to REPLICA via PostgreSQL logical replication:

| Table | Has PK? | REPLICA IDENTITY | Written By |
|-------|---------|------------------|------------|
| `cdr` | YES | DEFAULT | Asterisk |
| `queue_log` | YES | DEFAULT | Asterisk |
| `relatorio_operador` | YES | DEFAULT | Asterisk trigger |
| `relatorio_hora_voxcall` | NO | FULL (required) | Asterisk trigger |
| `monitor_operador` | NO | FULL (required) | App (login/logout/pause) |
| `pausas_operador` | YES | DEFAULT | App (pause/unpause) |
| `t_monitor_voxcall` | NO | FULL (required) | Asterisk |
| `queue_table` | NO | FULL (required) | App (queue CRUD) |
| `queue_member_table_tela` | NO | FULL (required) | App (member CRUD) |
| `agentes_tela` | NO | FULL (required) | App (operator CRUD) |
| `retorno_clientes` | NO | FULL (required) | App (retorno) |
| `retorno_historico` | YES | DEFAULT | App (retorno) |
| `queue_retorno_config` | YES | DEFAULT | App (retorno config) |
| `scripts_atendimento` | YES | DEFAULT | App (scripts CRUD) |
| `pausas` | NO | FULL (no PK) | App (pause types CRUD) |

### REPLICA IDENTITY Rules

- Tables **with PK**: Use `REPLICA IDENTITY DEFAULT` (identifies rows by PK) — no action needed
- Tables **without PK**: MUST have `REPLICA IDENTITY FULL` on BOTH primary AND replica, otherwise UPDATE/DELETE will fail with error: `cannot update table "X" because it does not have a replica identity and publishes updates`
- This error blocks the operation on the **primary** — it's not just a replication lag issue, the write itself fails
- Fix endpoint: `POST /api/admin/replication/fix-replica-identity` — applies FULL to all tables without PKs on both sides
- Fix is also applied automatically during `setup-primary` and `setup-replica` endpoints
- **IMPORTANT**: The fix endpoint reads replica config from `db-replica-config.json`. If `host=db` (Docker hostname), it only works when the app runs inside the Docker network on VPS. Running from Replit will fail with `ENOTFOUND db`

### Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `cannot update table "X" because it does not have a replica identity` | Table in publication lacks PK and REPLICA IDENTITY FULL | Run "Corrigir REPLICA IDENTITY" button on VPS (not Replit) |
| Write succeeds but replica table is empty | REPLICA IDENTITY not set on replica side | Run fix on VPS where `db` hostname resolves |
| `monitor_operador` empty after login | Auto-logout timer (15s) fired due to Socket.IO disconnect during page reload | Check `[auto-logout]` logs; ensure WebSocket reconnects within 15s |
| Reports show different data than dashboard | Expected — reports read from PRIMARY, dashboard from REPLICA | Check replication lag via Status Detalhado |
| Replica connection fails, dashboard still works | `withReplicaPg` has automatic fallback to PRIMARY | Check replica config in Settings |

## Common Gotchas

- All fetch calls get `X-Admin-Session` header automatically via `main.tsx` interceptor
- `requireAnyAuth` must check header before cookies (Replit iframe blocks cookies)
- External DB queries must always have timeout and cleanup (`client.end()`)
- GSM files need FFmpeg conversion — always provide MP3 fallback to browser
- Date filters: ensure consistent timezone handling (UTC from PostgreSQL)
- Asterisk CDR table has no `recordingFile` column — use `userfield = 'GRAVANDO'` to detect recordings
- Single active config pattern: database credentials and asterisk config both enforce one-active-at-a-time
- Deploy Assistant: see "VPS Deployment & Docker" section below for full details
- **Contexto Asterisk OBRIGATÓRIO**: SEMPRE usar `context: 'MANAGER'` em todas as ações ARI e AMI. Nunca usar `from-internal` ou outros contextos
- ChanSpy via ARI: NUNCA usar parâmetro `app` no Originate — usar `context: 'MANAGER'` + `extension: '*1369{ramal}'` via dialplan
- **ARI vs AMI**: ARI para originar/listar/desligar canais. AMI (porta 25038, TCP) para transferências (Redirect = cega, Atxfer = assistida) porque canais de call center NÃO estão em Stasis
- **AMI helper**: Função `amiAction()` em `server/routes.ts` — usa `loadAmiConfig()` para ler `ami-config.json` (fallback: host do ARI + porta 25038 + user primax). Conecta TCP, login, executa ação, logoff. Banner AMI termina com `\r\n` simples (não `\r\n\r\n`)
- **AMI config UI**: Seção na página Configurações (`settings.tsx`) logo abaixo da ARI. Campos: Host, Porta (default 25038), Usuário, Senha. Endpoints: `GET/PUT /api/ami/config` (arquivo `ami-config.json`), `POST /api/ami/test` (testa Login/Logoff via socket TCP)
- **Transfer cega**: USAR `findClientChannelForRamal(ramal)` (helper em `server/routes.ts` ~L2351) que descobre o canal real do cliente via ARI atravessando bridges + Local channel pairs (;1↔;2) + AMI `Redirect` com `Context: MANAGER`. NÃO usar a coluna `canal` da `t_monitor_voxcall` (em chamadas do dialer ela aponta para `Local/...;1` interno e o AMI `Redirect` derruba o cliente). Mesmo padrão para `/api/agent/transfer-satisfacao` (URA `*100@MANAGER`)
- **Transfer assistida (Consulta)**: Busca canal do operador via `findChannelByRamal` + AMI `Atxfer` com `Context: MANAGER` — espera, liga destino, transfere ao desligar
- SQL in routes.ts: Use string concatenation (`+`), NEVER template literals (`${}`) in large SQL queries — esbuild silently truncates class methods
- **DB Routing**: See "Database Routing Map" section above for complete PRIMARY vs REPLICA mapping per endpoint
- `withExternalPg()` helper: clears Replit PG env vars, connects to external `db-config.json`, restores env vars after. Used for ALL WRITE operations and reports
- `withReplicaPg()` helper: reads from `db-replica-config.json` (read-replica); falls back to `withExternalPg` if replica not configured or connection fails. Used for Dashboard, Operator Panel reads, and config listings
- `createCustomDbConnection()` in storage.ts: pool-based connection to PRIMARY via `db-config.json`. Used by ALL report methods in storage.ts
- `tempo_min_atendimento = 999999` means no calls — render as 0 in frontend

## Docker Management — Interactive SSH Terminal

### xterm.js Terminal
The Docker Management page (`/docker-management`) includes a real interactive SSH terminal (Tab "Terminal") powered by xterm.js and WebSocket.

**Architecture:**
- **Frontend**: xterm.js (`@xterm/xterm`, `@xterm/addon-fit`) renders a real terminal in the browser
- **Backend**: `server/ssh-terminal.ts` — WebSocket server at `/ws/terminal` that bridges browser ↔ SSH via `ssh2` library
- **Protocol flow**: Browser → WebSocket → Node.js → SSH PTY shell → VPS (or `docker exec -it container sh`)

**WebSocket Messages:**
- `{type:"init", host, port, username, password, containerName, cols, rows}` — opens SSH connection
- `{type:"input", data:"..."}` — sends keystrokes to SSH shell
- `{type:"resize", cols, rows}` — resizes PTY terminal
- Server sends `{type:"output", data:"..."}` and `{type:"status", data:"connected"|"disconnected"}`

**Container Selector:**
- "Host VPS (direto)" — runs shell directly on VPS
- Container names — runs `docker exec -it <container> /bin/sh` inside container
- "Detectar" button — fetches all running containers via `docker ps -a --format` over SSH

**Security:**
- Auth: Parses Express session cookie from WebSocket upgrade request, requires `superadmin` role
- Container name sanitization: `containerName.replace(/[^a-zA-Z0-9_.-]/g, '')` before use in `docker exec`
- Password `__use_saved__` or empty: reads from `ssh-config.json` server-side (never exposes password to frontend)

**Cleanup:**
- SSH stream close → sends disconnect status → removes from `activeSessions` Map
- WebSocket close → destroys SSH connection
- Window resize listener removed on WebSocket close (prevents leak on repeated connect/disconnect)

**Key files**: `server/ssh-terminal.ts`, `client/src/pages/docker-management.tsx`

### Multi-Server SSH Support
The Docker Management page can connect to different servers for different purposes:
- **VPS App Server** (85.209.93.135:22300): Runs `voxcall-app`, `voxcall-nginx`, `voxcall-db`
- **Asterisk Server** (boghos.voxcall.cc:22300): Runs `voxcall-asterisk`, `voxcall-asterisk-db`
- SSH credentials saved in `ssh-config.json` apply to both the Terminal tab and the Containers/CLI/Files tabs
- The "Detectar" button shows containers from whichever server the SSH credentials point to

## Asterisk PJSIP NAT Configuration (Docker)

### Common NAT/Audio Issue
When Asterisk runs in Docker (even with `network_mode: host`), audio may fail if NAT is not correctly configured. The key parameters are in `pjsip_wizard.conf` (or `pjsip.conf`) transports.

### Required Transport Configuration
Both `transport-wss` and `transport-udp-nat` MUST have `local_net` lines:
```ini
[transport-wss]
type=transport
protocol=wss
bind=0.0.0.0:8089
external_media_address=<PUBLIC_IP>
external_signaling_address=<PUBLIC_IP>
local_net=172.16.0.0/12
local_net=10.0.0.0/8
local_net=192.168.0.0/16
local_net=127.0.0.0/8
allow_reload=yes

[transport-udp-nat]
type=transport
protocol=udp
bind=0.0.0.0
external_media_address=<PUBLIC_IP>
external_signaling_address=<PUBLIC_IP>
local_net=172.16.0.0/12
local_net=10.0.0.0/8
local_net=192.168.0.0/16
local_net=127.0.0.0/8
```

**Without `local_net`**: Asterisk doesn't know which addresses are "local" vs "external", so it never substitutes `external_media_address` in SDP. Result: remote party gets Docker/VPS internal IP in SDP → RTP can't reach Asterisk → no audio.

### Required RTP Configuration
```ini
[general]
rtpstart=8000
rtpend=20000
strictrtp=no
icesupport=yes
stunaddr=74.125.250.129:19302
```
- Use STUN IPv4 IP directly (not hostname) — Docker may resolve to IPv6 which Asterisk can't use for STUN
- `strictrtp=no` prevents RTP packets from being dropped when source changes (common with NAT)

### WebRTC vs SIP Pure — Template Mismatch
**Critical diagnostic**: If a softphone has no audio, check which template the endpoint uses:
- `webrtc_template` (in `ramais_wss_pjsip.conf`) → WebRTC only: uses `transport-wss`, `webrtc=yes`, `use_avpf=yes`, DTLS-SRTP, ICE. **Only works with browser/WebRTC clients**
- `endpoint_template` (in `ramais_udp_pjsip.conf`) → SIP pure: uses `transport-udp-nat`, standard RTP. **Works with traditional SIP softphones** (Ouvirtone, Zoiper, etc.)

**Extension ranges** (current deployment on boghos.voxcall.cc):
- Ramais 2000-2xxx → `webrtc_template` (WebRTC/browser)
- Ramais 8500-8xxx, 9xxx → `endpoint_template` (SIP puro/softphone)

Using a SIP softphone with a WebRTC-configured endpoint will connect (SIP signaling works) but audio will fail (DTLS-SRTP vs plain RTP mismatch).

### Diagnostic Commands (via SSH)
```bash
# Check endpoint transport and config
docker exec voxcall-asterisk asterisk -rx "pjsip show endpoint 2000"
# Check transport local_net
docker exec voxcall-asterisk asterisk -rx "pjsip show transport transport-wss"
docker exec voxcall-asterisk asterisk -rx "pjsip show transport transport-udp-nat"
# Check RTP settings
docker exec voxcall-asterisk asterisk -rx "rtp show settings"
# Enable RTP debug during call
docker exec voxcall-asterisk asterisk -rx "rtp set debug on"
docker exec voxcall-asterisk asterisk -rx "pjsip set logger on"
# Check active channels
docker exec voxcall-asterisk asterisk -rx "core show channels verbose"
# Check contact registration
docker exec voxcall-asterisk asterisk -rx "pjsip show contacts"
```

### Writing Config Files to Docker Container
Use base64 encoding to avoid shell escaping issues:
```bash
# On VPS host, write file then docker cp into container
echo "<base64>" | base64 -d > /tmp/config.conf
docker cp /tmp/config.conf voxcall-asterisk:/etc/asterisk/config.conf
rm /tmp/config.conf
# Reload module
docker exec voxcall-asterisk asterisk -rx "module reload res_pjsip.so"
```

## Asterisk 22 Docker Deployment

The system includes a built-in Asterisk 22 Docker container generator integrated into the Deploy Assistant.

### Architecture
- **Generator**: `server/dockerGenerator.ts` — contains `generateAsteriskDockerfile()` and all config file generators
- **Backend**: `server/routes.ts` — Asterisk-specific deploy endpoints under `/api/admin/ssh/deploy/asterisk-*`
- **Frontend**: `client/src/pages/deploy-assistant.tsx` — "Asterisk 22 — Docker" card with config form + action buttons

### Dockerfile (Multi-stage)
- **Builder stage**: Debian 12 slim, compiles Asterisk 22 from source with PJSIP bundled
- **Runtime stage**: Debian 12 slim with only runtime libs + FFmpeg + Sox
- **Timezone**: `ENV TZ=America/Sao_Paulo` + `RUN ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime && echo "America/Sao_Paulo" > /etc/timezone` — **CRITICAL**: Asterisk reads `/etc/localtime`, NOT the `TZ` env var. Without the symlink, CDR timestamps are recorded in UTC causing +3h offset
- **Modules enabled**: codec_opus, format_mp3, res_ari (all sub-modules), res_pjsip, res_http_websocket, res_stasis, res_musiconhold, app_queue, app_mixmonitor, app_chanspy, app_playback, app_dial
- **Sounds/MOH**: Custom files from `modelo_asterisk/sounds/` and `modelo_asterisk/moh/` — NO internet downloads. menuselect disables MENUSELECT_CORE_SOUNDS, MENUSELECT_MOH, MENUSELECT_EXTRA_SOUNDS categories. Sounds → `/var/lib/asterisk/sounds/`, MOH → `/var/lib/asterisk/moh/` (3 subdirs: 1/, 2/, 3/). **IMPORTANT**: MOH config uses Realtime via ODBC (`extconfig.conf`: `musiconhold.conf => odbc,asterisk,music_conf`), NOT the local file. MOH classes are populated in `music_conf` table via `asterisk-schema.sql`. Classes: `default` (moh/1, 5 tracks), `moh2` (moh/2, 2 tracks), `moh3` (moh/3, 1 track)
- **Healthcheck**: `asterisk -rx "core show version"`
- **CMD**: `asterisk -fvvv` (foreground with verbose)

### docker-compose.asterisk.yml Timezone
Both Asterisk containers MUST have timezone environment variables:
```yaml
asterisk:
  environment:
    TZ: America/Sao_Paulo
asterisk-db:
  environment:
    TZ: America/Sao_Paulo
    PGTZ: America/Sao_Paulo
```
PostgreSQL also needs `timezone = 'America/Sao_Paulo'` in `postgresql.conf` and `ALTER DATABASE asterisk SET timezone = 'America/Sao_Paulo'`.

### Generated Config Files
| File | Generator Function | Purpose |
|------|-------------------|---------|
| `pjsip.conf` | `generateAsteriskPjsipConf()` | Transports (UDP, TCP, WSS), endpoint/auth/aor templates with MANAGER context |
| `http.conf` | `generateAsteriskHttpConf()` | HTTP/HTTPS server for ARI (ports 8088/8089) |
| `ari.conf` | `generateAsteriskAriConf()` | ARI user credentials |
| `manager.conf` | `generateAsteriskManagerConf()` | AMI user credentials and permissions |
| `modules.conf` | `generateAsteriskModulesConf()` | Autoload + explicit module loads, disables chan_sip |
| `extensions.conf` | `generateAsteriskExtensionsConf()` | MANAGER context with internal/external dial, agent-loginok (*13891), ChanSpy (*1369X), Whisper (*1370X), MixMonitor sub-routine |
| `rtp.conf` | `generateAsteriskRtpConf()` | RTP port range, ICE support, STUN server |
| `queues.conf` | `generateAsteriskQueuesConf()` | Queue defaults with MixMonitor |
| `voicemail.conf` | `generateAsteriskVoicemailConf()` | Voicemail defaults |
| `cdr_pgsql.conf` | `generateAsteriskCdrPgsqlConf()` | CDR PostgreSQL logging config |

### Deploy Flow
1. **Gerar e Enviar**: Creates `asterisk/` directory on VPS with Dockerfile + configs + deploy script. If Let's Encrypt cert exists for the configured domain, writes `http.conf` with correct cert paths. Otherwise falls back to self-signed cert. Also updates `pjsip_wizard.conf` with external IP for `external_media_address`/`external_signaling_address`.
2. **Build & Start**: Runs `asterisk-deploy.sh` in background (10-20 min compile time), polls logs every 20s. After build completes, automatically applies `http.conf` with Let's Encrypt cert inside the running container, runs `core reload`, and verifies WSS port 8089 is active.
3. **Container**: Runs with `--network host` (required for SIP/RTP), named volumes for configs/recordings/sounds/logs + `/etc/letsencrypt:/etc/letsencrypt:ro` (read-only mount for SSL certs)

### Automatic WebRTC/WSS Certificate Configuration
When deploying Asterisk via the Deploy Assistant, the system automatically configures SSL certificates for WebRTC:

1. **Domain from UI**: The domain field in the Deploy Assistant UI is passed to `astConfig.domain` and used for certificate detection
2. **Let's Encrypt detection**: Deploy script checks if `/etc/letsencrypt/live/<domain>/fullchain.pem` exists on the VPS
3. **http.conf auto-config**: If cert exists, generates `http.conf` with `tlscertfile=/etc/letsencrypt/live/<domain>/fullchain.pem` and `tlsprivatekey=/etc/letsencrypt/live/<domain>/privkey.pem`
4. **Volume mount**: `docker-compose.asterisk.yml` includes `/etc/letsencrypt:/etc/letsencrypt:ro` so the container can access host certs
5. **Post-deploy apply**: After the container starts, the deploy script applies the config inside the running container via `docker exec` and verifies port 8089 is listening
6. **Fallback**: If no Let's Encrypt cert exists, generates a self-signed certificate as fallback (WebRTC will show browser warnings)

**IMPORTANT**: The SSL certificate (Step 7 of VoxCALL deploy) must be installed BEFORE the Asterisk deploy for automatic WSS configuration to work. The Asterisk deploy script reads the cert from `/etc/letsencrypt/live/<domain>/` on the VPS host.

### Endpoints
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/admin/ssh/deploy/generate-asterisk` | Generate and upload Dockerfile + configs to VPS |
| POST | `/api/admin/ssh/deploy/build-asterisk` | Build image and start container (background) |
| POST | `/api/admin/ssh/deploy/asterisk-logs` | Poll build logs + status |
| POST | `/api/admin/ssh/deploy/asterisk-status` | Container status + version + endpoints + queues |
| POST | `/api/admin/ssh/deploy/asterisk-restart` | Restart container |
| POST | `/api/admin/ssh/deploy/asterisk-stop` | Stop and remove container |
| POST | `/api/admin/ssh/deploy/asterisk-cli` | Execute Asterisk CLI command in container |

### UI (Deploy Assistant)
- Orange-bordered card with Phone icon
- Config fields: ARI user/password, AMI user/password, External IP, Local Network CIDR, ports (SIP, AMI, ARI, WSS, RTP range)
- Action buttons: Gerar e Enviar (orange), Build & Start (green), Status, Reiniciar, Parar
- CLI input: Execute Asterisk commands (e.g., `core show version`, `pjsip show endpoints`) directly from the UI
- Build polling: Auto-polls logs every 20s during build with animated indicator

### Network Mode
Uses `--network host` instead of Docker port mapping because:
- SIP requires the container to see real client IPs for NAT traversal
- RTP port range (10000-20000) would require mapping 10000+ ports
- Simplifies external_media_address/external_signaling_address configuration

### Asterisk Docker Build Lessons (CRITICAL)
1. **Version URL**: Use `asterisk-22-current.tar.gz` NOT a specific version like `22.2.0` — the current URL always resolves to latest 22.x
2. **Directory detection**: Use `AST_DIR=$(ls -d asterisk-22.* | head -1)` to auto-detect extracted directory name
3. **menuselect**: Do NOT explicitly enable individual modules (res_ari, res_pjsip, app_queue, codec_opus, etc.) — they are ALL compiled automatically when dev libraries are installed. Only use menuselect for `format_mp3` (optional, with `|| true`). MUST disable sound/MOH download categories: `--disable-category MENUSELECT_CORE_SOUNDS`, `--disable-category MENUSELECT_MOH`, `--disable-category MENUSELECT_EXTRA_SOUNDS` — custom sounds come from `modelo_asterisk/sounds/` and `modelo_asterisk/moh/`
4. **app_macro**: Removed in Asterisk 21+, do NOT reference it
5. **`|| true` in Dockerfile chains**: NEVER use `|| true` mid-chain as it breaks `&&` precedence and swallows upstream errors. Only use it for isolated optional commands
6. **Multi-stage COPY**: MUST copy `/usr/lib/libasterisk*` (shared libs like libasteriskssl.so, libasteriskpj.so) in addition to `/usr/lib/asterisk/` (modules). Without these, the binary fails with exit code 127
7. **ldconfig**: MUST run `ldconfig` after copying shared libs in the final stage
8. **`set -ex`**: Always use in RUN commands for visibility and fail-fast behavior
9. **wget**: Do NOT use `-q` flag during build — show download progress for debugging

---

## VoxGuard — Multi-Source Security Agent (v2.0)

Custom Fail2Ban-like security agent for VPS. Monitors multiple log sources in real-time, blocks attacker IPs via nftables sets with auto-expiry, sends email alerts via SMTP. Supports both **Docker** and **native** Asterisk installations with auto-detection. **Only blocks external (public) IPs** — all private/internal ranges are whitelisted by default.

### Architecture
- **Python script** (`/opt/voxguard/voxguard.py`) running as systemd service on VPS **host** (NOT inside Docker)
- **nftables named sets** with `flags timeout` — kernel handles auto-expiry, O(1) lookup, handles 100K+ IPs
- **Up to 6 monitoring threads** (configurable via `log_sources`): Asterisk logs, SSH auth logs, PostgreSQL logs, Nginx logs, Docker daemon logs, maintenance loop
- **Dual mode**: Auto-detects Docker vs native Asterisk on startup
- **Stats persistence**: `/var/lib/voxguard/stats.json` saved every 60s
- **Logging**: `/var/log/voxguard.log` with 5MB rotation (3 backups)
- **VPS identity**: Emails include hostname + IP for multi-VPS environments

### Source Files
| File | Description |
|------|-------------|
| `modelo_asterisk/voxguard/voxguard.py` | Main Python agent script (v2.0) |
| `modelo_asterisk/voxguard/voxguard.conf` | JSON configuration (whitelist, thresholds, SMTP, monitoring, log_sources) |
| `modelo_asterisk/voxguard/voxguard.service` | systemd unit file |
| `modelo_asterisk/asterisk/logger.conf` | Asterisk security logging (security => security) |

### Configurable Log Sources (`log_sources` config key)
Each source can be toggled on/off independently. Disabled sources do not start monitoring threads (zero resource usage).

| Source Key | What it Monitors | Default |
|------------|-----------------|---------|
| `asterisk` | SIP probes, auth failures, SIP scanners (sipvicious) via Docker logs or native log files | `true` |
| `linux_ssh` | SSH brute force, invalid users via `/var/log/auth.log` or `journalctl` | `true` |
| `postgresql` | Auth failures, pg_hba violations, connection rejects — supports Docker containers (multi-container with `selectors` for non-blocking reads) and native log files | `false` |
| `nginx` | Vulnerability scans (phpMyAdmin, wp-admin, .env, .git, xmlrpc, etc.), web brute force (401 on login endpoints), 4xx status floods | `false` |
| `docker` | Unauthorized access to Docker daemon API | `false` |

### Attack Patterns Detected (v2.0)

**Asterisk Patterns:**
| Type | Pattern | Threshold | Ban Duration |
|------|---------|-----------|-------------|
| `sip_probe` | "No matching endpoint found" | 5 in 60s | 24h |
| `auth_fail` | ChallengeResponseFailed / InvalidPassword | 5 in 60s | 24h |
| `scanner` | sipvicious / friendly-scanner user-agent | Instant | 7 days |

**SSH Patterns:**
| Type | Pattern | Threshold | Ban Duration |
|------|---------|-----------|-------------|
| `ssh_brute` | "Failed password" / "Invalid user" / "authentication failure" | 5 in 300s | 24h |

**PostgreSQL Patterns:**
| Type | Pattern | Threshold | Ban Duration |
|------|---------|-----------|-------------|
| `pg_auth_fail` | "password authentication failed" (host=, client=, [client=], Docker format) | 5 in 300s | 24h |
| `pg_auth_fail` | "no pg_hba.conf entry" | 5 in 300s | 24h |
| `pg_auth_fail` | "connection rejected" / "role does not exist" / "database does not exist" | 5 in 300s | 24h |

**Nginx Patterns:**
| Type | Pattern | Threshold | Ban Duration |
|------|---------|-----------|-------------|
| `web_scan` | Request path contains phpMyAdmin, wp-admin, .env, .git/, xmlrpc, cgi-bin, eval(, /passwd, setup.php, .asp, /backup, etc. | 10 in 60s | 24h |
| `web_scan` | 400/403/404/444 HTTP status codes | 10 in 60s | 24h |
| `web_brute` | POST to /login, /auth, /signin, /api/auth returning 401 | 10 in 60s | 24h |

**Docker Patterns:**
| Type | Pattern | Threshold | Ban Duration |
|------|---------|-----------|-------------|
| `docker_unauth` | Unauthorized access to Docker daemon API | 3 in 300s | 24h |

**Global:**
| Type | Pattern | Threshold | Ban Duration |
|------|---------|-----------|-------------|
| Repeat offender | Blocked 3+ times | Auto | Permanent |

### Internal IP Protection (Whitelist)
VoxGuard **never blocks internal/private IPs**. Default whitelist includes:
- `127.0.0.1` — localhost
- `10.0.0.0/8` — private class A
- `172.16.0.0/12` — private class B (**covers all Docker bridge IPs**: `172.18.x.x`, `172.20.x.x`, etc.)
- `192.168.0.0/16` — private class C
- Replit IP ranges: `34.0.0.0/8`, `35.0.0.0/8`, `104.0.0.0/8`, `172.96.0.0/11`, `172.110.0.0/16`

The `is_whitelisted()` function checks every IP against these ranges before any blocking action. Container-to-container traffic is always safe.

### nftables Blocking
```bash
# Table and set created automatically by VoxGuard
nft add table inet voxguard
nft add set inet voxguard blocked '{ type ipv4_addr; flags timeout; }'
nft add chain inet voxguard input '{ type filter hook input priority -10; policy accept; }'
nft add rule inet voxguard input ip saddr @blocked counter drop

# Block with auto-expiry (done by VoxGuard)
nft add element inet voxguard blocked '{ 1.2.3.4 timeout 86400s }'

# Permanent block (repeat offenders)
nft add element inet voxguard blocked '{ 1.2.3.4 }'
```

### Dual Mode Support
VoxGuard auto-detects whether Asterisk runs in Docker or natively on startup:

| Check | Docker Mode | Native Mode |
|-------|-------------|-------------|
| Asterisk logs | `docker logs -f <container>` | `tail -F /var/log/asterisk/full` |
| Health check | `docker inspect <container>` | `systemctl is-active asterisk` |
| SSH monitoring | `/var/log/auth.log` or `journalctl` | `/var/log/auth.log` or `journalctl` |

**Detection priority** (auto mode):
1. If native `systemctl` active → native mode (even if old Docker container exists)
2. If Docker container running and no native service → docker mode
3. Fallback: check log file existence, then `which asterisk`

**Config fields for mode control**:
- `"mode"`: `"auto"` (default), `"docker"`, or `"native"` — forces a specific mode
- `"asterisk_log_path"`: custom log file path for native mode (default: auto-detect from `/var/log/asterisk/full`, `/var/log/asterisk/messages`, `/var/log/asterisk/security`)

### Configuration (`voxguard.conf`) — JSON format
```json
{
  "whitelist": ["127.0.0.1", "172.16.0.0/12", "10.0.0.0/8", "192.168.0.0/16"],
  "log_sources": {
    "asterisk": true,
    "linux_ssh": true,
    "postgresql": false,
    "nginx": false,
    "docker": false
  },
  "thresholds": {
    "sip_probe": {"count": 5, "window": 60, "ban_duration": 86400},
    "auth_fail": {"count": 5, "window": 60, "ban_duration": 86400},
    "scanner": {"ban_duration": 604800},
    "ssh_brute": {"count": 5, "window": 300, "ban_duration": 86400},
    "pg_auth_fail": {"count": 5, "window": 300, "ban_duration": 86400},
    "web_scan": {"count": 10, "window": 60, "ban_duration": 86400},
    "web_brute": {"count": 10, "window": 60, "ban_duration": 86400},
    "docker_unauth": {"count": 3, "window": 300, "ban_duration": 86400},
    "repeat_offender": {"count": 3, "ban_duration": 0}
  },
  "smtp": {
    "enabled": true, "host": "smtp.example.com", "port": 587,
    "user": "user@example.com", "password": "pass",
    "from_addr": "voxguard@voxcall.cc", "to": "admin@example.com",
    "ignore_tls": false, "alert_cooldown": 300
  },
  "monitoring": {
    "mode": "auto",
    "asterisk_container": "voxcall-asterisk",
    "asterisk_log_path": "",
    "check_interval": 30, "disk_threshold": 90, "daily_report_hour": 8
  }
}
```

### Systemd Service
- `Type=simple`, `Restart=always`, `RestartSec=10`
- `After=network.target`, `Wants=network.target` (NO Docker dependency — works on any VPS)
- `WantedBy=multi-user.target` — auto-starts on boot
- Logs to journald: `journalctl -u voxguard -f`

### Deployment
VoxGuard is deployed automatically during Asterisk build:
1. `generate-asterisk` endpoint uploads `modelo_asterisk/voxguard/` files to VPS `/opt/voxcall/voxguard/`
2. `asterisk-deploy.sh` (generated by `dockerGenerator.ts`) copies files to `/opt/voxguard/`, installs systemd service, enables and starts it
3. Can also be installed/updated independently via the `/api/admin/ssh/voxguard/install` endpoint
4. **Install endpoint auto-installs nftables** if not present on VPS (via `apt-get install -y nftables`)

### Management Page (`/voxguard`)
- SuperAdmin only (`superadminOnly: true` in sidebar)
- Requires SSH credentials (same as Docker Management page)
- **Header**: ShieldAlert icon, status badge (Ativo/Inativo/Falhou/Erro)
- **Stats Cards**: IPs Bloqueados, Ataques Hoje (24h), Total Bloqueados, Uptime
- **Tabs**:
  - **IPs Bloqueados**: Table with IP + timeout + unblock button
  - **Logs**: Terminal-style viewer with color-coded lines, auto-scroll
  - **Whitelist**: Add/remove IPs and CIDRs
  - **Configuração**: Log source toggles (Switch components for each source), email alerts config, thresholds display, monitoring settings
- **Actions**: Carregar Status, Reiniciar, Parar, Limpar Bloqueios, Instalar/Atualizar

### API Endpoints (all `superadmin` only)
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/admin/ssh/voxguard/status` | Service status + stats + blocked count |
| POST | `/api/admin/ssh/voxguard/blocked` | List blocked IPs from nftables set |
| POST | `/api/admin/ssh/voxguard/unblock` | Remove specific IP from blocked set |
| POST | `/api/admin/ssh/voxguard/unblock-all` | Flush entire blocked set |
| POST | `/api/admin/ssh/voxguard/logs` | Tail /var/log/voxguard.log |
| POST | `/api/admin/ssh/voxguard/restart` | systemctl restart voxguard |
| POST | `/api/admin/ssh/voxguard/stop` | systemctl stop voxguard |
| POST | `/api/admin/ssh/voxguard/whitelist` | Read/add/remove whitelist entries (modifies voxguard.conf) |
| POST | `/api/admin/ssh/voxguard/config` | Load/save log_sources, email, thresholds, monitoring config |
| POST | `/api/admin/ssh/voxguard/install` | Upload files + install + enable + start service |

### Email Alerts
- **Block alert**: Sent on first block per IP (cooldown 300s per IP), HTML email with IP, attack type, duration, reincidences
- **Daily report**: Sent at configured hour (default 8:00), summary of blocks, top 5 attackers, disk/memory usage
- **System alert**: Disk usage above threshold, Asterisk/container not running (cooldown 1h per alert type)
- **VPS identity in emails**: All emails include VPS hostname + IP in subject tag and HTML body (for multi-VPS identification)
- **SMTP security**: `ignore_tls=false` by default — STARTTLS is enforced. Set `ignore_tls=true` only for internal SMTP servers

### Key Implementation Rules
1. **VoxGuard runs on HOST, not inside Docker** — works with both Docker and native Asterisk
2. **Dual mode auto-detection**: Checks `systemctl` first, then Docker — native takes priority when both exist
3. **nftables sets auto-expire** — kernel handles timeout removal, no cleanup needed
4. **nftables auto-installed**: Install endpoint runs `apt-get install -y nftables` if `nft` command not found
5. **After server reboot**: systemd restarts VoxGuard automatically, nftables sets are recreated empty (attackers re-detected quickly)
6. **Service file has NO Docker dependency** — uses `After=network.target` so it starts on any VPS
7. **SSH monitoring fallback**: If `/var/log/auth.log` doesn't exist, uses `journalctl -u sshd -u ssh -f`
8. **Whitelist supports CIDR** — e.g., `10.0.0.0/8` blocks entire range from being banned; `172.16.0.0/12` covers all Docker bridge IPs
9. **Config format is JSON** (not YAML) — Python falls back to `json.loads()` if PyYAML not installed
10. **Stats saved to `/var/lib/voxguard/stats.json`** — survives restarts, loaded on startup
11. **Install endpoint uses sync fs** — must `await import('fs')` for `existsSync`/`readFileSync` (top-level `fs` is `promises` only)
12. **No hot-reload**: Config loaded once at startup. After changes (log sources, whitelist, thresholds), `systemctl restart voxguard` required
13. **PostgreSQL multi-container monitoring**: Uses Python `selectors` module for non-blocking reads across multiple `docker logs -f` processes — avoids stalling when one container is quiet
14. **Nginx patterns match request path**: Scan detection regex matches suspicious tokens in the URL path (before status code), not after — handles standard access log format correctly
