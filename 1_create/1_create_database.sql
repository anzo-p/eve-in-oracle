/*
    As ADMIN: Scripts in this module you have to run as ADMIN (SYS, SYSDBA...)
    Also applies to 2_create_acl.sql and 3_create_wallet.sql
    Others you may run as the user you CREATE here and GRANT these privilegest for.
  
    Create Database, Directory for Loader files, Role Developer, User in that Role


    Assumptions:
    - Oracle 12c database location:   /u01/app/oracle/     ...at least 11g required for XMLDB to work, 12c seems required for modern SSL Certificates to work
    - current user:                   oracle
    - password for everyting:         SomePasswd123
    - these scripts are at:           /home/oracle/Documents/eve
    - you have set up an EVE API KEY for your Player Character in EVE Online
*/


DROP USER       "EVE"                            CASCADE;
DROP TABLESPACE "EVEONLINE" INCLUDING CONTENTS   CASCADE CONSTRAINTS;


-- create dabatase
CREATE SMALLFILE TABLESPACE EVEONLINE
DATAFILE '/u01/app/oracle/oradata/orcl/eveonline' -- this path from common tutorials in web
SIZE 512M REUSE AUTOEXTEND ON NEXT 50M MAXSIZE 2024M
LOGGING
EXTENT MANAGEMENT LOCAL
SEGMENT SPACE MANAGEMENT AUTO
DEFAULT NOCOMPRESS;



-- assuming you sandbox with many projects youd maybe want a role with all needed rights, which you then grant to this User
-- if you dont have it already you can make one now, not sure what rights you be needing... here are some that will be useful
CREATE ROLE "DEVELOPER" NOT IDENTIFIED;
GRANT CREATE INDEXTYPE            TO "DEVELOPER";
GRANT CREATE JOB                  TO "DEVELOPER";
GRANT CREATE MATERIALIZED VIEW    TO "DEVELOPER";
GRANT CREATE PROCEDURE            TO "DEVELOPER";
GRANT CREATE SEQUENCE             TO "DEVELOPER";
GRANT CREATE TABLE                TO "DEVELOPER";
GRANT CREATE TYPE                 TO "DEVELOPER";
GRANT CREATE VIEW                 TO "DEVELOPER";


-- create user
CREATE USER "EVE"
PROFILE "DEFAULT" IDENTIFIED BY "passwordexpired"
PASSWORD EXPIRE
DEFAULT TABLESPACE "EVEONLINE" TEMPORARY TABLESPACE "TEMP"
QUOTA UNLIMITED ON "EVEONLINE"
ACCOUNT UNLOCK;


-- passwd is not a string so no '-s needed
ALTER USER "EVE" IDENTIFIED BY SomePasswd123;


GRANT "CONNECT"                               TO "EVE";
GRANT "DEVELOPER"                             TO "EVE";
GRANT EXECUTE ON SYS.UTL_HTTP                 TO "EVE";



-- create location for loader files, this assigns them in Orcale dbms, the folders themselves must be MKDIR'd in OS
CREATE OR REPLACE DIRECTORY directory_eve AS '/home/oracle/Documents/eve/3_data_load';
GRANT READ, WRITE ON DIRECTORY directory_eve TO "EVE";
