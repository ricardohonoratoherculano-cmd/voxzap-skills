# Consultas SQL Prontas para KPIs de Call Center

Todas as consultas são para PostgreSQL e consideram as tabelas `queue_log` e `cdr` do Asterisk.

## Notas Importantes

1. **Cast obrigatório**: `data1::integer`, `data2::integer`, `data3::integer` — colunas são varchar
2. **Cast seguro** (recomendado para produção): Use `CASE WHEN data1 ~ '^\d+$' THEN data1::integer ELSE NULL END`
3. **Filtro de data**: Sempre incluir para performance
4. **Parâmetros**: Use `$1`, `$2` para datas dinâmicas via aplicação

---

## 1. TME — Tempo Médio de Espera (por Fila)

```sql
SELECT 
  queuename AS fila,
  COUNT(*) AS total_atendidas,
  ROUND(AVG(CASE WHEN data1 ~ '^\d+$' THEN data1::integer ELSE NULL END), 2) AS tme_segundos,
  MIN(CASE WHEN data1 ~ '^\d+$' THEN data1::integer ELSE NULL END) AS menor_espera,
  MAX(CASE WHEN data1 ~ '^\d+$' THEN data1::integer ELSE NULL END) AS maior_espera,
  ROUND(AVG(CASE WHEN data1 ~ '^\d+$' THEN data1::integer ELSE NULL END) / 60.0, 2) AS tme_minutos
FROM queue_log
WHERE event = 'CONNECT'
  AND eventdate >= $1::timestamp
  AND eventdate < $2::timestamp
GROUP BY queuename
ORDER BY tme_segundos DESC;
```

## 2. TMA — Tempo Médio de Atendimento (por Fila)

```sql
SELECT 
  queuename AS fila,
  COUNT(*) AS chamadas_completadas,
  ROUND(AVG(CASE WHEN data2 ~ '^\d+$' THEN data2::integer ELSE NULL END), 2) AS tma_segundos,
  ROUND(AVG(CASE WHEN data2 ~ '^\d+$' THEN data2::integer ELSE NULL END) / 60.0, 2) AS tma_minutos,
  SUM(CASE WHEN data2 ~ '^\d+$' THEN data2::integer ELSE 0 END) AS tempo_total_falado,
  MIN(CASE WHEN data2 ~ '^\d+$' THEN data2::integer ELSE NULL END) AS menor_atendimento,
  MAX(CASE WHEN data2 ~ '^\d+$' THEN data2::integer ELSE NULL END) AS maior_atendimento
FROM queue_log
WHERE event IN ('COMPLETECALLER', 'COMPLETEAGENT')
  AND eventdate >= $1::timestamp
  AND eventdate < $2::timestamp
GROUP BY queuename
ORDER BY tma_segundos DESC;
```

## 3. TMA por Agente

```sql
SELECT 
  agent AS agente,
  queuename AS fila,
  COUNT(*) AS chamadas_atendidas,
  ROUND(AVG(CASE WHEN data2 ~ '^\d+$' THEN data2::integer ELSE NULL END), 2) AS tma_segundos,
  ROUND(AVG(CASE WHEN data2 ~ '^\d+$' THEN data2::integer ELSE NULL END) / 60.0, 2) AS tma_minutos,
  SUM(CASE WHEN data2 ~ '^\d+$' THEN data2::integer ELSE 0 END) AS tempo_total_falado
FROM queue_log
WHERE event IN ('COMPLETECALLER', 'COMPLETEAGENT')
  AND eventdate >= $1::timestamp
  AND eventdate < $2::timestamp
GROUP BY agent, queuename
ORDER BY agente, fila;
```

## 4. SLA — Nível de Serviço (meta em segundos como parâmetro)

