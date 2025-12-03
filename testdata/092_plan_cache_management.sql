-- Sample 092: Query Plan Cache Management
-- Source: Microsoft Learn, Kimberly Tripp, Brent Ozar
-- Category: Performance
-- Complexity: Advanced
-- Features: Plan cache analysis, single-use plans, plan reuse, cache pressure

-- Analyze plan cache contents
CREATE PROCEDURE dbo.AnalyzePlanCache
    @TopN INT = 50,
    @SortBy NVARCHAR(20) = 'SIZE'  -- SIZE, USECOUNT, CPU, READS
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT TOP (@TopN)
        cp.objtype AS PlanType,
        cp.cacheobjtype AS CacheObjectType,
        cp.usecounts AS UseCount,
        cp.size_in_bytes / 1024 AS SizeKB,
        cp.refcounts AS RefCount,
        qs.total_worker_time / 1000 AS TotalCPUMs,
        qs.total_elapsed_time / 1000 AS TotalDurationMs,
        qs.total_logical_reads AS TotalReads,
        qs.total_logical_writes AS TotalWrites,
        qs.execution_count AS ExecutionCount,
        DB_NAME(st.dbid) AS DatabaseName,
        OBJECT_NAME(st.objectid, st.dbid) AS ObjectName,
        SUBSTRING(st.text, (qs.statement_start_offset/2) + 1,
            ((CASE qs.statement_end_offset
                WHEN -1 THEN DATALENGTH(st.text)
                ELSE qs.statement_end_offset
            END - qs.statement_start_offset)/2) + 1) AS QueryText,
        qp.query_plan AS ExecutionPlan
    FROM sys.dm_exec_cached_plans cp
    INNER JOIN sys.dm_exec_query_stats qs ON cp.plan_handle = qs.plan_handle
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
    CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
    ORDER BY 
        CASE @SortBy
            WHEN 'SIZE' THEN cp.size_in_bytes
            WHEN 'USECOUNT' THEN cp.usecounts
            WHEN 'CPU' THEN qs.total_worker_time
            WHEN 'READS' THEN qs.total_logical_reads
            ELSE cp.size_in_bytes
        END DESC;
END
GO

-- Find single-use plans wasting memory
CREATE PROCEDURE dbo.FindSingleUsePlans
    @MinSizeKB INT = 100
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Summary of single-use plan waste
    SELECT 
        'Single-Use Plan Analysis' AS Section,
        COUNT(*) AS TotalPlans,
        SUM(CASE WHEN usecounts = 1 THEN 1 ELSE 0 END) AS SingleUsePlans,
        CAST(SUM(CASE WHEN usecounts = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS DECIMAL(5,2)) AS SingleUsePercent,
        SUM(size_in_bytes) / 1024 / 1024 AS TotalCacheMB,
        SUM(CASE WHEN usecounts = 1 THEN size_in_bytes ELSE 0 END) / 1024 / 1024 AS SingleUseCacheMB,
        CAST(SUM(CASE WHEN usecounts = 1 THEN size_in_bytes ELSE 0 END) * 100.0 / SUM(size_in_bytes) AS DECIMAL(5,2)) AS WastedPercent
    FROM sys.dm_exec_cached_plans
    WHERE objtype = 'Adhoc';
    
    -- Top single-use plans by size
    SELECT TOP 50
        size_in_bytes / 1024 AS SizeKB,
        st.text AS QueryText
    FROM sys.dm_exec_cached_plans cp
    CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) st
    WHERE cp.usecounts = 1
      AND cp.objtype = 'Adhoc'
      AND cp.size_in_bytes / 1024 >= @MinSizeKB
    ORDER BY cp.size_in_bytes DESC;
    
    -- Recommendation
    SELECT 
        'If single-use plans > 50% of cache, consider:' AS Recommendation,
        '1. Enable "optimize for ad hoc workloads"' AS Option1,
        '2. Parameterize queries in application' AS Option2,
        '3. Use sp_executesql with parameters' AS Option3;
END
GO

-- Get plan cache summary by type
CREATE PROCEDURE dbo.GetPlanCacheSummary
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        objtype AS PlanType,
        COUNT(*) AS PlanCount,
        SUM(usecounts) AS TotalUseCount,
        AVG(usecounts) AS AvgUseCount,
        SUM(size_in_bytes) / 1024 / 1024 AS TotalSizeMB,
        AVG(size_in_bytes) / 1024 AS AvgSizeKB,
        SUM(CASE WHEN usecounts = 1 THEN 1 ELSE 0 END) AS SingleUsePlans,
        SUM(CASE WHEN usecounts > 100 THEN 1 ELSE 0 END) AS HighReusePlans
    FROM sys.dm_exec_cached_plans
    GROUP BY objtype
    ORDER BY TotalSizeMB DESC;
    
    -- Cache hit ratio approximation
    SELECT 
        'Plan Cache Statistics' AS Section,
        (SELECT cntr_value FROM sys.dm_os_performance_counters 
         WHERE counter_name = 'SQL Compilations/sec') AS CompilationsPerSec,
        (SELECT cntr_value FROM sys.dm_os_performance_counters 
         WHERE counter_name = 'SQL Re-Compilations/sec') AS RecompilationsPerSec,
        (SELECT cntr_value FROM sys.dm_os_performance_counters 
         WHERE counter_name = 'Batch Requests/sec') AS BatchRequestsPerSec;
