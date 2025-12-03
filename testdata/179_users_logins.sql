-- Sample 179: User and Login Management
-- Category: Security / DDL
-- Complexity: Complex
-- Purpose: Parser testing - security principal syntax
-- Features: CREATE LOGIN, CREATE USER, roles, permissions

-- Pattern 1: CREATE LOGIN with password
CREATE LOGIN TestLogin WITH PASSWORD = 'StrongP@ssword123';
GO
DROP LOGIN TestLogin;
GO

-- Pattern 2: CREATE LOGIN with options
CREATE LOGIN TestLogin WITH PASSWORD = 'StrongP@ssword123',
    DEFAULT_DATABASE = master,
    DEFAULT_LANGUAGE = us_english,
    CHECK_EXPIRATION = OFF,
    CHECK_POLICY = OFF;
GO
DROP LOGIN TestLogin;
GO

-- Pattern 3: CREATE LOGIN with hashed password
CREATE LOGIN TestLogin WITH PASSWORD = 0x0200AABBCCDD1234567890AABBCCDD1234567890AABBCCDD1234567890AABBCCDD HASHED,
    SID = 0x0105000000000005150000001234567890ABCDEF12345678;
GO
DROP LOGIN TestLogin;
GO

-- Pattern 4: CREATE LOGIN from Windows
CREATE LOGIN [DOMAIN\UserName] FROM WINDOWS;
GO
DROP LOGIN [DOMAIN\UserName];
GO

-- Pattern 5: CREATE LOGIN from Windows with options
CREATE LOGIN [DOMAIN\UserName] FROM WINDOWS
WITH DEFAULT_DATABASE = master;
GO
DROP LOGIN [DOMAIN\UserName];
GO

-- Pattern 6: CREATE LOGIN from certificate
CREATE LOGIN CertLogin FROM CERTIFICATE MyCertificate;
GO
DROP LOGIN CertLogin;
GO

-- Pattern 7: CREATE LOGIN from asymmetric key
CREATE LOGIN KeyLogin FROM ASYMMETRIC KEY MyAsymmetricKey;
GO
DROP LOGIN KeyLogin;
GO

-- Pattern 8: CREATE USER for login
CREATE USER TestUser FOR LOGIN TestLogin;
GO
DROP USER TestUser;
GO

-- Pattern 9: CREATE USER with options
CREATE USER TestUser FOR LOGIN TestLogin
WITH DEFAULT_SCHEMA = dbo;
GO
DROP USER TestUser;
GO

-- Pattern 10: CREATE USER without login (contained database)
CREATE USER ContainedUser WITH PASSWORD = 'StrongP@ssword123';
GO
DROP USER ContainedUser;
GO

-- Pattern 11: CREATE USER without login (for certificate)
CREATE USER CertUser FOR CERTIFICATE MyCertificate;
GO
DROP USER CertUser;
GO

-- Pattern 12: CREATE USER without login (for asymmetric key)
CREATE USER KeyUser FOR ASYMMETRIC KEY MyAsymmetricKey;
GO
DROP USER KeyUser;
GO

-- Pattern 13: CREATE USER for Windows
CREATE USER [DOMAIN\UserName] FOR LOGIN [DOMAIN\UserName];
GO
DROP USER [DOMAIN\UserName];
GO

-- Pattern 14: CREATE USER from external provider (Azure AD)
CREATE USER [user@domain.com] FROM EXTERNAL PROVIDER;
GO
DROP USER [user@domain.com];
GO

-- Pattern 15: ALTER LOGIN
ALTER LOGIN TestLogin WITH PASSWORD = 'NewP@ssword456';
ALTER LOGIN TestLogin WITH PASSWORD = 'NewP@ssword456' OLD_PASSWORD = 'OldP@ssword123';
ALTER LOGIN TestLogin WITH DEFAULT_DATABASE = tempdb;
ALTER LOGIN TestLogin WITH NAME = RenamedLogin;
ALTER LOGIN TestLogin ENABLE;
ALTER LOGIN TestLogin DISABLE;
ALTER LOGIN TestLogin WITH CHECK_POLICY = ON;
ALTER LOGIN TestLogin WITH CHECK_EXPIRATION = ON;
ALTER LOGIN TestLogin WITH CREDENTIAL = MyCredential;
ALTER LOGIN TestLogin WITH NO CREDENTIAL;
GO

-- Pattern 16: ALTER USER
ALTER USER TestUser WITH NAME = RenamedUser;
ALTER USER TestUser WITH DEFAULT_SCHEMA = Sales;
ALTER USER TestUser WITH LOGIN = DifferentLogin;
ALTER USER TestUser WITH PASSWORD = 'NewP@ssword123';  -- Contained DB
GO

-- Pattern 17: CREATE ROLE
CREATE ROLE SalesRole;
CREATE ROLE SalesRole AUTHORIZATION dbo;
GO
DROP ROLE SalesRole;
GO

-- Pattern 18: ALTER ROLE - add/remove members
CREATE ROLE TestRole;