```sql
SELECT 
  queuename AS fila,
  COUNT(*) AS total_atendidas,
  SUM(CASE 
    WHEN data1 ~ '^\d+$' AND data1::integer <= $3 THEN 1 
    ELSE 0 
  END) AS dentro_sla,
  ROUND(
    (SUM(CASE WHEN data1 ~ '^\d+$' AND data1::integer <= $3 THEN 1 ELSE 0 END) * 100.0) 
    / NULLIF(COUNT(*), 0), 
    2
  ) AS sla_percentual,
  ROUND(AVG(CASE WHEN data1 ~ '^\d+$' THEN data1::integer ELSE NULL END), 2) AS tme_segundos
FROM queue_log
WHERE event = 'CONNECT'
  AND eventdate >= $1::timestamp
  AND eventdate < $2::timestamp
GROUP BY queuename
ORDER BY sla_percentual DESC;
```
*Nota: `$3` é a meta de SLA em segundos (ex: 20, 30, 60)*

## 5. Taxa de Abandono (por Fila)

```sql
WITH metricas AS (
  SELECT 
    queuename,
    SUM(CASE WHEN event = 'CONNECT' THEN 1 ELSE 0 END) AS atendidas,
    SUM(CASE WHEN event = 'ABANDON' THEN 1 ELSE 0 END) AS abandonadas,
    SUM(CASE WHEN event IN ('EXITWITHTIMEOUT', 'EXITEMPTY') THEN 1 ELSE 0 END) AS timeout_vazia,
    SUM(CASE WHEN event = 'ENTERQUEUE' THEN 1 ELSE 0 END) AS total_entraram
  FROM queue_log
  WHERE event IN ('CONNECT', 'ABANDON', 'ENTERQUEUE', 'EXITWITHTIMEOUT', 'EXITEMPTY')
    AND eventdate >= $1::timestamp
    AND eventdate < $2::timestamp
  GROUP BY queuename
)
SELECT 
  queuename AS fila,
  total_entraram,
  atendidas,
  abandonadas,
  timeout_vazia,
  ROUND((abandonadas * 100.0) / NULLIF(total_entraram, 0), 2) AS taxa_abandono_percentual,
  ROUND((atendidas * 100.0) / NULLIF(total_entraram, 0), 2) AS taxa_atendimento_percentual
FROM metricas
ORDER BY taxa_abandono_percentual DESC;
```

## 6. Análise de Abandonos Detalhada

```sql
SELECT 
  queuename AS fila,
  COUNT(*) AS total_abandonos,
  ROUND(AVG(CASE WHEN data3 ~ '^\d+$' THEN data3::integer ELSE NULL END), 2) AS paciencia_media_segundos,
  MIN(CASE WHEN data3 ~ '^\d+$' THEN data3::integer ELSE NULL END) AS menor_espera_abandono,
  MAX(CASE WHEN data3 ~ '^\d+$' THEN data3::integer ELSE NULL END) AS maior_espera_abandono,
  SUM(CASE WHEN data3 ~ '^\d+$' AND data3::integer <= 10 THEN 1 ELSE 0 END) AS abandono_rapido_10s,
  SUM(CASE WHEN data3 ~ '^\d+$' AND data3::integer BETWEEN 11 AND 30 THEN 1 ELSE 0 END) AS abandono_11_30s,
  SUM(CASE WHEN data3 ~ '^\d+$' AND data3::integer BETWEEN 31 AND 60 THEN 1 ELSE 0 END) AS abandono_31_60s,
  SUM(CASE WHEN data3 ~ '^\d+$' AND data3::integer > 60 THEN 1 ELSE 0 END) AS abandono_acima_60s
FROM queue_log
WHERE event = 'ABANDON'
  AND eventdate >= $1::timestamp
  AND eventdate < $2::timestamp
GROUP BY queuename
ORDER BY total_abandonos DESC;
```

## 7. Dashboard Resumo Geral (Uma Consulta)

