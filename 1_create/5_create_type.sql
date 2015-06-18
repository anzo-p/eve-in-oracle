
/*
    These types are needed in the logics when Casting an Array (TYPE .. IS TABLE OF) as a database Table.
    A typical need for this is when we have data that need to be initialized into database
    right when the module itself loads into memory.
    
    Functionally it is similar to having the data in loader files and having external tables on those
    except that here the the data is stored in the package header (*.pks) as Object and we can see
    both data and code in the same file. Good when experimenting.
*/




  DROP TYPE  t_all_regions;
  DROP TYPE  t_region;
  DROP TYPE  t_char_corp;
  DROP TYPE  t_api_key;




  CREATE OR REPLACE TYPE t_region          AS OBJECT  (eveapi_region_id     INTEGER
                                                      ,name_region          VARCHAR2(100));

  CREATE OR REPLACE TYPE t_all_regions     AS TABLE OF t_region;


  CREATE OR REPLACE TYPE t_api_key         AS OBJECT  (name                VARCHAR2(50)
                                                      ,id                  VARCHAR2(10)
                                                      ,char_corp           VARCHAR2(10)
                                                      ,keyid               VARCHAR2(10)
                                                      ,verification_code   VARCHAR2(100));

  CREATE OR REPLACE TYPE t_char_corp       AS TABLE OF t_api_key;

