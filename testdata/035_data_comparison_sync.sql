-- Sample 035: Data Comparison and Synchronization
-- Source: Various - MSSQLTips, Redgate patterns, Stack Overflow
-- Category: ETL/Data Loading
-- Complexity: Advanced
-- Features: EXCEPT, INTERSECT, HASHBYTES for comparison, sync patterns

-- Compare two tables and find differences
CREATE PROCEDURE dbo.CompareTableData
    @SourceSchema NVARCHAR(128),
    @SourceTable NVARCHAR(128),
    @TargetSchema NVARCHAR(128),
    @TargetTable NVARCHAR(128),
    @KeyColumns NVARCHAR(MAX),  -- Comma-separated
    @CompareColumns NVARCHAR(MAX) = NULL,  -- NULL = all non-key columns
    @MaxDifferences INT = 1000
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @SourcePath NVARCHAR(256) = QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable);
    DECLARE @TargetPath NVARCHAR(256) = QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable);
    DECLARE @KeyList NVARCHAR(MAX) = '';
    DECLARE @CompareList NVARCHAR(MAX) = '';
    DECLARE @JoinCondition NVARCHAR(MAX) = '';
    
    -- Build key column list
    SELECT @KeyList = STRING_AGG(QUOTENAME(LTRIM(RTRIM(value))), ', ')
    FROM STRING_SPLIT(@KeyColumns, ',');
    
    -- Build join condition
    SELECT @JoinCondition = STRING_AGG(
        's.' + QUOTENAME(LTRIM(RTRIM(value))) + ' = t.' + QUOTENAME(LTRIM(RTRIM(value))), ' AND '
    )
    FROM STRING_SPLIT(@KeyColumns, ',');
    
    -- Get compare columns if not specified
    IF @CompareColumns IS NULL
    BEGIN
        SELECT @CompareColumns = STRING_AGG(c.name, ',')
        FROM sys.columns c
        WHERE c.object_id = OBJECT_ID(@SourcePath)
          AND c.name NOT IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@KeyColumns, ','));
    END
    
    -- Build compare column list
    SELECT @CompareList = STRING_AGG(QUOTENAME(LTRIM(RTRIM(value))), ', ')
    FROM STRING_SPLIT(@CompareColumns, ',');
    
    -- Records only in source
    PRINT 'Finding records only in source...';
    SET @SQL = N'
        SELECT TOP (@MaxDiff) ''Only in Source'' AS DifferenceType, ' + @KeyList + '
        FROM ' + @SourcePath + ' s
        WHERE NOT EXISTS (
            SELECT 1 FROM ' + @TargetPath + ' t
            WHERE ' + @JoinCondition + '
        )';
    
    EXEC sp_executesql @SQL, N'@MaxDiff INT', @MaxDiff = @MaxDifferences;
    
    -- Records only in target
    PRINT 'Finding records only in target...';
    SET @SQL = N'
        SELECT TOP (@MaxDiff) ''Only in Target'' AS DifferenceType, ' + @KeyList + '
        FROM ' + @TargetPath + ' t
        WHERE NOT EXISTS (
            SELECT 1 FROM ' + @SourcePath + ' s
            WHERE ' + @JoinCondition + '
        )';
    
    EXEC sp_executesql @SQL, N'@MaxDiff INT', @MaxDiff = @MaxDifferences;
    
    -- Records with different values
    PRINT 'Finding records with different values...';
    SET @SQL = N'
        SELECT TOP (@MaxDiff) 
            ''Different Values'' AS DifferenceType,
            ' + REPLACE(@KeyList, ', ', ', s.') + ',
            ''Source'' AS RecordSource, ' + REPLACE(@CompareList, ', ', ', s.') + '
        FROM ' + @SourcePath + ' s
        INNER JOIN ' + @TargetPath + ' t ON ' + @JoinCondition + '
        WHERE EXISTS (
            SELECT ' + REPLACE(@CompareList, QUOTENAME(''), 's.') + '
            EXCEPT
            SELECT ' + REPLACE(@CompareList, QUOTENAME(''), 't.') + '
        )
        UNION ALL
        SELECT TOP (@MaxDiff)
            ''Different Values'' AS DifferenceType,
            ' + REPLACE(@KeyList, ', ', ', t.') + ',
            ''Target'' AS RecordSource, ' + REPLACE(@CompareList, ', ', ', t.') + '
        FROM ' + @SourcePath + ' s
        INNER JOIN ' + @TargetPath + ' t ON ' + @JoinCondition + '
        WHERE EXISTS (
            SELECT ' + REPLACE(@CompareList, QUOTENAME(''), 's.') + '
            EXCEPT
            SELECT ' + REPLACE(@CompareList, QUOTENAME(''), 't.') + '
        )
        ORDER BY 2';
    
    EXEC sp_executesql @SQL, N'@MaxDiff INT', @MaxDiff = @MaxDifferences;
    
    -- Summary
    SET @SQL = N'
        SELECT 
            (SELECT COUNT(*) FROM ' + @SourcePath + ') AS SourceRowCount,
            (SELECT COUNT(*) FROM ' + @TargetPath + ') AS TargetRowCount,
            (SELECT COUNT(*) FROM ' + @SourcePath + ' s
             WHERE NOT EXISTS (SELECT 1 FROM ' + @TargetPath + ' t WHERE ' + @JoinCondition + ')
            ) AS OnlyInSource,
            (SELECT COUNT(*) FROM ' + @TargetPath + ' t
             WHERE NOT EXISTS (SELECT 1 FROM ' + @SourcePath + ' s WHERE ' + @JoinCondition + ')
            ) AS OnlyInTarget';
    
    EXEC sp_executesql @SQL;
