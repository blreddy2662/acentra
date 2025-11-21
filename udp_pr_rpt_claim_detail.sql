-- DROP PROCEDURE udprdsftas.udp_pr_rpt_claim_detail(in numeric, in varchar, in numeric, in varchar, in numeric, in numeric, in varchar, in varchar, inout numeric, inout varchar, inout varchar, inout varchar);

CREATE OR REPLACE PROCEDURE udprdsftas.udp_pr_rpt_claim_detail(in p_scenario_sid numeric, in p_prvdr_npi varchar, in p_schedule_run_sid numeric, in p_debug varchar, in p_start_number numeric, in p_end_number numeric, in p_column_name varchar, in p_order_by varchar, inout p_participant_count numeric, inout p_result_set varchar, inout p_err_code varchar, inout p_err_msg varchar)
	LANGUAGE plpgsql
AS $$
	
	
	
	
/* Added as Base Product Code Fix on 7/31/2019 by Sriram. */
/* Added as Base Product Code Fix on 7/31/2019 by Sriram. */
/* Added as Base Product Code Fix on 7/31/2019 by Sriram. */
/* Added as Base Product Code Fix on 7/31/2019 by Sriram. */
/* Added as Base Product Code Fix on 7/31/2019 by Sriram. */

/*
*******************************************************************************************************************

   NAME      : udp_pr_rpt_claim_detail
   PURPOSE   : This procedure will give the claim details.in the 2nd drill down from the scenario run page.

   REVISIONS :
   Ver        Date        Author            Description
   ---------  ----------  -------------     -------------------------
   1.0        28/10/2014  Mangai           Created this procedure.
   1.1        07/31/2019  Sriram           Included Participant Count, Sorting of Level 3 Claim Details.
   2.1        12/12/2019  Karthik, Sriram  Fixed Sorting Issue.
   2.2        08/09/2020  Unnamalai        Added a column to notify case initiation status at level 3
   -----------------------------------Retrofit Changes--------------------------------------------------------------------
   2.3        06/14/2021  Unnamalai        Added logic to handle pharmacy and medical changes
   3.0        26-AUG-2021 Joyce            Modified Member_ID from SSN to MMIS_IDTFR and Provider ID from national_provider_identifier to Provider_ID.
   3.1        26-AUG-2021 Joyce            Commented to allow the Non-Contributing Claims as well in the results.
   4.0        18-NOV-2021 Joyce            Modified TCN Grid details based on relevant Claim level display.
   5.0        12/14/2021  Sriram           Modified for Case Management
   6.0        12/21/2021  Sriram           Modified for Member Restriction Scenario
   7.0        01/17/2022  Sriram           Modified Entire Procedure to Dynamic Procedure for Level 3 Changes.
   7.1        01/22/2022  Karthik          Included for Level 3 changes
   -----------------------------------Retrofit Changes--------------------------------------------------------------------
   8.0        03/03/2022  Sriram           Added for Utah Base Product Code
   PARAMETERS:
   INPUT   : p_scenario_sid          IN numeric,
             p_prvdr_npi             IN varchar,
			 p_schedule_run_sid      IN numeric,
             p_debug                 IN varchar  ,
             p_start_number          IN numeric,
             p_end_number            IN numeric,
             p_column_name           IN varchar,
             p_order_by              IN varchar,
             p_user                  IN numeric,
   OUTPUT  : p_participant_count    IN OUT numeric,
             p_result_set           IN OUT varchar,
             p_err_code             IN OUT varchar,
             p_err_msg              IN OUT varchar

   To execute it in standalone
   call udprdsftas.udp_pr_rpt_claim_detail(1003789,'7062053',107153,'N',0,100,'FROM_SERVICE_DATE','DESC',null,'p_result_set_temptable',null,null);
   select * from p_result_set_temptable;


**********************************************************************************************************************
*/
DECLARE
    v_phar_med_sql VARCHAR(max);
    v_scnr_type VARCHAR(5);
    /* SURS / FADS */
    v_level NUMERIC;
    /* {2:'Level 2',3:'Level 3',1:'Worklist'} */
    v_cnt NUMERIC DEFAULT 0;
    v_entity_lvl_code VARCHAR(3);
    /* MB/PR */
    v_columns VARCHAR(max);
    v_joins VARCHAR(max);
    v_where_cndtn VARCHAR(max) default '';
    v_sql VARCHAR(max) default '';
    v_result_set refcursor;
    /* v_tcn_query                CLOB; */
    v_bm_sql VARCHAR(max);
    v_tcn1_sql VARCHAR(max);
    v_prvdr_mbr VARCHAR(3);
    v_all_measure VARCHAR(max);
    v_sql_offset VARCHAR(max);
    v_step_no NUMERIC;
    v_replace_col VARCHAR(30000);
    v_pharmacy_where_cndtn VARCHAR(max);
    v_medical_where_cndtn VARCHAR(max);
    v_pharm_sql_1 VARCHAR(max);
    v_pharm_sql VARCHAR(max);
    v_med_sql_1 VARCHAR(max);
    v_med_sql VARCHAR(max);
    v_cnt1 NUMERIC;
    v_cnt2 NUMERIC;
    v_sql_1 VARCHAR(max);
    v_lkp_code VARCHAR(2);
    v_contributing_clms_qry VARCHAR(max);
    v_start_number NUMERIC;
    v_end_number NUMERIC;
    v_scenario_run_sid NUMERIC;
    i RECORD;
   v_participant_count numeric;
   
    v_loop_rec_cnt NUMERIC default 0;
    v_no_elements	NUMERIC default 0;
