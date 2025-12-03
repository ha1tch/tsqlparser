-- Sample 093: Batch Processing Patterns
-- Source: Various - Itzik Ben-Gan, MSSQLTips, Performance patterns
-- Category: ETL/Data Loading
-- Complexity: Complex
-- Features: Batch updates, throttled processing, progress tracking, resumable operations

-- Batch delete with progress tracking
CREATE PROCEDURE dbo.BatchDeleteWithProgress
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @WhereClause NVARCHAR(MAX),
    @BatchSize INT = 10000,
    @MaxBatches INT = NULL,  -- NULL = unlimited
    @DelayBetweenBatches VARCHAR(12) = '00:00:00.500'
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @RowsDeleted INT = 1;
    DECLARE @TotalDeleted INT = 0;
    DECLARE @BatchCount INT = 0;
    DECLARE @StartTime DATETIME2 = SYSDATETIME();
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    
    -- Progress tracking table
    CREATE TABLE #Progress (
        BatchNumber INT,
        RowsDeleted INT,
        BatchTime DATETIME2,
        TotalDeleted INT,
        ElapsedSeconds INT
    );
    
    SET @SQL = N'DELETE TOP (@Size) FROM ' + @FullPath + ' WHERE ' + @WhereClause;
    
    WHILE @RowsDeleted > 0 AND (@MaxBatches IS NULL OR @BatchCount < @MaxBatches)
    BEGIN
        EXEC sp_executesql @SQL, N'@Size INT', @Size = @BatchSize;
        SET @RowsDeleted = @@ROWCOUNT;
        SET @TotalDeleted = @TotalDeleted + @RowsDeleted;
        SET @BatchCount = @BatchCount + 1;
        
        INSERT INTO #Progress VALUES (
            @BatchCount, @RowsDeleted, SYSDATETIME(), @TotalDeleted,
            DATEDIFF(SECOND, @StartTime, SYSDATETIME())
        );
        
        -- Print progress
        RAISERROR('Batch %d: Deleted %d rows (Total: %d)', 0, 1, @BatchCount, @RowsDeleted, @TotalDeleted) WITH NOWAIT;
        
        IF @RowsDeleted > 0
            WAITFOR DELAY @DelayBetweenBatches;
    END
    
    -- Return progress summary
    SELECT * FROM #Progress ORDER BY BatchNumber;
    
    SELECT 
        @TotalDeleted AS TotalRowsDeleted,
        @BatchCount AS TotalBatches,
        DATEDIFF(SECOND, @StartTime, SYSDATETIME()) AS TotalSeconds,
        @TotalDeleted / NULLIF(DATEDIFF(SECOND, @StartTime, SYSDATETIME()), 0) AS RowsPerSecond;
    
    DROP TABLE #Progress;
END
GO

