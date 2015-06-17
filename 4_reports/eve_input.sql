
/*
    What's the CHEAPest Region for HIGH FLOW items?
    Everyone needs these input, incl. arbitrageurs, who might then become our customers.
*/
  SELECT INITCAP(          prt.label                                                               ) AS part
        ,INITCAP(          prt.race                                                                ) AS race
        ,TO_CHAR(          prt.pile                                          ,'990G990G990G990'    ) AS pile
        ,:buy_local                                                                                  AS loc
        ,INITCAP(          prt.material_origin                                                     ) AS origin
        ,INITCAP(          sel.name_region                                                         ) AS region
        ,TO_CHAR(                                sel.offers_low_range        ,'990G990G990G990D99' ) AS sellers      -- Carbides and Metamaterials always at their cheapest (total cost %)
        ,TO_CHAR(                                sel.offers_low_range * 1.02 ,'990G990G990G990D99' ) AS premium_two  -- for others, this tiny Premium is OK when more convenient
        ,TO_CHAR(                                sel.offers_low_range * 1.04 ,'990G990G990G990D99' ) AS premium_four -- never pay a higher premium than this for any moon mats
        ,TO_CHAR( CEIL(SUM(inp.quantity)                             )       ,'990G990G990G990'    ) AS quantity
        ,TO_CHAR( CEIL(SUM(inp.quantity)       * sel.offers_low_range)       ,'990G990G990G990'    ) AS expense
        ,TO_CHAR( CEIL(SUM(inp.quantity)       * prt.volume          )       ,    '990G990G990'    ) AS volume

  FROM            part                 prt
       INNER JOIN vw_avg_sells_regions sel ON sel.part = prt.label
  LEFT OUTER JOIN produce              inp ON inp.part = prt.label -- give all items, regadrless whether decided to use in prod, like Planetary and Moon Materials and Decryptors

  WHERE      sel.offers_low_range * sel.samples >  load_market_data.v_get('k_notable_supply_part')
  
  AND   (    inp.part                          IS  NOT NULL                          OR :every  IS NOT NULL)  
  AND   (    prt.material_origin             LIKE  '%'|| UPPER(:origin) ||'%'        OR :origin IS NULL)
  AND   (    prt.class                       LIKE  '%'|| UPPER(:class)  ||'%'        OR :class  IS NULL)

  AND    NVL(prt.material_origin, 'A')   NOT LIKE 'PRODUCE'

  AND        0                                  =   INSTR(NVL(UPPER(:exclude), utils.v_get('k_dummy_string'))
                                                             ,prt.label)

  AND        sel.region                         =   load_market_data.get_econ_region(p_part          => prt.label
                                                                                    ,p_direction     => sel.direction
                                                                                    ,p_local_regions => :buy_local)
  
  GROUP BY prt.label, prt.race, prt.volume, prt.pile, prt.class, prt.material_origin, sel.offers_low_range, sel.name_region
  ORDER BY origin, part
  ;




