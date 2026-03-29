---
name: s4e-crm
description: Especialista no banco de dados S4E/Izysoft — sistema de discagem e campanhas de cobrança/vendas que integra com a Ortoclin. Use quando precisar consultar, analisar ou gerar queries SQL para o banco MSSQL da S4E via VPN. Inclui mapeamento completo das tabelas, relacionamentos, campanhas de referência, e queries prontas.
---

# S4E / Izysoft — Mapeamento Completo do Banco de Dados

## Visão Geral

O **S4E (Izysoft)** é um sistema de **discagem automática e gestão de campanhas** utilizado para cobrança, vendas e agendamento. O banco de dados `Izysoft` é o ponto de integração que recebe listas de prospects (devedores/clientes) organizados por campanhas para processamento pelo discador.

### Escala do Banco
- **2 tabelas** principais: `Campanha` e `tb_Izzy`
- **80 campanhas** configuradas (PF, PJ, Key Account, Corporate, Middle, PME)
- **0 stored procedures** (operações feitas via INSERT/SELECT direto)
- **0 views** (consultas diretas nas tabelas)
- **1 foreign key**: `tb_Izzy.cd_campanha` → `Campanha.cd_campanha`

### Contexto do Sistema

O sistema S4E opera como um **discador automático** que:
1. Recebe listas de prospects carregados na tabela `tb_Izzy`
2. Organiza por campanhas (tabela `Campanha`)
3. Realiza discagem automática baseada em prioridade, horários e canais
4. Suporta campanhas de cobrança (PF/PJ por faixas de atraso) e campanhas especiais (pós-venda, renovação, agendamento)

O servidor MSSQL hospeda múltiplos bancos, mas o usuário `izysoft.ricardo` tem acesso apenas ao banco `Izysoft`. Outros bancos no servidor (Ortoclin, IntegracaoS4E, ClinApps, Agiben, etc.) pertencem à infraestrutura clínica/dental da Ortoclin.

## Conexão

| Parâmetro | Valor |
|-----------|-------|
| **Tipo** | Microsoft SQL Server |
| **Database** | `Izysoft` |
| **Método** | VPN + SSH Tunnel + driver `mssql` (tedious) |
| **Host MSSQL** | `172.22.138.24` (rede interna via VPN) |
| **Porta** | `1433` (padrão) |
| **VPN Necessária** | Sim — VPN config `vpn_1` na VPS (OpenVPN) |
| **VPN IP** | `10.8.0.46` (tun0) |
| **Rota Necessária** | `172.22.138.0/24 via 10.8.0.1 dev tun0` |
| **Usuário** | Usar scratchpad do agente (izysoft.ricardo) |
| **Senha** | Usar scratchpad do agente |

> **SEGURANÇA:** Credenciais NUNCA devem ser incluídas em código-fonte. Consultar o scratchpad do agente para valores reais.

### Arquitetura de Acesso

```
App (Replit) → SSH Tunnel (VPS:22300) → VPN (tun0) → MSSQL (172.22.138.24:1433)
```

**Pré-requisitos:**
1. VPN `vpn_1` ativa na VPS (verificar com `/api/vpn/status`)
2. Rota `172.22.138.0/24` via tun0 (configurada no .ovpn com `route 172.22.138.0 255.255.255.0 vpn_gateway`)
3. SSH tunnel do Replit para a VPS usando `ssh2`
4. Driver `mssql` (tedious) com `encrypt: false`, `trustServerCertificate: true`

### Padrão de Conexão via SSH Tunnel (Node.js)

