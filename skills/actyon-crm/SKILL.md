---
name: actyon-crm
description: Especialista no banco de dados Actyon Smartcob — sistema CRM/ERP de cobrança e recuperação de crédito. Use quando precisar consultar, analisar ou gerar queries SQL para o banco MSSQL do Actyon. Inclui mapeamento completo de 236 tabelas, relacionamentos, stored procedures, dados de referência, e queries prontas para o Assistente de IA.
---

# Actyon Smartcob — Mapeamento Completo do Banco de Dados

## Visão Geral

O **Actyon Smartcob** é um sistema CRM/ERP de **cobrança e recuperação de crédito** que gerencia todo o ciclo de cobrança: desde a importação de carteiras de títulos inadimplentes, passando pela distribuição em filas de trabalho, acionamento de devedores (ligações, SMS, email, WhatsApp), negociação de acordos, emissão de boletos, até o controle de pagamentos e prestação de contas aos credores.

### Escala do Banco
- **236 tabelas** (BASE TABLE) + 2 views
- **~180 stored procedures**
- **Registros principais:** 107K devedores, 446K títulos, 98K acordos, 3.7M acionamentos, 363K pagamentos, 25M logs

## Conexão

| Parâmetro | Valor |
|-----------|-------|
| **Tipo** | Microsoft SQL Server |
| **Database** | `dbActyon_Smartcob` |
| **Método Primário** | Conexão direta via driver `mssql` (tedious) do Node.js |
| **Host Direto** | `189.36.205.250` |
| **Porta Direta** | `31433` (regra firewall cliente) |
| **Método Alternativo** | SSH + ODBC (isql/FreeTDS) via VPS gateway |
| **DSN ODBC** | `mssql` (FreeTDS, TDS Version 7.3) |
| **Usuário** | Usar variável de ambiente ou scratchpad do agente |
| **Senha** | Usar variável de ambiente ou scratchpad do agente |
| **Conexão no App** | Nome "SmartCob", access_method="direct", configurada em `/external-connections` |

> **SEGURANÇA:** Credenciais de banco e SSH NUNCA devem ser incluídas em código-fonte ou documentação. Consultar o scratchpad do agente para valores reais. Em produção, usar variáveis de ambiente ou secret manager.

### Métodos de Acesso

**1. Conexão Direta (RECOMENDADO — ~1-2s por query)**
```
App (Node.js) → driver mssql/tedious → MSSQL (189.36.205.250:31433)
```
- Mais rápido, sem intermediários
- Configurado como `accessMethod: 'direct'` na tabela `external_db_connections`
- Driver: `mssql` (tedious) com `encrypt: false`, `trustServerCertificate: true`

**2. SSH + ODBC (fallback — ~5-8s por query)**
```
App → SSH (VPS) → isql -v mssql → FreeTDS/ODBC → MSSQL
```
- Usado quando acesso direto não é possível
- Delimitador de saída: `~` (til) para evitar conflito com vírgulas nos dados
- Parsing: extrair colunas do SQL, filtrar banner isql, split por `~`

### ODBC Config (VPS `/etc/odbc.ini`) — apenas para método SSH+ODBC
```ini
[mssql]
Description = MSSQL Server
Driver = FreeTDS
Server = ${ACTYON_MSSQL_HOST}
Port = 1433
Database = dbActyon_Smartcob
TDS_Version = 7.3
```

### Padrão de Execução de Query

**REGRAS DE SEGURANÇA OBRIGATÓRIAS:**
1. Sempre sanitizar input do usuário — NUNCA interpolar valores diretamente na query
2. Validar formato esperado (ex: CPF aceitar apenas dígitos, DEVEDOR_ID aceitar apenas números)
3. Queries devem ser SOMENTE `SELECT` com `TOP N` (máximo 100)
4. Nunca permitir `;`, `--`, `/*`, `DROP`, `DELETE`, `INSERT`, `UPDATE`, `ALTER`, `EXEC` no input
5. Credenciais devem vir do scratchpad do agente, NUNCA hardcoded em código
6. Mascarar CPF na saída: `LEFT(CPF, 3) + '.***.***-' + RIGHT(CPF, 2)`
7. Mascarar telefone na saída: exibir apenas DDD e últimos 4 dígitos

**Acesso ao banco:** Via SSH na VPS usando `isql -v mssql <user> <pass>` (credenciais no scratchpad do agente). As queries são enviadas via `isql` (FreeTDS ODBC) e retornam resultado em formato pipe-delimited.

**Funções de sanitização:**
```javascript
function sanitizeInput(val, type) {
  if (typeof val !== "string") val = String(val);
  val = val.substring(0, 100);
  if (type === "cpf") return val.replace(/[^0-9]/g, "");
  if (type === "id") return val.replace(/[^0-9]/g, "");
  if (type === "name") return val.replace(/[^a-zA-ZÀ-ÿ\s]/g, "").trim();
  return val.replace(/['";\\\/\*\-]/g, "").replace(/DROP|DELETE|INSERT|UPDATE|ALTER|EXEC/gi, "").trim();
}

function validateSelectOnly(sql) {
  const normalized = sql.trim().toUpperCase();
  if (!normalized.startsWith("SELECT")) throw new Error("Somente queries SELECT são permitidas");
  if (/\b(DROP|DELETE|INSERT|UPDATE|ALTER|EXEC|EXECUTE)\b/i.test(sql)) throw new Error("Operação proibida detectada");
  return true;
}
```

**Consulta de schema dinâmica:** Para obter a lista completa de colunas de qualquer tabela:
```sql
SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = '<nome_tabela>'
ORDER BY ORDINAL_POSITION
```

## Glossário do Domínio de Cobrança

| Termo | Significado |
|-------|-------------|
| **Devedor** | Pessoa (PF/PJ) que possui dívidas em aberto |
| **Título** | Um débito individual (parcela, boleto, carne, conta) vinculado a um devedor |
| **Contratante/Credor** | Empresa que delegou a carteira de cobrança para a assessoria |
| **Cobrador/Operador** | Funcionário que realiza a cobrança (ligações, negociação) |
| **Acionamento** | Cada contato/tentativa de contato com o devedor (ligação, SMS, email) |
| **Acordo** | Negociação fechada — parcelas, entrada, descontos, forma de pagamento |
| **Fila** | Carteira de devedores distribuída para um cobrador trabalhar |
| **Campanha** | Conjunto de regras especiais (descontos, ofertas) por período |
| **CNAB** | Arquivo bancário padronizado para remessa/retorno de boletos |
| **Fase** | Etapa do processo de cobrança (amigável, jurídica, etc.) |
| **Assessoria** | Empresa de cobrança terceirizada que atua na recuperação |
| **Renitência** | Regra de tentativas repetidas de contato com escalonamento |
| **Situação de Cobrança** | Status atual do devedor (em cobrança, acordo, incobrável, etc.) |
| **Score/Behavior** | Pontuação de propensão a pagar / comportamento do devedor |
| **Baixa** | Encerramento de um título (pagamento, devolução, acordo) |
| **Repasse** | Transferência de valores recebidos para o contratante/credor |
| **Honorário** | Comissão da assessoria sobre valores recuperados |
| **Prestação de Contas** | Relatório de valores recuperados enviado ao contratante |
| **Screen Pop** | Exibição automática da ficha do devedor quando uma ligação entra |
| **CPC** | Contato com a Pessoa Certa — devedor atendeu pessoalmente |

## Diagrama de Relacionamentos (ERD Simplificado)

```
                        tbcontratante (Credor)
                              │
                    ┌─────────┼─────────┐
                    │         │         │
              tbformula   tbregra   tbimportacao
                              │         │
                              │         │
    tbequipe ─── tbcobrador   │    ┌────┘
        │            │        │    │
        │            │        ▼    ▼
        │            └──► tbdevedor ◄──── tbdevedor_fone
        │                     │           tbdevedor_endereco
        │                     │           tbdevedor_email
        │                     │           tbdevedor_avalista
        │                     │           tbdevedor_acionamento
        │                     │           tbdevedor_cobrador
        │                     │           tbdevedor_calculo
        │                     │           tbdevedor_processo_juridico
        │                     │           tbdevedor_mensagem
        │                     │           tbdevedor_questionario
        │                     │
        │                     ▼
        │               tbtitulo ◄──── tbtipo_titulo
        │                  │  │        tbacao_cobranca
        │                  │  │        tbtitulo_calculo
        │                  │  │        tbtitulo_boleto
        │                  │  │        tbtitulo_contrato
        │                  │  │        tbtitulo_garantia
        │                  │  │        tbtitulo_acionamento
        │                  │  │        tbtitulo_pago
        │                  │  │
        │                  │  └──► tbfila ──► tbfila_cobrador
        │                  │
        │                  ▼
        │              tbacordo ◄──── tbacordo_titulos
        │                             tbacordo_forma_pagamento
        │                             tbacordo_comissao
        │                             tbacordo_repasse
        │                             tbacordo_pre
        │
        └──► tbcobrador_ramal
             tbcobrador_pausa
             tbcobrador_equipe
```

## Tabelas Principais — Volume de Dados

| Tabela | Registros | Descrição |
|--------|-----------|-----------|
| `tbdevedor` | 107.932 | Cadastro de devedores (PF/PJ) |
| `tbtitulo` | 446.591 | Títulos de dívida |
| `tbacordo` | 98.377 | Acordos de negociação |
| `tbdevedor_acionamento` | 3.732.554 | Histórico de acionamentos |
| `tbdevedor_fone` | 261.292 | Telefones dos devedores |
| `tbtitulo_pago` | 363.690 | Títulos pagos |
| `tblog` | 25.199.350 | Log de auditoria do sistema |
| `tbtitulo_calculo` | 99.557 | Cálculos de valores dos títulos |
| `tbacordo_titulos` | 194.571 | Títulos vinculados a acordos |
| `tbcontratante` | 202 | Credores/Contratantes |
| `tbcobrador` | 234 | Cobradores/Operadores |
| `tboperador` | 301 | Operadores do sistema |
| `tbdevedor_endereco` | 7.164 | Endereços |
| `tbdevedor_email` | 26.291 | Emails |
| `tbacao_cobranca` | 14.773 | Ações de cobrança |
| `tbsituacao_cobranca` | 47 | Situações de cobrança |
| `tbtipo_titulo` | 45 | Tipos de título |
| `tbfila` | 17.447 | Filas de cobrança |
| `tbimportacao` | 6.344 | Importações de carteiras |
| `tbequipe` | 38 | Equipes de cobrança |

## Mapeamento Completo de Colunas

### tbdevedor (72 colunas) — Cadastro de Devedores
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| DEVEDOR_ID | bigint | | PK | ID único do devedor |
| NOME | varchar | 55 | X | Nome completo |
| CPF | varchar | 14 | X | CPF ou CNPJ |
| TIPO_PESSOA | char | 1 | | F=Física, J=Jurídica |
| ENDERECO | varchar | 55 | X | Logradouro |
| NUMERO | varchar | 15 | X | Número |
| COMPLEMENTO | varchar | 25 | | Complemento |
| BAIRRO | varchar | 30 | X | Bairro |
| CIDADE | varchar | 30 | X | Cidade |
| UF | varchar | 2 | | Estado |
| CEP | varchar | 8 | | CEP |
| SEXO | char | 1 | | M/F |
| ESTADO_CIVIL | char | 1 | | S=Solteiro, C=Casado, etc. |
| NOME_PAI | varchar | 50 | | Nome do pai |
| NOME_MAE | varchar | 50 | | Nome da mãe |
| NOME_CONJUGUE | varchar | 50 | | Nome do cônjuge |
| DATA_NASCIMENTO | smalldatetime | | | Data de nascimento |
| RG | varchar | 20 | | Documento de identidade |
| RG_COMPLEMENTO | varchar | 10 | | Órgão emissor |
| EMPRESA | varchar | 50 | | Empresa onde trabalha |
| CARGO | varchar | 50 | | Cargo |
| VALOR_RENDA | numeric | | | Renda mensal |
| CONT_ID | smallint | | FK | ID do contratante |
| IDENTIFICADOR_ID | varchar | 17 | | ID externo do credor |
| DATA_IMPORTACAO | datetime | | FK | Data da importação |
| DATA_INCLUSAO | smalldatetime | | X | Data de cadastro |
| USUARIO_INCLUSAO | varchar | 15 | X | Usuário que cadastrou |
| DATA_ALTERACAO | smalldatetime | | | Última alteração |
| USUARIO_ALTERACAO | varchar | 15 | | Usuário que alterou |
| QTDE_TITULOS | smallint | | | Total de títulos |
| VALOR_DIVIDA_ATIVA | numeric | | | Valor total da dívida |
| ENDERECO_EMPRESA | varchar | 50 | | Endereço comercial |
| NUMERO_EMPRESA | varchar | 10 | | Número comercial |
| COMPLEMENTO_ENDERECO_EMPRESA | varchar | 10 | | Complemento comercial |
| BAIRRO_EMPRESA | varchar | 25 | | Bairro comercial |
| CIDADE_EMPRESA | varchar | 25 | | Cidade comercial |
| CEP_EMPRESA | varchar | 8 | | CEP comercial |
| UF_EMPRESA | varchar | 2 | | UF comercial |
| OBSE | varchar | 700 | | Observações gerais |
| OBSE2 | varchar | 700 | | Observações adicionais |
| DEPARTAMENTO | varchar | 20 | | Departamento |
| DATA_DEVOLUCAO | smalldatetime | | | Data de devolução ao credor |
| LOCALIDADE | varchar | 8 | | Código de localidade |
| DATA_APTO_CORTE | smalldatetime | | | Data apto para corte |
| ANTIGUIDADE | smallint | | | Antiguidade em meses |
| SERASA | varchar | 4 | | Status SERASA |
| SPC | varchar | 4 | | Status SPC |
| FORNECIMENTO | varchar | 10 | | Número de fornecimento |
| SITUACAO | varchar | 50 | | Situação atual |
| DEVEDOR_ID_AUX | bigint | | | ID auxiliar/migração |
| REGIAO | varchar | 20 | | Região geográfica |
| SE_RECEPTIVO | bit | | | Flag receptivo |
| PONT_SCORE | int | | | Pontuação Score (propensão a pagar) |
| PONT_BEHAVIOR | int | | | Pontuação comportamental |
| QTDE_COMPRAS | smallint | | | Quantidade de compras |
| DATA_REATIVACAO_SPC | smalldatetime | | | Data reativação SPC |
| DATA_REATIVACAO_SERASA | smalldatetime | | | Data reativação SERASA |
| CODIGO_CREDOR | varchar | 25 | | Código no credor |
| PONT_SCORE_EMPRESA | int | | | Score da empresa |
| SETOR | varchar | 5 | | Setor/lote |
| QUADRA | varchar | 5 | | Quadra |
| SE_BLACKLIST | bit | | | Devedor na blacklist |
| NUMERO_MEDIDOR | varchar | 15 | | Número do medidor |
| AREA_RISCO | varchar | 3 | | Área de risco |
| MELHOR_CANAL_TIPO | varchar | 15 | | Melhor canal de contato |
| MELHOR_CANAL_DESCRICAO | varchar | 90 | | Descrição do canal |
| TIPO_OCUPACAO | smallint | | | Tipo de ocupação |
| DATA_OBITO | datetime | | | Data de óbito |
| NACIONALIDADE | varchar | 30 | | Nacionalidade |
| DATA_NEGATIVACAO_SPC | smalldatetime | | | Data negativação SPC |
| DATA_NEGATIVACAO_SERASA | smalldatetime | | | Data negativação SERASA |
| STRING_ORIGINAL | text | MAX | | String original da importação |

### tbdevedor_fone (26 colunas) — Telefones dos Devedores
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| DEVEDOR_ID | bigint | | FK | ID do devedor |
| FONE | varchar | 11 | X | Número do telefone |
| TIPO | char | 1 | X | R=Residencial, C=Celular, T=Trabalho, O=Outros, etc. |
| STATUS | char | 1 | | 0=Correto, 1=Incorreto, -1=Bloqueado |
| OBSE | varchar | 150 | | Observação |
| ORIGEM | varchar | 20 | | Origem do telefone |
| DATA_INCLUSAO | smalldatetime | | X | Data de cadastro |
| DATA_IMPORTACAO | datetime | | | Data de importação |
| USUARIO_INCLUSAO | varchar | 15 | | Quem cadastrou |
| FONE_ID_AUX | bigint | | | ID auxiliar |
| DATA_ALTERACAO | smalldatetime | | | Última alteração |
| USUARIO_ALTERACAO | varchar | 15 | | Quem alterou |
| RESULTADO_DISCADOR | varchar | 50 | | Resultado do discador automático |
| PRIORITARIO | bit | | | Flag telefone prioritário |
| STRING_ORIGINAL | text | MAX | | String original |
| PERCENTUAL_LOCALIZACAO | int | | | Percentual de localização |
| DATA_EXPORTACAO | smalldatetime | | | Data de exportação |
| OBSE2 | varchar | 150 | | Observação adicional |
| SE_WHATSAPP | smallint | | | Flag WhatsApp |
| DATA_ENVIO_DISCADOR | smalldatetime | | | Data envio ao discador |
| DATA_BATIMENTO | smalldatetime | | | Data de batimento |
| SE_CPC | bit | | | Contato com Pessoa Certa |
| FORNECEDOR | varchar | 30 | | Fornecedor do fone |
| SCORE | smallint | | | Score do telefone |
| RANKING | smallint | | | Ranking de prioridade |
| SELE | smallint | | | Flag de seleção |

### tbdevedor_endereco (22 colunas) — Endereços dos Devedores
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| ENDERECO_ID | bigint | | PK | ID do endereço |
| DEVEDOR_ID | bigint | | FK | ID do devedor |
| ENDERECO | varchar | 50 | | Logradouro |
| NUMERO | varchar | 15 | X | Número |
| COMPLEMENTO | varchar | 20 | | Complemento |
| BAIRRO | varchar | 30 | X | Bairro |
| CIDADE | varchar | 30 | X | Cidade |
| UF | varchar | 2 | X | Estado |
| CEP | varchar | 8 | | CEP |
| TIPO | varchar | 20 | X | Tipo: Residencial, Comercial, Cobrança, Referências |
| ORIGEM | varchar | 15 | X | Origem |
| SITUACAO | varchar | 22 | | Situação |
| SE_PRIORITARIO | bit | | | Flag endereço prioritário |
| DATA_INCLUSAO | smalldatetime | | X | Data de cadastro |
| DATA_IMPORTACAO | datetime | | | Data de importação |
| USUARIO_INCLUSAO | varchar | 15 | X | Quem cadastrou |
| DATA_ALTERACAO | smalldatetime | | | Última alteração |
| USUARIO_ALTERACAO | varchar | 15 | | Quem alterou |
| ENDERECO_ID_AUX | bigint | | | ID auxiliar |
| COD_ESTADO | int | | | Código IBGE do estado |
| COD_CIDADE | int | | | Código IBGE da cidade |
| STRING_ORIGINAL | text | MAX | | String original |

### tbdevedor_email (13 colunas) — Emails dos Devedores
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| EMAIL_ID | smallint | | PK | ID do email |
| EMAIL | varchar | 90 | X | Endereço de email |
| DEVEDOR_ID | bigint | | FK | ID do devedor |
| SITUACAO | char | 1 | | Status |
| ORIGEM | varchar | 15 | | Origem |
| DATA_IMPORTACAO | datetime | | | Data de importação |
| EMAIL_ID_AUX | bigint | | | ID auxiliar |
| DATA_INCLUSAO | smalldatetime | | | Data de cadastro |
| USUARIO_INCLUSAO | varchar | 15 | | Quem cadastrou |
| TIPO | char | 1 | | Tipo |
| SE_PRIORITARIO | bit | | | Flag email prioritário |
| NOME | varchar | 50 | | Nome associado |
| STRING_ORIGINAL | text | MAX | | String original |

### tbdevedor_acionamento (44 colunas) — Histórico de Acionamentos
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| ACIONAMENTO_ID | bigint | | PK | ID do acionamento |
| DATA | smalldatetime | | X | Data/hora do acionamento |
| ACAO_ID | int | | FK | ID da ação de cobrança |
| MENSAGEM | varchar | 3000 | | Descrição/observações do contato |
| COBRADOR_ID | int | | FK | ID do cobrador |
| DEVEDOR_ID | bigint | | FK | ID do devedor |
| DATA_IMPORTACAO | datetime | | | Data de importação |
| USUARIO_INCLUSAO | varchar | 15 | | Operador que registrou |
| DATA_PROXIMO_ACIONAMENTO | smalldatetime | | | Data agendada próximo contato |
| FILA_ID | int | | | ID da fila |
| CONT_ID | smallint | | | ID do contratante |
| DATA_PREVISAO | smalldatetime | | | Data de previsão pagamento |
| DATA_INCLUSAO | datetime | | | Data real de inclusão |
| SE_SMS | bit | | | Flag SMS enviado |
| SE_SMS_LOTE | bit | | | Flag SMS em lote |
| RESULTADO_SMS | varchar | 35 | | Resultado do SMS |
| FONE | varchar | 12 | | Telefone utilizado |
| ID_SMS | varchar | 10 | | ID do SMS |
| PERFIL_ID | smallint | | | ID do perfil |
| DATA_ACIONAMENTO_FIM | datetime | | | Hora fim do acionamento |
| NOME_ARQUIVO | varchar | 250 | | Arquivo associado |
| ASSESSORIA_ID | smallint | | | ID da assessoria |
| DATA_EXPORTACAO | datetime | | | Data de exportação |
| RESULTADO_DISCADOR | varchar | 100 | | Resultado do discador |
| SE_ACAO_AUTO | bit | | | Flag ação automática |
| SITUACAO_ID_AUX | int | | | Situação auxiliar |
| RAMAL | varchar | 10 | | Ramal utilizado |
| DATA_PROPOSTA | smalldatetime | | | Data da proposta |
| VALOR_PROPOSTA | numeric | | | Valor proposto |
| ATRASO | smallint | | | Dias de atraso |
| NUME_PROTOCOLO | varchar | 30 | | Número do protocolo |
| DISCADOR | char | 1 | | Flag discador |
| TIPO_LIGACAO | char | 1 | | Tipo da ligação |
| ID_LIGACAO | varchar | 50 | | ID da ligação no PABX |
| RESULTADO_WS | varchar | 100 | | Resultado webservice |
| MELHOR_CANAL | varchar | 120 | | Melhor canal de contato |
| NUMERO_CONTRATO | varchar | 30 | | Número do contrato |
| REGRA_ID | int | | | ID da regra aplicada |
| SE_EMAIL | bit | | | Flag email enviado |
| CAMPANHA_NOME | varchar | 30 | | Nome da campanha |
| DEFASAGEM | int | | | Defasagem em dias |
| QTDE_TITULO | smallint | | | Qtde de títulos |
| DATA_ALTERACAO | datetime | | | Data alteração |
| USUARIO_ALTERACAO | varchar | 15 | | Quem alterou |

### tbdevedor_avalista (35 colunas) — Avalistas/Fiadores
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| DEVEDOR_ID | bigint | | FK | ID do devedor |
| AVALISTA_ID | int | | PK | ID do avalista |
| CPF | varchar | 14 | X | CPF do avalista |
| NOME | varchar | 50 | X | Nome do avalista |
| ENDERECO | varchar | 40 | X | Endereço |
| NUMERO | varchar | 15 | X | Número |
| COMPLEMENTO | varchar | 20 | | Complemento |
| CIDADE | varchar | 30 | | Cidade |
| BAIRRO | varchar | 30 | | Bairro |
| UF | char | 2 | | Estado |
| CEP | varchar | 8 | | CEP |
| ESTADO_CIVIL | char | 1 | | Estado civil |
| NOME_PAI | varchar | 55 | | Nome do pai |
| NOME_MAE | varchar | 55 | | Nome da mãe |
| DATA_NASCIMENTO | smalldatetime | | | Data nascimento |
| SEXO | char | 1 | | Sexo |
| DATA_IMPORTACAO | datetime | | | Data de importação |
| DATA_INCLUSAO | smalldatetime | | | Data de cadastro |
| USUARIO_INCLUSAO | varchar | 15 | | Quem cadastrou |
| DATA_ALTERACAO | smalldatetime | | | Data de alteração |
| USUARIO_ALTERACAO | varchar | 15 | | Quem alterou |
| OBSE | varchar | 150 | | Observações |
| TIPO_BENEFICIARIO | int | | | Tipo beneficiário |
| COD_CARTEIRA | varchar | 15 | | Código carteira |
| TIPO_VENDA | varchar | 25 | | Tipo de venda |
| DATA_ADESAO | smalldatetime | | | Data de adesão |
| DIA_VENCIMENTO | int | | | Dia de vencimento |
| DATA_NASC | smalldatetime | | | Data nascimento (alt) |
| PRODUTO | varchar | 60 | | Produto |
| VALOR | numeric | | | Valor |
| POSSUI_ODONTO | varchar | 20 | | Possui odonto |
| STRING_ORIGINAL | text | MAX | | String original |
| DATA_BATIMENTO | smalldatetime | | | Data de batimento |
| SE_VISIVEL | bit | | | Visível S/N |
| NUMERO_CONTRATO | varchar | 40 | | Contrato vinculado |

### tbdevedor_cobrador (6 colunas) — Vínculo Devedor-Cobrador
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| DEVEDOR_ID | bigint | | FK | ID do devedor |
| COBRADOR_ID | int | | FK | ID do cobrador |
| DATA_INCLUSAO | smalldatetime | | X | Data do vínculo |
| USUARIO_INCLUSAO | varchar | 15 | X | Quem vinculou |
| DATA_ALTERACAO | smalldatetime | | | Data alteração |
| USUARIO_ALTERACAO | varchar | 15 | | Quem alterou |

### tbdevedor_processo_juridico (24 colunas) — Processos Judiciais
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| processo_id | int | | PK | ID do processo |
| devedor_id | bigint | | FK | ID do devedor |
| numero_processo | varchar | 50 | | Número do processo |
| data | datetime | | | Data de entrada |
| comarca | varchar | 150 | | Comarca |
| vara | varchar | 120 | | Vara |
| valor | money | | | Valor da causa |
| juiz | varchar | 150 | | Juiz responsável |
| data_audiencia | datetime | | | Data da audiência |
| observacao | text | MAX | | Observações |
| data_citacao | datetime | | | Data da citação |
| tipo_acao | varchar | 150 | | Tipo da ação |
| data_bloqueio | datetime | | | Data de bloqueio judicial |
| valor_bloqueio | money | | | Valor bloqueado |
| investigacao_patrimonial | varchar | 150 | | Investigação patrimonial |
| acao_contraria | char | 1 | | Flag ação contrária |
| empresa_ativa | char | 1 | | Flag empresa ativa |
| movimentacao_juridica_id | int | | FK | ID movimentação jurídica |
| data_inclusao | smalldatetime | | | Data de inclusão |
| data_alteracao | smalldatetime | | | Data de alteração |
| usuario_inclusao | varchar | 15 | | Quem incluiu |
| usuario_alteracao | varchar | 15 | | Quem alterou |
| garantia | varchar | 150 | | Garantia |
| valor_custas_iniciais | money | | | Custas iniciais |

