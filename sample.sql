-- Example: non-atomic stored procedure with batch commits
-- Works in Amazon Redshift and Postgres (procedures that allow COMMIT)
CREATE OR REPLACE PROCEDURE udprdsftas.udp_pr_rpt_claim_detail_non_atomic(
    IN p_scenario_sid numeric,
    IN p_prvdr_npi varchar,
    IN p_schedule_run_sid numeric,
    IN p_debug varchar,
    IN p_start_number numeric,
    IN p_end_number numeric,
    IN p_column_name varchar,
    IN p_order_by varchar,
    IN p_batch_size integer DEFAULT 1000,    -- batch size for commits
    INOUT p_participant_count numeric,
    INOUT p_result_set varchar,
    INOUT p_err_code varchar,
    INOUT p_err_msg varchar
)
LANGUAGE plpgsql
NONATOMIC
AS $$
DECLARE
  v_order_col text;
  v_order_dir text;
  v_sql text;
  v_rows_processed int := 0;
  v_total_count bigint := 0;
  cur_ref refcursor;
  rec RECORD;
  v_batch_count int := 0;
BEGIN
  p_err_code := '0';
  p_err_msg := 'Success';

  -- 1) Validate ORDER BY column (whitelist)
  CASE upper(coalesce(p_column_name,''))
    WHEN 'FROM_SERVICE_DATE' THEN v_order_col := 'sort_from_date';
    WHEN 'TO_SERVICE_DATE'   THEN v_order_col := 'sort_to_date';
    WHEN 'BILLED_AMOUNT'     THEN v_order_col := 'sort_billed_amount';
    WHEN 'PAID_AMOUNT'       THEN v_order_col := 'sort_paid_amount';
    WHEN 'TCN'               THEN v_order_col := 'tcn';
    ELSE v_order_col := 'sort_from_date'; -- default safe column
  END CASE;
  v_order_dir := CASE WHEN upper(coalesce(p_order_by,'')) = 'DESC' THEN 'DESC' ELSE 'ASC' END;

  -- 2) Precompute small lookups / aggregates once (msr details)
  -- (Create temp pre-agg for measures to avoid repeated computation)
  DROP TABLE IF EXISTS tmp_msr_agg;
  CREATE TEMP TABLE tmp_msr_agg ON COMMIT PRESERVE ROWS AS
  SELECT
    tcn,
    COUNT(*) AS msr_count,
    LISTAGG(measure_code, ',') AS msr_codes -- for Redshift; in Postgres use string_agg
  FROM udprdsftas.udp_msr_prvdr_tcn_detail
  WHERE schedule_run_sid = p_schedule_run_sid
  GROUP BY tcn;
  -- commit after pre-agg so we don't keep large transaction open
  COMMIT;

  -- 3) Build base result set once into staging table (base_data)
  DROP TABLE IF EXISTS base_data;
  CREATE TEMP TABLE base_data ON COMMIT PRESERVE ROWS AS
  WITH tmp_modes AS (
    SELECT DISTINCT
      l.lkp_value_code AS phar_med,
      lv.lkp_value_code AS entity_type,
      s.scenario_type,
      md.prvdr_bill_type
    FROM udprdsftasext.measure_detail md
    JOIN udprdsftasext.lookup_value l ON l.lkp_value_sid = md.category_lkpid
    JOIN udprdsftasext.scenario_x_measure sxm ON sxm.measure_sid = md.measure_sid
    JOIN udprdsftasext.scenario_detail sd ON sd.scenario_dtl_sid = sxm.scenario_dtl_sid
    JOIN udprdsftasext.lookup_value lv ON lv.lkp_value_sid = sd.entity_lvl_lkpid
    JOIN udprdsftasext.scenario s ON s.scenario_sid = sd.scenario_sid
    WHERE s.scenario_sid = p_scenario_sid
  )
  SELECT
    p_scenario_sid AS scenario_sid,
    p_schedule_run_sid AS schedule_run_sid,
    -- choose fields for final insert; use CASE for M/P differences
    COALESCE(udprdsftas.udp_clm_header.tcn, udprdsftas.udp_rx_clm_header_phrmcy_dtl.tcn) AS tcn,
    COALESCE(udprdsftas.udp_clm_header.dim_mbr_sid, udprdsftas.udp_rx_clm_header_phrmcy_dtl.dim_mbr_sid) AS dim_mbr_sid,
    COALESCE(udprdsftvrtl.udp_member_info.client_mmis_id, udprdsftas.udp_rx_clm_header_phrmcy_dtl.ptnt_idntfr) AS member_id,
    COALESCE(udprdsftvrtl.udp_provider_info.prvdr_mmis_idntfr, udprdsftas.udp_clm_header.blng_national_prvdr_idntfr) AS provider_id,
    -- sort columns used for ordering/pagination
    COALESCE(udprdsftas.udp_clm_header.from_service_date, udprdsftas.udp_rx_clm_header_phrmcy_dtl.service_date) AS sort_from_date,
    COALESCE(udprdsftas.udp_clm_header.to_service_date, udprdsftas.udp_rx_clm_header_phrmcy_dtl.service_date) AS sort_to_date,
    COALESCE(udprdsftas.udp_clm_header.total_billed_amount, udprdsftas.udp_rx_clm_header_phrmcy_dtl.billed_amount) AS sort_billed_amount,
    COALESCE(udprdsftas.udp_clm_header.paid_amount, udprdsftas.udp_rx_clm_header_phrmcy_dtl.paid_amount) AS sort_paid_amount,
    -- join pre-agg msr codes (may be null)
    tmp_msr_agg.msr_codes AS assc_msrs
  FROM tmp_modes m
  LEFT JOIN udprdsftvrtl.udp_member_info ON true -- adapt joins to your real join conditions
  LEFT JOIN udprdsftas.udp_clm_header ON m.phar_med = 'M' AND udprdsftas.udp_clm_header.dim_mbr_sid = udprdsftvrtl.udp_member_info.mbr_sid
  LEFT JOIN udprdsftas.udp_rx_clm_header_phrmcy_dtl ON m.phar_med = 'P' AND udprdsftas.udp_rx_clm_header_phrmcy_dtl.dim_mbr_sid = udprdsftvrtl.udp_member_info.mbr_sid
  LEFT JOIN tmp_msr_agg ON tmp_msr_agg.tcn = COALESCE(udprdsftas.udp_clm_header.tcn, udprdsftas.udp_rx_clm_header_phrmcy_dtl.tcn)
  WHERE
    -- filter by provider param (example logic)
    (COALESCE(udprdsftvrtl.udp_member_info.client_mmis_id, '') = p_prvdr_npi OR COALESCE(udprdsftvrtl.udp_provider_info.prvdr_mmis_idntfr, '') = p_prvdr_npi)
    -- and restrict by schedule run date window (example)
    AND (
      (m.phar_med = 'M' AND udprdsftas.udp_clm_header.adjudication_date BETWEEN (SELECT data_start_date FROM udprdsftas.udp_schedule_run WHERE schedule_run_sid = p_schedule_run_sid)
                                                                     AND (SELECT data_end_date FROM udprdsftas.udp_schedule_run WHERE schedule_run_sid = p_schedule_run_sid))
      OR
      (m.phar_med = 'P' AND udprdsftas.udp_rx_clm_header_phrmcy_dtl.adjudication_date BETWEEN (SELECT data_start_date FROM udprdsftas.udp_schedule_run WHERE schedule_run_sid = p_schedule_run_sid)
                                                                                       AND (SELECT data_end_date FROM udprdsftas.udp_schedule_run WHERE schedule_run_sid = p_schedule_run_sid))
    );

  -- commit the staging creation so heavy work isn't wrapped in transaction
  COMMIT;

  -- 4) Count total rows (for participant count) — do this after base created
  SELECT COUNT(*) INTO v_total_count FROM base_data;
  p_participant_count := v_total_count;

  -- 5) Open cursor over the ordered set (apply pagination if the caller requested specific slice)
  -- We will loop and fetch p_batch_size rows, inserting into final reporting table with commits.
  OPEN cur_ref FOR
    SELECT * FROM base_data
    ORDER BY
      CASE WHEN v_order_col = 'sort_from_date' THEN sort_from_date
           WHEN v_order_col = 'sort_to_date' THEN sort_to_date
           WHEN v_order_col = 'sort_billed_amount' THEN sort_billed_amount
           WHEN v_order_col = 'sort_paid_amount' THEN sort_paid_amount
           ELSE sort_from_date END
    -- direction applied by separate CASE; if DESC then reverse by wrapping
    /* If you want to support p_start_number/p_end_number offset, apply WHERE RN between ... using ROW_NUMBER above */
  ;

  LOOP
    -- fetch in batches
    FETCH cur_ref INTO rec;
    EXIT WHEN NOT FOUND;
    v_batch_count := 1; -- we use a small internal counter for current batch
    -- start a local batch loop to fetch and insert p_batch_size rows
    PERFORM 1; -- no-op; we are already in loop; implement nested loop logic by collecting current row + next N-1 rows
    -- To simplify, we'll use a small temporary array to hold batch rows (pseudocode below).
    -- But PL/pgSQL doesn't allow variable-length typed arrays easily here; instead we do single-row inserts and commit after p_batch_size rows.
    -- Insert the current record:
    INSERT INTO udprdsftas.udp_temp_rpt_scnr_process /* adjust columns */ (
        scenario_sid, schedule_run_sid, tcn, dim_mbr_sid, member_id, provider_id,
        sort_from_date, sort_to_date, sort_billed_amount, sort_paid_amount, assc_msrs, last_insert_dt
    ) VALUES (
      rec.scenario_sid, rec.schedule_run_sid, rec.tcn, rec.dim_mbr_sid, rec.member_id, rec.provider_id,
      rec.sort_from_date, rec.sort_to_date, rec.sort_billed_amount, rec.sort_paid_amount, rec.assc_msrs, CURRENT_TIMESTAMP
    );

    v_rows_processed := v_rows_processed + 1;

    -- fetch and insert remaining rows for this batch
    FOR i IN 2..p_batch_size LOOP
      FETCH cur_ref INTO rec;
      EXIT WHEN NOT FOUND;
      INSERT INTO udprdsftas.udp_temp_rpt_scnr_process (
        scenario_sid, schedule_run_sid, tcn, dim_mbr_sid, member_id, provider_id,
        sort_from_date, sort_to_date, sort_billed_amount, sort_paid_amount, assc_msrs, last_insert_dt
      ) VALUES (
        rec.scenario_sid, rec.schedule_run_sid, rec.tcn, rec.dim_mbr_sid, rec.member_id, rec.provider_id,
        rec.sort_from_date, rec.sort_to_date, rec.sort_billed_amount, rec.sort_paid_amount, rec.assc_msrs, CURRENT_TIMESTAMP
      );
      v_rows_processed := v_rows_processed + 1;
    END LOOP;

    -- After batch inserted, commit so progress is persisted
    COMMIT;
  END LOOP;

  CLOSE cur_ref;

  p_result_set := 'udp_temp_rpt_scnr_process';
  -- leave p_err_code and msg as success
EXCEPTION WHEN OTHERS THEN
  -- capture error and return
  p_err_code := SQLSTATE;
  p_err_msg := SQLERRM;
  -- Do not rollback the whole run — that would revert prior batch commits; optionally you may ROLLBACK here if you want to revert partial work
  RAISE NOTICE 'Procedure failed after processing % rows: % / %', v_rows_processed, p_err_code, p_err_msg;
END;
$$;
