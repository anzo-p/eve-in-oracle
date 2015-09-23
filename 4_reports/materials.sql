SELECT -- CHEAPest Region for HIGH FLOW items
/*
    Price/Distance Convenience:
    - how param :current_region  compares to  Query Result
    - how Query Result           compares to  Best Price in the Known EVE Universe
    As % since it helps better to compare/estimate Profit Margins
*/
      INITCAP(CASE WHEN utils.keywd(prt.ident, 'ORE') = utils.f_get('k_numeric_true') THEN
                        utils.readable_ore(prt.label)
                      ELSE                 prt.label
                 END                                                                                ) AS part

        ,INITCAP(:keyword)                                                                            AS keyword
        ,INITCAP(          sel.name_region                                                          ) AS region 

         -- how do prices compare against best in known EVE Universe (%)?
        ,(SELECT CASE
                   WHEN :buy_local IS NOT NULL THEN
                     TO_CHAR(TRUNC(sel.offers_low_range/ bgn.offers_low_range *100)) || '% ' || INITCAP(bgn.name_region)
                 END
          FROM   vw_avg_sells_regions bgn
          WHERE  bgn.part_id          =  prt.ident
          AND    bgn.offers_low_range = (SELECT MIN(sub.offers_low_range)
                                         FROM   vw_avg_sells_regions sub
                                         WHERE  sub.part_id = bgn.part_id)
          AND    ROWNUM               =  1)                                                           AS of_best_buy_in

        ,TO_CHAR(                                 sel.offers_low_range        ,'990G990G990G990D99' ) AS sellers

         -- "Since I am currently flying at :current_region", how do these local prices compare?
        ,(SELECT CASE
                   WHEN :current_region IS NOT NULL THEN
                     TO_CHAR(TRUNC(sub.offers_low_range / sel.offers_low_range *100)) || '% ' || INITCAP(sub.name_region)
                 END
          FROM   vw_avg_sells_regions sub
          WHERE  sub.part_id          =  prt.ident
          AND   (sub.name_region   LIKE '%'|| UPPER(:current_region) ||'%'   AND :current_region IS NOT NULL)
          AND    ROWNUM               =  1)                                                           AS compares


        ,TO_CHAR(                                 sel.offers_low_range * 1.02 ,'990G990G990G990D99' ) AS premium_two
        ,TO_CHAR(                                 sel.offers_low_range * 1.04 ,'990G990G990G990D99' ) AS premium_four

/*
         What Quantities, Expenses, and Cargo Spaces involved if we build one piece out of every product that we have preset?
         Gives a loose idea on the expected material flows, which the Industrialist ought to assume over time
        ,TO_CHAR( CEIL(SUM(cmp.quantity)                              )       ,'990G990G990G990'    ) AS quantity
        ,TO_CHAR( CEIL(SUM(cmp.quantity)        * sel.offers_low_range)       ,'990G990G990G990'    ) AS expense
        ,TO_CHAR( CEIL(SUM(cmp.quantity)        * prt.volume          )       ,    '990G990G990'    ) AS volume
        ,TO_CHAR(          prt.pile                                           ,'990G990G990G990'    ) AS pile
*/

  FROM            part                 prt
       INNER JOIN vw_avg_sells_regions sel ON sel.part_id = prt.ident
  LEFT OUTER JOIN composite            cmp ON cmp.part_id = prt.ident -- give all items, regadrless whether decided to use in prod, like Planetary and Moon Materials and Decryptors

  WHERE  utils.keywd(prt.ident, UPPER(:keyword)) = utils.f_get('k_numeric_true')
  AND    sel.offers_low_range * sel.samples      > load_market_data.v_get('k_notable_supply_part')
  AND    sel.region                              = load_market_data.get_econ_region(p_part_id       => prt.ident
                                                                                   ,p_direction     => sel.direction
                                                                                   ,p_local_regions => :buy_local)
  
  GROUP BY prt.ident, prt.label, prt.volume, prt.pile, sel.offers_low_range, sel.name_region
  ORDER BY part
  ;






  SELECT -- Materials & Job List on Sets of Produces
