CREATE OR REPLACE PACKAGE load_market_data IS



--- Realism Rules -------------------------------------
  k_practical_demand_range       CONSTANT BINARY_DOUBLE                     := 2 *1000 *1000 *1000; -- iskworth of Purchase Orders to aggregate an AVG for a more realistic Best Price
  k_practical_supply_range       CONSTANT BINARY_DOUBLE                     := 2 *1000 *1000 *1000; -- iskworth of Sell Orders...
  k_notable_demand_good          CONSTANT BINARY_DOUBLE                     :=     300 *1000 *1000; -- minimum iskworth of Purchase Orders up for a considerable opportunity/yield
  k_notable_supply_part          CONSTANT BINARY_DOUBLE                     :=      20 *1000 *1000; -- minimum iskwort of Sales Orders to justify the traveling

  k_buys_max_below_break         CONSTANT NUMBER                            := 1 + 20/100;          -- max proximity of highest bid to breakeven, %
  k_sells_min_above_break        CONSTANT NUMBER                            := 1 +  5/100;          -- min proximity of lowest offer to breakeven, %  
  k_order_relevancy              CONSTANT PLS_INTEGER                       := 2;                   -- at least days left on buy/sell order to include it in market_aggregate
  k_spread_overshoot             CONSTANT PLS_INTEGER                       := 7;                   -- when highest buy / lowest sell spread this much within region, assume anomaly, not valid input for the appraisal
-------------------------------------------------------



/*
    Limit the size of incoming XML and speed up processing by parametrising the regions of interest. (SELECT * FROM region).
    Most likely you will want Empire/Hisec coverage on Regions where you operate + Trade Hubs Regions for price reference.
*/                                                                             
  k_regions_of_interest          CONSTANT VARCHAR2(300)                     := -- Local Regions
                                                                                  '&'||'regionlimit=10000033'  -- Citadel, the
                                                                               || '&'||'regionlimit=10000064'  -- Essence
                                                                               || '&'||'regionlimit=10000037'  -- Everyshore
                                                                               || '&'||'regionlimit=10000067'  -- Genesis
                                                                               || '&'||'regionlimit=10000068'  -- Verge Vendor
                                                                               
                                                                               -- Trade Hub Regions
                                                                               || '&'||'regionlimit=10000043'  -- Domain
                                                                               || '&'||'regionlimit=10000002'  -- Forge, the
                                                                               || '&'||'regionlimit=10000030'  -- Heimatar
                                                                               || '&'||'regionlimit=10000042'  -- Metropolis
                                                                               || '&'||'regionlimit=10000032'; -- Sinq Laison
                                                                               


  k_dstful                       CONSTANT PLS_INTEGER                       := 60000;  -- Deep Space Transport Cargo Bay
  k_freightful                   CONSTANT PLS_INTEGER                       := 800000; -- Freighter Ship Cargo Bay
  k_jumpfreightful               CONSTANT PLS_INTEGER                       := 300000; -- Jump Freighter Cargo Bay

  k_eveapi_fetch_jobs_per_sec    CONSTANT PLS_INTEGER                       := 5;
  k_build_cost_multiplier        CONSTANT NUMBER(5,2)                       := 1.03;   -- build cost is 1.5% of EVE-Global-Killboard-Aggregates, and "not expected to change dramatically", double it for "Margin of Safety"
  k_sales_cost_multiplier        CONSTANT NUMBER(5,2)                       := 1.02;   -- Tax 0.75% + Optimal Brokering 0.75% + contingency + ignorance on that it should apply deducted from 100% not added to 100%

  


  TYPE t_region                  IS TABLE OF region.eveapi_region_id%TYPE INDEX BY BINARY_INTEGER;



  FUNCTION  v_get                         (p_param               VARCHAR2)                                                RETURN VARCHAR2;
  FUNCTION  f_get                         (p_param               VARCHAR2)                                                RETURN BINARY_DOUBLE;



  FUNCTION  get_breakeven                 (p_param             IN NUMBER)                                                 RETURN NUMBER;

  FUNCTION  get_econ_region               (p_part                 market_aggregate.part%TYPE
                                          ,p_direction            market_aggregate.direction%TYPE
                                          ,p_local_regions        VARCHAR2)                                               RETURN market_aggregate.region%TYPE   RESULT_CACHE;

  PROCEDURE load_prices                   (p_eveapi_part_id    IN part.eveapi_part_id%TYPE
                                          ,p_security_limit    IN NUMBER);

  PROCEDURE submit_price_jobs             (p_local_regions     IN VARCHAR2
                                          ,p_security_limit    IN NUMBER);


