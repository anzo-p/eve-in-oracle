  SELECT -- WHAT TO BUILD and where to sell
/*
    One way to yield on this is to build 5-10 different kinds of products out of those that show higher profits,
    and keep filling the shelves as they sell. Another valuable info is which products do not seem profitable at the moment.
*/
         INITCAP(fin.produce) AS produce, INITCAP(fin.name_region) AS region
        ,            fin.sel_samples                                                                                    AS sells
        ,TO_CHAR(                        fin.lowest_offer,                                           '990G990G990G990') AS lowest_offer
        ,TO_CHAR(                        fin.offers_low_range,                                       '990G990G990G990') AS offers_low_range
        ,            fin.buy_samples                                                                                    AS buys
        ,TO_CHAR(                        fin.highest_bid,                                            '990G990G990G990') AS highest_bid
        ,TO_CHAR(                        fin.bids_high_range,                                        '990G990G990G990') AS bids_high_range
        ,TO_CHAR(                                             fin.mid_spread,                        '990G990G990G990') AS mid_spread
        ,TO_NUMBER( :adjust                                                                                           ) AS adj
        ,TO_CHAR(    fin.mid_spread  + ((fin.lowest_offer   - fin.mid_spread)      * :adjust/100),   '990G990G990G990') AS my_adjusted_offer
        ,TO_CHAR(                                             fin.mid_spread_jita,                   '990G990G990G990') AS mid_spread_jita
        ,TO_CHAR(                                                                    fin.breakeven,  '990G990G990G990') AS break
        ,TO_CHAR(    fin.buy_samples *  fin.bids_high_range,                                         '990G990G990G990') AS demand


/*
         Adjust as percentage between highest_bid (-100), mid_spread (0), and lowest_offer (100), eg.:

            bid        mid       offer
             |          |          |   -100: immediate cash-in by selling to highest bidder
             |XXXXXXXXXX|          |      0: assume mid_spread
             |XXXXXXXXXX|XXXXX     |     50: between mid_spread and lowest_offer
             |XXXXXXXXXX|XXXXXXXXX |     90: barely undercut the lowest_offer... ofc takes progressively longer to sell
         
         The greatest of { mid spread at Jita, your adjusted offer } becomes Margin against Breakeven.
         And that margin is also made the Sort Order.
*/
        ,utils.per_cent(p_share    => GREATEST(fin.mid_spread       + ((fin.lowest_offer - fin.mid_spread) * :adjust/100)
                                              ,fin.mid_spread_jita)
                                     -fin.breakeven
                       ,p_total    => fin.breakeven
                       ,p_decimals => 1)                                                                                AS margin


  FROM  (SELECT brk.produce
               ,brk.outcome_units
               ,sel.name_region
               ,sel.samples          AS sel_samples
               ,sel.lowest_offer
               ,sel.offers_low_range
               ,buy.samples          AS buy_samples
               ,buy.highest_bid
               ,buy.bids_high_range

               ,(sel.lowest_offer
                +buy.highest_bid) /2 AS mid_spread
               
               ,brk.breakeven


               ,(SELECT ROUND((MIN(s_sel.lowest_offer) + MAX(s_buy.highest_bid)) /2, 2)
                 FROM       vw_avg_sells_regions s_sel
                 INNER JOIN vw_avg_buys_regions  s_buy ON s_sel.part_id = s_buy.part_id
                                                      AND s_sel.region  = s_buy.region
                 WHERE  s_sel.part_id = brk.produce_id
                 AND    s_sel.region  = 10000002) AS mid_spread_jita -- at The Forge, most likely Jita then


         FROM  (SELECT pdc.produce_id, pdc.produce, goo.outcome_units
         
                      ,load_market_data.get_breakeven(SUM(agr.offers_low_range
                                                         *utils.calculate(REPLACE(pdc.formula_bp_orig
                                                                                 ,':UNITS'
                                                                                 ,goo.outcome_units)) -- for simplicity lets assume we build only one Unit
                                                         /goo.outcome_units)) AS breakeven            -- and for comparison also when one Run builds many units
                                                         
                                                          
                FROM       vw_produce_leaves    pdc
                INNER JOIN part                 goo ON goo.ident   = pdc.produce_id
                INNER JOIN part                 prt ON prt.ident   = pdc.part_id
                INNER JOIN vw_avg_sells_regions agr ON agr.part_id = prt.ident
                

                WHERE  pdc.produce                               LIKE  '%'|| UPPER(:produce) ||'%'

                -- produce belongs to this group
                AND   (utils.keywd(pdc.produce_id, UPPER(:keyword)) =  utils.f_get('k_numeric_true')   OR :keyword IS NULL)
                
                -- produce not in these groups
                AND    utils.keywd(pdc.produce_id, 'ORE')          <>  utils.f_get('k_numeric_true')
                AND    utils.keywd(pdc.produce_id, 'BLUEPRINTS')   <>  utils.f_get('k_numeric_true')

                -- produce doesnt have a part in these groups
                AND                                        NOT EXISTS (SELECT 1 --*
                                                                       FROM       keyword     kwd
                                                                       INNER JOIN keyword_map kmp ON kmp.keyword_id = kwd.ident
                                                                       INNER JOIN composite   cmp ON cmp.part_id    = kmp.part_id
                                                                       WHERE  cmp.good_id =  pdc.produce_id
                                                                       AND    kwd.label  IN ('CONTRACTS')) -- { Faction Ships, Named Modules }

                AND    agr.region                                   =  load_market_data.get_econ_region(p_part_id       => prt.ident
                                                                                                       ,p_direction     => agr.direction
                                                                                                       ,p_local_regions => :local_buy)

                GROUP BY pdc.produce_id, pdc.produce, goo.outcome_units) brk
                

         -- sells and buys may OUTER JOIN to Product data, but they must INNER JOIN together because we need mid_spread
         LEFT OUTER JOIN vw_avg_sells_regions sel ON  sel.part_id = brk.produce_id
              INNER JOIN vw_avg_buys_regions  buy ON  buy.part_id = brk.produce_id
                                                 AND  buy.region  = sel.region

         LEFT OUTER JOIN local_regions        loc ON  loc.region  = sel.region
         
         -- This must go together with that LEFT OUTER JOIN
         WHERE  (      loc.region                            IS NOT NULL
                 OR   :local_sell                            IS NULL)

         AND   ((    1=1 -- comment out any of the below and still works
--                 AND ( buy.bids_high_range * buy.samples      > load_market_data.f_get('k_notable_demand_good')   ) -- capital bound in buy orders means interest
--                 AND ( brk.breakeven       / buy.highest_bid <  load_market_data.f_get('k_buys_max_below_break')  ) -- conflicts with high :adjust
--                 AND ( sel.lowest_offer    / brk.breakeven    > load_market_data.f_get('k_sells_min_above_break') ) -- basically rules out negative margins 
                )
                 OR  :produce IS NOT NULL) -- obviously you want full results with specific Searches regardless whether theyre promising or not

        ) fin

  ORDER BY utils.per_cent(p_share => GREATEST(fin.mid_spread       + ((fin.lowest_offer - fin.mid_spread) * :adjust/100)
                                             ,fin.mid_spread_jita)
                                    -fin.breakeven
                         ,p_total => fin.breakeven) DESC
  ;







  SELECT -- BREAKEVEN FOR PRODUCE if all input materials bought at low, and FROM WHERE TO BUY them
