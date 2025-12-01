WITH sr AS (
  -- keep only the schedule run we need and its date-window
  SELECT schedule_run_sid, data_start_date, data_end_date
  FROM udprdsftas.udp_schedule_run
  WHERE schedule_run_sid = 385
),
-- pre-aggregate code list per measure for schedule_run 385
measure_codes AS (
  SELECT
    a.measure_sid,
    LISTAGG(code, ', ') WITHIN GROUP (ORDER BY code) AS codeagg
  FROM udprdsftas.udp_msr_prvdr_tcn_detail a
  WHERE a.schedule_run_sid = 385
  GROUP BY a.measure_sid
),
-- restrict provider rows to only those that match the provider identifier in provider_info
prov AS (
  SELECT prvdr_sid, prvdr_mmis_idntfr
  FROM udprdsftvrtl.udp_provider_info
  -- add any provider-level filters here if required
),
-- only consider rslt_surs_prvdr_msr rows for the schedule run and non-zero measures
prvdr_msr AS (
  SELECT dim_prvdr_sid, measure_sid
  FROM udprdsftas.udp_rslt_surs_prvdr_msr
  WHERE schedule_run_sid = 385
    AND measure_val <> 0
),
-- build a list of claim_header_sid that match the provider id = 1363112,
-- using UNION to avoid OR across columns so indexes on each column can be used
claim_header_candidates AS (
  SELECT DISTINCT cl.claim_header_sid
  FROM udprdsftas.udp_clm_line cl
  JOIN sr ON 1=1
  WHERE cl.SRVCNG_PRVDR_LCTN_IDENTIFIER = '1363112'
    -- limit by related header adjudication window using a join to header below
    AND EXISTS (
      SELECT 1 FROM udprdsftas.udp_clm_header h
      WHERE h.claim_header_sid = cl.claim_header_sid
        AND h.adjudication_date BETWEEN sr.data_start_date AND sr.data_end_date
    )
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
-- Now select main rows but join only to the reduced sets above
main AS (
  SELECT
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
    '1363112' AS participant_id,
    r.measure_sid,
    mc.codeagg
  FROM claim_header_candidates chc
  JOIN udprdsftas.udp_clm_header h
    ON h.claim_header_sid = chc.claim_header_sid
    -- header already guaranteed to be within schedule_run date window via the candidate CTE
  LEFT JOIN udprdsftas.udp_clm_line cl
    ON cl.claim_header_sid = h.claim_header_sid
  JOIN udprdsftvrtl.udp_provider_info p
    ON p.prvdr_mmis_idntfr = NVL(cl.SRVCNG_PRVDR_LCTN_IDENTIFIER,
                                 NVL(h.SRVCNG_PRVDR_LCTN_IDENTIFIER, h.BLNG_PRVDR_LCTN_IDENTIFIER))
  JOIN udprdsftvrtl.udp_d_diagnosis d
    ON d.diagnosis_iid = h.primary_diagnosis_iid
  JOIN udprdsftvrtl.udp_member_info m
    ON h.dim_mbr_sid = m.mbr_sid
  JOIN prvdr_msr r
    ON r.dim_prvdr_sid = p.prvdr_sid
  LEFT JOIN measure_codes mc
    ON mc.measure_sid = r.measure_sid
  -- If you still see duplicates (e.g. multiple lines per header), consider deduplicating here with ROW_NUMBER()
)
SELECT *
FROM main;