BEGIN
    p_err_code := 0;
    p_err_msg := 'Success';
    v_step_no := 10;
    /* --v4.0 Added for MSR_TCN Table logic starts */
    /* SELECT lkp.lkp_value_code */
    /* INTO v_lkp_code */
    /* FROM scenario_detail sd, */
    /* lookup_value lkp */
    /* WHERE sd.entity_lvl_lkpid = lkp.lkp_value_sid */
    /* AND sd.scenario_sid = p_scenario_sid */
    /* AND lkp.lkp_domain_cid = 3; */
    /* */
    /* IF v_lkp_code = 'PR' */
    /* THEN */
    /* DELETE FROM msr_prvdr_tcn_detail */
    /* WHERE */
    /* dim_prvdr_sid IN ( */
    /* SELECT */
    /* dim_prvdr_sid */
    /* FROM */
    /* udprdsftvrtl.udp_provider_info */
    /* WHERE */
    /* provider_id = p_prvdr_npi */
    /* ) */
    /* AND measure_sid IN ( */
    /* SELECT */
    /* sxm.measure_sid */
    /* FROM */
    /* scenario_x_measure   sxm */
    /* INNER JOIN scenario_detail      sd ON sxm.scenario_dtl_sid = sd.scenario_dtl_sid */
    /* WHERE */
    /* sd.scenario_sid = p_scenario_sid */
    /* ); */
    /* */
    /* MERGE	/*+ PARALLEL(a, 10) */ --INTO msr_prvdr_tcn_detail d */
    /* USING ( SELECT DISTINCT */
    /* mdd.measure_dtl_sid, */
    /* md.measure_sid, */
    /* mp.tcn, */
    /* mp.dim_prvdr_sid, */
    /* m.code */
    /* FROM */
    /* measure_derived      mdd */
    /* INNER JOIN msr_prvdr_tcn        mp ON ( mp.measure_sid = mdd.measure_1_sid */
    /* OR mp.measure_sid = mdd.measure_2_sid ) */
    /* INNER JOIN measure_detail       md ON md.measure_dtl_sid = mdd.measure_dtl_sid */
    /* INNER JOIN measure              m ON m.measure_sid = md.measure_sid */
    /* INNER JOIN scenario_x_measure   sxm ON sxm.measure_sid = md.measure_sid */
    /* INNER JOIN scenario_detail      sd ON sxm.scenario_dtl_sid = sd.scenario_dtl_sid */
    /* INNER JOIN udprdsftvrtl.udp_provider_info      ddp ON mp.dim_prvdr_sid = ddp.dim_prvdr_sid */
    /* WHERE */
    /* sd.scenario_sid = p_scenario_sid */
    /* AND ddp.provider_id = p_prvdr_npi */
    /* UNION */
    /* SELECT DISTINCT */
    /* md.measure_dtl_sid, */
    /* md.measure_sid, */
    /* mp.tcn, */
    /* mp.dim_prvdr_sid, */
    /* m.code */
    /* FROM */
    /* msr_prvdr_tcn        mp */
    /* INNER JOIN measure_detail       md ON md.measure_sid = mp.measure_sid */
    /* INNER JOIN measure              m ON m.measure_sid = md.measure_sid */
    /* INNER JOIN scenario_x_measure   sxm ON sxm.measure_sid = md.measure_sid */
    /* INNER JOIN scenario_detail      sd ON sxm.scenario_dtl_sid = sd.scenario_dtl_sid */
    /* INNER JOIN udprdsftvrtl.udp_provider_info      ddp ON mp.dim_prvdr_sid = ddp.dim_prvdr_sid */
    /* WHERE */
    /* sd.scenario_sid = p_scenario_sid */
    /* AND ddp.provider_id = p_prvdr_npi */
    /* ) */
    /* s ON ( d.measure_dtl_sid = d.measure_dtl_sid ) */
    /* WHEN MATCHED THEN UPDATE */
    /* SET d.dim_prvdr_sid = s.dim_prvdr_sid, */
    /* d.measure_sid = s.measure_sid, */
    /* d.tcn = s.tcn */
    /* WHEN NOT MATCHED THEN */
    /* INSERT ( */
    /* d.measure_dtl_sid, */
    /* d.measure_sid, */
    /* d.tcn, */
    /* d.dim_prvdr_sid, */
    /* d.code, */
    /* d.created_by, */
    /* d.created_date, */
    /* d.modified_by, */
    /* d.modified_date ) */
    /* VALUES */
    /* ( s.measure_dtl_sid, */
    /* s.measure_sid, */
    /* s.tcn, */
    /* s.dim_prvdr_sid, */
    /* s.code, */
    /* 1, */
    /* SYSDATE, */
    /* 1, */
    /* SYSDATE ); */
    /* */
    /* ELSE  --For Member */
    /* DELETE FROM msr_mbr_tcn_detail */
    /* WHERE */
    /* dim_mbr_sid IN ( */
    /* SELECT */
    /* dim_mbr_sid */
    /* FROM */
    /* dw_dim_member */
    /* WHERE */
    /* mmis_idntfr = p_prvdr_npi */
    /* ) */
    /* AND measure_sid IN ( */
    /* SELECT */
    /* sxm.measure_sid */
    /* FROM */
    /* scenario_x_measure   sxm */
    /* INNER JOIN scenario_detail      sd ON sxm.scenario_dtl_sid = sd.scenario_dtl_sid */
    /* WHERE */
    /* sd.scenario_sid = p_scenario_sid */
    /* ); */
    /* */
    /* MERGE	/*+ PARALLEL(a, 10) */-- INTO msr_mbr_tcn_detail d */
    /* USING ( SELECT DISTINCT */
    /* mdd.measure_dtl_sid, */
    /* md.measure_sid, */
    /* mp.tcn, */
    /* mp.dim_mbr_sid, */
    /* m.code */
    /* FROM */
    /* measure_derived      mdd */
    /* INNER JOIN msr_mbr_tcn        mp ON ( mp.measure_sid = mdd.measure_1_sid */
    /* OR mp.measure_sid = mdd.measure_2_sid ) */
    /* INNER JOIN measure_detail       md ON md.measure_dtl_sid = mdd.measure_dtl_sid */
    /* INNER JOIN measure              m ON m.measure_sid = md.measure_sid */
    /* INNER JOIN scenario_x_measure   sxm ON sxm.measure_sid = md.measure_sid */
    /* INNER JOIN scenario_detail      sd ON sxm.scenario_dtl_sid = sd.scenario_dtl_sid */
    /* INNER JOIN dw_dim_member      ddp ON mp.dim_mbr_sid = ddp.dim_mbr_sid */
    /* WHERE */
    /* sd.scenario_sid = p_scenario_sid */
    /* AND ddp.mmis_idntfr = p_prvdr_npi */
    /* UNION */
    /* SELECT DISTINCT */
    /* md.measure_dtl_sid, */
    /* md.measure_sid, */
    /* mp.tcn, */
    /* mp.dim_mbr_sid, */
    /* m.code */
    /* FROM */
    /* msr_mbr_tcn        mp */
    /* INNER JOIN measure_detail       md ON md.measure_sid = mp.measure_sid */
    /* INNER JOIN measure              m ON m.measure_sid = md.measure_sid */
    /* INNER JOIN scenario_x_measure   sxm ON sxm.measure_sid = md.measure_sid */
    /* INNER JOIN scenario_detail      sd ON sxm.scenario_dtl_sid = sd.scenario_dtl_sid */
    /* INNER JOIN dw_dim_member      ddp ON mp.dim_mbr_sid = ddp.dim_mbr_sid */
    /* WHERE */
    /* sd.scenario_sid = p_scenario_sid */
    /* AND ddp.mmis_idntfr = p_prvdr_npi */
    /* ) */
    /* s ON ( d.measure_dtl_sid = d.measure_dtl_sid ) */
    /* WHEN MATCHED THEN UPDATE */
    /* SET d.dim_mbr_sid = s.dim_mbr_sid, */
    /* d.measure_sid = s.measure_sid, */
    /* d.tcn = s.tcn */
    /* WHEN NOT MATCHED THEN */
    /* INSERT ( */
    /* d.measure_dtl_sid, */
    /* d.measure_sid, */
    /* d.tcn, */
    /* d.dim_mbr_sid, */
    /* d.code, */
    /* d.created_by, */
    /* d.created_date, */
    /* d.modified_by, */
    /* d.modified_date ) */
    /* VALUES */
    /* ( s.measure_dtl_sid, */
    /* s.measure_sid, */
    /* s.tcn, */
    /* s.dim_mbr_sid, */
    /* s.code, */
    /* 1, */
    /* SYSDATE, */
    /* 1, */
    /* SYSDATE ); */
    /* */
    /* END IF; */
    /* */
    /* COMMIT; */
    /* Basic Measure SQL WHERE Conduition Append Starts */
    
    /*
    FOR i IN (
           SELECT measure_type,
                  sql_where
            FROM
           (
            SELECT
               DISTINCT ' OR ('||TO_CHAR(mq.sql_only_where)||') ' sql_where,
               ROW_numeric() OVER(PARTITION BY TO_CHAR(mq.sql_only_where) ORDER BY NULL) rn,
               CASE WHEN UPPER(' OR ('||TO_CHAR(mq.sql_only_where)||') ') LIKE UPPER('%DW_RX%')
                    THEN 'P'
                    ELSE 'M'
                END measure_type
            FROM
                measure_detail md
                INNER JOIN lookup_value l ON l.lkp_value_sid = md.category_lkpid
                INNER JOIN lookup_value msr_typ
                        ON (msr_typ.lkp_value_sid  = md.type_lkpid
                        AND  msr_typ.lkp_value_code = 'BM')
    --            INNER JOIN scenario_x_measure sxm ON sxm.measure_sid = md.measure_sid
                INNER JOIN
                        (SELECT mr.measure_1_sid measure_sid, sxm.scenario_dtl_sid FROM measure_detail md	--(v1.4) Altered procedure for Adding Custom Date Range (product enhancement) starts
                                                INNER JOIN measure_derived mr ON mr.measure_dtl_sid = md.measure_dtl_sid
                                                INNER JOIN scenario_x_measure sxm ON sxm.measure_sid = md.measure_sid
                                                  UNION
                                                SELECT mr.measure_2_sid, sxm.scenario_dtl_sid FROM measure_detail md
                                                INNER JOIN measure_derived mr ON mr.measure_dtl_sid = md.measure_dtl_sid
                                                INNER JOIN scenario_x_measure sxm ON sxm.measure_sid = md.measure_sid
                                                  UNION
                                                SELECT md.measure_sid, sxm.scenario_dtl_sid FROM measure_detail md
                                                INNER JOIN scenario_x_measure sxm ON sxm.measure_sid = md.measure_sid) sm
                            ON (md.measure_sid = sm.measure_sid)
                INNER JOIN scenario_detail sd ON sd.scenario_dtl_sid = sm.scenario_dtl_sid
                INNER JOIN measure_sql mq ON mq.measure_sid = md.measure_sid
                INNER JOIN lookup_value lv ON (lv.lkp_value_sid = sd.entity_lvl_lkpid)
                INNER JOIN scenario s ON s.scenario_sid = sd.scenario_sid
            WHERE
                s.scenario_sid = p_scenario_sid)
           WHERE rn = 1)
        LOOP
             --v_tcn_sql := i.sql_where||' '||v_tcn_sql;
             IF i.measure_type = 'P' --For Pharmacy
             THEN
                 v_pharmacy_where_cndtn := i.sql_where||' '||v_pharmacy_where_cndtn;
             ELSE                    --For Medical
                 v_medical_where_cndtn := i.sql_where||' '||v_medical_where_cndtn;
             END IF;
        END LOOP;
    
          v_pharm_sql_1 := ' AND ('||v_pharmacy_where_cndtn||')';
          v_pharm_sql := REPLACE(v_pharm_sql_1,' AND ( OR (','AND ( (');
    
          v_med_sql_1 := ' AND ('||v_medical_where_cndtn||')';
          v_med_sql := REPLACE(v_med_sql_1,' AND ( OR (','AND ( (');
    
    --Basic Measure SQL WHERE Conduition Append Ends
    */
    /* --added on 23-Aug-2022 for contributing bills display based on runsid starts */
    /* SELECT count(*) */
    /* INTO v_cnt FROM msr_prvdr_tcn_detail */
    /* WHERE scenario_sid = p_scenario_sid */
    /* AND schedule_run_sid = p_schedule_run_sid; */
    /* */
    /* IF v_cnt>0 THEN */
    /* v_scenario_run_sid := p_schedule_run_sid; */
    /* ELSE */
    /* SELECT max(schedule_run_sid) */
    /* INTO v_scenario_run_sid */
    /* FROM msr_prvdr_tcn_detail */
    /* WHERE scenario_sid = p_scenario_sid; */
    /* END IF; */
    /* --added on 23-Aug-2022 for contributing bills display based on runsid ends */
    v_scenario_run_sid := p_schedule_run_sid;
    v_step_no := 20;
    /* -dbms_output.put_line('hello'); */

    drop table if exists temp_i;
  	create temporary table temp_i as 
  	SELECT
        row_number() OVER () AS cnt, lkp_value_code AS phar_med, scenario_type, entity_type, prvdr_bill_type, count(lkp_value_code) OVER () AS max_cnt
        FROM (SELECT DISTINCT
            l.lkp_value_code AS lkp_value_code, lv.lkp_value_code AS entity_type, s.scenario_type, md.prvdr_bill_type
            FROM udprdsftasext.measure_detail AS md
            INNER JOIN udprdsftasext.lookup_value AS l
                ON l.lkp_value_sid = md.category_lkpid
            INNER JOIN udprdsftasext.scenario_x_measure AS sxm
                ON sxm.measure_sid = md.measure_sid
            INNER JOIN udprdsftasext.scenario_detail AS sd
                ON sd.scenario_dtl_sid = sxm.scenario_dtl_sid
            INNER JOIN udprdsftasext.lookup_value AS lv
                ON (lv.lkp_value_sid = sd.entity_lvl_lkpid)
            INNER JOIN udprdsftasext.scenario AS s
                ON s.scenario_sid = sd.scenario_sid
            WHERE s.scenario_sid = p_scenario_sid);
           
       select count(1) into v_no_elements from temp_i;
      
      loop
	     v_loop_rec_cnt := v_loop_rec_cnt + 1;
         exit WHEN v_loop_rec_cnt > v_no_elements;
          
         select * into i from temp_i where cnt = v_loop_rec_cnt;
        v_prvdr_mbr := i.entity_type;
        v_cnt := i.max_cnt;
        /* Column Configuration Starts */
        v_columns := 'SELECT  DISTINCT ' || p_scenario_sid || ' scenario_sid,' || p_schedule_run_sid || ' schedule_run_sid,' ||
						CASE
							WHEN i.phar_med = 'M' THEN 'NVL((udprdsftas.udp_clm_header.blng_national_prvdr_idntfr)::varchar,'' '') "provider_npi",
												NVL((udprdsftas.udp_clm_header.blng_prvdr_lctn_identifier)::varchar,'' '') "provider_id",
												udprdsftvrtl.udp_member_info.client_mmis_id "member_id",
												udprdsftas.udp_clm_header.tcn "tcn",'
							WHEN i.phar_med = 'P' THEN 'NVL((udprdsftas.udp_rx_clm_header_phrmcy_dtl.prvdr_idntfr),'' '')::varchar "provider_npi",
												NVL((udprdsftvrtl.udp_provider_info.prvdr_mmis_idntfr)::varchar,'' '') "provider_id",
												udprdsftas.udp_rx_clm_header_phrmcy_dtl.ptnt_idntfr "member_id",
												udprdsftas.udp_rx_clm_header_phrmcy_dtl.tcn "tcn",'
						END ||
						CASE
							WHEN i.phar_med = 'M' THEN 'TO_CHAR(udprdsftas.udp_clm_header.from_service_date,''MM/DD/YYYY'') "from_service_date",
												TO_CHAR(udprdsftas.udp_clm_header.to_service_date,''MM/DD/YYYY'') "to_service_date",
												NVL(TO_CHAR(udprdsftas.udp_clm_header.total_billed_amount,''999999.99''),''0.00'') "billed_amount",
												NVL(TO_CHAR(udprdsftas.udp_clm_header.paid_amount,''999999.99''),''0.00'') "paid_amount",
												udprdsftas.udp_clm_header.patient_first_name||'' ''||udprdsftas.udp_clm_header.patient_last_name "member_name",
												udprdsftas.udp_clm_header.blng_prvdr_first_name||'' ''||udprdsftas.udp_clm_header.blng_prvdr_last_name "provider_name",
												udprdsftvrtl.udp_d_diagnosis.diagnosis_code||'' - ''||udprdsftvrtl.udp_d_diagnosis.diag_short_desc DC,
												udprdsftas.udp_clm_header.total_billed_amount sort_billed_amount,
												udprdsftas.udp_clm_header.paid_amount sort_paid_amount,
												udprdsftas.udp_clm_header.from_service_date sort_from_date,
												udprdsftas.udp_clm_header.to_service_date sort_to_date,'
							WHEN i.phar_med = 'P' THEN 'TO_CHAR(udprdsftas.udp_rx_clm_header_phrmcy_dtl.service_date,''MM/DD/YYYY'') "from_service_date",
												TO_CHAR(udprdsftas.udp_rx_clm_header_phrmcy_dtl.service_date,''MM/DD/YYYY'') "to_service_date",
												NVL(TO_CHAR(udprdsftas.udp_rx_clm_header_phrmcy_dtl.invoiced_bill_amt,''999999.99''),''0.00'') "billed_amount",
												NVL(TO_CHAR(udprdsftas.udp_rx_clm_header_phrmcy_dtl.total_paid_all_src_amt,''999999.99''),''0.00'') "paid_amount",
												udprdsftas.udp_rx_clm_header_phrmcy_dtl.pharmacy_name "provider_name",
												udprdsftas.udp_rx_clm_header_phrmcy_dtl.ptnt_first_name ||'' ''||udprdsftas.udp_rx_clm_header_phrmcy_dtl.ptnt_last_name "member_name",
												udprdsftas.udp_rx_clm_hdr_phrmcy_x_dgns.diagnosis_code DC,
												udprdsftas.udp_rx_clm_header_phrmcy_dtl.INVOICED_BILL_AMT sort_billed_amount,
												udprdsftas.udp_rx_clm_header_phrmcy_dtl.TOTAL_PAID_ALL_SRC_AMT sort_paid_amount,
												udprdsftas.udp_rx_clm_header_phrmcy_dtl.service_date sort_from_date,
												udprdsftas.udp_rx_clm_header_phrmcy_dtl.service_date sort_to_date,'
						END || 'CURRENT_DATE last_extract_date,
                                ''Y'' status,' || p_prvdr_npi ||
        /* Included for Level 3 changes */
        
        /* Added for Utah Base Product Code Starts */
								' participant_id , a.measure_sid,
                                  codeagg ';
        /* Added for Utah Base Product Code Ends */
        /* Column Configuration Ends */
        /* JOIN Configuration Starts */
        v_joins := 	CASE
						WHEN i.phar_med = 'M' THEN 'FROM udprdsftas.udp_clm_header
										INNER JOIN udprdsftas.udp_clm_line
												ON (udprdsftas.udp_clm_line.claim_header_sid = udprdsftas.udp_clm_header.claim_header_sid
												) '
						WHEN i.phar_med = 'P' THEN 'FROM udprdsftas.udp_rx_clm_header_phrmcy_dtl
										INNER JOIN udprdsftas.udp_rx_clm_line_phrmcy_dtl
													ON (udprdsftas.udp_rx_clm_header_phrmcy_dtl.rx_claim_header_sid = udprdsftas.udp_rx_clm_line_phrmcy_dtl.rx_claim_header_sid
													) '
					END ||
					CASE
						WHEN i.prvdr_bill_type IN ('BL', 'MB') AND i.phar_med = 'M' THEN ' INNER JOIN udprdsftvrtl.udp_provider_info
										ON ( udprdsftas.udp_clm_header.blng_prvdr_lctn_identifier = udprdsftvrtl.udp_provider_info.prvdr_mmis_idntfr
										) '
						WHEN i.prvdr_bill_type IN ('BL', 'MB') AND i.phar_med = 'P' THEN ' INNER JOIN udprdsftvrtl.udp_provider_info
										ON ( udprdsftas.udp_rx_clm_header_phrmcy_dtl.dim_prvdr_sid = udprdsftvrtl.udp_provider_info.prvdr_sid
										) '
						WHEN i.prvdr_bill_type IN ('SE') AND i.phar_med = 'M' THEN 'INNER JOIN udprdsftvrtl.udp_provider_info
										ON (udprdsftvrtl.udp_provider_info.prvdr_mmis_idntfr = NVL(udprdsftas.udp_clm_line.SRVCNG_PRVDR_LCTN_IDENTIFIER,NVL(udprdsftas.udp_clm_header.SRVCNG_PRVDR_LCTN_IDENTIFIER,udprdsftas.udp_clm_header.BLNG_PRVDR_LCTN_IDENTIFIER))) '
						WHEN i.prvdr_bill_type = ('OR') AND i.phar_med = 'M' THEN 'INNER JOIN udprdsftvrtl.udp_clm_ln_x_prvdr_lctn 
												ON (udprdsftas.udp_clm_line.CLAIM_LINE_SID = udprdsftvrtl.udp_clm_ln_x_prvdr_lctn.CLAIM_LINE_SID AND CLM_PRVDR_TYPE_LKPCD = ''OR'') 
										INNER JOIN udprdsftvrtl.udp_provider_info 
												ON (udprdsftvrtl.udp_provider_info.NATIONAL_PROVIDER_IDENTIFIER = udprdsftvrtl.udp_clm_ln_x_prvdr_lctn.PRVDR_LCTN_IDENTIFIER) '
						WHEN i.prvdr_bill_type = ('RF') AND i.phar_med = 'M' THEN 'INNER JOIN udprdsftvrtl.udp_clm_ln_x_prvdr_lctn
												ON (udprdsftas.udp_clm_line.CLAIM_LINE_SID = udprdsftvrtl.udp_clm_ln_x_prvdr_lctn.CLAIM_LINE_SID AND CLM_PRVDR_TYPE_LKPCD = ''RF'')
										INNER JOIN udprdsftvrtl.udp_clm_hdr_x_prvdr_lctn 
												ON ( udprdsftas.udp_clm_header.CLAIM_HEADER_SID = udprdsftvrtl.udp_clm_hdr_x_prvdr_lctn.CLAIM_HEADER_SID) 
										INNER JOIN udprdsftvrtl.udp_provider_info 
												ON (udprdsftvrtl.udp_provider_info.NATIONAL_PROVIDER_IDENTIFIER = NVL(udprdsftvrtl.udp_clm_ln_x_prvdr_lctn.PRVDR_LCTN_IDENTIFIER,udprdsftvrtl.udp_clm_hdr_x_prvdr_lctn.PRVDR_LCTN_IDENTIFIER)'
					END ||
					CASE
						WHEN i.phar_med = 'M' THEN ' LEFT JOIN udprdsftvrtl.udp_d_diagnosis
												ON (udprdsftvrtl.udp_d_diagnosis.diagnosis_iid = udprdsftas.udp_clm_header.primary_diagnosis_iid) '
						WHEN i.phar_med = 'P' THEN 'LEFT OUTER JOIN udprdsftas.udp_rx_clm_hdr_phrmcy_x_dgns
													ON (udprdsftas.udp_rx_clm_hdr_phrmcy_x_dgns.rx_claim_header_sid = udprdsftas.udp_rx_clm_header_phrmcy_dtl.rx_claim_header_sid) '
					END ||
					CASE
						WHEN i.phar_med = 'M' THEN 'INNER JOIN udprdsftvrtl.udp_member_info
											ON (udprdsftas.udp_clm_header.dim_mbr_sid = udprdsftvrtl.udp_member_info.mbr_sid)'
						WHEN i.phar_med = 'P' THEN 'INNER JOIN udprdsftvrtl.udp_member_info
											ON (udprdsftas.udp_rx_clm_header_phrmcy_dtl.dim_mbr_sid = udprdsftvrtl.udp_member_info.mbr_sid)'
					END ||
					CASE
						WHEN i.scenario_type = 'SURS' AND i.entity_type = 'PR' 
						THEN 'INNER JOIN udprdsftas.udp_schedule_run
								ON (udprdsftas.udp_schedule_run.schedule_run_sid = ' || p_schedule_run_sid || ')' || 
							'INNER JOIN udprdsftas.udp_rslt_surs_prvdr_msr
												ON (udprdsftas.udp_rslt_surs_prvdr_msr.dim_prvdr_sid = udprdsftvrtl.udp_provider_info.prvdr_sid
													AND udprdsftas.udp_rslt_surs_prvdr_msr.schedule_run_sid = udprdsftas.udp_schedule_run.schedule_run_sid
													AND udprdsftas.udp_rslt_surs_prvdr_msr.measure_val <> 0)
										/* Added for Utah Base Product Code Starts */
							
											--	COUNT(DISTINCT measure_sid)|| '' - ''||REGEXP_REPLACE(LISTAGG(code, '', '') WITHIN GROUP(ORDER BY 1), ''([^,]+)(,\\1)+(,|$)'', ''\\1\\3'')
								left outer join ( select measure_sid, code codeagg --REGEXP_REPLACE(LISTAGG(code, '', '') WITHIN GROUP(ORDER BY 1), ''([^,]+)(,\\1)+(,|$)'', ''\\1\\3'') codeagg
												from( select  distinct(a.measure_sid) measure_sid, code -- LISTAGG(code, '', '') code 
																from udprdsftas.udp_msr_prvdr_tcn_detail a inner join '||
																	CASE
																		WHEN i.phar_med = 'M' 
																		THEN 'udprdsftas.udp_clm_header uch
																				ON (a.tcn = uch.tcn )'
																		WHEN i.phar_med = 'P'
																		THEN 'udprdsftas.udp_rx_clm_header_phrmcy_dtl urchpd
																				ON (a.tcn = urchpd.tcn )'
																	END || 
																		'inner join udprdsftas.udp_rslt_surs_prvdr_msr urspm
																				on ( a.measure_sid = urspm.measure_sid 
																					AND a.dim_prvdr_sid = urspm.dim_prvdr_sid)
																where a.schedule_run_sid = ' || v_scenario_run_sid ||'
																--group by a.measure_sid
															)
														--group by measure_sid   
												) a
												ON a.measure_sid = udprdsftas.udp_rslt_surs_prvdr_msr.measure_sid
												
				
										/* Added for Utah Base Product Code Ends */
										'
						WHEN i.scenario_type = 'SURS' AND i.entity_type = 'MB' 
						THEN 'INNER JOIN udprdsftas.udp_schedule_run
												ON (udprdsftas.udp_schedule_run.schedule_run_sid = ' || p_schedule_run_sid || ')' || 
							'INNER JOIN udprdsftas.udp_rslt_surs_mbr_msr  
												ON (udprdsftas.udp_rslt_surs_mbr_msr.dim_mbr_sid = udprdsftvrtl.udp_member_info.mbr_sid
												AND udprdsftas.udp_rslt_surs_mbr_msr.schedule_run_sid = udprdsftas.udp_schedule_run.schedule_run_sid
												AND udprdsftas.udp_rslt_surs_mbr_msr.measure_val <> 0 )
										/* Added for Utah Base Product Code Starts */
										
						left outer join ( select measure_sid,REGEXP_REPLACE(LISTAGG(code, '', '') WITHIN GROUP(ORDER BY 1), ''([^,]+)(,\\1)+(,|$)'', ''\\1\\3'') codeagg
												from( select  distinct(a.measure_sid) measure_sid, LISTAGG(code, '', '') code 
																from udprdsftas.udp_msr_mbr_tcn_detail a inner join '||
																	CASE
																		WHEN i.phar_med = 'M' 
																		THEN 'udprdsftas.udp_clm_header uch
																				ON (a.tcn = uch.tcn )'
																		WHEN i.phar_med = 'P'
																		THEN 'udprdsftas.udp_rx_clm_header_phrmcy_dtl urchpd
																				ON (a.tcn = urchpd.tcn )'
																	END || 
																		'inner join udprdsftas.udp_rslt_surs_mbr_msr ursmm
																				on ( a.measure_sid = ursmm.measure_sid 
																					AND a.dim_mbr_sid = ursmm.dim_mbr_sid)
																where a.schedule_run_sid = ' || v_scenario_run_sid ||'
																group by a.measure_sid
															)
														group by measure_sid   
												) a
												ON a.measure_sid = udprdsftas.udp_rslt_surs_mbr_msr.measure_sid
										/* Added for Utah Base Product Code Ends */
												'
						WHEN i.scenario_type = 'FADS' AND i.entity_type = 'PR' 
						THEN 'INNER JOIN udprdsftas.udp_schedule_run
												ON (udprdsftas.udp_schedule_run.schedule_run_sid = ' || p_schedule_run_sid || ')' || 
							  'INNER JOIN udprdsftas.udp_rslt_fads_clus_prvdr_msr
												ON (udprdsftas.udp_rslt_fads_clus_prvdr_msr.dim_prvdr_sid = udprdsftvrtl.udp_provider_info.prvdr_sid
												AND udprdsftas.udp_rslt_fads_clus_prvdr_msr.schedule_run_sid = udprdsftas.udp_schedule_run.schedule_run_sid
												AND udprdsftas.udp_rslt_fads_clus_prvdr_msr.measure_value <> 0)
										/* Added for Utah Base Product Code Starts */
										
								left outer join ( select measure_sid,REGEXP_REPLACE(LISTAGG(code, '', '') WITHIN GROUP(ORDER BY 1), ''([^,]+)(,\\1)+(,|$)'', ''\\1\\3'') codeagg
												from( select  distinct(a.measure_sid) measure_sid, LISTAGG(code, '', '') code 
																from udprdsftas.udp_msr_prvdr_tcn_detail a inner join '||
																	CASE
																		WHEN i.phar_med = 'M' 
																		THEN 'udprdsftas.udp_clm_header uch
																				ON (a.tcn = uch.tcn )'
																		WHEN i.phar_med = 'P'
																		THEN 'udprdsftas.udp_rx_clm_header_phrmcy_dtl urchpd
																				ON (a.tcn = urchpd.tcn )'
																	END || 
																		'inner join udprdsftas.udp_rslt_fads_clus_prvdr_msr urfcpm
																				on ( a.measure_sid = urfcpm.measure_sid 
																					AND a.dim_prvdr_sid = urfcpm.dim_prvdr_sid)
																where a.schedule_run_sid = ' || v_scenario_run_sid ||'
																group by a.measure_sid
															)
														group by measure_sid   
												) a
												ON a.measure_sid = udprdsftas.udp_rslt_fads_clus_prvdr_msr.measure_sid
												
										/* Added for Utah Base Product Code Ends */
						
										'
						WHEN i.scenario_type = 'FADS' AND i.entity_type = 'MB' 
						THEN 'INNER JOIN udprdsftas.udp_schedule_run
												ON (udprdsftas.udp_schedule_run.schedule_run_sid = ' || p_schedule_run_sid || ')' || 
							'INNER JOIN udprdsftas.udp_rslt_fads_clus_mbr_msr
												ON (udprdsftas.udp_rslt_fads_clus_mbr_msr.dim_mbr_sid = udprdsftvrtl.udp_member_info.mbr_sid
												AND udprdsftas.udp_rslt_fads_clus_mbr_msr.schedule_run_sid = udprdsftas.udp_schedule_run.schedule_run_sid
												AND udprdsftas.udp_rslt_fads_clus_mbr_msr.measure_value <> 0)
										/* Added for Utah Base Product Code Starts */
							left outer join ( select measure_sid,REGEXP_REPLACE(LISTAGG(code, '', '') WITHIN GROUP(ORDER BY 1), ''([^,]+)(,\\1)+(,|$)'', ''\\1\\3'') codeagg
												from( select  distinct(a.measure_sid) measure_sid, LISTAGG(code, '', '') code 
																from udprdsftas.udp_msr_mbr_tcn_detail a inner join '||
																	CASE
																		WHEN i.phar_med = 'M' 
																		THEN 'udprdsftas.udp_clm_header uch
																				ON (a.tcn = uch.tcn )'
																		WHEN i.phar_med = 'P'
																		THEN 'udprdsftas.udp_rx_clm_header_phrmcy_dtl urchpd
																				ON (a.tcn = urchpd.tcn )'
																	END || 
																		'inner join udprdsftas.udp_rslt_fads_clus_mbr_msr urfcmm
																				on ( a.measure_sid = urfcmm.measure_sid 
																					AND a.dim_prvdr_sid = urfcmm.dim_prvdr_sid)
																where a.schedule_run_sid = ' || v_scenario_run_sid ||'
																group by a.measure_sid
															)
														group by measure_sid   
												) a
												ON a.measure_sid = udprdsftas.udp_rslt_fads_clus_mbr_msr.measure_sid
										/* Added for Utah Base Product Code Ends */        
												'
					END;
        /* JOIN Configuration Ends */
        /* WHERE COnfiguration Starts */
        v_where_cndtn := 'WHERE ' ||
        				CASE WHEN i.entity_type = 'MB' 
        					 THEN 'udprdsftvrtl.udp_member_info.client_mmis_id = ' || '''' || p_prvdr_npi || '''' || ''
        				else ''	 
        				END ||
        				CASE
            				WHEN i.entity_type = 'PR' AND i.prvdr_bill_type != 'SE' 
            				THEN ' udprdsftvrtl.udp_provider_info.prvdr_mmis_idntfr = ' || '''' || p_prvdr_npi || '''' || ' '
            				WHEN i.entity_type = 'PR' AND i.prvdr_bill_type = 'SE' 
            				THEN '(udprdsftas.udp_clm_line.SRVCNG_PRVDR_LCTN_IDENTIFIER = ' || '''' || p_prvdr_npi || '''' || '
                                          OR udprdsftas.udp_clm_header.SRVCNG_PRVDR_LCTN_IDENTIFIER = ' || '''' || p_prvdr_npi || '''' || '
                                          OR udprdsftas.udp_clm_header.BLNG_PRVDR_LCTN_IDENTIFIER = ' || '''' || p_prvdr_npi || '''' || ')'
							else ''
        				END || ' ' ||
        /* ||CASE WHEN i.phar_med = 'P' THEN v_pharm_sql ELSE v_med_sql END */
        				CASE
            				WHEN i.phar_med = 'M' 
            				THEN ' AND udprdsftas.udp_clm_header.adjudication_date 
										BETWEEN udprdsftas.udp_schedule_run.data_start_date AND udprdsftas.udp_schedule_run.data_end_date '
            				WHEN i.phar_med = 'P' 
            				THEN ' AND udprdsftas.udp_rx_clm_header_phrmcy_dtl.adjudication_date 
										BETWEEN udprdsftas.udp_schedule_run.data_start_date AND udprdsftas.udp_schedule_run.data_end_date '
        				END;
       
        v_phar_med_sql :=
						CASE
							WHEN i.cnt = 1 THEN v_columns || ' ' || nvl(v_joins,'') || ' ' || nvl(v_where_cndtn,'')
							ELSE ' UNION ' || v_columns || ' ' || nvl(v_joins,'') || ' ' || nvl(v_where_cndtn,'')
						END;
        v_sql := v_sql || ' ' || v_phar_med_sql;
        v_phar_med_sql := '';
        v_columns := '';
        v_where_cndtn := '';
    END LOOP;
 --  raise notice '%main query%',v_step_no,v_sql;
    v_contributing_clms_qry := '';
    v_step_no := 30;