### tbdevedor_mensagem (13 colunas) — Mensagens Internas
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| MENSAGEM_ID | bigint |  | PK | ID da mensagem |
| DEVEDOR_ID | bigint |  | FK | ID do devedor |
| CONT_ID | smallint |  | FK | ID do contratante |
| DATA_INCLUSAO | smalldatetime |  | X | Data de criação |
| USUARIO_INCLUSAO | varchar | 15 | X | Quem criou |
| DATA_ALTERACAO | smalldatetime |  |  | Data de alteração |
| USUARIO_ALTERACAO | varchar | 15 |  | Quem alterou |
| LIDO | bit |  | X | Flag lida |
| DATA_LEITURA | smalldatetime |  |  | Data de leitura |
| USUARIO_LEITURA | varchar | 15 |  | Quem leu |
| MENSAGEM | varchar | 500 | X | Texto da mensagem |
| MAQUINA | varchar | 50 |  | Nome da máquina |
| DATA_IMPORTACAO | datetime |  |  | Data de importação |

### tbtitulo (146 colunas) — Títulos de Dívida
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| TITULO_ID | bigint | | PK | ID único do título |
| TIPO_TITULO_ID | smallint | | FK | Tipo do título |
| DEVEDOR_ID | bigint | | FK | ID do devedor |
| NUMERO_CONTRATO | varchar | 80 | | Número do contrato |
| NUMERO_PRESTACAO | smallint | | | Número da prestação |
| QTDE_PRESTACAO | smallint | | | Total de prestações |
| NUMERO_DOCUMENTO | varchar | 30 | | Número do documento |
| VALOR | numeric | | X | Valor original do título |
| DATA_VENCIMENTO | smalldatetime | | X | Data de vencimento |
| DATA_VENCIMENTO_ORIGINAL | smalldatetime | | X | Vencimento original |
| VALOR_ORIGINAL | numeric | | X | Valor original sem correção |
| NUMERO_BANCO | varchar | 25 | | Número do banco |
| NUMERO_AGENCIA | varchar | 6 | | Agência |
| NUMERO_CONTA_CORRENTE | varchar | 10 | | Conta corrente |
| LOJA_ID | varchar | 70 | | ID da loja/filial |
| PRODUTO_ID | varchar | 50 | | ID do produto |
| NUMERO_REMESSA | varchar | 8 | | Número da remessa |
| DATA_IMPORTACAO | datetime | | FK | Data de importação |
| OBSE | varchar | 400 | | Observações |
| DATA_VENCIMENTO_ANTIGO | smalldatetime | | | Vencimento antigo |
| DATA_DEVOLUCAO | smalldatetime | | | Data de devolução |
| DATA_INCLUSAO | smalldatetime | | X | Data de inclusão |
| USUARIO_INCLUSAO | varchar | 15 | X | Quem incluiu |
| DATA_ALTERACAO | smalldatetime | | | Data de alteração |
| USUARIO_ALTERACAO | varchar | 15 | | Quem alterou |
| PERFIL_ID | smallint | | FK | Perfil de boleto |
| STRING_ORIGINAL | text | MAX | | String original da importação |
| BORDERO_ID | varchar | 20 | | ID do borderô |
| CONT_ID | smallint | | FK | ID do contratante |
| DATA_ENVIO | smalldatetime | | | Data de envio |
| DATA_COMPRA | smalldatetime | | | Data da compra |
| VALOR_COMPRA | numeric | | | Valor da compra |
| SELE | smallint | | | Seleção na fila |
| VALOR_ATUAL | numeric | | | Valor atualizado |
| FLAG | char | 1 | | Flag de controle |
| VALOR_RISCO | numeric | | | Valor em risco |
| VALOR_ADICIONAL | money | | | Valor adicional |
| VALOR_CUSTAS | money | | | Custas processuais |
| VALOR_PROTESTO | money | | | Valor de protesto |
| VALOR_NOTIFICACAO | money | | | Valor de notificação |
| VALOR_DESPESAS_ADIC | money | | | Despesas adicionais |
| COBRADOR_ID | int | | FK | ID do cobrador |
| ACAO_ID | int | | FK | Última ação de cobrança |
| FAIXA | int | | | Faixa de atraso em dias |
| FILA_ID | int | | | ID da fila |
| DATA_ULTIMO_ACIONAMENTO | datetime | | | Data último acionamento |
| DATA_PROXIMO_ACIONAMENTO | datetime | | | Data próximo acionamento |
| NOME_ALUNO | varchar | 50 | | Nome do aluno |
| TURMA | varchar | 50 | | Turma |
| propriedade_id | int | | | ID da propriedade |
| VALOR_JURO | numeric | | | Valor de juros |
| VALOR_MULTA | numeric | | | Valor de multa |
| VALOR_HONO | numeric | | | Valor de honorário |
| VALOR_DESC | numeric | | | Valor de desconto |
| VALOR_TAXA | numeric | | | Valor de taxa |
| VALOR_DESC_MIN | numeric | | | Desconto mínimo |
| sele_fila | bit | | | Seleção na fila (bit) |
| DATA_BATIMENTO | smalldatetime | | | Data do batimento |
| ACORDO_ID | varchar | 9 | | ID do acordo |
| HORARIO_PRIORITARIO | smalldatetime | | | Horário prioritário |
| PRIMEIRA_COMPRA | char | 1 | | Primeira compra |
| DATA_PROPRIEDADE | smalldatetime | | | Data propriedade |
| DATA_CALCULO_DATA_MIN | smalldatetime | | | Data cálculo data mínima |
| DATA_BASE | smalldatetime | | | Data base para cálculo |
| ALINEA | varchar | 4 | | Alínea |
| CARTEIRA | varchar | 10 | | Carteira |
| ALCADA_ACORDO | varchar | 25 | | Alçada do acordo |
| COBRADOR_ACIONAMENTO_ID | int | | | Cobrador do acionamento |
| ORDEM_ID | int | | | ID da ordem |
| VALOR_IGPM | numeric | | | Correção IGPM |
| VALOR_INCC | numeric | | | Correção INCC |
| VALOR_INPC | numeric | | | Correção INPC |
| VALOR_MINIMO | numeric | | | Valor mínimo |
| FASE | varchar | 20 | | Fase de cobrança |
| TITULO_ID_AUX | bigint | | | ID auxiliar do título |
| TIPO_PRODUTO | varchar | 15 | | Tipo do produto |
| ID_PRODUTO | varchar | 50 | | ID do produto |
| LOTE | varchar | 25 | | Lote |
| TIPO_ACORDO | varchar | 4 | | Tipo de acordo |
| TIPO_CARTAO | char | 2 | | Tipo de cartão |
| ATRASO_ORIGINAL | smallint | | | Atraso original em dias |
| PERMITE_REFIN | bit | | | Permite refinanciamento |
| DIA_VENCIMENTO_CARTAO | smallint | | | Dia vencimento cartão |
| ASSESSORIA_ID | smallint | | FK | ID da assessoria |
| VALOR_COMISSAO | numeric | | | Valor da comissão |
| VALOR_REPASSE | numeric | | | Valor de repasse |
| DATA_NEGATIVACAO_SPC | smalldatetime | | | Data negativação SPC |
| DATA_NEGATIVACAO_SERASA | smalldatetime | | | Data negativação SERASA |
| DATA_REATIVACAO_SPC | smalldatetime | | | Data reativação SPC |
| DATA_REATIVACAO_SERASA | smalldatetime | | | Data reativação SERASA |
| DATA_PROTESTO | smalldatetime | | | Data do protesto |
| VALOR_ORIGINAL_CALC | numeric | | | Valor original calculado |
| DEGRAU | int | | | Degrau de desconto |
| DATA_DISTRIBUICAO | smalldatetime | | | Data de distribuição |
| REGRA_ID | int | | FK | ID da regra |
| VALOR_CALCULADO_DESCONTO | numeric | | | Desconto calculado |
| VALOR_JURO_RETI | numeric | | | Juros retidos |
| DATA_D1 | smalldatetime | | | Data D1 |
| DATA_D2 | smalldatetime | | | Data D2 |
| DATA_D3 | smalldatetime | | | Data D3 |
| DATA_D4 | smalldatetime | | | Data D4 |
| DATA_D5 | smalldatetime | | | Data D5 |
| DATA_PREVISAO_PROPOSTA | smalldatetime | | | Data previsão proposta |
| VALOR_PROPOSTA | numeric | | | Valor da proposta |
| VALOR_ADICIONAL1 | numeric | | | Valor adicional 1 |
| VALOR_ADICIONAL2 | numeric | | | Valor adicional 2 |
| SETOR | varchar | 15 | | Setor |
| VALOR_JURO_REPA | numeric | | | Juros de repasse |
| VALOR_RECEITA | numeric | | | Valor de receita |
| TAXA_JUROS_CREDOR | numeric | | | Taxa juros do credor |
| DATA_ULTIMA_CORRECAO | smalldatetime | | | Última correção |
| CAMPANHA_CONT_ID | int | | | ID campanha contratante |
| SALDO_ORIGINAL | numeric | | | Saldo original |
| INIBIDO | bit | | | Título inibido |
| USUARIO_INIBIU | varchar | 15 | | Quem inibiu |
| VALOR_ACRESCIMO_FINANCEIRO | numeric | | | Acréscimo financeiro |
| VALOR_DESAGIO | numeric | | | Deságio |
| FORMA_PAGTO | char | 1 | | Forma de pagamento |
| VALOR_ADICIONAL1_ORIGINAL | numeric | | | Adicional 1 original |
| VALOR_ADICIONAL2_ORIGINAL | numeric | | | Adicional 2 original |
| VALOR_JURO_REFIN | numeric | | | Juros refinanciamento |
| SALDO_ORIGINAL_ENCARGOS | numeric | | | Saldo original c/ encargos |
| AJUIZAVEL | char | 1 | | Ajuizável S/N |
| SE_ENQUADROU | bit | | | Se enquadrou |
| DATA_NEGATIVACAO_SCPC | smalldatetime | | | Data negativação SCPC |
| DATA_REATIVACAO_SCPC | smalldatetime | | | Data reativação SCPC |
| SE_INCOBRAVEL | bit | | | Incobrável |
| VALOR_RECEITA_RECALCULADO | numeric | | | Receita recalculada |
| VALOR_COMISSAO_RECALCULADO | numeric | | | Comissão recalculada |
| DATA_NEGATIVACAO_SPCBRASIL | smalldatetime | | | Data negativação SPC Brasil |
| DATA_REATIVACAO_SPCBRASIL | smalldatetime | | | Data reativação SPC Brasil |
| DATA_CUSTAS | smalldatetime | | | Data das custas |
| DATA_CUSTAS_ADCIO | smalldatetime | | | Data custas adicionais |
| VALOR_COMISSAO_ACORDO | numeric | | | Comissão do acordo |
| FATURA_DEBITO_AUTOMATICO | char | 1 | | Débito automático |
| VALOR_IPCA | numeric | | | Correção IPCA |
| FATURA_RECEBIDA | char | 1 | | Fatura recebida |
| DATA_ROLAGEM_FASE | datetime | | | Data rolagem de fase |
| FASE_CONGELADA | varchar | 20 | | Fase congelada |
| NEGATIVACAO_ID | varchar | 50 | | ID da negativação |
| VALOR_JURO_ORIGINAL | numeric | | | Juros originais |
| VALOR_MULTA_ORIGINAL | numeric | | | Multa original |
| VALOR_INDICE_ORIGINAL | numeric | | | Índice original |
| VALOR_HONO_ORIGINAL | numeric | | | Honorários originais |
| LINHADIGITAVEL | varchar | 100 | | Linha digitável do boleto |
| QRCODE | nvarchar | MAX | | QR Code PIX |

### tbtitulo_pago (37 colunas) — Títulos Pagos/Baixados
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| TITULO_ID | bigint | | PK/FK | ID do título |
| DATA_PAGTO | smalldatetime | | X | Data do pagamento |
| VALOR | numeric | | X | Valor do título |
| VALOR_RECEBIDO | numeric | | X | Valor recebido |
| VALOR_MULTA | numeric | | X | Multa |
| VALOR_JURO | numeric | | X | Juros |
| VALOR_HONORARIO | numeric | | X | Honorários |
| VALOR_RECEITA | numeric | | | Receita |
| DATA_IMPORTACAO | datetime | | | Data importação |
| USUARIO_INCLUSAO | varchar | 15 | X | Quem incluiu |
| DATA_INCLUSAO | smalldatetime | | X | Data inclusão |
| TIPO_BAIXA | char | 1 | | Tipo baixa (0=Pagamento, 5=Acordo, X=PIX) |
| COBRADOR_ID | int | | FK | ID do cobrador |
| VALOR_TAXA | numeric | | | Taxa |
| USUARIO_ALTERACAO | varchar | 15 | | Quem alterou |
| DATA_ALTERACAO | smalldatetime | | | Data alteração |
| OBSE | varchar | 150 | | Observações |
| DATA_VENCIMENTO | smalldatetime | | | Data vencimento |
| DATA_VENCIMENTO_ANTIGO | smalldatetime | | | Vencimento antigo |
| CNAB_ID | int | | FK | ID CNAB |
| ACORDO_ID | varchar | 9 | | ID do acordo |
| RECIBO_ID | int | | FK | ID do recibo |
| STRING_ORIGINAL | text | MAX | | String original |
| VALOR_INDICE | numeric | | | Valor do índice |
| TIPO_BAIXA_CREDOR | varchar | 10 | | Tipo baixa credor |
| VALOR_DESCONTO | numeric | | | Desconto |
| VALOR_REPASSE | numeric | | | Repasse |
| DATA_PROCESSAMENTO_DEGRAU | smalldatetime | | | Data processamento degrau |
| VALOR_COMISSAO | numeric | | | Comissão |
| DATA_BATIMENTO | smalldatetime | | | Data batimento |
| DATA_EXPORTACAO | smalldatetime | | | Data exportação |
| EXPORTACAO_ID | int | | FK | ID exportação |
| VALOR_ADICIONAL | numeric | | | Valor adicional |
| DATA_CREDITO | smalldatetime | | | Data do crédito |
| USUARIO_EXPORTACAO | varchar | 15 | | Quem exportou |
| VALOR_PREMIO | numeric | | | Prêmio |
| ID_TRANSACAO | varchar | 40 | | ID da transação |

### tbtitulo_acionamento (8 colunas) — Títulos por Acionamento
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| ACIONAMENTO_ID | bigint | | FK | ID do acionamento |
| TITULO_ID | bigint | | FK | ID do título |
| NUMERO_CONTRATO | varchar | 70 | | Contrato |
| NUMERO_DOCUMENTO | varchar | 70 | | Documento |
| DATA_VENCIMENTO | smalldatetime | | | Vencimento |
| VALOR | numeric | | | Valor |
| USUARIO_INCLUSAO | varchar | 15 | | Quem incluiu |
| DATA_INCLUSAO | datetime | | | Data inclusão |

### tbacordo (72 colunas) — Acordos de Negociação
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| ACORDO_ID | varchar | 9 | PK | ID do acordo |
| DATA | smalldatetime | | X | Data do acordo |
| DEVEDOR_ID | bigint | | FK | ID do devedor |
| CONT_ID | smallint | | FK | ID do contratante |
| QTDE_PRESTACAO_ACORDO | smallint | | X | Total de parcelas |
| QTDE_NOVA_PRESTACAO_ACORDO | smallint | | X | Parcelas restantes |
| VALOR_ACORDO | numeric | | X | Valor total do acordo |
| VALOR_NOVA_PARCELA | numeric | | X | Valor de cada parcela |
| NUMERO_CONTRATO | varchar | 30 | | Contrato original |
| DATA_INCLUSAO | smalldatetime | | X | Data de criação |
| USUARIO_INCLUSAO | varchar | 15 | X | Quem criou |
| DATA_ALTERACAO | smalldatetime | | | Data de alteração |
| USUARIO_ALTERACAO | varchar | 15 | | Quem alterou |
| VALOR_ENTRADA | numeric | | | Valor da entrada |
| COBRADOR_ID | int | | FK | Cobrador que fechou |
| SELE | int | | | Seleção |
| CANCEL | bit | | | Flag cancelado |
| PAGO | bit | | | Flag pago |
| PARAMETRO_ID | smallint | | FK | ID do parâmetro |
| DATA_IMPORTACAO | datetime | | | Data importação |
| MENSAGEM | varchar | 200 | | Mensagem |
| DATA_QUEBRA | smalldatetime | | | Data da quebra |
| DATA_VENCIMENTO_ANTIGO | smalldatetime | | | Vencimento antigo |
| CNAB_ID | int | | FK | ID CNAB |
| DATA_LIMITE | smalldatetime | | | Data limite |
| TIPO_CANCELAMENTO | smallint | | | Tipo cancelamento |
| ORIGEM | varchar | 15 | | Origem do acordo |
| VALOR_ORIGINAL | numeric | | | Valor original |
| VALOR_DESCONTO | numeric | | | Desconto concedido |
| VALOR_JURO_COBRADO | numeric | | | Juros cobrados |
| VALOR_MULTA_COBRADO | numeric | | | Multa cobrada |
| VALOR_HONORARIO | numeric | | | Honorários |
| DATA_ENTRADA | smalldatetime | | | Data da entrada |
| PRE_ACORDO_ID | varchar | 9 | | ID do pré-acordo |
| ASSESSORIA_ID | smallint | | FK | ID da assessoria |
| ACORDO_ID_AUX | varchar | 9 | | ID auxiliar |
| USUARIO_INCLUSAO_AUX | varchar | 25 | | Usuário aux |
| NUMERO_CARTAO | varchar | 20 | | Número do cartão |
| CODIGO_SEGURANCA | varchar | 5 | | Código segurança cartão |
| DATA_VALIDADE | smalldatetime | | | Validade cartão |
| BANDEIRA | varchar | 20 | | Bandeira do cartão |
| CARTAO | varchar | 20 | | Cartão |
| FORMA_PAGAMENTO | varchar | 20 | | Forma pagamento |
| NUMERO_FATURA | varchar | 20 | | Número da fatura |
| CARTAO_NOME | varchar | 50 | | Nome no cartão |
| OBSE | varchar | 150 | | Observações |
| TAXA | numeric | | | Taxa |
| STRING_ORIGINAL | text | MAX | | String original |
| DEVOLVIDO | bit | | | Flag devolvido |
| DATA_EXPORTACAO | smalldatetime | | | Data exportação |
| DATA_RETORNO_TCD | datetime | | | Retorno TCD |
| PERC_DESCONTO_PRINC | numeric | | | % desconto principal |
| PERC_DESCONTO_JUROS | numeric | | | % desconto juros |
| PERC_DESCONTO_MULTA | numeric | | | % desconto multa |
| PERC_DESCONTO_HONOR | numeric | | | % desconto honorários |
| VALOR_BONUS | numeric | | | Bônus |
| ASSINATURA_DIGITAL_ID | varchar | 100 | | ID assinatura digital |
| VALOR_H2 | numeric | | | Valor H2 |
| VALOR_H3 | numeric | | | Valor H3 |
| VALOR_H4 | numeric | | | Valor H4 |
| VALOR_H5 | numeric | | | Valor H5 |
| VALOR_H6 | numeric | | | Valor H6 |
| VALOR_H7 | numeric | | | Valor H7 |
| VALOR_H8 | numeric | | | Valor H8 |
| VALOR_PAGO_ASSESSORIA | numeric | | | Valor pago à assessoria |
| VALOR_PAGO_CREDOR | numeric | | | Valor pago ao credor |
| VALOR_CORRECAO_MONETARIA | numeric | | | Correção monetária |
| VALOR_JUROS_HONORARIOS | numeric | | | Juros sobre honorários |
| VALOR_MULTA_HONORARIOS | numeric | | | Multa sobre honorários |
| VALOR_ACRESCIMOS | numeric | | | Acréscimos |
| VALOR_DECRESCIMOS | numeric | | | Decréscimos |
| VALOR_TAXA_BOLETO | numeric | | | Taxa do boleto |

### tbacordo_titulos (15 colunas) — Títulos Vinculados ao Acordo
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| ACORDO_ID | varchar | 9 | PK/FK | ID do acordo |
| TITULO_ID | bigint | | FK | ID do título |
| DEVEDOR_ID | bigint | | | ID do devedor |
| CONT_ID | smallint | | | ID do contratante |
| DATA_IMPORTACAO | datetime | | | Data importação |
| VALOR_JURO | numeric | | | Juros do título |
| VALOR_MULTA | numeric | | | Multa do título |
| VALOR_HONORARIO | numeric | | | Honorário |
| VALOR_CORRIGIDO | numeric | | | Valor corrigido |
| VALOR_RECEITA | numeric | | | Receita |
| VALOR_DESCONTO | numeric | | | Desconto aplicado |
| VALOR_ORIGINAL | numeric | | | Valor original |
| VALOR_COMISSAO | numeric | | | Comissão |
| VALOR_INDICES | numeric | | | Correção monetária |
| VALOR_ADICIONAL | numeric | | | Valor adicional |

### tbcontratante (116 colunas) — Credores/Contratantes
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| CONTRATANTE_ID | smallint | | PK | ID do contratante |
| FANTASIA | varchar | 60 | | Nome fantasia |
| RAZAOSOCIAL | varchar | 100 | | Razão social |
| ENDERECO | varchar | 50 | X | Endereço |
| NUMERO | varchar | 15 | X | Número |
| COMPLEMENTO | varchar | 20 | | Complemento |
| BAIRRO | varchar | 30 | X | Bairro |
| CIDADE | varchar | 25 | X | Cidade |
| UF | varchar | 2 | X | Estado |
| CEP | varchar | 8 | | CEP |
| CNPJ | varchar | 14 | X | CNPJ |
| ENVIA_SEQUENCIA_IMPORTACAO | char | 1 | X | Envia sequência importação |
| LOGO | varchar | 150 | | Logomarca |
| DIRETORIO_IMPORTACAO | varchar | 160 | | Diretório de importação |
| BOLETO_ID | bigint | | | ID do boleto |
| DIRETORIO_EXPORTACAO | varchar | 160 | | Diretório de exportação |
| TIPO_CHAVE_BUSCA | char | 1 | | Tipo busca: CPF, CONTRATO |
| GRUPO_ID | smallint | | FK | Grupo de contratantes |
| FONE | varchar | 11 | | Telefone |
| FAX | varchar | 11 | | Fax |
| SE_ATIV | char | 1 | | Ativo S/N |
| LAYOUT_ID | varchar | 10 | FK | Layout de importação |
| FORMULA_ID | int | | FK | Fórmula de cálculo |
| PERFIL_ID | smallint | | FK | Perfil de boleto |
| USUARIO_INCLUSAO | varchar | 15 | | Quem incluiu |
| DATA_INCLUSAO | smalldatetime | | | Data de inclusão |
| USUARIO_ALTERACAO | varchar | 15 | | Quem alterou |
| DATA_ALTERACAO | smalldatetime | | | Data de alteração |
| SE_RETEM_REPASSE | char | 1 | | Retém repasse |
| ATUACAO | char | 1 | | Atuação |
| ENVIA_EMAIL_COORDENADOR | char | 1 | | Envia email coordenador |
| COORDENADOR_ID | smallint | | FK | ID do coordenador |
| SE_UTILIZA_WS | char | 1 | | Usa webservice |
| QTDE_DIAS_COBRANCA | smallint | | | Dias de cobrança |
| SE_RETIRA_AUTO_VENCIDOS | char | 1 | | Retira auto vencidos |
| SE_RETIRA_ACORDO_VENCIDOS | char | 1 | | Retira acordo vencidos |
| DATA_CALCULO_PROPRIEDADE | smalldatetime | | | Data cálculo propriedade |
| CODIGO_CREDOR | varchar | 10 | | Código do credor |
| SEQU_CARTA_ID | smallint | | FK | Sequência de carta |
| DEVEDOR_ID_AUX | bigint | | | ID devedor auxiliar |
| BANCO | varchar | 3 | | Banco |
| AGENCIA | varchar | 10 | | Agência |
| CONTA | varchar | 15 | | Conta |
| OPERACAO | varchar | 3 | | Operação |
| TIPO_RECIBO | char | 1 | | Tipo de recibo |
| QTDE_LIGACAO_DIA | int | | | Ligações por dia |
| QTDE_LIGACAO_MES | int | | | Ligações por mês |
| QTDE_ACORDO_DIA | int | | | Acordos por dia |
| QTDE_ACORDO_MES | int | | | Acordos por mês |
| VALOR_RECEBIDO_MES | numeric | | | Valor recebido mês |
| VALOR_RECEITA_MES | numeric | | | Receita mês |
| EXPORTACAO_ID | int | | FK | ID exportação |
| TIPO_CONFISSAO_DIVIDA | char | 1 | | Tipo confissão dívida |
| CODIGO_CARTEIRA | varchar | 15 | | Código carteira |
| GERA_RECIBO_CNAB | char | 1 | | Gera recibo CNAB |
| EXPORTACAO_ID_2 | int | | | ID exportação 2 |
| SE_UTILIZA_FTP | char | 1 | | Usa FTP |
| DIRETORIO_IMPORTACAO_FTP | varchar | 160 | | Dir importação FTP |
| PORTA_IMPORTACAO_FTP | int | | | Porta FTP |
| USERNAME_FTP | varchar | 20 | | Usuário FTP |
| SENHA_FTP | varchar | 20 | | Senha FTP (campo sensível) |
| SE_FORCA_PROPOSTA | char | 1 | | Força proposta |
| SE_OCULTA_OCORRENCIA_VENDA | char | 1 | | Oculta ocorrência venda |
| DIRETORIO_DOCUMENTACAO | varchar | 160 | | Dir documentação |
| SE_PERMITE_DUPLICAR_ACAO_COBRANCA | char | 1 | | Permite duplicar ação |
| CONTA_CONTABIL | varchar | 20 | | Conta contábil |
| CONTA_ESTABELECIMENTO | varchar | 10 | | Conta estabelecimento |
| CENTRO_RESULTADO | varchar | 10 | | Centro resultado |
| CODIGO_RECEITA | varchar | 10 | | Código receita |
| CODIGO_SERVICO | varchar | 5 | | Código serviço |
| SE_UTILIZA_ACORDO_ONLINE | char | 1 | | Usa acordo online |
| TIPO_CARTA | char | 1 | | Tipo de carta |
| SE_CONTROLA_RETORNO_TCD | char | 1 | | Controla retorno TCD |
| SE_AVISA_BOLETO_VENCIDO | char | 1 | | Avisa boleto vencido |
| SE_BLOQUEAR_GERAR_NOVO_BOL | char | 1 | | Bloqueia novo boleto |
| SE_QUEBRAR_ACORDO_PROPORCIONAL | char | 1 | | Quebra acordo proporcional |
| REPRESENTANTE_NOME | varchar | 100 | | Nome do representante |
| REPRESENTANTE_CPF | varchar | 14 | | CPF do representante |
| REPRESENTANTE_NACIONALIDADE | varchar | 30 | | Nacionalidade |
| REPRESENTANTE_ESTCIVIL | varchar | 30 | | Estado civil |
| REPRESENTANTE_OCUPACAO | varchar | 30 | | Ocupação |
| REPRESENTANTE_DOCIDENTIFICACAO | varchar | 30 | | Doc identificação |
| REPRESENTANTE_ENDERECO | varchar | 100 | | Endereço representante |
| REPRESENTANTE_BAIRRO | varchar | 50 | | Bairro representante |
| REPRESENTANTE_CIDADE | varchar | 50 | | Cidade representante |
| REPRESENTANTE_UF | varchar | 2 | | UF representante |
| REPRESENTANTE_CEP | varchar | 8 | | CEP representante |
| ENTIDADE | varchar | 10 | | Entidade |
| ASSOCIADO | varchar | 10 | | Associado |
| PERC_LOCALIZACAO | int | | | % localização |
| SE_LOCALIZA_FONE | char | 1 | | Localiza fone |
| SE_GERA_NUMERO_PROTOCOLO | char | 1 | | Gera protocolo |
| QTDE_DIAS_VISU_FICHA_DEVEDOR | smallint | | | Dias visualização ficha |
| ENVIA_EMAIL_ACIONAMENTO | char | 1 | | Email de acionamento |
| TIPO_COMISSIONAMENTO | char | 1 | | Tipo comissão |
| SE_UTILIZA_API_ACORDO_ONLINE | varchar | 1 | | API acordo online |
| SE_ACIONA_POR_TITULO | char | 1 | | Aciona por título |
| SE_AVISA_ACORDO_VENCIDO | char | 1 | | Avisa acordo vencido |
| SE_TAXA_CREDOR_MAIS_JUROS | char | 1 | | Taxa credor + juros |
| SE_INFORMA_MELHOR_CANAL_ATENDIMENTO | char | 1 | | Informa melhor canal |
| SE_SELECIONA_TITULOS_FICHA | char | 1 | | Seleciona títulos ficha |
| SE_VERIFICA_LGPD | char | 1 | | Verifica LGPD |
| SE_EXPORTA_CONTABILIDADE | char | 1 | | Exporta contabilidade |
| SE_RETEM_TAXA_BOLETO_REPASSE | char | 1 | | Retém taxa boleto |
| SE_UTILIZA_CHAT | char | 1 | | Usa chat |
| SE_AVISA_CPF_2_CONTRATANTE | char | 1 | | Avisa CPF 2 contratantes |
| SE_PARCELEJA | char | 1 | | Usa Parceleja |
| EXIGE_SENHA_BOLETO | char | 1 | | Exige senha boleto |
| TIPO_ENCARGO_ACORDO | smallint | | | Tipo encargo acordo |
| TIPO_ENCARGO_BOLETO | smallint | | | Tipo encargo boleto |
| EXIGE_AUTORIZACAO_DESCONTO_MAIOR | char | 1 | | Exige autorização desconto |
| VERIFICA_OUTRAS_DIVIDAS | char | 1 | | Verifica outras dívidas |
| SE_CADASTRA_ACORDO_WS_AUTOMATICO | char | 1 | | Acordo WS automático |
| REPRESENTANTE_ASSINATURA | varchar | 100 | | Assinatura representante |
| EMAIL | varchar | 100 | | Email |
| OBSERVACAO | varchar | 700 | | Observações |

