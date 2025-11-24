SELECT
                run_id,
                scenario_sid,
                LISTAGG(uppv.program_cid::int,
                ',') WITHIN GROUP(
                ORDER BY
                    NULL
                ) program_cid,
                LISTAGG(uppv.program_name,
                ',') WITHIN GROUP(
                ORDER BY
                    NULL
                ) program_name,
                name,
                code,
                scenario_dtl_sid,
                entity,
                type,
                status,
                frequency,
                run_date,
                user_acct_sid,
                COUNT(1) OVER(
                    PARTITION BY NULL
                ) cnt
            FROM
                udprdsftas.udp_surs_run_list_vw sv
                INNER JOIN udprdsftasext.user_prfl_prgm uppv ON sv.program_cid = uppv.program_cid
            WHERE
                UPPER( user_login_id ) = UPPER ('supuser')
                        AND   prfl_sid = 500031635
                 AND UPPER(TYPE) = UPPER('Adhoc')
                 AND CODE SIMILAR TO '%DEMOSI01%'
                AND run_id IN (SELECT DISTINCT MAX(run_id) OVER(PARTITION BY scenario_sid) run_id
                             FROM udprdsftas.udp_surs_run_list_vw WHERE UPPER(TYPE) = UPPER('Adhoc'))
                AND   scenario_dtl_sid IN
                 (SELECT u. scenario_dtl_sid
                        FROM
                 udprdsftasext.scenario_x_program u
                 INNER JOIN (SELECT sd.scenario_dtl_sid from udprdsftasext.scenario_detail sd
            INNER JOIN udprdsftasext.scenario s ON s.scenario_sid = sd.scenario_sid
            WHERE s.scenario_type = 'SURS'
            UNION
            SELECT sr.scenario_dtl_sid from udprdsftasext.scenario_reject sr
            WHERE sr.scenario_type = 'SURS')w ON w.scenario_dtl_sid=u.scenario_dtl_sid)
            GROUP BY
                run_id,
                scenario_sid,
                name,
                code,
                scenario_dtl_sid,
                entity,
                type,
                status,
                frequency,
                run_date,
                user_acct_sid
            ORDER BY
               RUN_ID DESC
            OFFSET 0 LIMIT 100