END
GO

-- Find queries causing recompilations
CREATE PROCEDURE dbo.FindRecompilationCauses
    @TopN INT = 25
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT TOP (@TopN)
        qs.plan_generation_num AS RecompileCount,
        qs.execution_count AS ExecutionCount,
        CAST(qs.plan_generation_num * 100.0 / NULLIF(qs.execution_count, 0) AS DECIMAL(5,2)) AS RecompilePercent,
        qs.total_worker_time / 1000 AS TotalCPUMs,
        DB_NAME(st.dbid) AS DatabaseName,
        OBJECT_NAME(st.objectid, st.dbid) AS ObjectName,
        st.text AS QueryText
    FROM sys.dm_exec_query_stats qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
    WHERE qs.plan_generation_num > 1
    ORDER BY qs.plan_generation_num DESC;
    
    -- Common recompilation causes
    SELECT 
        Cause,
        Description,
        Solution
    FROM (VALUES
        ('Statistics Update', 'Auto-update statistics triggered recompile', 'Normal - ensure stats are accurate'),
        ('Schema Change', 'Table or index was modified', 'Review DDL operations during business hours'),
        ('SET Options', 'Different SET options between connections', 'Standardize connection settings'),
        ('Temp Table', 'Temp table row count changed significantly', 'Use table variables or KEEP PLAN hint'),
        ('RECOMPILE Hint', 'Query has RECOMPILE hint', 'Remove hint if recompile not needed'),
        ('Interleaved Execution', 'Adaptive query processing feature', 'Normal for table-valued functions')
    ) AS Causes(Cause, Description, Solution);
END
GO

-- Clear specific plans from cache
CREATE PROCEDURE dbo.ClearPlansFromCache
    @ClearType NVARCHAR(20),  -- ALL, DATABASE, OBJECT, QUERY
    @DatabaseName NVARCHAR(128) = NULL,
    @ObjectName NVARCHAR(256) = NULL,
    @PlanHandle VARBINARY(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    
    IF @ClearType = 'ALL'
    BEGIN
        DBCC FREEPROCCACHE;
        SELECT 'Entire plan cache cleared' AS Status;
    END
    ELSE IF @ClearType = 'DATABASE' AND @DatabaseName IS NOT NULL
    BEGIN
        DECLARE @DBID INT = DB_ID(@DatabaseName);
        DBCC FLUSHPROCINDB(@DBID);
        SELECT 'Plan cache cleared for database: ' + @DatabaseName AS Status;
    END
    ELSE IF @ClearType = 'OBJECT' AND @ObjectName IS NOT NULL
    BEGIN
        -- Get plan handles for the object
        DECLARE @Handles TABLE (plan_handle VARBINARY(64));
        
        INSERT INTO @Handles
        SELECT DISTINCT qs.plan_handle
        FROM sys.dm_exec_query_stats qs
        CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
        WHERE OBJECT_NAME(st.objectid, st.dbid) = @ObjectName;
        
        DECLARE @Handle VARBINARY(64);
        DECLARE HandleCursor CURSOR FOR SELECT plan_handle FROM @Handles;
        OPEN HandleCursor;
        FETCH NEXT FROM HandleCursor INTO @Handle;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            DBCC FREEPROCCACHE(@Handle);
            FETCH NEXT FROM HandleCursor INTO @Handle;
        END
        CLOSE HandleCursor;
        DEALLOCATE HandleCursor;
        
        SELECT 'Plans cleared for object: ' + @ObjectName AS Status, COUNT(*) AS PlansCleared FROM @Handles;
    END
    ELSE IF @ClearType = 'QUERY' AND @PlanHandle IS NOT NULL
    BEGIN
        DBCC FREEPROCCACHE(@PlanHandle);
        SELECT 'Specific plan cleared' AS Status;
    END
END
GO

-- Monitor plan cache pressure
CREATE PROCEDURE dbo.MonitorPlanCachePressure
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        type AS CacheType,
        name AS CacheName,
        entries_count AS Entries,
        entries_in_use_count AS EntriesInUse,
        CAST(single_pages_kb / 1024.0 AS DECIMAL(10,2)) AS SinglePagesMB,
        CAST(multi_pages_kb / 1024.0 AS DECIMAL(10,2)) AS MultiPagesMB,
        CAST((single_pages_kb + multi_pages_kb) / 1024.0 AS DECIMAL(10,2)) AS TotalMB
    FROM sys.dm_os_memory_cache_counters
    WHERE type IN ('CACHESTORE_SQLCP', 'CACHESTORE_OBJCP', 'CACHESTORE_PHDR')
    ORDER BY (single_pages_kb + multi_pages_kb) DESC;
    
    -- Check for memory pressure
    SELECT 
        CASE 
            WHEN (SELECT SUM(single_pages_kb + multi_pages_kb) / 1024 FROM sys.dm_os_memory_cache_counters 
                  WHERE type = 'CACHESTORE_SQLCP') > 
                 (SELECT committed_target_kb / 1024 * 0.75 FROM sys.dm_os_sys_info)
            THEN 'HIGH - Plan cache using significant memory'
            ELSE 'NORMAL'
        END AS PlanCachePressure;
END
GO
