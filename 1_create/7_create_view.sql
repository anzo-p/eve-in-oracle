
/*
    Update: "turned out" that the in-Game material Consumption rules in EVE Online are best implemented by
    letting Oracle RDBMS do it for us in a Hierarchical Quary. Then Materialize the result for performance.

    Key Problem: the Actual Material Requirements CANNOT be known until we know the Job Runs for ALL relating
    Industry jobs. We need to calculate the Material Quantities as-Late-as-Possible and we do that through
    "Lazy"-computing as can be seen below at VIEW mw_composite.



    Views are good for JOINs that you do so often that SELECTing FROM a view just spares lines and time.
    JOINs so common that a View on that becomes Self-Evident, Self-Explanatory.

    Views are NOT the right place to implement Business Logics and rules, however
    as that would lead to decentralising Logics all over the place.
        
    Contra to that I like to use SELECTs that illustrate the full path of Source Data into well Refined Intelligence.
    This sometimes makes Largish SELECTs but thats OK because the SELECTs can (=MUST) be written in a way that keeps them Simple.
*/



  -- details on the composite
  CREATE OR REPLACE VIEW vw_composite AS
    SELECT cmp.ident
          ,cmp.good_id -- = part.ident
          ,cmp.good    -- = part.label
          ,prt.volume
          ,prt.material_efficiency
          ,prt.pile
          ,prt.eveapi_part_id
          ,cmp.part_id
          ,cmp.part
          ,cmp.quantity
          ,cmp.materially_efficient
    FROM       part      prt
    INNER JOIN composite cmp ON prt.ident = cmp.good_id;
    

  -- details on a compositions constituents
  CREATE OR REPLACE VIEW vw_composition AS
    SELECT cmp.ident
          ,cmp.good_id
          ,cmp.good
          ,cmp.part_id -- = part.ident
          ,cmp.part
          ,cmp.quantity
          ,cmp.materially_efficient
          ,prt.volume
          ,prt.material_efficiency
          ,prt.pile
          ,prt.eveapi_part_id
    FROM       composite cmp
    INNER JOIN part      prt ON prt.ident = cmp.part_id;




  CREATE OR REPLACE VIEW vw_composite_rigged AS
/*
    This view is only required because the Quantities of Parts of some items (below) are normalized to Output of One Unit.
*/
    SELECT ident
          ,good_id
          ,good
          ,part_id
          ,part

          ,CASE
             WHEN utils.keywd(good_id, 'FUEL BLOCKS') = utils.f_get('k_numeric_true') THEN quantity *  40 -- One Round of Fuel Block builds makes  40 Blocks
             WHEN utils.keywd(good_id, 'R.A.M.')      = utils.f_get('k_numeric_true') THEN quantity * 100 --         ..of R.A.M.          ..makes 100 units
             ELSE                                                                          quantity
           END AS quantity

    FROM   composite;



-- materializing speeds up everything begining from DEBUGin
  DROP MATERIALIZED VIEW mw_composite;
  CREATE MATERIALIZED VIEW mw_composite
  REFRESH COMPLETE ON DEMAND AS