-- Resumable batch update
CREATE PROCEDURE dbo.ResumableBatchUpdate
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @PKColumn NVARCHAR(128),
    @SetClause NVARCHAR(MAX),
    @WhereClause NVARCHAR(MAX) = NULL,
    @BatchSize INT = 5000,
    @JobName NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Create checkpoint table if not exists
    IF OBJECT_ID('dbo.BatchUpdateCheckpoints', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.BatchUpdateCheckpoints (
            JobName NVARCHAR(100) PRIMARY KEY,
            TableName NVARCHAR(256),
            LastProcessedKey SQL_VARIANT,
            RowsProcessed BIGINT,
            LastUpdated DATETIME2,
            Status NVARCHAR(20)
        );
    END
    
    SET @JobName = ISNULL(@JobName, @SchemaName + '.' + @TableName + '_Update');
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    DECLARE @LastKey SQL_VARIANT;
    DECLARE @RowsUpdated INT = 1;
    DECLARE @TotalUpdated BIGINT = 0;
    
    -- Check for existing checkpoint
    SELECT @LastKey = LastProcessedKey, @TotalUpdated = RowsProcessed
    FROM dbo.BatchUpdateCheckpoints
    WHERE JobName = @JobName AND Status = 'InProgress';
    
    IF @LastKey IS NULL
    BEGIN
        -- Start new job
        INSERT INTO dbo.BatchUpdateCheckpoints (JobName, TableName, RowsProcessed, LastUpdated, Status)
        VALUES (@JobName, @FullPath, 0, SYSDATETIME(), 'InProgress');
        SET @TotalUpdated = 0;
    END
    
    -- Build update query
    SET @SQL = N'
        UPDATE TOP (@Size) t
        SET ' + @SetClause + '
        OUTPUT inserted.' + QUOTENAME(@PKColumn) + ' INTO #UpdatedKeys
        FROM ' + @FullPath + ' t
        WHERE ' + QUOTENAME(@PKColumn) + ' > ISNULL(@LastKey, (SELECT MIN(' + QUOTENAME(@PKColumn) + ') - 1 FROM ' + @FullPath + '))' +
        CASE WHEN @WhereClause IS NOT NULL THEN ' AND ' + @WhereClause ELSE '' END + '
        ORDER BY ' + QUOTENAME(@PKColumn);
    
    CREATE TABLE #UpdatedKeys (KeyValue SQL_VARIANT);
    
    WHILE @RowsUpdated > 0
    BEGIN
        TRUNCATE TABLE #UpdatedKeys;
        
        EXEC sp_executesql @SQL, N'@Size INT, @LastKey SQL_VARIANT', @Size = @BatchSize, @LastKey = @LastKey;
        SET @RowsUpdated = @@ROWCOUNT;
        
        IF @RowsUpdated > 0
        BEGIN
            SELECT @LastKey = MAX(KeyValue) FROM #UpdatedKeys;
            SET @TotalUpdated = @TotalUpdated + @RowsUpdated;
            
            -- Update checkpoint
            UPDATE dbo.BatchUpdateCheckpoints
            SET LastProcessedKey = @LastKey, RowsProcessed = @TotalUpdated, LastUpdated = SYSDATETIME()
            WHERE JobName = @JobName;
            
            RAISERROR('Updated %d rows (Total: %I64d)', 0, 1, @RowsUpdated, @TotalUpdated) WITH NOWAIT;
        END
    END
    
    -- Mark complete
    UPDATE dbo.BatchUpdateCheckpoints
    SET Status = 'Completed', LastUpdated = SYSDATETIME()
    WHERE JobName = @JobName;
    
    DROP TABLE #UpdatedKeys;
    
    SELECT @TotalUpdated AS TotalRowsUpdated, 'Completed' AS Status;
END
GO

-- Parallel batch processor using multiple sessions
CREATE PROCEDURE dbo.GetBatchRanges
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @PKColumn NVARCHAR(128),
    @NumberOfBatches INT = 10
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    
    -- Get min/max keys and row count
    SET @SQL = N'
        SELECT 
            MIN(' + QUOTENAME(@PKColumn) + ') AS MinKey,
            MAX(' + QUOTENAME(@PKColumn) + ') AS MaxKey,
            COUNT(*) AS TotalRows
        FROM ' + @FullPath;
    
    CREATE TABLE #Stats (MinKey BIGINT, MaxKey BIGINT, TotalRows BIGINT);
    INSERT INTO #Stats EXEC sp_executesql @SQL;
    
    DECLARE @MinKey BIGINT, @MaxKey BIGINT, @TotalRows BIGINT;
    SELECT @MinKey = MinKey, @MaxKey = MaxKey, @TotalRows = TotalRows FROM #Stats;
    
    -- Generate batch ranges using NTILE
    SET @SQL = N'
        ;WITH RankedRows AS (
            SELECT 
                ' + QUOTENAME(@PKColumn) + ',
                NTILE(@Batches) OVER (ORDER BY ' + QUOTENAME(@PKColumn) + ') AS BatchNum
            FROM ' + @FullPath + '
        )
        SELECT 
            BatchNum,
            MIN(' + QUOTENAME(@PKColumn) + ') AS StartKey,
            MAX(' + QUOTENAME(@PKColumn) + ') AS EndKey,
            COUNT(*) AS RowCount
        FROM RankedRows
        GROUP BY BatchNum
        ORDER BY BatchNum';
    
    EXEC sp_executesql @SQL, N'@Batches INT', @Batches = @NumberOfBatches;
    
    DROP TABLE #Stats;
END
GO

-- Throttled insert with rate limiting
CREATE PROCEDURE dbo.ThrottledInsert
    @SourceQuery NVARCHAR(MAX),
    @TargetSchema NVARCHAR(128) = 'dbo',
    @TargetTable NVARCHAR(128),
    @BatchSize INT = 1000,
    @MaxRowsPerSecond INT = 5000,
    @MaxTotalRows INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FullTarget NVARCHAR(256) = QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable);
    DECLARE @RowsInserted INT = 1;
    DECLARE @TotalInserted INT = 0;
    DECLARE @BatchStart DATETIME2;
    DECLARE @BatchDurationMs INT;
    DECLARE @RequiredDelayMs INT;
    
    -- Create temp table to stage data
    SET @SQL = N'SELECT TOP 0 * INTO #SourceData FROM (' + @SourceQuery + ') AS src';
    EXEC sp_executesql @SQL;
    
    SET @SQL = N'INSERT INTO #SourceData SELECT * FROM (' + @SourceQuery + ') AS src';
    EXEC sp_executesql @SQL;
    
    -- Add row number for batching
    SET @SQL = N'ALTER TABLE #SourceData ADD _RowNum INT IDENTITY(1,1)';
    EXEC sp_executesql @SQL;
    
    DECLARE @MaxRow INT;
    EXEC sp_executesql N'SELECT @Max = MAX(_RowNum) FROM #SourceData', N'@Max INT OUTPUT', @Max = @MaxRow OUTPUT;
    
    DECLARE @CurrentRow INT = 0;
    
    WHILE @CurrentRow < @MaxRow AND (@MaxTotalRows IS NULL OR @TotalInserted < @MaxTotalRows)
    BEGIN
        SET @BatchStart = SYSDATETIME();
        
        -- Insert batch
        SET @SQL = N'
            INSERT INTO ' + @FullTarget + '
            SELECT * FROM #SourceData 
            WHERE _RowNum > @Start AND _RowNum <= @Start + @Size';
        
        EXEC sp_executesql @SQL, N'@Start INT, @Size INT', @Start = @CurrentRow, @Size = @BatchSize;
        SET @RowsInserted = @@ROWCOUNT;
        SET @TotalInserted = @TotalInserted + @RowsInserted;
        SET @CurrentRow = @CurrentRow + @BatchSize;
        
        -- Calculate delay for rate limiting
        SET @BatchDurationMs = DATEDIFF(MILLISECOND, @BatchStart, SYSDATETIME());
        SET @RequiredDelayMs = (@RowsInserted * 1000 / @MaxRowsPerSecond) - @BatchDurationMs;
        
        IF @RequiredDelayMs > 0
        BEGIN
            DECLARE @Delay VARCHAR(12) = '00:00:00.' + RIGHT('000' + CAST(@RequiredDelayMs AS VARCHAR(3)), 3);
            WAITFOR DELAY @Delay;
        END
        
        RAISERROR('Inserted %d rows (Total: %d)', 0, 1, @RowsInserted, @TotalInserted) WITH NOWAIT;
    END
    
    SELECT @TotalInserted AS TotalRowsInserted;