/*
    Show me in a Single Query the required Materials/Components to build a diverse set of products.    
    Dont want to do many queries and somehow copy-cahche those results somewhere - what does that even mean?
    
    Sample lists: list_a: 9x{huginn,pilgrim,sacrilege}  list_b: 5x{impel,prorator}
    
    When Shopping: Set keyword to your loopuk Material
    When Building: Set keyword to "components" for a list of required jobs and units to build.
*/
         :list_a ||' '|| :list_b ||' '|| :list_c               AS params
        ,INITCAP(:keyword)                                     AS keyword
        ,INITCAP(fin.part)                                     AS part
        ,TO_CHAR(fin.quantity_orig,    '990G990G990G990D99')   AS quantity_orig -- here as backup to illustrate material consumption on Copies over Originals
        ,TO_CHAR(fin.quantity_copy,    '990G990G990G990D99')   AS quantity
        ,TO_CHAR(fin.quantity_copy * 0.5,    '990G990G990G990D99')   AS qu
        ,TO_CHAR(fin.pile,             '990G990G990G990D99')   AS pile
        ,TO_CHAR(fin.short,            '990G990G990G990D99')   AS shop_list
        ,TO_CHAR(fin.offers_low_range, '990G990G990G990D99')   AS quote
        ,INITCAP(fin.name_region)                              AS region

        ,TO_CHAR(SUM(fin.short * fin.offers_low_range) OVER (ORDER BY 1),
                                       '990G990G990G990D99')   AS items_tot

        ,ROUND(      fin.volume * fin.short
                    /load_market_data.f_get('k_dstful')
                    *100, 2)                                   AS item_dst_cargo
        
