WITH latest_runs AS (
    SELECT run_id, scenario_sid
    FROM (
        SELECT run_id, scenario_sid,
               ROW_NUMBER() OVER (PARTITION BY scenario_sid ORDER BY run_id DESC) AS rn
        FROM udprdsftas.udp_surs_run_list_vw
        WHERE type ILIKE 'Adhoc'
    ) t
    WHERE rn = 1
),
scenario_details AS (
    SELECT u.scenario_dtl_sid
    FROM udprdsftasext.scenario_x_program u
    INNER JOIN (
        SELECT scenario_dtl_sid
        FROM udprdsftasext.scenario_detail sd
        INNER JOIN udprdsftasext.scenario s ON s.scenario_sid = sd.scenario_sid
        WHERE s.scenario_type = 'SURS'
        UNION
        SELECT scenario_dtl_sid
        FROM udprdsftasext.scenario_reject
        WHERE scenario_type = 'SURS'
    ) w ON w.scenario_dtl_sid = u.scenario_dtl_sid
)
SELECT
    sv.run_id,
    sv.scenario_sid,
    LISTAGG(uppv.program_cid::INT, ',') WITHIN GROUP (ORDER BY uppv.program_cid) AS program_cid,
    LISTAGG(uppv.program_name, ',') WITHIN GROUP (ORDER BY uppv.program_cid) AS program_name,
    sv.name,
    sv.code,
    sv.scenario_dtl_sid,
    sv.entity,
    sv.type,
    sv.status,
    sv.frequency,
    sv.run_date,
    COUNT(*) OVER() AS cnt
FROM udprdsftas.udp_surs_run_list_vw sv
INNER JOIN udprdsftasext.user_prfl_prgm uppv ON sv.program_cid = uppv.program_cid
INNER JOIN latest_runs lr ON sv.run_id = lr.run_id AND sv.scenario_sid = lr.scenario_sid
WHERE sv.type ILIKE 'Adhoc'
  AND sv.code ILIKE '%DEMOSI01%'
  AND sv.scenario_dtl_sid IN (SELECT scenario_dtl_sid FROM scenario_details)
GROUP BY
    sv.run_id,
    sv.scenario_sid,
    sv.name,
    sv.code,
    sv.scenario_dtl_sid,
    sv.entity,
    sv.type,
    sv.status,
    sv.frequency,
    sv.run_date
ORDER BY sv.run_id DESC
LIMIT 100 OFFSET 0;