```javascript
const sql = require('mssql');
const { Client: SSHClient } = require('ssh2');
const net = require('net');

function createSSHTunnel(sshConfig, targetHost, targetPort, localPort) {
  return new Promise((resolve, reject) => {
    const sshClient = new SSHClient();
    sshClient.on('ready', () => {
      const server = net.createServer((sock) => {
        sshClient.forwardOut(
          sock.remoteAddress || '127.0.0.1',
          sock.remotePort || 0,
          targetHost,
          targetPort,
          (err, stream) => {
            if (err) { sock.end(); return; }
            sock.pipe(stream).pipe(sock);
          }
        );
      });
      server.listen(localPort, '127.0.0.1', () => resolve({ server, sshClient }));
    });
    sshClient.on('error', reject);
    sshClient.connect({ ...sshConfig, readyTimeout: 15000 });
  });
}

const tunnel = await createSSHTunnel(
  { host: SSH_HOST, port: SSH_PORT, username: SSH_USER, password: SSH_PASS },
  '172.22.138.24', 1433, 14330
);

const pool = await sql.connect({
  server: '127.0.0.1',
  port: 14330,
  database: 'Izysoft',
  user: '***',
  password: '***',
  options: { encrypt: false, trustServerCertificate: true, requestTimeout: 30000 }
});
```

## Modelo de Dados

### Tabela: Campanha (80 registros)

Configuração das campanhas de discagem. Cada campanha define um segmento de prospects.

| Coluna | Tipo | Nullable | Descrição |
|--------|------|----------|-----------|
| **cd_campanha** | `smallint` | NO | **PK** — Código da campanha |
| **ds_campanha** | `varchar(100)` | NO | Descrição/nome da campanha |
| **tp_empresa** | `smallint` | YES | Tipo empresa: 1=PF, 2=PJ |
| **qt_dias** | `smallint` | YES | Quantidade de dias (período) |
| **hr_inicial** | `int` | YES | Hora inicial de discagem |
| **hr_final** | `int` | YES | Hora final de discagem |
| **qt_canais** | `smallint` | YES | Quantidade de canais simultâneos |
| **mensagem_ura** | `varchar(200)` | YES | Mensagem da URA |
| **nm_script** | `varchar(50)` | YES | Nome do script de atendimento |
| **cd_tipo_campanha** | `smallint` | NO | Tipo da campanha (1=padrão) |
| **cd_origem_campanha** | `tinyint` | YES | Origem da campanha (1=padrão) |
| **fl_recarregar_dados** | `bit` | YES | Flag para recarregar dados |
| **cd_prioridade** | `smallint` | YES | Prioridade (1=alta, 2=normal) |
| **tsoId** | `smallint` | YES | ID do TSO (operação) |
| **cd_ordem_campanha** | `tinyint` | YES | Ordem de processamento |
| **fl_discarDDD** | `bit` | YES | Flag para discar com DDD |
| **resetManual** | `bit` | YES | Reset manual dos prospects |
| **excluirProspect** | `bit` | YES | Flag para excluir prospect |
| **dataVigencia** | `datetime` | YES | Data de vigência |
| **marcacaoConsulta** | `bit` | YES | Flag de marcação de consulta |
| **cobranca** | `bit` | YES | Flag de cobrança |

**Índices:**
- `PK_Campanha` — CLUSTERED PRIMARY KEY em `cd_campanha`

### Tabela: tb_Izzy (0 registros — tabela transitória)

Tabela principal que recebe os dados de prospects para processamento pelo discador. Cada registro é um prospect vinculado a uma campanha. **Nota:** A contagem de registros é tipicamente 0 porque os dados são transitórios — prospects são carregados periodicamente pelo ERP, processados pelo discador, e removidos após conclusão.

