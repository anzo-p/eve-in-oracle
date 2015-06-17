
/*
    Dealing with ORA-24247: network access denied by access control list (ACL)

    Access Control List. This is how to do it, not diffuclt at all.
    Cannot connect to internet from Oracle-dbms without.
*/



BEGIN
  dbms_network_acl_admin.drop_acl     (acl         => 'eveapi-permissions.xml');

  COMMIT;
END;
/


BEGIN
  dbms_network_acl_admin.create_acl   (acl         => 'eveapi-permissions.xml'
                                      ,description => 'To access EVE Online Market Data and XML API'
                                      ,principal   => 'EVE'
                                      ,is_grant    => TRUE
                                      ,privilege   => 'connect'
                                      ,start_date  => NULL
                                      ,end_date    => NULL);

  dbms_network_acl_admin.add_privilege(acl         => 'eveapi-permissions.xml'
                                      ,principal   => 'EVE'
                                      ,is_grant    => TRUE
                                      ,privilege   => 'resolve');

  dbms_network_acl_admin.assign_acl   (acl         => 'eveapi-permissions.xml'
                                      ,host        => 'api.eve-central.com'); 

  dbms_network_acl_admin.assign_acl   (acl         => 'eveapi-permissions.xml'
                                      ,host        => 'api.eveonline.com'); 


  COMMIT;
END;
/



-- got permission to connect there now?
DECLARE
  pcs utl_http.html_pieces;
BEGIN
  pcs := utl_http.request_pieces('http://api.eve-central.com');
  -- basically if Block runs without errors youre fine
END;
/


-- ACL set? - dbms-interface way
SELECT dbms_network_acl_admin.check_privilege('eveapi-permissions.xml'
                                             ,'EVE'
                                             ,'connect')
FROM   dual;


-- ACL set? - from config table (preferred way)
SELECT * FROM user_network_acl_privileges;


--describe xds_acl;
--select aclid, shared, description from xds_acl;
--delete FROM xds_acl where aclid = 'DE66B80A74234AE79300D19925729FEB';