/*
    This view implements the EVE Online in-Game rules that govern the True Material Consumptions in individual Composition Rules.
*/
    SELECT sel.ident
          ,sel.good_id
          ,sel.good
          ,sel.eveapi_part_id
          ,sel.material_efficiency
          ,sel.consume_rate_base
          ,sel.consume_rate_true_station
          ,sel.consume_rate_true_pos
          ,sel.part_id
          ,sel.part
          ,sel.quantity_raw
    
          ,sel.quantity_raw
          *sel.consume_rate_true_station AS quantity_true_station
          
          ,sel.quantity_raw
          *sel.consume_rate_true_pos     AS quantity_true_pos
          

    FROM  (SELECT cmp.ident
                 ,cmp.good_id
                 ,cmp.good
                 ,prt.eveapi_part_id
                 ,prt.material_efficiency
                 ,cmp.part_id
                 ,cmp.part
                 ,cmp.quantity                      AS quantity_raw
                 
                 ,(100 - material_efficiency) / 100 AS consume_rate_base


                 ,CASE
                    -- Ore must come through as it is, and before those rules that apply "1 to 1" - because Minerals out of Ore may be 1.00 'by accident'
                    WHEN utils.keywd(good_id, 'RAW MATERIALS')      = utils.f_get('k_numeric_true') THEN (100 - material_efficiency          ) / 100
      
                    -- no ME applies on input items that you need only one of
                    WHEN quantity                                   =                            1  THEN  1
      
                    -- other items where ME does not apply by their nature
                    WHEN utils.keywd(good_id, 'BLUEPRINTS')         = utils.f_get('k_numeric_true') OR
                         utils.keywd(part_id, 'BLUEPRINTS')         = utils.f_get('k_numeric_true') OR
                         utils.keywd(part_id, 'RESEARCH EQUIPMENT') = utils.f_get('k_numeric_true') THEN  1
      
                    -- no extra POS ME on { Component Assembly Array, Drug Lab, .. }
                    WHEN utils.keywd(good_id, 'SUBSYSTEMS')         = utils.f_get('k_numeric_true') OR
                         utils.keywd(good_id, 'STRATEGIC CRUISERS') = utils.f_get('k_numeric_true') OR
                         utils.keywd(good_id, 'BOOSTER')            = utils.f_get('k_numeric_true') THEN (100 - material_efficiency          ) / 100
      
                    -- All else assume POS Bonused ME's
                    ELSE                                                                                 (100 - material_efficiency          ) / 100
                                                                                                        *(100 - utils.n_get('k_pos_bonus_me')) / 100
                  END                               AS consume_rate_true_pos


                 ,CASE -- Must be same as consume_rate_true_pos except for the k_pos_bonus_me
                    WHEN utils.keywd(good_id, 'RAW MATERIALS')      = utils.f_get('k_numeric_true') THEN (100 - material_efficiency          ) / 100      
                    WHEN quantity                                   =                            1  THEN  1      
                    WHEN utils.keywd(good_id, 'BLUEPRINTS')         = utils.f_get('k_numeric_true') OR
                         utils.keywd(part_id, 'BLUEPRINTS')         = utils.f_get('k_numeric_true') OR
                         utils.keywd(part_id, 'RESEARCH EQUIPMENT') = utils.f_get('k_numeric_true') THEN  1      
                    ELSE                                                                                 (100 - material_efficiency          ) / 100
                  END                               AS consume_rate_true_station

      
           FROM       part                prt
           INNER JOIN vw_composite_rigged cmp ON prt.ident = cmp.good_id) sel;





  DROP MATERIALIZED VIEW mw_produce;
  CREATE MATERIALIZED VIEW mw_produce
  REFRESH COMPLETE ON DEMAND AS
