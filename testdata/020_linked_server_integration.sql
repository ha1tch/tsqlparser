-- Sample 020: Linked Server and External Data Access
-- Source: Microsoft Learn, MSSQLTips, Various
-- Category: Integration
-- Complexity: Complex
-- Features: OPENQUERY, OPENROWSET, linked servers, distributed queries

-- Execute query on linked server using OPENQUERY
CREATE PROCEDURE dbo.QueryLinkedServer
    @LinkedServerName NVARCHAR(128),
    @Query NVARCHAR(MAX),
    @UseOpenQuery BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    
    IF @UseOpenQuery = 1
    BEGIN
        -- OPENQUERY approach - query parsed and executed on remote server
        -- More efficient for complex queries
        SET @SQL = N'SELECT * FROM OPENQUERY(' + 
                   QUOTENAME(@LinkedServerName) + ', ''' +
                   REPLACE(@Query, '''', '''''') + ''')';
    END
    ELSE
    BEGIN
        -- Four-part naming - query parsed locally
        -- Useful for simple queries, allows local predicates
        SET @SQL = @Query;  -- Assumes query already uses four-part names
    END
    
    EXEC sp_executesql @SQL;
END
GO

-- Synchronize data between servers
CREATE PROCEDURE dbo.SyncTableFromLinkedServer
    @LinkedServerName NVARCHAR(128),
    @SourceDatabase NVARCHAR(128),
    @SourceSchema NVARCHAR(128),
    @SourceTable NVARCHAR(128),
    @TargetSchema NVARCHAR(128) = 'dbo',
    @TargetTable NVARCHAR(128),
    @KeyColumns NVARCHAR(500),  -- Comma-separated
    @SyncMode NVARCHAR(20) = 'MERGE',  -- MERGE, TRUNCATE_INSERT, APPEND
    @BatchSize INT = 10000
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @SourcePath NVARCHAR(500);
    DECLARE @RowCount INT = 0;
    DECLARE @StartTime DATETIME = GETDATE();
    
    SET @SourcePath = QUOTENAME(@LinkedServerName) + '.' + 
                      QUOTENAME(@SourceDatabase) + '.' + 
                      QUOTENAME(@SourceSchema) + '.' + 
                      QUOTENAME(@SourceTable);
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        IF @SyncMode = 'TRUNCATE_INSERT'
        BEGIN
            -- Simple truncate and reload
            SET @SQL = 'TRUNCATE TABLE ' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable);
            EXEC sp_executesql @SQL;
            
            SET @SQL = 'INSERT INTO ' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable) + '
                        SELECT * FROM ' + @SourcePath;
            EXEC sp_executesql @SQL;
            
            SET @RowCount = @@ROWCOUNT;
        END
        ELSE IF @SyncMode = 'APPEND'
        BEGIN
            -- Only insert new records
            DECLARE @JoinCondition NVARCHAR(MAX) = '';
            DECLARE @KeyCol NVARCHAR(128);
            DECLARE @KeyList TABLE (ColName NVARCHAR(128));
            
            INSERT INTO @KeyList
            SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@KeyColumns, ',');
            
            SELECT @JoinCondition = STRING_AGG(
                'src.' + QUOTENAME(ColName) + ' = tgt.' + QUOTENAME(ColName), ' AND '
            )
            FROM @KeyList;
            
            SET @SQL = '
                INSERT INTO ' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable) + '
                SELECT src.*
                FROM ' + @SourcePath + ' src
                WHERE NOT EXISTS (
                    SELECT 1 FROM ' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable) + ' tgt
                    WHERE ' + @JoinCondition + '
                )';
            
            EXEC sp_executesql @SQL;
            SET @RowCount = @@ROWCOUNT;
        END
        ELSE IF @SyncMode = 'MERGE'
        BEGIN
            -- Full merge (insert, update, optionally delete)
            DECLARE @MergeJoin NVARCHAR(MAX) = '';
            DECLARE @UpdateSet NVARCHAR(MAX);
            DECLARE @InsertCols NVARCHAR(MAX);
            
            -- Build join condition from key columns
            SELECT @MergeJoin = STRING_AGG(
                'tgt.' + QUOTENAME(ColName) + ' = src.' + QUOTENAME(ColName), ' AND '
            )
            FROM (SELECT LTRIM(RTRIM(value)) AS ColName FROM STRING_SPLIT(@KeyColumns, ',')) k;
            
            -- Get all columns for insert/update
            SET @SQL = N'
                SELECT @cols = STRING_AGG(QUOTENAME(c.name), '', '')
                FROM ' + QUOTENAME(@LinkedServerName) + '.' + QUOTENAME(@SourceDatabase) + 
                '.sys.columns c
                INNER JOIN ' + QUOTENAME(@LinkedServerName) + '.' + QUOTENAME(@SourceDatabase) + 
                '.sys.tables t ON c.object_id = t.object_id
                INNER JOIN ' + QUOTENAME(@LinkedServerName) + '.' + QUOTENAME(@SourceDatabase) + 
                '.sys.schemas s ON t.schema_id = s.schema_id
                WHERE t.name = @TableName AND s.name = @SchemaName';
            
            EXEC sp_executesql @SQL, 
                N'@TableName NVARCHAR(128), @SchemaName NVARCHAR(128), @cols NVARCHAR(MAX) OUTPUT',
                @TableName = @SourceTable, @SchemaName = @SourceSchema, @cols = @InsertCols OUTPUT;
            
            -- Build MERGE statement
            SET @SQL = '
                MERGE ' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable) + ' AS tgt
                USING ' + @SourcePath + ' AS src
                ON ' + @MergeJoin + '
                WHEN MATCHED THEN
                    UPDATE SET ' + 
                    (SELECT STRING_AGG('tgt.' + QUOTENAME(LTRIM(RTRIM(value))) + ' = src.' + QUOTENAME(LTRIM(RTRIM(value))), ', ')
                     FROM STRING_SPLIT(@InsertCols, ',')) + '
                WHEN NOT MATCHED BY TARGET THEN
                    INSERT (' + @InsertCols + ')
                    VALUES (src.' + REPLACE(@InsertCols, ', ', ', src.') + ');';
            
            EXEC sp_executesql @SQL;
            SET @RowCount = @@ROWCOUNT;
        END
        
        COMMIT TRANSACTION;
        
        -- Return summary
        SELECT 
            @SyncMode AS SyncMode,
            @SourcePath AS Source,
            QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable) AS Target,
            @RowCount AS RowsAffected,
            DATEDIFF(SECOND, @StartTime, GETDATE()) AS DurationSeconds,
            'Success' AS Status;
            
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        SELECT 
            @SyncMode AS SyncMode,
            @SourcePath AS Source,
            QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable) AS Target,
            0 AS RowsAffected,
            DATEDIFF(SECOND, @StartTime, GETDATE()) AS DurationSeconds,
            'Failed' AS Status,
            ERROR_MESSAGE() AS ErrorMessage;
            
        THROW;
    END CATCH
