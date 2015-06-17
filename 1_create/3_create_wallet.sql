/*
    When connecting securely (https://) you will need an 'Oracle Wallet' to hold the certificates or else Oracle wont proceed to the request
    First do 2_create_acl.sql, then this. Then the anon block below to confirm that all works nice.
    
  
    1. Now define the page you have to connect to, like this
    
      https://api.eveonline.com/char/AssetList.xml.aspx?keyID=[api key id]'||'&'||'vCode=[api verification code]'||'&'||'characterID=[your characters id]
      you need to have the EVE API KEY set to the character
    
    2. Open that in your browser, then open Trusted Certificates, then navigate to Export Certificate
       - Eg. in Firefox Click the Lock Icon just left of Address Bar
         Then 'More Information'.. 'View Certificate'.. 'Details'-Tab
         Then 'Export' all other Certificates EXCEPT for the leaf Cert (called *.eveonline.com at the time of writing)
  
    3. Store them in your documents and run the Shell Commands below
    
    4. Run the Anon Block below to verify all went well
*/


the Shell scripts
Begin by CD-ing to where you Exported the Certificates, maybe /home/oracle/Documents


Create a new Folder to hold the Certs
Below is defalul path on 12c installation (in common webtutorial), this is a fine place store your certs
$ mkdir -p /u01/app/oracle/admin/orcl/wallet/


Tell Oracle DBMS this folder is location for a Wallet.
$ orapki wallet create  -wallet /u01/app/oracle/admin/orcl/wallet/ -pwd SomePasswd123 -auto_login


Add certificates to, Browse them, and Delete from Wallet
The certs you need to add is the full tree from node to lowest level parent BUT NOT the leaf, like this
$ orapki wallet add -wallet /u01/app/oracle/admin/orcl/wallet/ -trusted_cert -cert "GeoTrustGlobalCA" -pwd SomePasswd123
$ orapki wallet add -wallet /u01/app/oracle/admin/orcl/wallet/ -trusted_cert -cert "RapidSSLSHA256CA-G3" -pwd SomePasswd123
and NO NEED to add the leaf Cert, called *.eveonline.com at the time of writing

$ orapki wallet display -wallet /u01/app/oracle/admin/orcl/wallet/ -pwd SomePasswd123
$ orapki wallet remove  -wallet /u01/app/oracle/admin/orcl/wallet/ -trusted_cert_all -pwd SomePasswd123






-- run this in dbms as your Developer-User that you created in create_database.sql
;
DECLARE

  a_pieces   utl_http.html_pieces;

BEGIN

  utl_http.set_wallet('file:' || '/u01/app/oracle/admin/orcl/wallet/', 'SomePasswd123');

  -- uncomment this to assert that at least ACL works and there is an Internet Connection
  --a_pieces := utl_http.request_pieces('http://api.eve-central.com');

/*
    The EVE API XML address youll connect to
    Remember, you must FIRST create your eveapi keys at eveapi.com which youll then use here
  
    by here you need
    1 ACL permissions set
    2 Wallet created and required cert's added
    3 Wallet set with that utl_http.set_wallet() above
*/
  a_pieces := utl_http.request_pieces('https://api.eveonline.com/char/AssetList.xml.aspx?keyID=[api key id]'||'&'||'vCode=[api verification code]'||'&'||'characterID=[your characters id]');

  -- If all went without Alerts/Probz you just downloaded your EVE Online Char's Asset list into a_pieces, congratz!

--exception
  --when others then
    --dbms_output.put_line(SQLERRM);
END;
/
