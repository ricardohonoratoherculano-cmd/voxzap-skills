---
name: site-voxtel
description: Site institucional voxtel.cc (PHP estático + nginx + Docker) deployado como tenant slot 4 do servidor multi-tenant eveo1. Use quando precisar editar páginas (home, voxcall, voxzap, política, termos), adicionar componentes (header, footer, cookie banner, widget VoxKit "Agendar por Voz"), refazer build, redeployar via SSH/Docker, configurar HTTPS, ou debugar o container voxtel-cc. Inclui estrutura de diretórios, fluxo de deploy, integração com cookie banner LGPD, e padrão de componentes PHP.
---

# Site Institucional voxtel.cc

Site público da Voxtel Telecomunicações (`https://voxtel.cc`). Migração do antigo `portalvoxtel.com.br` para arquitetura limpa, multi-tenant, dockerizada.

## Quando Usar

- Editar páginas (home, /voxcall, /voxzap, /politica-de-privacidade, /termos-de-uso)
- Adicionar/modificar componentes compartilhados (header, footer, cookie banner, voxkit widget)
- Trocar conteúdo, imagens, vídeos, CTAs
- Renovar/diagnosticar certificado HTTPS
- Redeployar após mudanças
- Debugar container `voxtel-cc` no eveo1
- Replicar o site em outro servidor multi-tenant

## Quando NÃO Usar

