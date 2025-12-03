-- Sample 049: Bulk Copy and Data Import
-- Source: Microsoft Learn, MSSQLTips, Various ETL patterns
-- Category: ETL/Data Loading
-- Complexity: Advanced
-- Features: BULK INSERT, OPENROWSET, format files, error handling

-- Bulk import from CSV file
CREATE PROCEDURE dbo.BulkImportCSV
    @FilePath NVARCHAR(500),
    @TargetSchema NVARCHAR(128) = 'dbo',
    @TargetTable NVARCHAR(128),
    @FieldTerminator NVARCHAR(10) = ',',
    @RowTerminator NVARCHAR(10) = '\n',
    @FirstRow INT = 2,  -- Skip header
    @MaxErrors INT = 10,
    @BatchSize INT = 10000,
    @TruncateFirst BIT = 0,
    @UseTransaction BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable);
    DECLARE @RowsImported INT;
    DECLARE @StartTime DATETIME = GETDATE();
    
    BEGIN TRY
        IF @UseTransaction = 1
            BEGIN TRANSACTION;
        
        -- Truncate if requested
        IF @TruncateFirst = 1
        BEGIN
            SET @SQL = 'TRUNCATE TABLE ' + @FullPath;
            EXEC sp_executesql @SQL;
        END
        
        -- Bulk insert
        SET @SQL = N'
            BULK INSERT ' + @FullPath + '
            FROM ''' + @FilePath + '''
            WITH (
                FIELDTERMINATOR = ''' + @FieldTerminator + ''',
                ROWTERMINATOR = ''' + @RowTerminator + ''',
                FIRSTROW = ' + CAST(@FirstRow AS NVARCHAR(10)) + ',
                MAXERRORS = ' + CAST(@MaxErrors AS NVARCHAR(10)) + ',
                BATCHSIZE = ' + CAST(@BatchSize AS NVARCHAR(10)) + ',
                TABLOCK,
                ERRORFILE = ''' + @FilePath + '.errors''
            )';
        
        EXEC sp_executesql @SQL;
        SET @RowsImported = @@ROWCOUNT;
        
        IF @UseTransaction = 1
            COMMIT TRANSACTION;
        
        SELECT 
            'Import completed' AS Status,
            @RowsImported AS RowsImported,
            DATEDIFF(SECOND, @StartTime, GETDATE()) AS DurationSeconds,
            @FilePath AS SourceFile,
            @FullPath AS TargetTable;
            
    END TRY
    BEGIN CATCH
        IF @UseTransaction = 1 AND @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        SELECT 
            'Import failed' AS Status,
            ERROR_MESSAGE() AS ErrorMessage,
            ERROR_LINE() AS ErrorLine;
        
        THROW;
    END CATCH
END
GO

-- Import with staging table and validation
CREATE PROCEDURE dbo.BulkImportWithStaging
    @FilePath NVARCHAR(500),
    @TargetSchema NVARCHAR(128) = 'dbo',
    @TargetTable NVARCHAR(128),
    @StagingTable NVARCHAR(128) = NULL,
    @KeyColumns NVARCHAR(MAX),  -- For duplicate detection
    @ValidationRules NVARCHAR(MAX) = NULL,  -- JSON rules
    @MergeMode BIT = 0  -- 0 = Insert only, 1 = Merge
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable);
    DECLARE @StagingPath NVARCHAR(256);
    
    SET @StagingTable = ISNULL(@StagingTable, @TargetTable + '_Staging');
    SET @StagingPath = QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@StagingTable);
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        -- Create staging table (copy structure from target)
        SET @SQL = 'DROP TABLE IF EXISTS ' + @StagingPath;
        EXEC sp_executesql @SQL;
        
        SET @SQL = 'SELECT * INTO ' + @StagingPath + ' FROM ' + @FullPath + ' WHERE 1 = 0';
        EXEC sp_executesql @SQL;
        
        -- Bulk insert into staging
        SET @SQL = N'
            BULK INSERT ' + @StagingPath + '
            FROM ''' + @FilePath + '''
            WITH (
                FIELDTERMINATOR = '','',
                ROWTERMINATOR = ''\n'',
                FIRSTROW = 2,
                TABLOCK
            )';
        EXEC sp_executesql @SQL;
        
        DECLARE @StagingCount INT;
        SET @SQL = 'SELECT @cnt = COUNT(*) FROM ' + @StagingPath;
        EXEC sp_executesql @SQL, N'@cnt INT OUTPUT', @cnt = @StagingCount OUTPUT;
        
        -- Validation (if rules provided)
        IF @ValidationRules IS NOT NULL
        BEGIN
            -- Create validation errors table
            CREATE TABLE #ValidationErrors (
                RowNumber INT,
                ColumnName NVARCHAR(128),
                ErrorType NVARCHAR(50),
                ErrorMessage NVARCHAR(500)
            );
            
            -- Check for duplicates in staging
            DECLARE @KeyList NVARCHAR(MAX);
            SELECT @KeyList = STRING_AGG(QUOTENAME(LTRIM(RTRIM(value))), ', ')
            FROM STRING_SPLIT(@KeyColumns, ',');
            
            SET @SQL = N'
                INSERT INTO #ValidationErrors (RowNumber, ColumnName, ErrorType, ErrorMessage)
                SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)), ''' + @KeyColumns + ''', ''Duplicate'', ''Duplicate key in import file''
                FROM ' + @StagingPath + '
                GROUP BY ' + @KeyList + '
                HAVING COUNT(*) > 1';
            EXEC sp_executesql @SQL;
            
            -- Return errors if any
            IF EXISTS (SELECT 1 FROM #ValidationErrors)
            BEGIN
                SELECT * FROM #ValidationErrors;
                RAISERROR('Validation errors found. Import aborted.', 16, 1);
                RETURN;
            END
        END
        
        -- Load to target
        IF @MergeMode = 1
        BEGIN
            -- Build MERGE statement
            DECLARE @AllColumns NVARCHAR(MAX);
            DECLARE @UpdateColumns NVARCHAR(MAX);
            DECLARE @JoinCondition NVARCHAR(MAX);
            
            SELECT @AllColumns = STRING_AGG(QUOTENAME(c.name), ', ')
            FROM sys.columns c
            WHERE c.object_id = OBJECT_ID(@FullPath);
            
            SELECT @JoinCondition = STRING_AGG(
                't.' + QUOTENAME(LTRIM(RTRIM(value))) + ' = s.' + QUOTENAME(LTRIM(RTRIM(value))), ' AND '
            )
            FROM STRING_SPLIT(@KeyColumns, ',');
            
            SELECT @UpdateColumns = STRING_AGG(
                't.' + QUOTENAME(c.name) + ' = s.' + QUOTENAME(c.name), ', '
            )
            FROM sys.columns c
            WHERE c.object_id = OBJECT_ID(@FullPath)
              AND c.name NOT IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@KeyColumns, ','));
            
            SET @SQL = N'
                MERGE ' + @FullPath + ' AS t
                USING ' + @StagingPath + ' AS s
                ON ' + @JoinCondition + '
                WHEN MATCHED THEN
                    UPDATE SET ' + @UpdateColumns + '
                WHEN NOT MATCHED THEN
                    INSERT (' + @AllColumns + ')
                    VALUES (s.' + REPLACE(@AllColumns, ', ', ', s.') + ');';
            
            EXEC sp_executesql @SQL;
        END
        ELSE
        BEGIN
            -- Simple insert
            SET @SQL = 'INSERT INTO ' + @FullPath + ' SELECT * FROM ' + @StagingPath;
            EXEC sp_executesql @SQL;
        END
        
        DECLARE @LoadedCount INT = @@ROWCOUNT;
        
        -- Cleanup staging
        SET @SQL = 'DROP TABLE ' + @StagingPath;
        EXEC sp_executesql @SQL;
        
        COMMIT TRANSACTION;
        
        SELECT 
            'Import completed' AS Status,
            @StagingCount AS RowsInFile,
            @LoadedCount AS RowsLoaded,
            @MergeMode AS MergeMode;
            
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        -- Cleanup staging on error
        SET @SQL = 'DROP TABLE IF EXISTS ' + @StagingPath;
        EXEC sp_executesql @SQL;
        
        THROW;
    END CATCH
END
GO

-- Generate format file for BULK INSERT
CREATE PROCEDURE dbo.GenerateFormatFile
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @Delimiter NVARCHAR(10) = ',',
    @OutputPath NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @XML NVARCHAR(MAX) = '<?xml version="1.0"?>
<BCPFORMAT xmlns="http://schemas.microsoft.com/sqlserver/2004/bulkload/format" 
           xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <RECORD>';
    
    DECLARE @ColumnCount INT;
    
    SELECT @ColumnCount = MAX(column_id)
    FROM sys.columns
    WHERE object_id = OBJECT_ID(@SchemaName + '.' + @TableName);
    
    -- Build FIELD elements
    SELECT @XML = @XML + '
    <FIELD ID="' + CAST(c.column_id AS VARCHAR(10)) + '" 
           xsi:type="CharTerm" 
           TERMINATOR="' + CASE WHEN c.column_id = @ColumnCount THEN '\r\n' ELSE @Delimiter END + '" 
           MAX_LENGTH="' + CAST(
               CASE 
                   WHEN t.name IN ('varchar', 'nvarchar', 'char', 'nchar') 
                   THEN CASE WHEN c.max_length = -1 THEN 8000 ELSE c.max_length END
                   ELSE 100
               END AS VARCHAR(10)) + '"/>'
    FROM sys.columns c
    INNER JOIN sys.types t ON c.user_type_id = t.user_type_id
    WHERE c.object_id = OBJECT_ID(@SchemaName + '.' + @TableName)
    ORDER BY c.column_id;
    
    SET @XML = @XML + '
  </RECORD>
  <ROW>';
    
    -- Build COLUMN elements
    SELECT @XML = @XML + '
    <COLUMN SOURCE="' + CAST(c.column_id AS VARCHAR(10)) + '" 
            NAME="' + c.name + '" 
            xsi:type="' + 
            CASE t.name
                WHEN 'int' THEN 'SQLINT'
                WHEN 'bigint' THEN 'SQLBIGINT'
                WHEN 'smallint' THEN 'SQLSMALLINT'
                WHEN 'tinyint' THEN 'SQLTINYINT'
                WHEN 'bit' THEN 'SQLBIT'
                WHEN 'decimal' THEN 'SQLDECIMAL'
                WHEN 'numeric' THEN 'SQLNUMERIC'
                WHEN 'money' THEN 'SQLMONEY'
                WHEN 'float' THEN 'SQLFLT8'
                WHEN 'real' THEN 'SQLFLT4'
                WHEN 'datetime' THEN 'SQLDATETIME'
                WHEN 'date' THEN 'SQLDATE'
                WHEN 'nvarchar' THEN 'SQLNVARCHAR'
                WHEN 'varchar' THEN 'SQLVARCHAR'
                WHEN 'nchar' THEN 'SQLNCHAR'
                WHEN 'char' THEN 'SQLCHAR'
                WHEN 'uniqueidentifier' THEN 'SQLUNIQUEID'
                ELSE 'SQLVARCHAR'
            END + '"/>'
    FROM sys.columns c
    INNER JOIN sys.types t ON c.user_type_id = t.user_type_id
    WHERE c.object_id = OBJECT_ID(@SchemaName + '.' + @TableName)
    ORDER BY c.column_id;
    
    SET @XML = @XML + '
  </ROW>
</BCPFORMAT>';
    
    SELECT @XML AS FormatFileContent;
    
    -- If output path specified, instructions for saving
    IF @OutputPath IS NOT NULL
        SELECT 'Save the above XML to: ' + @OutputPath AS Instructions;
END
GO

-- Import Excel file using OPENROWSET
CREATE PROCEDURE dbo.ImportExcelFile
    @FilePath NVARCHAR(500),
    @SheetName NVARCHAR(128) = 'Sheet1$',
    @TargetSchema NVARCHAR(128) = 'dbo',
    @TargetTable NVARCHAR(128),
    @TruncateFirst BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable);
    
    BEGIN TRY
        IF @TruncateFirst = 1
        BEGIN
            SET @SQL = 'TRUNCATE TABLE ' + @FullPath;
            EXEC sp_executesql @SQL;
        END
        
        SET @SQL = N'
            INSERT INTO ' + @FullPath + '
            SELECT * FROM OPENROWSET(
                ''Microsoft.ACE.OLEDB.12.0'',
                ''Excel 12.0 Xml;Database=' + @FilePath + ';HDR=YES;IMEX=1'',
                ''SELECT * FROM [' + @SheetName + ']''
            )';
        
        EXEC sp_executesql @SQL;
        
        SELECT 
            'Excel import completed' AS Status,
            @@ROWCOUNT AS RowsImported,
            @FilePath AS SourceFile;
            
    END TRY
    BEGIN CATCH
        SELECT 
            'Import failed' AS Status,
            ERROR_MESSAGE() AS ErrorMessage;
        THROW;
    END CATCH
END
GO
