-- Sample 019: Statistics and Query Performance Analysis
-- Source: Brent Ozar, Ola Hallengren, MSSQLTips
-- Category: Performance
-- Complexity: Advanced
-- Features: DMVs, query stats, execution plans, wait stats

-- Get top resource-consuming queries
CREATE PROCEDURE dbo.GetTopResourceQueries
    @TopN INT = 20,
    @OrderBy NVARCHAR(50) = 'TotalCPU',  -- TotalCPU, AvgCPU, TotalReads, AvgReads, ExecutionCount, TotalDuration
    @MinExecutionCount INT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT TOP (@TopN)
        qs.sql_handle,
        qs.plan_handle,
        qs.query_hash,
        qs.query_plan_hash,
        qs.execution_count,
        qs.total_worker_time / 1000 AS total_cpu_ms,
        qs.total_worker_time / qs.execution_count / 1000 AS avg_cpu_ms,
        qs.total_elapsed_time / 1000 AS total_duration_ms,
        qs.total_elapsed_time / qs.execution_count / 1000 AS avg_duration_ms,
        qs.total_logical_reads,
        qs.total_logical_reads / qs.execution_count AS avg_logical_reads,
        qs.total_logical_writes,
        qs.total_physical_reads,
        qs.total_rows,
        qs.total_rows / qs.execution_count AS avg_rows,
        qs.last_execution_time,
        qs.creation_time,
        SUBSTRING(st.text, 
            (qs.statement_start_offset / 2) + 1,
            ((CASE qs.statement_end_offset 
                WHEN -1 THEN DATALENGTH(st.text) 
                ELSE qs.statement_end_offset 
              END - qs.statement_start_offset) / 2) + 1
        ) AS query_text,
        DB_NAME(st.dbid) AS database_name,
        OBJECT_NAME(st.objectid, st.dbid) AS object_name
    FROM sys.dm_exec_query_stats qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
    WHERE qs.execution_count >= @MinExecutionCount
    ORDER BY 
        CASE @OrderBy
            WHEN 'TotalCPU' THEN qs.total_worker_time
            WHEN 'AvgCPU' THEN qs.total_worker_time / qs.execution_count
            WHEN 'TotalReads' THEN qs.total_logical_reads
            WHEN 'AvgReads' THEN qs.total_logical_reads / qs.execution_count
            WHEN 'ExecutionCount' THEN qs.execution_count
            WHEN 'TotalDuration' THEN qs.total_elapsed_time
            ELSE qs.total_worker_time
        END DESC;
END
GO

-- Get wait statistics
CREATE PROCEDURE dbo.GetWaitStats
    @ExcludeCommonWaits BIT = 1,
    @TopN INT = 30
AS
BEGIN
    SET NOCOUNT ON;
    
    WITH WaitStats AS (
        SELECT 
            wait_type,
            waiting_tasks_count,
            wait_time_ms,
            max_wait_time_ms,
            signal_wait_time_ms,
            wait_time_ms - signal_wait_time_ms AS resource_wait_time_ms
        FROM sys.dm_os_wait_stats
        WHERE wait_type NOT LIKE 'SLEEP_%'
          AND wait_time_ms > 0
          AND (@ExcludeCommonWaits = 0 OR wait_type NOT IN (
              -- Benign waits to exclude
              'CLR_SEMAPHORE', 'LAZYWRITER_SLEEP', 'RESOURCE_QUEUE',
              'SLEEP_TASK', 'SLEEP_SYSTEMTASK', 'SQLTRACE_BUFFER_FLUSH',
              'WAITFOR', 'LOGMGR_QUEUE', 'CHECKPOINT_QUEUE',
              'REQUEST_FOR_DEADLOCK_SEARCH', 'XE_TIMER_EVENT',
              'BROKER_TO_FLUSH', 'BROKER_TASK_STOP', 'CLR_MANUAL_EVENT',
              'CLR_AUTO_EVENT', 'DISPATCHER_QUEUE_SEMAPHORE',
              'FT_IFTS_SCHEDULER_IDLE_WAIT', 'XE_DISPATCHER_WAIT',
              'XE_DISPATCHER_JOIN', 'SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
              'ONDEMAND_TASK_QUEUE', 'BROKER_EVENTHANDLER',
              'SLEEP_BPOOL_FLUSH', 'DIRTY_PAGE_POLL',
              'HADR_FILESTREAM_IOMGR_IOCOMPLETION', 'SP_SERVER_DIAGNOSTICS_SLEEP'
          ))
    )
    SELECT TOP (@TopN)
        wait_type,
        waiting_tasks_count,
        wait_time_ms,
        CAST(wait_time_ms * 100.0 / SUM(wait_time_ms) OVER() AS DECIMAL(5,2)) AS wait_pct,
        CAST(SUM(wait_time_ms) OVER(ORDER BY wait_time_ms DESC) * 100.0 / 
             SUM(wait_time_ms) OVER() AS DECIMAL(5,2)) AS running_pct,
        max_wait_time_ms,
        signal_wait_time_ms,
        resource_wait_time_ms,
        CASE 
            WHEN waiting_tasks_count > 0 
            THEN wait_time_ms / waiting_tasks_count 
            ELSE 0 
        END AS avg_wait_ms
    FROM WaitStats
    ORDER BY wait_time_ms DESC;
