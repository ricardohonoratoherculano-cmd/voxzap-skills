---
name: microsoft-teams-integration
description: Integração de VoxCALL/Asterisk PBX com Microsoft Teams para chamadas externas. Use quando o usuário pedir para conectar Teams ao Asterisk, planejar Direct Routing (com ou sem SBC), Operator Connect, integração via Microsoft Graph Calling API, configurar troncos SIP TLS+SRTP do Teams, ou avaliar viabilidade de soluções para clientes que querem usar Teams como softphone integrado ao discador/PBX. Inclui caminhos de integração, requisitos técnicos, configuração de Asterisk como SBC, PowerShell do Teams, limitações honestas de troubleshoot autônomo, e recomendações de perfil de cliente.
---

# Integração VoxCALL/Asterisk com Microsoft Teams

Skill consultiva que consolida o conhecimento sobre como conectar o ecossistema VoxCALL (Asterisk PBX + discador + relatórios) ao Microsoft Teams da Microsoft 365, incluindo arquiteturas suportadas pela Microsoft, requisitos técnicos, adaptações no VoxCALL, e o que esperar/não esperar do suporte ao longo do tempo.

## Quando usar

- Cliente da PlanoClin/VoxCALL pediu para "fazer o Teams ligar pelo nosso PBX" ou "atender chamada de cliente direto no Teams"
- Avaliar se vale a pena vender VoxCALL para empresa que já padronizou Teams
- Planejar tronco SIP entre Asterisk e Teams sem comprar SBC certificado
- Decidir entre Direct Routing, Operator Connect e Graph Calling API
- Estimar esforço de manter integração Teams ao longo do tempo (mudanças da Microsoft)
- Responder dúvidas comerciais sobre "Teams vs softphone próprio"

## Os 3 caminhos oficiais para conectar telefonia externa ao Teams

A Microsoft suporta exatamente três arquiteturas para que um Teams faça chamadas pela rede pública/PBX externo. Qualquer abordagem fora destas três é gambiarra ou bot do lado do usuário.

### 1. Direct Routing (mais flexível, mais trabalhoso)

- O cliente conecta o **próprio PBX/SBC** ao Teams via tronco SIP TLS + SRTP
- A Microsoft trata o PBX como um SBC (Session Border Controller)
- Funciona com qualquer operadora/numeração
- **Único caminho viável** para integrar Asterisk diretamente
- Custo recorrente: licenças Teams Phone (Microsoft Teams Phone Standard ou plano E5) por usuário

### 2. Operator Connect (mais fácil, mais caro)

- Cliente compra serviço de operadora certificada pela Microsoft (Vodafone, BT, Verizon, Algar, etc.)
- A operadora gerencia o SBC e os números
- Configuração no admin center é "ponto-e-clica"
- Sem flexibilidade para integrar PBX próprio
- Não serve para o nosso cenário (queremos passar pelo Asterisk)

### 3. Microsoft Calling Plans

- Plano de telefonia fornecido pela própria Microsoft
- Disponível em poucos países (Brasil **não** está na lista completa)
- Sem qualquer integração com PBX externo
- Não serve

### 4. Bonus: Microsoft Graph Cloud Communications API

- API REST/WebSocket para construir bots de chamada **dentro** do Teams
- Permite criar URA, gravação de meeting, transferência via app
- **Não substitui Direct Routing** — o tráfego de voz continua passando pela Microsoft
- Útil para criar bot que escuta chamada Teams e fala com Asterisk via webhook, mas não para tronco SIP

## Direct Routing SEM comprar SBC certificado

A Microsoft mantém uma lista de SBCs "Certified for Teams" (AudioCodes, Ribbon, Oracle, Cisco). **Não é obrigatório** usar SBC certificado — a Microsoft suporta qualquer SBC que cumpra os requisitos técnicos. O Asterisk, configurado corretamente, funciona como SBC para Direct Routing. Há comunidades inteiras (asterisk.org, freepbx.org, github) que comprovam esse cenário em produção desde 2019.

### Trade-off de não usar SBC certificado

