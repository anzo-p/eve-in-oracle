CREATE OR REPLACE PACKAGE load_player_data IS


/*
    Access EVE API XML for player data. Currently only getting the assets owned by Player/Corporation.

    Be sure to create an EVE API KEY for your Char and Corp here
      https://community.eveonline.com/support/api-key/
    
    Must read:
      https://developers.eveonline.com/resource/xml-api
      http://wiki.eve-id.net/APIv2_Page_Index
*/


  k_loc_my_pos                   CONSTANT VARCHAR2(10)                        := '12345678'; -- the locationID of your POS here, download XML AssetList manually and deduce from there

  -- here you put the access parameters required to get your Secured player data from EVE Online.

    --         name           id          char/corp   keyid      verification_code
    t_api_key('CORP_NAME',  '12345678', 'corp',     '1234567', 'abcdefghijkljmopqrstuvwxyzABCDEFGHIJLKMNOPQRSTUVWXYZ0123456789ab') -- place your corp XML API keys for the Assets in the Factory
   ,t_api_key('CHAR_NAME',  '12345678', 'char',     '1234567', 'abcdefghijkljmopqrstuvwxyzABCDEFGHIJLKMNOPQRSTUVWXYZ0123456789ab') -- place your char XML API keys for assets in the HaulerCargo Bay
  );


  -- these would belong into loader files, and actually Impel is there already: SELECT * FROM part WHERE label = 'IMPEL'
  k_item_impel                   CONSTANT VARCHAR2(10)                        := '12753';
  k_item_mastodon                CONSTANT VARCHAR2(10)                        := '12747';
  k_item_prorator                CONSTANT VARCHAR2(10)                        := '12733';
  k_item_prowler                 CONSTANT VARCHAR2(10)                        := '12735';
  k_item_fenrir                  CONSTANT VARCHAR2(10)                        := '20189';
  k_item_providence              CONSTANT VARCHAR2(10)                        := '20183';
  k_item_ark                     CONSTANT VARCHAR2(10)                        := '28850';
  k_item_nomad                   CONSTANT VARCHAR2(10)                        := '28846';
  





  PROCEDURE load_pile;


END load_player_data;
/









CREATE OR REPLACE PACKAGE BODY load_player_data AS


  FUNCTION v_get(p_param VARCHAR2)
  RETURN VARCHAR2 AS
    v_return VARCHAR2(30);
  BEGIN
    EXECUTE IMMEDIATE ('BEGIN :1 := load_player_data.'|| p_param ||'; END;') USING IN OUT v_return;
    RETURN v_return;
  END v_get;





  PROCEDURE load_pile AS
/*
    What is the quantity I already have of various items needed in Eve Industry?
    Go get it from the game data in EVE Online Servers and store it.
*/
    v_url               VARCHAR2(500);
    x_doc               XMLTYPE;
    v_cached_until      VARCHAR2(20);
    ts_cached_until     cache_asset_list.cached_until%TYPE;

  BEGIN