END load_market_data;
/







CREATE OR REPLACE PACKAGE BODY load_market_data AS



  FUNCTION v_get(p_param VARCHAR2)
  RETURN VARCHAR2 AS
    v_return VARCHAR2(30);
  BEGIN
    EXECUTE IMMEDIATE ('BEGIN :1 := load_market_data.'|| p_param ||'; END;') USING IN OUT v_return;
    RETURN v_return;
  END v_get;


  FUNCTION f_get(p_param VARCHAR2)
  RETURN BINARY_DOUBLE AS
    f_return BINARY_DOUBLE;
  BEGIN
    EXECUTE IMMEDIATE ('BEGIN :1 := load_market_data.'|| p_param ||'; END;') USING IN OUT f_return;
    RETURN f_return;
  END f_get;




  FUNCTION get_breakeven(p_param IN NUMBER) RETURN NUMBER AS
/*
    Add build costs on top of p_param to get Breakeven.
    Could be more deterministic, but "Better to be roughly right than precisely wrong" - J.M. Keynes.
*/
  BEGIN
    RETURN p_param * k_build_cost_multiplier
                   * k_sales_cost_multiplier;
  END get_breakeven;




  FUNCTION get_econ_region(p_part          market_aggregate.part%TYPE
                          ,p_direction     market_aggregate.direction%TYPE
                          ,p_local_regions VARCHAR2)

  RETURN market_aggregate.region%TYPE   RESULT_CACHE RELIES_ON (market_aggregate, local_regions) AS
/*
    Get the cheapest region for part. The need for this query came from the heaviest SQLs.
    Putting functions into SQL tempted me to Cache the Result to ptomote performance:

    the call Parameters and the Return Value will be stored in RAM memory from where it is
    accesible superfast, until the tables defined at the RELIES_ON list change.
*/
    v_return   market_aggregate.region%TYPE;

  BEGIN

    SELECT reg.region
    INTO   v_return

    FROM  (SELECT     sub.region
                 ,    sub.price_average

           FROM   market_aggregate sub
           WHERE  sub.direction    =  p_direction
           AND    sub.part         =  p_part

          -- pre-selected OR all regions
           AND   (sub.region      IN (SELECT loc.region
                                      FROM   local_regions loc)
                     OR
                  p_local_regions IS  NULL)

           ORDER BY CASE WHEN direction = 'SELL' THEN price_average END ASC
                   ,CASE WHEN direction = 'BUY'  THEN price_average END DESC) reg

    WHERE  ROWNUM = 1;

    RETURN v_return;

  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RETURN NULL;

  END get_econ_region;




  PROCEDURE merge_market_aggregate(p_part      IN part.label%TYPE
                                  ,p_direction IN market_order.direction%TYPE) AS