- **Vantagem**: economia (SBC AudioCodes Mediant entry-level custa US$ 3-8k + licenças por canal)
- **Desvantagem**: se a Microsoft mudar requisito de TLS, codec, ou cabeçalho SIP, ninguém da Microsoft te ajuda — você descobre quebrando
- **Mitigação**: monitoramento ativo + comunidade Asterisk + canal de release notes do Teams Direct Routing

### SBC homologados ("Certified for Teams") — opções e faixas de preço

Lista oficial atualizada: https://learn.microsoft.com/microsoftteams/direct-routing-border-controllers

Use estas opções **somente** quando o cliente exigir suporte oficial Microsoft, alta densidade de canais (200+ ramais), ou quando a equipe de TI do cliente preferir hardware appliance dedicado em vez de Asterisk como SBC.

| Fabricante | Modelo entry-level | Capacidade | Faixa de preço (USD) | Quando indicar |
|---|---|---|---|---|
| **AudioCodes** | Mediant 500L / 800B | 25-250 sessões | US$ 3.000 – 8.000 + ~US$ 50/canal SBC license | Cliente com infra Microsoft pesada (Exchange, AD, M365 E5). Padrão "default" do mercado corporativo brasileiro. |
| **AudioCodes** | Mediant 1000B / 2600 | 250-2.000 sessões | US$ 8.000 – 25.000 + licenças | Operação 200+ ramais Teams ativos, alta concorrência. |
| **Ribbon** (ex-Sonus) | SBC 1000 / 2000 | 100-2.000 sessões | US$ 5.000 – 20.000 + licenças por canal | Cliente com SLA carrier-grade, integração com operadora SIP. Forte em telecom. |
| **Ribbon** | SBC SWe Edge (software) | 25-500 sessões | US$ 3.000 – 12.000 (licença) + VM própria | Quem já tem virtualização e quer SBC software certificado sem appliance. |
| **Oracle** (ex-Acme Packet) | Acme Packet 1100 / 3900 | 250-16.000 sessões | US$ 10.000 – 50.000+ | Enterprise muito grande, multi-site, alta disponibilidade ativa-ativa. |
| **Cisco** | CUBE (em ISR/CSR1000v) | varia por licença | US$ 2.000 – 15.000 (licença CUBE) + roteador Cisco | Cliente que já tem Cisco UC ou CallManager e quer integração nativa. |
| **TE-Systems** | anynode (software) | 10-2.000+ sessões | US$ 1.500 – 10.000 (licença anual) | SBC software certificado mais barato. Roda em Windows/Linux. Boa porta de entrada certificada. |
| **Asterisk como SBC** | (referência alternativa) | sem limite formal | US$ 0 (open-source) + custo do servidor | **NÃO certificado**. Funciona, mas sem suporte Microsoft. Ver seção acima. |

**Regra prática para o agente Replit ao recomendar**:
- Cliente VoxCALL típico (10-100 ramais, médio porte) → propor Asterisk como SBC (já temos). Economia de US$ 3-8k+ vs entry-level certificado.
- Cliente exige certificação Microsoft → começar por **TE-Systems anynode** (software, mais barato) ou **AudioCodes Mediant 500L** (appliance, padrão de mercado).
- Cliente 500+ ramais ou multi-site → **Ribbon SBC 2000** ou **Oracle Acme Packet 3900**.
- Cliente já-Cisco → **CUBE** dentro do ISR existente.

Preços são de referência 2024-2026 para canal de distribuição BR; podem variar ±30% com câmbio e descontos de revenda.

## Requisitos técnicos do Asterisk como SBC para Direct Routing

### Pré-requisitos do servidor Asterisk