--- Get API XML doc
    FOR r_chr IN (SELECT sel.*

      BEGIN
        SELECT xdoc -- Current, Valid API XML DOC from cache
        INTO   x_doc
        FROM   cache_asset_list
        WHERE      corp_char_name         = r_chr.name
        AND    NVL(cached_until, SYSDATE) > SYSDATE;

      EXCEPTION
        WHEN NO_DATA_FOUND THEN -- REFRESH from EVE Online
  
          v_url   :=         'https://api.eveonline.com/' || r_chr.char_corp
                          || '/AssetList.xml.aspx?'
                          || 'keyID='                     || r_chr.keyid
                     ||'&'|| 'vCode='                     || r_chr.verification_code;
  
          IF r_chr.char_corp = 'char' THEN
            v_url := v_url
                     ||'&'||'characterID='                || r_chr.id;
          END IF;
  

          -- get the XML from Web Service
          x_doc := utils.request_xml(v_url);


--- CACHE it up
          SELECT EXTRACTVALUE(VALUE(cch), '//cachedUntil')
          INTO   v_cached_until
          FROM   TABLE(XMLSEQUENCE(EXTRACT(x_doc
                                          ,'/eveapi'))) cch;

          ts_cached_until := TO_TIMESTAMP(v_cached_until, utils.k_mask_timestamp_eveapi_xml) -- <cachedUntil> at Server Timezone
                            +(CAST(SYSTIMESTAMP AS TIMESTAMP)                                -- timezone difference to Host Machine
                             -CAST(SYSTIMESTAMP AT TIME ZONE 'Europe/London' AS TIMESTAMP));


          MERGE INTO cache_asset_list cch

          USING (SELECT r_chr.name      AS corp_char_name
                       ,ts_cached_until AS cached_until
                       ,x_doc           AS xdoc
                 FROM   dual) ins
      
          ON (cch.corp_char_name = ins.corp_char_name)
      
          WHEN MATCHED THEN
            UPDATE
            SET    cch.cached_until = ins.cached_until
                  ,cch.xdoc         = ins.xdoc
            WHERE  cch.cached_until < ins.cached_until
          
          WHEN NOT MATCHED THEN
            INSERT (corp_char_name, cached_until, xdoc)
            VALUES (ins.corp_char_name, ins.cached_until, ins.xdoc);

      END; -- SELECT valid x_doc.. EXCEPTION NO_DATA_FOUND



--- STORE its data into a relational db format
      INSERT INTO tmp_load_assets -- GLOBAL TEMPORARY 

        SELECT r_chr.name
              ,dad.location_id AS eveapi_location_id
              ,dad.type_id     AS eveapi_loc_type_id
              ,cld.type_id     AS eveapi_item_type_id
              ,cld.quantity
        
        FROM       cache_asset_list cch
        INNER JOIN XMLTABLE('for $i in //eveapi/result/rowset/row
                            return $i'
                            PASSING cch.xdoc
                            COLUMNS location_id     VARCHAR2(10) PATH '@locationID'
                                   ,type_id         VARCHAR2(10) PATH '@typeID'
                                   ,lines           XMLTYPE      PATH 'rowset')    dad ON 1=1
  
        INNER JOIN XMLTABLE('/rowset/row'
                            PASSING dad.lines
                            COLUMNS type_id         VARCHAR2(10) PATH '@typeID'
                                   ,quantity        INTEGER      PATH '@quantity') cld ON 1=1
                                   --,flag            INTEGER      PATH '@flag'
                                   --,singleton       INTEGER      PATH '@singleton'
                                   --,raw_quantity    INTEGER      PATH '@rawQuantity'
  
        --LEFT OUTER JOIN part prt ON prt.eveapi_part_id = cld.type_id -- DEBUG
        INNER JOIN part prt ON prt.eveapi_part_id = cld.type_id
        WHERE  cch.corp_char_name = r_chr.name;
        
    END LOOP;
      


    -- finally cumulate to part
    MERGE INTO part prt

    USING (SELECT     prt.eveapi_part_id
                 ,NVL(sel.quantity, 0)   AS quantity

/*
           The EVE API XML AssetList only includes items that the character currently has,
           meaning the XML will NOT notify us that the character 'no longer' has any of it.
           Still we Must then UPDATE part.pile = 0 for the final reports to work:

           1. We need to guarantee a 'WHEN MACTHED' for every row, and we do so
              by making sure this 'USING SELECT' returns *something* for every row.

           2. And so we OUTER JOIN on the XML-data because not sure there is any,
              but INNER JOIN on the same table that we are about to UPDATE (part).

           3. Now, if we find any quantity in the XML, we use that
              but if we dont, we known the pile must be 0.
*/
           FROM             part prt
           LEFT OUTER JOIN (SELECT     eveapi_item_type_id
                                  ,SUM(quantity)           AS quantity
                                  
                            FROM  (SELECT eveapi_item_type_id, quantity -- from Factory Hangars
                                   FROM       tmp_load_assets ast
                                   WHERE  chr.char_corp           = 'corp'
                                   AND    ast.eveapi_location_id  =  load_player_data.v_get('k_loc_my_pos') -- if you copy this SQL out and DEBUG, it helps to have the v_get():s
                                   
                                   UNION ALL

                                   SELECT eveapi_item_type_id, quantity -- from my various Ship Cargoes if I maybe havent had time to drop them to factory yet
                                   WHERE  ast.name                = 'char'
                                   AND    ast.eveapi_loc_type_id IN (load_player_data.v_get('k_item_impel')
                                                                    ,load_player_data.v_get('k_item_mastodon')
                                                                    ,load_player_data.v_get('k_item_prorator')
                                                                    ,load_player_data.v_get('k_item_prowler')
                                                                    ,load_player_data.v_get('k_item_fenrir')
                                                                    ,load_player_data.v_get('k_item_providence')
                                                                    ,load_player_data.v_get('k_item_ark')))                                   
                                                          
                            GROUP BY eveapi_item_type_id) sel ON sel.eveapi_item_type_id = prt.eveapi_part_id) ins

    ON (prt.eveapi_part_id = ins.eveapi_part_id)
    
    WHEN MATCHED THEN
      UPDATE
      SET    prt.pile = ins.quantity
      
    -- WHEN NOT MATCHED THEN NO ACTION
    ;




    COMMIT;
    

  END load_pile;





END load_player_data;
/