END
GO

-- Generate sync script for two tables
CREATE PROCEDURE dbo.GenerateSyncScript
    @SourceSchema NVARCHAR(128),
    @SourceTable NVARCHAR(128),
    @TargetSchema NVARCHAR(128),
    @TargetTable NVARCHAR(128),
    @KeyColumns NVARCHAR(MAX),
    @SyncInserts BIT = 1,
    @SyncUpdates BIT = 1,
    @SyncDeletes BIT = 0,
    @ExecuteSync BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @MergeSQL NVARCHAR(MAX);
    DECLARE @SourcePath NVARCHAR(256) = QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable);
    DECLARE @TargetPath NVARCHAR(256) = QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable);
    DECLARE @AllColumns NVARCHAR(MAX);
    DECLARE @UpdateColumns NVARCHAR(MAX);
    DECLARE @JoinCondition NVARCHAR(MAX);
    DECLARE @InsertCount INT = 0;
    DECLARE @UpdateCount INT = 0;
    DECLARE @DeleteCount INT = 0;
    
    -- Get all columns
    SELECT @AllColumns = STRING_AGG(QUOTENAME(c.name), ', ')
    FROM sys.columns c
    WHERE c.object_id = OBJECT_ID(@SourcePath);
    
    -- Get update columns (non-key)
    SELECT @UpdateColumns = STRING_AGG(
        't.' + QUOTENAME(c.name) + ' = s.' + QUOTENAME(c.name), ', '
    )
    FROM sys.columns c
    WHERE c.object_id = OBJECT_ID(@SourcePath)
      AND c.name NOT IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@KeyColumns, ','));
    
    -- Build join condition
    SELECT @JoinCondition = STRING_AGG(
        't.' + QUOTENAME(LTRIM(RTRIM(value))) + ' = s.' + QUOTENAME(LTRIM(RTRIM(value))), ' AND '
    )
    FROM STRING_SPLIT(@KeyColumns, ',');
    
    -- Build MERGE statement
    SET @MergeSQL = '
