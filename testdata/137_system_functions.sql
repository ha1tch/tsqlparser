-- Sample 137: System Functions and Metadata Queries
-- Category: Pure Logic / Syntax Coverage
-- Complexity: Complex
-- Purpose: Parser testing - system and metadata functions
-- Features: System functions, configuration, security, metadata

-- Pattern 1: Identity and connection functions
SELECT 
    @@IDENTITY AS LastIdentity,
    SCOPE_IDENTITY() AS ScopeIdentity,
    IDENT_CURRENT('dbo.Orders') AS IdentCurrentOrders,
    @@ROWCOUNT AS RowCount,
    @@TRANCOUNT AS TransactionCount,
    @@NESTLEVEL AS NestLevel,
    @@SPID AS SessionID,
    @@CONNECTIONS AS TotalConnections;
GO

-- Pattern 2: Server and database functions
SELECT 
    @@SERVERNAME AS ServerName,
    @@SERVICENAME AS ServiceName,
    @@VERSION AS SQLVersion,
    @@LANGUAGE AS Language,
    @@LANGID AS LanguageID,
    @@DATEFIRST AS FirstDayOfWeek,
    @@LOCK_TIMEOUT AS LockTimeout,
    @@MAX_CONNECTIONS AS MaxConnections,
    @@MAX_PRECISION AS MaxPrecision;
GO

-- Pattern 3: Error functions
BEGIN TRY
    SELECT 1/0;
END TRY
BEGIN CATCH
    SELECT 
        ERROR_NUMBER() AS ErrorNumber,
        ERROR_SEVERITY() AS ErrorSeverity,
        ERROR_STATE() AS ErrorState,
        ERROR_PROCEDURE() AS ErrorProcedure,
        ERROR_LINE() AS ErrorLine,
        ERROR_MESSAGE() AS ErrorMessage;
END CATCH
GO

-- Pattern 4: Database context functions
SELECT 
    DB_ID() AS CurrentDBID,
    DB_ID('master') AS MasterDBID,
    DB_NAME() AS CurrentDBName,
    DB_NAME(1) AS DBName1,
    SCHEMA_ID() AS DefaultSchemaID,
    SCHEMA_ID('dbo') AS DboSchemaID,
    SCHEMA_NAME() AS DefaultSchemaName,
    SCHEMA_NAME(1) AS SchemaName1;
GO

-- Pattern 5: Object functions
SELECT 
    OBJECT_ID('dbo.Orders') AS OrdersObjectID,
    OBJECT_ID('dbo.Orders', 'U') AS OrdersTableID,
    OBJECT_NAME(OBJECT_ID('dbo.Orders')) AS OrdersName,
    OBJECT_SCHEMA_NAME(OBJECT_ID('dbo.Orders')) AS OrdersSchema,
    OBJECTPROPERTY(OBJECT_ID('dbo.Orders'), 'IsTable') AS IsTable,
    OBJECTPROPERTY(OBJECT_ID('dbo.Orders'), 'IsUserTable') AS IsUserTable,
    OBJECTPROPERTYEX(OBJECT_ID('dbo.Orders'), 'BaseType') AS BaseType;
GO

-- Pattern 6: Column and type functions
SELECT 
    COL_NAME(OBJECT_ID('dbo.Orders'), 1) AS FirstColumn,
    COL_LENGTH('dbo.Orders', 'CustomerID') AS CustomerIDLength,
    COLUMNPROPERTY(OBJECT_ID('dbo.Orders'), 'OrderID', 'IsIdentity') AS IsIdentity,
    TYPE_ID('int') AS IntTypeID,
    TYPE_NAME(56) AS TypeName56,
    TYPEPROPERTY('decimal', 'Precision') AS DecimalPrecision;
GO

-- Pattern 7: Security functions
SELECT 
    USER_ID() AS CurrentUserID,
    USER_ID('dbo') AS DboUserID,
    USER_NAME() AS CurrentUserName,
    USER_NAME(1) AS UserName1,
    SUSER_ID() AS LoginID,
    SUSER_SID() AS LoginSID,
    SUSER_SNAME() AS LoginName,
    SUSER_NAME() AS LoginNameAlt,
    SYSTEM_USER AS SystemUser,
    SESSION_USER AS SessionUser,
    CURRENT_USER AS CurrentUser,
    ORIGINAL_LOGIN() AS OriginalLogin;
GO

-- Pattern 8: Permission functions
SELECT 
    HAS_PERMS_BY_NAME('dbo.Orders', 'OBJECT', 'SELECT') AS CanSelectOrders,
    HAS_PERMS_BY_NAME('dbo.Orders', 'OBJECT', 'INSERT') AS CanInsertOrders,
    HAS_PERMS_BY_NAME('master', 'DATABASE', 'CREATE TABLE') AS CanCreateTable,
    IS_MEMBER('db_owner') AS IsDbOwner,
    IS_ROLEMEMBER('db_datareader') AS IsDataReader,
    IS_SRVROLEMEMBER('sysadmin') AS IsSysAdmin;
GO

-- Pattern 9: Index functions
SELECT 
    INDEX_COL('dbo.Orders', 1, 1) AS FirstIndexFirstCol,
    INDEXKEY_PROPERTY(OBJECT_ID('dbo.Orders'), 1, 1, 'IsDescending') AS IsDescending,
    INDEXPROPERTY(OBJECT_ID('dbo.Orders'), 'PK_Orders', 'IsClustered') AS IsClustered,
    INDEXPROPERTY(OBJECT_ID('dbo.Orders'), 'PK_Orders', 'IsUnique') AS IsUnique;
