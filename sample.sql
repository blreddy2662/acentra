CREATE OR REPLACE PROCEDURE udprdsftas.udp_pr_rpt_claim_detail_non_atomic_redshift(
  IN p_scenario_sid numeric,
  IN p_prvdr_npi varchar,
  IN p_schedule_run_sid numeric,
  IN p_debug varchar,
  IN p_start_number numeric,
  IN p_end_number numeric,
  IN p_column_name varchar,
  IN p_order_by varchar,
  IN p_batch_size integer,            -- no DEFAULT in signature
  INOUT p_participant_count numeric,
  INOUT p_result_set varchar,
  INOUT p_err_code varchar,
  INOUT p_err_msg varchar)
LANGUAGE plpgsql
NONATOMIC
AS $$
DECLARE
  v_order_col text;
  v_order_dir text;
  v_rows_processed bigint := 0;
  v_batch_rows int := 0;
  v_batch_size_local int := 1000;
  rec RECORD;
  cur_ref REFCURSOR;          -- Redshift supports refcursor style
BEGIN
  p_err_code := '0';
  p_err_msg := 'Success';

  -- default batch size if caller passes NULL or <= 0
  IF p_batch_size IS NULL OR p_batch_size <= 0 THEN
    v_batch_size_local := 1000;
  ELSE
    v_batch_size_local := p_batch_size;
  END IF;

  -- whitelist/order column mapping (safe mapping)
  CASE upper(coalesce(p_column_name,''))
    WHEN 'FROM_SERVICE_DATE' THEN v_order_col := 'sort_from_date';
    WHEN 'TO_SERVICE_DATE'   THEN v_order_col := 'sort_to_date';
    WHEN 'BILLED_AMOUNT'     THEN v_order_col := 'sort_billed_amount';
    WHEN 'PAID_AMOUNT'       THEN v_order_col := 'sort_paid_amount';
    WHEN 'TCN'               THEN v_order_col := 'tcn';
    ELSE v_order_col := 'sort_from_date';
  END CASE;
  v_order_dir := CASE WHEN upper(coalesce(p_order_by,'')) = 'DESC' THEN 'DESC' ELSE 'ASC' END;

  -- 1) Pre-aggregate msr details (LISTAGG in Redshift)
  DROP TABLE IF EXISTS tmp_msr_agg;
  CREATE TEMP TABLE tmp_msr_agg AS
  SELECT
    tcn,
    COUNT(*) AS msr_count,
    LISTAGG(measure_code, ',') WITHIN GROUP (ORDER BY measure_code) AS msr_codes
  FROM udprdsftas.udp_msr_prvdr_tcn_detail
  WHERE schedule_run_sid = p_schedule_run_sid
  GROUP BY tcn;
  -- commit to persist heavy work and release locks
  COMMIT;

  -- 2) Build base_data staging (single set-based query)
  DROP TABLE IF EXISTS base_data;
  CREATE TEMP TABLE base_data AS
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
    COALESCE(ch.tcn, rx.tcn) AS tcn,
    COALESCE(ch.dim_mbr_sid, rx.dim_mbr_sid) AS dim_mbr_sid,
    COALESCE(mi.client_mmis_id, rx.ptnt_idntfr) AS member_id,
    COALESCE(pi.prvdr_mmis_idntfr, ch.blng_national_prvdr_idntfr) AS provider_id,
    COALESCE(ch.from_service_date, rx.service_date) AS sort_from_date,
    COALESCE(ch.to_service_date, rx.service_date) AS sort_to_date,
    COALESCE(ch.total_billed_amount, rx.billed_amount) AS sort_billed_amount,
    COALESCE(ch.paid_amount, rx.paid_amount) AS sort_paid_amount,
    tma.msr_codes AS assc_msrs
  FROM (SELECT * FROM tmp_modes) m
  LEFT JOIN udprdsftvrtl.udp_member_info mi ON TRUE  -- adapt real join conditions here
  LEFT JOIN udprdsftas.udp_clm_header ch
    ON m.phar_med = 'M' AND ch.dim_mbr_sid = mi.mbr_sid
  LEFT JOIN udprdsftas.udp_rx_clm_header_phrmcy_dtl rx
    ON m.phar_med = 'P' AND rx.dim_mbr_sid = mi.mbr_sid
  LEFT JOIN tmp_msr_agg tma
    ON tma.tcn = COALESCE(ch.tcn, rx.tcn)
  LEFT JOIN udprdsftvrtl.udp_provider_info pi ON TRUE  -- adapt as needed
  WHERE
    (COALESCE(mi.client_mmis_id, '') = p_prvdr_npi OR COALESCE(pi.prvdr_mmis_idntfr,'') = p_prvdr_npi)
    AND (
      (m.phar_med = 'M' AND ch.adjudication_date BETWEEN (SELECT data_start_date FROM udprdsftas.udp_schedule_run WHERE schedule_run_sid = p_schedule_run_sid) AND (SELECT data_end_date FROM udprdsftas.udp_schedule_run WHERE schedule_run_sid = p_schedule_run_sid))
      OR
      (m.phar_med = 'P' AND rx.adjudication_date BETWEEN (SELECT data_start_date FROM udprdsftas.udp_schedule_run WHERE schedule_run_sid = p_schedule_run_sid) AND (SELECT data_end_date FROM udprdsftas.udp_schedule_run WHERE schedule_run_sid = p_schedule_run_sid))
    );

  COMMIT;  -- persist staging

  -- 3) Participant count
  SELECT COUNT(*) INTO p_participant_count FROM base_data;

  -- 4) Open cursor and iterate, inserting in batches with commits
  OPEN cur_ref FOR
    SELECT * FROM base_data
    ORDER BY
      CASE WHEN v_order_col = 'sort_from_date' THEN sort_from_date
           WHEN v_order_col = 'sort_to_date' THEN sort_to_date
           WHEN v_order_col = 'sort_billed_amount' THEN sort_billed_amount
           WHEN v_order_col = 'sort_paid_amount' THEN sort_paid_amount
           ELSE sort_from_date END
    -- Note: Redshift supports simple ORDER BY; if DESC is required, you can flip sign or use dynamic SQL pre-built whitelisted (avoid injection)
  ;

  LOOP
    FETCH cur_ref INTO rec;
    EXIT WHEN NOT FOUND;

    -- insert row into result table
    INSERT INTO udprdsftas.udp_temp_rpt_scnr_process (
      scenario_sid, schedule_run_sid, tcn, dim_mbr_sid, member_id, provider_id,
      sort_from_date, sort_to_date, sort_billed_amount, sort_paid_amount, assc_msrs, last_insert_dt
    ) VALUES (
      rec.scenario_sid, rec.schedule_run_sid, rec.tcn, rec.dim_mbr_sid, rec.member_id, rec.provider_id,
      rec.sort_from_date, rec.sort_to_date, rec.sort_billed_amount, rec.sort_paid_amount, rec.assc_msrs, SYSDATE
    );

    v_rows_processed := v_rows_processed + 1;
    v_batch_rows := v_batch_rows + 1;

    IF v_batch_rows >= v_batch_size_local THEN
      COMMIT;
      v_batch_rows := 0;
    END IF;
  END LOOP;

  -- final commit for leftover rows
  IF v_batch_rows > 0 THEN
    COMMIT;
  END IF;

  CLOSE cur_ref;

  p_result_set := 'udp_temp_rpt_scnr_process';
EXCEPTION WHEN OTHERS THEN
  p_err_code := SQLSTATE;
  p_err_msg := SQLERRM;
  RAISE NOTICE 'Procedure failed after % rows: % - %', v_rows_processed, p_err_code, p_err_msg;
  -- Do not ROLLBACK here to preserve prior committed batches (non-atomic mode).
END;
$$;