```sql
WITH dados AS (
  SELECT 
    queuename,
    event,
    CASE WHEN data1 ~ '^\d+$' THEN data1::integer ELSE NULL END AS d1,
    CASE WHEN data2 ~ '^\d+$' THEN data2::integer ELSE NULL END AS d2,
    CASE WHEN data3 ~ '^\d+$' THEN data3::integer ELSE NULL END AS d3
  FROM queue_log
  WHERE eventdate >= $1::timestamp
    AND eventdate < $2::timestamp
    AND event IN ('ENTERQUEUE', 'CONNECT', 'ABANDON', 'COMPLETECALLER', 'COMPLETEAGENT', 'EXITWITHTIMEOUT', 'EXITEMPTY')
)
SELECT 
  queuename AS fila,
  
  -- Volume
  SUM(CASE WHEN event = 'ENTERQUEUE' THEN 1 ELSE 0 END) AS total_recebidas,
  SUM(CASE WHEN event = 'CONNECT' THEN 1 ELSE 0 END) AS total_atendidas,
  SUM(CASE WHEN event = 'ABANDON' THEN 1 ELSE 0 END) AS total_abandonadas,
  SUM(CASE WHEN event IN ('EXITWITHTIMEOUT', 'EXITEMPTY') THEN 1 ELSE 0 END) AS total_timeout,
  
  -- Taxas
  ROUND(
    (SUM(CASE WHEN event = 'CONNECT' THEN 1 ELSE 0 END) * 100.0) / 
    NULLIF(SUM(CASE WHEN event = 'ENTERQUEUE' THEN 1 ELSE 0 END), 0), 
    2
  ) AS taxa_atendimento,
  ROUND(
    (SUM(CASE WHEN event = 'ABANDON' THEN 1 ELSE 0 END) * 100.0) / 
    NULLIF(SUM(CASE WHEN event = 'ENTERQUEUE' THEN 1 ELSE 0 END), 0), 
    2
  ) AS taxa_abandono,
  
  -- TME (Tempo Médio de Espera)
  ROUND(AVG(CASE WHEN event = 'CONNECT' THEN d1 ELSE NULL END), 2) AS tme_segundos,
  
  -- TMA (Tempo Médio de Atendimento)
  ROUND(AVG(CASE WHEN event IN ('COMPLETECALLER', 'COMPLETEAGENT') THEN d2 ELSE NULL END), 2) AS tma_segundos,
  
  -- SLA (meta 20 segundos)
  ROUND(
    (SUM(CASE WHEN event = 'CONNECT' AND d1 <= 20 THEN 1 ELSE 0 END) * 100.0) / 
    NULLIF(SUM(CASE WHEN event = 'CONNECT' THEN 1 ELSE 0 END), 0), 
    2
  ) AS sla_20s,
  
  -- SLA (meta 30 segundos)
  ROUND(
    (SUM(CASE WHEN event = 'CONNECT' AND d1 <= 30 THEN 1 ELSE 0 END) * 100.0) / 
    NULLIF(SUM(CASE WHEN event = 'CONNECT' THEN 1 ELSE 0 END), 0), 
    2
  ) AS sla_30s,
  
  -- Paciência média do cliente (em abandonos)
  ROUND(AVG(CASE WHEN event = 'ABANDON' THEN d3 ELSE NULL END), 2) AS paciencia_media
  
FROM dados
GROUP BY queuename
ORDER BY total_recebidas DESC;
```

## 8. Desempenho por Hora do Dia

```sql
SELECT 
  EXTRACT(HOUR FROM eventdate) AS hora,
  SUM(CASE WHEN event = 'ENTERQUEUE' THEN 1 ELSE 0 END) AS recebidas,
  SUM(CASE WHEN event = 'CONNECT' THEN 1 ELSE 0 END) AS atendidas,
  SUM(CASE WHEN event = 'ABANDON' THEN 1 ELSE 0 END) AS abandonadas,
  ROUND(AVG(CASE WHEN event = 'CONNECT' AND data1 ~ '^\d+$' THEN data1::integer ELSE NULL END), 2) AS tme_medio,
  ROUND(
    (SUM(CASE WHEN event = 'CONNECT' AND data1 ~ '^\d+$' AND data1::integer <= 20 THEN 1 ELSE 0 END) * 100.0) /
    NULLIF(SUM(CASE WHEN event = 'CONNECT' THEN 1 ELSE 0 END), 0),
    2
  ) AS sla_20s
FROM queue_log
WHERE event IN ('ENTERQUEUE', 'CONNECT', 'ABANDON')
  AND eventdate >= $1::timestamp
  AND eventdate < $2::timestamp
GROUP BY EXTRACT(HOUR FROM eventdate)
ORDER BY hora;
```