- Migração do site antigo `portalvoxtel.com.br` (em andamento na Task #150) → ver task-specific work
- Setup do servidor EVEO em si → use `eveo-server-setup`
- Provisionamento de novos tenants em geral → use `multi-tenant-server`
- Deploy de Node.js/Prisma (VoxZap/VoxCall) → use `voxzap-multitenant-install` ou `deploy-assistant-vps`

---

## 1. Arquitetura

| Item | Valor |
|---|---|
| Domínio | `voxtel.cc` |
| Servidor | `eveo1.voxserver.app.br` (slug cofre: `planoclin`) |
| Slot multi-tenant | 4 |
| Path remoto | `/opt/tenants/voxtel-cc/` |
| Path local (dev) | `.local/voxtel-cc-site/` |
| Container | `voxtel-cc` |
| Compose service | `voxtel-cc` |
| Stack | nginx + PHP-FPM 8.2 (Alpine) em uma única imagem |
| Porta interna | 80 |
| Porta exposta no host | 8084 (slot 4) |
| Reverse proxy | nginx central em `/opt/tenants/nginx/` |
| Cert HTTPS | Let's Encrypt via certbot (válido até 2026-07-25) |
| Hardening | `mem_limit: 256m`, `cpus: 0.5`, `pids_limit: 128`, `security_opt: no-new-privileges` |
| Bundle size | ~65KB (.tar.gz) |

### Rotas

- `/` — home
- `/voxcall/` — produto VoxCall (telefonia)
- `/voxzap/` — produto VoxZap (omnichannel)
- `/politica-de-privacidade/` — LGPD
- `/termos-de-uso/` — termos

### Integrações ativas

- **WebChat VoxZap** (token público em `data-token`, gated por consentimento de cookies "functionality")
- **VoxKit "Agendar por Voz"** (iframe de `https://playvox.voxkit.voxserver.app.br`, mesmo gating LGPD)
- **Font Awesome 6.4.2** (CDN cdnjs)

---

## 2. Estrutura de Diretórios

```
.local/voxtel-cc-site/                    # source local (mesmo layout que /opt/tenants/voxtel-cc/ no eveo1)
├── Dockerfile                            # nginx:alpine + php-fpm + supervisor
├── docker-compose.yml                    # service voxtel-cc, network nginx_net (externa), hardening
├── .dockerignore
├── nginx/
│   └── default.conf                      # site server block, fastcgi para .php, try_files
├── site/                                 # webroot (DocumentRoot)
│   ├── index.php                         # home
│   ├── voxcall/index.php
│   ├── voxzap/index.php
│   ├── politica-de-privacidade/index.php
│   ├── termos-de-uso/index.php
│   ├── components/                       # includes PHP reutilizáveis
│   │   ├── header.php
│   │   ├── footer.php
│   │   ├── cookie-banner.php             # LGPD (estilos + script + API window.VoxCookies)
│   │   └── voxkit.php                    # widget "Agendar por Voz" (botão flutuante + modal + iframe)
│   ├── assets/
│   │   ├── css/                          # style.css, header.css, hero.css, etc.
│   │   ├── js/                           # cookie-banner.js, etc.
│   │   └── img/                          # imagens do site
│   └── img/                              # logos (LogoVoxtel.svg, etc.)
└── voxtel-cc-bundle.tar.gz               # bundle gerado para deploy
```

### Convenções de inclusão de componentes

- Em `site/index.php` (raiz): `<?php include __DIR__ . '/components/<nome>.php'; ?>`
- Em `site/<rota>/index.php` (subpasta): `<?php include __DIR__ . '/../components/<nome>.php'; ?>`
- Ordem ao final do `<body>`: webchat → voxkit → cookie-banner (último)

---

## 3. Componente: Cookie Banner LGPD

`components/cookie-banner.php` injeta CSS inline + carrega `/assets/js/cookie-banner.js` que expõe a API global `window.VoxCookies`:

| Método | Comportamento |
|---|---|
| `VoxCookies.has(category)` | Retorna `true` se o usuário consentiu na categoria (`'functionality'`, `'analytics'`, etc.) |
| `VoxCookies.openSettings()` | Abre o modal de gestão de cookies |
| `data-vox-cookie-iframe-src="URL"` (atributo HTML) | iframe com este atributo só carrega `src` após consentimento |
| `<script type="text/plain" data-vox-cookie-category="...">` | Script só executa após consentimento |

**Padrão obrigatório para qualquer iframe/script de terceiros**: usar os atributos acima (não `src` direto).

---

## 4. Componente: VoxKit "Agendar por Voz"

`components/voxkit.php` — botão azul circular fixo (canto inferior direito, acima do botão de cookies) com ícone de microfone Font Awesome. Ao clicar:

1. Verifica `VoxCookies.has('functionality')`. Se NÃO consentido → abre `VoxCookies.openSettings()` e aborta.
2. Carrega o iframe `https://playvox.voxkit.voxserver.app.br` (lê de `data-vox-cookie-iframe-src`) na primeira abertura.
3. Mostra modal centralizado (850×650px, blur backdrop, fade-in 0.35s).
4. 500ms depois, dispara `.click()` no `.webchat-launcher-button` (integração com WebChat VoxZap).

Fechamento: botão X, click fora do modal, ou tecla ESC.

Estilos relevantes (todos inline no componente):
- Botão: `position: fixed; bottom: 110px; right: 20px; z-index: 1100; background: linear-gradient(135deg, #4a90e2, #357ABD);`
- Modal: `z-index: 1200; backdrop-filter: blur(12px);`

**Foi portado verbatim do `portalvoxtel.com.br`** para manter paridade visual e funcional. Mudanças visuais devem ser feitas em ambos os sites (ou consolidar a versão deste skill como source of truth).

---

## 5. Fluxo de Deploy

Pré-requisito: ter o `CLIENT_REGISTRY_KEY` no env (Replit Secrets) e o slug `planoclin` no cofre `.local/clients-vault.json`.

### Deploy completo (após qualquer edição em `.local/voxtel-cc-site/site/`)

```bash
# 1. Repacotar bundle (exclui baseline e tarballs antigos)
cd .local/voxtel-cc-site && tar --exclude=baseline --exclude='*.tar.gz' \
  -czf voxtel-cc-bundle.tar.gz Dockerfile docker-compose.yml .dockerignore site/ nginx/

# 2. Upload pro eveo1
node scripts/clients/upload.mjs planoclin \
  .local/voxtel-cc-site/voxtel-cc-bundle.tar.gz /tmp/voxtel-cc-bundle.tar.gz

# 3. Extrair + rebuild + restart no eveo1
node scripts/clients/ssh.mjs planoclin \
  "cd /opt/tenants/voxtel-cc && tar -xzf /tmp/voxtel-cc-bundle.tar.gz && docker compose up -d --build"
```

### Smoke test (sempre rodar após deploy)

```bash
# Home + 4 subpáginas devem responder 200 e conter os widgets esperados
for route in "/" "/voxcall/" "/voxzap/" "/politica-de-privacidade/" "/termos-de-uso/"; do
  echo "=== https://voxtel.cc${route} ==="
  curl -sk -o /dev/null -w "%{http_code}\n" "https://voxtel.cc${route}"
  curl -sk "https://voxtel.cc${route}" | grep -cE 'btnVoxKit|voxkitFrame|playvox\.voxkit'
done
# Esperado: 200 + 6 ocorrências cada
```

### Edição rápida de só um arquivo PHP (sem rebuild da imagem)

Se a mudança for só em `site/` (PHP/CSS/JS, sem mudar Dockerfile), é possível copiar direto pro container e pular rebuild:

```bash
# CUIDADO: o próximo deploy completo sobrescreve. Use só pra hotfix.
node scripts/clients/upload.mjs planoclin \
  .local/voxtel-cc-site/site/index.php /tmp/index.php
node scripts/clients/ssh.mjs planoclin \
  "docker cp /tmp/index.php voxtel-cc:/var/www/html/index.php"
```

### Restart sem rebuild

```bash
node scripts/clients/ssh.mjs planoclin "docker restart voxtel-cc"
```

### Health check

```bash
node scripts/clients/ssh.mjs planoclin "docker ps --filter name=voxtel-cc --format '{{.Status}}'"
# Esperado: "Up X minutes (healthy)"
```

---

## 6. Container & Imagem

### Dockerfile (resumo)

- Base: `nginx:alpine`
- Adiciona: `php82`, `php82-fpm`, `php82-session`, `supervisor`
- Symlink: `/usr/bin/php` → `/usr/bin/php82`
- Supervisor roda `nginx` + `php-fpm82` no foreground
- Webroot: `/var/www/html` (cópia de `./site/`)
- Healthcheck: `curl -f http://localhost/ || exit 1` a cada 30s

### docker-compose.yml (resumo)

```yaml
services:
  voxtel-cc:
    build: .
    container_name: voxtel-cc
    restart: unless-stopped
    networks: [nginx_net]
    expose: ["80"]
    mem_limit: 256m
    cpus: 0.5
    pids_limit: 128
    security_opt: ["no-new-privileges:true"]
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/"]
      interval: 30s
      timeout: 5s
      retries: 3

networks:
  nginx_net:
    external: true
    name: nginx_net
```

### nginx central (NÃO editar daqui — é compartilhado)

Em `/opt/tenants/nginx/conf.d/voxtel-cc.conf`:
- `server_name voxtel.cc www.voxtel.cc;`
- `listen 443 ssl http2;` com cert Let's Encrypt
- `proxy_pass http://voxtel-cc:80;`
- redirect 80→443

Para mexer no nginx central, ver skill `multi-tenant-server`.

---

## 7. Renovação do Certificado HTTPS

Cert atual válido até **2026-07-25**. Auto-renew via cron do certbot dentro do container `nginx-le` (também central).

Forçar renovação manual:

```bash
node scripts/clients/ssh.mjs planoclin \
  "docker exec nginx-le certbot renew --cert-name voxtel.cc --force-renewal && docker exec nginx reload"
```

---

## 8. Troubleshooting

| Sintoma | Diagnóstico | Fix |
|---|---|---|
| `502 Bad Gateway` | nginx central não acha o container | `docker network inspect nginx_net` — confirmar que `voxtel-cc` está na rede |
| Mudança no PHP não aparece | OPcache do php-fpm | `docker restart voxtel-cc` (no Dockerfile o opcache TTL é 60s, mas restart força) |
| Botão VoxKit não abre modal | Cookie consent não foi dado | Abrir DevTools → console — esperado: chamada de `VoxCookies.openSettings()` |
| iframe VoxKit não carrega | Atributo `src` não foi populado | Confirmar `data-vox-cookie-iframe-src` (não `src` direto) |
| Container reinicia em loop | Healthcheck falhando | `docker logs voxtel-cc --tail 50` — geralmente nginx config inválido |
| `permission denied` no deploy | SSH key/senha errada no cofre | Verificar `.local/clients-vault.json` slug `planoclin` |

---

## 9. Histórico de Tasks

- **#149 (MERGED)** — Redesign + dockerização inicial + deploy slot 4 + cookie banner em todas as 5 rotas + hardening
- **#150 (IN_PROGRESS)** — Migração do `portalvoxtel.com.br` para o mesmo padrão multi-tenant
- **Micro-tarefa abr/2026** — Portado widget VoxKit "Agendar por Voz" do `portalvoxtel.com.br` (componente `voxkit.php` reutilizável)

---

## 10. Cross-references

- `eveo-server-setup` — preparação do servidor eveo1 onde o site roda
- `multi-tenant-server` — arquitetura geral de tenants + nginx central + alocação de slots
- `client-server-access` — como o cofre `planoclin` funciona (SSH/upload helpers usados aqui)
- `voxtel-proposal-generator` — mesma marca/branding visual (Voxtel Telecomunicações), usar como referência de tom e cores