END
GO

-- Get missing index recommendations
CREATE PROCEDURE dbo.GetMissingIndexes
    @DatabaseName NVARCHAR(128) = NULL,
    @MinAvgUserImpact FLOAT = 50.0,
    @TopN INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT TOP (@TopN)
        DB_NAME(mid.database_id) AS DatabaseName,
        OBJECT_SCHEMA_NAME(mid.object_id, mid.database_id) AS SchemaName,
        OBJECT_NAME(mid.object_id, mid.database_id) AS TableName,
        migs.unique_compiles,
        migs.user_seeks,
        migs.user_scans,
        migs.avg_total_user_cost,
        migs.avg_user_impact,
        migs.user_seeks * migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) AS improvement_measure,
        mid.equality_columns,
        mid.inequality_columns,
        mid.included_columns,
        'CREATE NONCLUSTERED INDEX [IX_' + 
            OBJECT_NAME(mid.object_id, mid.database_id) + '_' +
            REPLACE(REPLACE(REPLACE(ISNULL(mid.equality_columns, ''), ', ', '_'), '[', ''), ']', '') + 
            '] ON ' +
            QUOTENAME(DB_NAME(mid.database_id)) + '.' +
            QUOTENAME(OBJECT_SCHEMA_NAME(mid.object_id, mid.database_id)) + '.' +
            QUOTENAME(OBJECT_NAME(mid.object_id, mid.database_id)) + ' (' +
            ISNULL(mid.equality_columns, '') +
            CASE 
                WHEN mid.equality_columns IS NOT NULL AND mid.inequality_columns IS NOT NULL 
                THEN ', ' 
                ELSE '' 
            END +
            ISNULL(mid.inequality_columns, '') + ')' +
            CASE 
                WHEN mid.included_columns IS NOT NULL 
                THEN ' INCLUDE (' + mid.included_columns + ')' 
                ELSE '' 
            END AS create_index_statement
    FROM sys.dm_db_missing_index_groups mig
    INNER JOIN sys.dm_db_missing_index_group_stats migs 
        ON mig.index_group_handle = migs.group_handle
    INNER JOIN sys.dm_db_missing_index_details mid 
        ON mig.index_handle = mid.index_handle
    WHERE (@DatabaseName IS NULL OR DB_NAME(mid.database_id) = @DatabaseName)
      AND migs.avg_user_impact >= @MinAvgUserImpact
    ORDER BY improvement_measure DESC;
END
GO

