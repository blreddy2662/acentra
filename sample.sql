-- Redshift-safe: preserve all codes (one row per code) to avoid LISTAGG overflow.
-- Run this in one session; temp tables live only for the session.

BEGIN;

-- Stage the schedule run window
DROP TABLE IF EXISTS tmp_schedule_run;
CREATE TEMP TABLE tmp_schedule_run AS
SELECT schedule_run_sid, data_start_date, data_end_date
FROM udprdsftas.udp_schedule_run
WHERE schedule_run_sid = 385;
ANALYZE tmp_schedule_run;

-- Stage prvdr_msr (filter to schedule & non-zero measure)
DROP TABLE IF EXISTS tmp_prvdr_msr;
CREATE TEMP TABLE tmp_prvdr_msr
DISTSTYLE KEY DISTKEY(dim_prvdr_sid)
AS
SELECT dim_prvdr_sid, measure_sid
FROM udprdsftas.udp_rslt_surs_prvdr_msr
WHERE schedule_run_sid = 385
  AND measure_val <> 0;
ANALYZE tmp_prvdr_msr;

-- Persist every code as one row per measure_sid (deduplicated)
DROP TABLE IF EXISTS tmp_measure_code_rows;
CREATE TEMP TABLE tmp_measure_code_rows
DISTSTYLE KEY DISTKEY(measure_sid)
AS
WITH dedup AS (
  -- deduplicate identical codes per measure if necessary
  SELECT measure_sid, code
  FROM (
    SELECT measure_sid, code,
           ROW_NUMBER() OVER (PARTITION BY measure_sid, code ORDER BY code) AS rn_dup
    FROM udprdsftas.udp_msr_prvdr_tcn_detail
    WHERE schedule_run_sid = 385
  ) t
  WHERE rn_dup = 1
),
ord AS (
  SELECT
    measure_sid,
    code,
    ROW_NUMBER() OVER (PARTITION BY measure_sid ORDER BY code) AS code_ord,
    COUNT(*) OVER (PARTITION BY measure_sid) AS total_cnt
  FROM dedup
)
SELECT measure_sid, code, code_ord, total_cnt
FROM ord;
ANALYZE tmp_measure_code_rows;

-- Build claim header candidate list (UNION to avoid OR)
DROP TABLE IF EXISTS tmp_claim_header_candidates;
CREATE TEMP TABLE tmp_claim_header_candidates
DISTSTYLE EVEN
AS
SELECT DISTINCT cl.claim_header_sid
FROM udprdsftas.udp_clm_line cl
JOIN udprdsftas.udp_clm_header h ON h.claim_header_sid = cl.claim_header_sid
JOIN tmp_schedule_run sr ON h.adjudication_date BETWEEN sr.data_start_date AND sr.data_end_date
WHERE cl.SRVCNG_PRVDR_LCTN_IDENTIFIER = '1363112'

UNION

SELECT DISTINCT h.claim_header_sid
FROM udprdsftas.udp_clm_header h
JOIN tmp_schedule_run sr ON h.adjudication_date BETWEEN sr.data_start_date AND sr.data_end_date
WHERE h.SRVCNG_PRVDR_LCTN_IDENTIFIER = '1363112'

UNION

SELECT DISTINCT h.claim_header_sid
FROM udprdsftas.udp_clm_header h
JOIN tmp_schedule_run sr ON h.adjudication_date BETWEEN sr.data_start_date AND sr.data_end_date
WHERE h.BLNG_PRVDR_LCTN_IDENTIFIER = '1363112';
ANALYZE tmp_claim_header_candidates;

-- Final SELECT: returns one row per original result row per code.
-- If a measure has N codes, the corresponding header/provider row will repeat N times (one for each code).
-- This preserves every code while avoiding LISTAGG size limits.
SELECT DISTINCT
  193 AS scenario_sid,
  385 AS schedule_run_sid,
  NVL((h.blng_national_prvdr_idntfr)::varchar,' ') AS provider_npi,
  NVL((h.blng_prvdr_lctn_identifier)::varchar,' ') AS provider_id,
  m.client_mmis_id AS member_id,
  h.tcn,
  TO_CHAR(h.from_service_date,'MM/DD/YYYY') AS from_service_date,
  TO_CHAR(h.to_service_date,'MM/DD/YYYY') AS to_service_date,
  NVL(TO_CHAR(h.total_billed_amount,'999999.99'),'0.00') AS billed_amount,
  NVL(TO_CHAR(h.paid_amount,'999999.99'),'0.00') AS paid_amount,
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
  mcr.code AS code,           -- one row per code (full data preserved)
  mcr.code_ord AS code_ord,   -- ordinal of the code within the measure
  mcr.total_cnt AS total_codes_for_measure
FROM tmp_claim_header_candidates chc
JOIN udprdsftas.udp_clm_header h ON h.claim_header_sid = chc.claim_header_sid
LEFT JOIN udprdsftas.udp_clm_line cl ON cl.claim_header_sid = h.claim_header_sid
JOIN udprdsftvrtl.udp_provider_info p
  ON p.prvdr_mmis_idntfr = NVL(cl.SRVCNG_PRVDR_LCTN_IDENTIFIER,
                               NVL(h.SRVCNG_PRVDR_LCTN_IDENTIFIER, h.BLNG_PRVDR_LCTN_IDENTIFIER))
JOIN udprdsftvrtl.udp_d_diagnosis d ON d.diagnosis_iid = h.primary_diagnosis_iid
JOIN udprdsftvrtl.udp_member_info m ON h.dim_mbr_sid = m.mbr_sid
JOIN tmp_prvdr_msr pm ON pm.dim_prvdr_sid = p.prvdr_sid
LEFT JOIN tmp_measure_code_rows mcr ON mcr.measure_sid = pm.measure_sid
ORDER BY pm.measure_sid, mcr.code_ord;  -- optional ordering

COMMIT;