/*
    In EVE Online Industry individual Jobs applies CEIL():ing of input items. Consequentially,
    true quantities of required input items cannot be known until we know the Job Runs of all jobs,
    including the batch to build the end Produce. At that point we finally have access to
    the complete plan of jobs and materials.    

    This view uses Hierarchical Querying to define the Tree of Parts to build :produce.
    A formula is composed through the levels that will eventually inform howto calculate the
    True Quantities of any and all required materials. The formula is built Top-Down from
    end-Produce through Components to Raw Materials.
*/
    SELECT sel.composite_id
          ,sel.produce_id
          ,sel.produce
          ,sel.good_id
          ,sel.good
          ,sel.material_efficiency
          ,sel.part_id
          ,sel.part
          ,sel.consume_rate_base
          ,sel.consume_rate_true_station
          ,sel.consume_rate_true_pos
          ,sel.quantity_raw
          ,sel.quantity_true_station
          ,sel.quantity_true_pos
          ,sel.formula_bp_orig

          -- 'Lazy'
          --,utils.calculate(sel.formula) AS qty_final

    FROM  (SELECT cmp.ident                     AS composite_id

                 ,CONNECT_BY_ROOT cmp.good_id   AS produce_id   -- Call any Produce at this column WHEN you      have part.ident -> FASTER: will skip the VARCHAR Comparisons
                 ,CONNECT_BY_ROOT cmp.good      AS produce      -- Call any Produce at this column WHEN you only have part.label -> SLOWER: but works very well when DEBUGing!

                 ,cmp.good_id
                 ,cmp.good
                 ,cmp.material_efficiency
                 ,LEVEL
                 ,cmp.part_id
                 ,cmp.part
                 ,cmp.consume_rate_base
                 ,cmp.consume_rate_true_station
                 ,cmp.consume_rate_true_pos
                 ,CONNECT_BY_ISLEAF             AS summable
                 ,cmp.quantity_raw
                 ,cmp.quantity_true_station
                 ,cmp.quantity_true_pos
                       
/*      
----------------- SYS_CONNECT_BY_PATH --- Begin -----------------------------------------------------------------------------------
                  
                  Example
                  
                    Lets build Photon Microprocessors for a number of Ishtars. We have invented the Ship Blueprint Copy using
                    Accelerant Decryptor. Material Efficiencies for Ishtar and the Photon Microprocessor are 4 and 10, respectively.
                    We build them at our own Player Owned Structure for additiona bonuses on Material Efficiencies.
                    
                    - each Ishtar requires:                         1270.08  Photon Microprocessors
                    - each Photon Microprocessor in turn requires:    14.994 Crystalline Carbonides
                    
                    The game does not work in decimals on materials, and so it will CEIL() all input quantities at every Job Installaton.
                    The Formula for the required amount of Crystalline Carbonieds needed to build the required Photon Microprocessors
                    for ANY NUMBER of Ishtars is:
                    
                      CEIL(CEIL(:JOB_RUNS * 1270.08) * 14.994)
                    
                    Key is that the CEIL()s make it a Discontinuous Function, where we need all terms before we may know the result.
                    We need to calculate the true reuired Quantities as late as possible. Therefore we need to bring the quantities as
                    'Partially Applied Functions' all the way to the Final SQL:s where we actualy decide how many eg. Ishtars we build.
*/
                  
                  -- open leading CEIL/FLOOR:s
                  , utils.repeat(CASE
                                    WHEN utils.keywd(cmp.part_id, 'BLUEPRINTS')         = utils.f_get('k_numeric_true') OR
                                         utils.keywd(cmp.part_id, 'RESEARCH EQUIPMENT') = utils.f_get('k_numeric_true') THEN ''
    
                                    WHEN utils.keywd(cmp.good_id, 'RAW MATERIALS')      = utils.f_get('k_numeric_true') THEN 'FLOOR('
    
                                    ELSE                                                                                     'CEIL('
                                  END
                                 ,LEVEL)               

                  || ':JOB_RUNS'
                  
                  -- append the material multiplier of this level in the hierarchy
                  || SYS_CONNECT_BY_PATH(REPLACE(TO_CHAR(cmp.quantity_true_pos) -- No POS? cmp.quantity_true_station
                                                ,',', '.')
    
                  -- close each opened CEIL/FLOOR
                  ||              CASE
                                    WHEN utils.keywd(cmp.part_id, 'BLUEPRINTS')         = utils.f_get('k_numeric_true') OR
                                         utils.keywd(cmp.part_id, 'RESEARCH EQUIPMENT') = utils.f_get('k_numeric_true') THEN ''
                                    ELSE                                                                                     ')'
                                  END
    
                  -- finally link through the levels of hierarchy
                                        ,' * ')

                  AS formula_bp_orig
                  
----------------- End --- SYS_CONNECT_BY_PATH -------------------------------------------------------------------------------------


           FROM        mw_composite cmp
    
           START WITH good IN (SELECT DISTINCT good FROM composite) -- every Produce
           --START WITH good LIKE '%'|| UPPER(:produce) ||'%' --DEBUG
    
           CONNECT BY PRIOR cmp.part = cmp.good
           ORDER BY produce, LEVEL, cmp.good, cmp.part) sel
           
    -- as the formula is built from Root towards Leaves, only the leaves need be SUMmed for Total Quantities to Build :produce
    WHERE  summable = utils.f_get('k_numeric_true')



/*
    But we are not ready yet.

    See this example on why the Formula based on an Original Blueprint of the Ishtar fails on Invented Copies for the same ship.
    The example uses the same Crystalline Carbinodes and Photon Microprocessors as above.

    SELECT -- building out of an Original Blueprint's Unlimited Runs (still asusming only ME4%)
                                        CEIL(CEIL(               :job_runs  * 1270.08) * 14.994)
    
           -- building Out of Blueprint Copies, assuming { same ME, same Max Runs, all Runs Remaining }
          ,FLOOR(:job_runs/:bpc_runs) * CEIL(CEIL(               :bpc_runs  * 1270.08) * 14.994)   -- we need this many full BPCs of known limited Runs
          +                             CEIL(CEIL(MOD(:job_runs, :bpc_runs) * 1270.08) * 14.994)   -- we need this many Runs on One further BPC
          
    FROM   dual;



    -- Finally this looks like the Minimal Necessary RAW SQL to actually Use the view mw_produce
    SELECT pdc.*
    
          ,                par.need_full_bpcs ||' * '|| REPLACE(pdc.formula_bp_orig, ':JOB_RUNS', par.bpc_runs)
                                              ||' + '|| REPLACE(pdc.formula_bp_orig, ':JOB_RUNS', par.need_short_runs)  AS formula_bp_copy
  
          ,utils.calculate(                             REPLACE(pdc.formula_bp_orig, ':JOB_RUNS', par.batch))           AS qty_final_bp_orig
    
          ,utils.calculate(par.need_full_bpcs ||' * '|| REPLACE(pdc.formula_bp_orig, ':JOB_RUNS', par.bpc_runs)
                                              ||' + '|| REPLACE(pdc.formula_bp_orig, ':JOB_RUNS', par.need_short_runs)) AS qty_final_bp_copy
  
    FROM        mw_produce   pdc
    INNER JOIN (SELECT :job_runs                                    AS batch
                      ,                  NVL(:bpc_runs, :job_runs)  AS bpc_runs
                      ,FLOOR(:job_runs / NVL(:bpc_runs, :job_runs)) AS need_full_bpcs
                      ,MOD  (:job_runs,  NVL(:bpc_runs, :job_runs)) AS need_short_runs
                FROM   dual) par ON 1=1
  
    WHERE       produce LIKE '%'|| UPPER(:produce) ||'%'
*/
    ;