| Coluna | Tipo | Nullable | Descrição |
|--------|------|----------|-----------|
| **id** | `bigint` | NO | **PK** — ID auto-incremento |
| **cd_campanha** | `smallint` | NO | **FK** → Campanha.cd_campanha |
| **ID_ERP_CRM** | `bigint` | YES | ID do registro no ERP/CRM origem |
| **Nome_Prospect** | `varchar(1000)` | NO | Nome completo do prospect |
| **DtNascimento** | `datetime` | YES | Data de nascimento |
| **CPF_CNPJ** | `varchar(14)` | YES | CPF ou CNPJ |
| **RG_CGF** | `varchar(200)` | YES | RG ou CGF |
| **email** | `varchar(1000)` | YES | E-mail |
| **sexo** | `smallint` | YES | Sexo (código) |
| **Logradouro** | `varchar(1000)` | YES | Endereço |
| **Complemento** | `varchar(500)` | YES | Complemento |
| **Bairro** | `varchar(1000)` | YES | Bairro |
| **cep** | `varchar(8)` | YES | CEP |
| **cidade** | `varchar(1000)` | YES | Cidade |
| **estado** | `varchar(2)` | YES | UF |
| **Data_ERP_CRM** | `datetime` | YES | Data do registro no ERP/CRM |
| **Telefone_Contato_1** | `varchar(100)` | YES | Telefone principal |
| **Telefone_Contato_2** | `varchar(100)` | YES | Telefone alternativo 1 |
| **Telefone_Contato_3** | `varchar(100)` | YES | Telefone alternativo 2 |
| **Contato_1** | `varchar(1000)` | YES | Nome do contato |
| **Numero_Titulo** | `varchar(1000)` | YES | Número do título/contrato |
| **Tipo_Titulo** | `varchar(1000)` | YES | Tipo do título |
| **Data_Titulo** | `datetime` | YES | Data do título |
| **Valor_Titulo** | `money` | YES | Valor do título |
| **Produto** | `varchar(1000)` | YES | Produto/serviço |
| **Filial** | `varchar(1000)` | YES | Filial |
| **Dia_Vencimento** | `smallint` | YES | Dia de vencimento |
| **Informacao_Adicional_1** | `varchar(1000)` | YES | Info adicional 1 |
| **Informacao_Adicional_2** | `varchar(1000)` | YES | Info adicional 2 |
| **Informacao_Adicional_3** | `varchar(1000)` | YES | Info adicional 3 |
| **Auxiliar_1** | `varchar(1000)` | YES | Campo auxiliar 1 |
| **Auxiliar_2** | `varchar(1000)` | YES | Campo auxiliar 2 |
| **Auxiliar_3** | `varchar(1000)` | YES | Campo auxiliar 3 |
| **Agrupador** | `int` | YES | Código agrupador |
| **Dt_Atendimento** | `datetime` | YES | Data do atendimento |
| **Nm_Funcionario** | `varchar(100)` | YES | Nome do funcionário |
| **Nm_Clinica** | `varchar(100)` | YES | Nome da clínica |
| **Cd_empresa** | `int` | YES | Código da empresa |
| **Cd_centro_custo** | `smallint` | YES | Código centro de custo |
| **cd_tipo_campanha** | `smallint` | YES | Tipo da campanha |
| **DS_tipo_campanha** | `varchar(50)` | YES | Descrição do tipo |
| **cd_parcela** | `int` | YES | Código da parcela |
| **cd_sequencial_agenda** | `int` | YES | Sequencial da agenda |
| **dt_ordenacao** | `datetime` | YES | Data para ordenação |
| **cd_sequencial_dep** | `int` | YES | Sequencial do dependente |

**Total: 45 colunas**

**Índices:**
- `PK_Izzy` — CLUSTERED PRIMARY KEY em `id`

**Foreign Keys:**
- `FK_tb_Izzy_Campanha` — `tb_Izzy.cd_campanha` → `Campanha.cd_campanha`

## Relacionamentos

```
Campanha (1) ←─── (N) tb_Izzy
   cd_campanha ←──── cd_campanha (FK)
```

## Dados de Referência — Campanhas

### Campanhas PF (Pessoa Física) — tp_empresa = 1

| Faixa de Atraso | Códigos | Observações |
|-----------------|---------|-------------|
| 3-30 dias | 1, 2, 3, 4, 5 | Inclui variantes por dia vencimento (15, 20, 25) e Cartão |
| 31-60 dias | 11, 12, 13, 14, 15 | Inclui variantes por dia vencimento e Cartão |
| 61-90 dias | 21, 22 | PF e Cartão |
| 91-180 dias | 31, 32 | PF e Cartão |
| Superior 180 dias | 41, 42 | PF e Cartão |
| Inadimplente Cartão | 59 | Específico cartão |
| Suspensos | 60 | PF suspensos |
| Renovação Cartão | 61 | Renovação |
| Pré-cadastro Boleto | 62 | PF pré-cadastro |

