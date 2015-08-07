/*
  TODO
  - make a program that proves what relic and decryptor are optimal
*/
BEGIN
--  EXECUTE IMMEDIATE 'ALTER SESSION SET SQL_TRACE = FALSE';
  EXECUTE IMMEDIATE 'PURGE TABLESPACE eveonline USER EVE';

  EXECUTE IMMEDIATE 'ALTER SESSION SET PLSQL_OPTIMIZE_LEVEL = 3';
  EXECUTE IMMEDIATE 'ALTER SESSION SET PLSQL_CODE_TYPE      = ' || CHR(39) || 'NATIVE' || CHR(39);
  EXECUTE IMMEDIATE 'ALTER SESSION SET PLSQL_DEBUG          = FALSE';

  dbms_utility.compile_schema(schema => 'EVE');
END;
/



-- REFRESH ALL DATA
BEGIN
  BEGIN
    --begin delete from cache_market_quicklook; delete from produce; delete from composite; delete from part; commit; end; -- uncomment for a full redo
    BEGIN load_indu_details.merge_part_composite; END;
  END;

  BEGIN
    BEGIN
      -- delete from cache_asset_list -- refresh from the Web Service, but be adviced CCP will not tolerate unnecessarily frequent & repetitive requests
      load_player_data.load_pile;
    END;

    BEGIN
      -- BEGIN load_market_data.load_prices(24700, 0.5); END; -- DEBUG with one items market data
      -- BEGIN DELETE FROM cache_market_quicklook; COMMIT; END;
      load_market_data.submit_price_jobs(p_local_regions  => 'VERGE VENDOR GENESIS ESSENCE EVERYSHORE SINQ LAISON PLACID THE CITADEL' -- define your local regions
                                        ,p_security_limit => 0.5);

      -- AS SYS/SYSDBA when problems: BEGIN DELETE FROM dba_jobs WHERE schema_user LIKE 'EVE' AND what LIKE '%load_market_data%'; COMMIT; END;
    END;
  END;
END;
/




-- Remaining JOBs
SELECT COUNT(1) OVER (ORDER BY 1) AS remain
      --,TO_TIMESTAMP(next_date || next_sec)
      --SYSTIMESTAMP AS til_next
      ,jobs.*
FROM   user_jobs jobs ORDER BY jobs.job;





-- market_order DELETEd and now missing? (market_order is the way to DRILL IN and find where exactly the sell is before traveling there
SELECT *
FROM            market_aggregate agr
LEFT OUTER JOIN market_order     mor ON mor.part_id = agr.part_id
WHERE  mor.part_id IS NULL;





--    Where is this Input needed?
  SELECT *
  FROM   vw_composite
  WHERE  1=1
  AND    part            LIKE '%'|| UPPER(:part)   ||'%'
  AND    material_origin LIKE '%'|| UPPER(:origin) ||'%'
/*
  Iso                        Ochre  Gneis  Hedber  Hemor        Kern  Omber                       Spodu
  Mega    Arkon  Bist
  Mexa    Arkon                     Gneis                 Jasp  Kern         Plagio  Pyro         Spodu
  Nocx                 Crok  Ochre         Hedber  Hemor  Jasp                       Pyro
  Pyer           Bist               Gneis  Hedber                     Omber  Plagio  Pyro  Scord  Spodu
  Trit    Arkon        Crok  Ochre                 Hemor        Kern  Omber  Plagio  Pyro  Scord  Spodu  Veld
  Zyd            Bist  Crok                Hedber  Hemor  Jasp
  -----------------------------------------------------------------------------------------------------------
  Arkon        Mega  Mexa              Trit
  Bist         Mega              Pyer        Zyd
  Crok                     Nocx        Trit  Zyd
  Ocher   Iso              Nocx        Trit
  Gneis   Iso        Mexa        Pyer
  Hedber  Iso              Nocx  Pyer        Zyd
  Hemor   Iso              Nocx        Trit  Zyd
  Jasp               Mexa  Mocx              Zyd
  Kern    Iso        Mexa              Trit
  Omber   Iso                    Pyer  Trit
  Plagio             Mexa        Pyer  Trit
  Pyro               Mexa  Nocx  Pyer  Trit
  Scord                          Pyer  Trit
  Spodu   Iso        Mexa        Pyer  Trit
  Veld                                 Trit
*/
  ;



-- Quickly browse on anything at Input
  SELECT *
  FROM   mw_produce
  WHERE  produce = 'PILGRIM'
  ORDER BY produce, good, part
  ;



-- A product at Part but not broken into Inputs
  SELECT *
  FROM            part      prt
  LEFT OUTER JOIN composite cmp ON cmp.good = prt.label
  WHERE  cmp.good           IS NULL
  AND    prt.material_origin = 'PRODUCE'
  ORDER BY race, label
  ;

  

  SELECT DISTINCT good FROM composite
  --WHERE good LIKE '%'|| UPPER(:good) ||'%'
  ORDER BY good ASC;