MERGE ' + @TargetPath + ' AS t
USING ' + @SourcePath + ' AS s
ON ' + @JoinCondition;
    
    IF @SyncUpdates = 1
        SET @MergeSQL = @MergeSQL + '
WHEN MATCHED THEN
    UPDATE SET ' + @UpdateColumns;
    
    IF @SyncInserts = 1
        SET @MergeSQL = @MergeSQL + '
WHEN NOT MATCHED BY TARGET THEN
    INSERT (' + @AllColumns + ')
    VALUES (s.' + REPLACE(@AllColumns, ', ', ', s.') + ')';
    
    IF @SyncDeletes = 1
        SET @MergeSQL = @MergeSQL + '
WHEN NOT MATCHED BY SOURCE THEN
    DELETE';
    
    SET @MergeSQL = @MergeSQL + '
OUTPUT $action AS Action, 
       INSERTED.*, 
       DELETED.*
;';
    
    IF @ExecuteSync = 0
    BEGIN
        -- Just return the script
        SELECT @MergeSQL AS SyncScript;
    END
    ELSE
    BEGIN
        -- Execute the sync
        CREATE TABLE #SyncResults (
            Action NVARCHAR(10),
            InsertedData NVARCHAR(MAX),
            DeletedData NVARCHAR(MAX)
        );
        
        BEGIN TRY
            EXEC sp_executesql @MergeSQL;
            
            SELECT 
                'Sync completed' AS Status,
                @@ROWCOUNT AS TotalRowsAffected;
        END TRY
        BEGIN CATCH
            SELECT 
                'Sync failed' AS Status,
                ERROR_MESSAGE() AS ErrorMessage;
            THROW;
        END CATCH
        
        DROP TABLE #SyncResults;
    END
END
GO

