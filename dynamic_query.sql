SELECT  DISTINCT 193 scenario_sid,385 schedule_run_sid,NVL((udprdsftas.udp_clm_header.blng_national_prvdr_idntfr)::varchar,' ') "provider_npi",
												NVL((udprdsftas.udp_clm_header.blng_prvdr_lctn_identifier)::varchar,' ') "provider_id",
												udprdsftvrtl.udp_member_info.client_mmis_id "member_id",
												udprdsftas.udp_clm_header.tcn "tcn",TO_CHAR(udprdsftas.udp_clm_header.from_service_date,'MM/DD/YYYY') "from_service_date",
												TO_CHAR(udprdsftas.udp_clm_header.to_service_date,'MM/DD/YYYY') "to_service_date",
												NVL(TO_CHAR(udprdsftas.udp_clm_header.total_billed_amount,'999999.99'),'0.00') "billed_amount",
												NVL(TO_CHAR(udprdsftas.udp_clm_header.paid_amount,'999999.99'),'0.00') "paid_amount",
												udprdsftas.udp_clm_header.patient_first_name||' '||udprdsftas.udp_clm_header.patient_last_name "member_name",
												udprdsftas.udp_clm_header.blng_prvdr_first_name||' '||udprdsftas.udp_clm_header.blng_prvdr_last_name "provider_name",
												udprdsftvrtl.udp_d_diagnosis.diagnosis_code||' - '||udprdsftvrtl.udp_d_diagnosis.diag_short_desc DC,
												udprdsftas.udp_clm_header.total_billed_amount sort_billed_amount,
												udprdsftas.udp_clm_header.paid_amount sort_paid_amount,
												udprdsftas.udp_clm_header.from_service_date sort_from_date,
												udprdsftas.udp_clm_header.to_service_date sort_to_date,CURRENT_DATE last_extract_date,
                                'Y' status,1363112 participant_id , a.measure_sid,
                                  codeagg  FROM udprdsftas.udp_clm_header
										INNER JOIN udprdsftas.udp_clm_line
												ON (udprdsftas.udp_clm_line.claim_header_sid = udprdsftas.udp_clm_header.claim_header_sid
												) INNER JOIN udprdsftvrtl.udp_provider_info
										ON (udprdsftvrtl.udp_provider_info.prvdr_mmis_idntfr = NVL(udprdsftas.udp_clm_line.SRVCNG_PRVDR_LCTN_IDENTIFIER,NVL(udprdsftas.udp_clm_header.SRVCNG_PRVDR_LCTN_IDENTIFIER,udprdsftas.udp_clm_header.BLNG_PRVDR_LCTN_IDENTIFIER)))  LEFT JOIN udprdsftvrtl.udp_d_diagnosis
												ON (udprdsftvrtl.udp_d_diagnosis.diagnosis_iid = udprdsftas.udp_clm_header.primary_diagnosis_iid) INNER JOIN udprdsftvrtl.udp_member_info
											ON (udprdsftas.udp_clm_header.dim_mbr_sid = udprdsftvrtl.udp_member_info.mbr_sid)INNER JOIN udprdsftas.udp_schedule_run
								ON (udprdsftas.udp_schedule_run.schedule_run_sid = 385)INNER JOIN udprdsftas.udp_rslt_surs_prvdr_msr
												ON (udprdsftas.udp_rslt_surs_prvdr_msr.dim_prvdr_sid = udprdsftvrtl.udp_provider_info.prvdr_sid
													AND udprdsftas.udp_rslt_surs_prvdr_msr.schedule_run_sid = udprdsftas.udp_schedule_run.schedule_run_sid
													AND udprdsftas.udp_rslt_surs_prvdr_msr.measure_val <> 0)
										/* Added for Utah Base Product Code Starts */
							
											--	COUNT(DISTINCT measure_sid)|| ' - '||REGEXP_REPLACE(LISTAGG(code, ', ') WITHIN GROUP(ORDER BY 1), '([^,]+)(,\1)+(,|$)', '\1\3')
								left outer join ( select measure_sid, code codeagg --REGEXP_REPLACE(LISTAGG(code, ', ') WITHIN GROUP(ORDER BY 1), '([^,]+)(,\1)+(,|$)', '\1\3') codeagg
												from( select  distinct(a.measure_sid) measure_sid, code -- LISTAGG(code, ', ') code
																from udprdsftas.udp_msr_prvdr_tcn_detail a inner join udprdsftas.udp_clm_header uch
																				ON (a.tcn = uch.tcn )inner join udprdsftas.udp_rslt_surs_prvdr_msr urspm
																				on ( a.measure_sid = urspm.measure_sid
																					AND a.dim_prvdr_sid = urspm.dim_prvdr_sid)
																where a.schedule_run_sid = 385
																--group by a.measure_sid
															)
														--group by measure_sid   
												) a
												ON a.measure_sid = udprdsftas.udp_rslt_surs_prvdr_msr.measure_sid
												
				
										/* Added for Utah Base Product Code Ends */
										 WHERE (udprdsftas.udp_clm_line.SRVCNG_PRVDR_LCTN_IDENTIFIER = '1363112'
                                          OR udprdsftas.udp_clm_header.SRVCNG_PRVDR_LCTN_IDENTIFIER = '1363112'
                                          OR udprdsftas.udp_clm_header.BLNG_PRVDR_LCTN_IDENTIFIER = '1363112')  AND udprdsftas.udp_clm_header.adjudication_date
										BETWEEN udprdsftas.udp_schedule_run.data_start_date AND udprdsftas.udp_schedule_run.data_end_date