ALTER ROLE TestRole ADD MEMBER TestUser;
ALTER ROLE TestRole DROP MEMBER TestUser;

-- Rename role
ALTER ROLE TestRole WITH NAME = RenamedRole;

DROP ROLE RenamedRole;
GO

-- Pattern 19: CREATE APPLICATION ROLE
CREATE APPLICATION ROLE AppRole WITH PASSWORD = 'AppP@ssword123';
CREATE APPLICATION ROLE AppRole WITH PASSWORD = 'AppP@ssword123',
    DEFAULT_SCHEMA = dbo;
GO
DROP APPLICATION ROLE AppRole;
GO

-- Pattern 20: ALTER APPLICATION ROLE
ALTER APPLICATION ROLE AppRole WITH PASSWORD = 'NewP@ssword456';
ALTER APPLICATION ROLE AppRole WITH NAME = RenamedAppRole;
ALTER APPLICATION ROLE AppRole WITH DEFAULT_SCHEMA = Sales;
GO

-- Pattern 21: CREATE SERVER ROLE (SQL 2012+)
CREATE SERVER ROLE ServerAdmin;
CREATE SERVER ROLE ServerAdmin AUTHORIZATION sa;
GO
DROP SERVER ROLE ServerAdmin;
GO

-- Pattern 22: ALTER SERVER ROLE
CREATE SERVER ROLE TestServerRole;

ALTER SERVER ROLE TestServerRole ADD MEMBER TestLogin;
ALTER SERVER ROLE TestServerRole DROP MEMBER TestLogin;
ALTER SERVER ROLE TestServerRole WITH NAME = RenamedServerRole;

DROP SERVER ROLE RenamedServerRole;
GO

-- Pattern 23: sp_addrolemember / sp_droprolemember (legacy)
EXEC sp_addrolemember 'db_datareader', 'TestUser';
EXEC sp_droprolemember 'db_datareader', 'TestUser';
GO

-- Pattern 24: Fixed database roles
ALTER ROLE db_owner ADD MEMBER TestUser;
ALTER ROLE db_datareader ADD MEMBER TestUser;
ALTER ROLE db_datawriter ADD MEMBER TestUser;
ALTER ROLE db_ddladmin ADD MEMBER TestUser;
ALTER ROLE db_securityadmin ADD MEMBER TestUser;
ALTER ROLE db_backupoperator ADD MEMBER TestUser;
ALTER ROLE db_denydatareader ADD MEMBER TestUser;
ALTER ROLE db_denydatawriter ADD MEMBER TestUser;
GO

-- Pattern 25: Fixed server roles
ALTER SERVER ROLE sysadmin ADD MEMBER TestLogin;
ALTER SERVER ROLE serveradmin ADD MEMBER TestLogin;
ALTER SERVER ROLE securityadmin ADD MEMBER TestLogin;
ALTER SERVER ROLE processadmin ADD MEMBER TestLogin;
ALTER SERVER ROLE setupadmin ADD MEMBER TestLogin;
ALTER SERVER ROLE bulkadmin ADD MEMBER TestLogin;
ALTER SERVER ROLE diskadmin ADD MEMBER TestLogin;
ALTER SERVER ROLE dbcreator ADD MEMBER TestLogin;
GO

-- Pattern 26: CREATE CREDENTIAL
CREATE CREDENTIAL MyCredential WITH IDENTITY = 'DOMAIN\ServiceAccount',
    SECRET = 'P@ssword123';
GO
DROP CREDENTIAL MyCredential;
GO

-- Pattern 27: CREATE DATABASE SCOPED CREDENTIAL
CREATE DATABASE SCOPED CREDENTIAL AzureCredential
WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
    SECRET = 'sv=2019...';
GO
DROP DATABASE SCOPED CREDENTIAL AzureCredential;
GO

-- Pattern 28: EXECUTE AS
EXECUTE AS USER = 'TestUser';
-- Do work as TestUser
REVERT;

EXECUTE AS LOGIN = 'TestLogin';
REVERT;

EXECUTE AS CALLER;  -- Default in procedures
EXECUTE AS SELF;    -- Procedure creator
EXECUTE AS OWNER;   -- Schema owner
GO

-- Pattern 29: Impersonation check
SELECT 
    SUSER_SNAME() AS LoginName,
    USER_NAME() AS UserName,
    ORIGINAL_LOGIN() AS OriginalLogin,
    SYSTEM_USER AS SystemUser,
    SESSION_USER AS SessionUser,
    CURRENT_USER AS CurrentUser;
GO

-- Pattern 30: Permission checking functions
SELECT HAS_PERMS_BY_NAME('dbo.Customers', 'OBJECT', 'SELECT');
SELECT HAS_PERMS_BY_NAME('MyDatabase', 'DATABASE', 'CREATE TABLE');
SELECT HAS_PERMS_BY_NAME(NULL, NULL, 'VIEW SERVER STATE');
SELECT IS_MEMBER('db_owner');
SELECT IS_ROLEMEMBER('db_datareader', 'TestUser');
SELECT IS_SRVROLEMEMBER('sysadmin');
GO
