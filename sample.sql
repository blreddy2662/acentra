-- Persistent staging DDL (run once; schedule refresh per run)
-- Adjust schema and table names as needed. These are created as permanent tables (not temp).
-- Replace owner/schema if needed and ensure you have permissions.

-- 1) Stage schedule_run (small)
DROP TABLE IF EXISTS staging.schedule_run_385;
CREATE TABLE staging.schedule_run_385 DISTSTYLE ALL AS
SELECT schedule_run_sid, data_start_date, data_end_date
FROM udprdsftas.udp_schedule_run
WHERE schedule_run_sid = 385;
ANALYZE staging.schedule_run_385;

-- 2) Stage provider measures (filtered) - useful join column: dim_prvdr_sid
DROP TABLE IF EXISTS staging.prvdr_msr_385;
CREATE TABLE staging.prvdr_msr_385
DISTSTYLE KEY DISTKEY(dim_prvdr_sid)
AS
SELECT dim_prvdr_sid, measure_sid
FROM udprdsftas.udp_rslt_surs_prvdr_msr
WHERE schedule_run_sid = 385
  AND measure_val <> 0;
ANALYZE staging.prvdr_msr_385;

-- 3) Stage claim headers relevant to provider 1363112 (small-ish)
DROP TABLE IF EXISTS staging.claim_header_candidates_1363112_385;
CREATE TABLE staging.claim_header_candidates_1363112_385
DISTSTYLE KEY DISTKEY(claim_header_sid)
AS
SELECT DISTINCT h.claim_header_sid
FROM udprdsftas.udp_clm_header h
JOIN udprdsftas.udp_clm_line cl ON cl.claim_header_sid = h.claim_header_sid
JOIN staging.schedule_run_385 sr ON h.adjudication_date BETWEEN sr.data_start_date AND sr.data_end_date
WHERE cl.SRVCNG_PRVDR_LCTN_IDENTIFIER = '1363112'
   OR h.SRVCNG_PRVDR_LCTN_IDENTIFIER = '1363112'
   OR h.BLNG_PRVDR_LCTN_IDENTIFIER = '1363112';
ANALYZE staging.claim_header_candidates_1363112_385;

-- 4) Stage measure code rows for only relevant measures (one row per code) - avoids LISTAGG overflow
DROP TABLE IF EXISTS staging.measure_code_rows_385;
CREATE TABLE staging.measure_code_rows_385
DISTSTYLE KEY DISTKEY(measure_sid)
SORTKEY(measure_sid, code)  -- sort by measure for efficient retrieval
AS
WITH relevant_measures AS (
  SELECT DISTINCT measure_sid FROM staging.prvdr_msr_385
),
dedup AS (
  SELECT a.measure_sid, a.code
  FROM udprdsftas.udp_msr_prvdr_tcn_detail a
  JOIN relevant_measures rm ON a.measure_sid = rm.measure_sid
  WHERE a.schedule_run_sid = 385
),
ord AS (
  SELECT measure_sid, code,
         ROW_NUMBER() OVER (PARTITION BY measure_sid ORDER BY code) AS code_ord,
         COUNT(*) OVER (PARTITION BY measure_sid) AS total_cnt
  FROM dedup
)
SELECT measure_sid, code, code_ord, total_cnt
FROM ord;
ANALYZE staging.measure_code_rows_385;

-- 5) Optional: Stage claims header minimal projection for joins (to avoid repeated full scans)
DROP TABLE IF EXISTS staging.clm_header_proj_1363112_385;
CREATE TABLE staging.clm_header_proj_1363112_385
DISTSTYLE KEY DISTKEY(claim_header_sid)
SORTKEY(adjudication_date)
AS
SELECT claim_header_sid, tcn, from_service_date, to_service_date,
       total_billed_amount, paid_amount,
       patient_first_name, patient_last_name,
       blng_prvdr_first_name, blng_prvdr_last_name,
       blng_national_prvdr_idntfr,
       blng_prvdr_lctn_identifier,
       SRVCNG_PRVDR_LCTN_IDENTIFIER, BLNG_PRVDR_LCTN_IDENTIFIER,
       primary_diagnosis_iid, dim_mbr_sid, adjudication_date
FROM udprdsftas.udp_clm_header h
WHERE h.adjudication_date BETWEEN (SELECT data_start_date FROM staging.schedule_run_385)
                            AND (SELECT data_end_date FROM staging.schedule_run_385)
  AND (h.SRVCNG_PRVDR_LCTN_IDENTIFIER = '1363112'
       OR h.BLNG_PRVDR_LCTN_IDENTIFIER = '1363112');
ANALYZE staging.clm_header_proj_1363112_385;