### tbcobrador (40 colunas) — Cobradores/Operadores
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| COBRADOR_ID | int | | PK | ID do cobrador |
| NOME | varchar | 50 | X | Nome completo |
| ENDERECO | varchar | 50 | X | Endereço |
| NUMERO | varchar | 15 | X | Número |
| COMPLEMENTO | varchar | 20 | | Complemento |
| BAIRRO | varchar | 30 | | Bairro |
| CIDADE | varchar | 30 | X | Cidade |
| UF | varchar | 2 | | UF |
| CEP | varchar | 8 | | CEP |
| SE_ATIVO | char | 1 | X | Ativo S/N |
| TURNO | char | 1 | X | Turno (M/T/N) |
| DATA_INCLUSAO | smalldatetime | | X | Data de cadastro |
| CPF | varchar | 11 | | CPF |
| FONE | varchar | 10 | | Telefone |
| FONE_CELULAR | varchar | 10 | | Celular |
| EMAIL | varchar | 180 | | Email |
| TIPO | char | 1 | | Tipo |
| DATA_NASCIMENTO | smalldatetime | | | Data nascimento |
| DATA_ALTERACAO | smalldatetime | | | Data alteração |
| RG | varchar | 12 | | RG |
| OPER_ID | varchar | 15 | FK | ID do operador |
| USUARIO_ALTERACAO | varchar | 15 | | Quem alterou |
| USUARIO_INCLUSAO | varchar | 15 | | Quem cadastrou |
| EQUIPE_ID | int | | FK | ID da equipe |
| STATUS | char | 1 | | Status |
| MATRICULA | varchar | 10 | | Matrícula |
| ACESSA_AGENDA | char | 1 | | Acessa agenda |
| VALOR_META | numeric | | | Valor da meta |
| TIPO_COBRADOR | char | 1 | | I=Interno, E=Externo |
| DATA_ULTIMO_ACIONAMENTO | smalldatetime | | | Último acionamento |
| ASSESSORIA_ID | smallint | | FK | ID da assessoria |
| NOME_GUERRA | varchar | 50 | | Apelido/nome de guerra |
| SE_CONTABILIZA_WEB | char | 1 | | Contabiliza web |
| META_VENDA | int | | | Meta de venda |
| META_VIDA | int | | | Meta de vidas |
| CLASSIFICACAO | varchar | 10 | | Classificação |
| SE_TABULA_RETORNO_CENTRAL | char | 1 | | Tabula retorno central |
| SE_EXECUTA_MARCA_DAGUA | char | 1 | | Executa marca d'água |
| HORA_INICIO | varchar | 5 | | Horário início |
| HORA_FIM | varchar | 5 | | Horário fim |

### tboperador (29 colunas) — Operadores do Sistema
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| OPERADOR_ID | varchar | 15 | PK | Login do operador |
| NOME | varchar | 50 | X | Nome completo |
| SENHA | varchar | 10 | | Senha desktop (campo sensível) |
| SE_ADMI | bit | | X | É administrador |
| UF | varchar | 2 | X | Estado |
| USUARIO_INCLUSAO | varchar | 15 | X | Quem incluiu |
| DATA_INCLUSAO | smalldatetime | | X | Data de inclusão |
| USUARIO_ALTERACAO | varchar | 15 | | Quem alterou |
| DATA_ALTERACAO | smalldatetime | | | Data alteração |
| SE_ATIVO | char | 1 | X | Ativo S/N |
| DATA_ULTIMO_ACESSO | smalldatetime | | | Último acesso |
| FILIAL_ID | smallint | | FK | ID da filial |
| PERFIL_SKIN | varchar | 20 | | Skin do perfil |
| SENHA_WEB | varchar | 10 | | Senha web (campo sensível) |
| SE_ACES_WEB | bit | | | Acesso web |
| EMAIL | varchar | 100 | | Email |
| LOGIN_CENTRAL | varchar | 20 | | Login central telefônica |
| ASSESSORIA_ID | smallint | | FK | ID da assessoria |
| SE_GRAVA_ACIONAMENTO_FICHA | char | 1 | | Grava acionamento ficha |
| SE_ACES_DASH | bit | | | Acesso dashboard |
| SENHA_CENTRAL | varchar | 15 | | Senha central (campo sensível) |
| OPERADOR_PERFIL_ID | varchar | 15 | FK | Perfil de permissões |
| DATA_ULTIMA_TROCA_SENHA | smalldatetime | | | Última troca senha |
| ID_CENTRAL | varchar | 10 | | ID na central |
| QTDE_DIAS_ALT_SENHA | int | | | Dias para trocar senha |
| ID_PERFIL | int | | FK | ID do perfil |
| SE_UTILIZA_SENHA_FORTE | char | 1 | | Usa senha forte |
| QTDE_DIAS_VISU_MAX_RELA | smallint | | | Dias máx visualização relatório |
| VISU_SOMENTE_ENTR_QUITACAO | char | 1 | | Visualiza somente entrada/quitação |

### tbfila (39 colunas) — Filas de Cobrança
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| FILA_ID | int | | PK | ID da fila |
| NOME | varchar | 80 | X | Nome da fila |
| QTDE_DEVE | int | | X | Quantidade de devedores |
| DATA | smalldatetime | | X | Data de criação |
| QTDE_DEVE_EXEC | int | | | Devedores executados |
| DATA_INCLUSAO | smalldatetime | | X | Data de inclusão |
| USUARIO_INCLUSAO | varchar | 15 | X | Quem criou |
| DATA_ALTERACAO | smalldatetime | | | Data alteração |
| SQL | text | MAX | | SQL da fila |
| ORDEM_SQL | varchar | 350 | | Ordenação SQL |
| ORDEM_ID | smallint | | X | ID da ordenação |
| SE_VISUALIZA | char | 1 | X | Visualizável |
| SE_CARTEIRA | char | 1 | X | É carteira |
| QTDE_RESTANTE | int | | | Devedores restantes |
| CONT_ID | int | | FK | ID do contratante |
| USUARIO_FINALIZA | varchar | 15 | | Quem finalizou |
| DATA_FINALIZA | smalldatetime | | | Data finalização |
| FILA_OK | smallint | | | Status OK |
| USUARIO_ALTERACAO | varchar | 15 | | Quem alterou |
| SE_REGRA | char | 1 | | Gerada por regra |
| REGRA_ID | int | | FK | ID da regra |
| TIPO | char | 1 | | Tipo da fila |
| TIPO_FILA_CENTRAL | char | 1 | | Tipo fila central |
| CAMPANHA_ID | bigint | | FK | ID da campanha |
| GRUPO_ID | smallint | | FK | ID do grupo |
| QTDE_FONE_RESIDENCIAL | int | | | Qtde fones residenciais |
| QTDE_FONE_COMERCIAL | int | | | Qtde fones comerciais |
| QTDE_FONE_CELULAR | int | | | Qtde fones celulares |
| ASSESSORIA_ID | smallint | | FK | ID da assessoria |
| SELE | smallint | | | Seleção |
| SE_FILA_MANUAL_URA | char | 1 | | Fila manual URA |
| POSICAO_CENTRAL | smallint | | | Posição na central |
| NUMERO_REMESSA | varchar | 8 | | Número da remessa |
| CAMPANHA_NOME | varchar | 30 | | Nome da campanha |
| ESTRATEGIA | text | MAX | | Estratégia |
| DATA_ULTIMA_ATUALIZACAO | datetime | | | Última atualização |
| SE_DESCONSIDERA_AGENDA | char | 1 | | Desconsidera agenda |
| FILTRO_FONE | varchar | 100 | | Filtro de telefones |
| EQUIPE_ID | int | | FK | ID da equipe |

### tbequipe (19 colunas) — Equipes de Cobrança
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| EQUIPE_ID | int | | PK | ID da equipe |
| NOME | varchar | 50 | X | Nome da equipe |
| COORDENADOR_ID | smallint | | FK | ID do coordenador |
| DATA_INCLUSAO | smalldatetime | | X | Data de inclusão |
| USUARIO_INCLUSAO | varchar | 15 | X | Quem incluiu |
| DATA_ALTERACAO | smalldatetime | | | Data alteração |
| USUARIO_ALTERACAO | varchar | 15 | | Quem alterou |
| VALOR_META | numeric | | | Meta da equipe |
| CONT_ID | smallint | | FK | ID do contratante |
| TIPO_CENTRAL | smallint | | | Tipo central |
| TMA | int | | | Tempo médio atendimento |
| ASSESSORIA_ID | smallint | | FK | ID da assessoria |
| CAMPANHA_ID | int | | FK | ID da campanha |
| SERVICO | varchar | 20 | | Serviço |
| TCM | int | | | Tempo chamada máximo |
| CAMPANHA_ID_TRANSFERENCIA | int | | FK | Campanha de transferência |
| FONE_EXTERNO | varchar | 20 | | Telefone externo |
| SE_PERMITE_TRANSFERENCIA_LIGACAO | char | 1 | | Permite transferência |
| SE_ATIVO | char | 1 | | Ativo S/N |

### tbagenda (12 colunas) — Agendamentos
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| AGENDA_ID | bigint |  | PK | ID do agendamento |
| DEVEDOR_ID | bigint |  | FK | ID do devedor |
| DATA | smalldatetime |  | X | Data agendada |
| OBSE | varchar | 150 | X | Observação |
| COBRADOR_ID | int |  |  | Cobrador responsável |
| USUARIO_INCLUSAO | varchar | 15 | X | Quem criou |
| DATA_INCLUSAO | smalldatetime |  | X | Data de criação |
| USUARIO_ALTERACAO | varchar | 15 |  | Quem alterou |
| DATA_ALTERACAO | smalldatetime |  |  | Data alteração |
| CONT_ID | smallint |  | X | ID do contratante |
| COORDENADOR_INCLUSAO | varchar | 15 |  | Coordenador que criou |
| FONE | varchar | 11 |  | Telefone para contato |

### tbcampanha (13 colunas) — Campanhas de Cobrança
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| CAMPANHA_ID | int |  | PK | ID da campanha |
| CONT_ID | int |  | FK | ID do contratante |
| DESCRICAO | varchar | 60 | X | Descrição |
| QTDE_OFERTA | int |  | X | Qtde de ofertas |
| INFORMACOES | varchar | 2000 |  | Informações da campanha |
| SE_ATIVO | char | 1 | X | Ativo S/N |
| DATA_INCLUSAO | smalldatetime |  | X | Data de criação |
| USUARIO_INCLUSAO | varchar | 15 | X | Quem criou |
| DATA_ALTERACAO | smalldatetime |  |  | Data alteração |
| USUARIO_ALTERACAO | varchar | 15 |  | Quem alterou |
| CAMPANHA_CONT_ID | int |  | FK | Campanha do contratante |
| DATA_IMPORTACAO | datetime |  |  | Data de importação |
| TIPO | char | 1 |  | Tipo da campanha |

### tbimportacao (55 colunas) — Importações de Carteiras
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| DATA_IMPORTACAO | datetime | | PK | Data/hora da importação |
| DATA_FINAL | smalldatetime | | | Data final |
| NOME_ARQUIVO | varchar | 400 | | Nome do arquivo |
| QTDE_REGISTRO | int | | | Qtde registros |
| QTDE_DEVEDOR | int | | | Qtde devedores |
| QTDE_TITULO | int | | | Qtde títulos |
| VALOR_ARQUIVO | numeric | | | Valor do arquivo |
| CONTRATANTE_ID | smallint | | FK | ID do contratante |
| VALOR_IMPORTADO | numeric | | | Valor importado |
| DATA_IMPORTACAO_FINAL | datetime | | | Data final importação |
| USUARIO_INCLUSAO | varchar | 15 | | Quem incluiu |
| DATA_ENVIO | smalldatetime | | | Data de envio |
| QTDE_DEVEDOR_EXIS | int | | | Devedores existentes |
| QTDE_TITULO_EXIS | int | | | Títulos existentes |
| QTDE_DEVEDOR_ERRO | int | | | Devedores com erro |
| QTDE_TITULO_ERRO | int | | | Títulos com erro |
| IMPO_OK | smallint | | | Importação OK |
| QTDE_PAGTO | int | | | Qtde pagamentos |
| QTDE_PAGTO_EXIS | smallint | | | Pagamentos existentes |
| QTDE_PAGTO_ERRO | smallint | | | Pagamentos com erro |
| NUMERO_REMESSA | varchar | 8 | X | Número da remessa |
| NOME_MAQUINA | varchar | 25 | | Nome da máquina |
| SCHEDULE | bit | | | Agendado |
| SELE | smallint | | | Seleção |
| QTDE_ACORDO | int | | | Qtde acordos |
| QTDE_ACORDO_EXIS | int | | | Acordos existentes |
| QTDE_ACORDO_ERRO | int | | | Acordos com erro |
| VALOR_ACORDO | numeric | | | Valor acordos |
| TEMPO | varchar | 20 | | Tempo de processamento |
| QTDE_FONE | int | | | Qtde telefones |
| LAYOUT_ID | varchar | 10 | FK | ID do layout |
| TIPO | smallint | | | Tipo de importação |
| OBSE | varchar | 500 | | Observações |
| HEADER | varchar | 1500 | | Header do arquivo |
| TRAILER | varchar | 1500 | | Trailer do arquivo |
| QTDE_CONTRATO | int | | | Qtde contratos |
| QTDE_TITULO_NAO_EXIS | int | | | Títulos não existentes |
| QTDE_FONE_EXIS | int | | | Telefones existentes |
| QTDE_ENDE | int | | | Qtde endereços |
| QTDE_ENDE_EXIS | int | | | Endereços existentes |
| QTDE_EMAIL | int | | | Qtde emails |
| QTDE_EMAIL_EXIS | int | | | Emails existentes |
| QTDE_DEVOLUCAO | int | | | Qtde devoluções |
| QTDE_DEVOLUCAO_EXIS | int | | | Devoluções existentes |
| QTDE_DEVOLUCAO_ERRO | int | | | Devoluções com erro |
| VALOR_DEVOLUCAO | numeric | | | Valor devoluções |
| QTDE_ACIONAMENTO | int | | | Qtde acionamentos |
| QTDE_ACIONAMENTO_EXIS | int | | | Acionamentos existentes |
| QTDE_ACIONAMENTO_ERRO | int | | | Acionamentos com erro |
| QTDE_FONE_ERRO | int | | | Telefones com erro |
| QTDE_AVALISTA | int | | | Qtde avalistas |
| QTDE_AVALISTA_EXIS | int | | | Avalistas existentes |
| QTDE_AVALISTA_ERRO | int | | | Avalistas com erro |
| VERSAO | varchar | 10 | | Versão |
| DATA_EXECUTAVEL | smalldatetime | | | Data do executável |

### tbparametro (59 colunas) — Configurações Globais do Sistema
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| DEVEDOR_ID | bigint | | | Último ID devedor |
| TITULO_ID | bigint | | | Último ID título |
| ACIONAMENTO_ID | bigint | | | Último ID acionamento |
| FILA_ID | int | | | Último ID fila |
| QTDE_OPERADOR_LOGADO | smallint | | | Operadores logados |
| AGENDA_ID | bigint | | | Último ID agenda |
| DATA_NOME | float | | | Data nome |
| DATA_NOME_PREV | float | | | Data nome previsão |
| EMPRESA | varchar | 40 | | Nome da empresa |
| CIDADE | varchar | 25 | | Cidade |
| BAIRRO | varchar | 30 | | Bairro |
| UF | varchar | 2 | | UF |
| CNPJ | varchar | 14 | | CNPJ |
| log_id | bigint | | | Último ID log |
| VERSAO | smallint | | | Versão do sistema |
| ACORDO_ID | bigint | | | Último ID acordo |
| BROADCAST | varchar | 20 | | Broadcast |
| QTDE_LICENCA | varchar | 10 | | Qtde licenças |
| EMAIL | varchar | 100 | | Email da empresa |
| PROGRAMA_ID | varchar | 30 | | ID do programa |
| DATA_RETIRA_TITULO_VENCIDO | smalldatetime | | | Data retirar títulos vencidos |
| EMPRESA_ID | varchar | 10 | | ID da empresa |
| ENDERECO | varchar | 50 | | Endereço |
| NUMERO | varchar | 20 | | Número |
| COMPLEMENTO | varchar | 25 | | Complemento |
| FONE | varchar | 10 | | Telefone |
| FONE_FAX | varchar | 10 | | Fax |
| RAZAO_SOCIAL | varchar | 45 | | Razão social |
| CEP | varchar | 8 | | CEP |
| LOGO | image | MAX | | Logo da empresa |
| SITE | varchar | 150 | | Site |
| BD | varchar | 20 | | Nome do banco |
| DATA_DEVEDOR_FILA | smalldatetime | | | Data devedor fila |
| DATA_PROCESSA_REGRAS | smalldatetime | | | Data processa regras |
| PORTA | int | | | Porta |
| DIRETORIO_BACKUP | varchar | 300 | | Diretório de backup |
| DASHBOARD | char | 1 | | Dashboard ativo |
| NOME_SOCIO1 | varchar | 70 | | Sócio 1 |
| NOME_SOCIO2 | varchar | 70 | | Sócio 2 |
| VERSAO_SQL | int | | | Versão SQL |
| DATA_PROCESSA_DEGRAU | smalldatetime | | | Data processa degrau |
| ACORDO_ID_2 | bigint | | | Último ID acordo 2 |
| FONE_0800 | varchar | 15 | | 0800 |
| SE_CONS | bit | | | Consolidado |
| DATA_NOME_EMAIL | float | | | Data nome email |
| SMS_ID | bigint | | | Último ID SMS |
| QTDE_LICENCA_MAQUINA | smallint | | | Licenças por máquina |
| SERVIDOR_ID | smallint | | | ID do servidor |
| QTDE_LICENCA_WEB | varchar | 55 | | Licenças web |
| QTDE_DIAS_ALTERAR_SENHA | int | | | Dias para alterar senha |
| DATA_PROCESSA_ACESSO_OPERADOR | smalldatetime | | | Último processamento acesso |
| INSCRICAO_MUNICIPAL | varchar | 10 | | Inscrição municipal |
| HOST_BACK_END | varchar | 250 | | Host backend |
| DATA_EXECUTAVEL | datetime | | | Data do executável |
| FONE_WHATS | varchar | 11 | | WhatsApp |
| HOST_WEBHOOK | varchar | 250 | | Host webhook |
| HOST_BOLETO_DOWNLOAD | varchar | 250 | | Host download boleto |
| SE_BLOQUEIA_ACESSO_SIMULTANEO | bit | | | Bloqueia acesso simultâneo |
| SE_TROCA_SENHA_APOS_CADASTRO | bit | | | Troca senha após cadastro |

### tblog (11 colunas) — Log de Auditoria
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| log_id | bigint |  | PK | ID do log |
| tela_id | varchar | 20 | X | Tela/módulo |
| acao_id | varchar | 20 | X | Ação executada |
| data | datetime |  |  | Data/hora |
| oper_id | varchar | 15 | X | Operador |
| texto | varchar | 1500 | X | Descrição |
| maquina | varchar | 25 | X | Máquina |
| VERSAO | varchar | 10 |  | Versão do sistema |
| chave_id | varchar | 20 |  | Chave do registro |
| aplicacao | varchar | 20 |  | Aplicação |
| data_executavel | smalldatetime |  |  | Data do executável |

### tbboleto (56 colunas) — Boletos de Cobrança
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| BOLETO_ID | varchar | 20 | PK | ID do boleto |
| DATA_VENCIMENTO | smalldatetime |  | X | Data vencimento |
| LINHA_DIGITAVEL | varchar | 100 |  | Linha digitável |
| COBRADOR_ID | int |  | FK | ID do cobrador |
| DEVEDOR_ID | bigint |  | FK | ID do devedor |
| VALOR | numeric |  | X | Valor do boleto |
| PERFIL_ID | smallint |  | FK | ID do perfil de boleto |
| OPERADOR_ID | varchar | 15 |  | Operador |
| SELE | smallint |  |  | Seleção |
| DATA_CADASTRO | smalldatetime |  |  | Data de cadastro |
| CANCEL | bit |  |  | Cancelado |
| PAGO | bit |  |  | Pago |
| FILIAL_ID | smallint |  | FK | ID da filial |
| CONT_ID | smallint |  | FK | ID do contratante |
| CODIGO_BARRA | varchar | 44 |  | Código de barras |
| CNAB_ID | int |  | FK | ID do CNAB |
| MASSA | bit |  |  | Gerado em massa |
| ACORDO_ID | varchar | 9 |  | ID do acordo |
| TIPO_SAIDA | char | 1 |  | Tipo de saída |
| EMAIL | char | 90 |  | Email do devedor |
| INSTRUCAO | varchar | 2500 |  | Instruções do boleto |
| PRE_ACORDO_ID | varchar | 9 |  | ID do pré-acordo |
| ASSESSORIA_ID | smallint |  | FK | ID da assessoria |
| VALOR_DESCONTO | numeric |  |  | Valor do desconto |
| MAQUINA | varchar | 20 |  | Máquina |
| OBSE | varchar | 350 |  | Observações |
| NUMERO_DOCUMENTO | varchar | 40 |  | Número do documento |
| VALOR_ADICIONAL | numeric |  |  | Valor adicional |
| NOSSO_NUMERO | varchar | 20 |  | Nosso número |
| DATA_ALTERACAO | smalldatetime |  |  | Data alteração |
| SEQUENCIAL_ID | bigint |  |  | ID sequencial |
| DATA_EXPORTACAO | smalldatetime |  |  | Data exportação |
| EXPORTACAO_ID | int |  | FK | ID da exportação |
| DATA_ALTERACAO_VENCIMENTO | datetime |  |  | Alteração de vencimento |
| DATA_IMPORTACAO | datetime |  |  | Data de importação |
| STRING_ORIGINAL | text | MAX |  | String original |
| VALOR_ORIGINAL | numeric |  |  | Valor original |
| DATA_VENCIMENTO_ORIGINAL | smalldatetime |  |  | Vencimento original |
| DATA_ENVIO_EMAIL | smalldatetime |  |  | Data envio email |
| BOLETO_BASE64 | text | MAX |  | Boleto em base64 |
| QRCODEPIX | nvarchar | MAX |  | QR Code PIX |
| TIPO_EMISSAO | char | 1 |  | Tipo de emissão |
| DATA_ENVIO_WHATSAPP | smalldatetime |  |  | Data envio WhatsApp |
| LINK_PAGTO | varchar | 250 |  | Link de pagamento |
| LINK_PAGTO_ID | varchar | 25 |  | ID link pagamento |
| LINK_PAGTO_VALIDADE | smalldatetime |  |  | Validade link pagamento |
| USUARIO_ALTERACAO | varchar | 15 |  | Quem alterou |
| DATA_CANCELAMENTO | smalldatetime |  |  | Data cancelamento |
| CEDENTE_NOME | varchar | 120 |  | Nome do cedente |
| CEDENTE_CNPJ | varchar | 20 |  | CNPJ do cedente |
| CEDENTE_BANCO | varchar | 5 |  | Banco do cedente |
| CEDENTE_AGENCIA | varchar | 10 |  | Agência do cedente |
| CEDENTE_AGENCIA_DV | varchar | 5 |  | DV agência |
| CEDENTE_CONTA | varchar | 15 |  | Conta do cedente |
| CEDENTE_CONTA_DV | varchar | 5 |  | DV conta |
| CEDENTE_CARTEIRA | varchar | 5 |  | Carteira do cedente |

### tbsql (9 colunas) — Queries SQL Salvas
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| ID | int |  | PK | ID da query |
| OPERADOR_ID | varchar | 15 | X | Operador dono |
| NOME | varchar | 60 |  | Nome da query |
| SQL | text | MAX | X | SQL da query |
| DATA_INCLUSAO | smalldatetime |  | X | Data de criação |
| USUARIO_INCLUSAO | varchar | 15 | X | Quem criou |
| DATA_ALTERACAO | smalldatetime |  |  | Data alteração |
| USUARIO_ALTERACAO | varchar | 15 |  | Quem alterou |
| QTDE_COLUNAS | smallint |  |  | Qtde de colunas esperadas |

## Tabelas Complementares — Mapeamento de Colunas

### tbdevedor_calculo (5 colunas) — Cálculos do Devedor
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| devedor_id | bigint | | FK | ID do devedor |
| cont_id | smallint | | FK | ID do contratante |
| valor_minimo | numeric | | | Valor mínimo de negociação |
| valor_medio | numeric | | | Valor médio |
| valor_maximo | numeric | | | Valor máximo |

### tbdevedor_propriedade (8 colunas) — Propriedades do Devedor
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| PROPRIEDADE_ID | int | | PK | ID da propriedade |
| NOME | varchar | 60 | X | Nome da propriedade |
| SE_ATIV | char | 1 | X | Ativo S/N |
| OBSE | varchar | 150 | | Observações |
| DATA_INCLUSAO | smalldatetime | | | Data de cadastro |
| USUARIO_INCLUSAO | varchar | 15 | | Quem cadastrou |
| DATA_ALTERACAO | smalldatetime | | | Última alteração |
| USUARIO_ALTERACAO | varchar | 15 | | Quem alterou |