### Campanhas PJ (Pessoa Jurídica) — tp_empresa = 2 (exceto onde indicado)

| Faixa de Atraso | Códigos | Observações |
|-----------------|---------|-------------|
| 3-30 dias | 101, 102, 103, 104, 105 | Inclui variantes por dia vencimento |
| 31-60 dias | 111, 112, 113, 114, 115 | Inclui variantes por dia vencimento |
| 61-90 dias | 121 | PJ |
| 91-180 dias | 131 | PJ |
| Superior 180 dias | 141 | PJ |
| Pós-venda | 142, 143 | Sem/com vendedor |
| Suspensos | 160 | PJ suspensos |
| Pré-cadastro Boleto | 162 | PJ pré-cadastro |

### Campanhas Especiais

| Tipo | Códigos | Descrição |
|------|---------|-----------|
| Abandono Carrinho | 164 | PF abandono de carrinho |
| Aguardando Pagamento | 163 | PF site |
| Key Account | 311, 321, 331 | Cobrança por faixa (3-30, 31-60, 61-90, 91-180) |
| Corporate | 312, 322, 332 | Cobrança corporate por faixa |
| Middle | 313, 323, 333 | Cobrança middle por faixa |
| PME | 314, 324, 334 | Cobrança PME por faixa |

## Glossário de Domínio

| Termo | Significado |
|-------|-------------|
| **Prospect** | Pessoa (física ou jurídica) cadastrada para contato pelo discador |
| **Campanha** | Agrupamento lógico de prospects com regras de discagem (horário, canais, prioridade) |
| **PF** | Pessoa Física (tp_empresa = 1) |
| **PJ** | Pessoa Jurídica (tp_empresa = 2) |
| **Faixa de atraso** | Classificação por dias de inadimplência (3-30, 31-60, 61-90, 91-180, >180) |
| **Discador** | Sistema automático que liga para os prospects carregados na tb_Izzy |
| **URA** | Unidade de Resposta Audível — mensagem automática tocada na ligação |
| **TSO** | Tipo de Serviço/Operação — agrupa campanhas por tipo de atendimento |
| **Script** | Roteiro de atendimento que o operador segue durante a ligação |
| **Canal** | Linha telefônica simultânea usada pelo discador |
| **Título** | Documento financeiro (boleto, parcela, contrato) em cobrança |
| **Agrupador** | Código que agrupa múltiplos registros do mesmo devedor |
| **ID_ERP_CRM** | ID do registro no sistema de origem (Ortoclin, etc.) |
| **Centro de custo** | Unidade contábil/departamento responsável |
| **Key Account** | Conta-chave — clientes PJ de alto valor |
| **Corporate** | Clientes PJ corporativos |
| **Middle** | Clientes PJ de porte médio |
| **PME** | Pequenas e Médias Empresas |
| **Pós-venda** | Campanha de acompanhamento após venda realizada |
| **Pré-cadastro** | Prospect em fase de cadastro inicial |
| **Abandono de carrinho** | Prospect que iniciou compra online mas não finalizou |
| **Recarregar dados** | Flag para indicar que a campanha deve reimportar dados do ERP |
| **Reset manual** | Flag para reiniciar manualmente o ciclo de discagem dos prospects |

## Regras de Segurança

1. **Somente SELECT** — NUNCA executar INSERT, UPDATE, DELETE, DROP, ALTER, EXEC
2. **Sempre TOP N** — Limitar resultados com `TOP 100` ou menos
3. **Sanitizar input** — Nunca interpolar valores diretamente na query
4. **Mascarar dados pessoais:**
   - CPF: `LEFT(CPF_CNPJ, 3) + '.***.***-' + RIGHT(CPF_CNPJ, 2)`
   - Telefone: exibir apenas DDD + últimos 4 dígitos
   - Email: mascarar com `LEFT(email, 2) + '***@***'`
