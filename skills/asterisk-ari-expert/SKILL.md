---
name: asterisk-ari-expert
description: Especialista em Asterisk REST Interface (ARI) para integração com sistemas VoIP/PABX. Use quando o usuário pedir para criar dashboards em tempo real, monitorar chamadas, gerenciar canais, bridges, filas, gravações, ou qualquer automação via ARI no Asterisk. Inclui referência completa da API REST, WebSocket, e exemplos práticos em Node.js.
---

# Especialista Asterisk ARI (Asterisk REST Interface)

Skill para desenvolvimento de funcionalidades que integram com o Asterisk via ARI, focada no projeto VoxCALL - sistema de gerenciamento de PABX.

## Quando Usar

- Criar ou atualizar dashboards de monitoramento em tempo real (chamadas ativas, filas, ramais)
- Implementar controle de chamadas (originar, transferir, desligar, colocar em espera)
- Monitorar eventos do Asterisk via WebSocket (novas chamadas, mudanças de estado, DTMF)
- Gerenciar bridges (conferências, salas de espera)
- Controlar gravações de chamadas
- Consultar status de endpoints/ramais
- Integrar dados ARI com relatórios do VoxCALL

## Contexto do Projeto VoxCALL

- **Stack**: Node.js/Express (backend) + React/TypeScript (frontend)
- **Configuração ARI**: Salva em `ari-config.json` na raiz do projeto
- **Formato do config**:
  ```json
  {
    "host": "servidor.exemplo.com",
    "port": 8088,
    "username": "usuario_ari",
    "password": "senha",
    "protocol": "http"
  }
  ```
- **Carregamento**: Ler config com `fs.readFile('ari-config.json')` antes de fazer requisições
- **Variáveis de ambiente**: Limpar PGHOST/PGPASSWORD/etc antes de conexões externas (Replit injeta variáveis do banco interno)

## REGRA OBRIGATÓRIA: Contexto MANAGER

**SEMPRE** utilize o contexto `MANAGER` ao executar ações via ARI ou AMI no Asterisk. Nunca use `from-internal` ou outros contextos.

```javascript
// ARI — Originar chamada (CORRETO)
await ariRequest('/channels', 'POST', {
  endpoint: 'PJSIP/' + ramal,
  extension: destino,
  context: 'MANAGER',  // SEMPRE MANAGER
  priority: 1
});

// AMI — Transferência cega (CORRETO)
// IMPORTANTE: NÃO usar o canal salvo em t_monitor_voxcall.canal!
// Em chamadas do dialer (Originate Local + Queue) ele aponta para
// Local/...;1 (lado interno), e o Redirect derruba o cliente.
// Sempre descobrir o canal real do cliente via ARI:
const clientChannel = await findClientChannelForRamal(ramal);
await amiAction({
  Action: 'Redirect',
  Channel: clientChannel.name,  // tronco PJSIP/SIP/IAX externo do cliente
  Exten: destino,
  Context: 'MANAGER',  // SEMPRE MANAGER
  Priority: '1'
});

// AMI — Transferência assistida (CORRETO)
await amiAction({
  Action: 'Atxfer',
  Channel: channelName,
  Exten: destino,
  Context: 'MANAGER',  // SEMPRE MANAGER
  Priority: '1'
});
```

## ARI vs AMI — Quando Usar Cada Um

### ARI (Asterisk REST Interface)
- **Usar para**: Originar chamadas, listar canais, desligar canais, consultar endpoints, ler variáveis, snoop/spy
- **Limitação**: Ações como `redirect` só funcionam em canais que estão em modo **Stasis**. Canais gerenciados pelo dialplan (chamadas normais de call center) **NÃO** estão em Stasis e retornam erro `"Channel not in Stasis application"` ao tentar redirect

### AMI (Asterisk Manager Interface)
- **Usar para**: Transferência cega (`Redirect`), transferência assistida (`Atxfer`), e qualquer ação que precise operar em canais **fora** do Stasis
- **Conexão**: TCP na porta **25038** (porta customizada, padrão seria 5038)
- **Credenciais**: Usuário `primax`, senha `primax@123`
- **Protocolo**: Texto sobre TCP — banner → login → ação → logoff