/*
   IMPORTANT: Assume you need a quantity of 10,000 (ten thousand) of and Item.
   Surely you can NOT travel across the galaxy to acquire a single or a few?
   
   No. We must come up with a more Credible/Practical/Realistic sense of a Budget Price Level.
   
   And so in this code we will sum up a number of the Sell (or Buy) Orders
   beginning from the Lowest (or Highest) and then divide the Total Price with the Quantity.
*/


    n_quantity      market_aggregate.samples%TYPE;
    f_top_price     market_aggregate.price_average%TYPE;
    f_avg_price     market_aggregate.price_average%TYPE;
    f_sum_total     market_aggregate.price_average%TYPE;

  BEGIN

    FOR r_reg IN (SELECT DISTINCT region
                  FROM   market_order
                  WHERE  direction = p_direction
                  AND    part      = p_part) LOOP

      f_top_price := NULL;
      f_avg_price := 0;
      n_quantity  := 0;
        

      FOR r_ord IN (SELECT part, direction, region, quantity, price
                    FROM   market_order
                    WHERE  direction = p_direction
                    AND    part      = p_part
                    AND    region    = r_reg.region
                    ORDER BY CASE WHEN p_direction = 'SELL' THEN price END ASC
                            ,CASE WHEN p_direction = 'BUY'  THEN price END DESC
                            ) LOOP

        IF f_top_price IS NULL THEN
          f_top_price := r_ord.price;

        ELSE
          -- EXIT BEFORE overshoot
          EXIT WHEN (p_direction = 'SELL' AND r_ord.price
                                             /f_top_price > k_spread_overshoot)
                        
               OR   (p_direction = 'BUY'  AND r_ord.price
                                             /f_top_price
                                             *100         < k_spread_overshoot);

             --OR else keep looping til SELECT runs out
        END IF;

        f_avg_price := ((f_avg_price  * n_quantity)
                       +(r_ord.price  * r_ord.quantity))
                       /(n_quantity   + r_ord.quantity);

        n_quantity  := r_ord.quantity + n_quantity;
        f_sum_total := f_avg_price    * n_quantity;

        -- OR EXIT AFTER the desired cumulation
        EXIT WHEN (p_direction = 'SELL' AND f_sum_total >= k_practical_supply_range)
             OR   (p_direction = 'BUY'  AND f_sum_total >= k_practical_demand_range);

      END LOOP;


      IF     p_direction              = 'BUY'                  OR

        (    p_direction              = 'SELL'
         AND f_avg_price * n_quantity > k_notable_supply_part) THEN -- we only want to know of item/price/region when trading potential justifies the visit


        MERGE INTO market_aggregate agr
        
        USING (SELECT p_part       AS part
                     ,p_direction  AS direction
                     ,r_reg.region AS region
                     ,n_quantity   AS samples
                     ,f_top_price  AS price_top
                     ,f_avg_price  AS price_average
               FROM   dual) ins
               
        ON (    agr.part      = ins.part
            AND agr.direction = ins.direction
            AND agr.region    = ins.region)
        
        WHEN MATCHED THEN
          UPDATE
          SET    agr.samples          = ins.samples
                ,agr.price_top        = ins.price_top
                ,agr.price_average    = ins.price_average
                ,agr.time_quotes_exec = SYSTIMESTAMP

          WHERE  NVL(agr.samples,       utils.k_dummy_number) <> NVL(ins.samples,       utils.k_dummy_number)
          OR     NVL(agr.price_top,     utils.k_dummy_number) <> NVL(ins.price_top,     utils.k_dummy_number)
          OR     NVL(agr.price_average, utils.k_dummy_number) <> NVL(ins.price_average, utils.k_dummy_number)
        
        WHEN NOT MATCHED THEN
          INSERT (part, direction, region, samples, price_top, price_average, time_quotes_exec)
          VALUES (ins.part, ins.direction, ins.region, ins.samples, ins.price_top, ins.price_average, SYSTIMESTAMP);

      END IF;
    END LOOP;

  END merge_market_aggregate;




  PROCEDURE load_prices(p_eveapi_part_id IN part.eveapi_part_id%TYPE
                       ,p_security_limit IN NUMBER) AS
  

    CURSOR c_sells(pc_item_id IN vw_eveapi_qsells.item_type_id%TYPE) IS

      SELECT SUBSTR(sel.station_name, 1, INSTR(sel.station_name, ' ')) AS stellar_sys

            ,sel.region
            --,sel.security
            --,sel.station
            --,sel.station_name
            ,sel.vol_remain
            ,sel.min_volume

            ,TO_NUMBER(sel.price
                      ,utils.k_mask_price_eveapi_xml 
                      ,utils.k_nls_decimal_chars)  AS price

            ,TO_DATE(sel.expires
                    ,utils.k_mask_date_eveapi_xml) AS expires


      FROM   vw_eveapi_qsells sel
      WHERE  sel.item_type_id             = pc_item_id
      AND    p_security_limit            <= TO_NUMBER(sel.security
                                                     ,utils.k_mask_price_eveapi_xml 
                                                     ,utils.k_nls_decimal_chars)

      AND    SYSDATE + k_order_relevancy <  TO_DATE(sel.expires
                                                   ,utils.k_mask_date_eveapi_xml);


    -- 'same' for buys
    CURSOR c_buys(pc_item_id IN vw_eveapi_qbuys.item_type_id%TYPE) IS
      SELECT SUBSTR(buy.station_name, 1, INSTR(buy.station_name, ' ')) AS stellar_sys
            ,buy.region
            ,buy.vol_remain
            ,buy.min_volume
            ,TO_NUMBER(buy.price, utils.k_mask_price_eveapi_xml, utils.k_nls_decimal_chars) AS price
            ,TO_DATE(buy.expires, utils.k_mask_date_eveapi_xml) AS expires
      FROM   vw_eveapi_qbuys buy
      WHERE  buy.item_type_id             = pc_item_id
      AND    p_security_limit            <= TO_NUMBER(buy.security, utils.k_mask_price_eveapi_xml, utils.k_nls_decimal_chars)
      AND    SYSDATE + k_order_relevancy <  TO_DATE(buy.expires, utils.k_mask_date_eveapi_xml);



    TYPE t_sells                 IS TABLE OF c_sells%ROWTYPE;
    TYPE t_buys                  IS TABLE OF c_buys%ROWTYPE;
    a_sells                      t_sells;
    a_buys                       t_buys;

    k_url_head          CONSTANT VARCHAR2(200) := 'http://api.eve-central.com/api/quicklook?typeid=';
    v_url                        VARCHAR2(500);
    l_site                       CLOB;
    a_pieces                     utl_http.html_pieces;
    x_doc                        XMLTYPE;
    ts_cached_until              TIMESTAMP;
    v_label                      part.label%TYPE;

  BEGIN

    SELECT label
    INTO   v_label
    FROM   part
    WHERE  eveapi_part_id  = p_eveapi_part_id;
    -- EXCEPTION WHEN NO_DATA_FOUND THEN JUST DIE VOCALLY
    

    v_url    :=         k_url_head            ||
                TO_CHAR(p_eveapi_part_id)     ||
                        k_regions_of_interest;
                           
    -- get the XML from Web Service
    x_doc := utils.request_xml(v_url);

      