/*
    Give list of Producables and quantity to build for multiple products with different jobs runs.
*/
  SELECT CASE WHEN :a_list IS NOT NULL THEN :a_qty || 'x{'|| :a_list || '}; ' END ||
         CASE WHEN :b_list IS NOT NULL THEN :b_qty || 'x{'|| :b_list || '}; ' END ||
         CASE WHEN :c_list IS NOT NULL THEN :c_qty || 'x{'|| :c_list || '}; ' END --||
         --CASE WHEN :d_list IS NOT NULL THEN :d_qty || 'x{'|| :d_list || '}; ' END ||
         --CASE WHEN :e_list IS NOT NULL THEN :e_qty || 'x{'|| :e_list || '}; ' END ||
         --CASE WHEN :f_list IS NOT NULL THEN :a_qty || 'x{'|| :f_list || '}; ' END --||

                                                      AS params
        ,part, origin, race        
        ,TO_CHAR(quantity,         '990G990G990G990') AS quantity
        ,TO_CHAR(pile,             '990G990G990G990') AS pile
        ,TO_CHAR(short,            '990G990G990G990') AS short
        ,TO_CHAR(offers_low_range, '990G990G990G990') AS quote
        ,name_region                                  AS region

  FROM  (SELECT INITCAP(mat.part)            AS part
               ,INITCAP(mat.race)            AS race
               ,INITCAP(mat.origin)          AS origin
               ,SUM(    mat.quantity)        AS quantity, mat.pile
               
               ,CASE
                  WHEN 0 < SUM(mat.quantity) - mat.pile THEN
                    SUM(mat.quantity) - mat.pile
                END                          AS short

               ,        sel.offers_low_range
               ,INITCAP(sel.name_region)     AS name_region

              
         FROM           (SELECT src.good, src.subheader, src.part, src.race, src.origin, src.pile
                               ,src.quantity_pos * src.multiplier AS quantity
                        
                         FROM  (SELECT      inp.good
                                      ,     inp.subheader
                                      ,     inp.part
                                      ,     prt.race
                                      ,     prt.material_origin AS origin
                                      ,CEIL(inp.quantity)       AS quantity
                                      ,CEIL(inp.quantity_pos)   AS quantity_pos
                                      ,     prt.pile
                              
                                      ,CASE
                                         WHEN 0 < INSTR(UPPER(:a_list), inp.good) THEN :a_qty
                                         WHEN 0 < INSTR(UPPER(:b_list), inp.good) THEN :b_qty
                                         WHEN 0 < INSTR(UPPER(:c_list), inp.good) THEN :c_qty 
                                         --WHEN 0 < INSTR(UPPER(:d_list), inp.good) THEN :d_qty 
                                         --WHEN 0 < INSTR(UPPER(:e_list), inp.good) THEN :e_qty 
                                         --WHEN 0 < INSTR(UPPER(:f_list), inp.good) THEN :f_qty 
          
                                       END AS multiplier
                              
                                FROM       produce inp
                                INNER JOIN part    prt ON prt.label = inp.part
                              
                                WHERE (0 < INSTR(UPPER(:origin), prt.material_origin)   OR :origin IS NULL)
                                ) src
                        
                         WHERE  src.multiplier IS NOT NULL
                         ORDER BY src.good, src.subheader, src.part) mat


         LEFT OUTER JOIN vw_avg_sells_regions                        sel ON sel.part = mat.part
         
         WHERE  (sel.region = load_market_data.get_econ_region(p_part          => sel.part
                                                              ,p_direction     => sel.direction
                                                              ,p_local_regions => :local_buy)    OR sel.region IS NULL)

         GROUP BY mat.part, mat.race, mat.origin, mat.pile, sel.offers_low_range, sel.name_region)

  ORDER BY origin, part;



/*
    Illustrate the concept of Practical High / Low

    Lowest Offer:     Lowest price available, though might be only few items and so not a very convenient info
    Best Practical:   a more likely price when you need to buy quantities to actually build something meaningful
    Offers Low Range: 
    
    Params, eg.:
      Part:    TRITANIUM
      Regions: NOT NULL to show source data (also best_practical and offers_low_range becomes equal)
*/
  SELECT INITCAP(  prt.label)                AS part
        ,      MIN(agr.lowest_offer)         AS lowest_offer        -- best price in all new eden
        ,      MIN(agr.offers_low_range)     AS best_practical      -- best regional price out of all regions
        ,ROUND(AVG(agr.offers_low_range), 2) AS avg_low_all_regions -- average out all regions best prices
        ,CASE
           WHEN :regions IS NOT NULL THEN INITCAP(agr.name_region)
         END AS regions
  
  FROM       part                 prt
  INNER JOIN vw_avg_sells_regions agr ON agr.part             = prt.label
  
  WHERE  prt.label          IN (UPPER(:part))
  
  GROUP BY prt.label
          ,CASE
             WHEN :regions IS NOT NULL THEN INITCAP(agr.name_region)
           END
  
  ORDER BY part                ASC
          ,avg_low_all_regions ASC;
