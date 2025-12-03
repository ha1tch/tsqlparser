-- Sample 166: System Stored Procedures Patterns
-- Category: Missing Syntax Elements / System Procedures
-- Complexity: Complex
-- Purpose: Parser testing - system stored procedure calls
-- Features: sp_* procedures, parameter patterns

-- Pattern 1: sp_help variants
EXEC sp_help;                           -- All objects
EXEC sp_help 'dbo.Customers';           -- Specific table
EXEC sp_help @objname = 'dbo.Orders';   -- Named parameter
GO

-- Pattern 2: sp_helptext - get object definition
EXEC sp_helptext 'dbo.MyStoredProcedure';
EXEC sp_helptext @objname = N'dbo.MyView';
GO

-- Pattern 3: sp_helpindex
EXEC sp_helpindex 'dbo.Customers';
EXEC sp_helpindex @objname = 'dbo.Orders';
GO

-- Pattern 4: sp_helpdb
EXEC sp_helpdb;                         -- All databases
EXEC sp_helpdb 'master';                -- Specific database
EXEC sp_helpdb @dbname = 'tempdb';      -- Named parameter
GO

-- Pattern 5: sp_who and sp_who2
EXEC sp_who;
EXEC sp_who 'active';
EXEC sp_who @loginame = 'sa';
EXEC sp_who2;
EXEC sp_who2 'active';
GO

-- Pattern 6: sp_lock
EXEC sp_lock;
EXEC sp_lock @spid1 = 55;
EXEC sp_lock @spid1 = 55, @spid2 = 56;
GO

-- Pattern 7: sp_spaceused
EXEC sp_spaceused;                           -- Database level
EXEC sp_spaceused 'dbo.Customers';           -- Table level
EXEC sp_spaceused @objname = 'dbo.Orders', @updateusage = 'TRUE';
GO

-- Pattern 8: sp_columns
EXEC sp_columns 'Customers';
EXEC sp_columns @table_name = 'Orders', @table_owner = 'dbo';
EXEC sp_columns @table_name = '%', @table_owner = 'dbo', @column_name = 'CustomerID';
GO

-- Pattern 9: sp_tables
EXEC sp_tables;
EXEC sp_tables @table_name = 'Customers';
EXEC sp_tables @table_name = '%', @table_owner = 'dbo', @table_type = "'TABLE'";
GO

-- Pattern 10: sp_stored_procedures
EXEC sp_stored_procedures;
EXEC sp_stored_procedures @sp_name = 'Get%';
EXEC sp_stored_procedures @sp_owner = 'dbo';
GO

-- Pattern 11: sp_databases
EXEC sp_databases;
GO

-- Pattern 12: sp_rename
EXEC sp_rename 'dbo.OldTableName', 'NewTableName';
EXEC sp_rename 'dbo.Customers.OldColumnName', 'NewColumnName', 'COLUMN';
EXEC sp_rename 'dbo.IX_OldIndexName', 'IX_NewIndexName', 'INDEX';
EXEC sp_rename @objname = 'dbo.OldName', @newname = 'NewName', @objtype = 'OBJECT';
GO

-- Pattern 13: sp_depends (deprecated but still parses)
EXEC sp_depends 'dbo.Customers';
EXEC sp_depends @objname = 'dbo.MyView';
GO

-- Pattern 14: sp_helpconstraint
EXEC sp_helpconstraint 'dbo.Customers';
EXEC sp_helpconstraint @objname = 'dbo.Orders', @nomsg = 'nomsg';
GO

-- Pattern 15: sp_statistics
EXEC sp_statistics 'Customers';
EXEC sp_statistics @table_name = 'Orders', @table_owner = 'dbo';
GO

-- Pattern 16: sp_pkeys and sp_fkeys
EXEC sp_pkeys 'Customers';
EXEC sp_pkeys @table_name = 'Orders', @table_owner = 'dbo';

EXEC sp_fkeys @pktable_name = 'Customers';
EXEC sp_fkeys @fktable_name = 'Orders';
GO