-- Update statistics for all tables
CREATE PROCEDURE dbo.UpdateAllStatistics
    @DatabaseName NVARCHAR(128) = NULL,
    @SamplePercent INT = NULL,  -- NULL = default sampling
    @OnlyOutdated BIT = 1,
    @DaysOld INT = 7,
    @LogToTable BIT = 1,
    @ExecuteCommands BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @SchemaName NVARCHAR(128);
    DECLARE @TableName NVARCHAR(128);
    DECLARE @StatName NVARCHAR(128);
    DECLARE @StartTime DATETIME;
    DECLARE @EndTime DATETIME;
    
    -- Create log table if needed
    IF @LogToTable = 1 AND OBJECT_ID('dbo.StatisticsUpdateLog', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.StatisticsUpdateLog (
            LogID INT IDENTITY(1,1) PRIMARY KEY,
            DatabaseName NVARCHAR(128),
            SchemaName NVARCHAR(128),
            TableName NVARCHAR(128),
            StatisticName NVARCHAR(128),
            StartTime DATETIME,
            EndTime DATETIME,
            DurationSeconds INT,
            RowsModified BIGINT,
            Status NVARCHAR(20),
            ErrorMessage NVARCHAR(4000)
        );
    END
    
    -- Get statistics that need updating
    DECLARE StatCursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT 
            OBJECT_SCHEMA_NAME(s.object_id) AS SchemaName,
            OBJECT_NAME(s.object_id) AS TableName,
            s.name AS StatisticName
        FROM sys.stats s
        INNER JOIN sys.objects o ON s.object_id = o.object_id
        CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
        WHERE o.type = 'U'
          AND (@OnlyOutdated = 0 OR 
               sp.last_updated IS NULL OR
               sp.last_updated < DATEADD(DAY, -@DaysOld, GETDATE()) OR
               sp.modification_counter > sp.rows * 0.20)
        ORDER BY sp.modification_counter DESC;
    
    OPEN StatCursor;
    FETCH NEXT FROM StatCursor INTO @SchemaName, @TableName, @StatName;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @StartTime = GETDATE();
        
        BEGIN TRY
            -- Build update statistics command
            SET @SQL = 'UPDATE STATISTICS ' + 
                       QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) +
                       ' ' + QUOTENAME(@StatName);
            
            IF @SamplePercent IS NOT NULL
                SET @SQL = @SQL + ' WITH SAMPLE ' + CAST(@SamplePercent AS NVARCHAR(3)) + ' PERCENT';
            
            IF @ExecuteCommands = 1
                EXEC sp_executesql @SQL;
            ELSE
                PRINT @SQL;
            
            SET @EndTime = GETDATE();
            
            -- Log success
            IF @LogToTable = 1
            BEGIN
                INSERT INTO dbo.StatisticsUpdateLog (
                    DatabaseName, SchemaName, TableName, StatisticName,
                    StartTime, EndTime, DurationSeconds, Status
                )
                VALUES (
                    ISNULL(@DatabaseName, DB_NAME()), @SchemaName, @TableName, @StatName,
                    @StartTime, @EndTime, DATEDIFF(SECOND, @StartTime, @EndTime), 'Success'
                );
            END
            
        END TRY
        BEGIN CATCH
            SET @EndTime = GETDATE();
            
            IF @LogToTable = 1
            BEGIN
                INSERT INTO dbo.StatisticsUpdateLog (
                    DatabaseName, SchemaName, TableName, StatisticName,
                    StartTime, EndTime, DurationSeconds, Status, ErrorMessage
                )
                VALUES (
                    ISNULL(@DatabaseName, DB_NAME()), @SchemaName, @TableName, @StatName,
                    @StartTime, @EndTime, DATEDIFF(SECOND, @StartTime, @EndTime), 
                    'Failed', ERROR_MESSAGE()
                );
            END
        END CATCH
        
        FETCH NEXT FROM StatCursor INTO @SchemaName, @TableName, @StatName;
    END
    
    CLOSE StatCursor;
    DEALLOCATE StatCursor;
    
    -- Return summary
    IF @LogToTable = 1
    BEGIN
        SELECT 
            Status,
            COUNT(*) AS StatisticsCount,
            SUM(DurationSeconds) AS TotalDurationSeconds
        FROM dbo.StatisticsUpdateLog
        WHERE StartTime >= @StartTime
        GROUP BY Status;
    END
END
GO

-- Analyze query plan cache
CREATE PROCEDURE dbo.AnalyzePlanCache
    @MinUsageCount INT = 10,
    @ShowPlanXML BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        cp.objtype AS ObjectType,
        cp.cacheobjtype AS CacheObjectType,
        cp.usecounts AS UseCount,
        cp.size_in_bytes / 1024 AS SizeKB,
        cp.refcounts AS ReferenceCount,
        qp.query_plan.value('declare namespace p="http://schemas.microsoft.com/sqlserver/2004/07/showplan";
            (//p:StmtSimple/@StatementEstRows)[1]', 'float') AS EstimatedRows,
        qp.query_plan.value('declare namespace p="http://schemas.microsoft.com/sqlserver/2004/07/showplan";
            (//p:StmtSimple/@StatementSubTreeCost)[1]', 'float') AS EstimatedCost,
        qp.query_plan.exist('declare namespace p="http://schemas.microsoft.com/sqlserver/2004/07/showplan";
            //p:TableScan') AS HasTableScan,
        qp.query_plan.exist('declare namespace p="http://schemas.microsoft.com/sqlserver/2004/07/showplan";
            //p:IndexScan[@Lookup="1"]') AS HasKeyLookup,
        qp.query_plan.exist('declare namespace p="http://schemas.microsoft.com/sqlserver/2004/07/showplan";
            //p:Sort') AS HasSort,
        qp.query_plan.exist('declare namespace p="http://schemas.microsoft.com/sqlserver/2004/07/showplan";
            //p:Hash') AS HasHashJoin,
        st.text AS QueryText,
        CASE WHEN @ShowPlanXML = 1 THEN qp.query_plan ELSE NULL END AS QueryPlan
    FROM sys.dm_exec_cached_plans cp
    CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) st
    CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) qp
    WHERE cp.usecounts >= @MinUsageCount
      AND cp.objtype IN ('Proc', 'Prepared', 'Adhoc')
    ORDER BY cp.usecounts DESC;
END
GO
