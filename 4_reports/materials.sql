/*
    What's the CHEAPest Region for HIGH FLOW items?
    Everyone needs these input, incl. arbitrageurs, who might then become our customers.    
    
    Price/Distance Convenience:
    - how param :current_region  compares to  Query Result
    - how Query Result           compares to  Best Price in the Known EVE Universe
    As % since it helps better to compare/estimate Profit Margins
*/
  SELECT INITCAP(CASE WHEN utils.keywd(prt.ident, 'ORE') = utils.f_get('k_numeric_true') THEN
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
*/
        ,TO_CHAR( CEIL(SUM(cmp.quantity)                              )       ,'990G990G990G990'    ) AS quantity
        ,TO_CHAR( CEIL(SUM(cmp.quantity)        * sel.offers_low_range)       ,'990G990G990G990'    ) AS expense
        ,TO_CHAR( CEIL(SUM(cmp.quantity)        * prt.volume          )       ,    '990G990G990'    ) AS volume
        ,TO_CHAR(          prt.pile                                           ,'990G990G990G990'    ) AS pile

  FROM            part                 prt
       INNER JOIN vw_avg_sells_regions sel ON sel.part_id = prt.ident
  LEFT OUTER JOIN composite            cmp ON cmp.part_id = prt.ident -- give all items, regadrless whether decided to use in prod, like Planetary and Moon Materials and Decryptors


  WHERE (   utils.keywd(prt.ident, 'MATERIALS')          = utils.f_get('k_numeric_true')
         OR utils.keywd(prt.ident, 'RESEARCH EQUIPMENT') = utils.f_get('k_numeric_true'))
         
  AND       utils.keywd(prt.ident, UPPER(:keyword))      = utils.f_get('k_numeric_true')

--  AND   (inp.part                                       IS  NOT NULL   OR :every  IS NOT NULL)  
  AND    sel.offers_low_range * sel.samples              >  load_market_data.v_get('k_notable_supply_part')
  AND    sel.region                                      =  load_market_data.get_econ_region(p_part_id       => prt.ident
                                                                                            ,p_direction     => sel.direction
                                                                                            ,p_local_regions => :buy_local)
  
  GROUP BY prt.ident, prt.label, prt.volume, prt.pile, sel.offers_low_range, sel.name_region
  ORDER BY part
  ;






/*
    Shop list: Show me in a Single Query the required materials to build a diverse set of products.    
    Dont want to do many queries and somehow copy-cahche those results somewhere - what does that even mean?

    Sample list: 3x{huginn,pilgrim,sacrilege}
*/
  SELECT :list_a ||' '|| :list_b ||' '|| :list_c         AS params

        ,part--, origin, race
        ,INITCAP(:keyword)                               AS keyword
        ,TO_CHAR(quantity_orig,    '990G990G990G990')    AS quantity_orig -- here as backup to illustrate material consumption on Copies over Originals
        ,TO_CHAR(quantity_copy,    '990G990G990G990')    AS quantity_copy
        ,TO_CHAR(pile,             '990G990G990G990')    AS pile
        ,TO_CHAR(short,            '990G990G990G990')    AS short_copy
        ,TO_CHAR(offers_low_range, '990G990G990G990D99') AS quote
        ,name_region                                     AS region

        ,ROUND(      short * volume 
                    /load_market_data.f_get('k_dstful')
                    *100, 2)                             AS item_dst_cargo
        
        ,ROUND(SUM(  short * volume
                    /load_market_data.f_get('k_dstful')
                    *100)
               OVER (ORDER BY 1), 1)                     AS total_dst_cargo


  FROM  (SELECT         mat.part_id
               ,INITCAP(mat.part)                      AS part
               ,        mat.volume
               ,        mat.pile
               ,        sel.offers_low_range
               ,INITCAP(sel.name_region)               AS name_region

               ,SUM(    mat.quantity_true_pos_bp_orig) AS quantity_orig
               ,SUM(    mat.quantity_true_pos_bp_copy) AS quantity_copy

               ,CASE
                  WHEN 0 < SUM(mat.quantity_true_pos_bp_copy) - mat.pile THEN
                    SUM(mat.quantity_true_pos_bp_copy) - mat.pile
                END                                    AS short
              
         FROM           (SELECT src.produce, src.good, src.part_id, src.part, src.pile, src.volume


------------------------------- the High Fidelity way: from Blueprint Copies. Leaving :bpc_runs to NULL makes it work just like Original Blueprints
                               ,utils.calculate(                                          FLOOR(src.job_runs / NVL(:bpc_runs, src.job_runs))   -- how many Full BPCs?                               
                                   ||' * '||    REPLACE(src.formula_bp_orig, ':JOB_RUNS',                      NVL(:bpc_runs, src.job_runs)  )
                                   ||' + '||    REPLACE(src.formula_bp_orig, ':JOB_RUNS', MOD  (src.job_runs,  NVL(:bpc_runs, src.job_runs)))) -- plus how many Job Runs on one further BPC
                                                                                                                                               AS quantity_true_pos_bp_copy

                                -- the faster way: from Original Blueprints, but too optimistic to use on Blueprint Copies
                               ,utils.calculate(REPLACE(src.formula_bp_orig, ':JOB_RUNS',       src.job_runs                                )) AS quantity_true_pos_bp_orig
-------------------------------
                                
                         FROM  (SELECT pdc.produce
                                      ,pdc.good
                                      ,prt.ident           AS part_id
                                      ,prt.label           AS part
                                      ,prt.volume
                                      ,prt.pile
                                      ,pdc.formula_bp_orig

                                      ,CASE
                                       -- format: Nx { [Elements, comma delimited] } eg. 3x{huginn,pilgrim,sacrilege}
                                       --WHEN                Produce   EXISTS in Our List                      THEN do given Job Runs
                                         WHEN utils.elem(pdc.produce, :list_a) = utils.v_get('k_numeric_true') THEN SUBSTR(:list_a, 1, INSTR(:list_a, 'x')-1)
                                         WHEN utils.elem(pdc.produce, :list_b) = utils.v_get('k_numeric_true') THEN SUBSTR(:list_b, 1, INSTR(:list_b, 'x')-1)
                                         WHEN utils.elem(pdc.produce, :list_c) = utils.v_get('k_numeric_true') THEN SUBSTR(:list_c, 1, INSTR(:list_c, 'x')-1)
                                         --...
                                       END                 AS job_runs

                                FROM       vw_produce_leaves pdc
                                INNER JOIN part              prt ON prt.ident = pdc.part_id
                              
                                WHERE  (utils.keywd(prt.ident, UPPER(:keyword)) = utils.f_get('k_numeric_true')   OR :keyword IS NULL)
                                ) src
                        
                         WHERE  src.job_runs IS NOT NULL
                         ORDER BY src.produce, src.good, src.part) mat


         LEFT OUTER JOIN vw_avg_sells_regions                        sel ON sel.part_id = mat.part_id
         
         WHERE  (sel.region = load_market_data.get_econ_region(p_part_id       => sel.part_id
                                                              ,p_direction     => sel.direction
                                                              ,p_local_regions => :local_buy)    OR sel.region IS NULL)

         GROUP BY mat.part_id, mat.part, mat.volume, mat.pile, sel.offers_low_range, sel.name_region)

  ORDER BY part;




/*
    Jobs list: What Intermediary Components needed to Build set of Produces?
    Copy below and Erase when Installing to keep track on remaining jobs.
    
*/
  SELECT TO_CHAR(fin.short, '9G999G990') ||'  '|| INITCAP(fin.label) AS line
  
  FROM  (SELECT src.*
               ,utils.calculate(quantity_true_pos_bp_copy) AS quantity
               
               ,utils.calculate(quantity_true_pos_bp_copy)
               -src.pile                                   AS short
              
         FROM  (SELECT prd.produce, prt.*
                      ,                                                       FLOOR(par.job_runs / par.bpc_runs)  
                       ||' * '||    REPLACE(prd.formula_bp_orig, ':JOB_RUNS',                      par.bpc_runs )
                       ||' + '||    REPLACE(prd.formula_bp_orig, ':JOB_RUNS', MOD  (par.job_runs,  par.bpc_runs)) AS quantity_true_pos_bp_copy
       
                FROM        mw_produce   prd
                INNER JOIN  part         prt ON prt.label = prd.part
                INNER JOIN (SELECT                SUBSTR(:list_a, 1, INSTR(:list_a, 'x') -1)  AS job_runs
                                  ,NVL(:bpc_runs, SUBSTR(:list_a, 1, INSTR(:list_a, 'x') -1)) AS bpc_runs
                            FROM   dual) par ON 1=1
            
                WHERE (utils.keywd(prt.ident, 'ADVANCED COMPONENTS')  = utils.f_get('k_numeric_true') OR
                       utils.keywd(prt.ident, 'SUBSYSTEM COMPONENTS') = utils.f_get('k_numeric_true'))
            
                AND    utils.elem(prd.produce, :list_a)               = utils.f_get('k_numeric_true')) src) fin

  WHERE  0 < fin.short
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





  SELECT *
  FROM   market_order
  WHERE  part      LIKE UPPER(:part)
  AND    direction    = 'SELL'
  AND    region       = (SELECT eveapi_region_id FROM region
                         WHERE  name_region = :region)
  ORDER BY price ASC;