### Resumo de Uso
| Ação | Interface | Motivo |
|------|-----------|--------|
| Originar chamada | ARI | Funciona via dialplan |
| Listar canais | ARI | Consulta simples |
| Desligar canal | ARI | DELETE funciona em qualquer canal |
| Atender canal | ARI | POST answer funciona |
| Transferência cega | AMI (`Redirect`) + ARI (descoberta de canal) | Canal fora do Stasis; canal alvo descoberto via ARI bridges (`findClientChannelForRamal`) — nunca usar `t_monitor_voxcall.canal` cru |
| Transferência assistida | AMI (`Atxfer`) | Canal fora do Stasis |
| Spy/Whisper/Conference | ARI | Originate via dialplan |
| Pausar/Despausar operador | DB | Tabela monitor_operador |

## Conceitos Fundamentais do ARI

### O que é ARI
ARI (Asterisk REST Interface) é uma API RESTful + WebSocket que permite controle total sobre chamadas no Asterisk. Diferente do AMI (gerencial) e AGI (scripts por chamada), o ARI oferece controle granular de mídia e canais via HTTP.

### O que é Stasis
**Stasis** é um modo especial do Asterisk onde uma chamada fica sob controle total da aplicação externa. Canais só entram em Stasis quando o dialplan tem `Stasis(app_name)`. Chamadas normais de call center (filas, ramais) **NÃO** passam por Stasis, portanto **NÃO** aceitam `redirect` via ARI. Para essas chamadas, usar AMI.

### Arquitetura
```
[Aplicação VoxCALL] <--HTTP/REST--> [Asterisk HTTP Server :8088] <--ARI--> [Asterisk Core]
[Aplicação VoxCALL] <--WebSocket--> [Asterisk HTTP Server :8088] <--Events--> [Asterisk Core]
[Aplicação VoxCALL] <--TCP:25038--> [Asterisk AMI] <--Manager--> [Asterisk Core]
```

### Fluxo Básico ARI (Stasis)
1. Dialplan encaminha chamada para `Stasis(app_name)` 
2. Asterisk emite evento `StasisStart` via WebSocket
3. Aplicação controla o canal via API REST (atender, tocar áudio, bridge, etc.)
4. Ao finalizar, aplicação remove canal do Stasis → Asterisk continua dialplan

### Autenticação
- **HTTP Basic Auth**: `Authorization: Basic base64(username:password)`
- **Query Parameter**: `?api_key=username:password`
- Credenciais configuradas no `ari.conf` do Asterisk

### Configuração no Asterisk

**http.conf**:
```ini
[general]
enabled=yes
bindaddr=0.0.0.0
bindport=8088
```

**ari.conf**:
```ini
[general]
enabled=yes
pretty=yes

[usuario_ari]
type=user
read_only=no
password=senha_segura
```

**extensions.conf** (exemplo para Stasis):
```ini
[from-internal]
exten => _X.,1,NoOp(Chamada para ${EXTEN})
 same => n,Stasis(voxcall-app,${EXTEN})
 same => n,Hangup()
```

## Endpoints Principais da API REST

Base URL: `{protocol}://{host}:{port}/ari`

### Canais (Channels)
| Método | Endpoint | Descrição |
|--------|----------|-----------|
| GET | `/channels` | Listar canais ativos |
| GET | `/channels/{channelId}` | Detalhes de um canal |
| POST | `/channels` | Originar chamada |
| DELETE | `/channels/{channelId}` | Desligar canal |
| POST | `/channels/{channelId}/answer` | Atender canal |
| POST | `/channels/{channelId}/hold` | Colocar em espera |
| DELETE | `/channels/{channelId}/hold` | Retirar da espera |
| POST | `/channels/{channelId}/mute` | Mutar canal |
| DELETE | `/channels/{channelId}/mute` | Desmutar |
| POST | `/channels/{channelId}/redirect` | Redirecionar canal |
| POST | `/channels/{channelId}/play` | Tocar áudio |
| POST | `/channels/{channelId}/snoop` | Espionar canal |
| GET | `/channels/{channelId}/variable` | Ler variável do canal |
| POST | `/channels/{channelId}/variable` | Definir variável |

### Bridges (Conferências/Salas)
| Método | Endpoint | Descrição |
|--------|----------|-----------|
| GET | `/bridges` | Listar bridges ativos |
| POST | `/bridges` | Criar bridge |
| GET | `/bridges/{bridgeId}` | Detalhes do bridge |
| DELETE | `/bridges/{bridgeId}` | Destruir bridge |
| POST | `/bridges/{bridgeId}/addChannel` | Adicionar canal ao bridge |
| POST | `/bridges/{bridgeId}/removeChannel` | Remover canal do bridge |
| POST | `/bridges/{bridgeId}/record` | Gravar bridge |
| POST | `/bridges/{bridgeId}/play` | Tocar áudio no bridge |