---- CACHE
/*
    quicklook does not have <cachedUntil> so lets make our own,
    though not requird for quicklook by CCP (at the time of writing).

    Bear in mind that meaningful/noticeable changes on the market takes many hours to develop.
    And limiting the list of items whose quotations to refresh will streamline the load process.
    (Though this no longer seems to be an issue in Oracle 12c with the optimized XML processing).
*/
    ts_cached_until := SYSTIMESTAMP
                      +((4 + MOD(p_eveapi_part_id                  -- diverse them abit: 4 + { 0, 1, 2, 3, 4 } hours forward
                                +TO_NUMBER(TO_CHAR(SYSDATE, 'SS')) -- add seconds to randomize the modulo abit, plain item_id would favor certain items
                                ,5))
                        /24);


    MERGE INTO cache_market_quicklook cch

    USING (SELECT p_eveapi_part_id AS item_type_id
                 ,ts_cached_until  AS cached_until
                 ,x_doc            AS xdoc
           FROM   dual) ins
    
    ON (cch.item_type_id = ins.item_type_id)

    WHEN MATCHED THEN
      UPDATE
      SET    cch.cached_until = ins.cached_until
            ,cch.xdoc         = ins.xdoc
    
    WHEN NOT MATCHED THEN
      INSERT (item_type_id, cached_until, xdoc)
      VALUES (ins.item_type_id, ins.cached_until, ins.xdoc);
      

