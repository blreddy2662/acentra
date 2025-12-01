-- Redshift-safe LISTAGG replacement: include as many codes per measure as fit under LISTAGG limit,
-- and append a "(+K more)" indicator when truncation happened.
-- Integrate this CTE into your main query (replace prior measure_codes CTE).

WITH measure_codes AS (
  -- Reserve a small safety margin (in bytes) so we do not hit the exact 16,000,000 limit.
  -- You can reduce margin if you want to push closer to the limit.
  SELECT
    measure_sid,
    LISTAGG(code, ', ') WITHIN GROUP (ORDER BY code) AS codeagg_limited,
    total_cnt,
    MAX(rn_included) AS included_cnt
  FROM (
    SELECT
      a.measure_sid,
      a.code,
      ROW_NUMBER() OVER (PARTITION BY a.measure_sid ORDER BY code) AS rn,
      COUNT(*) OVER (PARTITION BY a.measure_sid) AS total_cnt,
      -- running cumulative length of codes plus ", " separators (roughly +2 per extra code)
      SUM(LENGTH(a.code) + 2) OVER (PARTITION BY a.measure_sid ORDER BY code
                                    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_len,
      -- mark row as included only if cumulative length remains under threshold
      -- we will filter on this in the outer WHERE clause
      ROW_NUMBER() OVER (PARTITION BY a.measure_sid ORDER BY code) AS rn_included
    FROM udprdsftas.udp_msr_prvdr_tcn_detail a
    WHERE a.schedule_run_sid = 385
  ) t
  WHERE cum_len <= 16000000 - 2000  -- safety margin: 2KB; adjust if you want
  GROUP BY measure_sid, total_cnt
),

measure_codes_final AS (
  SELECT
    measure_sid,
    CASE
      WHEN included_cnt < total_cnt
      THEN codeagg_limited || ', ...(+ ' || (total_cnt - included_cnt) || ' more)'
      ELSE codeagg_limited
    END AS codeagg
  FROM (
    SELECT measure_sid, codeagg_limited, total_cnt, included_cnt
    FROM measure_codes
  ) x
)
-- Example: select from measure_codes_final to see results
SELECT * FROM measure_codes_final;
