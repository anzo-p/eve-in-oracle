CREATE OR REPLACE PACKAGE load_indu_details IS

/*
    Inserts data about Parts and the Composition rules over how those parts can be used to build more advanced parts.
    Used to have a table Produce here, which linked all Composite rows per end-Good together, but moved all that logics
    into MW_PRODUCE, see 7_create_view.sql.
*/



/*
    Future Plans...

    Make a program that calculates through all combinations for reverse engineering and also invention
    And materialises a plan out of which it is the evident which setup works best and how the different compare

    However on the face of it subsystem BPCs have all except one input materials with quantity 1, making them neglectable candidates altogether for any decryprots
    T3 Strategic Cruiser hulls however will benefit much from either Process or Accel decryptor
    T3 Tactical Destroyers will benefit marginally from ME and only with Batches of over 5 rounds.

  a_modifiers                    CONSTANT t_modifiers := t_modifiers(

    --           label                             probability   runs     me
    t_decryptor('ACCELERANT DECRYPTOR',                  '+20',   '+1',  '+2')
   ,t_decryptor('ATTAINMENT DECRYPTOR',                  '+80',   '+4',  '-1')
   ,t_decryptor('AUGMENTATION DECRYPTOR',                '-40',   '+9',  '-2')
   ,t_decryptor('OPTIMIZED ATTAINMENT DECRYPTOR',        '+90',   '+2',  '+1')
   ,t_decryptor('OPTIMIZED AUGMENTATION DECRYPTOR',      '-10',   '+7',  '+2')
   ,t_decryptor('PARITY DECRYPTOR',                      '+50',   '+3',  '+1')
   ,t_decryptor('PROCESS DECRYPTOR',                     '+10',    '0',  '+3')
   ,t_decryptor('SYMMETRY DECRYPTOR',                      '0',   '+2',  '+1')
  );
*/
  


  PROCEDURE merge_part_composite;
  PROCEDURE refresh_views;
  PROCEDURE merge_keywords           (p_part_id      IN part.ident%TYPE
                                     ,p_keywords     IN VARCHAR2);



END load_indu_details;
/





CREATE OR REPLACE PACKAGE BODY load_indu_details AS



  PROCEDURE pre_checks AS
/*
    Sure dbms Table Constraints are the real way to resist anomalous data.
    But this code is needed to Alert those very violating rows.
*/  
    r_part         tmp_load_part%ROWTYPE;
    r_composite    tmp_load_composite%ROWTYPE;
  
  BEGIN
  
    BEGIN
      SELECT one.*
      INTO   r_part
      FROM       tmp_load_part one
      INNER JOIN tmp_load_part oth  ON oth.label  = one.label
                                   AND oth.ROWID <> one.ROWID
      WHERE  one.label IS NOT NULL
      AND    ROWNUM = 1;
  
      RAISE_APPLICATION_ERROR(-20000, 'DUPLICATE PART: ' || r_part.label);
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        NULL;
    END;


    BEGIN
      SELECT one.*
      INTO   r_part
      FROM       tmp_load_part one
      INNER JOIN tmp_load_part oth  ON oth.eveapi_part_id = one.eveapi_part_id
                                   AND oth.ROWID         <> one.ROWID
      WHERE  one.label          IS NOT NULL
      AND    oth.label          IS NOT NULL
      AND    one.eveapi_part_id IS NOT NULL
      AND    oth.eveapi_part_id IS NOT NULL
      AND    ROWNUM              = 1;
  
      RAISE_APPLICATION_ERROR(-20000, 'DUPLICATE EVEAPI_ID: ' || r_part.label || ', ID: ' || r_part.eveapi_part_id);
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        NULL;
    END;


    BEGIN 
      SELECT *
      INTO   r_composite
      FROM   tmp_load_composite
      WHERE  good   = part
      AND    ROWNUM = 1;

      RAISE_APPLICATION_ERROR(-20000, 'Good = ' || r_composite.good || ' = Part is going for INFINITE LOOP');
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        NULL;
    END;


    BEGIN
      SELECT *
      INTO   r_composite
      FROM   tmp_load_composite cmp
      WHERE  good    IS  NOT NULL

      AND   (NOT EXISTS (SELECT 1 FROM tmp_load_part sub WHERE sub.label = cmp.good)
               OR
             NOT EXISTS (SELECT 1 FROM tmp_load_part sub WHERE sub.label = cmp.part))

      AND    ROWNUM   = 1;

      RAISE_APPLICATION_ERROR(-20000, r_composite.good || ' or ' || r_composite.part || ' is missing from part.txt, though required for ' || r_composite.good);
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        NULL;
    END;

  
  END pre_checks;




  PROCEDURE cache_externals AS