---- INSERT FROM local XML INTO local database
    OPEN  c_sells(p_eveapi_part_id);
    FETCH c_sells BULK COLLECT INTO a_sells;
    CLOSE c_sells;

    IF a_sells.COUNT > 0 THEN

      FORALL i IN a_sells.FIRST .. a_sells.LAST
                   
        INSERT INTO market_order
        (
          part, direction, system_name, region, price
         ,quantity, min_qty, expires, time_quotes_exec
         
        ) VALUES (
        
          v_label, 'SELL', a_sells(i).stellar_sys, a_sells(i).region, a_sells(i).price
         ,a_sells(i).vol_remain, a_sells(i).min_volume, a_sells(i).expires, SYSTIMESTAMP
        );
    END IF;



    OPEN  c_buys(p_eveapi_part_id);
    FETCH c_buys BULK COLLECT INTO a_buys;
    CLOSE c_buys;

    IF a_buys.COUNT > 0 THEN

      FORALL i IN a_buys.FIRST .. a_buys.LAST
                   
        INSERT INTO market_order
        (
          part, direction, system_name, region, price
         ,quantity, min_qty, expires, time_quotes_exec
         
        ) VALUES (
        
           v_label, 'BUY', a_buys(i).stellar_sys, a_buys(i).region, a_buys(i).price
          ,a_buys(i).vol_remain, a_buys(i).min_volume, a_buys(i).expires, SYSTIMESTAMP
        );
    END IF;


------ CALCULATE AVGs
    merge_market_aggregate(p_part      => v_label
                          ,p_direction => 'SELL');
                            
    merge_market_aggregate(p_part      => v_label
                          ,p_direction => 'BUY');


  END load_prices;




  PROCEDURE set_local_regions(p_param IN VARCHAR2) AS
  BEGIN
    DELETE FROM local_regions;
  
    INSERT INTO local_regions  
      SELECT eveapi_region_id
      FROM   region
      WHERE   0 < instr(p_param, name_region);

  END set_local_regions;




  PROCEDURE submit_price_jobs(p_local_regions     IN VARCHAR2
                             ,p_security_limit    IN NUMBER) AS
  
    k_ad_hoc_job   CONSTANT user_jobs.INTERVAL%TYPE := ''; -- IS NULL yes
    j_job                   user_jobs.JOB%TYPE;
  
  BEGIN

    set_local_regions(p_local_regions);


/*
    Dont want to know the history (for now), only need latest quotations.
    See if an otherwise quiet station had some for sale and those are sold,
    that quotation would have to be deliberately deleted/invalidated for this to work.
*/
    DELETE FROM market_order;


/*
    Oracle dbms Jobs are a handy way to use Concurrency to promote Performance,
    especially is you spread the jobs out in time, so not to choke your host machines resources.
*/
    FOR r_job IN (SELECT --sel.label
                         sel.eveapi_part_id
                        ,sel.cached_until

                        ,          SYSDATE + (sel.delay_secs / 24 / 60 / 60) AS next_date
                        --,TO_CHAR(SYSDATE + (sel.delay_secs / 24 / 60 / 60), 'DD.MM.YYYY HH24:MI:SS') -- DEBUG
                  
                  FROM  (SELECT --prt.label
                                prt.eveapi_part_id
                               ,cch.cached_until

/*                               
                                Every N jobs push one second further

                                Be advised: EVE Online API Politics states max 30 requests per second (at the time of writing)
                                OR run the risk of having to request an IP unban though a manual process.
*/                                
                               ,ROUND(ROWNUM * (1 / k_eveapi_fetch_jobs_per_sec)) AS delay_secs

                         FROM            part                   prt
                         LEFT OUTER JOIN cache_market_quicklook cch ON cch.item_type_id = prt.eveapi_part_id

                         WHERE     prt.eveapi_part_id IS NOT NULL
                         AND   (   cch.cached_until   IS     NULL
                                OR cch.cached_until    <     SYSTIMESTAMP)

                         --AND       ROWNUM              < 10 -- DEBUG

                         ) sel ) LOOP

  
      dbms_job.submit(job       => j_job
                     ,what      => 'load_market_data.load_prices('   ||         TO_CHAR(r_job.eveapi_part_id)           ||
                                                                ', ' || REPLACE(TO_CHAR(p_security_limit),    ',', '.') || ');'

                     ,next_date => r_job.next_date
                     ,interval  => k_ad_hoc_job);
    END LOOP;

    

    COMMIT;

  END submit_price_jobs;

  
  
END load_market_data;
/