### tbdevedor_questionario (12 colunas) — Questionários do Devedor
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| QUESTIONARIO_ID | bigint | | PK | ID do questionário |
| DEVEDOR_ID | bigint | | FK | ID do devedor |
| PERGUNTA_ID | int | | FK | ID da pergunta |
| SEQU_ID | int | | | Sequencial |
| RESPOSTA | char | 1 | | Resposta |
| NOTA | int | | | Nota atribuída |
| OBSE | varchar | 250 | X | Observação |
| ACIONAMENTO_ID | bigint | | FK | ID do acionamento |
| DATA_INCLUSAO | smalldatetime | | X | Data de cadastro |
| USUARIO_INCLUSAO | varchar | 15 | X | Quem cadastrou |
| DATA_ALTERACAO | smalldatetime | | | Última alteração |
| USUARIO_ALTERACAO | varchar | 15 | | Quem alterou |

### tbdevedor_tempo_ligacao (9 colunas) — Tempo de Ligação
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| CONTADOR | bigint | | PK | Contador sequencial |
| DEVEDOR_ID | bigint | | FK | ID do devedor |
| FONE_DISCADO | varchar | 20 | | Telefone discado |
| USUARIO_INCLUSAO | varchar | 15 | | Operador |
| DATA_INCLUSAO | smalldatetime | | | Data/hora início |
| DATA_FIM | smalldatetime | | | Data/hora fim |
| DURACAO | varchar | 10 | | Duração formatada |
| HORA_INIC | varchar | 10 | | Hora de início |
| HORA_FINA | varchar | 10 | | Hora de fim |

### tbdevedor_proposta_venda (8 colunas) — Propostas de Venda
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| CONT_ID | smallint | | FK | ID do contratante |
| DEVEDOR_ID | bigint | | FK | ID do devedor |
| PROPOSTA_ID | int | | FK | ID da proposta |
| DESCRICAO | varchar | 20 | X | Descrição da proposta |
| SE_VENDA | char | 1 | | Flag de venda |
| VELOCIDADE | varchar | 30 | | Velocidade do produto |
| DATA_INCLUSAO | smalldatetime | | | Data de inclusão |
| USUARIO_INCLUSAO | varchar | 15 | | Quem incluiu |

### tbacordo_forma_pagamento (14 colunas) — Forma de Pagamento do Acordo
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| ACORDO_ID | varchar | 9 | FK | ID do acordo |
| DEVEDOR_ID | bigint | | FK | ID do devedor |
| TITULO_ID | bigint | | FK | ID do título |
| NUMERO_CHEQUE | varchar | 10 | X | Número do cheque |
| DATA_VENCIMENTO | smalldatetime | | X | Data de vencimento |
| VALOR | numeric | | X | Valor |
| EMITENTE | varchar | 50 | X | Emitente |
| USUARIO_INCLUSAO | varchar | 15 | X | Quem incluiu |
| DATA_INCLUSAO | smalldatetime | | X | Data de inclusão |
| USUARIO_ALTERACAO | varchar | 15 | | Quem alterou |
| DATA_ALTERACAO | smalldatetime | | | Data de alteração |
| NUMERO_AGENCIA | varchar | 6 | | Agência bancária |
| NUMERO_CONTA_CORRENTE | varchar | 10 | | Conta corrente |
| BANCO | varchar | 20 | | Nome do banco |

### tbacordo_repasse (33 colunas) — Repasse do Acordo ao Credor
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| ACORDO_ID | varchar | 9 | FK | ID do acordo |
| DEVEDOR_ID | bigint | | FK | ID do devedor |
| TITULO_ID_ACORDO | bigint | | | Título do acordo |
| TITULO_ID_ORIGINAL | bigint | | | Título original |
| DATA_REPASSE | smalldatetime | | | Data do repasse |
| VALOR_PRINCIPAL_REPASSE | numeric | | | Principal repassado |
| VALOR_PRINCIPAL_COMISSAO | numeric | | | Comissão sobre principal |
| VALOR_PRINCIPAL_SALDO | numeric | | | Saldo do principal |
| VALOR_JUROS_REPASSE | numeric | | | Juros repassados |
| VALOR_JUROS_COMISSAO | numeric | | | Comissão sobre juros |
| VALOR_JUROS_SALDO | numeric | | | Saldo de juros |
| VALOR_MULTA_REPASSE | numeric | | | Multa repassada |
| VALOR_MULTA_COMISSAO | numeric | | | Comissão sobre multa |
| VALOR_MULTA_SALDO | numeric | | | Saldo de multa |
| VALOR_HONORARIO_REPASSE | numeric | | | Honorário repassado |
| VALOR_HONORARIO_COMISSAO | numeric | | | Comissão sobre honorário |
| VALOR_HONORARIO_SALDO | numeric | | | Saldo de honorário |
| VALOR_INDICE_REPASSE | numeric | | | Índice repassado |
| VALOR_INDICE_COMISSAO | numeric | | | Comissão sobre índice |
| VALOR_INDICE_SALDO | numeric | | | Saldo de índice |
| VALOR_ADICIONAL_REPASSE | numeric | | | Adicional repassado |
| VALOR_ADICIONAL_COMISSAO | numeric | | | Comissão sobre adicional |
| VALOR_ADICIONAL_SALDO | numeric | | | Saldo adicional |
| SEQUENCIAL | int | | | Sequencial |
| VALOR_DESCONTO_TOTAL | numeric | | | Desconto total |
| VALOR_DESCONTO_APLICADO | numeric | | | Desconto aplicado |
| VALOR_DESCONTO_SALDO | numeric | | | Saldo de desconto |
| DATA_INCLUSAO | smalldatetime | | | Data de inclusão |
| USUARIO_INCLUSAO | varchar | 15 | | Quem incluiu |
| DATA_ALTERACAO | smalldatetime | | | Data de alteração |
| USUARIO_ALTERACAO | varchar | 15 | | Quem alterou |
| VALOR_REPASSE_SALDO | numeric | | | Saldo do repasse |
| ORDEM | int | | | Ordem |

### tbacordo_comissao (15 colunas) — Comissão do Acordo
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| ACORDO_ID | varchar | 9 | FK | ID do acordo |
| DEVEDOR_ID | bigint | | FK | ID do devedor |
| VALOR_RATEIO_PRINCIPAL | numeric | | X | Rateio do principal |
| VALOR_RATEIO_JURO | numeric | | X | Rateio dos juros |
| VALOR_RATEIO_MULTA | numeric | | X | Rateio da multa |
| VALOR_RATEIO_HONORARIO | numeric | | X | Rateio do honorário |
| VALOR_RATEIO_INDICE | numeric | | | Rateio do índice |
| VALOR_RATEIO_IGPM | numeric | | | Rateio IGPM |
| VALOR_RATEIO_INCC | numeric | | | Rateio INCC |
| VALOR_RATEIO_INPC | numeric | | | Rateio INPC |
| VALOR_COMISSAO | numeric | | X | Valor da comissão |
| VALOR_RECEITA | numeric | | X | Valor da receita |
| QTDE_NOVA_PARCELA | int | | | Qtde de parcelas |
| VALOR_RATEIO_JURO_REPASSE | numeric | | | Rateio de juros no repasse |
| VALOR_RATEIO_ADICIONAL | numeric | | | Rateio adicional |

### tbacordo_pre (28 colunas) — Pré-Acordos
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| PRE_ACORDO_ID | varchar | 9 | PK | ID do pré-acordo |
| DATA | smalldatetime |  | X | Data do pré-acordo |
| DEVEDOR_ID | bigint |  | FK | ID do devedor |
| CONT_ID | smallint |  | FK | ID do contratante |
| QTDE_PRESTACAO_ACORDO | smallint |  | X | Qtde parcelas acordo |
| QTDE_NOVA_PRESTACAO_ACORDO | smallint |  | X | Qtde novas parcelas |
| VALOR_ACORDO | numeric |  | X | Valor do acordo |
| VALOR_NOVA_PARCELA | numeric |  | X | Valor nova parcela |
| NUMERO_CONTRATO | varchar | 25 |  | Número do contrato |
| DATA_INCLUSAO | smalldatetime |  | X | Data de inclusão |
| USUARIO_INCLUSAO | varchar | 15 | X | Quem incluiu |
| DATA_ALTERACAO | smalldatetime |  |  | Data alteração |
| USUARIO_ALTERACAO | varchar | 15 |  | Quem alterou |
| VALOR_ENTRADA | numeric |  |  | Valor de entrada |
| CANCEL | bit |  |  | Cancelado |
| PAGO | bit |  |  | Pago |
| CAMPANHA_ID | smallint |  | FK | ID da campanha |
| CNAB_ID | int |  | FK | ID do CNAB |
| BOLETO_ID | varchar | 20 |  | ID do boleto |
| CODIGO_BARRA | varchar | 44 |  | Código de barras |
| LINHA_DIGITAVEL | varchar | 60 |  | Linha digitável |
| DATA_VENCIMENTO | smalldatetime |  |  | Data vencimento |
| MENSAGEM | varchar | 200 |  | Mensagem |
| PERC_DESCONTO_PRINC | numeric |  |  | % desconto principal |
| PERC_DESCONTO_JUROS | numeric |  |  | % desconto juros |
| PERC_DESCONTO_MULTA | numeric |  |  | % desconto multa |
| PERC_DESCONTO_HONOR | numeric |  |  | % desconto honorário |
| VALOR_ORIGINAL | numeric |  |  | Valor original |

### tbacordo_ws (11 colunas) — Acordo via WebService
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| ACORDO_ID | bigint | | PK | ID do acordo |
| DEVEDOR_ID | bigint | | FK | ID do devedor |
| CONT_ID | smallint | | FK | ID do contratante |
| DATA | smalldatetime | | X | Data |
| VALOR | numeric | | | Valor total |
| VALOR_JURO | numeric | | | Juros |
| VALOR_MULTA | numeric | | | Multa |
| VALOR_DESCONTO | numeric | | | Desconto |
| VALOR_DESPESA | numeric | | | Despesas |
| VALOR_TAXAADM | numeric | | | Taxa administrativa |
| VALOR_TOTAL | numeric | | | Valor total final |

### tbacordo_titulos_original (16 colunas) — Títulos Originais do Acordo
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| ACORDO_ID | varchar | 9 | FK | ID do acordo |
| TITULO_ID | bigint | | FK | ID do título |
| DEVEDOR_ID | bigint | | FK | ID do devedor |
| DATA_VENCIMENTO | smalldatetime | | X | Vencimento original |
| NUMERO_CONTRATO | varchar | 30 | | Contrato |
| NUMERO_DOCUMENTO | varchar | 25 | | Documento |
| NUMERO_PRESTACAO | smallint | | X | Número da prestação |
| QTDE_PRESTACAO | smallint | | X | Total de prestações |
| VALOR | numeric | | X | Valor |
| VALOR_JURO | numeric | | X | Juros |
| VALOR_MULTA | numeric | | X | Multa |
| VALOR_HONO | numeric | | X | Honorários |
| USUARIO_INCLUSAO | varchar | 15 | X | Quem incluiu |
| DATA_INCLUSAO | smalldatetime | | X | Data de inclusão |
| VALOR_COMISSAO | numeric | | | Comissão |
| VALOR_RECEITA | numeric | | | Receita |

### tbtitulo_boleto (7 colunas) — Boletos Vinculados a Títulos
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| BOLETO_ID | varchar | 20 | FK | ID do boleto |
| TITULO_ID | bigint | | FK | ID do título |
| VALOR | numeric | | X | Valor |
| VALOR_JURO | numeric | | X | Juros |
| VALOR_MULTA | numeric | | X | Multa |
| VALOR_DESCONTO | numeric | | X | Desconto |
| VALOR_HONORARIO | numeric | | X | Honorário |

### tbtitulo_contrato (10 colunas) — Contratos dos Títulos
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| DATA_IMPORTACAO | datetime | | FK | Data de importação |
| CONT_ID | smallint | | FK | ID do contratante |
| DEVEDOR_ID | bigint | | FK | ID do devedor |
| NUMERO_CONTRATO | varchar | 20 | X | Número do contrato |
| QTDE_PRESTACAO | int | | X | Qtde de prestações |
| USUARIO_INCLUSAO | varchar | 15 | X | Quem incluiu |
| DATA_INCLUSAO | smalldatetime | | X | Data de inclusão |
| LOJA_ID | varchar | 35 | | ID da loja |
| VALOR_PREMIO | numeric | | | Valor do prêmio |
| ID_TRANSACAO | varchar | 40 | | ID da transação |

### tbemail (19 colunas) — Contas de Email
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| ID | smallint |  | PK | ID da conta |
| EMAIL | varchar | 180 | X | Endereço email |
| PORTA | smallint |  | X | Porta SMTP |
| SMTP_SERVIDOR | varchar | 60 | X | Servidor SMTP |
| SMTP_USUARIO_AUTENTICA | varchar | 60 | X | Usuário de autenticação |
| SMTP_SENHA_AUTENTICA | varchar | 60 |  | Senha (campo sensível) |
| SMTP_EMAIL_RETORNO | varchar | 180 | X | Email de retorno |
| SMTP_EMAIL_NOME | varchar | 30 | X | Nome do remetente |
| TIPO | char | 1 | X | Tipo |
| DATA_INCLUSAO | smalldatetime |  | X | Data de criação |
| USUARIO_INCLUSAO | varchar | 15 | X | Quem criou |
| DATA_ALTERACAO | smalldatetime |  |  | Data alteração |
| USUARIO_ALTERACAO | varchar | 15 |  | Quem alterou |
| SSL | char | 1 |  | Usa SSL |
| TLS | char | 1 |  | Usa TLS |
| CONT_ID | int |  | FK | ID do contratante |
| SE_COPIA_EMAIL_OPER | char | 1 |  | Cópia para operador |
| TIPO_INTEGRACAO | varchar | 30 |  | Tipo de integração |
| HOST | varchar | 100 |  | Host |

### tbemail_texto (26 colunas) — Templates de Email
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| EMAIL_TEXTO_ID | int |  | PK | ID do template |
| CONTRATANTE_ID | smallint |  | FK | ID do contratante |
| TITULO | varchar | 120 |  | Título/assunto |
| TEXTO_SUPERIOR | text | MAX |  | Texto superior |
| USUARIO_INCLUSAO | varchar | 15 |  | Quem criou |
| DATA_INCLUSAO | datetime |  |  | Data de criação |
| USUARIO_ALTERACAO | varchar | 15 |  | Quem alterou |
| DATA_ALTERACAO | datetime |  |  | Data alteração |
| PATH_ARQUIVO_TEXTO_SUPERIOR | varchar | 250 |  | Caminho texto superior |
| PATH_ARQUIVO_TEXTO_INFERIOR | varchar | 250 |  | Caminho texto inferior |
| TEXTO_INFERIOR | text | MAX |  | Texto inferior |
| PATH_ARQUIVO_ANEXO | varchar | 250 |  | Caminho anexo |
| PATH_ARQUIVO_IMAGEM_SUPERIOR | varchar | 250 |  | Caminho imagem superior |
| PATH_ARQUIVO_IMAGEM_INFERIOR | varchar | 250 |  | Caminho imagem inferior |
| EMAIL_ACAO_ID | varchar | 250 |  | ID ação de email |
| ACAO_ID | int |  | FK | ID da ação |
| HTML_BODY_COMPLETO | varchar | 3000 |  | HTML body completo |
| TIPO_ENVIO | char | 1 |  | Tipo de envio |
| ATIVO | char | 1 |  | Ativo S/N |
| EMAIL_DESTINATARIO | varchar | 160 |  | Email destinatário |
| TIPO_CONFISSAO_DIVIDA | char | 2 |  | Tipo confissão dívida |
| SOMENTE_MENSAGEM | char | 1 |  | Somente mensagem |
| MENSAGEM | varchar | 1500 |  | Mensagem |
| ANEXO_POR_EMAIL | char | 1 |  | Anexo por email |
| PATH_ARQUIVO_ANEXO_POR_EMAIL | varchar | 250 |  | Caminho anexo email |
| SE_IMPORTACAO | char | 1 |  | É importação |

### tbemail_texto_campo (4 colunas) — Campos de Template
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| EMAIL_TEXTO_ID | int | | FK | ID do template |
| SEQU_ID | smallint | | | Sequencial |
| CAMPO | varchar | 25 | | Nome do campo |
| DESCRICAO | varchar | 25 | | Descrição |

### tbdistribuicao (17 colunas) — Distribuição de Carteiras
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| DISTRIBUICAO_ID | bigint | | PK | ID da distribuição |
| CONT_ID | smallint | | FK | ID do contratante |
| FAIXA_INIC | int | | | Faixa de atraso inicial |
| FAIXA_FINA | int | | | Faixa de atraso final |
| QTDE | int | | | Quantidade |
| VALOR | numeric | | | Valor |
| ASSESSORIA_ID | smallint | | FK | ID da assessoria |
| COBRADOR_ID | int | | FK | ID do cobrador |
| DATA_SAIDA | smalldatetime | | | Data de saída |
| DATA_RETORNO | smalldatetime | | | Data de retorno |
| LOJA_ID | varchar | 35 | | ID da loja |
| NUMERO_REMESSA | varchar | 8 | | Número da remessa |
| SELE | smallint | | | Flag de seleção |
| DATA_INCLUSAO | smalldatetime | | | Data de inclusão |
| USUARIO_INCLUSAO | varchar | 15 | | Quem incluiu |
| DATA_ALTERACAO | smalldatetime | | | Data de alteração |
| USUARIO_ALTERACAO | varchar | 15 | | Quem alterou |

### tbdistribuicao_movimento (8 colunas) — Movimentação da Distribuição
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| DISTRIBUICAO_ID | bigint | | FK | ID da distribuição |
| SEQU_ID | int | | | Sequencial |
| DATA_EMISSAO | smalldatetime | | X | Data de emissão |
| QTDE_DISTRIBUIDA | int | | X | Quantidade distribuída |
| QTDE_ENTREGUE | int | | | Quantidade entregue |
| QTDE_DEVOLVIDA | int | | | Quantidade devolvida |
| DATA_INCLUSAO | smalldatetime | | X | Data de inclusão |
| USUARIO_INCLUSAO | varchar | 15 | X | Quem incluiu |

### tbregra (39 colunas) — Regras de Cobrança
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| REGRA_ID | int |  | PK | ID da regra |
| CONT_ID | smallint |  | FK | Contratante |
| DATA | smalldatetime |  | X | Data da regra |
| PROMESSA_PRO_DIA | char | 1 | X | Promessa pro dia |
| FAIXA_INICIAL | smallint |  |  | Atraso mínimo (dias) |
| FAIXA_FINAL | smallint |  |  | Atraso máximo (dias) |
| VALOR_INICIAL | numeric |  |  | Valor mínimo |
| VALOR_FINAL | numeric |  |  | Valor máximo |
| QTDE_DIAS_EXPIRA | smallint |  |  | Dias para expirar |
| PRIORIDADE | smallint |  |  | Prioridade |
| DATA_INCLUSAO | smalldatetime |  | X | Data inclusão |
| USUARIO_INCLUSAO | varchar | 15 | X | Quem incluiu |
| DATA_ALTERACAO | smalldatetime |  |  | Data alteração |
| USUARIO_ALTERACAO | varchar | 15 |  | Quem alterou |
| NOME | varchar | 50 | X | Nome da regra |
| SE_ATIVO | char | 1 |  | Ativo S/N |
| SE_ACORDO_TITULO | char | 1 |  | Acordo por título |
| SE_CRIA_FILA | char | 1 |  | Cria fila automaticamente |
| DIRECIONA_FILA_COBRADOR | char | 1 |  | Direciona para cobrador |
| HORARIO_PROGRAMADO | varchar | 5 |  | Horário de execução |
| SE_PRIMEIRA_COMPRA | char | 1 |  | Flag primeira compra |
| ID_CAMPANHA | int |  | FK | ID da campanha |
| BEHAVIOR_INICIAL | smallint |  |  | Behavior mínimo |
| BEHAVIOR_FINAL | smallint |  |  | Behavior máximo |
| EXECUCAO | char | 1 |  | Modo de execução |
| SE_PERMITE_REFIN | char | 1 |  | Permite refinanciamento |
| EQUIPE_ID | int |  | FK | ID da equipe |
| ID_CARTAO_INICIAL | char | 1 |  | Cartão inicial |
| ID_CARTAO_FINAL | char | 1 |  | Cartão final |
| SE_FORA_REGRA | char | 1 |  | Flag fora da regra |
| SE_VALOR_CALCULADO | char | 1 |  | Usa valor calculado |
| SEM_ACIONAMENTO | char | 1 |  | Sem acionamento |
| SEM_ACIONAMENTO2 | char | 1 |  | Sem acionamento 2 |
| DEFASAGEM_INICIAL | smallint |  |  | Defasagem inicial |
| DEFASAGEM_FINAL | smallint |  |  | Defasagem final |
| DISCADOR_ID | smallint |  | FK | ID do discador |
| QTDE_CLIENTES | int |  |  | Qtde de clientes |
| VALOR | numeric |  |  | Valor |
| GRUPO_ID | smallint |  | FK | ID do grupo |

### tbregra_situacao_cobranca (4 colunas) — Situações da Regra
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| REGRA_ID | int | | FK | ID da regra |
| SITUACAO_ID | smallint | | FK | ID da situação |
| DATA_INCLUSAO | smalldatetime | | | Data de inclusão |
| USUARIO_INCLUSAO | varchar | 15 | | Quem incluiu |

### tbregra_uf (4 colunas) — UFs da Regra
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| REGRA_ID | int | | FK | ID da regra |
| UF | char | 2 | | UF |
| DATA_INCLUSAO | smalldatetime | | | Data de inclusão |
| USUARIO_INCLUSAO | varchar | 15 | | Quem incluiu |

### tbrenitencia (4 colunas) — Renitências
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| RENITENCIA_ID | bigint |  | PK | ID da renitência |
| CONT_ID | smallint |  | FK | ID do contratante |
| DESCRICAO | varchar | 30 |  | Descrição |
| DATA_INCLUSAO | smalldatetime |  |  | Data de inclusão |

### tbrenitencia_regra (10 colunas) — Regras de Renitência
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| RENITENCIA_ID | int | | FK | ID da renitência |
| CONT_ID | smallint | | FK | ID do contratante |
| ACAO_ID | int | | FK | ID da ação de cobrança |
| TIPO_FONE | char | 1 | | Tipo de telefone |
| HORARIO_INICIAL | varchar | 5 | | Horário inicial |
| HORARIO_FINAL | varchar | 5 | | Horário final |
| INTERVALO | smallint | | | Intervalo em minutos |
| QTDE_TENTATIVA | smallint | | | Qtde de tentativas |
| DATA_INCLUSAO | smalldatetime | | | Data de inclusão |
| USUARIO_INCLUSAO | varchar | 15 | | Quem incluiu |

### tbcampanha_desconto (18 colunas) — Descontos de Campanha
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| CAMPANHA_ID | int |  | FK | ID da campanha |
| NUMERO_DOCUMENTO | varchar | 25 | X | Número documento |
| CPF | varchar | 14 | X | CPF |
| VALOR_SALDO_CONGELADO | numeric |  | X | Saldo congelado |
| VALOR_SALDO_ATUALIZADO | numeric |  | X | Saldo atualizado |
| VALOR_LIQUIDACAO | numeric |  |  | Valor liquidação |
| VALOR_PARCELADO | numeric |  |  | Valor parcelado |
| QTDE_PARCELA | int |  | X | Qtde parcelas |
| STRING_ORIGINAL | text | MAX |  | String original |
| USUARIO_INCLUSAO | varchar | 15 |  | Quem incluiu |
| DATA_INCLUSAO | smalldatetime |  |  | Data inclusão |
| USUARIO_ALTERACAO | varchar | 15 |  | Quem alterou |
| DATA_ALTERACAO | smalldatetime |  |  | Data alteração |
| DATA_IMPORTACAO | datetime |  |  | Data importação |
| DEVEDOR_ID | bigint |  | FK | ID do devedor |
| SELE | smallint |  |  | Seleção |
| VALOR_ENTRADA | numeric |  |  | Valor entrada |
| CONT_ID | int |  | FK | ID contratante |

### tbcampanha_oferta (3 colunas) — Ofertas de Campanha
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| CAMPANHA_ID | int | | FK | ID da campanha |
| OFERTA_ID | int | | PK | ID da oferta |
| QTDE_PARCELA | int | | X | Qtde de parcelas |

### tbcontratante_contato (9 colunas) — Contatos do Contratante
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| CC_ID | smallint | | PK | ID do contato |
| CONTRATANTE_ID | smallint | | FK | ID do contratante |
| NOME | varchar | 50 | X | Nome do contato |
| DEPARTAMENTO | varchar | 25 | | Departamento |
| FUNCAO | varchar | 20 | | Função |
| EMAIL | varchar | 160 | | Email |
| FONE | varchar | 11 | X | Telefone |
| NUMERO_AGENCIA | varchar | 6 | | Agência |
| NUMERO_FILIAL | varchar | 20 | | Filial |

### tbcontratante_fase (15 colunas) — Fases por Contratante
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| CONT_ID | smallint |  | FK | ID do contratante |
| FASE_ID | smallint |  | PK | ID da fase |
| FAIXA_INIC | smallint |  | X | Atraso inicial |
| FAIXA_FINAL | smallint |  | X | Atraso final |
| NOME | varchar | 30 |  | Nome da fase |
| AUXILIAR | varchar | 10 |  | Campo auxiliar |
| PERC_COMISSAO1 | float |  |  | % comissão 1 |
| PERC_COMISSAO2 | float |  |  | % comissão 2 |
| PERC_COORDENADOR | float |  |  | % coordenador |
| PERC_GERENTE | float |  |  | % gerente |
| PERC_DIRETOR | float |  |  | % diretor |
| SE_ATUALIZA_FASE | char | 1 |  | Atualiza fase |
| PERC_COMISSAO3 | float |  |  | % comissão 3 |
| PERC_META | float |  |  | % meta |
| DATA_INCLUSAO | smalldatetime |  |  | Data inclusão |

### tbcontratante_campanha (24 colunas) — Campanhas por Contratante
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| CONT_ID | smallint |  | FK | ID do contratante |
| SEQU_ID | int |  | PK | ID sequencial |
| DESCRICAO | varchar | 150 | X | Descrição |
| TIPO_ACORDO | varchar | 4 |  | Tipo de acordo |
| TIPO_CARTAO | char | 2 |  | Tipo de cartão |
| FORMA_ACORDO | char | 1 |  | Forma do acordo |
| DATA_INICIO | smalldatetime |  |  | Data início |
| DATA_FINAL | smalldatetime |  |  | Data final |
| OPCAO_ACORDO | char | 3 |  | Opção de acordo |
| QTDE_MINIMA_PARC | smallint |  |  | Parcelas mínimas |
| QTDE_MAXIMA_PARC | smallint |  |  | Parcelas máximas |
| PERC_DESCONTO | numeric |  |  | % desconto |
| PERC_ENTRADA | numeric |  |  | % entrada |
| VALOR_MINIMO_PARCELA | numeric |  |  | Valor mín parcela |
| TIPO_SALDO_DEVEDOR | char | 1 |  | Tipo saldo devedor |
| PERC_JURO_ACORDO | numeric |  |  | % juros acordo |
| PERC_ACORDO_PARC | numeric |  |  | % acordo parcela |
| DATA_IMPORTACAO | datetime |  |  | Data importação |
| DATA_INCLUSAO | smalldatetime |  |  | Data inclusão |
| USUARIO_INCLUSAO | varchar | 15 |  | Quem incluiu |
| DATA_ALTERACAO | smalldatetime |  |  | Data alteração |
| USUARIO_ALTERACAO | varchar | 15 |  | Quem alterou |
| STRING_ORIGINAL | text | MAX |  | String original |
| VALOR_ENTRADA | numeric |  |  | Valor entrada |

