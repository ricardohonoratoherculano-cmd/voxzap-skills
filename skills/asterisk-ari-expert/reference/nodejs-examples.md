# Exemplos Práticos Node.js - Integração ARI com VoxCALL

## Configuração Base

### Carregar Configuração ARI
```typescript
import fs from 'fs/promises';

interface AriConfig {
  host: string;
  port: number;
  username: string;
  password: string;
  protocol: string;
}

let ariConfigCache: AriConfig | null = null;

async function loadAriConfig(): Promise<AriConfig> {
  if (ariConfigCache) return ariConfigCache;
  try {
    const data = await fs.readFile('ari-config.json', 'utf8');
    ariConfigCache = JSON.parse(data);
    return ariConfigCache!;
  } catch {
    return { host: '', port: 8088, username: '', password: '', protocol: 'http' };
  }
}

function invalidateAriConfigCache() {
  ariConfigCache = null;
}
```

### Função de Requisição ARI
```typescript
async function ariRequest(endpoint: string, method = 'GET', body?: any) {
  const config = await loadAriConfig();
  if (!config.host) throw new Error('Configuração ARI não definida');
  
  const url = `${config.protocol}://${config.host}:${config.port}/ari${endpoint}`;
  const auth = Buffer.from(`${config.username}:${config.password}`).toString('base64');
  
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 10000);
  
  try {
    const response = await fetch(url, {
      method,
      headers: {
        'Authorization': `Basic ${auth}`,
        'Content-Type': 'application/json',
      },
      body: body ? JSON.stringify(body) : undefined,
      signal: controller.signal,
    });
    
    clearTimeout(timeoutId);
    
    if (!response.ok) {
      const errorText = await response.text().catch(() => '');
      throw new Error(`ARI ${response.status}: ${errorText}`);
    }
    
    const text = await response.text();
    return text ? JSON.parse(text) : null;
  } catch (error: any) {
    clearTimeout(timeoutId);
    if (error.name === 'AbortError') {
      throw new Error('Timeout na conexão ARI');
    }
    throw error;
  }
}
```

## Dashboard em Tempo Real

### Listar Canais Ativos (Chamadas em Andamento)
```typescript
app.get("/api/ari/channels/active", async (req, res) => {
  try {
    const channels = await ariRequest('/channels');
    
    const activeChannels = channels.map((ch: any) => ({
      id: ch.id,
      name: ch.name,
      state: ch.state,
      callerName: ch.caller?.name || '',
      callerNumber: ch.caller?.number || '',
      connectedName: ch.connected?.name || '',
      connectedNumber: ch.connected?.number || '',
      duration: ch.creationtime 
        ? Math.floor((Date.now() - new Date(ch.creationtime).getTime()) / 1000) 
        : 0,
      context: ch.dialplan?.context || '',
      extension: ch.dialplan?.exten || '',
    }));
    
    res.json({
      total: activeChannels.length,
      channels: activeChannels
    });
  } catch (error: any) {
    res.status(500).json({ message: `Erro ARI: ${error.message}` });
  }
});
```

### Status dos Ramais (Endpoints)
```typescript
app.get("/api/ari/endpoints/status", async (req, res) => {
  try {
    const endpoints = await ariRequest('/endpoints');
    
    const pjsipEndpoints = endpoints
      .filter((ep: any) => ep.technology === 'PJSIP')
      .map((ep: any) => ({
        ramal: ep.resource,
        technology: ep.technology,
        state: ep.state,
        stateLabel: ep.state === 'online' ? 'Online' : 
                    ep.state === 'offline' ? 'Offline' : 'Desconhecido',
        inCall: ep.channel_ids?.length > 0,
        activeChannels: ep.channel_ids?.length || 0,
      }));
    
    const summary = {
      total: pjsipEndpoints.length,
      online: pjsipEndpoints.filter((e: any) => e.state === 'online').length,
      offline: pjsipEndpoints.filter((e: any) => e.state === 'offline').length,
      inCall: pjsipEndpoints.filter((e: any) => e.inCall).length,
    };
    
    res.json({ summary, endpoints: pjsipEndpoints });
  } catch (error: any) {
    res.status(500).json({ message: `Erro ARI: ${error.message}` });
  }
});
```

### Informações do Sistema Asterisk
```typescript
app.get("/api/ari/system/info", async (req, res) => {
  try {
    const info = await ariRequest('/asterisk/info');
    
    res.json({
      version: info.system?.version || 'N/A',
      entityId: info.system?.entity_id || 'N/A',
      os: info.build?.os || 'N/A',
      kernel: info.build?.kernel || 'N/A',
      uptime: info.status?.startup_time 
        ? Math.floor((Date.now() - new Date(info.status.startup_time).getTime()) / 1000)
        : 0,
      lastReload: info.status?.last_reload_time || null,
      maxChannels: info.config?.max_channels || 0,
      language: info.config?.default_language || 'en',
    });
  } catch (error: any) {
    res.status(500).json({ message: `Erro ARI: ${error.message}` });
  }
});
```

### Bridges Ativos (Conferências)
```typescript
app.get("/api/ari/bridges/active", async (req, res) => {
  try {
    const bridges = await ariRequest('/bridges');
    
    const activeBridges = bridges.map((br: any) => ({
      id: br.id,
      type: br.bridge_type,
      technology: br.technology,
      participants: br.channels?.length || 0,
      channelIds: br.channels || [],
      creationTime: br.creationtime,
    }));
    
    res.json({
      total: activeBridges.length,
      bridges: activeBridges
    });
  } catch (error: any) {
    res.status(500).json({ message: `Erro ARI: ${error.message}` });
  }
});
```

## Controle de Chamadas

### Originar Chamada
```typescript
app.post("/api/ari/calls/originate", async (req, res) => {
  try {
    const { from, to, callerId, context, app } = req.body;
    
    if (!to) {
      return res.status(400).json({ message: "Destino é obrigatório" });
    }
    
    const params: any = {
      endpoint: `PJSIP/${to}`,
      callerId: callerId || `VoxCALL <${from || '0000'}>`,
    };
    
    if (app) {
      params.app = app;
    } else {
      params.extension = to;
      params.context = context || 'from-internal';
      params.priority = 1;
    }
    
    const channel = await ariRequest('/channels', 'POST', params);
    
    res.json({
      success: true,
      channelId: channel.id,
      message: `Chamada originada para ${to}`
    });
  } catch (error: any) {
    res.status(500).json({ message: `Erro ao originar chamada: ${error.message}` });
  }
});
```

### Desligar Chamada
```typescript
app.delete("/api/ari/calls/:channelId", async (req, res) => {
  try {
    const { channelId } = req.params;
    await ariRequest(`/channels/${encodeURIComponent(channelId)}`, 'DELETE');
    res.json({ success: true, message: "Chamada encerrada" });
  } catch (error: any) {
    res.status(500).json({ message: `Erro ao encerrar chamada: ${error.message}` });
  }
});
```

### Transferir Chamada
```typescript
app.post("/api/ari/calls/:channelId/transfer", async (req, res) => {
  try {
    const { channelId } = req.params;
    const { destination } = req.body;
    
    await ariRequest(
      `/channels/${encodeURIComponent(channelId)}/redirect`, 
      'POST', 
      { endpoint: `PJSIP/${destination}` }
    );
    
    res.json({ success: true, message: `Chamada transferida para ${destination}` });
  } catch (error: any) {
    res.status(500).json({ message: `Erro na transferência: ${error.message}` });
  }
});
```

### Colocar em Espera / Retirar da Espera
```typescript
app.post("/api/ari/calls/:channelId/hold", async (req, res) => {
  try {
    const { channelId } = req.params;
    await ariRequest(`/channels/${encodeURIComponent(channelId)}/hold`, 'POST');
    res.json({ success: true, message: "Canal em espera" });
  } catch (error: any) {
    res.status(500).json({ message: `Erro: ${error.message}` });
  }
});