END
GO

-- Query Excel file using OPENROWSET
CREATE PROCEDURE dbo.ImportFromExcel
    @FilePath NVARCHAR(500),
    @SheetName NVARCHAR(128) = 'Sheet1$',
    @TargetTable NVARCHAR(128),
    @TargetSchema NVARCHAR(128) = 'dbo',
    @TruncateTarget BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    
    -- Truncate if requested
    IF @TruncateTarget = 1
    BEGIN
        SET @SQL = 'TRUNCATE TABLE ' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable);
        EXEC sp_executesql @SQL;
    END
    
    -- Import from Excel using ACE provider
    SET @SQL = '
        INSERT INTO ' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable) + '
        SELECT * FROM OPENROWSET(
            ''Microsoft.ACE.OLEDB.12.0'',
            ''Excel 12.0;Database=' + @FilePath + ';HDR=YES;IMEX=1'',
            ''SELECT * FROM [' + @SheetName + ']''
        )';
    
    EXEC sp_executesql @SQL;
    
    SELECT @@ROWCOUNT AS RowsImported;
END
GO

-- Compare data between linked servers
CREATE PROCEDURE dbo.CompareLinkedServerData
    @Server1 NVARCHAR(128),
    @Server2 NVARCHAR(128),
    @Database NVARCHAR(128),
    @Schema NVARCHAR(128),
    @Table NVARCHAR(128),
    @KeyColumns NVARCHAR(500),
    @CompareColumns NVARCHAR(MAX) = NULL  -- NULL = all columns
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @JoinCondition NVARCHAR(MAX);
    DECLARE @CompareCondition NVARCHAR(MAX);
    DECLARE @Path1 NVARCHAR(500);
    DECLARE @Path2 NVARCHAR(500);
    
    SET @Path1 = QUOTENAME(@Server1) + '.' + QUOTENAME(@Database) + '.' + 
                 QUOTENAME(@Schema) + '.' + QUOTENAME(@Table);
    SET @Path2 = QUOTENAME(@Server2) + '.' + QUOTENAME(@Database) + '.' + 
                 QUOTENAME(@Schema) + '.' + QUOTENAME(@Table);
    
    -- Build join condition
    SELECT @JoinCondition = STRING_AGG(
        's1.' + QUOTENAME(LTRIM(RTRIM(value))) + ' = s2.' + QUOTENAME(LTRIM(RTRIM(value))), ' AND '
    )
    FROM STRING_SPLIT(@KeyColumns, ',');
    
    -- Find records only in Server1
    SET @SQL = '
        SELECT ''Only in ' + @Server1 + ''' AS Location, s1.*
        FROM ' + @Path1 + ' s1
        WHERE NOT EXISTS (
            SELECT 1 FROM ' + @Path2 + ' s2
            WHERE ' + @JoinCondition + '
        )';
    
    EXEC sp_executesql @SQL;
    
    -- Find records only in Server2
    SET @SQL = '
        SELECT ''Only in ' + @Server2 + ''' AS Location, s2.*
        FROM ' + @Path2 + ' s2
        WHERE NOT EXISTS (
            SELECT 1 FROM ' + @Path1 + ' s1
            WHERE ' + @JoinCondition + '
        )';
    
    EXEC sp_executesql @SQL;
    
    -- Summary
    SET @SQL = '
        SELECT 
            (SELECT COUNT(*) FROM ' + @Path1 + ') AS Server1Count,
            (SELECT COUNT(*) FROM ' + @Path2 + ') AS Server2Count,
            (SELECT COUNT(*) FROM ' + @Path1 + ' s1
             WHERE NOT EXISTS (SELECT 1 FROM ' + @Path2 + ' s2 WHERE ' + @JoinCondition + ')
            ) AS OnlyInServer1,
            (SELECT COUNT(*) FROM ' + @Path2 + ' s2
             WHERE NOT EXISTS (SELECT 1 FROM ' + @Path1 + ' s1 WHERE ' + @JoinCondition + ')
            ) AS OnlyInServer2';
    
    EXEC sp_executesql @SQL;
END
GO