### tbcontratante_comissao (8 colunas) — Comissões por Contratante
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| CONT_ID | smallint | | FK | ID do contratante |
| MES_ANO | varchar | 6 | X | Mês/ano |
| DATA_IMPORTACAO | datetime | | X | Data de importação |
| VALOR | numeric | | X | Valor |
| STRING_ORIGINAL | text | MAX | | String original |
| MES | smallint | | | Mês |
| ANO | smallint | | | Ano |
| DATA_PAGTO | smalldatetime | | | Data do pagamento |

### tbcontratante_questao (9 colunas) — Perguntas por Contratante
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| PERGUNTA_ID | int |  | PK | ID da pergunta |
| INDAGACAO | varchar | 1000 |  | Texto da pergunta |
| CONT_ID | smallint |  | FK | ID do contratante |
| SE_OBSE | char | 1 | X | Requer observação |
| DATA_INCLUSAO | smalldatetime |  | X | Data inclusão |
| USUARIO_INCLUSAO | varchar | 15 | X | Quem incluiu |
| DATA_ALTERACAO | smalldatetime |  |  | Data alteração |
| USUARIO_ALTERACAO | varchar | 15 |  | Quem alterou |
| SE_APRESENTACAO | char | 1 |  | É de apresentação |

### tbcontratante_questao_resposta (12 colunas) — Respostas às Perguntas
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| PERGUNTA_ID | int |  | FK | ID da pergunta |
| SEQU_ID | int |  | PK | ID sequencial |
| TIPO_RESPOSTA | varchar | 20 | X | Tipo de resposta |
| RESPOSTA | char | 1 |  | Resposta |
| NOTA | int |  |  | Nota |
| VISIBILIDADE | char | 1 | X | Visibilidade |
| DATA_INCLUSAO | smalldatetime |  | X | Data inclusão |
| USUARIO_INCLUSAO | varchar | 15 | X | Quem incluiu |
| DATA_ALTERACAO | smalldatetime |  |  | Data alteração |
| USUARIO_ALTERACAO | varchar | 15 |  | Quem alterou |
| PULA_PERGUNTA | bit |  |  | Pula pergunta |
| PROXIMA_PERGUNTA | smallint |  |  | Próxima pergunta |

### tbcontratante_criterio_acordo (25 colunas) — Critérios de Acordo por Contratante
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| CONT_ID | smallint |  | FK | ID do contratante |
| SEQU_ID | int |  | PK | ID sequencial |
| NUMERO_CONTRATO | varchar | 25 | X | Número contrato |
| CPF | varchar | 14 | X | CPF |
| DEVEDOR_ID | bigint |  | FK | ID do devedor |
| TIPO_ACORDO | varchar | 8 | X | Tipo de acordo |
| DATA_INICIO | datetime |  | X | Data início |
| DATA_FINAL | datetime |  | X | Data final |
| DIAS_CARENCIA | smallint |  | X | Dias de carência |
| TAXA_JUROS_CARENCIA | numeric |  | X | Taxa juros carência |
| NUMERO_PAGAMENTO_NAO_CUMPRIDO | smallint |  |  | Pagamentos não cumpridos |
| DIAS_ATRASO_MIN | smallint |  | X | Dias atraso mínimo |
| DIAS_ATRASO_MAX | smallint |  | X | Dias atraso máximo |
| TIPO_COTA | varchar | 10 | X | Tipo de cota |
| TAXA_JUROS | numeric |  |  | Taxa de juros |
| IMPOSTO | numeric |  |  | Imposto |
| DIAS_PAGAMENTO_INICIAL | smallint |  |  | Dias pagamento inicial |
| DIAS_PAGAMENTO_FINAL | smallint |  |  | Dias pagamento final |
| NUMERO_PAGAMENTO_MAXIMO | smallint |  |  | Pagamento máximo |
| STRING_ORIGINAL | text | MAX |  | String original |
| DATA_IMPORTACAO | datetime |  |  | Data importação |
| QTDE_PARCELA | smallint |  |  | Qtde parcelas |
| VALOR_PARCELA | numeric |  |  | Valor parcela |
| VALOR_TOTAL_PARCELA | numeric |  |  | Valor total parcela |
| DESCRICAO_PROPOSTA | varchar | 120 |  | Descrição proposta |

### tbcontratante_exportacao (17 colunas) — Exportações por Contratante
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| CONT_ID | smallint |  | FK | ID do contratante |
| DATA_EXPORTACAO | datetime |  | PK | Data da exportação |
| SEQUENCIAL | int |  | X | Sequencial |
| QTDE | int |  | X | Quantidade |
| VALOR_ARQUIVO | numeric |  |  | Valor do arquivo |
| NOME_ARQUIVO | varchar | 250 |  | Nome do arquivo |
| DATA_INCLUSAO | smalldatetime |  | X | Data inclusão |
| USUARIO_INCLUSAO | varchar | 15 | X | Quem incluiu |
| ASSESSORIA_ID | smallint |  | FK | ID da assessoria |
| TIPO | varchar | 10 |  | Tipo |
| PERIODO | varchar | 50 |  | Período |
| CAMPANHA_ID | int |  | FK | ID campanha |
| PLANO01 | smallint |  |  | Plano 01 |
| PLANO02 | smallint |  |  | Plano 02 |
| PLANO03 | smallint |  |  | Plano 03 |
| PLANO04 | smallint |  |  | Plano 04 |
| VALOR_DESPESAS | numeric |  |  | Valor despesas |

### tbcontratante_agenda_importacao (20 colunas) — Agenda de Importação por Contratante
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| cont_id | smallint |  | FK | ID do contratante |
| agenda_id | smallint |  | PK | ID da agenda |
| nome | varchar | 30 |  | Nome |
| taskfilename | varchar | 200 |  | Arquivo da tarefa |
| taskparameters | varchar | 30 |  | Parâmetros |
| active | int |  |  | Ativo |
| weekly | int |  |  | Semanal |
| daily | int |  |  | Diário |
| one_sho | int |  |  | Única vez |
| time | varchar | 8 |  | Hora |
| date | varchar | 10 |  | Data |
| monday | int |  |  | Segunda |
| tuesday | int |  |  | Terça |
| wednesday | int |  |  | Quarta |
| thursday | int |  |  | Quinta |
| friday | int |  |  | Sexta |
| saturday | int |  |  | Sábado |
| sunday | int |  |  | Domingo |
| time_last_executed | varchar | 8 |  | Hora última execução |
| date_last_executed | varchar | 10 |  | Data última execução |

### tbtipo_pausa (11 colunas) — Tipos de Pausa
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| ID | smallint |  | PK | ID do tipo |
| NOME | varchar | 20 | X | Nome da pausa |
| TEMPO | smallint |  | X | Tempo em minutos |
| TIPO_PAUSA | char | 1 |  | Tipo |
| TIPO_PAUSA_DISCADOR_ID | int |  | FK | ID pausa discador |
| TEMPO_TOLERANCIA | smallint |  |  | Tolerância |
| DATA_INCLUSAO | smalldatetime |  |  | Data inclusão |
| USUARIO_INCLUSAO | varchar | 15 |  | Quem incluiu |
| DATA_ALTERACAO | smalldatetime |  |  | Data alteração |
| USUARIO_ALTERACAO | varchar | 15 |  | Quem alterou |
| SE_BLOQUEIO_NR17 | char | 1 |  | Bloqueio NR17 |

### tbtipo_importacao (6 colunas) — Tipos de Importação
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| ID | int | | PK | ID do tipo |
| DESCRICAO | varchar | 90 | X | Descrição |
| DATA_INCLUSAO | smalldatetime | | X | Data de inclusão |
| USUARIO_INCLUSAO | varchar | 15 | X | Quem incluiu |
| DATA_ALTERACAO | smalldatetime | | | Última alteração |
| USUARIO_ALTERACAO | varchar | 15 | | Quem alterou |

### tbtipo_baixa (2 colunas) — Tipos de Baixa
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| TIPO_BAIXA_ID | char | 1 | PK | Código da baixa |
| DESCRICAO | varchar | 50 | X | Descrição |

### tbtipo_avalista (3 colunas) — Tipos de Avalista
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| TIPO_AVALISTA_ID | smallint | | PK | ID do tipo |
| DESCRICAO | varchar | 50 | X | Descrição |
| SE_ATIVO | char | 1 | | Ativo S/N |

### tbblack_list — Lista Negra de Telefones
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| FONE | varchar | 11 | PK | Telefone bloqueado |
| DATA_INCLUSAO | smalldatetime | | | Data de inclusão |
| USUARIO_INCLUSAO | varchar | 15 | | Quem incluiu |

### tbindice — Índices Econômicos
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| INDICE_ID | smallint | | PK | ID do índice |
| ANO | smallint | | | Ano |
| MES | smallint | | | Mês |
| VALOR | numeric | | | Valor do índice |
| NOME | varchar | 20 | | Nome do índice |

### tblocalidade_uf — Unidades Federativas
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| UF | char | 2 | PK | Sigla do estado |
| NOME | varchar | 50 | | Nome do estado |
| COD_ESTADO | int | | | Código IBGE |

### tblocalidade_cidade — Cidades
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| COD_CIDADE | int | | PK | Código IBGE |
| NOME | varchar | 100 | | Nome da cidade |
| UF | char | 2 | FK | Sigla do estado |
| COD_ESTADO | int | | | Código IBGE estado |

### tblocalidade_ddd — DDDs
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| DDD | varchar | 4 | PK | Código DDD |
| UF | char | 2 | | Sigla do estado |
| CIDADE | varchar | 100 | | Cidade |

### tbformula (17 colunas) — Fórmulas de Cálculo
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| FORMULA_ID | int |  | PK | ID da fórmula |
| NOME | varchar | 70 | X | Nome da fórmula |
| UTIL_VENC_ANTIGO | char | 1 |  | Utiliza vencimento antigo |
| INDICE | char | 1 |  | Índice |
| SE_TAXA_CREDOR | char | 1 |  | Taxa do credor |
| SE_TAXA_CREDOR_MAIS_JUROS | char | 1 |  | Taxa credor + juros |
| SE_DESCONTO_SOB_ATRASO | char | 1 |  | Desconto sob atraso |
| SE_CALCULA | char | 1 |  | Calcula |
| SE_NAO_CORRIGE_HONORARIO | char | 1 |  | Não corrige honorário |
| SE_CALCULA_JUROS_PERIODO_DIFERENTE | char | 1 |  | Juros período diferente |
| SE_RECALCULA_HONORARIO | char | 1 |  | Recalcula honorário |
| SE_NAO_CORRIGE_ENCARGOS | char | 1 |  | Não corrige encargos |
| SE_PARAMETRO_ACORDO | char | 1 |  | Parâmetro acordo |
| SE_JUROS_PRO_RATA_TEMPORIS | char | 1 |  | Juros pro rata |
| SE_CALCULA_DESCONTO_ANO_COMPETENCIA | char | 1 |  | Desconto ano competência |
| SE_DESCONTO_SOB_ATRASO_CONTRATO | char | 1 |  | Desconto atraso contrato |
| SE_RECALCULA_HONORARIO_TITULO_ACORDO | char | 1 |  | Recalcula hon. título acordo |

### tbformula_calculo (28 colunas) — Regras de Cálculo da Fórmula
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| FORMULA_ID | int |  | FK | ID da fórmula |
| FORMULA_CALCULO_ID | smallint |  | PK | ID do cálculo |
| TIPO | char | 1 | X | Tipo |
| PERC_MIN | numeric |  |  | % mínimo |
| PERC_MAX | numeric |  |  | % máximo |
| TIPO_CALCULO | varchar | 15 |  | Tipo de cálculo |
| DATA_INCLUSAO | smalldatetime |  |  | Data inclusão |
| USUARIO_INCLUSAO | varchar | 15 |  | Quem incluiu |
| DATA_ALTERACAO | smalldatetime |  |  | Data alteração |
| USUARIO_ALTERACAO | varchar | 15 |  | Quem alterou |
| MAQUINA | varchar | 20 |  | Máquina |
| CALCULO_SOB | varchar | 70 |  | Cálculo sobre |
| ORDEM | smallint |  |  | Ordem |
| DIAS_INIC | smallint |  |  | Dias inicial |
| DIAS_FINA | smallint |  |  | Dias final |
| DIAS | smallint |  |  | Dias |
| SEGMENTO | varchar | 50 |  | Segmento |
| FORMA_PAGTO | char | 1 |  | Forma pagamento |
| SE_TAXA_CREDOR | char | 1 |  | Taxa credor |
| QTDE_PARCELA_INIC | int |  |  | Parcelas inicial |
| QTDE_PARCELA_FINA | int |  |  | Parcelas final |
| VALOR_INICIAL | numeric |  |  | Valor inicial |
| VALOR_FINAL | numeric |  |  | Valor final |
| PERC_MIN_WEB | numeric |  |  | % mín web |
| PERC_MAX_WEB | numeric |  |  | % máx web |
| SCORE_INICIAL | varchar | 10 |  | Score inicial |
| SCORE_FINAL | varchar | 10 |  | Score final |
| PERCENTUAL_ENTRADA | numeric |  |  | % entrada |


### tbformula_receita (18 colunas) — Receitas da Fórmula
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| FORMULA_ID | int |  | FK | ID da fórmula |
| FORMULA_CALCULO_ID | smallint |  | FK | ID do cálculo |
| PERC_VALOR_PRINC | numeric |  |  | % valor principal |
| PERC_VALOR_JUROS | numeric |  |  | % valor juros |
| PERC_VALOR_MULTA | numeric |  |  | % valor multa |
| PERC_VALOR_HONOR | numeric |  |  | % valor honorário |
| DATA_INCLUSAO | smalldatetime |  |  | Data inclusão |
| USUARIO_INCLUSAO | varchar | 15 |  | Quem incluiu |
| DATA_ALTERACAO | smalldatetime |  |  | Data alteração |
| USUARIO_ALTERACAO | varchar | 15 |  | Quem alterou |
| MAQUINA | varchar | 20 |  | Máquina |
| ORDEM | smallint |  |  | Ordem |
| DIAS_INIC | smallint |  |  | Dias inicial |
| DIAS_FINA | smallint |  |  | Dias final |
| DIAS | smallint |  |  | Dias |
| PERC_VALOR_INDIC | numeric |  |  | % indicador |
| PERC_VALOR_JUROS_RETI | numeric |  |  | % juros retirados |
| PERC_VALOR_ADIC | numeric |  |  | % adicional |

### tbformula_desconto (0 colunas) — Fórmulas de Desconto
> Tabela existe no banco mas possui schema vazio (0 colunas em sys.columns). Possivelmente reservada para uso futuro.

### tbformula_acordo (13 colunas) — Acordo da Fórmula
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| FORMULA_ID | int |  | FK | ID da fórmula |
| FORMULA_ACORDO_ID | smallint |  | PK | ID do acordo |
| DIAS_INIC | smallint |  | X | Dias inicial |
| DIAS_FINA | smallint |  | X | Dias final |
| CALCULO_SOB | varchar | 30 |  | Cálculo sobre |
| FORMA_PAGAMENTO | char | 1 |  | Forma pagamento |
| PERC_MIN | numeric |  |  | % mínimo |
| PERC_MAX | numeric |  |  | % máximo |
| DATA_INCLUSAO | smalldatetime |  | X | Data inclusão |
| USUARIO_INCLUSAO | varchar | 15 | X | Quem incluiu |
| DATA_ALTERACAO | smalldatetime |  |  | Data alteração |
| USUARIO_ALTERACAO | varchar | 15 |  | Quem alterou |
| MAQUINA | varchar | 20 |  | Máquina |

### tbcnab (14 colunas) — Arquivos CNAB
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| CNAB_ID | int |  | PK | ID do CNAB |
| NOME_ARQUIVO | varchar | 30 | X | Nome do arquivo |
| DATA | smalldatetime |  | X | Data |
| BANCO | varchar | 20 | X | Banco |
| NUMERO_BANCO | varchar | 3 | X | Número do banco |
| QTDE_REGISTRO | smallint |  | X | Qtde registros |
| EMPRESA | varchar | 30 | X | Empresa |
| SITUACAO | char | 1 |  | Situação |
| VALOR_PROCESSADO | numeric |  |  | Valor processado |
| VALOR_ARQUIVO | numeric |  | X | Valor do arquivo |
| usuario_inclusao | varchar | 15 |  | Quem incluiu |
| QTDE_REGISTRO_PROCESSADO | smallint |  |  | Registros processados |
| OCOR_DATA | smalldatetime |  |  | Data ocorrência |
| LAYOUT | varchar | 50 |  | Layout |

### tbcnab_arquivo (5 colunas) — Detalhes Arquivo CNAB
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| CNAB_ID | int | | FK | ID do CNAB |
| SEQU_ID | int | | PK | Sequencial |
| TEXTO | text | MAX | | Conteúdo da linha |
| DATA_INCLUSAO | smalldatetime | | | Data de inclusão |
| USUARIO_INCLUSAO | varchar | 15 | | Quem incluiu |

### tbtela (2 colunas) — Telas do Sistema
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| TELA_ID | varchar | 20 | PK | ID da tela |
| DESCRICAO | varchar | 50 | X | Descrição da tela |

### tbtela_botao (4 colunas) — Botões das Telas
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| TELA_ID | varchar | 20 | FK | ID da tela |
| BOTA_ID | varchar | 15 | PK | ID do botão |
| DESCRICAO | varchar | 55 | X | Descrição do botão |
| ORDEM | smallint |  | X | Ordem de exibição |

### tbtela_operador (8 colunas) — Permissões de Tela por Operador
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| TELA_ID | smallint | | FK | ID da tela |
| OPERADOR_ID | varchar | 15 | FK | Login do operador |
| SE_CONSULTA | char | 1 | | Permite consulta |
| SE_INCLUSAO | char | 1 | | Permite inclusão |
| SE_ALTERACAO | char | 1 | | Permite alteração |
| SE_EXCLUSAO | char | 1 | | Permite exclusão |
| DATA_INCLUSAO | smalldatetime | | | Data de inclusão |
| USUARIO_INCLUSAO | varchar | 15 | | Quem incluiu |

### tbtela_perfil (6 colunas) — Perfis de Tela
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| TELA_ID | smallint | | FK | ID da tela |
| PERFIL_ID | smallint | | FK | ID do perfil |
| SE_CONSULTA | char | 1 | | Permite consulta |
| SE_INCLUSAO | char | 1 | | Permite inclusão |
| SE_ALTERACAO | char | 1 | | Permite alteração |
| SE_EXCLUSAO | char | 1 | | Permite exclusão |

### tbtela_perfil_botao (4 colunas) — Botões por Perfil de Tela
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| TELA_ID | smallint | | FK | ID da tela |
| BOTAO_ID | smallint | | FK | ID do botão |
| PERFIL_ID | smallint | | FK | ID do perfil |
| SE_ATIV | char | 1 | | Ativo S/N |

### tbboleto_perfil (64 colunas) — Perfis de Boleto
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| PERFIL_ID | smallint |  | PK | ID do perfil |
| DESCRICAO | varchar | 50 | X | Descrição |
| TEXTO | varchar | 5000 | X | Texto do boleto |
| VALOR_TAXA | numeric |  |  | Valor da taxa |
| BANCO | varchar | 3 | X | Código do banco |
| NOME_BANCO | varchar | 25 | X | Nome do banco |
| AGENCIA | varchar | 10 | X | Agência |
| CONTA | varchar | 15 |  | Conta |
| CARTEIRA | varchar | 5 | X | Carteira |
| TIPO | varchar | 35 |  | Tipo |
| CEDENTE | varchar | 100 |  | Cedente |
| CNPJ_CEDENTE | varchar | 14 |  | CNPJ cedente |
| LOGOMARCA | varchar | 100 |  | Logomarca |
| AGENCIA_DIGITO | char | 1 |  | DV agência |
| CONTA_DIGITO | char | 1 |  | DV conta |
| INSTRUCAO | varchar | 1500 |  | Instruções |
| ASSUNTO | varchar | 100 |  | Assunto |
| MENSAGEM | varchar | 8000 |  | Mensagem |
| CODIGO_CEDENTE | varchar | 10 |  | Código cedente |
| INSTRUCAO_ACORDO | varchar | 1500 |  | Instrução acordo |
| ENDERECO | varchar | 120 |  | Endereço |
| BAIRRO | varchar | 30 |  | Bairro |
| CIDADE | varchar | 30 |  | Cidade |
| UF | varchar | 2 |  | UF |
| LOCAL_PAGTO | varchar | 160 |  | Local pagamento |
| CEP | varchar | 8 |  | CEP |
| ASSESSORIA_ID | smallint |  | FK | ID assessoria |
| SE_REIMPRIME_BOLETO_PAGO | char | 1 |  | Reimprime pago |
| VARIACAO | varchar | 5 |  | Variação |
| PERCENTUAL_JUROS | numeric |  |  | % juros |
| CODIGO_EMPRESA | varchar | 20 |  | Código empresa |
| SEQUENCIAL_CREDOR | char | 1 |  | Sequencial credor |
| SE_SEQUENCIAL_NOSSO_NUMERO | char | 1 |  | Seq nosso número |
| NOSSO_NUMERO_ID | bigint |  |  | ID nosso número |
| QTDE_DIAS_ALTE_BOLE | smallint |  |  | Dias alt boleto |
| EXPORTACAO_CNAB_ID | int |  | FK | ID exportação CNAB |
| CLIENT_SECRET | varchar | 250 |  | Client secret (sensível) |
| CLIENT_KEY | varchar | 50 |  | Client key (sensível) |
| CLIENT_ID | varchar | 50 |  | Client ID (sensível) |
| SE_CRITICA_ENDERECO_SACADO | char | 1 |  | Critica endereço |
| SE_CANCELA_BOLETO_AVENCER | char | 1 |  | Cancela a vencer |
| PERCENTUAL_MULTA | numeric |  |  | % multa |
| DATA_INCLUSAO | smalldatetime |  |  | Data inclusão |
| USUARIO_INCLUSAO | varchar | 15 |  | Quem incluiu |
| DATA_ALTERACAO | smalldatetime |  |  | Data alteração |
| USUARIO_ALTERACAO | varchar | 15 |  | Quem alterou |
| SE_SOMENTE_TITULO_ACORDO | char | 1 |  | Somente título acordo |
| QTDE_DIAS_BAIXA_BANCO | smallint |  |  | Dias baixa banco |
| SE_VISUALIZA_VALOR_ORIG_DETA | char | 1 |  | Visualiza valor original |
| CLIENT_AUTH | varchar | 500 |  | Autenticação (sensível) |
| DATA_VALIDA_TOKEN | datetime |  |  | Validade token |
| LOCAL_PAGTO_PIX | varchar | 160 |  | Local pgto PIX |
| INSTRUCAO_PIX | varchar | 1500 |  | Instrução PIX |
| CHAVE_PIX | varchar | 150 |  | Chave PIX |
| CAMINHO_CERTIFICADO_CRT | varchar | 400 |  | Caminho cert CRT |
| CAMINHO_CERTIFICADO_KEY | varchar | 400 |  | Caminho cert KEY |
| CLIENT_ID_PIX | varchar | 500 |  | Client ID PIX (sensível) |
| CLIENT_SECRET_PIX | varchar | 500 |  | Client secret PIX (sensível) |
| CAMINHO_CERTIFICADO_CRT_PIX | varchar | 400 |  | Cert CRT PIX |
| CAMINHO_CERTIFICADO_KEY_PIX | varchar | 400 |  | Cert KEY PIX |
| HOST_API | varchar | 250 |  | Host API |
| ENDPOINT_WEBHOOK | varchar | 250 |  | Endpoint webhook |
| TIPO_CHAVE_PIX | varchar | 30 |  | Tipo chave PIX |
| MODELO_ID_PIX | smallint |  |  | Modelo PIX |

### tbcnab_titulos (9 colunas) — Títulos do CNAB
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| CNAB_ID | int | | FK | ID do CNAB |
| BOLETO_ID | varchar | 20 | X | ID do boleto |
| TITULO_ID | bigint | | FK | ID do título |
| VALOR | numeric | | X | Valor |
| VALOR_JURO | numeric | | | Juros |
| VALOR_MULTA | numeric | | | Multa |
| VALOR_HONO | numeric | | | Honorários |
| VALOR_DESC | numeric | | | Desconto |
| VALOR_TAXA | numeric | | | Taxa |

### tbtitulo_liberacao (15 colunas) — Liberações de Título
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| LIDA | char | 1 | | Flag lida |
| CONT_ID | bigint | | FK | ID do contratante |
| DEVEDOR_ID | bigint | | FK | ID do devedor |
| OPERADOR_ID | varchar | 15 | | Operador solicitante |
| NUMERO_PARCELA | int | | | Número da parcela |
| DATA | smalldatetime | | | Data da solicitação |
| DESCONTO_MAX | numeric | | | Desconto máximo permitido |
| DESCONTO_SOLICITADO | numeric | | | Desconto solicitado |
| VALOR | numeric | | | Valor do título |
| VALOR_DESCONTO | numeric | | | Valor do desconto |
| VALOR_DESC_SOLIC | numeric | | | Valor desconto solicitado |
| AUTORIZA_DESCONTO | char | 1 | | Flag autorização |
| OBSE | text | MAX | | Observações |
| DATA_VALIDADE | smalldatetime | | | Validade da liberação |
| VALOR_ENTRADA | numeric | | | Valor de entrada |

### tbtitulo_anexo (9 colunas) — Anexos do Título
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| ANEXO_ID | smallint | | PK | ID do anexo |
| TITULO_ID | bigint | | FK | ID do título |
| DEVEDOR_ID | bigint | | FK | ID do devedor |
| ARQUIVO | text | MAX | X | Conteúdo do arquivo (base64) |
| NOME_ARQUIVO | varchar | 100 | X | Nome do arquivo |
| FORMATO_ARQUIVO | varchar | 30 | | Formato (pdf, jpg, etc.) |
| TAMANHO_ARQUIVO | varchar | 10 | | Tamanho |
| USUARIO_INCLUSAO | varchar | 25 | X | Quem incluiu |
| DATA_INCLUSAO | smalldatetime | | X | Data de inclusão |

### tbtitulo_calculo (41 colunas) — Cálculos de Títulos
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|