### Endpoints (Ramais/Troncos)
| Método | Endpoint | Descrição |
|--------|----------|-----------|
| GET | `/endpoints` | Listar todos os endpoints |
| GET | `/endpoints/{tech}` | Listar por tecnologia (PJSIP, SIP, IAX2) |
| GET | `/endpoints/{tech}/{resource}` | Detalhes de endpoint específico |

### Gravações (Recordings)
| Método | Endpoint | Descrição |
|--------|----------|-----------|
| GET | `/recordings/stored` | Listar gravações salvas |
| GET | `/recordings/stored/{name}` | Detalhes da gravação |
| DELETE | `/recordings/stored/{name}` | Excluir gravação |
| GET | `/recordings/stored/{name}/file` | Download do arquivo |
| GET | `/recordings/live/{name}` | Gravação em andamento |
| POST | `/recordings/live/{name}/stop` | Parar gravação |
| POST | `/recordings/live/{name}/pause` | Pausar gravação |
| POST | `/recordings/live/{name}/unpause` | Retomar gravação |

### Informações do Sistema
| Método | Endpoint | Descrição |
|--------|----------|-----------|
| GET | `/asterisk/info` | Informações do sistema |
| GET | `/asterisk/modules` | Módulos carregados |
| GET | `/asterisk/variable` | Variáveis globais |
| GET | `/applications` | Aplicações Stasis registradas |

### Eventos (WebSocket)
| Conexão | Descrição |
|---------|-----------|
| `ws://{host}:{port}/ari/events?app={app}&api_key={user}:{pass}` | Stream de eventos em tempo real |

## Eventos WebSocket Importantes

| Evento | Descrição |
|--------|-----------|
| `StasisStart` | Canal entrou na aplicação Stasis |
| `StasisEnd` | Canal saiu da aplicação Stasis |
| `ChannelCreated` | Novo canal criado |
| `ChannelDestroyed` | Canal destruído |
| `ChannelStateChange` | Mudança de estado (Ring, Up, Down) |
| `ChannelDtmfReceived` | Dígito DTMF recebido |
| `ChannelHangupRequest` | Solicitação de desligamento |
| `ChannelVarset` | Variável do canal definida |
| `BridgeCreated` | Bridge criado |
| `BridgeDestroyed` | Bridge destruído |
| `ChannelEnteredBridge` | Canal entrou no bridge |
| `ChannelLeftBridge` | Canal saiu do bridge |
| `EndpointStateChange` | Mudança de estado do endpoint |
| `PeerStatusChange` | Mudança de status do peer |
| `RecordingStarted` | Gravação iniciou |
| `RecordingFinished` | Gravação finalizada |

## Implementação no VoxCALL

### Padrão para Requisições ARI no Backend