5. **VPN obrigatória** — Verificar status da VPN antes de tentar conexão
6. **Credenciais do scratchpad** — Nunca hardcoded

## Queries de Referência

### 1. Listar campanhas por tipo (PF/PJ)
```sql
SELECT cd_campanha, ds_campanha, tp_empresa,
  CASE tp_empresa WHEN 1 THEN 'PF' WHEN 2 THEN 'PJ' ELSE 'Outro' END AS tipo
FROM Campanha
ORDER BY cd_campanha
```

### 2. Contar prospects por campanha
```sql
SELECT c.cd_campanha, c.ds_campanha, COUNT(t.id) AS total_prospects
FROM Campanha c
LEFT JOIN tb_Izzy t ON c.cd_campanha = t.cd_campanha
GROUP BY c.cd_campanha, c.ds_campanha
ORDER BY total_prospects DESC
```

### 3. Buscar prospect por CPF (mascarado)
```sql
SELECT TOP 10
  id, cd_campanha, Nome_Prospect,
  LEFT(CPF_CNPJ, 3) + '.***.***-' + RIGHT(CPF_CNPJ, 2) AS CPF_Mascarado,
  Telefone_Contato_1, Valor_Titulo, Data_Titulo
FROM tb_Izzy
WHERE CPF_CNPJ = @cpf
```

### 4. Prospects com títulos de maior valor
```sql
SELECT TOP 20
  id, Nome_Prospect, Valor_Titulo, Numero_Titulo,
  Tipo_Titulo, Data_Titulo, cd_campanha
FROM tb_Izzy
ORDER BY Valor_Titulo DESC
```

### 5. Prospects por cidade/estado
```sql
SELECT estado, cidade, COUNT(*) AS total
FROM tb_Izzy
WHERE estado IS NOT NULL
GROUP BY estado, cidade
ORDER BY total DESC
```

### 6. Resumo de campanhas por faixa de atraso
```sql
SELECT
  CASE
    WHEN ds_campanha LIKE '%03 a 30%' OR ds_campanha LIKE '%7 a 30%' THEN '3-30 dias'
    WHEN ds_campanha LIKE '%31 a 60%' THEN '31-60 dias'
    WHEN ds_campanha LIKE '%61 a 90%' THEN '61-90 dias'
    WHEN ds_campanha LIKE '%91 a 180%' THEN '91-180 dias'
    WHEN ds_campanha LIKE '%Superior%180%' THEN '>180 dias'
    ELSE 'Especial'
  END AS faixa_atraso,
  COUNT(*) AS total_campanhas,
  SUM(CASE WHEN tp_empresa = 1 THEN 1 ELSE 0 END) AS campanhas_PF,
  SUM(CASE WHEN tp_empresa = 2 THEN 1 ELSE 0 END) AS campanhas_PJ
FROM Campanha
GROUP BY
  CASE
    WHEN ds_campanha LIKE '%03 a 30%' OR ds_campanha LIKE '%7 a 30%' THEN '3-30 dias'
    WHEN ds_campanha LIKE '%31 a 60%' THEN '31-60 dias'
    WHEN ds_campanha LIKE '%61 a 90%' THEN '61-90 dias'
    WHEN ds_campanha LIKE '%91 a 180%' THEN '91-180 dias'
    WHEN ds_campanha LIKE '%Superior%180%' THEN '>180 dias'
    ELSE 'Especial'
  END
ORDER BY faixa_atraso
```

### 7. Prospects duplicados (mesmo CPF em campanhas diferentes)
```sql
SELECT TOP 50
  CPF_CNPJ,
  LEFT(CPF_CNPJ, 3) + '.***.***-' + RIGHT(CPF_CNPJ, 2) AS CPF_Mascarado,
  COUNT(*) AS total_ocorrencias,
  COUNT(DISTINCT cd_campanha) AS campanhas_distintas,
  STRING_AGG(CAST(cd_campanha AS VARCHAR), ', ') AS campanhas
FROM tb_Izzy
WHERE CPF_CNPJ IS NOT NULL AND CPF_CNPJ <> ''
GROUP BY CPF_CNPJ
HAVING COUNT(*) > 1
ORDER BY total_ocorrencias DESC
```

