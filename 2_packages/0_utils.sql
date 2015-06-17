CREATE OR REPLACE PACKAGE utils IS


  k_location_wallet               CONSTANT all_directories.directory_path%TYPE := 'file:/u01/app/oracle/admin/orcl/wallet';

  k_dummy_number                  CONSTANT PLS_INTEGER                         := 1;
  k_dummy_string                  CONSTANT VARCHAR2(5)                         := 'DUMMY';
  k_dummy_date                    CONSTANT DATE                                := TO_DATE('01.01.2000', 'DD.MM.YYYY');

  k_mask_price_eveapi_xml         CONSTANT VARCHAR2(20)                        := '999999999999999D99';
  k_mask_date_eveapi_xml          CONSTANT VARCHAR2(10)                        := 'YYYY-MM-DD';
  k_mask_timestamp_eveapi_xml     CONSTANT VARCHAR2(21)                        := 'YYYY-MM-DD HH24:MI:SS';
  k_nls_decimal_chars             CONSTANT VARCHAR2(35)                        := 'NLS_NUMERIC_CHARACTERS = ''.,''';




  FUNCTION  v_get               (p_param                  VARCHAR2)                              RETURN VARCHAR2;
  FUNCTION  f_get               (p_param                  VARCHAR2)                              RETURN BINARY_DOUBLE;
  FUNCTION  d_get               (p_param                  VARCHAR2)                              RETURN DATE;

  FUNCTION  request_xml         (p_url                    VARCHAR2)                              RETURN XMLTYPE;
  
  FUNCTION  per_cent            (p_share                  NUMBER
                                ,p_total                  NUMBER
                                ,p_decimals               PLS_INTEGER          DEFAULT NULL)     RETURN NUMBER;

  FUNCTION  readable_ore        (p_param                  VARCHAR2)                              RETURN VARCHAR2;



END utils;
/





CREATE OR REPLACE PACKAGE BODY utils AS



  FUNCTION v_get(p_param VARCHAR2)
  RETURN VARCHAR2 AS
    v_return VARCHAR2(30);
  BEGIN
    EXECUTE IMMEDIATE ('BEGIN :1 := utils.'|| p_param ||'; END;') USING IN OUT v_return;
    RETURN v_return;
  END v_get;


  FUNCTION f_get(p_param VARCHAR2)
  RETURN BINARY_DOUBLE AS
    f_return BINARY_DOUBLE;
  BEGIN
    EXECUTE IMMEDIATE ('BEGIN :1 := utils.'|| p_param ||'; END;') USING IN OUT f_return;
    RETURN f_return;
  END f_get;


  FUNCTION d_get(p_param VARCHAR2)
  RETURN DATE AS
    d_return DATE;
  BEGIN
    EXECUTE IMMEDIATE ('BEGIN :1 := utils.'|| p_param ||'; END;') USING IN OUT d_return;
    RETURN d_return;
  END d_get;




  FUNCTION request_xml(p_url VARCHAR2)
  RETURN XMLTYPE AS
/*
    Gets the XML through http and returns it as a SELECTable datatype.
*/
    l_site       CLOB;
    a_pieces     utl_http.html_pieces;    
    x_doc        XMLTYPE;
  
  BEGIN

    -- needed when Oracle validates https security certificates
    utl_http.set_wallet(utils.k_location_wallet, 'SomePasswd123');


    dbms_lob.createtemporary(lob_loc => l_site
                            ,cache   => TRUE);

    a_pieces := utl_http.request_pieces(p_url);

    -- append to single searchable object
    FOR r_piece IN a_pieces.FIRST .. a_pieces.LAST LOOP
  
      dbms_lob.writeappend(lob_loc => l_site
                          ,amount  => LENGTH(a_pieces(r_piece))
                          ,buffer  => a_pieces(r_piece));
    END LOOP;
    

    x_doc := XMLTYPE.CREATEXML(l_site);
    dbms_lob.freetemporary(l_site);


    RETURN x_doc;

  EXCEPTION
    WHEN OTHERS THEN
      dbms_lob.freetemporary(l_site);
      RAISE;

  END request_xml;




  FUNCTION per_cent(p_share    NUMBER
                   ,p_total    NUMBER
                   ,p_decimals PLS_INTEGER   DEFAULT NULL)
  RETURN NUMBER AS
    f_per_cent NUMBER;
  BEGIN
    IF p_share IS NULL OR
       p_total IS NULL THEN
      RETURN NULL;
    END IF;
    
    BEGIN
      f_per_cent := (p_share/p_total) *100;
    EXCEPTION
      WHEN ZERO_DIVIDE THEN
        f_per_cent := 0;
    END;

    IF p_decimals IS NOT NULL THEN
      f_per_cent := ROUND(f_per_cent, p_decimals);
    END IF;

    RETURN f_per_cent;

  END per_cent;




  FUNCTION readable_ore(p_param VARCHAR2)
  RETURN VARCHAR2 AS
  BEGIN
    IF 0 < INSTR(p_param, ' ') THEN
      RETURN SUBSTR(p_param,    INSTR(p_param, ' ') +1) || ', ' ||
             SUBSTR(p_param, 1, INSTR(p_param, ' ') -1);
    ELSE
      RETURN p_param;
    END IF;
  END readable_ore;



END utils;
/