app.delete("/api/ari/calls/:channelId/hold", async (req, res) => {
  try {
    const { channelId } = req.params;
    await ariRequest(`/channels/${encodeURIComponent(channelId)}/hold`, 'DELETE');
    res.json({ success: true, message: "Canal retirado da espera" });
  } catch (error: any) {
    res.status(500).json({ message: `Erro: ${error.message}` });
  }
});
```

### Mutar / Desmutar Canal
```typescript
app.post("/api/ari/calls/:channelId/mute", async (req, res) => {
  try {
    const { channelId } = req.params;
    const { direction } = req.body;
    await ariRequest(
      `/channels/${encodeURIComponent(channelId)}/mute?direction=${direction || 'both'}`, 
      'POST'
    );
    res.json({ success: true, message: "Canal mutado" });
  } catch (error: any) {
    res.status(500).json({ message: `Erro: ${error.message}` });
  }
});

app.delete("/api/ari/calls/:channelId/mute", async (req, res) => {
  try {
    const { channelId } = req.params;
    await ariRequest(`/channels/${encodeURIComponent(channelId)}/mute`, 'DELETE');
    res.json({ success: true, message: "Canal desmutado" });
  } catch (error: any) {
    res.status(500).json({ message: `Erro: ${error.message}` });
  }
});
```

## WebSocket para Eventos em Tempo Real

### Conexão WebSocket com Reconexão Automática
```typescript
import WebSocket from 'ws';

