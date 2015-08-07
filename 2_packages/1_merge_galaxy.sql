/*
    All Regions in EVE Online
*/

DECLARE

  t_galaxy     t_all_regions := t_all_regions(

    t_region(10000054, 'ARIDIA')
   ,t_region(10000069, 'BLACK RISE')
   ,t_region(10000038, 'THE BLEAK LANDS')
   ,t_region(10000055, 'BRANCH')
   ,t_region(10000007, 'CACHE')
   ,t_region(10000014, 'CATCH')
   ,t_region(10000033, 'THE CITADEL')
   ,t_region(10000051, 'CLOUD RING')
   ,t_region(10000053, 'COBALT EDGE')
   ,t_region(10000012, 'CURSE')
   ,t_region(10000035, 'DEKLEIN')
   ,t_region(10000060, 'DELVE')
   ,t_region(10000001, 'DERELIK')
   ,t_region(10000005, 'DETROID')
   ,t_region(10000036, 'DEVOID')
   ,t_region(10000043, 'DOMAIN')
   ,t_region(10000064, 'ESSENCE')
   ,t_region(10000039, 'ESOTERIA')
   ,t_region(10000027, 'ETHERIUM REACH')
   ,t_region(10000037, 'EVERYSHORE')
   ,t_region(10000046, 'FADE')
   ,t_region(10000056, 'FEYTHABOLIS')
   ,t_region(10000002, 'THE FORGE')
   ,t_region(10000058, 'FOUNTAIN')
   ,t_region(10000029, 'GEMINATE')
   ,t_region(10000067, 'GENESIS')
   ,t_region(10000011, 'GREAT WILDLANDS')
   ,t_region(10000030, 'HEIMATAR')
   ,t_region(10000025, 'IMMENSEA')
   ,t_region(10000031, 'IMPASS')
   ,t_region(10000009, 'INSMOTHER')
   ,t_region(10000052, 'KADOR')
   ,t_region(10000034, 'THE KALEVALA EXPANSE')
   ,t_region(10000049, 'KHANID')
   ,t_region(10000065, 'KOR-AZOR')
   ,t_region(10000016, 'LONETREK')
   ,t_region(10000013, 'MALPAIS')
   ,t_region(10000042, 'METROPOLIS')
   ,t_region(10000028, 'MOLDEN HEATH')
   ,t_region(10000040, 'OASA')
   ,t_region(10000062, 'OMIST')
   ,t_region(10000021, 'OUTER PASSAGE')
   ,t_region(10000057, 'OUTER RING')
   ,t_region(10000059, 'PARAGON SOUL')
   ,t_region(10000063, 'PERIOD BASIS')
   ,t_region(10000066, 'PERRIGEN FALLS')
   ,t_region(10000048, 'PLACID')
   ,t_region(10000047, 'PROVIDENCE')
   ,t_region(10000023, 'PURE BLIND')
   ,t_region(10000050, 'QUERIOUS')
   ,t_region(10000008, 'SCALDING PASS')
   ,t_region(10000032, 'SINQ LAISON')
   ,t_region(10000044, 'SOLITUDE')
   ,t_region(10000018, 'THE SPIRE')
   ,t_region(10000022, 'STAIN')
   ,t_region(10000041, 'SYNDICATE')
   ,t_region(10000020, 'TASH-MURKON')
   ,t_region(10000045, 'TENAL')
   ,t_region(10000061, 'TENERIFIS')
   ,t_region(10000010, 'TRIBUTE')
   ,t_region(10000003, 'VALE OF THE SILENT')
   ,t_region(10000015, 'VENAL')
   ,t_region(10000068, 'VERGE VENDOR')
   ,t_region(10000006, 'WICKED CREEK')

  );
  
BEGIN

  FOR i IN (SELECT one.*
            FROM       TABLE(t_galaxy) one
            INNER JOIN TABLE(t_galaxy) oth ON (oth.eveapi_region_id  = one.eveapi_region_id   AND oth.name_region <> one.name_region)
                                           OR (oth.eveapi_region_id <> one.eveapi_region_id   AND oth.name_region  = one.name_region)) LOOP

    RAISE_APPLICATION_ERROR(-20000, 'DUPLICATE: ' || i.eveapi_region_id || ' OR ' || i.name_region);
  END LOOP;
  

  MERGE INTO region reg

  USING (SELECT eveapi_region_id
               ,name_region
         FROM   TABLE(t_galaxy)) ins

  ON (reg.eveapi_region_id = ins.eveapi_region_id)

  WHEN NOT MATCHED THEN
    INSERT (eveapi_region_id, name_region)
    VALUES (ins.eveapi_region_id, ins.name_region);


  COMMIT;

END;
/