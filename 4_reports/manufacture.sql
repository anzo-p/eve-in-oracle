/*
    WHAT TO BUILD and where to sell?

    One way to yield on this is to build 5-10 different kinds of products out of those that show higher profits,
    and keep filling the shelves as they sell. Another valuable info is which products do not seem profitable at the moment.
*/
  SELECT INITCAP(produce) AS produce, INITCAP(name_region) AS region
        ,            sel_samples                                                                          AS sells
        ,TO_CHAR(                   lowest_offer,                                      '990G990G990G990') AS lowest_offer
        ,TO_CHAR(                   offers_low_range,                                  '990G990G990G990') AS offers_low_range
        ,            buy_samples                                                                          AS buys
        ,TO_CHAR(                   highest_bid,                                       '990G990G990G990') AS highest_bid
        ,TO_CHAR(                   bids_high_range,                                   '990G990G990G990') AS bids_high_range
        ,TO_CHAR(                                    mid_spread,                       '990G990G990G990') AS mid_spread
        ,TO_NUMBER( :adjust                                                                             ) AS adj
        ,TO_CHAR(    mid_spread + ((lowest_offer   - mid_spread)      * :adjust/100),  '990G990G990G990') AS my_adjusted_offer
        ,TO_CHAR(                                    mid_spread_jita,                  '990G990G990G990') AS mid_spread_jita
        ,TO_CHAR(                                                       breakeven,     '990G990G990G990') AS break
        ,TO_CHAR(    buy_samples *  bids_high_range,                                   '990G990G990G990') AS demand


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
        ,utils.per_cent(p_share    => mid_spread + ((lowest_offer - mid_spread) * :adjust/100) - breakeven
                       ,p_total    => breakeven
                       ,p_decimals => 1)                                                                  AS margin


  FROM  (SELECT brk.produce, sel.name_region, brk.breakeven
               ,sel.samples AS sel_samples, sel.lowest_offer, sel.offers_low_range
               ,buy.samples AS buy_samples, buy.highest_bid, buy.bids_high_range
               ,(sel.lowest_offer + buy.highest_bid) /2 AS mid_spread


               ,(SELECT ROUND((MIN(s_sel.lowest_offer) + MAX(s_buy.highest_bid)) /2, 2)
                 FROM       vw_avg_sells_regions s_sel
                 INNER JOIN vw_avg_buys_regions  s_buy ON s_sel.part_id = s_buy.part_id
                                                      AND s_sel.region  = s_buy.region
                 WHERE  s_sel.part_id = brk.produce_id
                 AND    s_sel.region  = 10000002) AS mid_spread_jita -- at The Forge, Most likely Jita then


         FROM  (SELECT pdc.produce_id, pdc.produce
         
                      ,load_market_data.get_breakeven(SUM(agr.offers_low_range
                                                         *utils.calculate(REPLACE(pdc.formula_bp_orig
                                                                                 ,':JOB_RUNS'
                                                                                 ,1)))) -- for simplicity lets assume we build only one Unit
                                                                                 AS breakeven
                                                          
                FROM       mw_produce           pdc
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

                GROUP BY pdc.produce_id, pdc.produce) brk
                

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

        ) lst

  ORDER BY utils.per_cent(p_share => GREATEST(lst.mid_spread       + ((lst.lowest_offer - lst.mid_spread) * :adjust/100)
                                             ,lst.mid_spread_jita)
                                    -lst.breakeven
                         ,p_total => lst.breakeven) DESC
  ;







