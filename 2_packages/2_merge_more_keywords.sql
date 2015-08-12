/*
    BEGIN DELETE FROM keyword; COMMIT; END;
    BEGIN load_indu_details.merge_part_composite; END;
    -- then run this block

    TODO: why not make it more like part.txt? Maybe add another such loader file and fill in more keywords in the same '/' -fashion?
*/
BEGIN
  
  FOR i IN (SELECT ident AS part_id
            FROM   part
            WHERE  label     IN ('STANDARD DROP BOOSTER BLUEPRINT COPY'
                                ,'IMPROVED DROP BOOSTER BLUEPRINT COPY'
                                ,'STRONG DROP BOOSTER BLUEPRINT COPY'
                                ,'STANDARD FRENTIX BOOSTER BLUEPRINT COPY'
                                ,'IMPROVED FRENTIX BOOSTER BLUEPRINT COPY'
                                ,'STRONG FRENTIX BOOSTER BLUEPRINT COPY'
                                ,'STANDARD MINDFLOOD BOOSTER BLUEPRINT COPY'
                                ,'IMPROVED MINDFLOOD BOOSTER BLUEPRINT COPY'
                                ,'STRONG MINDFLOOD BOOSTER BLUEPRINT COPY'
                                ,'STANDARD SOOTH SAYER BOOSTER BLUEPRINT COPY'
                                ,'IMPROVED SOOTH SAYER BOOSTER BLUEPRINT COPY'
                                ,'STRONG SOOTH SAYER BOOSTER BLUEPRINT COPY'
            
                                ,'ASTERO BLUEPRINT COPY'
                                ,'CRUOR BLUEPRINT COPY'
                                ,'DAREDEVIL BLUEPRINT COPY'
                                ,'DRAMIEL BLUEPRINT COPY'
                                ,'GARMUR BLUEPRINT COPY'
                                ,'SUCCUBUS BLUEPRINT COPY'
                                ,'WORM BLUEPRINT COPY'
                                ,'ASHIMMU BLUEPRINT COPY'
                                ,'CYNABAL BLUEPRINT COPY'
                                ,'GILA BLUEPRINT COPY'
                                ,'ORTHRUS BLUEPRINT COPY'
                                ,'PHANTASM BLUEPRINT COPY'
                                ,'STRATIOS BLUEPRINT COPY'
                                ,'VIGILANT BLUEPRINT COPY'
                                ,'CAPITAL INEFFICIENT ARMOR REPAIR UNIT BLUEPRINT COPY')
            ) LOOP

    load_indu_details.merge_keywords(p_part_id  => i.part_id
                                    ,p_keywords => 'BLUEPRINTS');
 
    load_indu_details.merge_keywords(p_part_id  => i.part_id
                                    ,p_keywords => 'CONTRACTS');
  END LOOP;


  FOR i IN (SELECT ident AS part_id
            FROM   part
            WHERE  label     IN ('ABSOLUTION BLUEPRINT COPY'
                                ,'DAMNATION BLUEPRINT COPY'
                                ,'NIGHTHAWK BLUEPRINT COPY'
                                ,'VULTURE BLUEPRINT COPY'
                                ,'ASTARTE BLUEPRINT COPY'
                                ,'EOS BLUEPRINT COPY'
                                ,'CLAYMORE BLUEPRINT COPY'
                                ,'SLEIPNIR BLUEPRINT COPY'
                                ,'SACRILEGE BLUEPRINT COPY'
                                ,'ZEALOT BLUEPRINT COPY'
                                ,'CERBERUS BLUEPRINT COPY'
                                ,'EAGLE BLUEPRINT COPY'
                                ,'DEIMOS BLUEPRINT COPY'
                                ,'ISHTAR BLUEPRINT COPY'
                                ,'MUNINN BLUEPRINT COPY'
                                ,'VAGABOND BLUEPRINT COPY'
                                ,'HERETIC BLUEPRINT COPY'
                                ,'FLYCATCHER BLUEPRINT COPY'
                                ,'ERIS BLUEPRINT COPY'
                                ,'SABRE BLUEPRINT COPY'
                                ,'GUARDIAN BLUEPRINT COPY'
                                ,'BASILISK BLUEPRINT COPY'
                                ,'ONEIROS BLUEPRINT COPY'
                                ,'SCIMITAR BLUEPRINT COPY'
                                ,'CURSE BLUEPRINT COPY'
                                ,'PILGRIM BLUEPRINT COPY'
                                ,'FALCON BLUEPRINT COPY'
                                ,'ROOK BLUEPRINT COPY'
                                ,'ARAZU BLUEPRINT COPY'
                                ,'LACHESIS BLUEPRINT COPY'
                                ,'HUGINN BLUEPRINT COPY'
                                ,'RAPIER BLUEPRINT COPY'
                                ,'IMPEL BLUEPRINT COPY'
                                ,'PRORATOR BLUEPRINT COPY'
                                ,'CRANE BLUEPRINT COPY'
                                ,'BUSTARD BLUEPRINT COPY'
                                ,'VIATOR BLUEPRINT COPY'
                                ,'OCCATOR BLUEPRINT COPY'
                                ,'PROWLER BLUEPRINT COPY'
                                ,'MASTODON BLUEPRINT COPY')
            ) LOOP

    load_indu_details.merge_keywords(p_part_id  => i.part_id
                                    ,p_keywords => 'INVENTION');
  END LOOP;
  
  
  FOR i IN (SELECT ident AS part_id
            FROM   part
            WHERE  label     IN ('DEVOTER BLUEPRINT COPY'
                                ,'ONYX BLUEPRINT COPY'
                                ,'PHOBOS BLUEPRINT COPY'
                                ,'BROADSWORD BLUEPRINT COPY'

                                ,'ENTOSIS LINK II BLUEPRINT COPY'
                                ,'SIEGE MODULE II BLUEPRINT COPY'
                                ,'TRIAGE MODULE II BLUEPRINT COPY')
           ) LOOP
            
    load_indu_details.merge_keywords(p_part_id  => i.part_id
                                    ,p_keywords => 'BLUEPRINTS');

    load_indu_details.merge_keywords(p_part_id  => i.part_id
                                    ,p_keywords => 'INVENTION');                                    
  END LOOP;


  FOR i IN (SELECT ident AS part_id
            FROM   part
            WHERE  label   LIKE '% - %'
            AND    label   LIKE '%BLUEPRINT COPY%'
            UNION
            SELECT ident AS part_id
            FROM   part
            WHERE  label     IN ('CONFESSOR BLUEPRINT COPY'
                                ,'JACKDAW BLUEPRINT COPY'
                                ,'HECATE BLUEPRINT COPY'
                                ,'SVIPUL BLUEPRINT COPY'
                                ,'LEGION BLUEPRINT COPY'
                                ,'TENGU BLUEPRINT COPY'
                                ,'PROTEUS BLUEPRINT COPY'
                                ,'LOKI BLUEPRINT COPY')
            ) LOOP

    load_indu_details.merge_keywords(p_part_id  => i.part_id
                                    ,p_keywords => 'BLUEPRINTS');

    load_indu_details.merge_keywords(p_part_id  => i.part_id
                                    ,p_keywords => 'REVERSE ENGINEERING');
  END LOOP;



  load_indu_details.refresh_views;


  COMMIT;

END;
/