```typescript
import fs from 'fs/promises';

async function loadAriConfig() {
  try {
    const data = await fs.readFile('ari-config.json', 'utf8');
    return JSON.parse(data);
  } catch {
    return { host: '', port: 8088, username: '', password: '', protocol: 'http' };
  }
}

async function ariRequest(endpoint: string, method = 'GET', body?: any) {
  const config = await loadAriConfig();
  const url = `${config.protocol}://${config.host}:${config.port}/ari${endpoint}`;
  const auth = Buffer.from(`${config.username}:${config.password}`).toString('base64');
  
  const options: RequestInit = {
    method,
    headers: {
      'Authorization': `Basic ${auth}`,
      'Content-Type': 'application/json',
    },
  };
  
  if (body) options.body = JSON.stringify(body);
  
  const response = await fetch(url, options);
  if (!response.ok) {
    throw new Error(`ARI Error ${response.status}: ${await response.text()}`);
  }
  return response.json();
}
```

### Padrão para Requisições AMI no Backend

A função `amiAction` conecta via TCP ao AMI, faz login, executa uma ação e retorna a resposta. Usada para transferências (Redirect, Atxfer) em canais fora do Stasis.

```typescript
async function amiAction(action: Record<string, string>): Promise<Record<string, string>> {
  const config = await loadAriConfig();
  if (!config || !config.host) throw new Error('Configuração ARI/AMI não encontrada');
  const net = await import('net');
  return new Promise((resolve, reject) => {
    const socket = new net.Socket();
    const host = config.host;
    const port = 25038;
    let buffer = '';
    let step = 0;
    const timer = setTimeout(() => {
      socket.destroy();
      reject(new Error('AMI timeout'));
    }, 10000);

    socket.connect(port, host, () => {});
    socket.on('data', (data: Buffer) => {
      buffer += data.toString();
      // Step 0: Banner recebido (apenas \r\n, NÃO \r\n\r\n)
      if (step === 0 && buffer.includes('\r\n')) {
        step = 1;
        buffer = '';
        socket.write('Action: Login\r\nUsername: primax\r\nSecret: primax@123\r\n\r\n');
        return;
      }
      // Step 1: Resposta do login
      if (step === 1 && buffer.includes('Response:')) {
        if (buffer.includes('Response: Error')) {
          clearTimeout(timer);
          socket.destroy();
          reject(new Error('AMI Login failed'));
          return;
        }
        if (buffer.includes('Authentication accepted')) {
          step = 2;
          buffer = '';
          let cmd = '';
          for (const [key, val] of Object.entries(action)) {
            cmd += key + ': ' + val + '\r\n';
          }
          cmd += '\r\n';
          socket.write(cmd);
          return;
        }
      }
      // Step 2: Resposta da ação
      if (step === 2 && buffer.includes('Response:') && buffer.includes('\r\n\r\n')) {
        clearTimeout(timer);
        const blocks = buffer.split('\r\n\r\n');
        const firstBlock = blocks[0] || '';
        const lines = firstBlock.split('\r\n');
        const result: Record<string, string> = {};
        for (const line of lines) {
          const idx = line.indexOf(':');
          if (idx > 0) {
            result[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
          }
        }
        socket.write('Action: Logoff\r\n\r\n');
        socket.destroy();
        if (result['Response'] === 'Error') {
          reject(new Error('AMI Error: ' + (result['Message'] || 'Unknown')));
        } else {
          resolve(result);
        }
      }
    });
    socket.on('error', (err: any) => {
      clearTimeout(timer);
      reject(new Error('AMI connection error: ' + err.message));
    });
  });
}
```

**IMPORTANTE sobre o protocolo AMI:**
- O banner do Asterisk (`Asterisk Call Manager/X.X.X`) termina com `\r\n` simples, NÃO `\r\n\r\n`
- As respostas (login, ação) terminam com `\r\n\r\n`
- A resposta do login pode vir junto com eventos (ex: `FullyBooted`) — filtrar por `Authentication accepted`
- Sempre fazer Logoff antes de fechar o socket

### Padrão para WebSocket no Backend

```typescript
import WebSocket from 'ws';

async function connectAriWebSocket(appName: string) {
  const config = await loadAriConfig();
  const wsProtocol = config.protocol === 'https' ? 'wss' : 'ws';
  const wsUrl = `${wsProtocol}://${config.host}:${config.port}/ari/events?app=${appName}&api_key=${config.username}:${config.password}`;
  
  const ws = new WebSocket(wsUrl);
  
  ws.on('open', () => console.log('ARI WebSocket conectado'));
  ws.on('message', (data) => {
    const event = JSON.parse(data.toString());
    handleAriEvent(event);
  });
  ws.on('close', () => {
    console.log('ARI WebSocket desconectado, reconectando em 5s...');
    setTimeout(() => connectAriWebSocket(appName), 5000);
  });
  ws.on('error', (err) => console.error('ARI WebSocket erro:', err.message));
  
  return ws;
}
```

## Referências Adicionais

Para documentação detalhada da API e exemplos práticos em Node.js, consulte:
- `reference/api-reference.md` - Referência completa com parâmetros e respostas
- `reference/nodejs-examples.md` - Exemplos práticos para dashboard, monitoramento e controle de chamadas

## Painel "Gráfico da Operação" — Status em Tempo Real via ARI

### Endpoint: `GET /api/callcenter/operators-status?queue=`

Combina dados da tabela `monitor_operador` com status em tempo real do ARI para exibir o estado de cada operador no dashboard.

### Fluxo de Determinação de Status

1. Consulta `monitor_operador` (banco externo) para obter operadores logados
2. Para cada ramal, consulta ARI:
   - `GET /ari/endpoints/PJSIP/{ramal}` → verifica se o endpoint está `online` ou `offline`
   - `GET /ari/channels` → verifica canais ativos associados ao ramal
3. Determina status combinado com a seguinte prioridade:
   - ARI indisponível ou endpoint offline → **INDISPONÍVEL**
   - ARI online + `fl_pausa = 1` → **PAUSA - {tipo_pausa}**
   - ARI online + canal com state `Ringing`/`Ring` → **CHAMANDO**
   - ARI online + canal com state `Up` → **OCUPADO** (inclui telefone do caller)
   - ARI online + sem canal ativo → **LIVRE**

### Lógica de Decisão Online/Offline

```typescript
const isOnline = ariAvailable ? (epState === 'online') : hasLogin;
if (isOnline) {
  // Determinar status detalhado...
} else {
  status = 'INDISPONÍVEL';
}
```

**IMPORTANTE**: Quando o ARI está disponível, usar **somente** o estado do ARI (`epState === 'online'`) para determinar se o ramal está online. **NÃO** usar `hasLogin` como fallback junto com `isOnline` (ex: `isOnline || hasLogin`), pois isso faz ramais não autenticados no PBX aparecerem como LIVRE.

### Cache de Status e Relógio em Tempo Real

O sistema usa um **cache em memória no servidor** para rastrear mudanças de status e controlar o relógio (TEMPO) exibido no frontend:

```typescript
const operatorStatusCache: Record<string, { 
  status: string; 
  timestamp: number; 
  prevStatus?: string; 
  prevTimestamp?: number 
}> = {};
```

**Regras do relógio:**
1. **Status igual ao anterior** → mantém timestamp do cache (relógio continua contando)
2. **Status mudou** → reseta timestamp para `Date.now()` (relógio zera)
3. **Transição CHAMANDO → LIVRE** (operador não atendeu a chamada) → recupera o timestamp de quando era LIVRE **antes** do CHAMANDO, somando o tempo do CHAMANDO ao tempo LIVRE anterior
4. **Servidor reiniciou** → cache vazio, todos começam do zero

```typescript
const cached = operatorStatusCache[ramal];
let timestampEstado: number;
if (cached && cached.status === status) {
  timestampEstado = cached.timestamp;
} else if (cached && status === 'LIVRE' && cached.status === 'CHAMANDO' 
           && cached.prevStatus === 'LIVRE' && cached.prevTimestamp) {
  timestampEstado = cached.prevTimestamp;
  operatorStatusCache[ramal] = { status, timestamp: timestampEstado, prevStatus: cached.status, prevTimestamp: cached.timestamp };
} else {
  timestampEstado = nowTs;
  operatorStatusCache[ramal] = { status, timestamp: nowTs, prevStatus: cached?.status, prevTimestamp: cached?.timestamp };
}
```

### Frontend — LiveClock Component

O relógio no frontend atualiza a cada segundo via `setInterval`, calculando o tempo decorrido:

```typescript
function LiveClock({ timestampEstado, status }) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const interval = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(interval);
  }, []);
  const elapsed = now - timestampEstado;
  return <span>{formatElapsed(elapsed)}</span>; // HH:MM:SS
}
```

Os dados do endpoint são refreshed a cada 5 segundos no frontend via React Query.

### Cores por Status

| Status | Cor do texto | Cor do relógio |
|--------|-------------|----------------|
| LIVRE | text-green-400 | text-green-400 |
| OCUPADO | text-red-500 | text-red-400 |
| CHAMANDO | text-orange-400 | text-orange-400 |
| PAUSA - {tipo} | text-yellow-400 | text-yellow-400 |
| INDISPONÍVEL | text-gray-500 | text-gray-400 |

### Formatação de hora_login

O campo `hora_login` do banco é formatado no backend usando `getUTCDate/getUTCMonth/getUTCHours` etc. para formato "DD/MM/YYYY HH:MM:SS". O PostgreSQL do Asterisk armazena timestamps sem timezone (os valores representam horário de Fortaleza), e o driver `pg` os interpreta como UTC, então `getUTC*` retorna o valor correto para exibição.

### Filtro por Fila

O endpoint aceita `?queue=nome_da_fila` para filtrar operadores por fila, usando a tabela `queue_member_table_tela`:
```sql
SELECT membername FROM queue_member_table_tela WHERE queue_name = $1
```

### Batching de Requisições ARI

Para evitar sobrecarregar o ARI, os endpoints são consultados em batches de 10 ramais com `Promise.allSettled` e timeout de 3 segundos por requisição via `AbortController`.

## Boas Práticas

1. **Sempre usar reconexão automática** no WebSocket (o Asterisk pode reiniciar)
2. **Cache de configuração**: Ler `ari-config.json` uma vez e cachear, recarregando quando necessário
3. **Timeout nas requisições**: Usar AbortController com timeout de 3-10s
4. **Não expor credenciais ARI** no frontend - todas as requisições devem passar pelo backend Express
5. **Tratar estados de canal**: Ring → Up → Down (nem todo canal passa por todos os estados)
6. **Filtrar tecnologia**: Endpoints retornam PJSIP/SIP/IAX2 - filtrar conforme necessidade
7. **Monitorar filas**: Usar combinação de ARI events + consulta periódica para dados de fila
8. **Cache de status no servidor**: Usar cache em memória para detectar mudanças de status e controlar o relógio do painel de operação
9. **Transição CHAMANDO→LIVRE**: Preservar o tempo LIVRE anterior quando o operador não atende a chamada (somar tempo do CHAMANDO)

## Ações no Ramal via ARI + Dialplan (Dashboard Modal)

### Visão Geral
O dashboard tem um modal de ações que abre ao clicar no ramal na tabela "Gráfico da Operação". As ações se dividem em dois grupos:

1. **Ações via ARI Originate + Dialplan** (Monitorar, Intercalar, Conferência) — usam `POST /ari/channels` com `context` + `extension` para executar via dialplan do Asterisk
2. **Ações via DB** (Pausar, Despausar, Deslogar) — operam na tabela `monitor_operador` no PostgreSQL externo

### IMPORTANTE: NÃO usar Stasis para ChanSpy
Ao originar chamadas para ChanSpy/monitoramento, **NUNCA** use o parâmetro `app` no ARI Originate. Isso coloca o canal em modo Stasis e o ChanSpy não funciona corretamente (o canal cai ao atender).

**ERRADO** (Stasis — canal cai):
```javascript
await ariRequest('/channels', 'POST', {
  endpoint: 'PJSIP/4010',
  app: 'ChanSpy',
  appArgs: 'PJSIP/2302,q'
});
```

**CORRETO** (Dialplan — funciona):
```javascript
await ariRequest('/channels', 'POST', {
  endpoint: 'PJSIP/4010',
  extension: '*1369' + ramal,
  context: 'MANAGER',
  priority: 1
});
```

### Helpers Reutilizáveis em `server/routes.ts`

```typescript
// Carrega config ARI do arquivo
async function loadAriConfig() { /* lê ari-config.json */ }