## 9. Desempenho do Agente — Relatório Completo

```sql
WITH agent_calls AS (
  SELECT 
    agent,
    COUNT(*) AS chamadas_atendidas,
    ROUND(AVG(CASE WHEN data1 ~ '^\d+$' THEN data1::integer ELSE NULL END), 2) AS tme_medio,
    ROUND(AVG(CASE WHEN data2 ~ '^\d+$' THEN data2::integer ELSE NULL END), 2) AS tma_medio,
    SUM(CASE WHEN data2 ~ '^\d+$' THEN data2::integer ELSE 0 END) AS tempo_total_falado
  FROM queue_log
  WHERE event IN ('COMPLETECALLER', 'COMPLETEAGENT')
    AND eventdate >= $1::timestamp
    AND eventdate < $2::timestamp
  GROUP BY agent
),
agent_pauses AS (
  SELECT 
    agent,
    COUNT(*) AS total_pausas,
    SUM(CASE WHEN event = 'PAUSE' THEN 1 ELSE 0 END) AS entradas_pausa,
    SUM(CASE WHEN event = 'UNPAUSE' THEN 1 ELSE 0 END) AS saidas_pausa
  FROM queue_log
  WHERE event IN ('PAUSE', 'UNPAUSE')
    AND eventdate >= $1::timestamp
    AND eventdate < $2::timestamp
  GROUP BY agent
),
agent_ring AS (
  SELECT
    agent,
    COUNT(*) AS rings_nao_atendidos
  FROM queue_log
  WHERE event = 'RINGNOANSWER'
    AND eventdate >= $1::timestamp
    AND eventdate < $2::timestamp
  GROUP BY agent
),
agent_login AS (
  SELECT 
    agent,
    MIN(CASE WHEN event = 'AGENTLOGIN' THEN eventdate ELSE NULL END) AS primeiro_login,
    MAX(CASE WHEN event = 'AGENTLOGOFF' THEN eventdate ELSE NULL END) AS ultimo_logoff,
    MAX(CASE WHEN event = 'AGENTLOGOFF' AND data2 ~ '^\d+$' THEN data2::integer ELSE NULL END) AS tempo_logado
  FROM queue_log
  WHERE event IN ('AGENTLOGIN', 'AGENTLOGOFF')
    AND eventdate >= $1::timestamp
    AND eventdate < $2::timestamp
  GROUP BY agent
)
SELECT 
  ac.agent AS agente,
  ac.chamadas_atendidas,
  ac.tme_medio AS tme_segundos,
  ac.tma_medio AS tma_segundos,
  ac.tempo_total_falado,
  COALESCE(ap.entradas_pausa, 0) AS total_pausas,
  COALESCE(ar.rings_nao_atendidos, 0) AS rings_perdidos,
  al.primeiro_login,
  al.ultimo_logoff,
  al.tempo_logado AS tempo_logado_segundos,
  CASE 
    WHEN al.tempo_logado > 0 
    THEN ROUND((ac.tempo_total_falado * 100.0) / al.tempo_logado, 2)
    ELSE NULL
  END AS ocupacao_percentual
FROM agent_calls ac
LEFT JOIN agent_pauses ap ON ac.agent = ap.agent
LEFT JOIN agent_ring ar ON ac.agent = ar.agent
LEFT JOIN agent_login al ON ac.agent = al.agent
ORDER BY ac.chamadas_atendidas DESC;
```

## 10. Relatório por Dia da Semana

