
/*
    Views are good for JOINs that you do so often that SELECTing FROM a view just spares lines and time.
    JOINs so common that a View on that becomes Self-Evident, Self-Explanatory.

    Views are NOT the right place to implement Business Logics and rules, however
    as that would lead to decentralising Logics all over the place.
        
    Contra to that I like to use SELECTs that illustrate the full path of Source Data into Well Refined Intelligence.
    This sometimes makes Largish SELECTs but thats OK because the SELECTs can (=MUST) be written in a way that keeps them Simple.
*/




/*
    Sample says it all - from here it is already possible to see how Oracle XMLDB Works, how the PASSING -parameters below map to the XML-snippet
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
    As a downside Buys and Sells must follow this duplicate pattern allower the system.
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
    SELECT agr.part
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
    SELECT agr.part
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




  -- details on the composite
  CREATE OR REPLACE VIEW vw_composite AS
    SELECT *
    FROM       part      prt
    INNER JOIN composite cmp ON prt.label = cmp.good;
    

  -- details on a compositions constituents
  CREATE OR REPLACE VIEW vw_composition AS
    SELECT *
    FROM       composite cmp
    INNER JOIN part      prt ON prt.label = cmp.part;
    