- IP público fixo (não NAT 1:1 atrás de carrier)
- FQDN público resolvível (ex: `pbx-cliente.voxcall.cc`) — A Microsoft exige FQDN, não aceita IP
- Certificado TLS público válido (Let's Encrypt, DigiCert, GoDaddy) emitido para o FQDN
- Asterisk 16+ (idealmente 18 ou 20 LTS) com pjsip
- Firewall abrindo TCP 5061 (SIP-TLS) e UDP 49152-53247 (RTP) **somente** para os IPs/range da Microsoft Teams (publicado em https://learn.microsoft.com/microsoftteams/direct-routing-plan)

### Codecs aceitos pelo Teams

- **Obrigatórios**: SILK, OPUS, G.711 (a-law/u-law)
- **Aceitos**: G.722, G.729 (com licença)
- Asterisk **precisa transcodificar** se o tronco da operadora local for G.711 e o Teams pedir SILK/OPUS — isso consome CPU. Dimensione com folga (1 vCPU para cada 30 chamadas concorrentes em transcoding).

### Recursos obrigatórios

- **SRTP** (criptografia de mídia) — Teams exige
- **SIP over TLS** — não aceita SIP UDP/TCP cleartext
- **ICE/STUN** — para NAT traversal das mídias
- **SIP OPTIONS** keepalive a cada 60s para o Teams considerar o tronco "saudável"

### Exemplo de pjsip.conf para o tronco Teams

```ini
;==== Transport TLS ====
[transport-tls]
type=transport
protocol=tls
bind=0.0.0.0:5061
external_media_address=pbx-cliente.voxcall.cc
external_signaling_address=pbx-cliente.voxcall.cc
cert_file=/etc/letsencrypt/live/pbx-cliente.voxcall.cc/fullchain.pem
priv_key_file=/etc/letsencrypt/live/pbx-cliente.voxcall.cc/privkey.pem
method=tlsv1_2
verify_server=yes
verify_client=no
require_client_cert=no

;==== Endpoint Teams ====
[teams-endpoint]
type=endpoint
transport=transport-tls
context=from-teams
disallow=all
allow=ulaw
allow=alaw
allow=opus
allow=silk16
direct_media=no
ice_support=yes
media_encryption=sdes
rtp_symmetric=yes
force_rport=yes
rewrite_contact=yes
trust_id_inbound=yes
from_user=pbx-cliente.voxcall.cc
from_domain=pbx-cliente.voxcall.cc
aors=teams-aor
identify_by=ip

;==== AOR (3 SIP proxies do Teams para failover) ====
[teams-aor]
type=aor
contact=sip:sip.pstnhub.microsoft.com:5061\;transport=tls
contact=sip:sip2.pstnhub.microsoft.com:5061\;transport=tls
contact=sip:sip3.pstnhub.microsoft.com:5061\;transport=tls
qualify_frequency=60

;==== Identify (libera os IPs da Microsoft) ====
[teams-identify]
type=identify
endpoint=teams-endpoint
match=52.114.148.0
match=52.114.132.46
match=52.114.75.24
match=52.114.76.76
match=52.114.7.24
match=52.114.14.70
; lista completa em https://learn.microsoft.com/microsoftteams/direct-routing-plan
```

### Exemplo de extensions.conf

```ini
;==== Recebendo do Teams ====
[from-teams]
exten => _X.,1,NoOp(Chamada vinda do Teams para ${EXTEN})
 same => n,Set(CALLERID(num)=${CALLERID(num):-2}) ; ajuste se Teams enviar com prefixo +
 same => n,Goto(MANAGER,${EXTEN},1)               ; rotear pelo dialplan padrão VoxCALL

;==== Enviando para o Teams ====
[MANAGER]
; quando o destino for um usuário Teams (ex: ramal 9XXX mapeado para usuário Teams)
exten => _9XXX,1,NoOp(Roteando ${EXTEN} para Teams)
 same => n,Set(CALLERID(num)=+5581XXXXXXXX)        ; obrigatório E.164 com +
 same => n,Dial(PJSIP/${EXTEN}@teams-endpoint,60,t)
 same => n,Hangup()
```

## Configuração no lado da Microsoft 365 (PowerShell Teams)

Tudo é feito via módulo `MicrosoftTeams` PowerShell (não há UI completa para Direct Routing). Precisa de conta admin global do tenant.

```powershell
# 1. Conectar
Install-Module -Name MicrosoftTeams -Force
Connect-MicrosoftTeams

# 2. Adicionar o PBX como gateway (PSTN Gateway)
New-CsOnlinePSTNGateway `
  -Fqdn pbx-cliente.voxcall.cc `
  -SipSignalingPort 5061 `
  -ForwardCallHistory $true `
  -ForwardPai $true `
  -MediaBypass $false `
  -Enabled $true

# 3. Criar PSTN Usage
Set-CsOnlinePstnUsage -Identity Global -Usage @{Add="VoxCALL-Brasil"}

# 4. Criar Voice Route apontando para o gateway
New-CsOnlineVoiceRoute `
  -Identity "VoxCALL-Route-BR" `
  -NumberPattern "^\+55[0-9]{10,11}$" `
  -OnlinePstnGatewayList pbx-cliente.voxcall.cc `
  -OnlinePstnUsages "VoxCALL-Brasil"

# 5. Criar Voice Routing Policy
New-CsOnlineVoiceRoutingPolicy "VoxCALL-Policy" -OnlinePstnUsages "VoxCALL-Brasil"

# 6. Atribuir a policy ao usuário (e dar a ele Teams Phone Standard)
Grant-CsOnlineVoiceRoutingPolicy -Identity usuario@cliente.com.br -PolicyName "VoxCALL-Policy"
Set-CsPhoneNumberAssignment -Identity usuario@cliente.com.br -PhoneNumber "+5581XXXXXXXX" -PhoneNumberType DirectRouting
```

### Validação no Teams

Depois de configurar, no Teams admin center → Voice → Direct Routing, o gateway deve aparecer com status SBC = **Active** dentro de 5-10 minutos. Se ficar Inactive, geralmente é:

- Cert TLS inválido/expirado
- FQDN não resolvendo no DNS público
- Asterisk não respondendo OPTIONS para os IPs do Teams
- Cabeçalho `Contact` com IP em vez de FQDN

## Adaptações necessárias no VoxCALL

### Tabela `users` (shared/schema.ts)

Adicionar campos opcionais ao usuário para mapear ramal Asterisk ↔ usuário Teams:

```typescript
teamsUpn: text("teams_upn"),                 // user@cliente.onmicrosoft.com
teamsPhoneNumber: text("teams_phone_number"), // +5581XXXXXXXX (E.164)
teamsRoutingEnabled: boolean("teams_routing_enabled").default(false),
```

### Roteamento no discador (server/dialer-engine.ts)

No `originateCall()`, quando o ramal do operador tem `teamsRoutingEnabled = true`:

- Trocar `endpoint: "PJSIP/" + ramal` por `endpoint: "PJSIP/" + teamsPhoneNumber + "@teams-endpoint"`
- Forçar `CALLERID(num)` no formato E.164 (a Microsoft rejeita SIP From sem `+`)
- Garantir que `originateMode` continua respeitando `queue` ou `dialplan` (feature de Roteamento Asterisk por campanha já implementada)

### Painel "Gráfico da Operação"

O painel de status em tempo real (consulta ARI) **não enxerga** o estado do usuário Teams diretamente — o ARI só vê o canal SIP do tronco. Soluções:

- **Opção A (simples)**: marcar status como "TEAMS - EM USO" enquanto houver canal ativo no tronco Teams associado ao número do operador
- **Opção B (rica)**: integrar Microsoft Graph Presence API (`/users/{id}/presence`) para puxar Available/Busy/InACall do Teams e exibir no dashboard
  - Custo: aplicação Azure AD registrada com permissão `Presence.Read.All` (consentimento admin)
  - Polling a cada 30-60s ou subscription via Graph webhooks

### CDR e gravações

- **CDR**: o `cdr` do Asterisk continua registrando a chamada normalmente — `dst` será o número Teams (ex: `+5581XXXXXXXX`), `dstchannel` será `PJSIP/teams-endpoint-XXXXXXXX`. Os relatórios do VoxCALL não precisam mudar.
- **Gravações**: continuam sendo geradas pelo Asterisk (Monitor/MixMonitor). O Teams **não** grava o lado dele — quem grava é nosso Asterisk. Ponto positivo: as gravações da operação ficam no nosso ecossistema, não dependem de retenção do Microsoft 365.

### Pause/Unpause/Logout do operador

Continua via tabela `monitor_operador` (escrita do VoxCALL) → trigger `trg_sync_monitor_to_queue` → `queue_member_table` (Asterisk respeita). O Teams não interfere nisso porque o operador continua sendo membro de fila Asterisk; apenas o **canal de mídia/áudio** é o Teams em vez de softphone próprio.

## Limitações honestas do agente Replit para troubleshoot

A Microsoft muda os requisitos do Direct Routing periodicamente (TLS 1.3, IPs novos, deprecation de SILK NB, mudança em SIP headers). O que o agente Replit consegue e não consegue fazer:

### O agente CONSEGUE

- Configurar `pjsip.conf`, `extensions.conf`, `http.conf`, `ari.conf` no Asterisk via SSH
- Verificar logs do Asterisk (`/var/log/asterisk/full`, `pjsip set logger on`)
- Atualizar IPs da Microsoft no `[teams-identify]` quando o cliente reportar quebra
- Renovar certificado Let's Encrypt automaticamente
- Adicionar/remover roteamento por campanha (Roteamento Asterisk por campanha — feature pronta)
- Adicionar campos `teamsUpn/teamsPhoneNumber` no schema, formulários e dialer engine
- Consultar Microsoft Graph (presence, calling) com OAuth client_credentials
- Gerar scripts PowerShell do Teams para o admin do cliente rodar

### O agente NÃO CONSEGUE

- Acessar o tenant Microsoft 365 do cliente (precisa do admin global rodar PowerShell)
- Capturar pacotes SIP entre Asterisk e Microsoft (tcpdump funciona, mas leitura é manual)
- Receber alerta proativo de "a Microsoft vai mudar X em Y dias" (RSS/blog Microsoft 365 Roadmap precisa ser monitorado externamente)
- Responder por SLA da Microsoft (não há suporte Microsoft para SBC não-certificado — Microsoft só apoia se for AudioCodes/Ribbon/Oracle/Cisco)
- Garantir que o codec SILK 16k vai continuar aceito amanhã (a Microsoft pode forçar OPUS, e nosso Asterisk + libopus precisam estar prontos)

### Padrão de troubleshoot quando o tronco quebrar

1. SSH no servidor Asterisk via `client-server-access` skill
2. `asterisk -rx "pjsip show endpoint teams-endpoint"` — confirmar que está `Available`
3. `tail -f /var/log/asterisk/full | grep -i teams` enquanto cliente tenta uma chamada
4. Se houver erro `403 Forbidden` ou `488 Not Acceptable`, ler o SIP RAW e comparar com requisitos da Microsoft
5. Comparar IP do Microsoft contra a lista pública e atualizar `[teams-identify]` se mudou
6. Verificar validade do cert TLS: `openssl s_client -connect pbx-cliente.voxcall.cc:5061 -showcerts`
7. Se tudo no Asterisk estiver OK, escalar para o admin Microsoft 365 do cliente rodar diagnóstico no Teams admin center → Direct Routing → Health

## Recomendação de perfil de cliente

### Cliente IDEAL para integração Teams

- Já tem licença Teams Phone Standard ou E5 (não vai pagar a mais)
- Quer eliminar softphone próprio e padronizar Teams como ferramenta única
- Tem TI interna ou parceiro que conhece Microsoft 365
- Aceita que mudanças no Teams podem exigir manutenção paga
- Volume médio (10-50 ramais) — para ROI vs SBC certificado

### Cliente que NÃO vale a pena

- Quer "só pra economizar licença Teams" (não vai dar — Teams Phone é obrigatório)
- Não tem admin Microsoft 365 nem aceita pagar parceiro
- Quer SLA de 99,9% sem pagar suporte premium
- Vai trazer 200+ usuários — nesse caso, SBC AudioCodes/Ribbon dedicado paga rápido

## Próximos passos para POC

Quando o usuário decidir avançar com algum cliente:

1. Confirmar que o cliente tem Teams Phone Standard (ou plano E5) ativo
2. Confirmar IP público + FQDN + emissão de cert Let's Encrypt no servidor PlanoClin (ou novo tenant)
3. Aplicar configuração `pjsip.conf` + `extensions.conf` acima via SSH
4. Pedir ao admin do cliente para rodar o script PowerShell
5. Aguardar 10min e verificar status SBC = Active no Teams admin center
6. Testar chamada de saída Teams → celular do técnico
7. Testar chamada de entrada celular → DID Teams (deve cair no PBX, ser distribuído pelo dialplan MANAGER)
8. Adicionar campos `teamsUpn/teamsPhoneNumber` ao schema VoxCALL e ao formulário de usuários
9. Adaptar `dialer-engine.ts` para originar pelo tronco Teams quando `teamsRoutingEnabled=true`
10. Documentar o tenant cliente em `client-server-access` para reuso futuro

## Skills relacionadas (cross-links)

Antes de implementar mudanças no VoxCALL motivadas pela integração Teams, leia também:

- **`voxfone-telephony-crm`** (`.agents/skills/voxfone-telephony-crm/SKILL.md`) — padrões obrigatórios do VoxCALL/PlanoClin: schema (`shared/schema.ts`), `IStorage`, `server/routes.ts`, autenticação, gravações, softphone WebRTC. **Toda mudança em ramal/usuário/CDR/discador descrita aqui precisa seguir os padrões dessa skill.**
- **`asterisk-callcenter-expert`** (`.agents/skills/asterisk-callcenter-expert/SKILL.md`) — eventos `queue_log` e schema `cdr` em PostgreSQL. Use ao adicionar coluna `channel_tech` ao CDR ou filtrar relatórios por origem PJSIP vs Teams.
- **`asterisk-ari-expert`** (`.agents/skills/asterisk-ari-expert/SKILL.md`) — controle de canais via ARI. Use para roteamento dinâmico Teams ↔ Asterisk e para o "Gráfico da Operação" mostrar status real-time dos troncos Teams.
- **`client-server-access`** (`.agents/skills/client-server-access/SKILL.md`) — SSH no servidor do cliente. **Obrigatório** para aplicar `pjsip.conf`/`extensions.conf` do tronco Teams, rodar `pjsip reload`, capturar `pjsip set logger on` e diagnosticar handshake TLS.
- **`whatsapp-calling-expert`** (`.agents/skills/whatsapp-calling-expert/SKILL.md`) — referência de padrão BYOV (Bring-Your-Own-VoIP) usado pelo WhatsApp Calling. A integração Teams segue arquitetura similar (PBX próprio conectado via tronco SIP TLS+SRTP a um provedor cloud), e a forma como modelamos `permission` e webhooks no WhatsApp é um bom espelho para `direct_routing_status` no Teams.
- **`deploy-assistant-vps`** (`.agents/skills/deploy-assistant-vps/SKILL.md`) — UI de deploy do VoxCALL. Se um dia oferecermos "wizard Teams Direct Routing" no painel admin, deve seguir o mesmo padrão de stepper guiado dessa skill.

## Referências oficiais

- Direct Routing planning: https://learn.microsoft.com/microsoftteams/direct-routing-plan
- Lista de IPs/portas Teams: https://learn.microsoft.com/microsoftteams/direct-routing-plan#sip-signaling-fqdns
- SBC certificados (referência, não obrigatório): https://learn.microsoft.com/microsoftteams/direct-routing-border-controllers
- PowerShell MicrosoftTeams: https://learn.microsoft.com/powershell/teams/intro
- Graph Presence API: https://learn.microsoft.com/graph/api/resources/presence
- Graph Calling API: https://learn.microsoft.com/graph/api/resources/communications-api-overview
- Comunidade Asterisk + Teams: https://community.asterisk.org/c/asterisk-support/microsoft-teams/