RAISE INFO 'v sql  : %', v_sql;
	
    DELETE FROM udprdsftas.udp_temp_rpt_scnr_process
    WHERE scenario_run_sid = p_schedule_run_sid 
	AND CASE
            WHEN v_prvdr_mbr = 'PR' THEN participant_id
        /* Included for Level 3 changes */
            WHEN v_prvdr_mbr = 'MB' THEN member_id
        END = '' || p_prvdr_npi || '';
    v_step_no := 40;
    /* Added for Utah Base Product Code Starts */
    v_sql_1 := ' INSERT INTO udprdsftas.udp_temp_rpt_scnr_process (
                                    scenario_sid,
                                    scenario_run_sid,
                                    provider_npi,
                                    provider_id,
                                    member_id,
                                    rpt_flex_field_1,
                                    rpt_flex_field_2,
                                    rpt_flex_field_8,
                                    rpt_flex_field_3,
                                    rpt_flex_field_4,
                                    member_name,
                                    provider_name,
                                    rpt_flex_field_5,
                                    rpt_flex_field_6,
                                    rpt_flex_field_7,
                                    rpt_flex_field_9,
                                    rpt_flex_field_10,
                                    last_extract_date,
                                    status,
                                    PARTICIPANT_ID,
                                    /* Added for Utah Base Product Code Starts*/
                                    assc_msrs
                                    /* Added for Utah Base Product Code Ends*/
                                   )
                             SELECT scenario_sid,
                                    schedule_run_sid scenario_run_sid,
                                   "provider_npi"          provider_npi,
                                   "provider_id"           provider_id,
                                   "member_id"             member_id,
                                   "tcn"                   rpt_flex_field_1,
                                   "from_service_date"     rpt_flex_field_2,
                                   "to_service_date"       rpt_flex_field_8,
                                   "paid_amount"           rpt_flex_field_3,
                                   "billed_amount"         rpt_flex_field_4,
                                   "member_name"           member_name,
                                   "provider_name"         provider_name,
                                   DC                      rpt_flex_field_5,
                                   sort_paid_amount        rpt_flex_field_6,
                                   sort_billed_amount      rpt_flex_field_7,
                                   sort_to_date            rpt_flex_field_9,
                                   sort_from_date          rpt_flex_field_10,
                                   last_extract_date,
                                   status,
                                   participant_id,
                                   /* Added for Utah Base Product Code Starts*/
                                  CASE WHEN COUNT( measure_sid) = ''0''
                                        THEN ''0''
                                        ELSE COUNT( measure_sid)|| '' - ''||REGEXP_REPLACE(LISTAGG(codeagg, '', '') WITHIN GROUP(ORDER BY 1), ''([^,]+)(,\\1)+(,|$)'', ''\\1\\3'')
                                    END assc_msrs
									 --cnt||''-''||codeagg assc_msrs
									 --case when length(codeagg)>0 then REGEXP_COUNT(codeagg, '','') + 1 ||''-'' ||codeagg
									 --else ''0''
									 --end assc_msrs
                        FROM (' || v_sql || ')    -- Included for Level 3 changes
                                GROUP BY scenario_sid, 
                                      schedule_run_sid, 
                                      "provider_npi", 
                                      "provider_id", 
                                      "member_id", 
                                      "tcn",
                                      "from_service_date",
                                      "to_service_date",
                                      "paid_amount",
                                      "billed_amount", 
                                      "member_name",
                                      "provider_name",
                                      DC, 
                                      sort_paid_amount, 
                                      sort_billed_amount, 
                                      sort_to_date, 
                                      sort_from_date, 
                                      last_extract_date, 
                                      status, 
                                      participant_id
                                      --codeagg
                            ';
    COMMIT;
	-- raise notice '%main query%',v_step_no,v_sql_1;
    /* Added for Utah Base Product Code Ends */
    /* DBMS_OUTPUT.PUT_LINE(v_sql_1); */
    EXECUTE v_sql_1;
    v_step_no := 50;
    /* Participant Count */
    SELECT COUNT(1)
        INTO v_participant_count
    FROM udprdsftas.udp_temp_rpt_scnr_process
    WHERE scenario_run_sid = p_schedule_run_sid 
	AND CASE
            WHEN v_prvdr_mbr = 'PR' THEN participant_id
        /* Included for Level 3 changes */
            WHEN v_prvdr_mbr = 'MB' THEN member_id
        END = p_prvdr_npi;
       
       p_participant_count := v_participant_count;
       
    /* DBMS_OUTPUT.PUT_LINE('Step -> 50-> '||p_participant_count); */
    v_step_no := 60;
    v_all_measure := 'SELECT * FROM
                    (SELECT * FROM
                    (SELECT DISTINCT member_id,
                            rpt_flex_field_1 claim_id,
                            provider_id ,
                            provider_npi,
                            member_name mbr_name,
                            nvl(provider_name,'''') prvdr_name,
                            rpt_flex_field_2 from_service_date,
                            rpt_flex_field_8 to_service_date,
                            rpt_flex_field_4 billed_amount,
                            rpt_flex_field_3 paid_amount,
                            rpt_flex_field_5 DC,
                            '''' COS,
                            rpt_flex_field_6 PC,
                            rpt_flex_field_7 PS,
                            '''' ST,
                            '''' PT,
                            rpt_flex_field_9 sort_from_date,
                            rpt_flex_field_10 sort_to_date,
                            status,
                            assc_msrs,'  || v_participant_count || '
      /* Added for Utah Base Product Code*/                            
                      cnt FROM udprdsftas.udp_temp_rpt_scnr_process' ||
    /* Base Code fix on 12/12/2019 Starts */
					  ' WHERE scenario_sid = ' || p_scenario_sid || ' AND ' ||
					CASE
						WHEN v_prvdr_mbr = 'PR' THEN 'PARTICIPANT_ID'
					/* Included for Level 3 changes' */
						WHEN v_prvdr_mbr = 'MB' THEN 'member_id'
					END || ' = ' || p_prvdr_npi || ' AND scenario_run_sid = ' || p_schedule_run_sid || ' )' || ' ORDER BY ' || p_column_name || CHR(MOD(32, 256));
    v_step_no := 70;

    IF UPPER(p_order_by) LIKE 'DESC' THEN
        v_all_measure := v_all_measure || 'DESC)';
    ELSE
        v_all_measure := v_all_measure || 'ASC)';
    END IF;
    /* For Taking Count */
    /* EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ( '||v_all_measure||' )' INTO p_participant_count; */
    /* For Taking Offset */
    v_step_no := 80;
    /* added by Unnamalai for veracode fix ends */

    IF (p_start_number >= 0 AND p_end_number >= 0) THEN
        v_start_number := p_start_number;
        v_end_number := p_end_number;
    END IF;
    /* added by Unnamalai for veracode fix ends */
		
	v_sql_offset := v_all_measure||' LIMIT '||v_end_number||' OFFSET '
                    ||v_start_number;
                   
                  -- raise notice '%',v_sql_offset;
                    
	EXECUTE 'DROP TABLE IF EXISTS '||p_result_set;
	EXECUTE ' CREATE TEMP TABLE '||p_result_set ||' AS '||v_sql_offset;
    /* Base Product Fix on 12/12/2019 Ends. */
    RAISE INFO 'p_result_set : %', p_result_set;
    COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            p_err_code := SQLSTATE;
			
			SELECT java_error_desc
				INTO p_err_msg
			FROM udprdsftasext.sec_error_msg
			WHERE sql_error_code = p_err_code 
			AND error_category = 'RedShift';

			p_err_code := -1;
		
			call udprdsftas.udp_pr_error_log_ins(
													SQLSTATE,
													SQLERRM,
													v_step_no,
													SUBSTR(v_replace_col, 1, 4000)||' '||SUBSTR(v_replace_col, 4001, 8000),
													'RUN_ID: '||p_schedule_run_sid,
													SUBSTR(v_all_measure, 1, 4000),
													SUBSTR(v_all_measure, 4001, 8000),
													SUBSTR(v_all_measure, 8001, 12000),
													'upd_pr_rpt_claim_detail',
													1
													);			
					
END;





$$
;