/*
    Whats the BREAKEVEN FOR PRODUCE if all input materials bought at low? And from where to buy them cheapest?

    You will want to be MORE Price Sensitive with materials that constitute to higher pct (%) of the goods_total.
    Also you may make generous profits even if you are LESS price sensitive with the low pct materials.
    Better yet, as these prices actually are high-/low-end ranges, some materials you will likely get even cheaper.
*/
  SELECT INITCAP(SUBSTR(fin.produce, 1, 22)) AS produce, fin.job_runs AS n, INITCAP(SUBSTR(fin.part, 1, 22)) AS part
  
        ,TO_CHAR(  fin.quantity,               '990G990G990D99') AS quantity
        ,TO_CHAR(  fin.pile,                   '990G990G990D99') AS pile

        ,CASE WHEN fin.quantity - fin.pile > 0 THEN
           TO_CHAR(fin.quantity - fin.pile,    '990G990G990D99')
         END                                                     AS short

        ,TO_CHAR(  fin.short_volume,           '990G990G990D99') AS vol_short

         -- most matetials you will likely want to haul with your Deep Space Transporter (DST), uncomment others as necessary
        ,of_cargo_deeptransport                                  AS dst -- of_cargo_freighter AS frg, of_cargo_jump_freighter AS jf

        ,TO_CHAR(  fin.offers_low_range,       '990G990G990D99') AS quote
        ,INITCAP(SUBSTR(fin.name_region, 1, 15)                ) AS region
        ,TO_CHAR(  fin.items_total,        '990G990G990G990'   ) AS items_tot
        ,                                                           pct
        ,TO_CHAR(  fin.goods_total,        '990G990G990G990'   ) AS goods_tot
        ,TO_CHAR(  fin.goods_total * 0.96, '990G990G990G990'   ) AS disconut_four
        ,TO_CHAR(  fin.goods_total * 0.93, '990G990G990G990'   ) AS disconut_seven
        ,TO_CHAR(  fin.breakeven,          '990G990G990G990'   ) AS break
        ,TO_CHAR(  fin.just_buy_it,        '990G990G990G990'   ) AS just_buy_it


  FROM  (SELECT src.produce, src.part, src.pile, src.job_runs, src.offers_low_range, src.name_region
  
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


               ,(SELECT sub.offers_low_range * src.job_runs
                 FROM   vw_avg_sells_regions sub
                 WHERE  sub.part_id = src.produce_id
                 AND    sub.region  = load_market_data.get_econ_region(p_part_id      => src.produce_id
                                                                     ,p_direction     => 'SELL'
                                                                     ,p_local_regions => :local_sell)  OR sub.region IS NULL) AS just_buy_it


         FROM  (SELECT pdc.produce_id, pdc.produce, pdc.part_id, pdc.part --, pdc.good_id, pdc.good
                      ,pdc.material_efficiency, pdc.consume_rate_true_pos, pdc.quantity_true_pos
                      ,prt.volume, prt.pile, par.job_runs
                     
                      ,utils.calculate(par.need_full_bpcs ||' * '|| REPLACE(pdc.formula_bp_orig, ':JOB_RUNS', par.bpc_runs)
                                                          ||' + '|| REPLACE(pdc.formula_bp_orig, ':JOB_RUNS', par.need_short_runs)) AS quantity
              
                      ,sel.region, sel.offers_low_range, sel.name_region

               
                FROM             mw_produce           pdc
                INNER JOIN       part                 prt ON prt.ident   = pdc.part_id 

                INNER JOIN      (SELECT :job_runs                                    AS job_runs
                                       ,NVL(:bpc_runs, :job_runs)                    AS bpc_runs
                                       ,FLOOR(:job_runs / NVL(:bpc_runs, :job_runs)) AS need_full_bpcs
                                       ,MOD  (:job_runs,  NVL(:bpc_runs, :job_runs)) AS need_short_runs
                                 FROM   dual)         par ON 1=1

                LEFT OUTER JOIN  vw_avg_sells_regions sel ON sel.part_id = prt.ident

              
                WHERE  produce LIKE '%'|| UPPER(:produce) ||'%'
                AND   (sel.region = load_market_data.get_econ_region(p_part_id       => prt.ident
                                                                    ,p_direction     => sel.direction
                                                                    ,p_local_regions => :local_buy)    OR sel.region IS NULL)) src
                                                                     
         GROUP BY src.produce_id, src.produce, src.part, src.volume, src.pile, src.job_runs, src.offers_low_range, src.name_region) fin

  ORDER BY fin.produce
          ,fin.items_total  DESC
          ,fin.part;