--        ,ROUND(SUM(  fin.volume * fin.short
        ,ROUND(SUM(  fin.volume * fin.quantity_copy
                    /80500 --load_market_data.f_get('k_dstful')
                    *100)
               OVER (ORDER BY 1), 1)                           AS total_dst_cargo

        ,CASE
           WHEN utils.keywd(fin.part_id, 'COMPONENTS') = utils.f_get('k_numeric_true') AND
                            short                      > 0                             THEN
             -- essentially the same as shop_list, but in a readable format to Copy-Paste for todo list - easily track the remaning jobs
             --TO_CHAR(fin.quantity_copy, '9G999G990') ||'  '|| INITCAP(fin.part) -- DEBUG
             TO_CHAR(fin.short, '9G999G990') ||'  '|| INITCAP(fin.part)
         END                                                   AS job_list


  FROM  (SELECT mat.part_id
               ,mat.part
               ,mat.volume
               ,mat.pile
               ,sel.offers_low_range
               ,sel.name_region
               
               ,SUM(    mat.quantity_true_pos_bp_orig) AS quantity_orig
               ,SUM(    mat.quantity_true_pos_bp_copy) AS quantity_copy

               ,CASE
                  WHEN 0 < SUM(mat.quantity_true_pos_bp_copy) - mat.pile THEN
                    SUM(mat.quantity_true_pos_bp_copy) - mat.pile
                END                                    AS short
              
         FROM           (SELECT --src.produce
                                src.good, src.part_id, src.part, src.pile, src.volume


                                -- the faster way: from Original Blueprints, but too optimistic to use on Blueprint Copies
                               ,utils.calculate(REPLACE(src.formula_bp_orig, ':UNITS',       src.units                             )) AS quantity_true_pos_bp_orig


                                -- the High Fidelity way: from Blueprint Copies. Leaving :bpc_runs to NULL makes it work just like Original Blueprints
                               ,utils.calculate(                                       FLOOR(src.units / NVL(:bpc_runs, src.units))   -- how many Full BPCs?
                                   ||' * '||    REPLACE(src.formula_bp_orig, ':UNITS',                   NVL(:bpc_runs, src.units) )
                                   ||' + '||    REPLACE(src.formula_bp_orig, ':UNITS', MOD  (src.units,  NVL(:bpc_runs, src.units)))) -- plus how many Units/Job Runs on one further BPC
                                                                                                                                      AS quantity_true_pos_bp_copy
/*
                               ,                REPLACE(src.formula_bp_orig, ':UNITS',       src.units                             )  AS formula_bp_orig

                               ,                                                       FLOOR(src.units / NVL(:bpc_runs, src.units))
                                   ||' * '||    REPLACE(src.formula_bp_orig, ':UNITS',                   NVL(:bpc_runs, src.units)  )
                                   ||' + '||    REPLACE(src.formula_bp_orig, ':UNITS', MOD  (src.units,  NVL(:bpc_runs, src.units)))  AS formula_bp_copy
*/
                               ,formula_bp_orig
                                
                         FROM  (SELECT --pdc.produce
                                       pdc.good
                                      ,prt.ident           AS part_id
                                      ,prt.label           AS part
                                      ,prt.volume
                                      ,prt.pile
                                      ,pdc.formula_bp_orig

                                      ,CASE
                                       -- format: Nx { [Elements, comma delimited] } eg. 3x{huginn,pilgrim,sacrilege}
                                       --WHEN                Produce   EXISTS in Our List                      THEN do given Units
                                         WHEN utils.elem(pdc.produce, :list_a) = utils.v_get('k_numeric_true') THEN SUBSTR(:list_a, 1, INSTR(:list_a, 'x')-1)
                                         WHEN utils.elem(pdc.produce, :list_b) = utils.v_get('k_numeric_true') THEN SUBSTR(:list_b, 1, INSTR(:list_b, 'x')-1)
                                         WHEN utils.elem(pdc.produce, :list_c) = utils.v_get('k_numeric_true') THEN SUBSTR(:list_c, 1, INSTR(:list_c, 'x')-1)
                                         --...
                                       END                 AS units

                                FROM       mw_produce pdc
                                INNER JOIN part       prt ON prt.ident = pdc.part_id
                              
                                WHERE  (utils.keywd(prt.ident, UPPER(:keyword)) = utils.f_get('k_numeric_true')   OR :keyword IS NULL)
                                ) src
                        
                         WHERE  src.units IS NOT NULL
                         ORDER BY src.part, src.good
                         ) mat


         LEFT OUTER JOIN vw_avg_sells_regions                        sel ON sel.part_id = mat.part_id
         
         WHERE  (sel.region = load_market_data.get_econ_region(p_part_id       => sel.part_id
                                                              ,p_direction     => sel.direction
                                                              ,p_local_regions => :local_buy)    OR sel.region IS NULL)

         GROUP BY mat.part_id, mat.part, mat.volume, mat.pile, sel.offers_low_range, sel.name_region) fin
         

  WHERE  (0 < fin.quantity_copy - fin.pile   OR :short IS NULL)
         
  ORDER BY fin.part;








  SELECT -- Accurate Material Requirements on 3-Tier Mass Builds
/*
    A revised, prototyping More Exact Fetch for Materials, that takes into account the EXTRA YIELD
    on Material Efficiency when building Components that are COMMON OVER THE SETS of buils. SHOPPING LIST ONLY.

--> THE ONLY SENSIBLE KEYWORD's here are 'Materials' and all headings under that tree in EVE Market Window <---

    
    Massmaterials test sets, mind the Max Runs on Copies:
    - No Benefit on Tech2 Builds: 9x{Sacrilege,Devoter,Guardian,Curse,Pilgrim}

    - Considerable Benefit on Tech3: When the full set totally uses the same components
      15x{legion defensive - warfare processor,tengu defensive - warfare processor,loki defensive - warfare processor}
*/
         :list_a ||' '|| :list_b ||' '|| :list_c               AS params
        ,INITCAP(fin.part)                                     AS part
        ,INITCAP(:keyword)                                     AS keyword
        ,TO_CHAR(fin.quantity_orig,    '990G990G990G990')      AS quantity_orig -- here as backup to illustrate material consumption on Copies over Originals
        ,TO_CHAR(fin.quantity_copy,    '990G990G990G990')      AS quantity
        ,TO_CHAR(fin.pile,             '990G990G990G990')      AS pile
        ,TO_CHAR(fin.short,            '990G990G990G990')      AS shop_list
        ,TO_CHAR(fin.offers_low_range, '990G990G990G990D99')   AS quote
        ,INITCAP(fin.name_region)                              AS region

        ,TO_CHAR(SUM(fin.short * fin.offers_low_range) OVER (ORDER BY 1),
                                       '990G990G990G990D99')   AS items_tot

        ,ROUND(      fin.short * fin.volume
                    /load_market_data.f_get('k_dstful')
                    *100, 2)                                   AS item_dst_cargo
        
        ,ROUND(  SUM(fin.short * fin.volume
                    /load_market_data.f_get('k_dstful')
                    *100)
                 OVER (ORDER BY 1), 1)                         AS total_dst_cargo


  FROM  (SELECT mat.part_id
               ,mat.part
               ,mat.volume
               ,mat.pile
               ,sel.offers_low_range
               ,sel.name_region
               
               ,SUM(    mat.quantity_true_pos_bp_orig) AS quantity_orig
               ,SUM(    mat.quantity_true_pos_bp_copy) AS quantity_copy

               ,CASE
                  WHEN 0 < SUM(mat.quantity_true_pos_bp_copy) - mat.pile THEN
                    SUM(mat.quantity_true_pos_bp_copy) - mat.pile
                END                                    AS short
              

         -- 3 finally we have all the materials optimized over the full set of produces
         FROM            (SELECT prd.part, prd.part_id, prt.pile, prt.volume
                              
                                ,                REPLACE(prd.formula_bp_orig, ':UNITS',         bld.units_orig            ) AS formula_true_pos_bp_orig     
                                ,utils.calculate(REPLACE(prd.formula_bp_orig, ':UNITS', REPLACE(bld.units_orig, ',', '.'))) AS quantity_true_pos_bp_orig
                               
                                 -- here we build out of Original Blueprints { Ships, Components } and dont need to calculate Copies, just flow them through from Subquery
                                ,                REPLACE(prd.formula_bp_orig, ':UNITS',         bld.units_copy            ) AS formula_true_pos_bp_copy   
                                ,utils.calculate(REPLACE(prd.formula_bp_orig, ':UNITS', REPLACE(bld.units_copy, ',', '.'))) AS quantity_true_pos_bp_copy
                         
                
                          FROM             mw_produce             prd
                               INNER JOIN  part                   prt ON prt.ident   = prd.part_id
                
                               -- 2B: This is the Whole POINT: Sum up the distinct requirements of same Components as we can build them all in one Job - Economics of Scale on Material Efficiency
                               INNER JOIN (SELECT bat.part
                                                 ,TO_NUMBER(SUM(bat.units_orig)) AS units_orig
                                                 ,TO_NUMBER(SUM(bat.units_copy)) AS units_copy
                      
                                           -- 2 Get their individually required Intermediate Components
                                           FROM  (SELECT src.good, src.part
                      
                                                        ,                REPLACE(src.formula_bp_orig, ':UNITS',       src.units                             )  AS formula_orig
                                                        ,utils.calculate(REPLACE(src.formula_bp_orig, ':UNITS',       src.units                             )) AS units_orig
                      
                                                         -- here we probably build out of Tech2 & 3 Blueprint Copies and its necessary to do the Copies-calculation
                                                        ,utils.calculate(                                       FLOOR(src.units / NVL(:bpc_runs, src.units))
                                                             ||' * '||   REPLACE(src.formula_bp_orig, ':UNITS',                   NVL(:bpc_runs, src.units)  )
                                                             ||' + '||   REPLACE(src.formula_bp_orig, ':UNITS', MOD  (src.units,  NVL(:bpc_runs, src.units)))) AS units_copy
                      
                                                  -- 1 FROM All the listed up 3-Tier builds
                                                  FROM (SELECT bat.*
                                                              ,CASE
                                                                 WHEN utils.elem(bat.good, :list_a) = utils.v_get('k_numeric_true') THEN SUBSTR(:list_a, 1, INSTR(:list_a, 'x')-1)
                                                                 WHEN utils.elem(bat.good, :list_b) = utils.v_get('k_numeric_true') THEN SUBSTR(:list_b, 1, INSTR(:list_b, 'x')-1)
                                                                 WHEN utils.elem(bat.good, :list_c) = utils.v_get('k_numeric_true') THEN SUBSTR(:list_c, 1, INSTR(:list_c, 'x')-1)
                                                               END AS units
                                                        FROM   mw_produce bat
                                                        ) src
                                                  WHERE  src.units IS NOT NULL
                                                  ORDER BY src.good, src.part
                                                  ) bat
                                           GROUP BY bat.part
                                           ORDER BY bat.part
                                           )                      bld ON bld.part    = prd.produce

                          -- by here it is only sensible to use 'Materials' or any heading under that one, eg. Minerals, Reaction Materials, Advanced Moon Materials, Polymer Materials
                          WHERE (utils.keywd(prt.ident, :keyword) = utils.n_get('k_numeric_true')  OR :keyword IS NULL)

                          ORDER BY prd.good, prd.part
                          )                   mat

         LEFT OUTER JOIN vw_avg_sells_regions sel ON sel.part_id = mat.part_id
         
         WHERE  (sel.region = load_market_data.get_econ_region(p_part_id       => sel.part_id
                                                              ,p_direction     => sel.direction
                                                              ,p_local_regions => :local_buy)    OR sel.region IS NULL)

         GROUP BY mat.part_id, mat.part, mat.volume, mat.pile, sel.offers_low_range, sel.name_region) fin
         

  WHERE  (0 < fin.quantity_copy - fin.pile   OR :short IS NULL)
         
  ORDER BY fin.part
  ;






  SELECT -- How does Ore and their variants compare on their underlying minerals?
/*
    This is the same ranking that you get on the famous site http://ore.cerlestes.de/#site:ore
    Except here you also have the Ore Variants
*/
         DISTINCT
         INITCAP(utils.readable_ore(sel.label_ore))  AS ore
        ,        sel.reprocess_normalized            AS repcor
        ,INITCAP(sel.label_mineral)                  AS mineral
        ,TO_CHAR( sel.bids_high_range, '990G990D99') AS bid
        ,INITCAP(sel.name_region)                    AS region

         -- Iskworth with a Fully Pimped Prospect 2x Deep Core Miners, Tech 1 Crystals
        ,TO_CHAR(SUM(ROUND(sel.reprocess_normalized
                          *sel.bids_high_range))
                 OVER (PARTITION BY sel.label_ore)
                ,'9G990G990')                         AS value_index
  
  FROM  (SELECT ore.label              AS label_ore
               ,ore.volume
               ,:yield_m3 / ore.volume      AS amount_normalized
               ,cmp.quantity_true_pos
               ,cmp.formula_bp_orig
               ,utils.calculate(REPLACE(REPLACE(cmp.formula_bp_orig, ':UNITS', :yield_m3 / ore.volume), ',', '.')) AS reprocess_normalized
               ,mnr.label              AS label_mineral
               ,buy.bids_high_range
               ,buy.name_region
        
         FROM       part                ore
         INNER JOIN mw_produce          cmp ON cmp.good_id = ore.ident
         INNER JOIN part                mnr ON mnr.ident   = cmp.part_id
         INNER JOIN vw_avg_buys_regions buy ON buy.part_id = mnr.ident
        
         WHERE  utils.keywd(ore.ident, 'ORE') = 1
         AND    buy.name_region            LIKE '%'|| UPPER(:sell_region) ||'%') sel
        
  ORDER BY value_index DESC
          ,ore
          ,mineral
;







  SELECT -- WHAT BLUEPRINT to Invent/Reverse Engineer next?
/*    
    Though only shows the number of Blueprint Items and One Print may have many runs:
    - Tech 2 Cruisers, Battlecruisers   Up to  2 Runs using Accelerant Decryptor                        Over 2 times faster Copy Run Acquisition, slightly lower ME
    - Siege Modules                     Up to 11 Runs using Accel..                                     Accels conveniently lying around..
    - Tech 3 Subsystems and Hulls       Up to 10 Runs using Process Decryptor on Malfunctioning Relic   Fair price, allows considerable ME both through the print and accross prints 
*/
         prt.label, prt.pile
        ,ind.installer_name, ind.blueprint_type_name, ind.runs, ind.licensed_runs, ind.probability
        ,ind.date_end - SYSDATE AS ready_in_days

  FROM        part prt

  LEFT OUTER JOIN (SELECT lin.installer_name
                         ,lin.blueprint_type_name
                         ,lin.runs
                         ,lin.licensed_runs
                         ,lin.probability
                         ,lin.product_type_id
                         --,lin.product_type_name
                        
                         ,TO_TIMESTAMP(lin.date_end, 'YYYY-MM-DD HH24:MI:SS')
                         +(CAST(SYSTIMESTAMP AS TIMESTAMP)                               -- Host TZ
                          -CAST(SYSTIMESTAMP AT TIME ZONE 'Europe/London' AS TIMESTAMP)) -- Game Servers TZ
                         AS date_end
                        
                                
                   FROM       cache_industry_jobs cch
                   INNER JOIN XMLTABLE('for $i in //eveapi/result/rowset/row
                                        return $i'
                                       PASSING cch.xdoc
                                       COLUMNS job_id                      VARCHAR2( 10) PATH '@jobID'
                                              --,installer_id                VARCHAR2( 10) PATH '@installerID'
                                              ,installer_name              VARCHAR2( 50) PATH '@installerName'
                                              --,facility_id                 VARCHAR2( 20) PATH '@facilityID'
                                              --,solar_system_id             VARCHAR2( 10) PATH '@solarSystemID'
                                              --,solar_system_name           VARCHAR2(100) PATH '@solarSystemName'
                                              --,station_id                  VARCHAR2( 20) PATH '@stationID'
                                              ,activity_id                 INTEGER       PATH '@activityID'          -- 1 Manufacturing, 3 Time Efficiency Research, 4 Material Efficiency Research, 8 Invention...
                                              ,blueprint_id                VARCHAR2( 20) PATH '@blueprintID'
                                              ,blueprint_type_id           VARCHAR2( 10) PATH '@blueprintTypeID'
                                              ,blueprint_type_name         VARCHAR2(100) PATH '@blueprintTypeName'
                                              --,blueprint_location_id       VARCHAR2( 20) PATH '@blueprintLocationID'
                                              --,output_location_id          VARCHAR2( 20) PATH '@outputLocationID'
                                              ,runs                        INTEGER       PATH '@runs'
                                              --,cost                        VARCHAR2( 10) PATH '@cost'
                                              --team_id   PATH   '@teamID'
                                              ,licensed_runs               INTEGER       PATH '@licensedRuns'
                                              ,probability                 VARCHAR2( 20) PATH '@probability'
                                              ,product_type_id             VARCHAR2( 10) PATH '@productTypeID'
                                              ,product_type_name           VARCHAR2(100) PATH '@productTypeName'
                                              --,status                      INTEGER       PATH '@status'
                                              --,time_seconds                INTEGER       PATH '@timeInSeconds'
                                              --,date_start                  VARCHAR2( 20) PATH '@startDate'
                                              --,date_paused                 VARCHAR2( 20) PATH '@pausedDate'
                                              ,date_end                    VARCHAR2( 20) PATH '@endDate'
                                              --,date_completed              VARCHAR2( 20) PATH '@completedDate'
                                              --,completer_id                VARCHAR2( 10) PATH '@completedCharacterID'
                                              --,successful_runs             INTEGER       PATH '@successfulRuns'
                  
                                              ) lin ON 1=1
                                           
                   WHERE  lin.activity_id = 8) ind ON ind.product_type_id = prt.eveapi_part_id

  WHERE  utils.keywd(prt.ident, 'BLUEPRINTS') = utils.n_get('k_numeric_true')
  AND    utils.keywd(prt.ident, 'CONTRACTS') <> utils.n_get('k_numeric_true')  

  ORDER BY prt.pile  ASC NULLS FIRST
          ,prt.label ASC
  ;







/*
    Illustrate the concept of Practical Price

    Lowest Offer:          lowest price available, though might be only few available and so not very reliable info
    Best Practical:        a more likely price when you need to buy sufficient quantities to actually build something
    Avg Low all regions:   average out all regions Best Practicals
    
    Params, eg.:
      Part:    TRITANIUM
      Regions: NOT NULL to show source data (also best_practical and offers_low_range becomes equal)
*/
  SELECT INITCAP(  prt.label)                AS part
        ,      MIN(agr.lowest_offer)         AS lowest_offer
        ,      MIN(agr.offers_low_range)     AS best_practical
        ,ROUND(AVG(agr.offers_low_range), 2) AS avg_low_all_regions
        ,CASE
           WHEN :regions IS NOT NULL THEN INITCAP(agr.name_region)
         END AS regions
  
  FROM       part                 prt
  INNER JOIN vw_avg_sells_regions agr ON agr.part_id = prt.ident
  
  WHERE  prt.label LIKE '%'|| UPPER(:part) ||'%'
  
  GROUP BY prt.label
          ,CASE
             WHEN :regions IS NOT NULL THEN INITCAP(agr.name_region)
           END

  ORDER BY avg_low_all_regions ASC;





  SELECT prt.label, sel.*
  FROM       vw_avg_sells_regions sel
  INNER JOIN part                 prt ON prt.ident = sel.part_id
  WHERE  prt.label LIKE UPPER(:part)
  AND    sel.region   = (SELECT eveapi_region_id FROM region
                         WHERE  name_region = :region OR :region IS NULL)
  ORDER BY sel.offers_low_range ASC;