```sql
SELECT 
  CASE EXTRACT(DOW FROM eventdate)
    WHEN 0 THEN 'Domingo'
    WHEN 1 THEN 'Segunda'
    WHEN 2 THEN 'Terça'
    WHEN 3 THEN 'Quarta'
    WHEN 4 THEN 'Quinta'
    WHEN 5 THEN 'Sexta'
    WHEN 6 THEN 'Sábado'
  END AS dia_semana,
  EXTRACT(DOW FROM eventdate) AS dow,
  SUM(CASE WHEN event = 'ENTERQUEUE' THEN 1 ELSE 0 END) AS recebidas,
  SUM(CASE WHEN event = 'CONNECT' THEN 1 ELSE 0 END) AS atendidas,
  SUM(CASE WHEN event = 'ABANDON' THEN 1 ELSE 0 END) AS abandonadas,
  ROUND(AVG(CASE WHEN event = 'CONNECT' AND data1 ~ '^\d+$' THEN data1::integer ELSE NULL END), 2) AS tme_medio
FROM queue_log
WHERE event IN ('ENTERQUEUE', 'CONNECT', 'ABANDON')
  AND eventdate >= $1::timestamp
  AND eventdate < $2::timestamp
GROUP BY EXTRACT(DOW FROM eventdate)
ORDER BY dow;
```

## 11. Pausas Detalhadas por Agente

```sql
WITH pause_events AS (
  SELECT 
    agent,
    eventdate AS inicio_pausa,
    data1 AS motivo,
    LEAD(eventdate) OVER (PARTITION BY agent ORDER BY eventdate) AS fim_pausa,
    LEAD(event) OVER (PARTITION BY agent ORDER BY eventdate) AS proximo_evento
  FROM queue_log
  WHERE event IN ('PAUSE', 'UNPAUSE')
    AND eventdate >= $1::timestamp
    AND eventdate < $2::timestamp
)
SELECT 
  agent AS agente,
  motivo,
  COUNT(*) AS total_pausas,
  ROUND(AVG(EXTRACT(EPOCH FROM (fim_pausa - inicio_pausa))), 2) AS duracao_media_segundos,
  SUM(EXTRACT(EPOCH FROM (fim_pausa - inicio_pausa)))::integer AS tempo_total_pausa_segundos
FROM pause_events
WHERE proximo_evento = 'UNPAUSE'
GROUP BY agent, motivo
ORDER BY agent, tempo_total_pausa_segundos DESC;
```

## 12. Relatório Analítico — Chamadas Individuais com JOIN

```sql
SELECT 
  ql_enter.eventdate AS data_hora,
  ql_enter.queuename AS fila,
  cdr.src AS origem,
  cdr.dst AS destino,
  COALESCE(ql_connect.agent, 'Não atendida') AS agente,
  CASE 
    WHEN ql_connect.callid IS NOT NULL THEN 'Atendida'
    WHEN ql_abandon.callid IS NOT NULL THEN 'Abandonada'
    WHEN ql_timeout.callid IS NOT NULL THEN 'Timeout'
    ELSE 'Outro'
  END AS status,
  CASE WHEN ql_connect.data1 ~ '^\d+$' THEN ql_connect.data1::integer ELSE NULL END AS tempo_espera,
  CASE WHEN ql_complete.data2 ~ '^\d+$' THEN ql_complete.data2::integer ELSE NULL END AS tempo_falado,
  cdr.duration AS duracao_total,
  cdr.billsec AS tempo_billsec
FROM queue_log ql_enter
LEFT JOIN cdr ON ql_enter.callid = cdr.uniqueid
LEFT JOIN queue_log ql_connect 
  ON ql_enter.callid = ql_connect.callid 
  AND ql_connect.event = 'CONNECT'
LEFT JOIN queue_log ql_abandon 
  ON ql_enter.callid = ql_abandon.callid 
  AND ql_abandon.event = 'ABANDON'
LEFT JOIN queue_log ql_timeout 
  ON ql_enter.callid = ql_timeout.callid 
  AND ql_timeout.event = 'EXITWITHTIMEOUT'
LEFT JOIN queue_log ql_complete 
  ON ql_enter.callid = ql_complete.callid 
  AND ql_complete.event IN ('COMPLETECALLER', 'COMPLETEAGENT')
WHERE ql_enter.event = 'ENTERQUEUE'
  AND ql_enter.eventdate >= $1::timestamp
  AND ql_enter.eventdate < $2::timestamp
ORDER BY ql_enter.eventdate DESC
LIMIT 500;
```