| TITULO_ID | bigint | | FK | ID do título |
| VALOR_ORIGINAL | numeric | | X | Valor original |
| VALOR_ORIGINAL_CALC | numeric | | | Valor original calculado |
| VALOR_JUROS_ORIG | numeric | | | Juros original |
| VALOR_JUROS_CALC | numeric | | | Juros calculado |
| VALOR_MULTA_ORIG | numeric | | | Multa original |
| VALOR_MULTA_CALC | numeric | | | Multa calculada |
| VALOR_HONO_ORIG | numeric | | | Honorário original |
| VALOR_HONO_CALC | numeric | | | Honorário calculado |
| DATA_INCLUSAO | smalldatetime | | | Data inclusão |
| USUARIO_INCLUSAO | varchar | 15 | | Quem incluiu |
| DEVEDOR_ID | bigint | | FK | ID do devedor |
| VALOR_IGPM_ORIG | numeric | | | IGPM original |
| VALOR_IGPM_CALC | numeric | | | IGPM calculado |
| VALOR_INCC_ORIG | numeric | | | INCC original |
| VALOR_INCC_CALC | numeric | | | INCC calculado |
| VALOR_INPC_ORIG | numeric | | | INPC original |
| VALOR_INPC_CALC | numeric | | | INPC calculado |
| VALOR_ADICIONAL1 | numeric | | | Adicional 1 |
| VALOR_ADICIONAL2 | numeric | | | Adicional 2 |
| VALOR_COMISSAO_ORIG | numeric | | | Comissão original |
| VALOR_COMISSAO_CALC | numeric | | | Comissão calculada |
| VALOR_RECEITA_ORIG | numeric | | | Receita original |
| VALOR_RECEITA_CALC | numeric | | | Receita calculada |
| VALOR_ADICIONAL1_CALC | numeric | | | Adicional 1 calculado |
| VALOR_ADICIONAL2_CALC | numeric | | | Adicional 2 calculado |
| SE_CREDITO | bit | | | É crédito |
| SOLICITACAO_ID | int | | FK | ID solicitação |
| ATRASO | int | | | Dias de atraso |
| VALOR_IPCA_CALC | numeric | | | IPCA calculado |
| VALOR_IPCA_ORIG | numeric | | | IPCA original |
| VALOR_IPCA_DESC | numeric | | | IPCA desconto |
| VALOR_ORIGINAL_DESC | numeric | | | Original desconto |
| VALOR_JUROS_DESC | numeric | | | Juros desconto |
| VALOR_MULTA_DESC | numeric | | | Multa desconto |
| VALOR_HONO_DESC | numeric | | | Honorário desconto |
| VALOR_IGPM_DESC | numeric | | | IGPM desconto |
| VALOR_INCC_DESC | numeric | | | INCC desconto |
| VALOR_INPC_DESC | numeric | | | INPC desconto |
| VALOR_ADICIONAL1_DESC | numeric | | | Adicional 1 desconto |
| VALOR_ADICIONAL2_DESC | numeric | | | Adicional 2 desconto |

### tbtitulo_garantia (22 colunas) — Garantias de Títulos
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| DEVEDOR_ID | bigint | | PK/FK | ID do devedor |
| CONT_ID | int | | PK/FK | ID do contratante |
| NUMERO_CONTRATO | varchar | 20 | X | Número do contrato |
| PLACA | varchar | 10 | X | Placa do veículo |
| MODELO | varchar | 50 | | Modelo do veículo |
| CHASSI | varchar | 30 | | Chassi |
| COR | varchar | 20 | | Cor do veículo |
| ANO_MODELO | varchar | 8 | X | Ano/modelo |
| UF | char | 2 | | UF |
| RENAVAN | varchar | 15 | | Renavan |
| DATA_IMPORTACAO | datetime | | | Data de importação |
| DATA_INCLUSAO | smalldatetime | | | Data de inclusão |
| USUARIO_INCLUSAO | varchar | 15 | | Quem incluiu |
| DATA_ALTERACAO | smalldatetime | | | Data de alteração |
| USUARIO_ALTERACAO | varchar | 15 | | Quem alterou |
| DATA_APREENSAO | smalldatetime | | | Data de apreensão |
| FIRMA | varchar | 10 | | Firma |
| ANO_FABRICACAO | varchar | 10 | | Ano de fabricação |
| STRING_ORIGINAL | varchar | 1000 | | String original da importação |
| VALOR_GARANTIA | numeric | | | Valor da garantia |
| ID_AUTO | varchar | 15 | | ID automático |
| DEVEDOR_ID_AUX | bigint | | FK | ID devedor auxiliar |

### tbregra_estrategia (113 colunas) — Estratégias de Regra
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| REGRA_ID | int |  | FK | ID da regra |
| ESTRATEGIA_ID | smallint |  | PK | ID da estratégia |
| TIPO_PESSOA | char | 1 |  | F=Física, J=Jurídica |
| ESTADO_CIVIL | char | 1 |  | Estado civil |
| SEXO | char | 1 |  | M/F |
| SE_POSSUI_EMAIL | char | 1 |  | Possui email |
| SE_NAO_POSSUI_EMAIL | char | 1 |  | Não possui email |
| DATA_NASCIMENTO_INICIAL | smalldatetime |  |  | Nascimento inicial |
| DATA_NASCIMENTO_FINAL | smalldatetime |  |  | Nascimento final |
| IDADE_INICIAL | smallint |  |  | Idade mínima |
| IDADE_FINAL | smallint |  |  | Idade máxima |
| SE_FPD | char | 1 |  | First Payment Default |
| FAIXA_ATRASO_INICIAL | smallint |  |  | Atraso mínimo |
| FAIXA_ATRASO_FINAL | smallint |  |  | Atraso máximo |
| VALOR_DIVIDA_INICIAL | numeric |  |  | Valor dívida mínimo |
| VALOR_DIVIDA_FINAL | numeric |  |  | Valor dívida máximo |
| VALOR_RISCO_INICIAL | numeric |  |  | Risco mínimo |
| VALOR_RISCO_FINAL | numeric |  |  | Risco máximo |
| DATA_ENTRADA_CONTRATO_INICIAL | smalldatetime |  |  | Entrada contrato inicial |
| DATA_ENTRADA_CONTRATO_FINAL | smalldatetime |  |  | Entrada contrato final |
| DATA_LIMITE_CONTRATO_INICIAL | smalldatetime |  |  | Limite contrato inicial |
| DATA_LIMITE_CONTRATO_FINAL | smalldatetime |  |  | Limite contrato final |
| DATA_PARCELA_ACORDO_INICIAL | smalldatetime |  |  | Parcela acordo inicial |
| DATA_PARCELA_ACORDO_FINAL | smalldatetime |  |  | Parcela acordo final |
| QTDE_CONTRATO | smallint |  |  | Qtde contratos |
| OPERADOR_QTDE_CONTRATO | char | 1 |  | Operador qtde contrato |
| CLIENTE_NUNCA_TEVE_ACORDO | char | 1 |  | Nunca teve acordo |
| CLIENTE_JA_TEVE_ACORDO | char | 1 |  | Já teve acordo |
| CLIENTE_JA_TEVE_PAGAMENTO | char | 1 |  | Já teve pagamento |
| CLIENTE_SEM_FONE | char | 1 |  | Sem telefone |
| CLIENTE_COM_FONE | char | 1 |  | Com telefone |
| CLIENTE_COM_CELULAR | char | 1 |  | Com celular |
| CLIENTE_SOMENTE_COM_CELULAR | char | 1 |  | Somente celular |
| SE_POSSUI_ACORDO | char | 1 |  | Possui acordo |
| DESAFAGEM_INICIAL | smallint |  |  | Defasagem inicial |
| DESAFAGEM_FINAL | smallint |  |  | Defasagem final |
| DDD_FONE | char | 2 |  | DDD |
| REMESSA_ID | varchar | 1000 |  | IDs de remessa |
| LOJA_ID | varchar | 1000 |  | IDs de loja |
| TIPO_VARIAVEL_QTDE_SMS | char | 1 |  | Tipo var qtde SMS |
| QTDE_SMS | smallint |  |  | Qtde SMS |
| PERCENTUAL_FONE_INICIAL | smallint |  |  | % fone inicial |
| PERCENTUAL_FONE_FINAL | smallint |  |  | % fone final |
| CIDADE | varchar | 500 |  | Cidade |
| SE_FORNECIMENTO | varchar | 3 |  | Fornecimento |
| SQL | text | MAX |  | SQL customizado |
| ESTRATEGIA | text | MAX |  | Estratégia customizada |
| TIPO_VARIAVEL_QTDE_ACIONAMENTO | char | 1 |  | Tipo var qtde acion |
| QTDE_ACIONAMENTO | smallint |  |  | Qtde acionamentos |
| NAO_CONTENHA_TIPO_ACIONAMENTO | char | 1 |  | Não contenha tipo acion |
| NAO_EXISTA_ACIONAMENTO | char | 1 |  | Não exista acionamento |
| CLIENTE_COM_TELEFONE_FIXO | char | 1 |  | Com tel fixo |
| CLIENTE_SOMENTE_COM_TELEFONE_FIXO | char | 1 |  | Somente fixo |
| TIPO_FONE_DISCADOR | varchar | 40 |  | Tipo fone discador |
| PROPRIEDADE_ID | varchar | 50 |  | ID propriedade |
| SE_CLIENTE_TEVE_ALO | char | 1 |  | Cliente teve alô |
| PERCENTUAL_PAGAMENTO_CONTRATO | numeric |  |  | % pgto contrato |
| LOCALIDADE | varchar | 1000 |  | Localidade |
| SITUACAO | varchar | 1000 |  | Situação |
| DATA_VENCIMENTO_INICIAL | smalldatetime |  |  | Vencimento inicial |
| DATA_VENCIMENTO_FINAL | smalldatetime |  |  | Vencimento final |
| CLASSIFICACAO_ACIONAMENTO | varchar | 12 |  | Classificação acion |
| QTDE_DIAS_SEM_ACIONAMENTO_POSITIVO | smallint |  |  | Dias s/ acion positivo |
| QTDE_DIAS_COM_ACIONAMENTO_POSITIVO | smallint |  |  | Dias c/ acion positivo |
| CALCULA_RISCO_CPF | char | 1 |  | Calcula risco CPF |
| CALCULA_RISCO_CONTRATO | char | 1 |  | Calcula risco contrato |
| PERFIL_SMS_ID | smallint |  | FK | ID perfil SMS |
| DATA_VENCIMENTO_BOLETO_INICIAL | smalldatetime |  |  | Venc boleto inicial |
| DATA_VENCIMENTO_BOLETO_FINAL | smalldatetime |  |  | Venc boleto final |
| QTDE_DIAS_VENCIMENTO_BOLETO_INICIAL | smallint |  |  | Dias venc boleto ini |
| QTDE_DIAS_VENCIMENTO_BOLETO_FINAL | smallint |  |  | Dias venc boleto fin |
| AREA_RISCO | varchar | 3 |  | Área de risco |
| CALCULA_RISCO_VENCIDAS_VINCENDAS | char | 1 |  | Risco venc+vinc |
| CALCULA_RISCO_VENCIDAS | char | 1 |  | Risco vencidas |
| TIPO_CENTRAL | smallint |  |  | Tipo central |
| CAMPANHA_ID | varchar | 50 |  | ID campanha |
| PERFIL_EMAIL_ID | int |  | FK | ID perfil email |
| COBRADOR_ID | varchar | 5000 |  | IDs cobrador |
| INDICADOR | varchar | 1000 |  | Indicador |
| INDICADOR_DESCRICAO | varchar | 1000 |  | Descrição indicador |
| QTDE_DIAS_EXPIRAR_CONTRATO | int |  |  | Dias expirar contrato |
| QTDE_DIAS_EXPIRAR_CONTRATO_FINAL | int |  |  | Dias expirar cont final |
| QTDE_DIAS_IMPORTACAO_INICIAL | int |  |  | Dias importação ini |
| QTDE_DIAS_IMPORTACAO_FINAL | int |  |  | Dias importação fin |
| PERCENTUAL_PAGAMENTO_CONTRATO_FINAL | numeric |  |  | % pgto cont final |
| PRODUTO_ID | varchar | 5000 |  | IDs produto |
| HORA_INICIO | varchar | 5 |  | Hora início |
| SE_LIMPA_CAMPANHA_DISCADOR | char | 1 |  | Limpa campanha disc |
| FREQUENCIA | char | 1 |  | Frequência |
| OCORRE_FORMA | char | 1 |  | Forma ocorrência |
| DIASEM_SEG | char | 1 |  | Segunda |
| DIASEM_TER | char | 1 |  | Terça |
| DIASEM_QUA | char | 1 |  | Quarta |
| DIASEM_QUI | char | 1 |  | Quinta |
| DIASEM_SEX | char | 1 |  | Sexta |
| DIASEM_SAB | char | 1 |  | Sábado |
| DIASEM_DOM | char | 1 |  | Domingo |
| DATA_INICIO | datetime |  |  | Data início |
| DATA_FINAL | datetime |  |  | Data final |
| HORA_INICIO_AGENDADA | varchar | 10 |  | Hora início agendada |
| HORA_FINAL_AGENDADA | varchar | 10 |  | Hora final agendada |
| OCORRE_TEMPO | varchar | 15 |  | Tempo ocorrência |
| TEMPO | smallint |  |  | Tempo |
| QTDE_PRESTACAO_INICIAL | int |  |  | Prestações inicial |
| QTDE_PRESTACAO_FINAL | int |  |  | Prestações final |
| DEPARTAMENTO | varchar | 1000 |  | Departamento |
| NOME_ARQUIVO_CAMPANHA | varchar | 70 |  | Arquivo campanha |
| LOTE_ID | varchar | 1000 |  | IDs lote |
| SETOR_ID | varchar | 1000 |  | IDs setor |
| TIPO_PRODUTO | varchar | 1000 |  | Tipo produto |
| ID_PRODUTO | varchar | 1000 |  | ID produto |
| QTDE_DIAS_VENCIMENTO_ACORDO_INICIAL | smallint |  |  | Dias venc acordo ini |
| QTDE_DIAS_VENCIMENTO_ACORDO_FINAL | smallint |  |  | Dias venc acordo fin |

### tbcontrole_canais (13 colunas) — Controle de Canais de Comunicação
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| ID | int |  | PK | ID do controle |
| DEVEDOR_ID | bigint |  | FK | ID do devedor |
| TIPO | varchar | 10 | X | Tipo de canal |
| ORIGEM | varchar | 20 | X | Origem da comunicação |
| DATA_INCLUSAO | smalldatetime |  | X | Data/hora |
| OPERADOR_ID | varchar | 15 | FK | Operador |
| PERFIL_ID | smallint |  | FK | Perfil de SMS |
| SENTIDO | char | 1 | X | E=Entrada, S=Saída |
| MENSAGEM | nvarchar | 300 |  | Conteúdo da mensagem |
| ID_NOTIFICACAO | int |  |  | ID notificação |
| SE_CONVERSA_LIDA | bit |  | X | Conversa lida |
| FONE | varchar | 15 | X | Telefone |
| DATA_INCLUSAO_DIA | date |  |  | Data (somente dia) |

### tbauditoria (11 colunas) — Auditoria de Atendimento
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| DATA | smalldatetime | | X | Data/hora |
| OPERADOR_ID | varchar | 15 | X | Operador auditado |
| DEVEDOR_ID | bigint | | X | ID do devedor |
| CONT_ID | int | | X | ID do contratante |
| AUDITOR_ID | varchar | 15 | | Auditor |
| RAMAL | int | | | Ramal da ligação |
| SCRIPT | text | MAX | | Script esperado |
| MENSAGEM | text | MAX | | Mensagem do operador |
| RESPOSTA | text | MAX | | Resposta da auditoria |
| LIDO | char | 1 | | Flag lida |
| SE_APROVADA | char | 1 | | Aprovada S/N |

### tbassessoria (9 colunas) — Assessorias de Cobrança
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| ASSESSORIA_ID | smallint | | PK | ID da assessoria |
| NOME | varchar | 50 | X | Nome da assessoria |
| CNPJ | varchar | 14 | | CNPJ |
| ENDERECO | varchar | 50 | | Endereço |
| SE_ATIV | char | 1 | X | Ativo S/N |
| FONE | varchar | 11 | | Telefone |
| EMAIL | varchar | 80 | | Email |
| DATA_INCLUSAO | smalldatetime | | | Data de cadastro |
| USUARIO_INCLUSAO | varchar | 15 | | Quem cadastrou |

### tbcoordenador (7 colunas) — Coordenadores
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| COORDENADOR_ID | int | | PK | ID do coordenador |
| NOME | varchar | 50 | X | Nome completo |
| SE_ATIV | char | 1 | X | Ativo S/N |
| DATA_INCLUSAO | smalldatetime | | | Data de cadastro |
| USUARIO_INCLUSAO | varchar | 15 | | Quem cadastrou |
| DATA_ALTERACAO | smalldatetime | | | Última alteração |
| USUARIO_ALTERACAO | varchar | 15 | | Quem alterou |

### tbperfil (10 colunas) — Perfis de Operador
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| PERFIL_ID | smallint |  | PK | ID do perfil |
| NOME | varchar | 35 |  | Nome do perfil |
| CONT_ID | smallint |  | FK | ID do contratante |
| DATA_INCLUSAO | smalldatetime |  | X | Data de cadastro |
| USUARIO_INCLUSAO | varchar | 15 | X | Quem cadastrou |
| DATA_ALTERACAO | smalldatetime |  |  | Data alteração |
| USUARIO_ALTERACAO | varchar | 15 |  | Quem alterou |
| TIPO_CALCULO_PREMIACAO | char | 1 |  | Tipo cálculo premiação |
| VALOR_META_GERAL | numeric |  |  | Meta geral valor |
| PERCENTUAL_META_GERAL | numeric |  |  | Meta geral % |

### tbponto (6 colunas) — Ponto de Operadores
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| DATA | smalldatetime | | PK | Data |
| OPERADOR_ID | varchar | 15 | X | Operador |
| HORA | varchar | 10 | X | Hora de entrada |
| HORA_FINA | varchar | 10 | | Hora de saída |
| HORA_SAIDA | varchar | 8 | | Hora de saída (formato alternativo) |
| MAQUINA | varchar | 30 | | Máquina |

### tbcontratante_faixa_atraso (8 colunas) — Faixas de Atraso por Contratante
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|-----------|
| CONT_ID | smallint | | PK/FK | ID contratante |
| SEQU_ID | smallint | | PK | Sequencial |
| CONT_ID_AUX | smallint | | X | Contratante auxiliar |
| FAIXA_ATRASO | int | | X | Faixa de atraso (dias) |
| DATA_INCLUSAO | smalldatetime | | | Data inclusão |
| USUARIO_INCLUSAO | varchar | 15 | | Quem incluiu |
| FILIAL | varchar | 50 | | Filial |
| GRUPO | varchar | 10 | | Grupo |


### tbcontratante_filial (14 colunas) — Filiais por Contratante
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|-----------|
| CONT_ID | smallint | | PK/FK | ID contratante |
| FILI_ID | smallint | | PK | ID filial |
| NOME | varchar | 100 | X | Nome da filial |
| ENDERECO | varchar | 100 | | Endereço |
| BAIRRO | varchar | 30 | | Bairro |
| CIDADE | varchar | 30 | | Cidade |
| UF | char | 2 | | Estado |
| CEP | varchar | 8 | | CEP |
| CNPJ | varchar | 14 | | CNPJ |
| CODIGO_INTERNO | varchar | 10 | | Código interno |
| DATA_INCLUSAO | smalldatetime | | | Data inclusão |
| USUARIO_INCLUSAO | varchar | 15 | | Quem incluiu |
| DATA_ALTERACAO | smalldatetime | | | Data alteração |
| USUARIO_ALTERACAO | varchar | 15 | | Quem alterou |


### tbcontratante_grupo (2 colunas) — Grupos de Contratantes
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|-----------|
| GRUPO_ID | smallint | | PK | ID do grupo |
| NOME | varchar | 40 | X | Nome do grupo |


### tbcontratante_produto (10 colunas) — Produtos por Contratante
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|-----------|
| CONT_ID | smallint | | PK/FK | ID contratante |
| PRODUTO_ID | varchar | 10 | PK | ID produto |
| DESCRICAO | varchar | 60 | X | Descrição do produto |
| DATA_INCLUSAO | smalldatetime | | X | Data inclusão |
| USUARIO_INCLUSAO | varchar | 15 | X | Quem incluiu |
| DATA_ALTERACAO | smalldatetime | | | Data alteração |
| USUARIO_ALTERACAO | varchar | 15 | | Quem alterou |
| NATUREZA | varchar | 10 | | Natureza do produto |
| TIPO_PRODUTO | varchar | 35 | | Classificação do produto |
| OBSE | varchar | 500 | | Observações |

### tbcontratante_arquivo (3 colunas) — Arquivos por Contratante
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|-----------|
| CONT_ID | smallint | | PK/FK | ID contratante |
| ARQU_ID | smallint | | PK | ID arquivo |
| NOMENCLATURA | varchar | 20 | X | Nomenclatura do arquivo |

### tbcontratante_associado (6 colunas) — Associados por Contratante
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|-----------|
| CONT_ID | smallint | | PK/FK | ID contratante |
| ASSOCIADO_ID | varchar | 15 | PK | ID associado |
| ASSOCIADO_NOME | varchar | 150 | | Nome do associado |
| EMAIL_TEXTO_ID | int | | | ID do template de email |
| DATA_INCLUSAO | datetime | | | Data inclusão |
| USUARIO_INCLUSAO | varchar | 15 | | Quem incluiu |

### tbcontratante_batimento (15 colunas) — Batimentos por Contratante
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|-----------|
| NOME_ARQUIVO | varchar | 20 | X | Nome do arquivo |
| SEQU_ID | bigint | | PK | Sequencial |
| DEVEDOR_ID | varchar | 14 | | ID devedor |
| NUMERO_CONTRATO | varchar | 20 | X | Número contrato |
| NUMERO_DOCUMENTO | varchar | 25 | | Número documento |
| VALOR | numeric | | | Valor batimento |
| DATA_ENVIO | smalldatetime | | | Data envio |
| CONT_ID | smallint | | FK | ID contratante |
| DATA_VENCIMENTO | smalldatetime | | | Data vencimento |
| DATA_INCLUSAO | smalldatetime | | | Data inclusão |
| USUARIO_INCLUSAO | varchar | 15 | | Quem incluiu |
| DATA_IMPORTACAO | datetime | | | Data importação |
| SE_ACHOU | char | 1 | | Encontrou match S/N |
| CPF | varchar | 14 | | CPF devedor |
| DATA_PAGTO | smalldatetime | | | Data pagamento |

### tbcontratante_confissao_divida (5 colunas) — Confissão de Dívida por Contratante
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|-----------|
| CONT_ID | smallint | | PK/FK | ID contratante |
| CONFISSAO_DIVIDA_ID | char | 3 | PK | ID confissão |
| DESCRICAO | varchar | 70 | | Descrição do modelo |
| USUARIO_INCLUSAO | varchar | 15 | | Quem incluiu |
| DATA_INCLUSAO | smalldatetime | | | Data inclusão |

### tbcontratante_exportacao_detalhe (10 colunas) — Detalhes de Exportação por Contratante
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|-----------|
| CONT_ID | smallint | | PK/FK | ID contratante |
| DATA_EXPORTACAO | datetime | | PK | Data da exportação |
| DEVEDOR_ID | bigint | | PK | ID devedor |
| TITULO_ID | bigint | | PK | ID título |
| VALOR | numeric | | X | Valor exportado |
| VALOR_OPCAO01 | numeric | | | Valor opção 1 |
| VALOR_OPCAO02 | numeric | | | Valor opção 2 |
| VALOR_OPCAO03 | numeric | | | Valor opção 3 |
| VALOR_OPCAO04 | numeric | | | Valor opção 4 |
| VALOR_AVISTA | numeric | | | Valor à vista |

### tbcontratante_exportacao_prestacao_contas (18 colunas) — Prestação de Contas da Exportação
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|-----------|
| DATA_EXPORTACAO | datetime | | PK | Data exportação |
| SEQUENCIAL | int | | PK | Sequencial |
| TITULO_ID | bigint | | FK | ID título |
| DEVEDOR_ID | bigint | | FK | ID devedor |
| CONT_ID | smallint | | FK | ID contratante |
| ACORDO_ID | varchar | 15 | X | ID acordo |
| NUMERO_CONTRATO | varchar | 40 | X | Número contrato |
| NUMERO_DOCUMENTO | varchar | 30 | X | Número documento |
| VALOR_ORIGINAL | numeric | | X | Valor original |
| VALOR_JUROS | numeric | | X | Valor juros |
| VALOR_DEBITADO_PRINCIPAL | numeric | | | Valor debitado (principal) |
| VALOR_DEBITADO_JUROS | numeric | | | Valor debitado (juros) |
| VALOR_SALDO_PRINCIPAL | numeric | | X | Saldo principal |
| VALOR_SALDO_JUROS | numeric | | X | Saldo juros |
| DATA_INCLUSAO | smalldatetime | | X | Data inclusão |
| USUARIO_INCLUSAO | varchar | 15 | X | Quem incluiu |
| DATA_ALTERACAO | smalldatetime | | | Data alteração |
| USUARIO_ALTERACAO | varchar | 15 | | Quem alterou |

### tbcontratante_indicador (9 colunas) — Indicadores por Contratante
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|-----------|
| CONT_ID | smallint | | PK/FK | ID contratante |
| INDICADOR_ID | int | | PK | ID indicador |
| INDICADOR | varchar | 20 | X | Código indicador |
| CODIGO_INTERNO | varchar | 20 | X | Código interno |
| NOME | varchar | 100 | X | Nome do indicador |
| DATA_INCLUSAO | smalldatetime | | X | Data inclusão |
| USUARIO_INCLUSAO | varchar | 15 | X | Quem incluiu |
| DATA_ALTERACAO | smalldatetime | | | Data alteração |
| USUARIO_ALTERACAO | varchar | 15 | | Quem alterou |

### tbcontratante_lista_campo (4 colunas) — Campos Personalizados por Contratante
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|-----------|
| CONTRATANTE_ID | smallint | | PK/FK | ID contratante |
| SEQU_ID | smallint | | PK | Sequencial |
| CAMPO | varchar | 25 | X | Nome do campo |
| DESCRICAO | varchar | 25 | | Descrição do campo |

### tbcontratante_meta (21 colunas) — Metas por Contratante
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|-----------|
| META_ID | int | | PK | ID da meta |
| CONT_ID | int | | FK | ID contratante |
| DATA_INICIO | smalldatetime | | X | Data início |
| DATA_FINAL | smalldatetime | | | Data final |
| META_INICIAL_CONTR_ATRASO | numeric | | | Meta inicial atraso |
| META_INICIAL_CONTR_PREJUIZO | numeric | | | Meta inicial prejuízo |
| META_REAL_CONTR_ATRASO | numeric | | | Meta real atraso |
| META_REAL_CONTR_PREJUIZO | numeric | | | Meta real prejuízo |
| REALIZADO_CONTR_ATRASO | numeric | | | Realizado atraso |
| REALIZADO_CONTR_PREJUIZO | numeric | | | Realizado prejuízo |
| DATA_IMPORTACAO | datetime | | | Data importação |
| QTDE_ACIONAMENTO_MES | int | | | Acionamentos/mês |
| DATA_INCLUSAO | smalldatetime | | | Data inclusão |
| USUARIO_INCLUSAO | varchar | 15 | | Quem incluiu |
| QTDE_ACIONAMENTO_DIA | int | | | Acionamentos/dia |
| QTDE_ACORDO_MES | int | | | Acordos/mês |
| QTDE_ACORDO_DIA | int | | | Acordos/dia |
| DATA_ALTERACAO | smalldatetime | | | Data alteração |
| QTDE_DIAS_UTEIS | int | | | Dias úteis |
| USUARIO_ALTERACAO | varchar | 15 | | Quem alterou |
| STRING_ORIGINAL | text | MAX | | String original importação |

