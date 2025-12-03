-- Sample 059: Cross-Database Operations
-- Source: Microsoft Learn, MSSQLTips, Stack Overflow
-- Category: Integration
-- Complexity: Complex
-- Features: Three-part naming, synonyms, cross-database queries, distributed transactions

-- Execute query across multiple databases
CREATE PROCEDURE dbo.ExecuteAcrossDatabases
    @SQL NVARCHAR(MAX),
    @DatabaseList NVARCHAR(MAX) = NULL,  -- Comma-separated, NULL = all user databases
    @ExcludeDatabases NVARCHAR(MAX) = 'master,model,msdb,tempdb'
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @DatabaseName NVARCHAR(128);
    DECLARE @DynamicSQL NVARCHAR(MAX);
    DECLARE @Results TABLE (
        DatabaseName NVARCHAR(128),
        ResultData NVARCHAR(MAX)
    );
    
    -- Build database list
    DECLARE @Databases TABLE (DatabaseName NVARCHAR(128));
    
    IF @DatabaseList IS NOT NULL
    BEGIN
        INSERT INTO @Databases
        SELECT LTRIM(RTRIM(value))
        FROM STRING_SPLIT(@DatabaseList, ',');
    END
    ELSE
    BEGIN
        INSERT INTO @Databases
        SELECT name
        FROM sys.databases
        WHERE state = 0  -- Online
          AND name NOT IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@ExcludeDatabases, ','));
    END
    
    -- Execute in each database
    DECLARE DBCursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT DatabaseName FROM @Databases;
    
    OPEN DBCursor;
    FETCH NEXT FROM DBCursor INTO @DatabaseName;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @DynamicSQL = 'USE ' + QUOTENAME(@DatabaseName) + '; ' + @SQL;
        
        BEGIN TRY
            INSERT INTO @Results (DatabaseName, ResultData)
            EXEC sp_executesql @DynamicSQL;
        END TRY
        BEGIN CATCH
            INSERT INTO @Results (DatabaseName, ResultData)
            VALUES (@DatabaseName, 'Error: ' + ERROR_MESSAGE());
        END CATCH
        
        FETCH NEXT FROM DBCursor INTO @DatabaseName;
    END
    
    CLOSE DBCursor;
    DEALLOCATE DBCursor;
    
    SELECT * FROM @Results;
END
GO

-- Create synonym for cross-database object
CREATE PROCEDURE dbo.CreateCrossDatabaseSynonym
    @SynonymName NVARCHAR(128),
    @TargetDatabase NVARCHAR(128),
    @TargetSchema NVARCHAR(128),
    @TargetObject NVARCHAR(128),
    @LocalSchema NVARCHAR(128) = 'dbo'
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FullSynonym NVARCHAR(256) = QUOTENAME(@LocalSchema) + '.' + QUOTENAME(@SynonymName);
    DECLARE @FullTarget NVARCHAR(256) = QUOTENAME(@TargetDatabase) + '.' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetObject);
    
    -- Drop if exists
    IF EXISTS (SELECT 1 FROM sys.synonyms WHERE name = @SynonymName AND SCHEMA_NAME(schema_id) = @LocalSchema)
    BEGIN
        SET @SQL = 'DROP SYNONYM ' + @FullSynonym;
        EXEC sp_executesql @SQL;
    END
    
    -- Create synonym
    SET @SQL = 'CREATE SYNONYM ' + @FullSynonym + ' FOR ' + @FullTarget;
    EXEC sp_executesql @SQL;
    
    SELECT 'Synonym created' AS Status, @SynonymName AS SynonymName, @FullTarget AS TargetObject;
END
GO

-- Compare object counts across databases
CREATE PROCEDURE dbo.CompareDatabaseObjects
    @Database1 NVARCHAR(128),
    @Database2 NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    
    SET @SQL = N'
        SELECT 
            COALESCE(d1.ObjectType, d2.ObjectType) AS ObjectType,
            d1.ObjectCount AS ' + QUOTENAME(@Database1 + '_Count') + ',
            d2.ObjectCount AS ' + QUOTENAME(@Database2 + '_Count') + ',
            ISNULL(d1.ObjectCount, 0) - ISNULL(d2.ObjectCount, 0) AS Difference
        FROM (
            SELECT type_desc AS ObjectType, COUNT(*) AS ObjectCount
            FROM ' + QUOTENAME(@Database1) + '.sys.objects
            WHERE is_ms_shipped = 0
            GROUP BY type_desc
        ) d1
        FULL OUTER JOIN (
            SELECT type_desc AS ObjectType, COUNT(*) AS ObjectCount
            FROM ' + QUOTENAME(@Database2) + '.sys.objects
            WHERE is_ms_shipped = 0
            GROUP BY type_desc
        ) d2 ON d1.ObjectType = d2.ObjectType
        ORDER BY ObjectType';
    
    EXEC sp_executesql @SQL;
END
GO