/*
    Putting those External Data into Internal data will speed up processing.
*/

    CURSOR c_part IS
      SELECT *
      FROM   ext_load_part
      WHERE  label IS NOT NULL;

    CURSOR c_composite IS
      SELECT *
      FROM   ext_load_composite
      WHERE  good IS NOT NULL;


    TYPE t_part            IS TABLE OF tmp_load_part%ROWTYPE         INDEX BY BINARY_INTEGER;
    TYPE t_composite       IS TABLE OF tmp_load_composite%ROWTYPE    INDEX BY BINARY_INTEGER;

    a_part                 t_part;
    a_composite            t_composite;

  BEGIN

    OPEN  c_part;
    FETCH c_part BULK COLLECT INTO a_part;
    CLOSE c_part;
      
    FORALL i IN a_part.FIRST .. a_part.LAST
      INSERT INTO tmp_load_part
      VALUES a_part(i);


    OPEN  c_composite;
    FETCH c_composite BULK COLLECT INTO a_composite;
    CLOSE c_composite;
      
    FORALL i IN a_composite.FIRST .. a_composite.LAST
      INSERT INTO tmp_load_composite
      VALUES a_composite(i);

  END cache_externals;
  
  
  
  
  PROCEDURE merge_keywords(p_part_id  IN part.ident%TYPE
                          ,p_keywords IN VARCHAR2) AS
/*
    p_keywords is one or more keywords linked together in a Disk System Folder-like fashion so to
    mimic the familiar Hierarcy at the Market Window in EVE Online. See part.txt loader file, column 'path'.
*/
    v_keywd_path     VARCHAR2(500)      := p_keywords;
    v_keywd_next     keyword.label%TYPE;
    n_keyword_id     keyword.ident%TYPE;

  BEGIN

    IF p_keywords IS NULL THEN
      RETURN;
    END IF;

    v_keywd_path := TRIM ('/' FROM v_keywd_path);
    v_keywd_path := UPPER(v_keywd_path);          -- Small Caps in loader file for Readability, though store the keywords CAPSed, like all else.

    LOOP
    
      IF 0 < INSTR(v_keywd_path, '/') THEN
        v_keywd_next := SUBSTR(v_keywd_path, 1, INSTR(v_keywd_path, '/') -1);
        v_keywd_path := SUBSTR(v_keywd_path,    INSTR(v_keywd_path, '/') +1);
      ELSE
        v_keywd_next := v_keywd_path;
        v_keywd_path := NULL;
      END IF;
    
      -- DEBUG
      --dbms_output.put_line('PATH>'||v_keywd_path||'<');
      --dbms_output.put_line('SNIP>'||v_keywd_next||'<');

      -- insert keyword in the old way to return the ident
      BEGIN
        SELECT ident 
        INTO   n_keyword_id
        FROM   keyword
        WHERE  label = v_keywd_next;
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
      
          INSERT INTO keyword(ident, label)
          VALUES (sq_general.NEXTVAL, v_keywd_next)
          RETURNING ident INTO n_keyword_id;
      END;

      -- now we have the required ( part_id, keyword_id } MERGE the mapping
      MERGE INTO keyword_map kwm
      USING (SELECT n_keyword_id AS keyword_id                   
             FROM   keyword
             WHERE  label = v_keywd_next) ins
  
      ON (    kwm.keyword_id = ins.keyword_id
          AND kwm.part_id    = p_part_id)
  
      WHEN NOT MATCHED THEN
        INSERT (keyword_id, part_id)
        VALUES (n_keyword_id, p_part_id);
  

      EXIT WHEN v_keywd_path IS NULL; -- no more remaining keywords in list

    END LOOP;

  EXCEPTION
    WHEN OTHERS THEN
      RAISE_APPLICATION_ERROR(-20000, p_part_id ||', '|| SQLERRM);

  END merge_keywords;




  PROCEDURE refresh_views AS
/*
    Basically if base Industry data changes then alo redo its 'Application Layer'.
*/
  BEGIN

    DBMS_MVIEW.REFRESH(                        'EVE.MW_COMPOSITE'
                      ,method               => 'C'
                      ,rollback_seg         => ''
                      ,push_deferred_rpc    => FALSE
                      ,refresh_after_errors => FALSE
                      ,purge_option         => 0
                      ,parallelism          => 0
                      ,heap_size            => 0
                      ,atomic_refresh       => TRUE);
                      
    DBMS_MVIEW.REFRESH(                        'EVE.MW_PRODUCE'
                      ,method               => 'C'
                      ,rollback_seg         => ''
                      ,push_deferred_rpc    => FALSE
                      ,refresh_after_errors => FALSE
                      ,purge_option         => 0
                      ,parallelism          => 0
                      ,heap_size            => 0
                      ,atomic_refresh       => TRUE);

  END refresh_views;




  PROCEDURE merge_part_composite AS