### tbcontratante_perfil_fila (5 colunas) — Perfis de Fila por Contratante
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|-----------|
| CONTRATANTE_ID | smallint | | PK/FK | ID contratante |
| SEQU_ID | smallint | | PK | Sequencial |
| DESCRICAO_CAMPO | varchar | 50 | X | Descrição do campo |
| DATA_INCLUSAO | smalldatetime | | X | Data inclusão |
| USUARIO_INCLUSAO | varchar | 15 | X | Quem incluiu |

### tbcontratante_previa_eficiencia (12 colunas) — Prévia de Eficiência por Contratante
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|-----------|
| CONT_ID | smallint | | PK/FK | ID contratante |
| FASE | varchar | 10 | X | Fase de cobrança |
| DATA | smalldatetime | | PK | Data referência |
| VALOR_CARTEIRA | numeric | | | Valor da carteira |
| VALOR_META | numeric | | | Valor da meta |
| PERC_META | numeric | | | Percentual da meta |
| VALOR_RECEBIDO | numeric | | | Valor recebido |
| PERC_RECEBIDO_CARTEIRA | numeric | | | % recebido/carteira |
| PERC_META_RECEBIDO | numeric | | | % meta recebido |
| DATA_IMPORTACAO | datetime | | | Data importação |
| USUARIO_INCLUSAO | varchar | 15 | | Quem incluiu |
| SEQUENCIAL_ID | smallint | | | Sequencial |


## Relacionamentos (Foreign Keys)

> Mapa de FKs declarados no banco via `sys.foreign_keys`. Relacionamentos implícitos (sem FK formal, como tbacordo_titulos) são indicados separadamente.

```
tbdevedor.CONT_ID → tbcontratante.CONTRATANTE_ID
tbdevedor.DATA_IMPORTACAO → tbimportacao.DATA_IMPORTACAO
tbdevedor_acionamento.DEVEDOR_ID → tbdevedor.DEVEDOR_ID
tbdevedor_acionamento.ACAO_ID → tbacao_cobranca.ACAO_ID
tbdevedor_acionamento.COBRADOR_ID → tbcobrador.COBRADOR_ID
tbdevedor_fone.DEVEDOR_ID → tbdevedor.DEVEDOR_ID
tbdevedor_proposta_venda.DEVEDOR_ID → tbdevedor.DEVEDOR_ID
tbdevedor_proposta_venda.CONT_ID → tbcontratante.CONTRATANTE_ID

tbtitulo.DEVEDOR_ID → tbdevedor.DEVEDOR_ID
tbtitulo.CONT_ID → tbcontratante.CONTRATANTE_ID
tbtitulo.COBRADOR_ID → tbcobrador.COBRADOR_ID
tbtitulo.ACAO_ID → tbacao_cobranca.ACAO_ID
tbtitulo.TIPO_TITULO_ID → tbtipo_titulo.TIPO_TITULO_ID
tbtitulo.PERFIL_ID → tbboleto_perfil.PERFIL_ID
tbtitulo.DATA_IMPORTACAO → tbimportacao.DATA_IMPORTACAO
tbtitulo_anexo.TITULO_ID → tbtitulo.TITULO_ID
tbtitulo_boleto.TITULO_ID → tbtitulo.TITULO_ID
tbtitulo_boleto.BOLETO_ID → tbboleto.BOLETO_ID
tbtitulo_garantia.DATA_IMPORTACAO → tbimportacao.DATA_IMPORTACAO
tbtitulo_pago.TITULO_ID → tbtitulo.TITULO_ID
tbtitulo_pago.CNAB_ID → tbcnab.CNAB_ID

tbacordo.CNAB_ID → tbcnab.CNAB_ID
tbacordo.DATA_IMPORTACAO → tbimportacao.DATA_IMPORTACAO
tbacordo_titulos → (relacionamento implícito, join por ACORDO_ID + TITULO_ID)

tbcobrador.EQUIPE_ID → tbequipe.EQUIPE_ID
tbcobrador_equipe.COBRADOR_ID → tbcobrador.COBRADOR_ID
tbcobrador_equipe.EQUIPE_ID → tbequipe.EQUIPE_ID
tbcobrador_login_contratante.COBRADOR_ID → tbcobrador.COBRADOR_ID
tbcobrador_login_contratante.CONT_ID → tbcontratante.CONTRATANTE_ID
tbcobrador_pausa.TIPO_PAUSA_ID → tbtipo_pausa.ID

tbcontratante.FORMULA_ID → tbformula.FORMULA_ID
tbcontratante.LAYOUT_ID → tblayout.LAYOUT_ID
tbcontratante.PERFIL_ID → tbboleto_perfil.PERFIL_ID
tbcontratante.GRUPO_ID → tbcontratante_grupo.GRUPO_ID
tbcontratante_agenda_importacao.cont_id → tbcontratante.CONTRATANTE_ID
tbcontratante_arquivo.CONT_ID → tbcontratante.CONTRATANTE_ID
tbcontratante_fase.CONT_ID → tbcontratante.CONTRATANTE_ID
tbcontratante_questao_resposta.PERGUNTA_ID → tbcontratante_questao.PERGUNTA_ID

tbimportacao.CONTRATANTE_ID → tbcontratante.CONTRATANTE_ID

tbboleto.COBRADOR_ID → tbcobrador.COBRADOR_ID
tbboleto.DEVEDOR_ID → tbdevedor.DEVEDOR_ID
tbboleto.PERFIL_ID → tbboleto_perfil.PERFIL_ID
tbboleto_titulos.BOLETO_ID → tbboleto.BOLETO_ID
tbcampanha_desconto.CAMPANHA_ID → tbcampanha.CAMPANHA_ID
tbcampanha_oferta.CAMPANHA_ID → tbcampanha.CAMPANHA_ID
tbcnab_arquivo.CNAB_ID → tbcnab.CNAB_ID

tbequipe.COORDENADOR_ID → tbcoordenador.COORDENADOR_ID
tbequipe_contratante.EQUIPE_ID → tbequipe.EQUIPE_ID

tbformula_acordo.FORMULA_ID → tbformula.FORMULA_ID
tbformula_calculo.FORMULA_ID → tbformula.FORMULA_ID
tbformula_desconto.FORMULA_ID → tbformula.FORMULA_ID *(tabela com schema vazio — FK prevista)*
tbformula_receita.FORMULA_ID → tbformula.FORMULA_ID
tbformula_receita_situacao.FORMULA_ID → tbformula.FORMULA_ID

tbregra.CONT_ID → tbcontratante.CONTRATANTE_ID
tbregra_estrategia.REGRA_ID → tbregra.REGRA_ID
tbregra_situacao_cobranca.REGRA_ID → tbregra.REGRA_ID
tbregra_situacao_cobranca.SITUACAO_ID → tbsituacao_cobranca.SITUACAO_ID
tbregra_uf.REGRA_ID → tbregra.REGRA_ID
tbrenitencia.CONT_ID → tbcontratante.CONTRATANTE_ID
tbrenitencia_regra.RENITENCIA_ID → tbrenitencia.RENITENCIA_ID
tbrenitencia_regra.ACAO_ID → tbacao_cobranca.ACAO_ID

tbfila_cobrador.FILA_ID → tbfila.FILA_ID
tboperador.FILIAL_ID → tbfilial.filial_id
tbcontrole_canais.DEVEDOR_ID → tbdevedor.DEVEDOR_ID
tbcontrole_canais.OPERADOR_ID → tboperador.OPERADOR_ID

tbtela_botao.TELA_ID → tbtela.TELA_ID
tbtela_operador.TELA_ID → tbtela.TELA_ID
tbtela_perfil.TELA_ID → tbtela.TELA_ID
```

## Dados de Referência (Lookup Tables)

### tbsituacao_cobranca (7 colunas) — Situações de Cobrança
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|

| SITUACAO_ID | smallint | | PK | ID da situação |
| NOME | varchar | 50 | X | Nome da situação |
| CODIGO_CREDOR | varchar | 20 | | Código credor |
| TIPO_ACIONAMENTO | varchar | 20 | | Tipo acionamento |
| SE_VISIVEL | char | 1 | | Visível |
| SE_RECEPTIVO | char | 1 | | É receptivo |
| DATA_INCLUSAO | smalldatetime | | | Data inclusão |

### tbtipo_titulo (8 colunas) — Tipos de Título
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|
| TIPO_TITULO_ID | smallint | | PK | ID do tipo |
| DESCRICAO | varchar | 30 | X | Descrição do tipo |
| TIPO | char | 1 | X | Classificação (tipo) |
| DATA_INCLUSAO | smalldatetime | | | Data inclusão |
| USUARIO_INCLUSAO | varchar | 15 | | Quem incluiu |
| DATA_ALTERACAO | smalldatetime | | | Data alteração |
| USUARIO_ALTERACAO | varchar | 15 | | Quem alterou |
| ATUAL_DIVIDA | char | 1 | | Atualiza dívida |

### tbtipo_fone — Tipos de Telefone
| ID | Descrição |
|----|-----------|
| A | Avalista |
| C | Celular |
| E | Referência |
| N | Celular Referência |
| O | Outros |
| R | Residencial |
| T | Trabalho |
| U | Celular Vizinho |
| V | Celular Avalista |
| Z | Vizinho |

### tbtipo_endereco — Tipos de Endereço
| ID | Descrição |
|----|-----------|
| 0 | Não definido |
| 1 | Residencial |
| 2 | Comercial |
| 3 | Endereço de Cobrança |
| 4 | Referências |

### tbtipo_baixa — Tipos de Baixa
| ID | Descrição |
|----|-----------|
| 0 | Pagamento |
| 1 | Devolucao por Prazo |
| 2 | Retirada |
| 3 | Retirada Manual |
| 4 | Retirada WS |
| 5 | Acordo |
| 6 | Retirada Outros |
| 7 | Pagamento no Contratante |
| 8 | Retirada por Solicitação do Contratante |
| 9 | Cancelamento |
| A | Cheque Não compensado |
| B | Amortização |
| C | Redistribuido |
| D | Negociado |
| H | Retenção de Honorários |
| J | Jurídico |
| X | Pagamento via PIX |

### tbsituacao_fone — Situações de Telefone
| ID | Descrição |
|----|-----------|
| -1 | Bloqueado |
| 0 | Correto |
| 1 | Incorreto |
| 2 | Não definido |
| 4 | Verificado |

### tbacao_cobranca (68 colunas) — Ações de Cobrança
| Coluna | Tipo | Tam | NN | Descrição |
|--------|------|-----|----|----|

| ACAO_ID | int | | PK | ID da ação |
| DESCRICAO | varchar | 50 | X | Descrição |
| SE_ATIVO | char | 1 | | Ativo S/N |
| QTDE_DIAS_PROX_ACION | smallint | | | Dias próximo acionamento |
| SE_PROPRIEDADE | char | 1 | | Gera propriedade |
| QTDE_DIAS_PROPRIEDADE | smallint | | | Dias propriedade |
| SE_PRODUTIVO | char | 1 | | É produtivo |
| SE_OBSE_OBRIG | char | 1 | | Observação obrigatória |
| SE_CONTATO | char | 1 | | É contato |
| DATA_CADASTRO | smalldatetime | | | Data cadastro |
| INCL_OPER_ID | varchar | 15 | | Quem incluiu |
| DATA_ALTERACAO | smalldatetime | | | Data alteração |
| OCOR_OPER_ID | varchar | 15 | | Quem alterou |
| TIPO_ROLAGEM | char | 1 | | Tipo rolagem |
| SITUACAO_ID | smallint | | FK | Situação destino |
| CONT_ID | smallint | | FK | Contratante |
| LIMITE_ACIONAMENTO | smallint | | | Limite acionamentos |
| SE_ROLAGEM_PREVISAO | char | 1 | | Rolagem previsão |
| SE_ACIONAMENTO_MESMO_DIA | char | 1 | | Mesmo dia |
| SE_PERM_DATA_RETRO | char | 1 | | Permite data retroativa |
| TIPO_ACIONAMENTO | char | 1 | | Tipo acionamento |
| CODIGO_CREDOR | varchar | 20 | | Código credor |
| SE_VISIVEL | char | 1 | | Visível |
| ENVIA_DISCADOR | char | 1 | | Envia discador |
| SE_REMUNERA | char | 1 | | Remunera |
| RESULTADO_CREDOR | char | 5 | | Resultado credor |
| SE_HABILITA_CALENDARIO | char | 1 | | Habilita calendário |
| SE_PINTA_CELULA | char | 1 | | Pinta célula |
| SE_ACAO_AUTO | char | 1 | | Ação automática |
| SE_UTIL_SCRIPT | char | 1 | | Utiliza script |
| SCRIPT | text | MAX | | Script da ação |
| PERCENTUAL_LOCALIZACAO | int | | | % localização |
| SE_FINALIZA_TABULACAO | char | 1 | | Finaliza tabulação |
| MOTIVO_NAO_ACORDO | char | 2 | | Motivo não acordo |
| STATUS_CHAMADA | char | 2 | | Status da chamada |
| DESCRICAO_CREDOR | varchar | 50 | | Descrição credor |
| SE_MULTITABULACAO | char | 1 | | Multitabulação |
| SE_OBRIG_SITUACAO_AUXILIAR | char | 1 | | Obriga situação auxiliar |
| PESO | smallint | | | Peso |
| PROPRIEDADE_ID | int | | FK | ID propriedade |
| SE_GERA_NUME_PROT | char | 1 | | Gera número protocolo |
| ID_INTEGRACAO_DISCADOR | smallint | | | ID integração discador |
| CODIGO_DISCADOR | varchar | 10 | | Código discador |
| CLASSIFICACAO | varchar | 12 | | Classificação |
| CLASSIFICACAO_FUNIL_ATENDIMENTO | varchar | 12 | | Classificação funil |
| SE_DISCADOR | char | 1 | | É discador |
| SE_MASSIVA | char | 1 | | É massiva |
| SE_ATENDIDA | char | 1 | | É atendida |
| SE_CPC | char | 1 | | É CPC |
| SE_CPCA | char | 1 | | É CPCA |
| SE_PROMESSA | char | 1 | | É promessa |
| CLASSIFICACAO_ACORDO_ONLINE | smallint | | | Class acordo online |
| LIMITE_CARACTER | smallint | | | Limite caracteres |
| SE_VISIVEL_OPERACAO | char | 1 | | Visível operação |
| SE_BOLETO | char | 1 | | Gera boleto |
| SE_CPCN | char | 1 | | É CPCN |
| SE_RECADO | char | 1 | | É recado |
| SE_OBRIG_FONE_ACIONAMENTO | char | 1 | | Obriga fone |
| SE_OBRIG_DATA_AGENDA | char | 1 | | Obriga data agenda |
| SE_ENVIO_SOMENTE_LOTE | char | 1 | | Somente lote |
| SE_NEGATIVA_FONE | char | 1 | | Negativa fone |
| QTDE_LIMITE_NEGATIVACAO | smallint | | | Limite negativação |
| SE_TRANSFERE_LIGACAO | char | 1 | | Transfere ligação |
| SE_OBSE_BLOQ | char | 1 | | Observação bloqueada |
| SE_VINCULA_CONTRATO | char | 1 | | Vincula contrato |
| SE_VINCULA_TITULOS_MARCADOS | char | 1 | | Vincula títulos marcados |
| CODIGO_WHATSAPP | varchar | 200 | | Código WhatsApp |
| DATA_IMPORTACAO | datetime | | | Data importação |

### tbequipe — Equipes de Cobrança (Amostra)
| ID | Nome |
|----|------|
| 1 | EQUIPE COBRANCA |
| 2 | EQUIPE JULIENNE |
| 3 | EQUIPE ANA KECIA |
| 4 | EQUIPE DOUGLAS |
| 5 | EQUIPE WELITON |
| 6 | EQUIPE TIAGO |
| 7 | EQUIPE ALUIZIO |
| 8 | EQUIPE KATIANA |
| 9 | EQUIPE KELVIA |
| 11 | GRUPO VIP LEILÕES |

## Stored Procedures — 178 Procedures (Inventário Completo)

> Validado em 2026-03-26. Para atualizar: `SELECT name FROM sys.procedures ORDER BY name`

### Inventário Completo (todas as 178 SPs)
```
sp_eficiencia                        sp_relatorio_acordos                 sp_relatorio_pagamentos
sp_WhoIsActive                       spAcaoCorrenteTitulo                 spAcertaDataLimiteEsposende
spAcertaFone                         spACIONAMENTO_ID                     spACORDO
spAcordoExis                         spAcordoQuebra                       spAcordoQuebraWS
spAGENDA_ID                          spAjustaNumeroRemessa                spAjustaRedesplan
spAjustaValoresRecebidos             spAlteraDevedor                      spAlteraSenhaWeb
spAtualiza_Formulas_DSL              spATUALIZA_TITULO                    spAtualizaBensRecovery
spAtualizaDataMin                    spAtualizaNumeroRemessa              spAtualizaPagamento
spAtualizaPagamentoDashbord          spAtualizaPosicaoFila                spAtualizaTitulosRecovery
spAtualizaValorAcordoEsposende       spAtualizaValores                    spBaseEsposende
spBatimentoAuxiliar                  spBatimentoCoelba                    spBoletoExis
spBulkInsert                         spBuscaDevedor                       spCadastraOperador
spCalculaCreditoJurosPandemia        spCalculaDataMinDevedor              spCalculaDegrais
spCalculaDegrais_BACKUP              spCalculaDegrau                      spCalculaDesconto
spCalculaHonorario                   spCalculaJuroPrice                   spCalculaJuros
spCalculaJurosTaxaCredor             spCalculaMulta                       spCalculaPremio
spCalculaReceita                     spCampanhaLISPBX                     spCarregaImportacao
spCNAB                               spCNAB_Importacao                    spCNAB_Processa
spCNAB_ProcessaManual                spCobrador_Monitoria                 spCobradorBaixa
spCOBRANCA_PRIORITARIA               spComputadorOperador                 spCorrigeReceita
spCriaTitulosAcordo                  spDashboardCoelce                    spDATA_MINIMA
spDATA_MINIMA_CNAB                   spDATA_MINIMA_DEVEDOR                spDATA_MINIMA_FAIXA
spDATA_MINIMA_TITULO                 spDATA_MINIMA_TITULO_ACORDO          spDATA_MINIMA_TITULO_BKP_26122019
spDEVEDOR_DADOS                      spDEVEDOR_FILA_FIM                   spDEVEDOR_ID
spDEVEDOR_PROPRIEDADE                spDevedorAvalistaCarteiraExis        spDevedorAvalistaExis
spDevedorExis                        spDevedorExisAcordo                  spDevedorExisIdent
spDevedorExisIdentAux                spDevedorExisIdentCPF                spDevedorExisNome
spDevedorExisNomeCPF                 spDevedorExisVendaJuridico           spDevedorRestante
spEficienciaVencimento               spEmailExis                          spEnderecoExis
spEventos                            spEXCLUI_ACORDO                      spEXCLUI_ACORDO_PROPORCIONAL
spEXCLUI_DEV_DIST_TEMPO_EXCEDIDO     spEXCLUI_FILA_PROX                  spEXCLUI_TITULO_PROPRIEDADE
spExcluiAgendaTitulo                 spExcluiBatimento                    spExcluiCNAB
spExcluiDuplicidade                  spExcluiDuplicidadeFila              spExcluiDuplicidadeRecorery
spExcluiFila                         spExcluiFormula                      spExcluiImportacao
spExcluiRecibo                       spExcluirFonesInconsistentes         spFaixaAtraso
spFaixaAtrasoUF                      spFILA_COPIA                         spFILA_ID
spFILA_LIBERA_DEVEDOR                spFILA_PROXIMO                       spFILA_QUANTIDADE
spFilaDesmarcaAcoes                  spFilaSimula                         spFinalizaFila
spFinalizaImportacaoTitulo           spFoneExis                           spFonePrioritario
spFoneValida                         spGeraBoleto                         spGeraBoletoRange
spIdentityDevedor                    spIdentityDevedorAvalista            spIdentityTitulo
spImportaAcordo                      spImportaAcordoRecovery              spImportaAguasdoBrasil
spImportaAux                         spImportaAvalista                    spImportaBoleto
spImportaCampanha                    spImportacaoInconsistencia           spImportaDevedor
spImportaEmail                       spImportaEndereco                    spImportaEnelPC3
spImportaFone                        spImportaPagamento                   spImportaParcelaAcordo
spImportaRemessa                     spImportaTitulo                      spImportaTituloAcordo
spImportaTituloContrato              spImportaTituloGarantia              spInibirProdutoAlgar
spLayoutTelefonesFlexivel            spLibera                             spLiberaDevedorPresoFila
spLimpaImportacao                    spLocalizaDevedorContrato            spLOG
spLOG_web                            spManutencaoIndices                  spMaquinaLogada
spMonitoramentoReport                spOperadorUsoLicenca                 spOperadorUsoLicenca_web
spOperadorUsoLicenca_whatsapp        spPosicaoCarteira                    spRetiraContratoEsposende
spRetiraDuplicidade                  spRetiraTitulosBatimento             spRetiraTitulosBatimentoCoelce
spRetiraTituloVencido                spRetiraTituloVencidoGeral           spRetiraTituloVencidoRecupera
spSMS_ID                             spTestaDataMin                       spTipoAcaoCobranca
spTITULO_ID                          spTITULO_PROPRIEDADE                 spTituloContratoExis
spTituloExis                         spTituloExisAcordo                   spTituloExisAcordoEsposende
spTituloGarantiaExis                 spTituloParcela                      spUpdateUsuarioTbMaquinaLogada
spVALIDA_OPERADOR_BOTAO
```

### Catálogo Funcional (SPs Agrupadas por Área)

> Subconjunto curado das 178 SPs agrupadas por função de negócio. O inventário completo está acima.

### Acionamento/Cobrança
| Procedure | Descrição |
|-----------|-----------|
| `spACIONAMENTO_ID` | Gera próximo ID de acionamento |
| `spAcaoCorrenteTitulo` | Ação corrente do título |
| `spCOBRANCA_PRIORITARIA` | Marca cobrança prioritária |
| `spCobradorBaixa` | Baixa de cobrador |
| `spTipoAcaoCobranca` | Tipo de ação de cobrança |

### Acordo (Negociação de Dívidas)
| Procedure | Descrição |
|-----------|-----------|
| `spACORDO` | Cria acordo de negociação |
| `spAcordoExis` | Verifica existência de acordo |
| `spAcordoQuebra` | Quebra de acordo |
| `spAcordoQuebraWS` | Quebra de acordo via WS |
| `spCriaTitulosAcordo` | Cria títulos do acordo |
| `spEXCLUI_ACORDO` | Exclui acordo |
| `spEXCLUI_ACORDO_PROPORCIONAL` | Exclui acordo proporcional |

### Cálculos Financeiros
| Procedure | Descrição |
|-----------|-----------|
| `spCalculaJuros` | Calcula juros |
| `spCalculaJuroPrice` | Calcula juros PRICE |
| `spCalculaJurosTaxaCredor` | Juros com taxa do credor |
| `spCalculaMulta` | Calcula multa |
| `spCalculaHonorario` | Calcula honorários |
| `spCalculaDesconto` | Calcula descontos |
| `spCalculaPremio` | Calcula prêmio |
| `spCalculaReceita` | Calcula receita |
| `spCalculaDegrais` | Calcula degraus de desconto |
| `spCalculaDegrau` | Calcula degrau individual |
| `spCalculaCreditoJurosPandemia` | Crédito juros pandemia |
| `spCalculaDataMinDevedor` | Calcula data mínima |
| `spAtualizaValores` | Atualiza valores dos títulos |
| `spATUALIZA_TITULO` | Atualiza título |
| `spAtualiza_Formulas_DSL` | Atualiza fórmulas DSL |
| `spCorrigeReceita` | Corrige receita |

### Devedor (Busca e Manipulação)
| Procedure | Descrição |
|-----------|-----------|
| `spBuscaDevedor` | Busca devedor (principal) |
| `spDEVEDOR_DADOS` | Dados completos do devedor |
| `spDEVEDOR_ID` | Gera próximo ID de devedor |
| `spDevedorExis` | Verifica existência |
| `spDevedorExisIdent` | Verifica por identificador |
| `spDevedorExisIdentCPF` | Verifica por CPF |
| `spDevedorExisNome` | Verifica por nome |
| `spDevedorExisNomeCPF` | Verifica por nome + CPF |
| `spDevedorRestante` | Devedores restantes |
| `spDevedorExisAcordo` | Verifica devedor com acordo |
| `spDevedorExisIdentAux` | Verifica por identificador auxiliar |
| `spDevedorExisVendaJuridico` | Verifica venda jurídico |
| `spDevedorAvalistaExis` | Verifica avalista |
| `spDevedorAvalistaCarteiraExis` | Verifica avalista em carteira |
| `spDEVEDOR_FILA_FIM` | Finaliza devedor na fila |
| `spDEVEDOR_PROPRIEDADE` | Propriedade do devedor |
| `spAlteraDevedor` | Altera dados do devedor |
| `spLocalizaDevedorContrato` | Localiza por contrato |
| `spIdentityDevedor` | Gera identity devedor |
| `spIdentityDevedorAvalista` | Gera identity avalista |

### Fila de Trabalho
| Procedure | Descrição |
|-----------|-----------|
| `spFILA_ID` | Gera próximo ID de fila |
| `spFILA_PROXIMO` | Próximo devedor da fila |
| `spFILA_QUANTIDADE` | Quantidade na fila |
| `spFILA_COPIA` | Copia fila |
| `spFILA_LIBERA_DEVEDOR` | Libera devedor da fila |
| `spFilaDesmarcaAcoes` | Desmarca ações na fila |
| `spFilaSimula` | Simula fila |
| `spFinalizaFila` | Finaliza fila |
| `spExcluiFila` | Exclui fila |
| `spEXCLUI_FILA_PROX` | Exclui próximo da fila |
| `spAtualizaPosicaoFila` | Atualiza posição na fila |

### Importação/Exportação
| Procedure | Descrição |
|-----------|-----------|
| `spCarregaImportacao` | Carrega importação |
| `spBulkInsert` | Inserção em massa |
| `spImportaDevedor` | Importa devedor |
| `spImportaTitulo` | Importa título |
| `spImportaFone` | Importa telefone |
| `spImportaEmail` | Importa email |
| `spImportaEndereco` | Importa endereço |
| `spImportaPagamento` | Importa pagamento |
| `spImportaRemessa` | Importa remessa |
| `spFinalizaImportacaoTitulo` | Finaliza importação |
| `spLimpaImportacao` | Limpa importação |
| `spExcluiImportacao` | Exclui importação |
| `spImportaAcordo` | Importa acordo |
| `spImportaAcordoRecovery` | Importa acordo recovery |
| `spImportaAux` | Importa auxiliar |
| `spImportaAvalista` | Importa avalista |
| `spImportaBoleto` | Importa boleto |
| `spImportaCampanha` | Importa campanha |
| `spImportacaoInconsistencia` | Inconsistência de importação |
| `spImportaParcelaAcordo` | Importa parcela de acordo |
| `spImportaTituloAcordo` | Importa título de acordo |
| `spImportaTituloContrato` | Importa título contrato |
| `spImportaTituloGarantia` | Importa título garantia |

