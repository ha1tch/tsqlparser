-- Sample 080: Database Cloning and Templating
-- Source: Microsoft Learn, MSSQLTips, Database DevOps patterns
-- Category: ETL/Data Loading
-- Complexity: Advanced
-- Features: DBCC CLONEDATABASE, schema-only copy, template databases

-- Clone database (schema only) for testing
CREATE PROCEDURE dbo.CloneDatabaseSchemaOnly
    @SourceDatabase NVARCHAR(128),
    @TargetDatabase NVARCHAR(128),
    @IncludeStatistics BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    
    -- Validate source exists
    IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = @SourceDatabase)
    BEGIN
        RAISERROR('Source database does not exist: %s', 16, 1, @SourceDatabase);
        RETURN;
    END
    
    -- Check if target exists
    IF EXISTS (SELECT 1 FROM sys.databases WHERE name = @TargetDatabase)
    BEGIN
        RAISERROR('Target database already exists: %s', 16, 1, @TargetDatabase);
        RETURN;
    END
    
    -- Use DBCC CLONEDATABASE (SQL Server 2016+)
    IF @IncludeStatistics = 1
    BEGIN
        DBCC CLONEDATABASE (@SourceDatabase, @TargetDatabase) WITH VERIFY_CLONEDB;
    END
    ELSE
    BEGIN
        DBCC CLONEDATABASE (@SourceDatabase, @TargetDatabase) WITH NO_STATISTICS, VERIFY_CLONEDB;
    END
    
    -- Make the clone database read-write
    SET @SQL = 'ALTER DATABASE ' + QUOTENAME(@TargetDatabase) + ' SET READ_WRITE';
    EXEC sp_executesql @SQL;
    
    SELECT 'Database cloned successfully' AS Status, @TargetDatabase AS NewDatabase;
END
GO

-- Generate script to recreate database schema
CREATE PROCEDURE dbo.GenerateDatabaseSchemaScript
    @DatabaseName NVARCHAR(128) = NULL,
    @IncludeTables BIT = 1,
    @IncludeViews BIT = 1,
    @IncludeProcedures BIT = 1,
    @IncludeFunctions BIT = 1,
    @IncludeIndexes BIT = 1,
    @IncludeConstraints BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @DatabaseName = ISNULL(@DatabaseName, DB_NAME());
    
    DECLARE @Scripts TABLE (ObjectType NVARCHAR(50), ObjectName NVARCHAR(256), Script NVARCHAR(MAX), SortOrder INT);
    
    -- Tables
    IF @IncludeTables = 1
    BEGIN
        INSERT INTO @Scripts
        SELECT 
            'TABLE',
            SCHEMA_NAME(t.schema_id) + '.' + t.name,
            'CREATE TABLE ' + QUOTENAME(SCHEMA_NAME(t.schema_id)) + '.' + QUOTENAME(t.name) + ' (' + CHAR(13) +
            STRING_AGG(
                '    ' + QUOTENAME(c.name) + ' ' + 
                TYPE_NAME(c.user_type_id) + 
                CASE WHEN TYPE_NAME(c.user_type_id) IN ('varchar', 'nvarchar', 'char', 'nchar') 
                     THEN '(' + CASE WHEN c.max_length = -1 THEN 'MAX' ELSE CAST(c.max_length / CASE WHEN TYPE_NAME(c.user_type_id) LIKE 'n%' THEN 2 ELSE 1 END AS VARCHAR(10)) END + ')'
                     WHEN TYPE_NAME(c.user_type_id) IN ('decimal', 'numeric')
                     THEN '(' + CAST(c.precision AS VARCHAR(10)) + ',' + CAST(c.scale AS VARCHAR(10)) + ')'
                     ELSE ''
                END +
                CASE WHEN c.is_nullable = 0 THEN ' NOT NULL' ELSE ' NULL' END +
                CASE WHEN c.is_identity = 1 THEN ' IDENTITY(1,1)' ELSE '' END,
                ',' + CHAR(13)
            ) WITHIN GROUP (ORDER BY c.column_id) + CHAR(13) + ');',
            1
        FROM sys.tables t
        INNER JOIN sys.columns c ON t.object_id = c.object_id
        WHERE t.is_ms_shipped = 0
        GROUP BY t.schema_id, t.name, t.object_id;
    END
    
    -- Views
    IF @IncludeViews = 1
    BEGIN
        INSERT INTO @Scripts
        SELECT 'VIEW', SCHEMA_NAME(v.schema_id) + '.' + v.name, m.definition, 2
        FROM sys.views v
        INNER JOIN sys.sql_modules m ON v.object_id = m.object_id
        WHERE v.is_ms_shipped = 0;
    END
    
    -- Procedures
    IF @IncludeProcedures = 1
    BEGIN
        INSERT INTO @Scripts
        SELECT 'PROCEDURE', SCHEMA_NAME(p.schema_id) + '.' + p.name, m.definition, 3
        FROM sys.procedures p
        INNER JOIN sys.sql_modules m ON p.object_id = m.object_id
        WHERE p.is_ms_shipped = 0;
    END
    
    -- Functions
    IF @IncludeFunctions = 1
    BEGIN
        INSERT INTO @Scripts
        SELECT 'FUNCTION', SCHEMA_NAME(o.schema_id) + '.' + o.name, m.definition, 4
        FROM sys.objects o
        INNER JOIN sys.sql_modules m ON o.object_id = m.object_id
        WHERE o.type IN ('FN', 'TF', 'IF')
          AND o.is_ms_shipped = 0;
    END
    
    SELECT ObjectType, ObjectName, Script FROM @Scripts ORDER BY SortOrder, ObjectName;
