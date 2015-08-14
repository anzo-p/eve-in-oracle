
/*
    Table PART represents Items in EVE Online, like spaceship, or components to build the ship, or materials to build the components.

    Table Composite implements rules to tells which parts in which quantities are required to make other, more advanced parts.
    One row links two Parts together and thus the table creates a web of parts. However, the loader file, whose contents will be
    loaded up into table composite, must be populated as a tree. This will be checked.

    Table Market_order holds Sell and Buy orders for parts around the galaxy.

    Table Market_aggregate is an attempt to make regionwide sums for more realistic information on those market orders.

    Table local_regions holds the regions that you define local (at eve_drill.sql) and allows to filter market data down
    to more convenient traveling distances.
*/



  DROP TABLE market_aggregate;
  DROP TABLE market_order;
  DROP TABLE produce;
  DROP TABLE composite;
  DROP TABLE part;
  DROP TABLE region;
  DROP TABLE local_regions;
  DROP TABLE keyword;
  DROP TABLE keyword_map;



  CREATE SEQUENCE sq_general
    MINVALUE       1
    START     WITH 1
    INCREMENT BY   1;



  
  CREATE TABLE region                        (eveapi_region_id          INTEGER                                     NOT NULL
                                             ,name_region               VARCHAR2(50)     UNIQUE                     NOT NULL
                     
                                             ,CONSTRAINT pk_region PRIMARY KEY (eveapi_region_id));



  CREATE TABLE part                          (ident                     INTEGER                                     NOT NULL
                                             ,label                     VARCHAR2(100)                               NOT NULL
                                             ,eveapi_part_id            INTEGER                                         NULL
                                             ,volume                    NUMBER(10,3)                                NOT NULL
                                             ,material_efficiency       NUMBER(5,3)               DEFAULT 0             NULL
                                             ,outcome_units             INTEGER                   DEFAULT 1         NOT NULL
                                             ,pile                      INTEGER                                         NULL
                                             ,base_invent_success       NUMBER(5,3)                                     NULL
                                             ,base_invent_copies        INTEGER                                         NULL
              
                                             ,CONSTRAINT pk_part                        PRIMARY KEY (ident)

                                              );
  
  CREATE INDEX ix_part_label                  ON part(label);
  CREATE INDEX ix_eveapi_part_id              ON part(eveapi_part_id);
  
  

  CREATE TABLE composite                     (ident                     INTEGER                                     NOT NULL
                                             ,good_id                   INTEGER                                     NOT NULL
                                             ,part_id                   INTEGER                                     NOT NULL
                                             ,good                      VARCHAR2(100)                               NOT NULL
                                             ,part                      VARCHAR2(100)                               NOT NULL
                                             ,quantity                  NUMBER(12,5)                                NOT NULL

  
                                             ,CONSTRAINT fk_composite_good              FOREIGN KEY (good_id)           REFERENCES part(ident)
                                             ,CONSTRAINT fk_composite_part              FOREIGN KEY (part_id)           REFERENCES part(ident)

                                             ,CONSTRAINT br_comprise_once_only          UNIQUE (good_id, part_id)
                                             ,CONSTRAINT br_finite_composite_loop
                                                CHECK (good <> part)
  
                                             );

  CREATE INDEX ix_composite_good              ON composite(good_id);
  CREATE INDEX ix_composite_part              ON composite(part_id);
  CREATE INDEX ix_composite_good_label        ON composite(good);
  CREATE INDEX ix_composite_part_label        ON composite(part);
   



  CREATE TABLE keyword                       (ident                     INTEGER                                     NOT NULL
                                             ,label                     VARCHAR2(50)                                NOT NULL
                    
                                             ,CONSTRAINT pk_keyword PRIMARY KEY (ident));
                                             
  CREATE INDEX ix_keyword_label               ON keyword(label);



  CREATE TABLE keyword_map                   (keyword_id                INTEGER                                     NOT NULL
                                             ,part_id                   INTEGER                                     NOT NULL
                        
                                             ,CONSTRAINT fk_keyword_link      FOREIGN KEY (keyword_id) REFERENCES keyword(ident)   ON DELETE CASCADE
                                             ,CONSTRAINT fk_keyword_part_link FOREIGN KEY (part_id)    REFERENCES part(ident)      ON DELETE CASCADE
                                             
                                             ,CONSTRAINT br_distinct_mapping UNIQUE (keyword_id, part_id));

  CREATE INDEX ix_keyword_link                ON keyword_map(keyword_id);
  CREATE INDEX ix_keyword_part_link           ON keyword_map(part_id);




  CREATE TABLE market_order                  (part_id                   INTEGER                                     NOT NULL
                                             ,direction                 VARCHAR2(4)                                 NOT NULL
                                             ,system_name               VARCHAR2(50)                                NOT NULL
                                             ,region                    INTEGER                                     NOT NULL
                                             ,price                     NUMBER(15,2)                                NOT NULL
                                             ,quantity                  INTEGER                                     NOT NULL
                                             ,min_qty                   INTEGER                                     NOT NULL
                                             ,expires                   DATE                                        NOT NULL
                                             ,time_quotes_exec          TIMESTAMP                                   NOT NULL
                                             
                                             ,CONSTRAINT fk_market_order_part           FOREIGN KEY (part_id)           REFERENCES part(ident)               ON DELETE CASCADE
                                             ,CONSTRAINT fk_market_order_region         FOREIGN KEY (region)            REFERENCES region(eveapi_region_id)

                                             ,CONSTRAINT br_market_order_xor_buy_sell   CHECK (direction IN ('BUY', 'SELL'))

                                             ,CONSTRAINT br_market_order_possible       CHECK (    price    > 0
                                                                                               AND quantity > 0
                                                                                               AND min_qty  > 0));

  CREATE INDEX ix_market_order_part           ON market_order(part_id);
  CREATE INDEX ix_market_order_direction      ON market_order(direction);
  CREATE INDEX ix_market_order_region         ON market_order(region);
  CREATE INDEX ix_market_order_system         ON market_order(system_name);



  CREATE TABLE market_aggregate              (part_id                   INTEGER                                     NOT NULL
                                             ,direction                 VARCHAR2(4)                                 NOT NULL
                                             ,region                    INTEGER                                     NOT NULL
                                             ,samples                   INTEGER                                     NOT NULL
                                             ,price_top                 NUMBER(15,2)                                NOT NULL
                                             ,price_average             NUMBER(15,2)                                NOT NULL
                                             ,time_quotes_exec          TIMESTAMP                                   NOT NULL
                               
                                             ,CONSTRAINT fk_market_aggregate_part       FOREIGN KEY (part_id)           REFERENCES part(ident)               ON DELETE CASCADE
                                             ,CONSTRAINT fk_market_aggregate_region     FOREIGN KEY (region)            REFERENCES region(eveapi_region_id)

                                             ,CONSTRAINT br_market_aggr_xor_buy_sell    CHECK (direction IN ('BUY', 'SELL'))
                                             ,CONSTRAINT br_market_aggregate_possible   CHECK (price_average > 0)
                                             
                                              );

  CREATE INDEX ix_market_aggregate_part       ON market_aggregate(part_id);
  CREATE INDEX ix_market_aggregate_region     ON market_aggregate(region);
  CREATE INDEX ix_market_aggregate_direction  ON market_aggregate(direction);
  
  -- this function is needed in the most massive queries, lets INDEX that too
  CREATE INDEX ix_f_market_aggr_notable       ON market_aggregate(price_average * samples);




  CREATE TABLE local_regions                (region                    INTEGER                                     NOT NULL
  
                                             ,CONSTRAINT pk_local_regions               PRIMARY KEY (region));