## 13. Chamadas por Faixa de Duração

```sql
SELECT 
  queuename AS fila,
  SUM(CASE WHEN d2 BETWEEN 0 AND 30 THEN 1 ELSE 0 END) AS "0-30s",
  SUM(CASE WHEN d2 BETWEEN 31 AND 60 THEN 1 ELSE 0 END) AS "31-60s",
  SUM(CASE WHEN d2 BETWEEN 61 AND 120 THEN 1 ELSE 0 END) AS "1-2min",
  SUM(CASE WHEN d2 BETWEEN 121 AND 300 THEN 1 ELSE 0 END) AS "2-5min",
  SUM(CASE WHEN d2 BETWEEN 301 AND 600 THEN 1 ELSE 0 END) AS "5-10min",
  SUM(CASE WHEN d2 > 600 THEN 1 ELSE 0 END) AS "10min+",
  COUNT(*) AS total
FROM (
  SELECT 
    queuename,
    CASE WHEN data2 ~ '^\d+$' THEN data2::integer ELSE NULL END AS d2
  FROM queue_log
  WHERE event IN ('COMPLETECALLER', 'COMPLETEAGENT')
    AND eventdate >= $1::timestamp
    AND eventdate < $2::timestamp
) sub
GROUP BY queuename
ORDER BY total DESC;
```

## 14. Comparativo Diário (Tendência)

```sql
SELECT 
  eventdate::date AS data,
  SUM(CASE WHEN event = 'ENTERQUEUE' THEN 1 ELSE 0 END) AS recebidas,
  SUM(CASE WHEN event = 'CONNECT' THEN 1 ELSE 0 END) AS atendidas,
  SUM(CASE WHEN event = 'ABANDON' THEN 1 ELSE 0 END) AS abandonadas,
  ROUND(
    (SUM(CASE WHEN event = 'CONNECT' THEN 1 ELSE 0 END) * 100.0) /
    NULLIF(SUM(CASE WHEN event = 'ENTERQUEUE' THEN 1 ELSE 0 END), 0),
    2
  ) AS taxa_atendimento,
  ROUND(AVG(CASE WHEN event = 'CONNECT' AND data1 ~ '^\d+$' THEN data1::integer ELSE NULL END), 2) AS tme_medio,
  ROUND(
    (SUM(CASE WHEN event = 'CONNECT' AND data1 ~ '^\d+$' AND data1::integer <= 20 THEN 1 ELSE 0 END) * 100.0) /
    NULLIF(SUM(CASE WHEN event = 'CONNECT' THEN 1 ELSE 0 END), 0),
    2
  ) AS sla_20s
FROM queue_log
WHERE event IN ('ENTERQUEUE', 'CONNECT', 'ABANDON')
  AND eventdate >= $1::timestamp
  AND eventdate < $2::timestamp
GROUP BY eventdate::date
ORDER BY data;
```

---

## Consultas para Tabelas Customizadas VoxCALL

---

## 15. Painel de Operadores em Tempo Real (monitor_operador)

```sql
SELECT 
  operador,
  ramal,
  CASE 
    WHEN hora_logoff IS NOT NULL THEN 'Deslogado'
    WHEN fl_pausa = 1 THEN 'Em Pausa'
    ELSE 'Disponível'
  END AS status,
  tipo_pausa,
  hora_login,
  hora_logoff,
  hora_entra_pausa,
  hora_sai_pausa,
  ultimo_atendimento,
  atendidas,
  CASE 
    WHEN hora_login IS NOT NULL AND hora_logoff IS NULL 
    THEN EXTRACT(EPOCH FROM (NOW() - hora_login))::integer
    ELSE NULL
  END AS tempo_logado_segundos,
  CASE 
    WHEN fl_pausa = 1 AND hora_entra_pausa IS NOT NULL 
    THEN EXTRACT(EPOCH FROM (NOW() - hora_entra_pausa))::integer
    ELSE NULL
  END AS tempo_em_pausa_segundos
FROM monitor_operador
WHERE hora_logoff IS NULL
ORDER BY 
  fl_pausa ASC,
  atendidas DESC;
```