interface AriEvent {
  type: string;
  timestamp: string;
  channel?: any;
  bridge?: any;
  endpoint?: any;
  [key: string]: any;
}

type EventHandler = (event: AriEvent) => void;

class AriWebSocketManager {
  private ws: WebSocket | null = null;
  private handlers: Map<string, EventHandler[]> = new Map();
  private reconnectTimer: NodeJS.Timeout | null = null;
  private isConnected = false;

  async connect(appName = 'voxcall-app') {
    const config = await loadAriConfig();
    if (!config.host) return;
    
    const wsProtocol = config.protocol === 'https' ? 'wss' : 'ws';
    const url = `${wsProtocol}://${config.host}:${config.port}/ari/events?app=${appName}&api_key=${config.username}:${config.password}`;
    
    try {
      this.ws = new WebSocket(url);
      
      this.ws.on('open', () => {
        this.isConnected = true;
        console.log('[ARI WS] Conectado');
        this.emit('connected', { type: 'connected', timestamp: new Date().toISOString() });
      });
      
      this.ws.on('message', (data) => {
        try {
          const event: AriEvent = JSON.parse(data.toString());
          this.emit(event.type, event);
          this.emit('*', event);
        } catch (e) {
          console.error('[ARI WS] Erro ao parsear evento:', e);
        }
      });
      
      this.ws.on('close', () => {
        this.isConnected = false;
        console.log('[ARI WS] Desconectado, reconectando em 5s...');
        this.emit('disconnected', { type: 'disconnected', timestamp: new Date().toISOString() });
        this.scheduleReconnect(appName);
      });
      
      this.ws.on('error', (err) => {
        console.error('[ARI WS] Erro:', err.message);
      });
    } catch (error: any) {
      console.error('[ARI WS] Falha na conexão:', error.message);
      this.scheduleReconnect(appName);
    }
  }
  
  private scheduleReconnect(appName: string) {
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer);
    this.reconnectTimer = setTimeout(() => this.connect(appName), 5000);
  }
  
  on(eventType: string, handler: EventHandler) {
    if (!this.handlers.has(eventType)) {
      this.handlers.set(eventType, []);
    }
    this.handlers.get(eventType)!.push(handler);
  }
  
  private emit(eventType: string, event: AriEvent) {
    const handlers = this.handlers.get(eventType) || [];
    handlers.forEach(handler => handler(event));
  }
  
  disconnect() {
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer);
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
    this.isConnected = false;
  }
  
  get connected() { return this.isConnected; }
}

const ariWS = new AriWebSocketManager();
export { ariWS };
```

### Usar WebSocket para Dashboard em Tempo Real
```typescript
ariWS.connect('voxcall-app');

ariWS.on('ChannelCreated', (event) => {
  console.log(`Nova chamada: ${event.channel?.caller?.number} → ${event.channel?.connected?.number}`);
});

ariWS.on('ChannelDestroyed', (event) => {
  console.log(`Chamada finalizada: ${event.channel?.id}`);
});

ariWS.on('ChannelStateChange', (event) => {
  console.log(`Estado mudou: ${event.channel?.id} → ${event.channel?.state}`);
});