-- Pattern 17: sp_configure
EXEC sp_configure;                                      -- Show all
EXEC sp_configure 'show advanced options';              -- Show specific
EXEC sp_configure 'max server memory (MB)', 4096;       -- Set value
RECONFIGURE;
RECONFIGURE WITH OVERRIDE;
GO

-- Pattern 18: sp_executesql
DECLARE @SQL NVARCHAR(MAX) = N'SELECT * FROM dbo.Customers WHERE CustomerID = @ID';
DECLARE @Params NVARCHAR(100) = N'@ID INT';

EXEC sp_executesql @SQL, @Params, @ID = 1;
GO

-- Pattern 19: sp_executesql with OUTPUT
DECLARE @SQL NVARCHAR(MAX) = N'SELECT @Count = COUNT(*) FROM dbo.Customers';
DECLARE @Params NVARCHAR(100) = N'@Count INT OUTPUT';
DECLARE @Result INT;

EXEC sp_executesql @SQL, @Params, @Count = @Result OUTPUT;
SELECT @Result AS CustomerCount;
GO

-- Pattern 20: sp_addmessage
EXEC sp_addmessage 
    @msgnum = 50001, 
    @severity = 16, 
    @msgtext = N'Custom error message: %s',
    @lang = 'us_english',
    @with_log = 'FALSE',
    @replace = 'REPLACE';

RAISERROR(50001, 16, 1, 'Test parameter');

EXEC sp_dropmessage @msgnum = 50001;
GO

-- Pattern 21: sp_addtype / sp_droptype (deprecated)
EXEC sp_addtype 'PhoneNumber', 'VARCHAR(20)', 'NOT NULL';
EXEC sp_droptype 'PhoneNumber';
GO

-- Pattern 22: sp_addlogin / sp_droplogin (deprecated, use CREATE LOGIN)
-- EXEC sp_addlogin 'NewUser', 'Password123', 'master';
-- EXEC sp_droplogin 'NewUser';
GO

-- Pattern 23: sp_grantdbaccess / sp_revokedbaccess (deprecated)
-- EXEC sp_grantdbaccess 'LoginName', 'UserName';
-- EXEC sp_revokedbaccess 'UserName';
GO

-- Pattern 24: sp_addrolemember / sp_droprolemember
EXEC sp_addrolemember 'db_datareader', 'TestUser';
EXEC sp_droprolemember 'db_datareader', 'TestUser';
GO

-- Pattern 25: sp_helprole and sp_helprolemember
EXEC sp_helprole;
EXEC sp_helprole 'db_owner';
EXEC sp_helprolemember 'db_datareader';
GO

-- Pattern 26: sp_helpuser
EXEC sp_helpuser;
EXEC sp_helpuser 'dbo';
GO

-- Pattern 27: sp_helpfile and sp_helpfilegroup
EXEC sp_helpfile;
EXEC sp_helpfile 'primary';
EXEC sp_helpfilegroup;
EXEC sp_helpfilegroup 'PRIMARY';
GO

-- Pattern 28: sp_updatestats
EXEC sp_updatestats;
EXEC sp_updatestats @resample = 'RESAMPLE';
GO

-- Pattern 29: sp_recompile
EXEC sp_recompile 'dbo.Customers';
EXEC sp_recompile 'dbo.MyStoredProcedure';
GO

-- Pattern 30: sp_setapprole
EXEC sp_setapprole 'MyAppRole', 'AppRolePassword';
-- EXEC sp_unsetapprole @cookie OUTPUT;
GO

-- Pattern 31: sp_getapplock / sp_releaseapplock
DECLARE @Result INT;

EXEC @Result = sp_getapplock 
    @Resource = 'MyLockResource',
    @LockMode = 'Exclusive',
    @LockOwner = 'Transaction',
    @LockTimeout = 5000;

IF @Result >= 0
BEGIN
    -- Do work...
    EXEC sp_releaseapplock @Resource = 'MyLockResource';
END
GO

-- Pattern 32: sp_MSforeachtable / sp_MSforeachdb (undocumented)
EXEC sp_MSforeachtable 'PRINT ''?''';
EXEC sp_MSforeachdb 'PRINT ''?''';
GO
