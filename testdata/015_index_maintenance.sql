-- Sample 015: Index Maintenance Procedures
-- Source: Ola Hallengren (ola.hallengren.com), MSSQLTips, Brent Ozar
-- Category: Performance
-- Complexity: Advanced
-- Features: DMVs, Dynamic SQL, sys.dm_db_index_physical_stats, REORGANIZE, REBUILD

-- Analyze index fragmentation
CREATE PROCEDURE dbo.AnalyzeIndexFragmentation
    @DatabaseName NVARCHAR(128) = NULL,
    @SchemaName NVARCHAR(128) = NULL,
    @TableName NVARCHAR(128) = NULL,
    @MinPageCount INT = 1000,
    @MinFragmentation FLOAT = 5.0
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        DB_NAME(ps.database_id) AS DatabaseName,
        OBJECT_SCHEMA_NAME(ps.object_id, ps.database_id) AS SchemaName,
        OBJECT_NAME(ps.object_id, ps.database_id) AS TableName,
        i.name AS IndexName,
        i.type_desc AS IndexType,
        ps.index_id,
        ps.partition_number,
        ps.avg_fragmentation_in_percent,
        ps.fragment_count,
        ps.avg_fragment_size_in_pages,
        ps.page_count,
        ps.record_count,
        ps.compressed_page_count,
        CASE 
            WHEN ps.avg_fragmentation_in_percent < 10 THEN 'None'
            WHEN ps.avg_fragmentation_in_percent < 30 THEN 'Reorganize'
            ELSE 'Rebuild'
        END AS RecommendedAction,
        'ALTER INDEX ' + QUOTENAME(i.name) + ' ON ' + 
            QUOTENAME(OBJECT_SCHEMA_NAME(ps.object_id, ps.database_id)) + '.' +
            QUOTENAME(OBJECT_NAME(ps.object_id, ps.database_id)) +
            CASE 
                WHEN ps.avg_fragmentation_in_percent < 30 THEN ' REORGANIZE'
                ELSE ' REBUILD WITH (ONLINE = ON)'
            END AS MaintenanceScript
    FROM sys.dm_db_index_physical_stats(
        DB_ID(@DatabaseName), 
        OBJECT_ID(@SchemaName + '.' + @TableName), 
        NULL, NULL, 'LIMITED'
    ) ps
    INNER JOIN sys.indexes i 
        ON ps.object_id = i.object_id 
        AND ps.index_id = i.index_id
    WHERE ps.index_id > 0  -- Exclude heaps
      AND ps.page_count >= @MinPageCount
      AND ps.avg_fragmentation_in_percent >= @MinFragmentation
      AND ps.alloc_unit_type_desc = 'IN_ROW_DATA'
    ORDER BY ps.avg_fragmentation_in_percent DESC;
END
GO

