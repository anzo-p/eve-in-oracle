/*
    WHAT TO BUILD and where to sell?

    One way to yield on this is to build 5-10 different kinds of products out of those that show higher profits,
    and keep filling the shelves as they sell. Another valuable info is which products do not seem profitable at the moment.
*/
  SELECT INITCAP(good) AS good, INITCAP(race) AS rc, INITCAP(name_region) AS region
        
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


  FROM  (SELECT brk.good, brk.race, sel.name_region, brk.breakeven
  
               ,sel.samples AS sel_samples, sel.lowest_offer, sel.offers_low_range, buy.samples AS buy_samples, buy.highest_bid, buy.bids_high_range
               ,(sel.lowest_offer + buy.highest_bid) /2 AS mid_spread


               ,(SELECT ROUND((MIN(s_sel.lowest_offer) + MAX(s_buy.highest_bid)) /2, 2)
                 FROM       vw_avg_sells_regions s_sel
                 INNER JOIN vw_avg_buys_regions  s_buy ON s_sel.part   = s_buy.part
                                                      AND s_sel.region = s_buy.region
                 WHERE  s_sel.part   = brk.good
                 AND    s_sel.region = 10000002) AS mid_spread_jita -- at The Forge, Most likely Jita then


         FROM  (SELECT inp.good, goo.race
               
                      ,load_market_data.get_breakeven(SUM(agr.offers_low_range
                                                         *CASE
                                                            WHEN goo.class LIKE 'COMPONENT - FUEL BLOCK' THEN      inp.quantity_pos -- replace both with inp.quantity when no POS
                                                            ELSE                                              CEIL(inp.quantity_pos)
                                                          END)) AS breakeven
                                                          
                FROM       produce              inp
                INNER JOIN part                 goo ON goo.label = inp.good
                INNER JOIN part                 prt ON prt.label = inp.part
                INNER JOIN vw_avg_sells_regions agr ON agr.part  = prt.label -- notable supply implicit

                WHERE      goo.material_origin   = 'PRODUCE'
                AND        inp.transitive        = 'FALSE'
                AND        inp.good           LIKE '%' || UPPER(:good)  || '%'                       
                AND    NVL(goo.race, 'DUMMY') LIKE '%' || UPPER(:race)  || '%'
               
                AND        agr.region            =  load_market_data.get_econ_region(p_part          => prt.label
                                                                                    ,p_direction     => agr.direction
                                                                                    ,p_local_regions => :local_buy)
                GROUP BY inp.good, goo.race) brk


         -- sells and buys may OUTER JOIN to Product data, but they must INNER JOIN together because we need mid_spread
         LEFT OUTER JOIN vw_avg_sells_regions sel ON  sel.part   = brk.good
              INNER JOIN vw_avg_buys_regions  buy ON  buy.part   = brk.good
                                                 AND  buy.region = sel.region

         LEFT OUTER JOIN local_regions        loc ON  loc.region = sel.region
         

         WHERE  (      loc.region                            IS NOT NULL
                 OR   :local_sell                            IS NULL)

         AND   ((    ( buy.bids_high_range * buy.samples      > load_market_data.f_get('k_notable_demand_good')   )
                 AND ( brk.breakeven       / buy.highest_bid <  load_market_data.f_get('k_buys_max_below_break')  )
                 AND ( sel.lowest_offer    / brk.breakeven    > load_market_data.f_get('k_sells_min_above_break') )
                )

                 OR  :good IS NOT NULL) -- obviously you want full results with specific Searches regardless whether theyre promising or not

        ) lst

  ORDER BY utils.per_cent(p_share => GREATEST(lst.mid_spread       + ((lst.lowest_offer - lst.mid_spread) * :adjust/100)
                                             ,lst.mid_spread_jita)
                                    -lst.breakeven
                         ,p_total => lst.breakeven) DESC
  ;