-- Copy table data between databases
CREATE PROCEDURE dbo.CopyTableBetweenDatabases
    @SourceDatabase NVARCHAR(128),
    @SourceSchema NVARCHAR(128),
    @SourceTable NVARCHAR(128),
    @TargetDatabase NVARCHAR(128),
    @TargetSchema NVARCHAR(128),
    @TargetTable NVARCHAR(128) = NULL,
    @TruncateTarget BIT = 0,
    @CreateIfNotExists BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @SourcePath NVARCHAR(500) = QUOTENAME(@SourceDatabase) + '.' + QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable);
    DECLARE @TargetPath NVARCHAR(500);
    
    SET @TargetTable = ISNULL(@TargetTable, @SourceTable);
    SET @TargetPath = QUOTENAME(@TargetDatabase) + '.' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable);
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        -- Check if target exists
        DECLARE @TargetExists BIT = 0;
        SET @SQL = N'
            SELECT @Exists = 1 
            FROM ' + QUOTENAME(@TargetDatabase) + '.sys.tables t
            INNER JOIN ' + QUOTENAME(@TargetDatabase) + '.sys.schemas s ON t.schema_id = s.schema_id
            WHERE t.name = @TblName AND s.name = @SchName';
        
        EXEC sp_executesql @SQL,
            N'@TblName NVARCHAR(128), @SchName NVARCHAR(128), @Exists BIT OUTPUT',
            @TblName = @TargetTable, @SchName = @TargetSchema, @Exists = @TargetExists OUTPUT;
        
        -- Create target if needed
        IF @TargetExists = 0 AND @CreateIfNotExists = 1
        BEGIN
            SET @SQL = 'SELECT * INTO ' + @TargetPath + ' FROM ' + @SourcePath + ' WHERE 1 = 0';
            EXEC sp_executesql @SQL;
            PRINT 'Target table created';
        END
        
        -- Truncate if requested
        IF @TruncateTarget = 1 AND @TargetExists = 1
        BEGIN
            SET @SQL = 'TRUNCATE TABLE ' + @TargetPath;
            EXEC sp_executesql @SQL;
        END
        
        -- Copy data
        SET @SQL = 'INSERT INTO ' + @TargetPath + ' SELECT * FROM ' + @SourcePath;
        EXEC sp_executesql @SQL;
        
        DECLARE @RowsCopied INT = @@ROWCOUNT;
        
        COMMIT TRANSACTION;
        
        SELECT 'Data copied successfully' AS Status, @RowsCopied AS RowsCopied;
        
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        SELECT 'Copy failed' AS Status, ERROR_MESSAGE() AS ErrorMessage;
        THROW;
    END CATCH
END
GO

-- Find orphaned cross-database references
CREATE PROCEDURE dbo.FindBrokenReferences
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Check synonyms pointing to missing objects
    SELECT 
        s.name AS SynonymName,
        SCHEMA_NAME(s.schema_id) AS SynonymSchema,
        s.base_object_name AS TargetObject,
        'Synonym' AS ReferenceType,
        CASE 
            WHEN OBJECT_ID(s.base_object_name) IS NULL THEN 'Target Not Found'
            ELSE 'Valid'
        END AS Status
    FROM sys.synonyms s
    WHERE OBJECT_ID(s.base_object_name) IS NULL;
    
    -- Check for cross-database references in procedures/views
    SELECT 
        OBJECT_SCHEMA_NAME(d.referencing_id) AS ReferencingSchema,
        OBJECT_NAME(d.referencing_id) AS ReferencingObject,
        o.type_desc AS ReferencingType,
        d.referenced_database_name AS ReferencedDatabase,
        d.referenced_schema_name AS ReferencedSchema,
        d.referenced_entity_name AS ReferencedObject,
        CASE 
            WHEN d.referenced_database_name IS NOT NULL 
                 AND NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = d.referenced_database_name)
            THEN 'Database Not Found'
            ELSE 'Check Manually'
        END AS Status
    FROM sys.sql_expression_dependencies d
    INNER JOIN sys.objects o ON d.referencing_id = o.object_id
    WHERE d.referenced_database_name IS NOT NULL
      AND d.referenced_database_name <> DB_NAME();
END
GO

-- Get all database sizes
CREATE PROCEDURE dbo.GetAllDatabaseSizes
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        d.name AS DatabaseName,
        d.state_desc AS State,
        d.recovery_model_desc AS RecoveryModel,
        CAST(SUM(CASE WHEN mf.type = 0 THEN mf.size END) * 8.0 / 1024 AS DECIMAL(18,2)) AS DataSizeMB,
        CAST(SUM(CASE WHEN mf.type = 1 THEN mf.size END) * 8.0 / 1024 AS DECIMAL(18,2)) AS LogSizeMB,
        CAST(SUM(mf.size) * 8.0 / 1024 AS DECIMAL(18,2)) AS TotalSizeMB,
        d.create_date AS CreatedDate
    FROM sys.databases d
    INNER JOIN sys.master_files mf ON d.database_id = mf.database_id
    GROUP BY d.name, d.state_desc, d.recovery_model_desc, d.create_date
    ORDER BY TotalSizeMB DESC;
END
GO