## 16. Resumo de Operadores — Dashboard

```sql
SELECT 
  COUNT(*) FILTER (WHERE hora_logoff IS NULL) AS total_logados,
  COUNT(*) FILTER (WHERE hora_logoff IS NULL AND fl_pausa = 0) AS disponiveis,
  COUNT(*) FILTER (WHERE hora_logoff IS NULL AND fl_pausa = 1) AS em_pausa,
  COUNT(*) FILTER (WHERE hora_logoff IS NOT NULL) AS deslogados,
  COUNT(*) FILTER (WHERE hora_logoff IS NULL AND fl_pausa = 1 AND tipo_pausa = 'SUPERVISAO') AS supervisores,
  SUM(CASE WHEN hora_logoff IS NULL THEN atendidas ELSE 0 END) AS total_atendidas_dia,
  ROUND(AVG(CASE WHEN hora_logoff IS NULL AND atendidas > 0 THEN atendidas ELSE NULL END), 1) AS media_atendidas_por_operador
FROM monitor_operador;
```

## 17. Ranking de Operadores por Atendimentos

```sql
SELECT 
  operador,
  ramal,
  atendidas,
  hora_login,
  ultimo_atendimento,
  CASE 
    WHEN hora_login IS NOT NULL AND hora_logoff IS NULL 
    THEN EXTRACT(EPOCH FROM (NOW() - hora_login))::integer
    ELSE NULL
  END AS tempo_logado_segundos,
  CASE 
    WHEN hora_login IS NOT NULL AND hora_logoff IS NULL AND EXTRACT(EPOCH FROM (NOW() - hora_login)) > 0
    THEN ROUND(atendidas * 3600.0 / EXTRACT(EPOCH FROM (NOW() - hora_login)), 2)
    ELSE NULL
  END AS atendimentos_por_hora
FROM monitor_operador
WHERE hora_logoff IS NULL
  AND atendidas > 0
ORDER BY atendidas DESC;
```

## 18. Pausas Ativas (Quem está em pausa agora)

```sql
SELECT 
  operador,
  ramal,
  tipo_pausa,
  hora_entra_pausa,
  EXTRACT(EPOCH FROM (NOW() - hora_entra_pausa))::integer AS tempo_em_pausa_segundos,
  TO_CHAR(hora_entra_pausa, 'HH24:MI:SS') AS inicio_pausa_formatado
FROM monitor_operador
WHERE fl_pausa = 1
  AND hora_logoff IS NULL
ORDER BY hora_entra_pausa ASC;
```

## 19. Atendimentos por Operador com Detalhes (t_monitor_voxcall)

```sql
SELECT 
  tmv.operador,
  tmv.fila,
  COUNT(*) AS total_atendimentos,
  ROUND(AVG(CASE WHEN tmv.espera ~ '^\d+$' THEN tmv.espera::integer ELSE NULL END), 2) AS espera_media_segundos,
  MIN(tmv.hora_atendimento) AS primeiro_atendimento,
  MAX(tmv.hora_atendimento) AS ultimo_atendimento
FROM t_monitor_voxcall tmv
WHERE tmv.hora_atendimento >= $1::timestamp
  AND tmv.hora_atendimento < $2::timestamp
GROUP BY tmv.operador, tmv.fila
ORDER BY total_atendimentos DESC;
```

## 20. Relatório Analítico Completo — JOIN das 4 Tabelas