/*
    MERGE makes it possible to run unlimited 'Refresh All's. Change any value at loader files even from/to NULL
    and it will be set into the system tables, provided that the column accepts NULLs.
    
    However, if you change ANY Value that goes into the MERGE...ON (...) -clause, you will need to...
    ...well simplest way then is to DELETE part and composite and rerun this procedure.
*/
    
    n_part_id            part.ident%TYPE;
  
  BEGIN
  
    cache_externals;
    pre_checks;


    MERGE INTO part prt -- Aka. INSERT.. EXCEPTION WHEN DUP_VAL_ON_INDEX THEN UPDATE..

    USING (SELECT     label
                 ,    eveapi_part_id
                 ,    volume
                 ,NVL(material_efficiency, 0) AS material_efficiency
                 ,NVL(outcome_units,       1) AS outcome_units
                 ,    base_invent_success
                 ,    base_invent_copies
           FROM   tmp_load_part
           WHERE  label IS NOT NULL) ins

    ON (prt.label = ins.label)
    
    WHEN MATCHED THEN
      UPDATE
      SET    prt.eveapi_part_id      = ins.eveapi_part_id
            ,prt.volume              = ins.volume
            ,prt.material_efficiency = ins.material_efficiency
            ,prt.outcome_units       = ins.outcome_units
            ,prt.base_invent_success = ins.base_invent_success
            ,prt.base_invent_copies  = ins.base_invent_copies

      WHERE  NVL(prt.eveapi_part_id,        utils.k_dummy_number) <> NVL(ins.eveapi_part_id,      utils.k_dummy_number)
      OR     NVL(prt.volume,                utils.k_dummy_number) <> NVL(ins.volume,              utils.k_dummy_number)
      OR     NVL(prt.material_efficiency,   utils.k_dummy_number) <> NVL(ins.material_efficiency, utils.k_dummy_number)
      OR     NVL(prt.outcome_units,         utils.k_dummy_number) <> NVL(ins.outcome_units,       utils.k_dummy_number)
      OR     NVL(prt.base_invent_success,   utils.k_dummy_number) <> NVL(ins.base_invent_success, utils.k_dummy_number)
      OR     NVL(prt.base_invent_copies,    utils.k_dummy_number) <> NVL(ins.base_invent_copies,  utils.k_dummy_number)
    
    WHEN NOT MATCHED THEN
      INSERT (ident, label, eveapi_part_id, volume, material_efficiency
             ,outcome_units, base_invent_success, base_invent_copies)

      VALUES (sq_general.NEXTVAL, ins.label, ins.eveapi_part_id, ins.volume, ins.material_efficiency
             ,ins.outcome_units, ins.base_invent_success, ins.base_invent_copies);



    FOR i IN (SELECT label
                    ,market_browser_path
              FROM   tmp_load_part
              WHERE  label IS NOT NULL) LOOP

      SELECT ident
      INTO   n_part_id
      FROM   part
      WHERE  label = i.label;

      merge_keywords(p_part_id  => n_part_id
                    ,p_keywords => i.market_browser_path);
                    
    END LOOP;



    MERGE INTO composite cpr

    USING (SELECT (SELECT ident FROM part
                   WHERE  label = good) AS good_id
                   
                 ,(SELECT ident FROM part
                   WHERE  label = part) AS part_id
    
                 ,good
                 ,part
                 ,quantity
           FROM   tmp_load_composite
           WHERE  good IS NOT NULL) ins

    ON (    cpr.good_id = ins.good_id
        AND cpr.part_id = ins.part_id)
    
    WHEN MATCHED THEN
      UPDATE
      SET    cpr.quantity = ins.quantity  

      WHERE  NVL(cpr.quantity, utils.k_dummy_number) <> NVL(ins.quantity, utils.k_dummy_number)
    
    WHEN NOT MATCHED THEN
      INSERT (ident, good_id, part_id, good, part, quantity)
      VALUES (sq_general.NEXTVAL, ins.good_id, ins.part_id, ins.good, ins.part, ins.quantity);
  


    refresh_views;



    COMMIT;

  END merge_part_composite;
  
  
  
END load_indu_details;
/