GO

-- Pattern 10: File and filegroup functions
SELECT 
    FILE_ID('PRIMARY') AS PrimaryFileID,
    FILE_IDEX('tempdb') AS TempDBFileID,
    FILE_NAME(1) AS FileName1,
    FILEGROUP_ID('PRIMARY') AS PrimaryFilegroupID,
    FILEGROUP_NAME(1) AS FilegroupName1,
    FILEPROPERTY('tempdb', 'SpaceUsed') AS TempDBSpaceUsed,
    FILEGROUPPROPERTY('PRIMARY', 'IsDefault') AS IsDefaultFilegroup;
GO

-- Pattern 11: Statistics functions
SELECT 
    STATS_DATE(OBJECT_ID('dbo.Orders'), 1) AS StatsLastUpdated,
    @@CPU_BUSY AS CPUBusy,
    @@IO_BUSY AS IOBusy,
    @@IDLE AS Idle,
    @@PACKET_ERRORS AS PacketErrors,
    @@TOTAL_READ AS TotalReads,
    @@TOTAL_WRITE AS TotalWrites,
    @@TOTAL_ERRORS AS TotalErrors;
GO

-- Pattern 12: Configuration functions
SELECT 
    @@OPTIONS AS SessionOptions,
    @@TEXTSIZE AS TextSize,
    @@FETCH_STATUS AS FetchStatus,
    @@CURSOR_ROWS AS CursorRows,
    SERVERPROPERTY('ProductVersion') AS ProductVersion,
    SERVERPROPERTY('ProductLevel') AS ProductLevel,
    SERVERPROPERTY('Edition') AS Edition,
    SERVERPROPERTY('EngineEdition') AS EngineEdition,
    SERVERPROPERTY('Collation') AS ServerCollation,
    SERVERPROPERTY('IsFullTextInstalled') AS IsFullTextInstalled;
GO

-- Pattern 13: Database property functions
SELECT 
    DATABASEPROPERTYEX(DB_NAME(), 'Collation') AS DBCollation,
    DATABASEPROPERTYEX(DB_NAME(), 'Recovery') AS RecoveryModel,
    DATABASEPROPERTYEX(DB_NAME(), 'Status') AS Status,
    DATABASEPROPERTYEX(DB_NAME(), 'Updateability') AS Updateability,
    DATABASEPROPERTYEX(DB_NAME(), 'UserAccess') AS UserAccess,
    DATABASEPROPERTYEX(DB_NAME(), 'Version') AS Version;
GO

-- Pattern 14: Assembly and CLR functions
SELECT 
    ASSEMBLYPROPERTY('Microsoft.SqlServer.Types', 'VersionMajor') AS TypesVersionMajor,
    @@MICROSOFTVERSION AS MicrosoftVersion;
GO

-- Pattern 15: Trigger context functions
-- These would be used inside a trigger
/*
CREATE TRIGGER trg_Example ON dbo.Orders
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SELECT 
        TRIGGER_NESTLEVEL() AS NestLevel,
        COLUMNS_UPDATED() AS UpdatedColumns,  -- Bitmask
        UPDATE(ColumnName) AS WasColumnUpdated;  -- Per column check
END
*/
GO

-- Pattern 16: Parsing and validation functions
SELECT 
    ISDATE('2024-06-15') AS IsValidDate,
    ISNUMERIC('123.45') AS IsValidNumeric,
    ISNUMERIC('12.34.56') AS IsInvalidNumeric,
    ISNULL(NULL, 'Default') AS IsNullResult,
    NULLIF('A', 'A') AS NullIfEqual,
    NULLIF('A', 'B') AS NullIfNotEqual;
GO

-- Pattern 17: Data length functions
SELECT 
    DATALENGTH('Hello') AS DataLengthAscii,
    DATALENGTH(N'Hello') AS DataLengthUnicode,
    LEN('Hello') AS LenAscii,
    LEN(N'Hello') AS LenUnicode,
    LEN('Hello   ') AS LenWithTrailingSpaces,
    DATALENGTH('Hello   ') AS DataLengthWithSpaces;
GO

-- Pattern 18: Session context functions
SELECT 
    SESSION_CONTEXT(N'UserID') AS SessionContextUserID,
    CONTEXT_INFO() AS ContextInfo,
    APP_NAME() AS ApplicationName,
    HOST_ID() AS HostProcessID,
    HOST_NAME() AS HostName;
GO

-- Pattern 19: Cursor functions
DECLARE @cursor_var CURSOR;
SELECT 
    CURSOR_STATUS('global', 'cursor_name') AS GlobalCursorStatus,
    CURSOR_STATUS('local', 'cursor_name') AS LocalCursorStatus,
    CURSOR_STATUS('variable', '@cursor_var') AS VariableCursorStatus;
GO

-- Pattern 20: Miscellaneous system functions
SELECT 
    NEWID() AS NewGuid,
    NEWSEQUENTIALID() AS NewSeqGuid,  -- Only in DEFAULT constraint
    CHECKSUM('test') AS Checksum,
    CHECKSUM_AGG(CHECKSUM(*)) AS AggregateChecksum,
    BINARY_CHECKSUM('test') AS BinaryChecksum,
    HASHBYTES('SHA2_256', 'test') AS HashBytes,
    COMPRESS('test data') AS Compressed,
    DECOMPRESS(COMPRESS('test data')) AS Decompressed
FROM (SELECT 1 AS Col) AS T;
GO
