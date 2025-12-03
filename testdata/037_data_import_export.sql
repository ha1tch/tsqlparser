-- Sample 037: Data Import/Export Procedures
-- Source: Microsoft Learn, MSSQLTips, Stack Overflow
-- Category: ETL/Data Loading
-- Complexity: Advanced
-- Features: BULK INSERT, OPENROWSET, BCP, FORMAT files, staging patterns

-- Import CSV file with error handling
CREATE PROCEDURE dbo.ImportCSVFile
    @FilePath NVARCHAR(500),
    @TargetSchema NVARCHAR(128) = 'dbo',
    @TargetTable NVARCHAR(128),
    @HasHeader BIT = 1,
    @FieldTerminator NVARCHAR(10) = ',',
    @RowTerminator NVARCHAR(10) = '\n',
    @MaxErrors INT = 10,
    @TruncateFirst BIT = 0,
    @UseStaging BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @StagingTable NVARCHAR(128);
    DECLARE @TargetPath NVARCHAR(256) = QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable);
    DECLARE @RowsImported INT;
    DECLARE @StartTime DATETIME = GETDATE();
    
    BEGIN TRY
        IF @UseStaging = 1
        BEGIN
            -- Create staging table
            SET @StagingTable = @TargetTable + '_Staging_' + FORMAT(GETDATE(), 'yyyyMMddHHmmss');
            
            SET @SQL = 'SELECT * INTO ' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@StagingTable) + 
                       ' FROM ' + @TargetPath + ' WHERE 1 = 0';
            EXEC sp_executesql @SQL;
            
            -- Bulk insert into staging
            SET @SQL = '
                BULK INSERT ' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@StagingTable) + '
                FROM ''' + @FilePath + '''
                WITH (
                    FIELDTERMINATOR = ''' + @FieldTerminator + ''',
                    ROWTERMINATOR = ''' + @RowTerminator + ''',
                    FIRSTROW = ' + CASE WHEN @HasHeader = 1 THEN '2' ELSE '1' END + ',
                    MAXERRORS = ' + CAST(@MaxErrors AS VARCHAR(10)) + ',
                    TABLOCK,
                    ERRORFILE = ''' + @FilePath + '.errors''
                )';
            
            EXEC sp_executesql @SQL;
            SET @RowsImported = @@ROWCOUNT;
            
            -- Truncate target if requested
            IF @TruncateFirst = 1
            BEGIN
                SET @SQL = 'TRUNCATE TABLE ' + @TargetPath;
                EXEC sp_executesql @SQL;
            END
            
            -- Move from staging to target
            SET @SQL = 'INSERT INTO ' + @TargetPath + ' SELECT * FROM ' + 
                       QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@StagingTable);
            EXEC sp_executesql @SQL;
            
            -- Drop staging
            SET @SQL = 'DROP TABLE ' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@StagingTable);
            EXEC sp_executesql @SQL;
        END
        ELSE
        BEGIN
            -- Direct bulk insert
            IF @TruncateFirst = 1
            BEGIN
                SET @SQL = 'TRUNCATE TABLE ' + @TargetPath;
                EXEC sp_executesql @SQL;
            END
            
            SET @SQL = '
                BULK INSERT ' + @TargetPath + '
                FROM ''' + @FilePath + '''
                WITH (
                    FIELDTERMINATOR = ''' + @FieldTerminator + ''',
                    ROWTERMINATOR = ''' + @RowTerminator + ''',
                    FIRSTROW = ' + CASE WHEN @HasHeader = 1 THEN '2' ELSE '1' END + ',
                    MAXERRORS = ' + CAST(@MaxErrors AS VARCHAR(10)) + ',
                    TABLOCK
                )';
            
            EXEC sp_executesql @SQL;
            SET @RowsImported = @@ROWCOUNT;
        END
        
        SELECT 
            'Import completed' AS Status,
            @RowsImported AS RowsImported,
            DATEDIFF(SECOND, @StartTime, GETDATE()) AS DurationSeconds,
            @TargetPath AS TargetTable;
            
    END TRY
    BEGIN CATCH
        -- Clean up staging if exists
        IF @UseStaging = 1 AND @StagingTable IS NOT NULL
        BEGIN
            SET @SQL = 'IF OBJECT_ID(''' + @TargetSchema + '.' + @StagingTable + ''') IS NOT NULL DROP TABLE ' + 
                       QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@StagingTable);
            EXEC sp_executesql @SQL;
        END
        
        SELECT 
            'Import failed' AS Status,
            ERROR_MESSAGE() AS ErrorMessage,
            ERROR_LINE() AS ErrorLine;
        
        THROW;
    END CATCH
END
GO

-- Export table to CSV format (generates BCP command)
CREATE PROCEDURE dbo.ExportToCSV
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @OutputPath NVARCHAR(500),
    @IncludeHeader BIT = 1,
    @FieldTerminator NVARCHAR(10) = ',',
    @Query NVARCHAR(MAX) = NULL,
    @ServerName NVARCHAR(128) = NULL,
    @GenerateScriptOnly BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @BCPCommand NVARCHAR(MAX);
    DECLARE @SourcePath NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    DECLARE @HeaderSQL NVARCHAR(MAX);
    
    SET @ServerName = ISNULL(@ServerName, @@SERVERNAME);
    
    -- Build header row if needed
    IF @IncludeHeader = 1
    BEGIN
        SELECT @HeaderSQL = STRING_AGG(QUOTENAME(c.name, '"'), @FieldTerminator)
        FROM sys.columns c
        WHERE c.object_id = OBJECT_ID(@SourcePath)
        ORDER BY c.column_id;
    END
    
    -- Build query if not provided
    IF @Query IS NULL
        SET @Query = 'SELECT * FROM ' + @SourcePath;
    
    -- Generate BCP command
    SET @BCPCommand = 'bcp "' + REPLACE(@Query, '"', '\"') + '" queryout "' + @OutputPath + '" ' +
                      '-c -t"' + @FieldTerminator + '" -S ' + @ServerName + ' -T';
    
    IF @GenerateScriptOnly = 1
    BEGIN
        SELECT 
            'BCP Export Command' AS CommandType,
            @BCPCommand AS Command;
        
        IF @IncludeHeader = 1
        BEGIN
            SELECT 
                'Header Row' AS Info,
                @HeaderSQL AS HeaderRow,
                'Prepend this to the output file' AS Note;
        END
    END
    ELSE
    BEGIN
        -- Execute via xp_cmdshell (requires appropriate permissions)
        DECLARE @Result TABLE (OutputLine NVARCHAR(MAX));
        
        INSERT INTO @Result
        EXEC xp_cmdshell @BCPCommand;
        
        SELECT * FROM @Result WHERE OutputLine IS NOT NULL;
    END
END
GO

-- Import data with transformations
CREATE PROCEDURE dbo.ImportWithTransform
    @SourcePath NVARCHAR(500),
    @TargetSchema NVARCHAR(128),
    @TargetTable NVARCHAR(128),
    @TransformSQL NVARCHAR(MAX),  -- SQL to transform staging data
    @ValidateSQL NVARCHAR(MAX) = NULL,  -- SQL to validate before final insert
    @BatchSize INT = 10000
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @StagingTable NVARCHAR(128) = 'Import_Staging_' + FORMAT(GETDATE(), 'yyyyMMddHHmmss');
    DECLARE @ErrorTable NVARCHAR(128) = 'Import_Errors_' + FORMAT(GETDATE(), 'yyyyMMddHHmmss');
    DECLARE @RowsStaged INT;
    DECLARE @RowsValid INT;
    DECLARE @RowsImported INT;
    DECLARE @RowsRejected INT;
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        -- Create staging table (all NVARCHAR for flexibility)
        SET @SQL = '
            CREATE TABLE dbo.' + QUOTENAME(@StagingTable) + ' (
                RowID INT IDENTITY(1,1),
                RawData NVARCHAR(MAX)
            )';
        EXEC sp_executesql @SQL;
        
        -- Import raw data
        SET @SQL = '
            BULK INSERT dbo.' + QUOTENAME(@StagingTable) + '
            FROM ''' + @SourcePath + '''
            WITH (ROWTERMINATOR = ''\n'')';
        EXEC sp_executesql @SQL;
        
        SET @RowsStaged = @@ROWCOUNT;
        
        -- Create transformed staging table
        SET @SQL = 'SELECT * INTO dbo.' + QUOTENAME(@StagingTable + '_Transformed') + 
                   ' FROM (' + @TransformSQL + ') AS Transformed';
        EXEC sp_executesql @SQL;
        
        -- Validate if validation SQL provided
        IF @ValidateSQL IS NOT NULL
        BEGIN
            -- Create error table
            SET @SQL = '
                SELECT *, ''Validation Failed'' AS ErrorReason
                INTO dbo.' + QUOTENAME(@ErrorTable) + '
                FROM dbo.' + QUOTENAME(@StagingTable + '_Transformed') + '
                WHERE NOT (' + @ValidateSQL + ')';
            EXEC sp_executesql @SQL;
            
            SET @RowsRejected = @@ROWCOUNT;
            
            -- Remove invalid rows from staging
            SET @SQL = '
                DELETE FROM dbo.' + QUOTENAME(@StagingTable + '_Transformed') + '
                WHERE NOT (' + @ValidateSQL + ')';
            EXEC sp_executesql @SQL;
        END
        ELSE
            SET @RowsRejected = 0;
        
        -- Insert into target
        SET @SQL = '
            INSERT INTO ' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable) + '
            SELECT * FROM dbo.' + QUOTENAME(@StagingTable + '_Transformed');
        EXEC sp_executesql @SQL;
        
        SET @RowsImported = @@ROWCOUNT;
        
        COMMIT TRANSACTION;
        
        -- Cleanup
        SET @SQL = 'DROP TABLE IF EXISTS dbo.' + QUOTENAME(@StagingTable);
        EXEC sp_executesql @SQL;
        SET @SQL = 'DROP TABLE IF EXISTS dbo.' + QUOTENAME(@StagingTable + '_Transformed');
        EXEC sp_executesql @SQL;
        
        SELECT 
            'Import completed' AS Status,
            @RowsStaged AS RowsStaged,
            @RowsImported AS RowsImported,
            @RowsRejected AS RowsRejected,
            CASE WHEN @RowsRejected > 0 THEN @ErrorTable ELSE NULL END AS ErrorTable;
            
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        -- Cleanup on error
        SET @SQL = 'DROP TABLE IF EXISTS dbo.' + QUOTENAME(@StagingTable);
        EXEC sp_executesql @SQL;
        SET @SQL = 'DROP TABLE IF EXISTS dbo.' + QUOTENAME(@StagingTable + '_Transformed');
        EXEC sp_executesql @SQL;
        
        THROW;
    END CATCH
END
GO

-- Generate INSERT statements for data export
CREATE PROCEDURE dbo.GenerateInsertStatements
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @WhereClause NVARCHAR(MAX) = NULL,
    @IncludeIdentity BIT = 0,
    @TopN INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @ColumnList NVARCHAR(MAX);
    DECLARE @ValueTemplate NVARCHAR(MAX);
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    
    -- Build column list
    SELECT @ColumnList = STRING_AGG(QUOTENAME(c.name), ', '),
           @ValueTemplate = STRING_AGG(
               CASE 
                   WHEN t.name IN ('int', 'bigint', 'smallint', 'tinyint', 'bit', 'decimal', 'numeric', 'money', 'smallmoney', 'float', 'real')
                   THEN 'ISNULL(CAST(' + QUOTENAME(c.name) + ' AS NVARCHAR(MAX)), ''NULL'')'
                   WHEN t.name IN ('datetime', 'datetime2', 'date', 'time', 'datetimeoffset', 'smalldatetime')
                   THEN 'ISNULL('''''''' + CONVERT(NVARCHAR(50), ' + QUOTENAME(c.name) + ', 121) + '''''''', ''NULL'')'
                   ELSE 'ISNULL('''''''' + REPLACE(CAST(' + QUOTENAME(c.name) + ' AS NVARCHAR(MAX)), '''''''', '''''''''''') + '''''''', ''NULL'')'
               END, ' + '', '' + '
           )
    FROM sys.columns c
    INNER JOIN sys.types t ON c.user_type_id = t.user_type_id
    WHERE c.object_id = OBJECT_ID(@FullPath)
      AND (@IncludeIdentity = 1 OR c.is_identity = 0);
    
    -- Generate INSERT statements
    SET @SQL = '
        SELECT ''INSERT INTO ' + @FullPath + ' (' + @ColumnList + ') VALUES ('' + ' + @ValueTemplate + ' + '');''
        FROM ' + @FullPath;
    
    IF @WhereClause IS NOT NULL
        SET @SQL = @SQL + ' WHERE ' + @WhereClause;
    
    IF @TopN IS NOT NULL
        SET @SQL = 'SELECT TOP ' + CAST(@TopN AS VARCHAR(10)) + ' * FROM (' + @SQL + ') AS Inserts';
    
    -- Add identity insert wrapper if needed
    IF @IncludeIdentity = 1 AND EXISTS (
        SELECT 1 FROM sys.columns 
        WHERE object_id = OBJECT_ID(@FullPath) AND is_identity = 1
    )
    BEGIN
        -- Note: FROM (EXEC ...) is not valid T-SQL. Use INSERT...EXEC pattern instead.
        DECLARE @InsertStmts TABLE (InsertStatement NVARCHAR(MAX));
        INSERT INTO @InsertStmts EXEC sp_executesql @SQL;
        
        SELECT 'SET IDENTITY_INSERT ' + @FullPath + ' ON;' AS InsertStatement
        UNION ALL
        SELECT InsertStatement FROM @InsertStmts
        UNION ALL
        SELECT 'SET IDENTITY_INSERT ' + @FullPath + ' OFF;';
    END
    ELSE
    BEGIN
        EXEC sp_executesql @SQL;
    END
END
GO