ariWS.on('EndpointStateChange', (event) => {
  console.log(`Ramal ${event.endpoint?.resource}: ${event.endpoint?.state}`);
});
```

### Enviar Eventos para Frontend via SSE (Server-Sent Events)
```typescript
app.get("/api/ari/events/stream", (req, res) => {
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
  });
  
  const sendEvent = (event: AriEvent) => {
    res.write(`data: ${JSON.stringify(event)}\n\n`);
  };
  
  ariWS.on('*', sendEvent);
  
  req.on('close', () => {
    // Limpar handler quando cliente desconectar
  });
});
```

### Usar no Frontend React com SSE
```typescript
function useAriEvents() {
  const [channels, setChannels] = useState<any[]>([]);
  const [endpoints, setEndpoints] = useState<any[]>([]);
  
  useEffect(() => {
    const eventSource = new EventSource('/api/ari/events/stream');
    
    eventSource.onmessage = (event) => {
      const data = JSON.parse(event.data);
      
      switch (data.type) {
        case 'ChannelCreated':
        case 'ChannelDestroyed':
        case 'ChannelStateChange':
          fetchActiveChannels();
          break;
        case 'EndpointStateChange':
          fetchEndpointStatus();
          break;
      }
    };
    
    return () => eventSource.close();
  }, []);
  
  return { channels, endpoints };
}
```

## Gravações

### Listar Gravações
```typescript
app.get("/api/ari/recordings", async (req, res) => {
  try {
    const recordings = await ariRequest('/recordings/stored');
    res.json(recordings.map((rec: any) => ({
      name: rec.name,
      format: rec.format,
      duration: rec.duration,
      talkingDuration: rec.talking_duration,
      silenceDuration: rec.silence_duration,
      state: rec.state,
    })));
  } catch (error: any) {
    res.status(500).json({ message: `Erro: ${error.message}` });
  }
});
```

### Iniciar Gravação de Canal
```typescript
app.post("/api/ari/calls/:channelId/record", async (req, res) => {
  try {
    const { channelId } = req.params;
    const { name, format } = req.body;
    
    const recordingName = name || `rec-${Date.now()}`;
    const recording = await ariRequest(
      `/channels/${encodeURIComponent(channelId)}/record?name=${recordingName}&format=${format || 'wav'}&ifExists=overwrite`,
      'POST'
    );
    
    res.json({ success: true, recording });
  } catch (error: any) {
    res.status(500).json({ message: `Erro ao gravar: ${error.message}` });
  }
});
```

## Dashboard Resumo Completo

### Endpoint de Resumo para Dashboard
```typescript
app.get("/api/ari/dashboard/summary", async (req, res) => {
  try {
    const [channels, bridges, endpoints] = await Promise.all([
      ariRequest('/channels').catch(() => []),
      ariRequest('/bridges').catch(() => []),
      ariRequest('/endpoints').catch(() => []),
    ]);
    
    const pjsipEndpoints = endpoints.filter((e: any) => e.technology === 'PJSIP');
    
    res.json({
      calls: {
        active: channels.length,
        ringing: channels.filter((c: any) => c.state === 'Ringing').length,
        up: channels.filter((c: any) => c.state === 'Up').length,
      },
      bridges: {
        active: bridges.length,
        totalParticipants: bridges.reduce((sum: number, b: any) => sum + (b.channels?.length || 0), 0),
      },
      endpoints: {
        total: pjsipEndpoints.length,
        online: pjsipEndpoints.filter((e: any) => e.state === 'online').length,
        offline: pjsipEndpoints.filter((e: any) => e.state === 'offline').length,
        inCall: pjsipEndpoints.filter((e: any) => (e.channel_ids?.length || 0) > 0).length,
      },
      timestamp: new Date().toISOString(),
    });
  } catch (error: any) {
    res.status(500).json({ message: `Erro ARI: ${error.message}` });
  }
});
```

## Tratamento de Erros Padrão

```typescript
function handleAriError(error: any, res: any, context: string) {
  console.error(`[ARI] Erro em ${context}:`, error.message);
  
  let statusCode = 500;
  let message = error.message;
  let hint = '';
  
  if (error.message.includes('401')) {
    statusCode = 401;
    message = 'Credenciais ARI inválidas';
    hint = 'Verifique usuário e senha nas configurações ARI.';
  } else if (error.message.includes('Timeout') || error.message.includes('AbortError')) {
    message = 'Servidor ARI não respondeu';
    hint = 'Verifique se o Asterisk está rodando e acessível.';
  } else if (error.message.includes('ECONNREFUSED')) {
    message = 'Conexão recusada pelo servidor ARI';
    hint = 'Verifique se o HTTP Server do Asterisk está habilitado.';
  } else if (error.message.includes('não definida')) {
    statusCode = 400;
    message = 'Configuração ARI não definida';
    hint = 'Configure a conexão ARI em Configurações.';
  }
  
  res.status(statusCode).json({ message, hint });
}
```