/*
    You will want to be MORE Price Sensitive with materials that constitute to higher pct (%) of the goods_total.
    Also you may make generous profits even if you are LESS price sensitive with the low pct materials.
    Better yet, as these prices actually are high-/low-end ranges, some materials you will likely get even cheaper.
    

    The CEIL()s/FLOOR()s makes it hard to implement quantities for one unit of { Ore, Fuel Blocks, Ammo, R.A.M., ... } (without sacrificing readability much)
    They all outcome in many units which renders the "True Quantity for One Unit" an imaginary concept.    
    - Ore, set          :units = 100, :bpc_runs = NULL
    - Fuel Blocks, set  :units =  40, :bcp_runs = NULL
    - Ammo, set         :units, :bpd_runs from your Faction Blueprint Copy
*/
         :units ||'x '|| INITCAP(SUBSTR(fin.produce, 1, 22))              AS produce
        ,                INITCAP(SUBSTR(fin.part,    1, 22))              AS part
  
        ,TO_CHAR(  fin.quantity,                        '990G990G990D99') AS quantity
        ,TO_CHAR(  fin.pile,                            '990G990G990D99') AS pile

        ,CASE WHEN fin.quantity - fin.pile > 0 THEN
           TO_CHAR(fin.quantity - fin.pile,             '990G990G990D99')
         END                                                              AS short

--        ,TO_CHAR(  fin.short_volume,                    '990G990G990D99') AS vol_short

         -- most matetials you will likely want to haul with your Deep Space Transporter (DST), uncomment others as necessary
        ,of_cargo_deeptransport                                           AS dst -- of_cargo_freighter AS frg, of_cargo_jump_freighter AS jf

        ,TO_CHAR(  fin.offers_low_range,                '990G990G990D99') AS quote
        ,INITCAP(SUBSTR(fin.name_region, 1, 15)                         ) AS region
        ,TO_CHAR(  fin.items_total,                 '990G990G990G990'   ) AS items_tot
        ,                                                                    pct
        ,TO_CHAR(  fin.goods_total,                 '990G990G990G990'   ) AS goods_tot
        ,TO_CHAR(  fin.breakeven,                   '990G990G990G990'   ) AS break
        ,TO_CHAR(  fin.just_buy_it,                 '990G990G990G990'   ) AS just_buy_it

         -- unitwise fields necesary to compare Fuel Blocks, Ore.. against market; decimals necessary for most Ore
        ,TO_CHAR(  fin.goods_total        / :units,     '990G990G990D99') AS goods_unit