### 8. Qualidade dos dados — campos nulos por coluna
```sql
SELECT
  COUNT(*) AS total_registros,
  SUM(CASE WHEN CPF_CNPJ IS NULL OR CPF_CNPJ = '' THEN 1 ELSE 0 END) AS sem_cpf,
  SUM(CASE WHEN Telefone_Contato_1 IS NULL OR Telefone_Contato_1 = '' THEN 1 ELSE 0 END) AS sem_tel1,
  SUM(CASE WHEN Telefone_Contato_2 IS NULL OR Telefone_Contato_2 = '' THEN 1 ELSE 0 END) AS sem_tel2,
  SUM(CASE WHEN email IS NULL OR email = '' THEN 1 ELSE 0 END) AS sem_email,
  SUM(CASE WHEN Valor_Titulo IS NULL THEN 1 ELSE 0 END) AS sem_valor,
  SUM(CASE WHEN Data_Titulo IS NULL THEN 1 ELSE 0 END) AS sem_data_titulo,
  SUM(CASE WHEN Logradouro IS NULL OR Logradouro = '' THEN 1 ELSE 0 END) AS sem_endereco
FROM tb_Izzy
```

### 9. Prospects por clínica/funcionário
```sql
SELECT TOP 30
  Nm_Clinica, Nm_Funcionario,
  COUNT(*) AS total_prospects,
  SUM(ISNULL(Valor_Titulo, 0)) AS valor_total
FROM tb_Izzy
WHERE Nm_Clinica IS NOT NULL
GROUP BY Nm_Clinica, Nm_Funcionario
ORDER BY total_prospects DESC
```

### 10. Volume de títulos por faixa de valor
```sql
SELECT
  CASE
    WHEN Valor_Titulo IS NULL THEN 'Sem valor'
    WHEN Valor_Titulo <= 100 THEN 'Até R$100'
    WHEN Valor_Titulo <= 500 THEN 'R$101-500'
    WHEN Valor_Titulo <= 1000 THEN 'R$501-1000'
    WHEN Valor_Titulo <= 5000 THEN 'R$1001-5000'
    ELSE 'Acima R$5000'
  END AS faixa_valor,
  COUNT(*) AS total,
  SUM(ISNULL(Valor_Titulo, 0)) AS valor_total
FROM tb_Izzy
GROUP BY
  CASE
    WHEN Valor_Titulo IS NULL THEN 'Sem valor'
    WHEN Valor_Titulo <= 100 THEN 'Até R$100'
    WHEN Valor_Titulo <= 500 THEN 'R$101-500'
    WHEN Valor_Titulo <= 1000 THEN 'R$501-1000'
    WHEN Valor_Titulo <= 5000 THEN 'R$1001-5000'
    ELSE 'Acima R$5000'
  END
ORDER BY valor_total DESC
```

### 11. Prospects carregados por dia (análise de carga)
```sql
SELECT TOP 30
  CONVERT(DATE, Data_ERP_CRM) AS data_carga,
  COUNT(*) AS registros_carregados,
  COUNT(DISTINCT cd_campanha) AS campanhas_distintas
FROM tb_Izzy
WHERE Data_ERP_CRM IS NOT NULL
GROUP BY CONVERT(DATE, Data_ERP_CRM)
ORDER BY data_carga DESC
```

### 12. Campanhas com prioridade alta vs normal
```sql
SELECT
  cd_prioridade,
  CASE cd_prioridade WHEN 1 THEN 'Alta' WHEN 2 THEN 'Normal' ELSE 'Outro' END AS prioridade,
  COUNT(*) AS total_campanhas,
  STRING_AGG(ds_campanha, ', ') AS campanhas
FROM Campanha
GROUP BY cd_prioridade
ORDER BY cd_prioridade
```