```sql
SELECT 
  tmv.hora_atendimento AS data_hora,
  tmv.protocolo,
  tmv.fila,
  tmv.operador,
  tmv.ramal,
  tmv.telefone,
  CASE WHEN tmv.espera ~ '^\d+$' THEN tmv.espera::integer ELSE NULL END AS tempo_espera,
  cdr.billsec AS tempo_falado,
  cdr.duration AS duracao_total,
  cdr.disposition AS status_cdr,
  mo.atendidas AS total_atendidas_operador,
  tmv.codgravacao
FROM t_monitor_voxcall tmv
LEFT JOIN cdr ON tmv.callid = cdr.uniqueid
LEFT JOIN monitor_operador mo ON tmv.operador = mo.operador
WHERE tmv.hora_atendimento >= $1::timestamp
  AND tmv.hora_atendimento < $2::timestamp
ORDER BY tmv.hora_atendimento DESC
LIMIT 500;
```

## 21. Chamadas por Fila e Operador — t_monitor_voxcall

```sql
SELECT 
  tmv.fila,
  tmv.operador,
  COUNT(*) AS atendimentos,
  ROUND(AVG(CASE WHEN tmv.espera ~ '^\d+$' THEN tmv.espera::integer ELSE NULL END), 2) AS espera_media,
  ROUND(AVG(cdr.billsec), 2) AS tma_segundos,
  SUM(cdr.billsec) AS tempo_total_falado
FROM t_monitor_voxcall tmv
LEFT JOIN cdr ON tmv.callid = cdr.uniqueid
WHERE tmv.hora_atendimento >= $1::timestamp
  AND tmv.hora_atendimento < $2::timestamp
GROUP BY tmv.fila, tmv.operador
ORDER BY tmv.fila, atendimentos DESC;
```

## 22. Busca por Protocolo ou Telefone

```sql
-- Busca por protocolo
SELECT 
  tmv.protocolo,
  tmv.hora_atendimento,
  tmv.operador,
  tmv.fila,
  tmv.telefone,
  tmv.ramal,
  tmv.espera,
  cdr.duration,
  cdr.billsec,
  cdr.disposition,
  tmv.codgravacao
FROM t_monitor_voxcall tmv
LEFT JOIN cdr ON tmv.callid = cdr.uniqueid
WHERE tmv.protocolo = $1
   OR tmv.telefone = $1;
```

## 23. Volume de Chamadas por Fila (t_monitor_voxcall)

```sql
SELECT 
  fila,
  COUNT(*) AS total_atendidas,
  COUNT(DISTINCT operador) AS operadores_ativos,
  ROUND(AVG(CASE WHEN espera ~ '^\d+$' THEN espera::integer ELSE NULL END), 2) AS espera_media,
  MIN(hora_atendimento) AS primeiro_atendimento,
  MAX(hora_atendimento) AS ultimo_atendimento
FROM t_monitor_voxcall
WHERE hora_atendimento >= $1::timestamp
  AND hora_atendimento < $2::timestamp
GROUP BY fila
ORDER BY total_atendidas DESC;
```

---

## Notas de Implementação no VoxCALL

### Formatar Duração no Frontend
```typescript
function formatDuration(seconds: number): string {
  if (!seconds || seconds < 0) return '00:00:00';
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
}
```

### Normalizar Nome do Agente
```typescript
function normalizeAgent(agent: string): string {
  // PJSIP/1001-00000001 → 1001
  // SIP/1001-00000001 → 1001
  // Local/1001@from-internal → 1001
  const match = agent.match(/(?:PJSIP|SIP|IAX2|Local)\/(\d+)/);
  return match ? match[1] : agent;
}
```

### Construção Dinâmica de Filtros
```typescript
function buildWhereClause(filters: {
  startDate: string;
  endDate: string;
  queue?: string;
  agent?: string;
}): { where: string; params: any[] } {
  const conditions = ['eventdate >= $1::timestamp', 'eventdate < $2::timestamp'];
  const params: any[] = [filters.startDate, filters.endDate];
  
  if (filters.queue) {
    params.push(filters.queue);
    conditions.push(`queuename = $${params.length}`);
  }
  
  if (filters.agent) {
    params.push(`%${filters.agent}%`);
    conditions.push(`agent LIKE $${params.length}`);
  }
  
  return { where: conditions.join(' AND '), params };
}
```