--        ,TO_CHAR(  fin.goods_total * 0.96,              '990G990G990'   ) AS dsconut_four
        ,TO_CHAR(  fin.goods_total * 0.93 / :units,     '990G990G990D99') AS dsconut_seven
        ,TO_CHAR(  fin.breakeven          / :units,     '990G990G990D99') AS break_unit
        ,TO_CHAR(  fin.just_buy_it        / :units,     '990G990G990D99') AS just_buy_one


  FROM  (SELECT src.produce, src.part, src.pile, src.offers_low_range, src.name_region
  
               ,                                                                SUM(src.quantity)                                          AS quantity
               ,                                                  src.volume *  SUM(src.quantity)                                          AS volume
               
               ,CASE WHEN src.pile < SUM(src.quantity) THEN       src.volume * (SUM(src.quantity) - src.pile)
                END                                                                                                                        AS short_volume

               ,CASE WHEN src.pile < SUM(src.quantity) THEN ROUND(src.volume * (SUM(src.quantity) - src.pile) / load_market_data.f_get('k_dstful') *100, 1)
                END                                                                                                                        AS of_cargo_deeptransport

               ,CASE WHEN src.pile < SUM(src.quantity) THEN ROUND(src.volume * (SUM(src.quantity) - src.pile) / load_market_data.f_get('k_jumpfreightful') *100, 1)
                END                                                                                                                        AS of_cargo_jump_freighter

               ,                             ROUND(     src.offers_low_range *  SUM(src.quantity))                                         AS items_total
               ,                             ROUND(     src.offers_low_range *  SUM(src.quantity)
                                                  /(SUM(src.offers_low_range *  SUM(src.quantity)) OVER (PARTITION BY src.produce))  *100) AS pct
               ,                             ROUND( SUM(src.offers_low_range *  SUM(src.quantity)) OVER (PARTITION BY src.produce))        AS goods_total

               ,CEIL(load_market_data.get_breakeven(SUM(src.offers_low_range *  SUM(src.quantity)) OVER (PARTITION BY src.produce)))       AS breakeven


               ,(SELECT sub.offers_low_range * :units
                 FROM   vw_avg_sells_regions sub
                 WHERE  sub.part_id = src.produce_id
                 AND    sub.region  = load_market_data.get_econ_region(p_part_id       => src.produce_id
                                                                      ,p_direction     => 'SELL'
                                                                      ,p_local_regions => :local_sell)  OR sub.region IS NULL) AS just_buy_it


         FROM  (SELECT pdc.produce_id
                      ,pdc.produce
                      --,pdc.good_id
                      --,pdc.good
                      --,pdc.part_id
                      ,pdc.part
                      ,prt.volume
                      ,prt.pile
                      ,sel.region
                      ,sel.offers_low_range
                      ,sel.name_region
                     
                      ,                par.need_full_bpcs ||' * '|| REPLACE(pdc.formula_bp_orig, ':UNITS', par.bpc_runs)
                                                          ||' + '|| REPLACE(pdc.formula_bp_orig, ':UNITS', par.need_short_runs)  AS formula  -- DEBUG

                      ,utils.calculate(par.need_full_bpcs ||' * '|| REPLACE(pdc.formula_bp_orig, ':UNITS', par.bpc_runs)
                                                          ||' + '|| REPLACE(pdc.formula_bp_orig, ':UNITS', par.need_short_runs)) AS quantity
              

                FROM             vw_produce_leaves    pdc
                INNER JOIN       part                 prt ON prt.ident   = pdc.part_id 

                INNER JOIN      (SELECT                               :units   AS units
                                       ,               NVL(:bpc_runs, :units)  AS bpc_runs
                                       ,FLOOR(:units / NVL(:bpc_runs, :units)) AS need_full_bpcs
                                       ,MOD  (:units,  NVL(:bpc_runs, :units)) AS need_short_runs
                                 FROM   dual)         par ON 1=1

                LEFT OUTER JOIN  vw_avg_sells_regions sel ON sel.part_id = prt.ident

              
                WHERE  pdc.produce LIKE '%'|| UPPER(:produce) ||'%'
                AND   (sel.region     = load_market_data.get_econ_region(p_part_id       => prt.ident
                                                                        ,p_direction     => sel.direction
                                                                        ,p_local_regions => :local_buy)    OR sel.region IS NULL)) src
                                                                     
         GROUP BY src.produce_id, src.produce, src.part, src.volume, src.pile, src.offers_low_range, src.name_region) fin

  ORDER BY fin.produce
          ,fin.items_total  DESC
          ,fin.part;