// Faz requisição HTTP ao ARI com Basic Auth e timeout 8s
async function ariRequest(endpoint, method, body?) { /* fetch com auth */ }

// Busca canal ativo (Up/Ringing) para um ramal
async function findChannelByRamal(ramal) { /* GET /ari/channels, filtra PJSIP/{ramal} */ }
```

### Endpoints Backend — Dashboard (Admin)

| Endpoint | Ação | Implementação |
|----------|------|---------------|
| `POST /api/ari/channels/:ramal/spy` | Monitorar | ARI Originate → `*1369{ramal}` no contexto `MANAGER`. Requer `ramalSupervisor` no body. Supervisor escuta operador e cliente, ninguém escuta o supervisor. |
| `POST /api/ari/channels/:ramal/whisper` | Intercalar | ARI Originate → `*1370{ramal}` no contexto `MANAGER`. Requer `ramalSupervisor` no body. Supervisor escuta todos e fala com o operador (cliente não ouve supervisor). |
| `POST /api/ari/channels/:ramal/conference` | Conferência | ARI Originate → `*1371{ramal}` no contexto `MANAGER`. Requer `ramalSupervisor` no body. Todos se ouvem e interagem (conferência a 3). |
| `POST /api/ari/channels/:ramal/hangup` | Desligar Canal | `findChannelByRamal` + `DELETE /ari/channels/{channelId}` |
| `POST /api/ari/channels/:ramal/pause` | Pausar | `UPDATE monitor_operador SET fl_pausa=1, hora_entra_pausa=NOW(), tipo_pausa=$2 WHERE ramal=$1 AND fl_pausa=0` |
| `POST /api/ari/channels/:ramal/unpause` | Despausar | `UPDATE monitor_operador SET fl_pausa=0, hora_sai_pausa=NOW(), tipo_pausa=NULL, hora_entra_pausa=NULL WHERE ramal=$1 AND fl_pausa=1` |
| `POST /api/ari/channels/:ramal/logout` | Deslogar | `DELETE FROM monitor_operador WHERE ramal=$1` |

### Endpoints Backend — Painel do Agente (Operador)

Protegidos por `requireAgentAuth`. O ramal vem de `req.session.agentSession.ramal`.

| Endpoint | Ação | Interface | Implementação |
|----------|------|-----------|---------------|
| `POST /api/agent/dial` | Discar | ARI | ARI Originate: `POST /channels` com `endpoint: PJSIP/{ramal}`, `extension: {destino}`, `context: MANAGER`, `priority: 1` |
| `POST /api/agent/answer` | Atender | ARI | `findChannelByRamal` (estado Ringing) + `POST /channels/{channelId}/answer` |
| `POST /api/agent/transfer` | Transferência cega | ARI + AMI | `findClientChannelForRamal(ramal)` (ARI: descobre canal real do cliente atravessando bridges + Local pairs) + AMI `Redirect` com `Context: MANAGER` |
| `POST /api/agent/transfer-satisfacao` | Transferência cega para URA de Pesquisa de Satisfação | ARI + AMI | Mesma lógica de `/transfer`, mas extension=`*100` e NÃO remove linha de `t_monitor_voxcall` (trigger `trg_enriquece_pesquisa_satisfacao` precisa) |
| `POST /api/agent/consult` | Transferência assistida | AMI | `findChannelByRamal` para achar canal do operador + AMI `Atxfer` com `Context: MANAGER`. Coloca chamada em espera, liga para destino, transfere quando operador desliga |
| `POST /api/agent/hangup` | Desligar | ARI | `findChannelByRamal` + `DELETE /channels/{channelId}` |
| `GET /api/agent/calls/attended` | Atendidas hoje | DB | queue_log COMPLETEAGENT/COMPLETECALLER por operador, paginado (page/limit) |
| `GET /api/agent/calls/abandoned` | Abandonadas hoje | DB | queue_log ABANDON pelas filas do operador (via queue_member_table_tela), paginado |
| `GET /api/agent/calls/recordings` | Gravações | DB | queue_log + cdr pelas filas do operador, com filtros startDate/endDate/phone, paginado |

**Clickable phone numbers**: Nos tabs Atendidas/Abandonadas/Gravações, o telefone é clicável e dispara `POST /api/agent/dial` (ARI Originate).

**Audio auth**: `/api/cdr/audio/:uniqueid` aceita tanto sessão de usuário quanto sessão de agente (`req.session.agentSession`).

**Diferença entre Transfer e Consult:**
- **Transfer (Redirect)**: Transferência cega — redireciona o canal **externo do cliente** direto para o destino. O operador sai da chamada imediatamente. **CRÍTICO**: o canal alvo deve ser descoberto via ARI (`findClientChannelForRamal`), NUNCA usar a coluna `canal` da `t_monitor_voxcall` cru — em chamadas do dialer (Originate Local + Queue) ela aponta para `Local/...;1` (lado interno do canal Local que conecta de volta no Manager dialplan), e o `Redirect` nesse lado deixa o cliente órfão e a chamada cai.
- **Consult (Atxfer)**: Transferência assistida — usa o canal do operador (PJSIP/ramal). O Asterisk coloca a chamada original em espera, liga para o destino, e quando o operador desliga, a chamada original é conectada ao destino.

### Helper `findClientChannelForRamal(ramal)` — Descoberta do canal real do cliente

Definida em `server/routes.ts` (~L2351). Padrão obrigatório para qualquer transferência cega no VoxCALL. Algoritmo:

1. Busca em paralelo `GET /channels` e `GET /bridges` via ARI.
2. Localiza o canal do operador: `ch.name` casa com `^(PJSIP|SIP|IAX2)/{ramal}-` e `state === 'Up'`.
3. Procura o bridge que contém o `id` desse canal e pega o **peer** (o outro `channel id` na lista do bridge).
4. Se o peer for `Local/...;1` ou `Local/...;2`, troca `;1`↔`;2` para achar o "irmão" Local channel, busca o bridge dele, pega o peer desse irmão, e repete (até profundidade 4 — guarda contra loops em dialplans muito complexos).
5. Retorna o primeiro canal **não-Local** encontrado (o tronco PJSIP/SIP/IAX externo do cliente). Se a cadeia terminar em Local channel, retorna `null` (chamada possivelmente meio-transferida ou mal-formada).

**Por que esse padrão é necessário no dialer**: o `Originate Local/{phone}@MANAGER` + `Application=Queue` cria duas pontes. Bridge A: operador (`PJSIP/100`) ↔ `Local/{phone}@MANAGER-XXX;2` (lado Queue). Bridge B: `Local/{phone}@MANAGER-XXX;1` (lado Manager) ↔ tronco externo do cliente (`PJSIP/trunk-YYY`). Para achar o tronco do cliente partindo do operador, é necessário atravessar do Bridge A para o Bridge B através do par Local.

**Comparação com `consult-cancel`** (`server/routes.ts` ~L8624): aquele endpoint procura especificamente o `Local/...;1` dentro do bridge do operador para fazer Hangup nele (cancelar Atxfer e voltar ao cliente original) — propósito diferente, lógica intencionalmente diferente. Use `findClientChannelForRamal` para `transfer`/`transfer-satisfacao`, e a busca de Local;1 in-bridge para `consult-cancel`.

### Dialplan Asterisk — Contexto [MANAGER]

```ini
; Monitorar — supervisor apenas escuta (spy silencioso)
exten => _*1369X.,1,Answer()
    same => n,ChanSpy(PJSIP/${EXTEN:5},q)
    same => n,Hangup()