END
GO

-- Create database from template
CREATE PROCEDURE dbo.CreateDatabaseFromTemplate
    @TemplateName NVARCHAR(128),
    @NewDatabaseName NVARCHAR(128),
    @DataFilePath NVARCHAR(500) = NULL,
    @LogFilePath NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @TemplateDataPath NVARCHAR(500);
    DECLARE @TemplateLogPath NVARCHAR(500);
    
    -- Get template file paths
    SELECT @TemplateDataPath = physical_name
    FROM sys.master_files
    WHERE database_id = DB_ID(@TemplateName) AND type = 0;
    
    SELECT @TemplateLogPath = physical_name
    FROM sys.master_files
    WHERE database_id = DB_ID(@TemplateName) AND type = 1;
    
    -- Use same directory if not specified
    IF @DataFilePath IS NULL
        SET @DataFilePath = LEFT(@TemplateDataPath, LEN(@TemplateDataPath) - CHARINDEX('\', REVERSE(@TemplateDataPath)) + 1) + @NewDatabaseName + '.mdf';
    
    IF @LogFilePath IS NULL
        SET @LogFilePath = LEFT(@TemplateLogPath, LEN(@TemplateLogPath) - CHARINDEX('\', REVERSE(@TemplateLogPath)) + 1) + @NewDatabaseName + '_log.ldf';
    
    -- Set template offline
    SET @SQL = 'ALTER DATABASE ' + QUOTENAME(@TemplateName) + ' SET OFFLINE WITH ROLLBACK IMMEDIATE';
    EXEC sp_executesql @SQL;
    
    -- Restore from template using file copy
    -- Note: In production, use RESTORE WITH MOVE instead
    SET @SQL = '
        CREATE DATABASE ' + QUOTENAME(@NewDatabaseName) + '
        ON (NAME = ' + QUOTENAME(@NewDatabaseName + '_Data', '''') + ', FILENAME = ' + QUOTENAME(@DataFilePath, '''') + ')
        LOG ON (NAME = ' + QUOTENAME(@NewDatabaseName + '_Log', '''') + ', FILENAME = ' + QUOTENAME(@LogFilePath, '''') + ')
        FOR ATTACH';
    
    -- Bring template back online
    SET @SQL = 'ALTER DATABASE ' + QUOTENAME(@TemplateName) + ' SET ONLINE';
    EXEC sp_executesql @SQL;
    
    SELECT 'Note: For production use, consider RESTORE DATABASE with MOVE option' AS Warning;
END
GO

-- Compare two database schemas
CREATE PROCEDURE dbo.CompareDatabaseSchemas
    @Database1 NVARCHAR(128),
    @Database2 NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    
    -- Compare tables
    SET @SQL = N'
        SELECT 
            COALESCE(d1.TableName, d2.TableName) AS TableName,
            CASE 
                WHEN d1.TableName IS NULL THEN ''Only in ' + @Database2 + '''
                WHEN d2.TableName IS NULL THEN ''Only in ' + @Database1 + '''
                WHEN d1.ColumnCount <> d2.ColumnCount THEN ''Column count differs''
                ELSE ''Match''
            END AS ComparisonResult,
            d1.ColumnCount AS ' + QUOTENAME(@Database1 + '_Columns') + ',
            d2.ColumnCount AS ' + QUOTENAME(@Database2 + '_Columns') + '
        FROM (
            SELECT SCHEMA_NAME(schema_id) + ''.'' + name AS TableName, 
                   (SELECT COUNT(*) FROM ' + QUOTENAME(@Database1) + '.sys.columns c WHERE c.object_id = t.object_id) AS ColumnCount
            FROM ' + QUOTENAME(@Database1) + '.sys.tables t
        ) d1
        FULL OUTER JOIN (
            SELECT SCHEMA_NAME(schema_id) + ''.'' + name AS TableName,
                   (SELECT COUNT(*) FROM ' + QUOTENAME(@Database2) + '.sys.columns c WHERE c.object_id = t.object_id) AS ColumnCount
            FROM ' + QUOTENAME(@Database2) + '.sys.tables t
        ) d2 ON d1.TableName = d2.TableName
        ORDER BY COALESCE(d1.TableName, d2.TableName)';
    
    EXEC sp_executesql @SQL;
    
    -- Compare stored procedures
    SET @SQL = N'
        SELECT 
            COALESCE(d1.ProcName, d2.ProcName) AS ProcedureName,
            CASE 
                WHEN d1.ProcName IS NULL THEN ''Only in ' + @Database2 + '''
                WHEN d2.ProcName IS NULL THEN ''Only in ' + @Database1 + '''
                WHEN d1.DefHash <> d2.DefHash THEN ''Definition differs''
                ELSE ''Match''
            END AS ComparisonResult
        FROM (
            SELECT SCHEMA_NAME(p.schema_id) + ''.'' + p.name AS ProcName,
                   HASHBYTES(''SHA2_256'', m.definition) AS DefHash
            FROM ' + QUOTENAME(@Database1) + '.sys.procedures p
            INNER JOIN ' + QUOTENAME(@Database1) + '.sys.sql_modules m ON p.object_id = m.object_id
        ) d1
        FULL OUTER JOIN (
            SELECT SCHEMA_NAME(p.schema_id) + ''.'' + p.name AS ProcName,
                   HASHBYTES(''SHA2_256'', m.definition) AS DefHash
            FROM ' + QUOTENAME(@Database2) + '.sys.procedures p
            INNER JOIN ' + QUOTENAME(@Database2) + '.sys.sql_modules m ON p.object_id = m.object_id
        ) d2 ON d1.ProcName = d2.ProcName
        ORDER BY COALESCE(d1.ProcName, d2.ProcName)';
    
    EXEC sp_executesql @SQL;
END
GO

-- Export table structure as JSON template
CREATE PROCEDURE dbo.ExportTableAsTemplate
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT (
        SELECT 
            @SchemaName AS schemaName,
            @TableName AS tableName,
            (
                SELECT 
                    c.name AS columnName,
                    TYPE_NAME(c.user_type_id) AS dataType,
                    c.max_length AS maxLength,
                    c.precision AS precision,
                    c.scale AS scale,
                    c.is_nullable AS isNullable,
                    c.is_identity AS isIdentity,
                    dc.definition AS defaultValue
                FROM sys.columns c
                LEFT JOIN sys.default_constraints dc ON c.default_object_id = dc.object_id
                WHERE c.object_id = OBJECT_ID(QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName))
                ORDER BY c.column_id
                FOR JSON PATH
            ) AS columns,
            (
                SELECT 
                    i.name AS indexName,
                    i.type_desc AS indexType,
                    i.is_unique AS isUnique,
                    i.is_primary_key AS isPrimaryKey,
                    STRING_AGG(COL_NAME(ic.object_id, ic.column_id), ',') AS columns
                FROM sys.indexes i
                INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
                WHERE i.object_id = OBJECT_ID(QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName))
                GROUP BY i.name, i.type_desc, i.is_unique, i.is_primary_key
                FOR JSON PATH
            ) AS indexes
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    ) AS TableTemplate;
END
GO