-- Create checksum for table data
CREATE PROCEDURE dbo.GetTableChecksum
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @Columns NVARCHAR(MAX) = NULL,  -- NULL = all columns
    @GroupByColumn NVARCHAR(128) = NULL  -- For partitioned checksums
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @ColumnList NVARCHAR(MAX);
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    
    -- Get columns
    IF @Columns IS NULL
    BEGIN
        SELECT @ColumnList = STRING_AGG(
            'ISNULL(CAST(' + QUOTENAME(c.name) + ' AS NVARCHAR(MAX)), '''')', ' + ''|'' + '
        )
        FROM sys.columns c
        WHERE c.object_id = OBJECT_ID(@FullPath)
        ORDER BY c.column_id;
    END
    ELSE
    BEGIN
        SELECT @ColumnList = STRING_AGG(
            'ISNULL(CAST(' + QUOTENAME(LTRIM(RTRIM(value))) + ' AS NVARCHAR(MAX)), '''')', ' + ''|'' + '
        )
        FROM STRING_SPLIT(@Columns, ',');
    END
    
    IF @GroupByColumn IS NULL
    BEGIN
        -- Single checksum for entire table
        SET @SQL = N'
            SELECT 
                ''' + @FullPath + ''' AS TableName,
                COUNT(*) AS RowCount,
                CHECKSUM_AGG(CHECKSUM(' + @ColumnList + ')) AS TableChecksum,
                HASHBYTES(''SHA2_256'', 
                    (SELECT ' + @ColumnList + ' AS [data()] 
                     FROM ' + @FullPath + ' 
                     ORDER BY (SELECT NULL) 
                     FOR XML PATH(''''))
                ) AS TableHash';
        
        EXEC sp_executesql @SQL;
    END
    ELSE
    BEGIN
        -- Checksum by partition
        SET @SQL = N'
            SELECT 
                ' + QUOTENAME(@GroupByColumn) + ' AS PartitionValue,
                COUNT(*) AS RowCount,
                CHECKSUM_AGG(CHECKSUM(' + @ColumnList + ')) AS PartitionChecksum
            FROM ' + @FullPath + '
            GROUP BY ' + QUOTENAME(@GroupByColumn) + '
            ORDER BY ' + QUOTENAME(@GroupByColumn);
        
        EXEC sp_executesql @SQL;
    END
END
GO

-- Detect and log data drift
CREATE PROCEDURE dbo.DetectDataDrift
    @SourceSchema NVARCHAR(128),
    @SourceTable NVARCHAR(128),
    @TargetSchema NVARCHAR(128),
    @TargetTable NVARCHAR(128),
    @ComparisonName NVARCHAR(128) = NULL,
    @AlertThreshold INT = 100  -- Alert if more than N differences
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SourcePath NVARCHAR(256) = QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable);
    DECLARE @TargetPath NVARCHAR(256) = QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable);
    DECLARE @SourceCount INT;
    DECLARE @TargetCount INT;
    DECLARE @SourceChecksum INT;
    DECLARE @TargetChecksum INT;
    DECLARE @SQL NVARCHAR(MAX);
    
    SET @ComparisonName = ISNULL(@ComparisonName, @SourceTable + '_to_' + @TargetTable);
    
    -- Get counts and checksums
    SET @SQL = 'SELECT @cnt = COUNT(*), @chk = CHECKSUM_AGG(BINARY_CHECKSUM(*)) FROM ' + @SourcePath;
    EXEC sp_executesql @SQL, N'@cnt INT OUTPUT, @chk INT OUTPUT', 
        @cnt = @SourceCount OUTPUT, @chk = @SourceChecksum OUTPUT;
    
    SET @SQL = 'SELECT @cnt = COUNT(*), @chk = CHECKSUM_AGG(BINARY_CHECKSUM(*)) FROM ' + @TargetPath;
    EXEC sp_executesql @SQL, N'@cnt INT OUTPUT, @chk INT OUTPUT',
        @cnt = @TargetCount OUTPUT, @chk = @TargetChecksum OUTPUT;
    
    -- Create log table if not exists
    IF OBJECT_ID('dbo.DataDriftLog', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.DataDriftLog (
            LogID INT IDENTITY(1,1) PRIMARY KEY,
            ComparisonName NVARCHAR(128),
            SourceTable NVARCHAR(256),
            TargetTable NVARCHAR(256),
            SourceRowCount INT,
            TargetRowCount INT,
            RowCountDifference INT,
            ChecksumMatch BIT,
            CheckDate DATETIME DEFAULT GETDATE(),
            DriftDetected BIT,
            AlertTriggered BIT
        );
    END
    
    -- Log result
    INSERT INTO dbo.DataDriftLog (
        ComparisonName, SourceTable, TargetTable,
        SourceRowCount, TargetRowCount, RowCountDifference,
        ChecksumMatch, DriftDetected, AlertTriggered
    )
    VALUES (
        @ComparisonName, @SourcePath, @TargetPath,
        @SourceCount, @TargetCount, ABS(@SourceCount - @TargetCount),
        CASE WHEN @SourceChecksum = @TargetChecksum THEN 1 ELSE 0 END,
        CASE WHEN @SourceChecksum <> @TargetChecksum OR @SourceCount <> @TargetCount THEN 1 ELSE 0 END,
        CASE WHEN ABS(@SourceCount - @TargetCount) > @AlertThreshold THEN 1 ELSE 0 END
    );
    
    -- Return current status
    SELECT 
        @ComparisonName AS ComparisonName,
        @SourcePath AS SourceTable,
        @TargetPath AS TargetTable,
        @SourceCount AS SourceRowCount,
        @TargetCount AS TargetRowCount,
        ABS(@SourceCount - @TargetCount) AS RowCountDifference,
        CASE WHEN @SourceChecksum = @TargetChecksum THEN 'MATCH' ELSE 'MISMATCH' END AS ChecksumStatus,
        CASE 
            WHEN @SourceChecksum = @TargetChecksum AND @SourceCount = @TargetCount THEN 'IN SYNC'
            ELSE 'DRIFT DETECTED'
        END AS OverallStatus;
END
GO