-- Perform intelligent index maintenance
CREATE PROCEDURE dbo.MaintainIndexes
    @DatabaseName NVARCHAR(128) = NULL,
    @ReorganizeThreshold FLOAT = 10.0,
    @RebuildThreshold FLOAT = 30.0,
    @MinPageCount INT = 1000,
    @OnlineRebuild BIT = 1,
    @MaxDOP INT = 0,
    @LogToTable BIT = 1,
    @ExecuteCommands BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @IndexName NVARCHAR(128);
    DECLARE @SchemaName NVARCHAR(128);
    DECLARE @TableName NVARCHAR(128);
    DECLARE @Fragmentation FLOAT;
    DECLARE @PageCount INT;
    DECLARE @Action NVARCHAR(20);
    DECLARE @StartTime DATETIME;
    DECLARE @EndTime DATETIME;
    DECLARE @ErrorMessage NVARCHAR(4000);
    
    -- Create log table if needed
    IF @LogToTable = 1 AND OBJECT_ID('dbo.IndexMaintenanceLog', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.IndexMaintenanceLog (
            LogID INT IDENTITY(1,1) PRIMARY KEY,
            DatabaseName NVARCHAR(128),
            SchemaName NVARCHAR(128),
            TableName NVARCHAR(128),
            IndexName NVARCHAR(128),
            Action NVARCHAR(20),
            FragmentationBefore FLOAT,
            PageCount INT,
            StartTime DATETIME,
            EndTime DATETIME,
            DurationSeconds INT,
            Status NVARCHAR(20),
            ErrorMessage NVARCHAR(4000)
        );
    END
    
    -- Cursor through indexes needing maintenance
    DECLARE IndexCursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT 
            OBJECT_SCHEMA_NAME(ps.object_id) AS SchemaName,
            OBJECT_NAME(ps.object_id) AS TableName,
            i.name AS IndexName,
            ps.avg_fragmentation_in_percent,
            ps.page_count,
            CASE 
                WHEN ps.avg_fragmentation_in_percent >= @RebuildThreshold THEN 'REBUILD'
                WHEN ps.avg_fragmentation_in_percent >= @ReorganizeThreshold THEN 'REORGANIZE'
            END AS Action
        FROM sys.dm_db_index_physical_stats(
            DB_ID(@DatabaseName), NULL, NULL, NULL, 'LIMITED'
        ) ps
        INNER JOIN sys.indexes i 
            ON ps.object_id = i.object_id 
            AND ps.index_id = i.index_id
        WHERE ps.index_id > 0
          AND ps.page_count >= @MinPageCount
          AND ps.avg_fragmentation_in_percent >= @ReorganizeThreshold
          AND ps.alloc_unit_type_desc = 'IN_ROW_DATA'
          AND i.is_disabled = 0
        ORDER BY ps.avg_fragmentation_in_percent DESC;
    
    OPEN IndexCursor;
    FETCH NEXT FROM IndexCursor INTO 
        @SchemaName, @TableName, @IndexName, @Fragmentation, @PageCount, @Action;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @StartTime = GETDATE();
        SET @ErrorMessage = NULL;
        
        BEGIN TRY
            -- Build maintenance command
            IF @Action = 'REBUILD'
            BEGIN
                SET @SQL = 'ALTER INDEX ' + QUOTENAME(@IndexName) + 
                    ' ON ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) +
                    ' REBUILD WITH (';
                
                IF @OnlineRebuild = 1
                    SET @SQL = @SQL + 'ONLINE = ON, ';
                
                SET @SQL = @SQL + 'MAXDOP = ' + CAST(@MaxDOP AS NVARCHAR(10)) + ')';
            END
            ELSE
            BEGIN
                SET @SQL = 'ALTER INDEX ' + QUOTENAME(@IndexName) + 
                    ' ON ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) +
                    ' REORGANIZE';
            END
            
            -- Execute or print
            IF @ExecuteCommands = 1
                EXEC sp_executesql @SQL;
            ELSE
                PRINT @SQL;
            
            SET @EndTime = GETDATE();
            
            -- Log success
            IF @LogToTable = 1
            BEGIN
                INSERT INTO dbo.IndexMaintenanceLog (
                    DatabaseName, SchemaName, TableName, IndexName, Action,
                    FragmentationBefore, PageCount, StartTime, EndTime, 
                    DurationSeconds, Status
                )
                VALUES (
                    ISNULL(@DatabaseName, DB_NAME()), @SchemaName, @TableName, 
                    @IndexName, @Action, @Fragmentation, @PageCount,
                    @StartTime, @EndTime, DATEDIFF(SECOND, @StartTime, @EndTime),
                    'Success'
                );
            END
            
        END TRY
        BEGIN CATCH
            SET @EndTime = GETDATE();
            SET @ErrorMessage = ERROR_MESSAGE();
            
            -- Log failure
            IF @LogToTable = 1
            BEGIN
                INSERT INTO dbo.IndexMaintenanceLog (
                    DatabaseName, SchemaName, TableName, IndexName, Action,
                    FragmentationBefore, PageCount, StartTime, EndTime,
                    DurationSeconds, Status, ErrorMessage
                )
                VALUES (
                    ISNULL(@DatabaseName, DB_NAME()), @SchemaName, @TableName,
                    @IndexName, @Action, @Fragmentation, @PageCount,
                    @StartTime, @EndTime, DATEDIFF(SECOND, @StartTime, @EndTime),
                    'Failed', @ErrorMessage
                );
            END
        END CATCH
        
        FETCH NEXT FROM IndexCursor INTO 
            @SchemaName, @TableName, @IndexName, @Fragmentation, @PageCount, @Action;
    END
    
    CLOSE IndexCursor;
    DEALLOCATE IndexCursor;
    
    -- Return summary
    IF @LogToTable = 1
    BEGIN
        SELECT 
            Status,
            COUNT(*) AS IndexCount,
            SUM(DurationSeconds) AS TotalDurationSeconds
        FROM dbo.IndexMaintenanceLog
        WHERE StartTime >= CAST(GETDATE() AS DATE)
        GROUP BY Status;
    END
END
GO

-- Get index usage statistics
CREATE PROCEDURE dbo.GetIndexUsageStats
    @SchemaName NVARCHAR(128) = NULL,
    @TableName NVARCHAR(128) = NULL,
    @ShowUnused BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        OBJECT_SCHEMA_NAME(i.object_id) AS SchemaName,
        OBJECT_NAME(i.object_id) AS TableName,
        i.name AS IndexName,
        i.type_desc AS IndexType,
        i.is_primary_key,
        i.is_unique,
        ISNULL(us.user_seeks, 0) AS UserSeeks,
        ISNULL(us.user_scans, 0) AS UserScans,
        ISNULL(us.user_lookups, 0) AS UserLookups,
        ISNULL(us.user_seeks + us.user_scans + us.user_lookups, 0) AS TotalReads,
        ISNULL(us.user_updates, 0) AS UserUpdates,
        ISNULL(us.last_user_seek, '1900-01-01') AS LastUserSeek,
        ISNULL(us.last_user_scan, '1900-01-01') AS LastUserScan,
        ISNULL(us.last_user_lookup, '1900-01-01') AS LastUserLookup,
        ps.row_count,
        CAST(ps.reserved_page_count * 8.0 / 1024 AS DECIMAL(18,2)) AS SizeMB,
        CASE 
            WHEN us.user_seeks + us.user_scans + us.user_lookups = 0 
                 AND us.user_updates > 0 
            THEN 'Unused - Consider Dropping'
            WHEN us.user_updates > (us.user_seeks + us.user_scans + us.user_lookups) * 10
            THEN 'High Write/Low Read'
            ELSE 'Active'
        END AS UsageStatus
    FROM sys.indexes i
    INNER JOIN sys.objects o ON i.object_id = o.object_id
    LEFT JOIN sys.dm_db_index_usage_stats us 
        ON i.object_id = us.object_id 
        AND i.index_id = us.index_id
        AND us.database_id = DB_ID()
    LEFT JOIN sys.dm_db_partition_stats ps
        ON i.object_id = ps.object_id
        AND i.index_id = ps.index_id
    WHERE o.type = 'U'
      AND i.type > 0  -- Exclude heaps
      AND (@SchemaName IS NULL OR OBJECT_SCHEMA_NAME(i.object_id) = @SchemaName)
      AND (@TableName IS NULL OR OBJECT_NAME(i.object_id) = @TableName)
      AND (@ShowUnused = 0 OR 
           ISNULL(us.user_seeks + us.user_scans + us.user_lookups, 0) = 0)
    ORDER BY 
        ISNULL(us.user_seeks + us.user_scans + us.user_lookups, 0),
        us.user_updates DESC;
END
GO
