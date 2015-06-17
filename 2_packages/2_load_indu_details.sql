CREATE OR REPLACE PACKAGE load_indu_details IS

/*
    Inserts data about Parts and the Composition rules over how those parts can be used to build more advanced parts.
    Then uses those data to define all required parts and their quantities in order to build specific Products (table Produce).

    The compositions have something called material_efficiency: a value that decreases the quantities of required parts.
    And those Material Efficiencies are different for different compositions (called 'Blueprints' in EVE Online).
    It is more convenient both programmatically and performancewise to materialise them in advance, before SELECTing.

    A little bit unfortuntely, all logics regarding material efficiency cannot be done here, but some will bubble up to SQLs.
    This goes to illustrate how complex the rules are already in the EVE Online source code.
*/



  k_pos_saves_extra_me           CONSTANT part.material_efficiency%TYPE     := 2;
  

  PROCEDURE merge_part_composite;
  PROCEDURE define_all_products;


END load_indu_details;
/





CREATE OR REPLACE PACKAGE BODY load_indu_details AS



  PROCEDURE pre_checks AS
/*
    Sure dbms Table Constraints are the real way to resist anomalous data.
    But this code is needed to Alert those very violating rows.
*/  
    r_domain       ext_load_domain%ROWTYPE;
    r_part         tmp_load_part%ROWTYPE;
    r_composite    tmp_load_composite%ROWTYPE;
  
  BEGIN
  
    BEGIN
      SELECT one.*
      INTO   r_domain
      FROM       ext_load_domain one
      INNER JOIN ext_load_domain oth  ON oth.domain = one.domain
                                     AND oth.value  = one.value
                                     AND oth.ROWID <> one.ROWID
      WHERE  one.domain IS NOT NULL
      AND    ROWNUM = 1;
  
      RAISE_APPLICATION_ERROR(-20000, 'DUPLICATE CONSTANT: ' || r_domain.value);
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        NULL; -- these checks are only expected to find violations against db semantical integrity
    END;
  
  
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

      RAISE_APPLICATION_ERROR(-20000, 'Composition rules exists for ' || r_composite.good || ' - but this item is MISSING from part.txt');
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




  PROCEDURE merge_part_composite AS
  
    CURSOR c_race IS
      SELECT *
      FROM   ext_load_domain
      WHERE  domain = 'RACE';
  
    CURSOR c_material_origin IS
      SELECT *
      FROM   ext_load_domain
      WHERE  domain = 'MATERIAL_ORIGIN';
  
    CURSOR c_item_class IS
      SELECT *
      FROM   ext_load_domain
      WHERE  domain = 'ITEM_CLASS';
    
    CURSOR c_part IS
      SELECT *
      FROM   tmp_load_part  prt
      WHERE  prt.label IS NOT NULL;

    CURSOR c_composite IS
      SELECT *
      FROM   tmp_load_composite
      WHERE  good IS NOT NULL;
      
  
    TYPE t_race                IS TABLE OF c_race%ROWTYPE                INDEX BY BINARY_INTEGER;
    TYPE t_material_origin     IS TABLE OF c_material_origin%ROWTYPE     INDEX BY BINARY_INTEGER;
    TYPE t_item_class          IS TABLE OF c_item_class%ROWTYPE          INDEX BY BINARY_INTEGER;
    TYPE t_part                IS TABLE OF c_part%ROWTYPE                INDEX BY BINARY_INTEGER;
    TYPE t_composite           IS TABLE OF c_composite%ROWTYPE           INDEX BY BINARY_INTEGER;
  
    a_race                     t_race;
    a_material_origin          t_material_origin;
    a_item_class               t_item_class;
    a_part                     t_part;
    a_composite                t_composite;
  
  BEGIN
  
    cache_externals;
    pre_checks;
      
  
    OPEN  c_race;
    FETCH c_race BULK COLLECT INTO a_race;
    CLOSE c_race;
      
    IF a_race.COUNT > 0 THEN
      FORALL i IN a_race.FIRST .. a_race.LAST
        MERGE INTO domain_race dom
        USING (SELECT a_race(i).value AS race
               FROM   dual) ins             
        ON (dom.race = ins.race)      
        WHEN NOT MATCHED THEN
          INSERT (race)
          VALUES (ins.race);
    END IF;
  
  
    OPEN  c_material_origin;
    FETCH c_material_origin BULK COLLECT INTO a_material_origin;
    CLOSE c_material_origin;
      
    IF a_material_origin.COUNT > 0 THEN
      FORALL i IN a_material_origin.FIRST .. a_material_origin.LAST    
        MERGE INTO domain_material_origin dom
        USING (SELECT a_material_origin(i).value AS origin
               FROM   dual) ins             
        ON (dom.origin = ins.origin)
        WHEN NOT MATCHED THEN
          INSERT (origin)
          VALUES (ins.origin);
    END IF;
  
  
    OPEN  c_item_class;
    FETCH c_item_class BULK COLLECT INTO a_item_class;
    CLOSE c_item_class;
      
    IF a_item_class.COUNT > 0 THEN
      FORALL i IN a_item_class.FIRST .. a_item_class.LAST
        MERGE INTO domain_class dom
        USING (SELECT a_item_class(i).value AS class
               FROM   dual) ins
        ON (dom.class = ins.class)      
        WHEN NOT MATCHED THEN
          INSERT (class)
          VALUES (ins.class);
    END IF;
  
  
  
    OPEN  c_part;
    FETCH c_part BULK COLLECT INTO a_part;
    CLOSE c_part;
  
  
    IF a_part.COUNT > 0 THEN
  
      FORALL i IN a_part.FIRST .. a_part.LAST

        MERGE INTO part prt -- Aka. INSERT.. EXCEPTION WHEN DUP_VAL_ON_INDEX THEN UPDATE..
        
        USING (SELECT     a_part(i).label                   AS label
                     ,    a_part(i).eveapi_part_id          AS eveapi_part_id
                     ,    a_part(i).race                    AS race
                     ,    a_part(i).class                   AS class
                     ,    a_part(i).tech                    AS tech
                     ,    a_part(i).material_origin         AS material_origin
                     ,    a_part(i).volume                  AS volume
                     ,NVL(a_part(i).material_efficiency, 0) AS material_efficiency
  
               FROM   dual) ins
  
        ON (prt.label = ins.label)
        
        WHEN MATCHED THEN
          UPDATE
          SET    prt.race                = ins.race
                ,prt.eveapi_part_id      = ins.eveapi_part_id
                ,prt.class               = ins.class
                ,prt.tech                = ins.tech
                ,prt.material_origin     = ins.material_origin
                ,prt.volume              = ins.volume
                ,prt.material_efficiency = ins.material_efficiency
  
          WHERE  NVL(prt.eveapi_part_id,        utils.k_dummy_number) <> NVL(ins.eveapi_part_id,      utils.k_dummy_number)
          OR     NVL(prt.race,                  utils.k_dummy_string) <> NVL(ins.race,                utils.k_dummy_string)
          OR     NVL(prt.class,                 utils.k_dummy_string) <> NVL(ins.class,               utils.k_dummy_string)
          OR     NVL(prt.tech,                  utils.k_dummy_number) <> NVL(ins.tech,                utils.k_dummy_number)
          OR     NVL(prt.material_origin,       utils.k_dummy_string) <> NVL(ins.material_origin,     utils.k_dummy_string)
          OR     NVL(prt.volume,                utils.k_dummy_number) <> NVL(ins.volume,              utils.k_dummy_number)
          OR     NVL(prt.material_efficiency,   utils.k_dummy_number) <> NVL(ins.material_efficiency, utils.k_dummy_number)
        
        WHEN NOT MATCHED THEN
          INSERT (label, eveapi_part_id, race, class
                 ,tech, material_origin, volume, material_efficiency)

          VALUES (ins.label, ins.eveapi_part_id, ins.race, ins.class
                 ,ins.tech, ins.material_origin, ins.volume, ins.material_efficiency);
          
    END IF;
    
      
  
    OPEN  c_composite;
    FETCH c_composite BULK COLLECT INTO a_composite;
    CLOSE c_composite;
  
  
    IF a_composite.COUNT > 0 THEN
  
      FORALL i IN a_composite.FIRST .. a_composite.LAST
      
        MERGE INTO composite cpr
        
        USING (SELECT a_composite(i).good                 AS good
                     ,a_composite(i).part                 AS part
                     ,a_composite(i).quantity             AS quantity
                     ,a_composite(i).materially_efficient AS materially_efficient
  
               FROM   dual) ins
  
        ON (    cpr.good = ins.good
            AND cpr.part = ins.part)
        
        WHEN MATCHED THEN
          UPDATE
          SET    cpr.quantity             = ins.quantity
                ,cpr.materially_efficient = ins.materially_efficient
  
          WHERE  NVL(cpr.quantity,             utils.k_dummy_number) <> NVL(ins.quantity,             utils.k_dummy_number)
          OR     NVL(cpr.materially_efficient, utils.k_dummy_string) <> NVL(ins.materially_efficient, utils.k_dummy_string)
        
        WHEN NOT MATCHED THEN
          INSERT (good, part, quantity, materially_efficient)
          VALUES (ins.good, ins.part, ins.quantity, ins.materially_efficient);
  
    END IF;
  


    COMMIT;

  END merge_part_composite;




  PROCEDURE define_full_list_of_materials(p_good           IN produce.good%TYPE
                                         ,p_subheader      IN produce.subheader%TYPE      DEFAULT NULL
                                         ,p_multiplier     IN produce.quantity%TYPE       DEFAULT 1
                                         ,p_multiplier_pos IN produce.quantity_pos%TYPE   DEFAULT 1) AS
