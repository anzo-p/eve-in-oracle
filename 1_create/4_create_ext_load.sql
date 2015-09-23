
/*
    These Tables are used to load data from local *.csv files into the System.
    Whats fancy about that is that we can now control all loadable data through loader files
    and let the population into database tables to a single transaction.
    
    This is why I keep my loader files in Human Readable format.
    (eg. GEdit or another notepadlike app, Fixed Width fonts required)
*/



  DROP TABLE ext_load_part;
  DROP TABLE ext_load_composite;
  DROP TABLE tmp_load_part;
  DROP TABLE tmp_load_composite;
  DROP TABLE tmp_load_assets;
  DROP TABLE cache_market_quicklook;
  DROP TABLE cache_asset_list;
  DROP TABLE cache_indu_jobs;





/*
    Right there inside the Access Parameters in these Table Definitions is the directory
    you created as ADMIN at 1_create_database.sql. This is why they are needed.
  
    This table definition tells Oracle to go open that file (part.txt in this case)
    and read it as a Database Table using the rules Defined in Access Parameters.
    
    As you can see in every ext_load_* table the columns matches the columns in respective Loader File.  
*/
  CREATE TABLE ext_load_part                 (label                    VARCHAR2(100)
                                             ,market_browser_path      VARCHAR2(500)
                                             ,volume                   NUMBER(15,3)
                                             ,eveapi_part_id           INTEGER
                                             ,material_efficiency      NUMBER(10,3)
                                             ,outcome_units            INTEGER
                                             ,base_invent_success      NUMBER(10,3)
                                             ,base_invent_copies       INTEGER)
    ORGANIZATION EXTERNAL      (
                                  TYPE ORACLE_LOADER
                                  DEFAULT DIRECTORY directory_eve
                                  ACCESS PARAMETERS
                                  (
                                     RECORDS    DELIMITED  BY newline
                                     BADFILE directory_eve: 'bad_part.txt'
                                     NODISCARDFILE NOLOGFILE
                                     SKIP 1
                                     FIELDS     TERMINATED BY ','
                                     OPTIONALLY ENCLOSED   BY '"'      
                                     MISSING FIELD VALUES ARE NULL
                                     
                                     (label                 CHAR(100)
                                     ,market_browser_path   CHAR(500)
                                     ,volume                CHAR(10)
                                     ,eveapi_part_id        CHAR(10)
                                     ,material_efficiency   CHAR(10)
                                     ,outcome_units         CHAR(5)
                                     ,base_invent_success   CHAR(10)
                                     ,base_invent_copies    CHAR(3))
                                     
                                  )
                                  LOCATION('part.txt')
    )
    REJECT LIMIT UNLIMITED;




  CREATE TABLE ext_load_composite            (good                     VARCHAR2(100)
                                             ,part                     VARCHAR2(100)
                                             ,quantity                 NUMBER(10,3))
    ORGANIZATION EXTERNAL      (
                                  TYPE ORACLE_LOADER
                                  DEFAULT DIRECTORY directory_eve
                                  ACCESS PARAMETERS
                                  (
                                     RECORDS    DELIMITED  BY newline
                                     BADFILE directory_eve: 'bad_composite.txt'
                                     NODISCARDFILE NOLOGFILE
                                     SKIP 1
                                     FIELDS     TERMINATED BY ','
                                     OPTIONALLY ENCLOSED   BY '"'      
                                     MISSING FIELD VALUES ARE NULL
                                     
                                     (good                  CHAR(100)
                                     ,part                  CHAR(100)
                                     ,quantity              CHAR(10))

                                  )
                                  LOCATION('composite.txt')
    )
    REJECT LIMIT UNLIMITED;






/*
    But External Tables are just a schema on top of a flatfile.
    Most importantly this means that they cannot be Indexed on (=superslow search, superslow JOINs).
    No compromise on performance and so make exact Copies as
    real database tables into which to read the loader data.

    Temporary Tables, especially when ON COMMIT DELETE ROWS, tells everyone
    that no business logic may be used on top of these these tables.
*/
  CREATE GLOBAL TEMPORARY TABLE tmp_load_part           (label                    VARCHAR2(100)
                                                        ,market_browser_path      VARCHAR2(500)
                                                        ,volume                   NUMBER(15,3)
                                                        ,eveapi_part_id           INTEGER
                                                        ,material_efficiency      NUMBER(5,3)
                                                        ,outcome_units            INTEGER
                                                        ,base_invent_success      NUMBER(10,3)
                                                        ,base_invent_copies       INTEGER
                                                        
                                                        ) ON COMMIT DELETE ROWS;

  CREATE INDEX ix_load_part_label          ON tmp_load_part(label);
  CREATE INDEX ix_load_part_eveapi_part_id ON tmp_load_part(eveapi_part_id);



  CREATE GLOBAL TEMPORARY TABLE tmp_load_composite      (good                     VARCHAR2(100)
                                                        ,part                     VARCHAR2(100)
                                                        ,quantity                 NUMBER(10,3)
                                                        
                                                        ) ON COMMIT DELETE ROWS;

  CREATE INDEX ix_load_composite_good      ON tmp_load_composite(good);
  CREATE INDEX ix_load_composite_part      ON tmp_load_composite(part);



  CREATE GLOBAL TEMPORARY TABLE tmp_load_assets         (name                     VARCHAR2(50)             NOT NULL
                                                        ,eveapi_location_id       VARCHAR2(10)             NOT NULL
                                                        ,eveapi_loc_type_id       VARCHAR2(10)             NOT NULL
                                                        ,eveapi_item_type_id      VARCHAR2(10)             NOT NULL
                                                        ,quantity                 INTEGER                  NOT NULL
                                                        
                                                        ) ON COMMIT DELETE ROWS;


  
  CREATE TABLE cache_industry_jobs                      (corp_char_name           VARCHAR2(50)             NOT NULL
                                                        ,cached_until             TIMESTAMP                NOT NULL
                                                        ,xdoc                     XMLTYPE                  NOT NULL);


  CREATE TABLE cache_asset_list                         (corp_char_name           VARCHAR2(50)             NOT NULL
                                                        ,cached_until             TIMESTAMP                NOT NULL
                                                        ,xdoc                     XMLTYPE                  NOT NULL);


  CREATE TABLE cache_market_quicklook                   (item_type_id             VARCHAR2(10)             NOT NULL
                                                        ,cached_until             TIMESTAMP                NOT NULL
                                                        ,xdoc                     XMLTYPE                  NOT NULL

                                                        ,CONSTRAINT pk_cache_market_quicklook   PRIMARY KEY (item_type_id));

  CREATE INDEX ix_cache_mqlook_cached_until ON cache_market_quicklook(cached_until);
  