## Inventário Completo de Bancos no Servidor

O servidor MSSQL em 172.22.138.24 hospeda **25 bancos de dados**. O usuário `izysoft.ricardo` tem acesso **apenas** ao banco `Izysoft` (e system DBs master/msdb/tempdb).

| # | Banco | DB ID | Status | Acesso | Descrição Provável |
|---|-------|-------|--------|--------|-------------------|
| 1 | **Izysoft** | 19 | ONLINE | **SIM** | Banco de integração S4E — discador/campanhas |
| 2 | master | 1 | ONLINE | SIM (system) | Banco de sistema SQL Server |
| 3 | msdb | 4 | ONLINE | SIM (system) | Jobs e alertas SQL Server |
| 4 | tempdb | 2 | ONLINE | SIM (system) | Tabelas temporárias |
| 5 | model | 3 | ONLINE | NÃO | Template para novos bancos |
| 6 | Ortoclin | 5 | ONLINE | NÃO | Sistema clínico/dental principal |
| 7 | OrtoclinLog | 9 | ONLINE | NÃO | Logs do Ortoclin |
| 8 | Ortoclin_Site | 23 | ONLINE | NÃO | Site web Ortoclin |
| 9 | IntegracaoS4E | 8 | ONLINE | NÃO | Integração entre Ortoclin e S4E |
| 10 | ClinApps | 15 | ONLINE | NÃO | Aplicações clínicas |
| 11 | ClinAppsElmah | 20 | ONLINE | NÃO | Logs de erro (Elmah) das apps clínicas |
| 12 | ClinBeneficiarioJobs | 18 | ONLINE | NÃO | Jobs de beneficiários |
| 13 | ClinDentistaJobs | 16 | ONLINE | NÃO | Jobs de dentistas |
| 14 | ClinEmpresaJobs | 17 | ONLINE | NÃO | Jobs de empresas |
| 15 | ClinfluencerDB | 21 | ONLINE | NÃO | Sistema influenciadores clínicos |
| 16 | ClintechAgenda | 14 | ONLINE | NÃO | Agendamento Clintech |
| 17 | CredenciamentoAPI | 22 | ONLINE | NÃO | API de credenciamento |
| 18 | Agiben | 10 | ONLINE | NÃO | Sistema de benefícios |
| 19 | AgibenLog | 6 | ONLINE | NÃO | Logs do Agiben |
| 20 | Agisales | 24 | ONLINE | NÃO | Sistema de vendas |
| 21 | AgisalesLog | 25 | ONLINE | NÃO | Logs do Agisales |
| 22 | APIMercantil | 12 | ONLINE | NÃO | API Mercantil |
| 23 | APIMercantilLog | 7 | ONLINE | NÃO | Logs API Mercantil |
| 24 | Melhorai | 13 | ONLINE | NÃO | Sistema Melhor.ai |
| 25 | MelhoraiLog | 11 | ONLINE | NÃO | Logs do Melhor.ai |

## Troubleshooting

### Erro: "Login failed for user"
- O usuário só tem acesso ao banco `Izysoft`. Usar `database: 'Izysoft'` na config.

### Erro: Conexão timeout
1. Verificar se VPN está ativa: `GET /api/vpn/1/status`
2. Verificar rota: `ip route show dev tun0` deve incluir `172.22.138.0/24 via 10.8.0.1`
3. Testar ping: `ping -c 2 172.22.138.24`
4. Se rota ausente: `ip route add 172.22.138.0/24 via 10.8.0.1 dev tun0`

### Erro: "Cannot reach MSSQL"
- VPN pode ter reconectado sem rota. Rota está configurada no .ovpn (`route 172.22.138.0 255.255.255.0 vpn_gateway`) mas verificar se está ativa.

### tb_Izzy está vazia (0 registros)
- Normal: a tabela é carregada periodicamente com novos prospects e esvaziada após processamento pelo discador.
- Os dados são transitórios — prospects são inseridos, processados, e removidos.