/*
    Whats the BREAKEVEN FOR PRODUCE if all input materials bought low? And from where to buy them cheapest?

    You will want to be MORE Price Sensitive with materials that constitute to higher pct of the goods_total.
    Also you may make generous profits even if you are LESS price sensitive with the low pct materials.
    Better yet, as these prices actually are high-/low-end ranges, some materials you will likely get even cheaper.

    IMPORTANT NOTE: when building from Blueprint Copies (BPC) the Remaining Runs will ultimately dictate
    the final material efficiencies, and subsequently the final quantities of required items.
    Those remaining runs cannot be known here (because at the time of writing EVE API XML does not show it)
    and so the result will show that much smaller quantities than what is actually required.
*/
  SELECT INITCAP(SUBSTR(good, 1, 22)) AS good, batch AS n, INITCAP(SUBSTR(part, 1, 22)) AS part, INITCAP(origin) AS orig

        ,  TO_CHAR(quantity,               '990G990G990D99') AS quantity
        ,  TO_CHAR(pile,                   '990G990G990D99') AS pile

        ,CASE WHEN quantity - pile > 0 THEN
           TO_CHAR(quantity - pile,        '990G990G990D99')
         END                                                 AS short

        ,  TO_CHAR(short_volume,           '990G990G990D99') AS vol_short

         -- most matetials you will likely want to haul with your Deep Space Transporter (DST), uncomment others as necessary
        ,of_cargo_deeptransport                              AS dst -- of_cargo_freighter AS frg, of_cargo_jump_freighter AS jf
        ,  TO_CHAR(offers_low_range,       '990G990G990D99') AS quote
        ,INITCAP(SUBSTR(name_region, 1, 15)                ) AS region
        ,  TO_CHAR(items_total,        '990G990G990G990'   ) AS items_tot
        ,                                                       pct
        ,  TO_CHAR(goods_total,        '990G990G990G990'   ) AS goods_tot
        ,  TO_CHAR(goods_total * 0.96, '990G990G990G990'   ) AS discont_four
        ,  TO_CHAR(goods_total * 0.93, '990G990G990G990'   ) AS discont_seven
        ,  TO_CHAR(breakeven,          '990G990G990G990'   ) AS break
        ,  TO_CHAR(just_buy_it,        '990G990G990G990'   ) AS just_buy_it


  FROM  (SELECT good, part, origin, tech, pile, batch, offers_low_range, name_region
  
               ,                                                    SUM(quantity)                                             AS quantity
               ,                                          volume *  SUM(quantity)                                             AS volume               

               ,CASE WHEN pile < SUM(quantity) THEN       volume * (SUM(quantity) - pile)
                END                                                                                                           AS short_volume

               ,CASE WHEN pile < SUM(quantity) THEN ROUND(volume * (SUM(quantity) - pile) / load_market_data.f_get('k_dstful') *100, 1)
                END                                                                                                           AS of_cargo_deeptransport

               ,CASE WHEN pile < SUM(quantity) THEN ROUND(volume * (SUM(quantity) - pile) / load_market_data.f_get('k_jumpfreightful') *100, 1)
                END                                                                                                           AS of_cargo_jump_freighter


               ,                             ROUND(     offers_low_range * SUM(quantity))                                     AS items_total
               ,                             ROUND(     offers_low_range * SUM(quantity)
                                                  /(SUM(offers_low_range * SUM(quantity)) OVER (PARTITION BY good))  *100)    AS pct
               ,                             ROUND( SUM(offers_low_range * SUM(quantity)) OVER (PARTITION BY good))           AS goods_total
               ,CEIL(load_market_data.get_breakeven(SUM(offers_low_range * SUM(quantity)) OVER (PARTITION BY good)))          AS breakeven


               ,(SELECT sub.offers_low_range * batch
                 FROM   vw_avg_sells_regions sub
                 WHERE  sub.part   = good
                 AND    sub.region = load_market_data.get_econ_region(p_part          => good
                                                                     ,p_direction     => 'SELL'
                                                                     ,p_local_regions => :local_sell)  OR sub.region IS NULL) AS just_buy_it


         FROM (SELECT inp.good, inp.subheader, inp.part, prt.material_origin AS origin, prt.volume
                     ,prt.pile, cmp.batch, sel.region, sel.offers_low_range, sel.name_region, goo.tech

                      -- replace with inp.me when no POS
                     ,inp.me_pos AS me
                     --,inp.me
                     
                     ,CASE
                        WHEN prt.material_origin IN ('ICE', 'MINERAL')        THEN FLOOR(inp.quantity_pos * batch) -- replace all with inp.quantity when no POS
                        WHEN prt.class           IN ('DATACORE', 'DECRYPTOR') THEN       inp.quantity_pos * batch
                        ELSE                                                        CEIL(inp.quantity_pos * batch) -- DEFAULT
                      END AS quantity
                      
                FROM             produce             inp
                     INNER JOIN  part                prt ON prt.label = inp.part
                     INNER JOIN  part                goo ON goo.label = inp.good
      
                     -- extra join for Ore and Fuel
                     INNER JOIN (SELECT label, material_origin
                                       ,CASE
                                          WHEN material_origin IN ('ORE' /*, 'ICE ORE'*/)  THEN 100           -- Ore always at 100 makes it Directly Comparable to Market Orders
                                          WHEN class            = 'COMPONENT - FUEL BLOCK' THEN 40  *:rounds  -- Fuel Block normalized back to batch of 40, times intended production rounds
                                          ELSE                                                  TO_NUMBER(:rounds)
                                        END AS batch
                                 FROM   part)        cmp ON cmp.label = inp.good

                LEFT OUTER JOIN vw_avg_sells_regions sel ON sel.part  = prt.label

                WHERE      inp.good            LIKE '%' || UPPER(:good)  || '%'
                AND        inp.transitive         = 'FALSE'
                AND   (    sel.region             = load_market_data.get_econ_region(p_part          => prt.label
                                                                                    ,p_direction     => sel.direction
                                                                                    ,p_local_regions => :local_buy)    OR sel.region IS NULL))
                                                                     
         GROUP BY good, part, origin, tech, volume, pile, batch, offers_low_range, name_region)

  ORDER BY good
          ,items_total  DESC
          ,part;

