CREATE OR REPLACE PACKAGE utils IS


  k_pos_bonus_me                  CONSTANT part.material_efficiency%TYPE       := 2;

  k_numeric_true                  CONSTANT PLS_INTEGER                         := 1;
  k_numeric_false                 CONSTANT PLS_INTEGER                         := 0;
  k_string_true                   CONSTANT VARCHAR2(5)                         := 'TRUE';
  k_string_false                  CONSTANT VARCHAR2(5)                         := 'FALSE';

  k_dummy_number                  CONSTANT PLS_INTEGER                         := 1;
  k_dummy_string                  CONSTANT VARCHAR2(5)                         := 'DUMMY';
  k_dummy_date                    CONSTANT DATE                                := TO_DATE('01.01.2000', 'DD.MM.YYYY');

  k_mask_price_eveapi_xml         CONSTANT VARCHAR2(20)                        := '999999999999999D99';
  k_mask_date_eveapi_xml          CONSTANT VARCHAR2(10)                        := 'YYYY-MM-DD';
  k_mask_timestamp_eveapi_xml     CONSTANT VARCHAR2(21)                        := 'YYYY-MM-DD HH24:MI:SS';
  k_nls_decimal_chars             CONSTANT VARCHAR2(35)                        := 'NLS_NUMERIC_CHARACTERS = ''.,''';

  k_location_wallet               CONSTANT all_directories.directory_path%TYPE := 'file:/u01/app/oracle/admin/orcl/wallet';





  FUNCTION  v_get               (p_param                  VARCHAR2)                              RETURN VARCHAR2;
  FUNCTION  n_get               (p_param                  VARCHAR2)                              RETURN PLS_INTEGER;
  FUNCTION  f_get               (p_param                  VARCHAR2)                              RETURN BINARY_DOUBLE;
  FUNCTION  d_get               (p_param                  VARCHAR2)                              RETURN DATE;

  FUNCTION  calculate           (p_param                  VARCHAR2)                              RETURN BINARY_DOUBLE;
  
  FUNCTION  repeat              (p_label                  VARCHAR2
                                ,p_times                  PLS_INTEGER)                           RETURN VARCHAR2;

  FUNCTION  request_xml         (p_url                    VARCHAR2)                              RETURN XMLTYPE;
  
  FUNCTION  per_cent            (p_share                  NUMBER
                                ,p_total                  NUMBER
                                ,p_decimals               PLS_INTEGER          DEFAULT NULL)     RETURN NUMBER;

  FUNCTION  readable_ore        (p_param                  VARCHAR2)                              RETURN VARCHAR2;

  FUNCTION  keywd               (p_part_id                part.ident%TYPE
                                ,p_keyword                keyword.label%TYPE)                    RETURN PLS_INTEGER;

  FUNCTION  keywd               (p_label                  part.label%TYPE
                                ,p_keyword                keyword.label%TYPE)                    RETURN PLS_INTEGER;


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


  FUNCTION n_get(p_param VARCHAR2)
  RETURN PLS_INTEGER AS
    n_return BINARY_DOUBLE;
  BEGIN
    EXECUTE IMMEDIATE ('BEGIN :1 := utils.'|| p_param ||'; END;') USING IN OUT n_return;
    RETURN n_return;
  END n_get;


  FUNCTION d_get(p_param VARCHAR2)
  RETURN DATE AS
    d_return DATE;
  BEGIN
    EXECUTE IMMEDIATE ('BEGIN :1 := utils.'|| p_param ||'; END;') USING IN OUT d_return;
    RETURN d_return;
  END d_get;




  FUNCTION calculate(p_param VARCHAR2)
  RETURN BINARY_DOUBLE AS
    f_return BINARY_DOUBLE;
  BEGIN
    EXECUTE IMMEDIATE ('BEGIN :1 :='|| p_param ||' ; END;') USING IN OUT f_return;
    RETURN f_return;
  END calculate;



  FUNCTION repeat(p_label VARCHAR2
                 ,p_times PLS_INTEGER)
  RETURN VARCHAR2 AS
    n_counter PLS_INTEGER    := p_times;
    v_return  VARCHAR2(1000);
  BEGIN
    LOOP
      EXIT WHEN n_counter <= 0;
      v_return  := v_return || p_label;
      n_counter := n_counter - 1;
    END LOOP;
    RETURN v_return;
  END repeat;




  FUNCTION request_xml(p_url VARCHAR2)
  RETURN XMLTYPE AS
/*
    THIS SUPERTINY FUNCTION IS OUR 'DRIVER'! \o/
    All we need is few Oracle RDBMS Built-Ins!

    (Having now seen this code, go figure the Insanely Complex Java-practices
     aka. "already existing Drivers" that Youll come across haha, lol.

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




  FUNCTION keywd(p_part_id part.ident%TYPE
                ,p_keyword keyword.label%TYPE)
  RETURN PLS_INTEGER AS
    n_dummy PLS_INTEGER;
  BEGIN
    SELECT 1
    INTO   n_dummy
    FROM       keyword     kwd
    INNER JOIN keyword_map kmp ON kmp.keyword_id = kwd.ident
    WHERE  kmp.part_id = p_part_id
    AND    kwd.label   = UPPER(p_keyword);
    
    RETURN k_numeric_true;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RETURN k_numeric_false;
  END keywd;


  FUNCTION keywd(p_label   part.label%TYPE
                ,p_keyword keyword.label%TYPE)
  RETURN PLS_INTEGER AS
/*
    ONLY come here if you dont know the part.ident!
    If you do know, or the code knows, use the part.ident%TYPE OVERRIDE to skip this extra SELECT
*/
    n_part_id part.ident%TYPE;
  BEGIN
    SELECT ident
    INTO   n_part_id
    FROM   part
    WHERE  label = UPPER(p_label);
    
    RETURN keywd(p_part_id => n_part_id
                ,p_keyword => p_keyword);
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RETURN k_numeric_false;
  END keywd;



END utils;
/