-- Optimized single-query (CTE) version for Redshift.
-- - Avoids OR by using UNION for provider-location matches
-- - Restricts code scanning to only measures present in the filtered provider-measure set
-- - Returns one row per original result row per code (preserves every code; no LISTAGG overflow)
-- Run as a single statement in one session. Replace schedule_run_sid / provider id as needed.

WITH
-- schedule run window (small)
sr AS (
  SELECT schedule_run_sid, data_start_date, data_end_date
  FROM udprdsftas.udp_schedule_run
  WHERE schedule_run_sid = 385
),

-- provider-measure rows (filtered & reduced early)
prvdr_msr AS (
  SELECT DISTINCT dim_prvdr_sid, measure_sid
  FROM udprdsftas.udp_rslt_surs_prvdr_msr
  WHERE schedule_run_sid = 385
    AND measure_val <> 0
),

-- claim headers matching provider identifier (UNION avoids OR and allows index use)
claim_header_candidates AS (
  SELECT DISTINCT cl.claim_header_sid
  FROM udprdsftas.udp_clm_line cl
  JOIN udprdsftas.udp_clm_header h ON h.claim_header_sid = cl.claim_header_sid
  JOIN sr ON h.adjudication_date BETWEEN sr.data_start_date AND sr.data_end_date
  WHERE cl.SRVCNG_PRVDR_LCTN_IDENTIFIER = '1363112'

  UNION

  SELECT DISTINCT h.claim_header_sid
  FROM udprdsftas.udp_clm_header h
  JOIN sr ON h.adjudication_date BETWEEN sr.data_start_date AND sr.data_end_date
  WHERE h.SRVCNG_PRVDR_LCTN_IDENTIFIER = '1363112'

  UNION

  SELECT DISTINCT h.claim_header_sid
  FROM udprdsftas.udp_clm_header h
  JOIN sr ON h.adjudication_date BETWEEN sr.data_start_date AND sr.data_end_date
  WHERE h.BLNG_PRVDR_LCTN_IDENTIFIER = '1363112'
),

-- minimal header projection for faster joins
clm_header_proj AS (
  SELECT
    h.claim_header_sid,
    h.tcn,
    h.from_service_date,
    h.to_service_date,
    h.total_billed_amount,
    h.paid_amount,
    h.patient_first_name,
    h.patient_last_name,
    h.blng_prvdr_first_name,
    h.blng_prvdr_last_name,
    h.blng_national_prvdr_idntfr,
    h.blng_prvdr_lctn_identifier,
    h.SRVCNG_PRVDR_LCTN_IDENTIFIER,
    h.BLNG_PRVDR_LCTN_IDENTIFIER,
    h.primary_diagnosis_iid,
    h.dim_mbr_sid,
    h.adjudication_date
  FROM udprdsftas.udp_clm_header h
  WHERE h.claim_header_sid IN (SELECT claim_header_sid FROM claim_header_candidates)
),

-- Only codes for measures that actually appear in prvdr_msr (restrict costly scan)
measure_code_rows AS (
  WITH relevant_measures AS (
    SELECT DISTINCT measure_sid FROM prvdr_msr
  ),
  dedup AS (
    SELECT a.measure_sid, a.code
    FROM udprdsftas.udp_msr_prvdr_tcn_detail a
    JOIN relevant_measures rm ON a.measure_sid = rm.measure_sid
    WHERE a.schedule_run_sid = 385
  ),
  ord AS (
    SELECT
      measure_sid,
      code,
      ROW_NUMBER() OVER (PARTITION BY measure_sid ORDER BY code) AS code_ord,
      COUNT(*) OVER (PARTITION BY measure_sid) AS total_cnt
    FROM (
      SELECT DISTINCT measure_sid, code  -- dedupe equal codes per measure
      FROM dedup
    ) d
  )
  SELECT measure_sid, code, code_ord, total_cnt
  FROM ord
),

-- provider_info and member/diagnosis are small reference joins; keep them in main select
-- final result: one row per header x code (preserves all codes)
final AS (
  SELECT DISTINCT
    193 AS scenario_sid,
    385 AS schedule_run_sid,
    NVL((h.blng_national_prvdr_idntfr)::varchar, ' ') AS provider_npi,
    NVL((h.blng_prvdr_lctn_identifier)::varchar, ' ') AS provider_id,
    m.client_mmis_id AS member_id,
    h.tcn,
    TO_CHAR(h.from_service_date, 'MM/DD/YYYY') AS from_service_date,
    TO_CHAR(h.to_service_date, 'MM/DD/YYYY') AS to_service_date,
    NVL(TO_CHAR(h.total_billed_amount, '999999.99'), '0.00') AS billed_amount,
    NVL(TO_CHAR(h.paid_amount, '999999.99'), '0.00') AS paid_amount,
    h.patient_first_name || ' ' || h.patient_last_name AS member_name,
    h.blng_prvdr_first_name || ' ' || h.blng_prvdr_last_name AS provider_name,
    d.diagnosis_code || ' - ' || d.diag_short_desc AS DC,
    h.total_billed_amount AS sort_billed_amount,
    h.paid_amount AS sort_paid_amount,
    h.from_service_date AS sort_from_date,
    h.to_service_date AS sort_to_date,
    CURRENT_DATE AS last_extract_date,
    'Y' AS status,
    1363112 AS participant_id,
    pm.measure_sid,
    mcr.code AS code,
    mcr.code_ord,
    mcr.total_cnt
  FROM clm_header_proj h
  LEFT JOIN udprdsftas.udp_clm_line cl ON cl.claim_header_sid = h.claim_header_sid
  JOIN udprdsftvrtl.udp_provider_info p
    ON p.prvdr_mmis_idntfr = NVL(cl.SRVCNG_PRVDR_LCTN_IDENTIFIER,
                                 NVL(h.SRVCNG_PRVDR_LCTN_IDENTIFIER, h.BLNG_PRVDR_LCTN_IDENTIFIER))
  JOIN udprdsftvrtl.udp_d_diagnosis d ON d.diagnosis_iid = h.primary_diagnosis_iid
  JOIN udprdsftvrtl.udp_member_info m ON h.dim_mbr_sid = m.mbr_sid
  JOIN prvdr_msr pm ON pm.dim_prvdr_sid = p.prvdr_sid
  LEFT JOIN measure_code_rows mcr ON mcr.measure_sid = pm.measure_sid
)

SELECT *
FROM final
ORDER BY measure_sid, code_ord;  -- optional: remove ORDER BY if not needed
