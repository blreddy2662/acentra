-- Optimized for Redshift: preserves original result & logic but avoids window-in-IN-subquery
-- and reduces scanning / repeated work by computing latest runs once, and by moving filters earlier.
WITH latest_runs AS (
    -- latest run_id per scenario for type = 'ADHOC'
    SELECT scenario_sid,
           MAX(run_id) AS run_id
    FROM udprdsftas.udp_surs_run_list_vw
    WHERE UPPER(type) = 'ADHOC'
    GROUP BY scenario_sid
),
allowed_scenario_dtl AS (
    -- union of scenario_dtl_sid from scenario_detail and scenario_reject for scenario_type = 'SURS'
    SELECT scenario_dtl_sid
    FROM udprdsftasext.scenario_detail
    WHERE scenario_type = 'SURS'
    UNION
    SELECT scenario_dtl_sid
    FROM udprdsftasext.scenario_reject
    WHERE scenario_type = 'SURS'
)
SELECT
    lr.run_id,
    sv.scenario_sid,
    LISTAGG(uppv.program_cid::int, ',') WITHIN GROUP (ORDER BY uppv.program_cid)     AS program_cid,
    LISTAGG(uppv.program_name, ',')   WITHIN GROUP (ORDER BY uppv.program_name)      AS program_name,
    sv.name,
    sv.code,
    sv.scenario_dtl_sid,
    sv.entity,
    sv.type,
    sv.status,
    sv.frequency,
    sv.run_date,
    sv.user_acct_sid,
    COUNT(*) OVER ()                                                                     AS cnt
FROM udprdsftas.udp_surs_run_list_vw sv
JOIN latest_runs lr
    ON sv.scenario_sid = lr.scenario_sid
   AND sv.run_id = lr.run_id          -- only rows for the latest run per scenario (type = 'ADHOC')
JOIN udprdsftasext.user_prfl_prgm uppv
    ON sv.program_cid = uppv.program_cid
JOIN udprdsftasext.scenario_x_program u
    ON sv.scenario_dtl_sid = u.scenario_dtl_sid
JOIN allowed_scenario_dtl w
    ON u.scenario_dtl_sid = w.scenario_dtl_sid
WHERE UPPER(sv.user_login_id) = UPPER('supuser')
  AND sv.prfl_sid = 500031635
  AND UPPER(sv.type) = UPPER('Adhoc')
  AND sv.code SIMILAR TO '%DEMOSI01%'
GROUP BY
    lr.run_id,
    sv.scenario_sid,
    sv.name,
    sv.code,
    sv.scenario_dtl_sid,
    sv.entity,
    sv.type,
    sv.status,
    sv.frequency,
    sv.run_date,
    sv.user_acct_sid
ORDER BY lr.run_id DESC
OFFSET 0
LIMIT 100;
