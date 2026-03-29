# Referência Completa da API ARI - Asterisk REST Interface

## Autenticação

Todas as requisições exigem autenticação via HTTP Basic Auth ou query parameter.

```
Authorization: Basic base64(username:password)
```
ou
```
GET /ari/channels?api_key=username:password
```

## Channels (Canais)

### GET /ari/channels
Lista todos os canais ativos.

**Resposta** (200):
```json
[
  {
    "id": "1234567890.42",
    "name": "PJSIP/2001-00000001",
    "state": "Up",
    "caller": { "name": "João Silva", "number": "2001" },
    "connected": { "name": "", "number": "2002" },
    "accountcode": "",
    "dialplan": { "context": "from-internal", "exten": "2002", "priority": 1 },
    "creationtime": "2024-01-15T10:30:00.000-0300",
    "language": "pt_BR"
  }
]
```

### POST /ari/channels
Origina uma nova chamada.

**Parâmetros**:
| Param | Tipo | Obrigatório | Descrição |
|-------|------|-------------|-----------|
| endpoint | string | Sim | Endpoint destino (ex: `PJSIP/2001`) |
| extension | string | Não | Extensão para dialplan após Stasis |
| context | string | Não | Contexto do dialplan |
| priority | int | Não | Prioridade no dialplan |
| callerId | string | Não | Caller ID (ex: `"João <2001>"`) |
| timeout | int | Não | Timeout em segundos (padrão: 30) |
| app | string | Não* | Nome da aplicação Stasis |
| appArgs | string | Não | Argumentos para a aplicação |
| channelId | string | Não | ID personalizado para o canal |
| otherChannelId | string | Não | ID do outro canal (para originate com 2 canais) |
| originator | string | Não | ID do canal originador |
| formats | string | Não | Codecs permitidos (ex: `ulaw,alaw`) |

*`app` ou `extension`+`context` são necessários.

**Exemplo - Originar chamada para ramal**:
```
POST /ari/channels
{
  "endpoint": "PJSIP/2001",
  "app": "voxcall-app",
  "callerId": "VoxCALL <9999>"
}
```

### GET /ari/channels/{channelId}
Detalhes de um canal específico.

### DELETE /ari/channels/{channelId}
Desliga um canal.

**Query params**:
| Param | Tipo | Descrição |
|-------|------|-----------|
| reason_code | string | Código de desligamento (ex: `normal`, `busy`, `congestion`) |
| reason | string | Motivo textual |

### POST /ari/channels/{channelId}/answer
Atende o canal (equivale ao `Answer()` do dialplan).

### POST /ari/channels/{channelId}/ring
Indica ring no canal.

### DELETE /ari/channels/{channelId}/ring
Para de indicar ring.

### POST /ari/channels/{channelId}/hold
Coloca o canal em espera.

### DELETE /ari/channels/{channelId}/hold
Retira o canal da espera.

### POST /ari/channels/{channelId}/mute
Muta o canal.

**Query params**:
| Param | Tipo | Descrição |
|-------|------|-----------|
| direction | string | `both` (padrão), `in`, `out` |

### DELETE /ari/channels/{channelId}/mute
Desmuta o canal.

### POST /ari/channels/{channelId}/redirect
Redireciona o canal para outro contexto/extensão do dialplan.

**Body**:
```json
{
  "endpoint": "PJSIP/2003"
}
```

### POST /ari/channels/{channelId}/play
Reproduz mídia no canal.

**Query params**:
| Param | Tipo | Descrição |
|-------|------|-----------|
| media | string | URI da mídia (ex: `sound:hello-world`, `recording:gravacao1`) |
| lang | string | Idioma (ex: `pt_BR`) |
| offsetms | int | Offset em milissegundos |
| skipms | int | Skip em milissegundos para ff/rw |
| playbackId | string | ID personalizado para o playback |

### POST /ari/channels/{channelId}/record
Inicia gravação do canal.

**Query params**:
| Param | Tipo | Descrição |
|-------|------|-----------|
| name | string | Nome do arquivo de gravação |
| format | string | Formato (`wav`, `gsm`, `ulaw`) |
| maxDurationSeconds | int | Duração máxima |
| maxSilenceSeconds | int | Máximo de silêncio antes de parar |
| ifExists | string | `fail`, `overwrite`, `append` |
| beep | boolean | Tocar beep ao iniciar |
| terminateOn | string | DTMF para parar (`#`, `*`, `any`, `none`) |

### POST /ari/channels/{channelId}/snoop
Espiona (monitor) um canal.

**Query params**:
| Param | Tipo | Descrição |
|-------|------|-----------|
| spy | string | Direção do áudio: `none`, `both`, `out`, `in` |
| whisper | string | Direção do sussurro: `none`, `both`, `out`, `in` |
| app | string | Aplicação Stasis para o canal snoop |
| appArgs | string | Argumentos da aplicação |
| snoopId | string | ID personalizado |

### GET /ari/channels/{channelId}/variable
Lê uma variável do canal.

**Query params**: `variable` (nome da variável, ex: `CALLERID(num)`)

### POST /ari/channels/{channelId}/variable
Define uma variável no canal.

**Query params**: `variable` (nome), `value` (valor)

## Bridges (Conferências/Salas)

### GET /ari/bridges
Lista todos os bridges ativos.

**Resposta**:
```json
[
  {
    "id": "bridge-001",
    "technology": "simple_bridge",
    "bridge_type": "mixing",
    "bridge_class": "base",
    "channels": ["1234567890.42", "1234567890.43"],
    "creationtime": "2024-01-15T10:30:00.000-0300"
  }
]
```

### POST /ari/bridges
Cria um novo bridge.