/*
    THIS Procedure is the most important piece of code!
    
    Materializes all required materials (part) for all products (produce).
    Correct material efficiency applies to every distinct Industry Job in EVE.
    Recursively drills down on products that are themselves composites of composites.
    Particularly important as products may have different material efficiencies
    on different underlying composites/jobs (=effectively denying a single SQL).
    
    Amounts are decimals to allow later SQL to calculate ME on Batches.
*/

    CURSOR c_composite(pc_good composite.good%TYPE) IS
      SELECT *
      FROM   vw_composite
      WHERE  good = pc_good;


    TYPE t_cmp          IS TABLE OF c_composite%ROWTYPE   INDEX BY BINARY_INTEGER;
    a_cmp               t_cmp;
                                 
    f_meffic            part.material_efficiency%TYPE;
    f_quantity          composite.quantity%TYPE;
    f_meffic_pos        part.material_efficiency%TYPE;
    f_quantity_pos      composite.quantity%TYPE;
    n_this_part         produce.ident%TYPE;
    n_dummy             PLS_INTEGER;  


    FUNCTION get_quantity_this_input_item(p_materially_efficient IN composite.materially_efficient%TYPE
                                         ,p_quantity             IN composite.quantity%TYPE
                                         ,p_multiplier           IN produce.quantity%TYPE
                                         ,p_material_efficiency  IN part.material_efficiency%TYPE)
    RETURN composite.quantity%TYPE AS

      f_return   composite.quantity%TYPE;    
    BEGIN
      IF p_materially_efficient = 'TRUE' THEN
      
        f_return :=       p_multiplier
                   *(1 - (p_material_efficiency / 100))
                   *      p_quantity;
      ELSE
        f_return := p_quantity * p_multiplier;
      END IF;
      
      RETURN f_return;
      
    END get_quantity_this_input_item;


  BEGIN

    OPEN  c_composite(NVL(p_subheader -- on recursive calls
                         ,p_good));   -- on main call

    FETCH c_composite BULK COLLECT INTO a_cmp;
    CLOSE c_composite;


    IF a_cmp.COUNT > 0 THEN
    
      FOR ix_cmp IN a_cmp.FIRST .. a_cmp.LAST LOOP
  
    
        -- assert material efficiency
        FOR r_prt IN (SELECT class
                            ,material_origin
                      FROM   part
                      WHERE  label = a_cmp(ix_cmp).good) LOOP