/*
    This is a sample snippet from the EVE API XML QuickLook, which holds buy and sell orders for one item.
    One way to write XMLTABLEs is to copy into the SQL Worksheet a meaningfully long snippet from the source XML
    as a visual guide to write the path to <elements> (the 'for $i' -clause below) and those COLUMNS -parameters.

    <quicklook>
      <item>34</item>
      <itemname>Tritanium</itemname>
      <regions></regions>
      <hours>360</hours>
      <minqty>10001</minqty>
      <sell_orders>
        <order id="3877024977">
          <region>10000014</region>
          <station>61000182</station>
          <station_name>GE-8JV VII - Braveland - for Fapstar Stasarik</station_name>
          <security>-0.2</security>
          <range>32767</range>
          <price>10.92</price>
          <vol_remain>6490335</vol_remain>
          <min_volume>1</min_volume>
          <expires>2015-03-10</expires>
          <reported_time>12-10 10:34:52</reported_time>
        </order>
*/
  CREATE OR REPLACE VIEW vw_eveapi_qsells AS
    SELECT cch.item_type_id, res.*
    FROM   cache_market_quicklook cch
    INNER JOIN XMLTABLE('for $i in //quicklook/sell_orders/order
                         return $i'
                        PASSING cch.xdoc
                        COLUMNS region          INTEGER       PATH 'region'
                               ,station         VARCHAR2(20)  PATH 'station'
                               ,station_name    VARCHAR2(200) PATH 'station_name'
                               ,security        VARCHAR2(4)   PATH 'security'
                               ,price           VARCHAR2(20)  PATH 'price'
                               ,vol_remain      INTEGER       PATH 'vol_remain'
                               ,min_volume      INTEGER       PATH 'min_volume'
                               ,expires         VARCHAR2(10)  PATH 'expires'
                               ) res ON 1=1;


/*
    Duplicate to *qsells: not a good idea to have two virtually identical views
    though common to have only either Sell or Buy Orders up for spefic items/stations.
    Forcing that into a single view would mean OUTER JOINs, which surely kills performance.
    As a downside Buys and Sells must follow this duplicate pattern through system.
*/
  CREATE OR REPLACE VIEW vw_eveapi_qbuys AS
    SELECT cch.item_type_id, res.*
    FROM   cache_market_quicklook cch
    INNER JOIN XMLTABLE('for $i in //quicklook/buy_orders/order
                         return $i'
                        PASSING cch.xdoc
                        COLUMNS region          INTEGER       PATH 'region'
                               ,station         VARCHAR2(20)  PATH 'station'
                               ,station_name    VARCHAR2(200) PATH 'station_name'
                               ,security        VARCHAR2(4)   PATH 'security'
                               ,price           VARCHAR2(20)  PATH 'price'
                               ,vol_remain      INTEGER       PATH 'vol_remain'
                               ,min_volume      INTEGER       PATH 'min_volume'
                               ,expires         VARCHAR2(10)  PATH 'expires'
                               ) res ON 1=1;




  -- joins Region to market data
  CREATE OR REPLACE VIEW vw_avg_sells_regions AS
    SELECT agr.part_id
          ,agr.direction
          ,agr.samples
          ,agr.price_top        AS lowest_offer
          ,agr.price_average    AS offers_low_range
          ,agr.time_quotes_exec
          ,agr.region
          ,reg.name_region
    FROM       market_aggregate agr
    INNER JOIN region           reg ON reg.eveapi_region_id = agr.region
    WHERE  agr.direction = 'SELL';


  CREATE OR REPLACE VIEW vw_avg_buys_regions AS
    SELECT agr.part_id
          ,agr.direction
          ,agr.samples
          ,agr.price_top        AS highest_bid
          ,agr.price_average    AS bids_high_range
          ,agr.time_quotes_exec
          ,agr.region
          ,reg.name_region
    FROM       market_aggregate agr
    INNER JOIN region           reg ON reg.eveapi_region_id = agr.region
    WHERE  agr.direction = 'BUY';
    