**Query params**:
| Param | Tipo | Descrição |
|-------|------|-----------|
| type | string | Tipo: `mixing` (conferência), `holding` (espera), `dtmf_events`, `proxy_media` |
| bridgeId | string | ID personalizado |
| name | string | Nome do bridge |

### POST /ari/bridges/{bridgeId}/addChannel
Adiciona canal(is) ao bridge.

**Query params**:
| Param | Tipo | Descrição |
|-------|------|-----------|
| channel | string | ID(s) do canal (múltiplos separados por vírgula) |
| role | string | `participant` ou `announcer` |
| absorbDTMF | boolean | Absorver DTMF (não enviar para outros participantes) |
| mute | boolean | Entrar mutado |

### POST /ari/bridges/{bridgeId}/removeChannel
Remove canal do bridge.

**Query params**: `channel` (ID do canal)

### POST /ari/bridges/{bridgeId}/record
Grava o áudio do bridge.

### POST /ari/bridges/{bridgeId}/play
Reproduz áudio no bridge (para todos os participantes).

## Endpoints (Ramais/Troncos)

### GET /ari/endpoints
Lista todos os endpoints registrados.

**Resposta**:
```json
[
  {
    "technology": "PJSIP",
    "resource": "2001",
    "state": "online",
    "channel_ids": ["1234567890.42"]
  }
]
```

### GET /ari/endpoints/{tech}
Lista endpoints de uma tecnologia específica.

Tecnologias válidas: `PJSIP`, `SIP`, `IAX2`, `DAHDI`

### GET /ari/endpoints/{tech}/{resource}
Detalhes de um endpoint específico (ex: `/ari/endpoints/PJSIP/2001`).

**Resposta**:
```json
{
  "technology": "PJSIP",
  "resource": "2001",
  "state": "online",
  "channel_ids": []
}
```

Estados possíveis: `unknown`, `offline`, `online`

## Recordings (Gravações)

### GET /ari/recordings/stored
Lista gravações armazenadas.

**Resposta**:
```json
[
  {
    "name": "gravacao-20240115",
    "format": "wav",
    "target_uri": "channel:1234567890.42",
    "state": "done",
    "duration": 120,
    "talking_duration": 95,
    "silence_duration": 25
  }
]
```

### GET /ari/recordings/stored/{name}/file
Download do arquivo de gravação (retorna o binário do áudio).

### GET /ari/recordings/live/{name}
Status de uma gravação em andamento.

### POST /ari/recordings/live/{name}/stop
Para uma gravação em andamento.

### POST /ari/recordings/live/{name}/pause
Pausa uma gravação.

### POST /ari/recordings/live/{name}/unpause
Retoma gravação pausada.

## Asterisk (Informações do Sistema)

### GET /ari/asterisk/info
Informações do sistema Asterisk.

**Query params**: `only` (filtrar seção: `build`, `system`, `config`, `status`)

**Resposta**:
```json
{
  "build": {
    "os": "Linux",
    "kernel": "5.15.0",
    "machine": "x86_64",
    "date": "2024-01-10",
    "user": "root"
  },
  "system": {
    "version": "22.0.0",
    "entity_id": "asterisk-server-01"
  },
  "config": {
    "name": "Asterisk",
    "default_language": "pt_BR",
    "max_channels": 0,
    "max_open_files": 16384
  },
  "status": {
    "startup_time": "2024-01-15T08:00:00.000-0300",
    "last_reload_time": "2024-01-15T09:30:00.000-0300"
  }
}
```

### GET /ari/asterisk/modules
Lista módulos carregados no Asterisk.

### PUT /ari/asterisk/modules/{moduleName}
Carrega um módulo.

### DELETE /ari/asterisk/modules/{moduleName}
Descarrega um módulo.

### POST /ari/asterisk/modules/{moduleName}
Recarrega um módulo.

### GET /ari/asterisk/variable
Lê variável global do Asterisk.

**Query params**: `variable` (nome da variável)

### POST /ari/asterisk/variable
Define variável global.

**Query params**: `variable`, `value`

## Applications (Aplicações Stasis)

### GET /ari/applications
Lista aplicações Stasis registradas.

### GET /ari/applications/{appName}
Detalhes de uma aplicação.

### POST /ari/applications/{appName}/subscription
Inscreve a aplicação para receber eventos de um recurso.

**Query params**: `eventSource` (ex: `channel:1234567890.42`, `bridge:bridge-001`, `endpoint:PJSIP/2001`)

### DELETE /ari/applications/{appName}/subscription
Remove inscrição de eventos.

## Devicestates (Estados de Dispositivo)

### GET /ari/deviceStates
Lista todos os estados de dispositivo.

### GET /ari/deviceStates/{deviceName}
Estado de dispositivo específico.

### PUT /ari/deviceStates/{deviceName}
Define estado do dispositivo.

**Query params**: `deviceState` (`NOT_INUSE`, `INUSE`, `BUSY`, `INVALID`, `UNAVAILABLE`, `RINGING`, `RINGINUSE`, `ONHOLD`)

## Sounds (Sons)

### GET /ari/sounds
Lista sons disponíveis no sistema.

**Query params**: `lang` (idioma, ex: `pt_BR`), `format` (formato do arquivo)

### GET /ari/sounds/{soundId}
Detalhes de um som específico.

## Códigos de Status HTTP

| Status | Descrição |
|--------|-----------|
| 200 | Sucesso |
| 201 | Recurso criado |
| 204 | Sucesso sem conteúdo |
| 400 | Parâmetro inválido |
| 401 | Não autenticado |
| 403 | Sem permissão |
| 404 | Recurso não encontrado |
| 405 | Método não permitido |
| 409 | Conflito (recurso já existe) |
| 412 | Pré-condição falhou (canal não no Stasis) |
| 500 | Erro interno do Asterisk |