-- DEBT: fetches material efficiency each round, which seems valid since we often drill into component compositions, where applicable ME differs, but still there is redundancy


          -- List of Goods where 'POS Extra Material Efficiency' does NOT Apply.
          -- (POS = Player Own Starbase, which has eg. extra bonuses for industry.)
          IF     a_cmp(ix_cmp).material_origin      IN ('ORE')       OR
             NVL(r_prt.class, utils.k_dummy_string) IN ('BLUEPRINT') THEN

             f_meffic := 0;
          ELSE          
            BEGIN
              SELECT material_efficiency
              INTO   f_meffic
              FROM   part
              WHERE  label = a_cmp(ix_cmp).good;
      
              f_meffic_pos := (1 - (1 - f_meffic             / 100)  -- ME on Blueprint (BPO)
                                  *(1 - k_pos_saves_extra_me / 100)) -- ME on Facility (when POS)
                               *100;
            EXCEPTION
              WHEN NO_DATA_FOUND THEN
                RAISE_APPLICATION_ERROR(-20000, 'MATERIAL EFFICIENCIES may be missing for good: ' || a_cmp(ix_cmp).good || '! or ' || SQLERRM);
            END;
          END IF;
        END LOOP;


        f_quantity       := get_quantity_this_input_item(p_materially_efficient => a_cmp(ix_cmp).materially_efficient
                                                        ,p_quantity             => a_cmp(ix_cmp).quantity
                                                        ,p_multiplier           => p_multiplier
                                                        ,p_material_efficiency  => f_meffic);

        IF f_meffic_pos IS NULL THEN

          f_quantity_pos := f_quantity;
        ELSE
          f_quantity_pos := get_quantity_this_input_item(p_materially_efficient => a_cmp(ix_cmp).materially_efficient
                                                        ,p_quantity             => a_cmp(ix_cmp).quantity
                                                        ,p_multiplier           => p_multiplier_pos
                                                        ,p_material_efficiency  => f_meffic_pos);
        END IF;
        

        BEGIN -- if this p_good is an industrial composite, ie. a composite of a composite..
  
          SELECT 1
          INTO   n_dummy
          FROM       composite one
          INNER JOIN composite oth ON oth.good = one.part
          WHERE  one.good = a_cmp(ix_cmp).good
          AND    ROWNUM   = 1;
          
  
          BEGIN -- ..and the part is subject to CEILing, ie. composite is producable and part is natural raw material (as opposed to intellectual or market artefact)
  
            SELECT 1 --*
            INTO   n_dummy
            FROM       vw_composite   dad
            INNER JOIN vw_composition cld ON cld.good = dad.part
            WHERE  dad.good             =  a_cmp(ix_cmp).good
            AND    cld.good             =  a_cmp(ix_cmp).part
            AND    dad.material_origin  =  'PRODUCE'
            AND    cld.material_origin IN ('ICE', 'MINERAL', 'MOON', 'PLANET', 'SALVAGE')
            AND    ROWNUM               = 1;

            -- ..then CEIL
            f_quantity     := CEIL(f_quantity);
            f_quantity_pos := CEIL(f_quantity_pos);

          EXCEPTION
            WHEN NO_DATA_FOUND THEN
              NULL;
          END;        
        EXCEPTION
          WHEN NO_DATA_FOUND THEN
            NULL;
        END;


  
        SELECT sq_general.NEXTVAL
        INTO   n_this_part
        FROM   dual;

    
        MERGE INTO produce prd
    
        USING (SELECT      n_this_part         AS ident
                     ,     p_good              AS good
                     ,     a_cmp(ix_cmp).good  AS subheader
                     ,     a_cmp(ix_cmp).part  AS part
                     ,     f_meffic            AS me
                     ,     f_quantity          AS quantity
                     ,     f_meffic_pos        AS me_pos
                     ,     f_quantity_pos      AS quantity_pos
                     ,     'FALSE'             AS transitive
  
               FROM  dual) ins
                   
        ON (    prd.good      = ins.good
            AND prd.subheader = ins.subheader
            AND prd.part      = ins.part)
  
        WHEN MATCHED THEN
          UPDATE
          SET    prd.me           = ins.me
                ,prd.quantity     = ins.quantity
                ,prd.me_pos       = ins.me_pos
                ,prd.quantity_pos = ins.quantity_pos
                ,prd.transitive   = ins.transitive
                  
          WHERE  NVL(prd.me,           utils.k_dummy_number) <> NVL(ins.me,           utils.k_dummy_number)
          OR     NVL(prd.quantity,     utils.k_dummy_number) <> NVL(ins.quantity,     utils.k_dummy_number)
          OR     NVL(prd.me_pos,       utils.k_dummy_number) <> NVL(ins.me_pos,       utils.k_dummy_number)
          OR     NVL(prd.quantity_pos, utils.k_dummy_number) <> NVL(ins.quantity_pos, utils.k_dummy_number)
          OR     NVL(prd.transitive,   utils.k_dummy_number) <> NVL(ins.transitive,   utils.k_dummy_number)
  
        WHEN NOT MATCHED THEN
          INSERT (ident, good, subheader, part, me, quantity, me_pos, quantity_pos, transitive)
          VALUES (ins.ident, ins.good, ins.subheader, ins.part, ins.me, ins.quantity, ins.me_pos, ins.quantity_pos, ins.transitive);


        BEGIN
          -- item itself a part?
          SELECT 1
          INTO   n_dummy
          FROM   composite
          WHERE  good   = a_cmp(ix_cmp).part
          AND    ROWNUM = 1;
    
          -- drill deeper
          define_full_list_of_materials(p_good           => p_good
                                       ,p_subheader      => a_cmp(ix_cmp).part
                                       ,p_multiplier     => f_quantity
                                       ,p_multiplier_pos => f_quantity_pos);
            
        EXCEPTION
          WHEN no_data_found THEN
            NULL; -- no probz, just not a composite then
        END;

      END LOOP;
  

/*
      Stamp composites to separate them from atomic parts.
      More convenient in the final, already complex SQLs, to rely on this field than do subqueries.
*/
      UPDATE produce inp
      SET    inp.transitive = 'TRUE'
      WHERE  inp.ident     IN (SELECT one.ident
                               FROM       produce one
                               INNER JOIN produce oth ON oth.subheader = one.part);
    END IF;
    
  END define_full_list_of_materials;
  



  PROCEDURE define_all_products AS

  BEGIN

    FOR i IN (SELECT DISTINCT good
              FROM   composite) LOOP
  
      define_full_list_of_materials(i.good);
    END LOOP;
    


    COMMIT;

  
  END define_all_products;
  
  
  
END load_indu_details;
/