END
GO

-- Batch upsert with conflict handling
CREATE PROCEDURE dbo.BatchUpsert
    @SourceQuery NVARCHAR(MAX),
    @TargetSchema NVARCHAR(128) = 'dbo',
    @TargetTable NVARCHAR(128),
    @KeyColumns NVARCHAR(MAX),
    @BatchSize INT = 5000
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FullTarget NVARCHAR(256) = QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable);
    DECLARE @MergeJoin NVARCHAR(MAX);
    DECLARE @UpdateSet NVARCHAR(MAX);
    DECLARE @Columns NVARCHAR(MAX);
    DECLARE @TotalInserted INT = 0;
    DECLARE @TotalUpdated INT = 0;
    
    -- Build join condition
    SELECT @MergeJoin = STRING_AGG('target.' + QUOTENAME(LTRIM(RTRIM(value))) + ' = source.' + QUOTENAME(LTRIM(RTRIM(value))), ' AND ')
    FROM STRING_SPLIT(@KeyColumns, ',');
    
    -- Get columns
    SELECT @Columns = STRING_AGG(QUOTENAME(name), ', ')
    FROM sys.columns WHERE object_id = OBJECT_ID(@FullTarget);
    
    -- Build update set (exclude key columns)
    SELECT @UpdateSet = STRING_AGG('target.' + QUOTENAME(name) + ' = source.' + QUOTENAME(name), ', ')
    FROM sys.columns 
    WHERE object_id = OBJECT_ID(@FullTarget)
      AND name NOT IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@KeyColumns, ','));
    
    -- Execute merge
    SET @SQL = N'
        MERGE ' + @FullTarget + ' AS target
        USING (' + @SourceQuery + ') AS source
        ON ' + @MergeJoin + '
        WHEN MATCHED THEN UPDATE SET ' + @UpdateSet + '
        WHEN NOT MATCHED THEN INSERT (' + @Columns + ') VALUES (' + @Columns + ')
        OUTPUT $action INTO #MergeResults;
        
        SELECT 
            @Ins = SUM(CASE WHEN MergeAction = ''INSERT'' THEN 1 ELSE 0 END),
            @Upd = SUM(CASE WHEN MergeAction = ''UPDATE'' THEN 1 ELSE 0 END)
        FROM #MergeResults';
    
    CREATE TABLE #MergeResults (MergeAction NVARCHAR(10));
    
    EXEC sp_executesql @SQL, 
        N'@Ins INT OUTPUT, @Upd INT OUTPUT', 
        @Ins = @TotalInserted OUTPUT, @Upd = @TotalUpdated OUTPUT;
    
    DROP TABLE #MergeResults;
    
    SELECT @TotalInserted AS RowsInserted, @TotalUpdated AS RowsUpdated;
END
GO
