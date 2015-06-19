
/*
    Table PART represents an Item in EVE Online, like spaceship, or components to build the ship, or materials to build the components.

    Table Composite implements rules to tells which parts in which quantities are required to make other, more advanced parts.
    One row links two Parts together and thus creates web of parts. However, the loader file, whose contents will be loaded up
    into table composite, must be populated as a tree. This will be checked.

    Table Produce holds all parts and intermediary components needed in all industry jobs required to build a final product.
    A product that itself is no longer a part of a more advanced part. The Column Good is 'the Root part in this Tree of parts'.
    This table will be populated computationally out of Parts and their Composition rules. The table has constraints that
    only accepts data that comply to a tree structure of parts.

    Table Market_order holds Sell and Buy orders for some quantity of a part somewhere in the galaxy.

    Table Market_aggregate is an attempt to make regionwise sums for more realistic information on those market orders.

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

  DROP TABLE domain_material_origin;
  DROP TABLE domain_class;
  DROP TABLE domain_race;




  CREATE TABLE domain_race                   (race       VARCHAR2(50)     NOT NULL     ,CONSTRAINT pk_race   PRIMARY KEY (race));
  CREATE TABLE domain_material_origin        (origin     VARCHAR2(50)     NOT NULL     ,CONSTRAINT pk_origin PRIMARY KEY (origin));
  CREATE TABLE domain_class                  (class      VARCHAR2(50)     NOT NULL     ,CONSTRAINT pk_class  PRIMARY KEY (class));
  

  CREATE SEQUENCE sq_general
    MINVALUE       1
    START     WITH 1
    INCREMENT BY   1;
  



  CREATE TABLE region                        (eveapi_region_id          INTEGER                                     NOT NULL
                                             ,name_region               VARCHAR2(50)     UNIQUE                     NOT NULL
                     
                                             ,CONSTRAINT pk_region PRIMARY KEY (eveapi_region_id));



  CREATE TABLE part                          (label                     VARCHAR2(100)                               NOT NULL
                                             ,eveapi_part_id            INTEGER                                         NULL
                                             ,race                      VARCHAR2(20)                                    NULL
                                             ,class                     VARCHAR2(50)                                    NULL
                                             ,tech                      INTEGER                                         NULL                        
                                             ,material_origin           VARCHAR2(100)                                   NULL                        
                                             ,volume                    NUMBER(10,3)                                NOT NULL
                                             ,material_efficiency       NUMBER(5,3)               DEFAULT 0             NULL
                                             ,pile                      INTEGER                                         NULL
              
                                             ,CONSTRAINT pk_part                        PRIMARY KEY (label)
                                             ,CONSTRAINT br_enum_race                   FOREIGN KEY (race)              REFERENCES domain_race(race)
                                             ,CONSTRAINT br_enum_class                  FOREIGN KEY (class)             REFERENCES domain_class(class)
                                             ,CONSTRAINT br_enum_origin                 FOREIGN KEY (material_origin)   REFERENCES domain_material_origin(origin)
            
                                             ,CONSTRAINT br_materially_efficient_parts
                                                CHECK (NOT (material_efficiency <> 0 AND
                                                            material_origin     IN ('ICE', 'MINERAL', 'PLANET', 'MOON', 'SALVAGE', 'MARKET')))
            
                                              );
  
  CREATE INDEX ix_part_class                  ON part(class);
  CREATE INDEX ix_part_material_origin        ON part(material_origin);
  CREATE INDEX ix_part_eveapi_id              ON part(eveapi_part_id);
  
  

  CREATE TABLE composite                     (good                      VARCHAR2(100)                               NOT NULL
                                             ,part                      VARCHAR2(100)                               NOT NULL
                                             ,quantity                  NUMBER(12,5)                                NOT NULL
                                             ,materially_efficient      VARCHAR2(5)               DEFAULT 'FALSE'   NOT NULL
  
                                             ,CONSTRAINT fk_composite_good              FOREIGN KEY (good)              REFERENCES part(label)
                                             ,CONSTRAINT fk_composite_part              FOREIGN KEY (part)              REFERENCES part(label)

                                             ,CONSTRAINT br_comprise_once_only          UNIQUE (good, part)
                                             ,CONSTRAINT br_finite_composite_loop
                                                CHECK (good <> part)
  
                                             );

  CREATE INDEX ix_composite_good              ON composite(good);
  CREATE INDEX ix_composite_part              ON composite(part);


   
  CREATE TABLE produce                       (ident                     INTEGER                                     NOT NULL
                                             ,good                      VARCHAR2(100)                               NOT NULL
                                             ,subheader                 VARCHAR2(100)                               NOT NULL
                                             ,part                      VARCHAR2(100)                               NOT NULL
                                             ,me                        NUMBER(4,2)                                     NULL
                                             ,quantity                  NUMBER(12,5)                                NOT NULL
                                             ,me_pos                    NUMBER(4,2)                                     NULL
                                             ,quantity_pos              NUMBER(12,5)                                NOT NULL
                                             ,transitive                VARCHAR2(5)               DEFAULT 'FALSE'   NOT NULL

                                             ,CONSTRAINT pk_produce                     PRIMARY KEY (ident)
                                             ,CONSTRAINT fk_produce_good                FOREIGN KEY (good)              REFERENCES part(label)
                                             ,CONSTRAINT fk_produce_subheader           FOREIGN KEY (subheader)         REFERENCES part(label)
                                             ,CONSTRAINT fk_produce_part                FOREIGN KEY (part)              REFERENCES part(label)
            
                                             ,CONSTRAINT br_produce_once_only           UNIQUE (good, subheader, part)
 
                                             ,CONSTRAINT br_finite_input_loop           CHECK (    good      <> part
                                                                                               AND subheader <> part)
                                              );

  CREATE INDEX ix_produce_good                ON produce(good);
  CREATE INDEX ix_produce_subheader           ON produce(subheader);
  CREATE INDEX ix_produce_part                ON produce(part);



  CREATE TABLE market_order                  (part                      VARCHAR2(100)                               NOT NULL
                                             ,direction                 VARCHAR2(4)                                 NOT NULL
                                             ,system_name               VARCHAR2(50)                                NOT NULL
                                             ,region                    INTEGER                                     NOT NULL
                                             ,price                     NUMBER(15,2)                                NOT NULL
                                             ,quantity                  INTEGER                                     NOT NULL
                                             ,min_qty                   INTEGER                                     NOT NULL
                                             ,expires                   DATE                                        NOT NULL
                                             ,time_quotes_exec          TIMESTAMP                                   NOT NULL
                                             
                                             ,CONSTRAINT fk_market_order_part           FOREIGN KEY (part)              REFERENCES part(label)               ON DELETE CASCADE
                                             ,CONSTRAINT fk_market_order_region         FOREIGN KEY (region)            REFERENCES region(eveapi_region_id)

                                             ,CONSTRAINT br_market_order_xor_buy_sell   CHECK (direction IN ('BUY', 'SELL'))

                                             ,CONSTRAINT br_market_order_possible       CHECK (    price    > 0
                                                                                               AND quantity > 0
                                                                                               AND min_qty  > 0));

  CREATE INDEX ix_market_order_part           ON market_order(part);
  CREATE INDEX ix_market_order_direction      ON market_order(direction);
  CREATE INDEX ix_market_order_region         ON market_order(region);
  CREATE INDEX ix_market_order_system         ON market_order(system_name);



  CREATE TABLE market_aggregate              (part                      VARCHAR2(100)                               NOT NULL
                                             ,direction                 VARCHAR2(4)                                 NOT NULL
                                             ,region                    INTEGER                                     NOT NULL
                                             ,samples                   INTEGER                                     NOT NULL
                                             ,price_top                 NUMBER(15,2)                                NOT NULL
                                             ,price_average             NUMBER(15,2)                                NOT NULL
                                             ,time_quotes_exec          TIMESTAMP                                   NOT NULL
                               
                                             ,CONSTRAINT fk_market_aggregate_part       FOREIGN KEY (part)              REFERENCES part(label)               ON DELETE CASCADE
                                             ,CONSTRAINT fk_market_aggregate_region     FOREIGN KEY (region)            REFERENCES region(eveapi_region_id)

                                             ,CONSTRAINT br_market_aggr_xor_buy_sell    CHECK (direction IN ('BUY', 'SELL'))
                                             ,CONSTRAINT br_market_aggregate_possible   CHECK (price_average > 0)
                                             
                                              );

  CREATE INDEX ix_market_aggregate_part       ON market_aggregate(part);
  CREATE INDEX ix_market_aggregate_direction  ON market_aggregate(direction);
  CREATE INDEX ix_market_aggregate_region     ON market_aggregate(region);
  
  -- this function is needed in the most massive queries, lets INDEX that too
  CREATE INDEX ix_f_market_aggr_notable       ON market_aggregate(price_average * samples);




  CREATE TABLE local_regions                (region                    INTEGER                                     NOT NULL
  
                                             ,CONSTRAINT pk_local_regions               PRIMARY KEY (region));