; Intercalar — supervisor escuta e fala com operador (whisper)
exten => _*1370X.,1,Answer()
    same => n,ChanSpy(PJSIP/${EXTEN:5},qw)
    same => n,Hangup()

; Conferência — todos se ouvem (barge)
exten => _*1371X.,1,Answer()
    same => n,ChanSpy(PJSIP/${EXTEN:5},qB)
    same => n,Hangup()
```

### Flags do ChanSpy

| Flag | Descrição |
|------|-----------|
| `q` | Silencioso — sem bip ao entrar na escuta |
| `w` | Whisper — supervisor fala com o operador, cliente NÃO ouve |
| `B` | Barge — conferência a 3, todos se ouvem e interagem |

### Frontend — Modal de Ações (`dashboard.tsx`)

- **Trigger**: Clique no número do ramal na tabela (cursor pointer, hover azul)
- **Estado**: `selectedOperator`, `actionModalOpen`, `actionLoading`, `confirmAction`, `supervisorPrompt`, `ramalSupervisor`
- **Botões linha 1** (3 colunas): Monitorar (Headphones), Intercalar (PhoneForwarded), Conferência (Users) — só habilitados se status=OCUPADO
- **Botões linha 2** (3 colunas): Desligar Canal, Pausar, Despausar
- **Botões linha 3**: Deslogar (vermelho)
- **Supervisor input**: Monitorar/Intercalar/Conferência abrem um segundo Dialog pedindo o ramal do supervisor (só números, Enter confirma, Escape cancela)
- **AlertDialog**: Para ações destrutivas (Desligar Canal, Deslogar) com confirmação
- **Status live**: `currentOperator` busca status atualizado do `operatorsStatus` query (refetch 5s) para habilitar/desabilitar botões em tempo real
- **Toast**: Feedback de 1s para sucesso, 2s para erro

### Tabela `monitor_operador` (PostgreSQL externo)

| Coluna | Tipo | Uso nas ações |
|--------|------|---------------|
| ramal | text | WHERE clause para todas as ações DB |
| fl_pausa | smallint | 0=ativo, 1=pausado |
| tipo_pausa | text | Tipo da pausa (default 'PAUSA') |
| hora_entra_pausa | timestamp | Set on pause, cleared on unpause |
| hora_sai_pausa | timestamp | Set on unpause, cleared on pause |

## Skills Relacionadas

- **diagnostic-assistant-expert**: Para manutenção do Assistente de Diagnóstico (base de conhecimento, ferramentas, prompts, modelo GPT-4.1)
- **asterisk-callcenter-expert**: Para relatórios de call center, KPIs, queries de queue_log e CDR
- **voxfone-telephony-crm**: Para features do CRM (softphone, CDR reports, extensões, agendas, auth)
- **deploy-assistant-vps**: Para deploy em VPS via Docker Compose, nginx, SSL