### Boleto/CNAB
| Procedure | Descrição |
|-----------|-----------|
| `spGeraBoleto` | Gera boleto individual |
| `spGeraBoletoRange` | Gera boletos em lote |
| `spBoletoExis` | Verifica existência de boleto |
| `spCNAB` | Processa arquivo CNAB |
| `spCNAB_Importacao` | Importa CNAB |
| `spCNAB_Processa` | Processa CNAB |
| `spCNAB_ProcessaManual` | Processamento manual CNAB |

### Relatórios
| Procedure | Descrição |
|-----------|-----------|
| `sp_eficiencia` | Relatório de eficiência |
| `sp_relatorio_acordos` | Relatório de acordos |
| `sp_relatorio_pagamentos` | Relatório de pagamentos |
| `spFaixaAtraso` | Faixa de atraso |
| `spFaixaAtrasoUF` | Faixa de atraso por UF |
| `spMonitoramentoReport` | Monitoramento |
| `spEficienciaVencimento` | Eficiência por vencimento |
| `spDashboardCoelce` | Dashboard Coelce |

### Operador/Login
| Procedure | Descrição |
|-----------|-----------|
| `spCadastraOperador` | Cadastra operador |
| `spVALIDA_OPERADOR_BOTAO` | Valida botão por operador |
| `spMaquinaLogada` | Registra máquina logada |
| `spOperadorUsoLicenca` | Uso de licença |
| `spOperadorUsoLicenca_web` | Uso de licença web |
| `spComputadorOperador` | Computador do operador |
| `spAlteraSenhaWeb` | Altera senha web |
| `spCobrador_Monitoria` | Monitoria de cobrador |
| `spOperadorUsoLicenca_whatsapp` | Uso de licença WhatsApp |
| `spMaquinaLogada` | Registra máquina logada |
| `spUpdateUsuarioTbMaquinaLogada` | Atualiza usuário máquina logada |

### Agenda
| Procedure | Descrição |
|-----------|-----------|
| `spAGENDA_ID` | Gera próximo ID de agenda |

### Título (Busca e Manipulação)
| Procedure | Descrição |
|-----------|-----------|
| `spTITULO_ID` | Gera próximo ID de título |
| `spTITULO_PROPRIEDADE` | Propriedade do título |
| `spTituloExis` | Verifica existência de título |
| `spTituloExisAcordo` | Verifica título com acordo |
| `spTituloExisAcordoEsposende` | Verifica título acordo Esposende |
| `spTituloContratoExis` | Verifica contrato do título |
| `spTituloGarantiaExis` | Verifica garantia do título |
| `spTituloParcela` | Parcela do título |
| `spIdentityTitulo` | Gera identity título |
| `spExcluiAgendaTitulo` | Exclui agenda do título |
| `spEXCLUI_TITULO_PROPRIEDADE` | Exclui propriedade do título |
| `spRetiraTituloVencido` | Retira título vencido |
| `spRetiraTituloVencidoGeral` | Retira título vencido geral |
| `spRetiraTituloVencidoRecupera` | Retira título vencido recupera |

### Data Mínima (Cálculo de Datas)
| Procedure | Descrição |
|-----------|-----------|
| `spDATA_MINIMA` | Calcula data mínima |
| `spDATA_MINIMA_CNAB` | Data mínima CNAB |
| `spDATA_MINIMA_DEVEDOR` | Data mínima devedor |
| `spDATA_MINIMA_FAIXA` | Data mínima por faixa |
| `spDATA_MINIMA_TITULO` | Data mínima título |
| `spDATA_MINIMA_TITULO_ACORDO` | Data mínima título acordo |
| `spTestaDataMin` | Testa data mínima |
| `spAtualizaDataMin` | Atualiza data mínima |

### Telefone/Email/Endereço (Validação)
| Procedure | Descrição |
|-----------|-----------|
| `spFoneExis` | Verifica existência de telefone |
| `spFonePrioritario` | Telefone prioritário |
| `spFoneValida` | Valida telefone |
| `spAcertaFone` | Acerta telefone |
| `spEmailExis` | Verifica existência de email |
| `spEnderecoExis` | Verifica existência de endereço |
| `spSMS_ID` | Gera ID de SMS |
| `spLayoutTelefonesFlexivel` | Layout flexível de telefones |

### Batimento/Pagamento
| Procedure | Descrição |
|-----------|-----------|
| `spAtualizaPagamento` | Atualiza pagamento |
| `spAtualizaPagamentoDashbord` | Atualiza pagamento dashboard |
| `spBatimentoAuxiliar` | Batimento auxiliar |
| `spBatimentoCoelba` | Batimento Coelba |
| `spExcluiBatimento` | Exclui batimento |
| `spRetiraTitulosBatimento` | Retira títulos do batimento |
| `spRetiraTitulosBatimentoCoelce` | Retira títulos batimento Coelce |
| `spAjustaValoresRecebidos` | Ajusta valores recebidos |

### Manutenção/Utilitários
| Procedure | Descrição |
|-----------|-----------|
| `spLOG` | Registra log |
| `spLOG_web` | Registra log web |
| `spEventos` | Eventos do sistema |
| `spManutencaoIndices` | Manutenção de índices |
| `spRetiraDuplicidade` | Remove duplicidades |
| `spExcluiDuplicidade` | Exclui duplicidades |
| `spExcluiDuplicidadeFila` | Exclui duplicidade em fila |
| `spExcluiDuplicidadeRecorery` | Exclui duplicidade recovery |
| `spExcluirFonesInconsistentes` | Exclui fones inconsistentes |
| `spExcluiFormula` | Exclui fórmula |
| `spExcluiRecibo` | Exclui recibo |
| `spExcluiCNAB` | Exclui CNAB |
| `spLibera` | Liberação genérica |
| `spLiberaDevedorPresoFila` | Libera devedor preso na fila |
| `spEXCLUI_DEV_DIST_TEMPO_EXCEDIDO` | Exclui devedor distribuído com tempo excedido |
| `spEXCLUI_FILA_PROX` | Exclui próximo da fila |
| `spUpdateUsuarioTbMaquinaLogada` | Atualiza usuário máquina logada |
| `sp_WhoIsActive` | Processos ativos no SQL Server |

### Diversos/Auxiliares
| Procedure | Descrição |
|-----------|-----------|
| `spAjustaNumeroRemessa` | Ajusta número de remessa |
| `spAtualizaNumeroRemessa` | Atualiza número de remessa |
| `spAjustaRedesplan` | Ajusta dados Redesplan |
| `spAtualizaBensRecovery` | Atualiza bens recovery |
| `spAtualizaTitulosRecovery` | Atualiza títulos recovery |
| `spPosicaoCarteira` | Posição de carteira |
| `spCalculaDegrais_BACKUP` | Backup de cálculo degraus (legado) |
| `spDATA_MINIMA_TITULO_BKP_26122019` | Backup data mínima título 26/12/2019 (legado) |

### Específicas de Clientes
| Procedure | Descrição |
|-----------|-----------|
| `spAcertaDataLimiteEsposende` | Acerta data limite Esposende |
| `spAtualizaValorAcordoEsposende` | Atualiza valor acordo Esposende |
| `spBaseEsposende` | Base Esposende |
| `spRetiraContratoEsposende` | Retira contrato Esposende |
| `spImportaEnelPC3` | Importa Enel PC3 |
| `spImportaAguasdoBrasil` | Importa Águas do Brasil |
| `spInibirProdutoAlgar` | Inibir produto Algar |
| `spCampanhaLISPBX` | Campanha LISPBX |
| `spDashboardCoelce` | Dashboard Coelce |

## Views

### viFaixaAtrasoUF
Visão que cruza títulos com faixa de atraso e UF do devedor.

### viRecebimentos
Visão que consolida recebimentos/pagamentos.

## Queries SQL Prontas para o Assistente de IA

> **Nota:** Os placeholders `@devedor_id`, `@data_inicio`, `@data_fim` devem ser substituídos por valores reais antes da execução via `isql`. Use a função `sanitizeInput()` para limpar valores recebidos do usuário. Exemplo: `WHERE d.CPF LIKE '%' + sanitizeInput(cpf) + '%'`

### 1. Buscar devedor por CPF
```sql
SELECT TOP 10 d.DEVEDOR_ID, d.NOME,
       LEFT(d.CPF, 3) + '.***.***-' + RIGHT(d.CPF, 2) AS CPF_MASCARADO,
       d.CIDADE, d.UF,
       d.VALOR_DIVIDA_ATIVA, d.QTDE_TITULOS, d.SITUACAO, d.TIPO_PESSOA,
       c.FANTASIA AS CONTRATANTE
FROM tbdevedor d
LEFT JOIN tbcontratante c ON d.CONT_ID = c.CONTRATANTE_ID
WHERE d.CPF LIKE '%{CPF_PARCIAL}%'
```

### 2. Buscar devedor por nome
```sql
SELECT TOP 20 d.DEVEDOR_ID, d.NOME,
       LEFT(d.CPF, 3) + '.***.***-' + RIGHT(d.CPF, 2) AS CPF_MASCARADO,
       d.CIDADE, d.UF,
       d.VALOR_DIVIDA_ATIVA, d.QTDE_TITULOS, c.FANTASIA AS CONTRATANTE
FROM tbdevedor d
LEFT JOIN tbcontratante c ON d.CONT_ID = c.CONTRATANTE_ID
WHERE d.NOME LIKE '%{NOME}%'
ORDER BY d.NOME
```

### 3. Listar títulos de um devedor
```sql
SELECT TOP 100 t.TITULO_ID, t.NUMERO_CONTRATO, t.NUMERO_DOCUMENTO,
       t.VALOR_ORIGINAL, t.VALOR_ATUAL, t.VALOR_JURO, t.VALOR_MULTA, t.VALOR_HONO,
       t.DATA_VENCIMENTO, t.FASE,
       DATEDIFF(DAY, t.DATA_VENCIMENTO, GETDATE()) AS DIAS_ATRASO,
       tt.DESCRICAO AS TIPO_TITULO,
       ac.DESCRICAO AS ULTIMA_ACAO
FROM tbtitulo t
LEFT JOIN tbtipo_titulo tt ON t.TIPO_TITULO_ID = tt.TIPO_TITULO_ID
LEFT JOIN tbacao_cobranca ac ON t.ACAO_ID = ac.ACAO_ID
WHERE t.DEVEDOR_ID = @devedor_id
  AND t.ACORDO_ID IS NULL
ORDER BY t.DATA_VENCIMENTO
```

### 4. Consultar acordos de um devedor
```sql
SELECT TOP 100 a.ACORDO_ID, a.DATA, a.VALOR_ACORDO, a.VALOR_ENTRADA,
       a.QTDE_PRESTACAO_ACORDO, a.VALOR_NOVA_PARCELA,
       a.VALOR_DESCONTO, a.FORMA_PAGAMENTO,
       CASE WHEN a.CANCEL = 1 THEN 'CANCELADO'
            WHEN a.PAGO = 1 THEN 'PAGO'
            WHEN a.DATA_QUEBRA IS NOT NULL THEN 'QUEBRADO'
            ELSE 'ATIVO' END AS STATUS,
       c.FANTASIA AS CONTRATANTE
FROM tbacordo a
LEFT JOIN tbcontratante c ON a.CONT_ID = c.CONTRATANTE_ID
WHERE a.DEVEDOR_ID = @devedor_id
ORDER BY a.DATA DESC
```

### 5. Histórico de acionamentos de um devedor
```sql
SELECT TOP 50 da.DATA, da.MENSAGEM, da.FONE, da.RAMAL,
       ac.DESCRICAO AS ACAO,
       cb.NOME AS COBRADOR,
       CASE WHEN da.SE_SMS = 1 THEN 'SMS'
            WHEN da.SE_EMAIL = 1 THEN 'EMAIL'
            WHEN da.DISCADOR = 'S' THEN 'DISCADOR'
            ELSE 'MANUAL' END AS CANAL
FROM tbdevedor_acionamento da
LEFT JOIN tbacao_cobranca ac ON da.ACAO_ID = ac.ACAO_ID
LEFT JOIN tbcobrador cb ON da.COBRADOR_ID = cb.COBRADOR_ID
WHERE da.DEVEDOR_ID = @devedor_id
ORDER BY da.DATA DESC
```

### 6. Resumo de carteira por contratante
```sql
SELECT TOP 50 c.CONTRATANTE_ID, c.FANTASIA,
       COUNT(DISTINCT d.DEVEDOR_ID) AS TOTAL_DEVEDORES,
       COUNT(t.TITULO_ID) AS TOTAL_TITULOS,
       SUM(t.VALOR_ORIGINAL) AS VALOR_TOTAL_ORIGINAL,
       SUM(t.VALOR_ATUAL) AS VALOR_TOTAL_ATUAL,
       AVG(DATEDIFF(DAY, t.DATA_VENCIMENTO, GETDATE())) AS MEDIA_ATRASO_DIAS
FROM tbcontratante c
LEFT JOIN tbdevedor d ON c.CONTRATANTE_ID = d.CONT_ID
LEFT JOIN tbtitulo t ON d.DEVEDOR_ID = t.DEVEDOR_ID AND t.ACORDO_ID IS NULL
WHERE c.SE_ATIV = 'S'
GROUP BY c.CONTRATANTE_ID, c.FANTASIA
ORDER BY VALOR_TOTAL_ATUAL DESC
```

### 7. Títulos em atraso por faixa
```sql
SELECT
  CASE
    WHEN DATEDIFF(DAY, t.DATA_VENCIMENTO, GETDATE()) BETWEEN 1 AND 30 THEN '01-30 dias'
    WHEN DATEDIFF(DAY, t.DATA_VENCIMENTO, GETDATE()) BETWEEN 31 AND 60 THEN '31-60 dias'
    WHEN DATEDIFF(DAY, t.DATA_VENCIMENTO, GETDATE()) BETWEEN 61 AND 90 THEN '61-90 dias'
    WHEN DATEDIFF(DAY, t.DATA_VENCIMENTO, GETDATE()) BETWEEN 91 AND 120 THEN '91-120 dias'
    WHEN DATEDIFF(DAY, t.DATA_VENCIMENTO, GETDATE()) > 120 THEN '120+ dias'
    ELSE 'Em dia'
  END AS FAIXA_ATRASO,
  COUNT(*) AS QTDE_TITULOS,
  SUM(t.VALOR_ATUAL) AS VALOR_TOTAL,
  COUNT(DISTINCT t.DEVEDOR_ID) AS QTDE_DEVEDORES
FROM tbtitulo t
WHERE t.ACORDO_ID IS NULL AND t.DATA_VENCIMENTO < GETDATE()
GROUP BY
  CASE
    WHEN DATEDIFF(DAY, t.DATA_VENCIMENTO, GETDATE()) BETWEEN 1 AND 30 THEN '01-30 dias'
    WHEN DATEDIFF(DAY, t.DATA_VENCIMENTO, GETDATE()) BETWEEN 31 AND 60 THEN '31-60 dias'
    WHEN DATEDIFF(DAY, t.DATA_VENCIMENTO, GETDATE()) BETWEEN 61 AND 90 THEN '61-90 dias'
    WHEN DATEDIFF(DAY, t.DATA_VENCIMENTO, GETDATE()) BETWEEN 91 AND 120 THEN '91-120 dias'
    WHEN DATEDIFF(DAY, t.DATA_VENCIMENTO, GETDATE()) > 120 THEN '120+ dias'
    ELSE 'Em dia'
  END
ORDER BY 1
```

### 8. Performance de cobrador
```sql
SELECT TOP 50 cb.COBRADOR_ID, cb.NOME, e.NOME AS EQUIPE,
       COUNT(DISTINCT CASE WHEN ac.DESCRICAO LIKE '%ACORDO%' THEN da.ACIONAMENTO_ID END) AS ACORDOS_FECHADOS,
       COUNT(da.ACIONAMENTO_ID) AS TOTAL_ACIONAMENTOS,
       COUNT(DISTINCT da.DEVEDOR_ID) AS DEVEDORES_TRABALHADOS
FROM tbcobrador cb
LEFT JOIN tbequipe e ON cb.EQUIPE_ID = e.EQUIPE_ID
LEFT JOIN tbdevedor_acionamento da ON cb.COBRADOR_ID = da.COBRADOR_ID
  AND da.DATA >= DATEADD(MONTH, -1, GETDATE())
LEFT JOIN tbacao_cobranca ac ON da.ACAO_ID = ac.ACAO_ID
WHERE cb.SE_ATIVO = 'S'
GROUP BY cb.COBRADOR_ID, cb.NOME, e.NOME
ORDER BY ACORDOS_FECHADOS DESC
```

### 9. Pagamentos recebidos por período
```sql
SELECT CONVERT(VARCHAR(10), tp.DATA_PAGTO, 103) AS DATA,
       COUNT(*) AS QTDE_PAGAMENTOS,
       SUM(tp.VALOR_RECEBIDO) AS VALOR_TOTAL,
       c.FANTASIA AS CONTRATANTE
FROM tbtitulo_pago tp
LEFT JOIN tbtitulo t ON tp.TITULO_ID = t.TITULO_ID
LEFT JOIN tbcontratante c ON t.CONT_ID = c.CONTRATANTE_ID
WHERE tp.DATA_PAGTO BETWEEN @data_inicio AND @data_fim
GROUP BY CONVERT(VARCHAR(10), tp.DATA_PAGTO, 103), c.FANTASIA
ORDER BY 1 DESC
```

### 10. Dashboard KPIs
```sql
SELECT
  (SELECT SUM(VALOR_ATUAL) FROM tbtitulo WHERE ACORDO_ID IS NULL) AS VALOR_EM_CARTEIRA,
  (SELECT SUM(VALOR_RECEBIDO) FROM tbtitulo_pago WHERE YEAR(DATA_PAGTO) = YEAR(GETDATE())) AS VALOR_RECUPERADO_ANO,
  (SELECT COUNT(DISTINCT DEVEDOR_ID) FROM tbtitulo WHERE ACORDO_ID IS NULL) AS DEVEDORES_ATIVOS,
  (SELECT COUNT(*) FROM tbacordo WHERE YEAR(DATA) = YEAR(GETDATE()) AND CANCEL = 0) AS ACORDOS_ANO,
  (SELECT COUNT(*) FROM tbacordo WHERE YEAR(DATA) = YEAR(GETDATE()) AND CANCEL = 0 AND PAGO = 1) AS ACORDOS_PAGOS_ANO,
  (SELECT COUNT(DISTINCT DEVEDOR_ID) FROM tbdevedor_acionamento WHERE CAST(DATA AS DATE) = CAST(GETDATE() AS DATE)) AS DEVEDORES_ACIONADOS_HOJE
```

### 11. Telefones de um devedor com status
```sql
SELECT f.FONE, f.TIPO,
       CASE f.TIPO WHEN 'R' THEN 'Residencial' WHEN 'C' THEN 'Celular' WHEN 'T' THEN 'Trabalho' WHEN 'O' THEN 'Outros' ELSE f.TIPO END AS TIPO_DESC,
       CASE f.STATUS WHEN '0' THEN 'Correto' WHEN '1' THEN 'Incorreto' WHEN '-1' THEN 'Bloqueado' ELSE 'Não definido' END AS STATUS_DESC,
       f.SE_WHATSAPP, f.SE_CPC, f.PRIORITARIO, f.SCORE, f.OBSE
FROM tbdevedor_fone f
WHERE f.DEVEDOR_ID = @devedor_id
ORDER BY f.PRIORITARIO DESC, f.SCORE DESC
```

### 12. Ficha completa do devedor (para Screen Pop)
```sql
SELECT TOP 100 d.DEVEDOR_ID, d.NOME,
       LEFT(d.CPF, 3) + '.***.***-' + RIGHT(d.CPF, 2) AS CPF_MASCARADO,
       d.TIPO_PESSOA,
       d.ENDERECO + ', ' + d.NUMERO + ISNULL(' ' + d.COMPLEMENTO, '') AS ENDERECO_COMPLETO,
       d.BAIRRO, d.CIDADE, d.UF, d.CEP,
       d.EMPRESA, d.CARGO, d.VALOR_RENDA,
       d.VALOR_DIVIDA_ATIVA, d.QTDE_TITULOS,
       d.PONT_SCORE, d.PONT_BEHAVIOR,
       d.SITUACAO, d.OBSE,
       c.FANTASIA AS CONTRATANTE, c.CONTRATANTE_ID,
       (SELECT TOP 1 FONE FROM tbdevedor_fone WHERE DEVEDOR_ID = d.DEVEDOR_ID AND PRIORITARIO = 1) AS FONE_PRIORITARIO,
       (SELECT TOP 1 EMAIL FROM tbdevedor_email WHERE DEVEDOR_ID = d.DEVEDOR_ID AND SE_PRIORITARIO = 1) AS EMAIL_PRIORITARIO
FROM tbdevedor d
LEFT JOIN tbcontratante c ON d.CONT_ID = c.CONTRATANTE_ID
WHERE d.DEVEDOR_ID = @devedor_id
```

## Regras de Segurança para Assistente de IA

1. **Somente leitura** — NUNCA executar INSERT, UPDATE, DELETE, DROP, ALTER, EXEC (stored procedures)
2. **Limitar resultados** — Sempre usar `TOP N` (max 100) para evitar sobrecarga
3. **Mascarar CPF** — Exibir apenas primeiros 3 e últimos 2 dígitos: `LEFT(CPF,3) + '.***.***-' + RIGHT(CPF,2)`
4. **Mascarar telefone** — Exibir apenas DDD e últimos 4 dígitos
5. **Nunca expor senhas** — Colunas SENHA, SENHA_WEB, SMTP_SENHA_AUTENTICA são proibidas em SELECT
6. **Timeout** — Máximo 30 segundos por query
7. **Rate limit** — Máximo 10 queries por minuto por sessão
8. **Tabelas proibidas** — Não acessar: tbparametro (senhas do sistema), tbtela_operador (permissões)
9. **Log obrigatório** — Toda query executada deve ser registrada com timestamp, operador, SQL

## Todas as Tabelas do Banco (236)

```
eficiencia_vencimento, FONES_HIG_11092024, FONES_HIG_INTOUCH, fones_intouch_pf,
HIG_FONES_PF, HIG_FONES_PJ, HIG_INTOUCH, t_dados, T_Discador_Log,
tbacao_cobranca, tbacao_cobranca_schedule, tbacao_cobranca_situacao,
tbACIONAMENTO_ID, tbacordo, tbacordo_comissao, tbacordo_forma_pagamento,
tbacordo_pre, tbacordo_repasse, tbacordo_titulos, tbacordo_titulos_original,
tbacordo_titulos_pre, tbacordo_ws, tbagencia, tbagenda, tbassessoria,
tbassessoria_distribuicao, tbauditoria, tbaux, tbaviso, tbblack_list,
tbboleto, tbboleto_pagto_titulos, tbboleto_perfil, tbboleto_perfil_nosso_numero,
tbboleto_titulos, tbcampanha, tbcampanha_desconto, tbcampanha_oferta,
tbcartao, tbcartao_bandeira, tbcartao_tarifa, tbcnab, tbcnab_arquivo,
tbcnab_titulos, tbcobrador, tbcobrador_equipe, tbcobrador_login_contratante,
tbcobrador_pausa, tbcobrador_ramal, tbcomputador_operador, tbcontratante,
tbcontratante_agenda_importacao, tbcontratante_arquivo, tbcontratante_associado,
tbcontratante_batimento, tbcontratante_campanha, tbcontratante_comissao,
tbcontratante_confissao_divida, tbcontratante_contato, tbcontratante_criterio_acordo,
tbcontratante_exportacao, tbcontratante_exportacao_detalhe,
tbcontratante_exportacao_prestacao_contas, tbcontratante_faixa_atraso,
tbcontratante_fase, tbcontratante_filial, tbcontratante_grupo,
tbcontratante_indicador, tbcontratante_lista_campo, tbcontratante_meta,
tbcontratante_perfil_fila, tbcontratante_previa_eficiencia, tbcontratante_produto,
tbcontratante_questao, tbcontratante_questao_resposta, tbcontrole_anexo,
tbcontrole_canais, tbcontrole_canais_historico, tbcontrole_notificacao,
tbcontrole_notificacao_distribuicao, tbcoordenador, tbdashboard_aux,
tbdevedor, tbdevedor_acionamento, tbdevedor_avalista, tbdevedor_calculo,
tbdevedor_cobrador, tbdevedor_email, tbdevedor_endereco, tbdevedor_fone,
tbdevedor_mensagem, tbdevedor_processo_juridico, tbdevedor_proposta_venda,
tbdevedor_propriedade, tbdevedor_questionario, tbdevedor_tempo_ligacao,
tbdistribuicao, tbdistribuicao_movimento, tbeficiencia, tbeficiencia_lote,
tbeficiencia_remessa, tbeficiencia_vencimento, tbemail, tbemail_texto,
tbemail_texto_campo, tbequipe, tbequipe_campanha_transferencia,
tbequipe_contratante, tbestoque, tbfila, tbfila_cobrador, tbfila_cobrador_exec,
tbfila_simula, tbfilial, tbformula, tbformula_acordo, tbformula_calculo,
tbformula_calculo_ano_competencia, TBFORMULA_CALCULO_DSL_BKP,
tbformula_desconto, tbformula_desconto_excecao, tbformula_receita,
tbformula_receita_acordo, tbformula_receita_pagamento, tbformula_receita_situacao,
tbformula_receita_valor, tbimportacao, tbimportacao_aux, tbimportacao_inconsistencia,
tbimportacao_remessa, tbimportacao_remessa_fisica, tbimportacao_remessa_fone,
tbindice, tblayout, tblayout_acao, TBLISTA_INADIMPLENCIA, tblocalidade_cidade,
tblocalidade_ddd, tblocalidade_uf, tblog, tblog_erro_web, tblog_requisicao,
tbmaquina_logada, tbmaquina_logada_historico, tbmovimentacao_juridica,
tboperador, tboperador_layout, tboperador_perfil, tboperador_web,
tbparametro, tbperfil, tbperfil_meta, tbperfil_sms, tbperfil_sms_log,
tbponto, tbponto_deta, tbproposta, tbproposta_parcelamento, tbrecibo,
tbrecibo_titulo, tbregra, tbregra_estrategia, tbregra_situacao_cobranca,
tbregra_uf, tbrenitencia, tbrenitencia_regra, tbsituacao_cobranca,
tbsituacao_fone, tbsql, tbtela, tbtela_botao, tbtela_exportacao,
tbtela_operador, tbtela_operador_botao, tbtela_operador_exportacao,
tbtela_perfil, tbtela_perfil_botao, tbtela_web, tbtela_web_operador,
tbtela_web_tipo, tbtelefone_campanha_log, tbtipo_avalista, tbtipo_baixa,
tbtipo_baixa_credor, tbtipo_endereco, tbtipo_fone, tbtipo_fone_discador,
tbtipo_importacao, tbtipo_pausa, tbtipo_pausa_discador, tbtipo_titulo,
tbtitulo, tbtitulo_acionamento, tbtitulo_acordo_pre, tbtitulo_anexo,
tbtitulo_aux, tbtitulo_boleto, tbtitulo_calculo, tbtitulo_calculo_solicita_desconto,
tbtitulo_contrato, tbtitulo_contrato_indicador,
tbtitulo_contrato_proposta_parcelamento, tbtitulo_garantia, tbtitulo_garantia_aux,
tbtitulo_liberacao, tbtitulo_pago, tbtitulo_pago_dashboard, tbtitulo_parcela,
tbtitulo_propriedade, tbtitulo_ws, tbvenda, tbvenda_produto,
tbwebhook_eventos, web_Importacao, web_ResumoImportacao
```
