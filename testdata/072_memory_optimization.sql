-- Sample 072: Memory Optimization and Analysis
-- Source: Microsoft Learn, Brent Ozar, Glenn Berry
-- Category: Performance
-- Complexity: Advanced
-- Features: Buffer pool, memory grants, memory clerks, DBCC MEMORYSTATUS

-- Analyze buffer pool usage
CREATE PROCEDURE dbo.AnalyzeBufferPool
    @TopN INT = 25
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Buffer pool by database
    SELECT 
        CASE database_id 
            WHEN 32767 THEN 'ResourceDB'
            ELSE DB_NAME(database_id)
        END AS DatabaseName,
        COUNT(*) AS PageCount,
        CAST(COUNT(*) * 8.0 / 1024 AS DECIMAL(18,2)) AS BufferSizeMB,
        CAST(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM sys.dm_os_buffer_descriptors) AS DECIMAL(5,2)) AS BufferPercent,
        SUM(CAST(free_space_in_bytes AS BIGINT)) / 1024 / 1024 AS FreeSpaceMB
    FROM sys.dm_os_buffer_descriptors
    GROUP BY database_id
    ORDER BY PageCount DESC;
    
    -- Buffer pool by object (current database)
    SELECT TOP (@TopN)
        OBJECT_SCHEMA_NAME(p.object_id) AS SchemaName,
        OBJECT_NAME(p.object_id) AS ObjectName,
        i.name AS IndexName,
        i.type_desc AS IndexType,
        COUNT(*) AS PageCount,
        CAST(COUNT(*) * 8.0 / 1024 AS DECIMAL(18,2)) AS BufferMB,
        SUM(CASE WHEN bd.is_modified = 1 THEN 1 ELSE 0 END) AS DirtyPages
    FROM sys.dm_os_buffer_descriptors bd
    INNER JOIN sys.allocation_units au ON bd.allocation_unit_id = au.allocation_unit_id
    INNER JOIN sys.partitions p ON au.container_id = p.hobt_id
    INNER JOIN sys.indexes i ON p.object_id = i.object_id AND p.index_id = i.index_id
    WHERE bd.database_id = DB_ID()
      AND p.object_id > 100
    GROUP BY p.object_id, i.name, i.type_desc
    ORDER BY PageCount DESC;
END
GO

-- Analyze memory grants
CREATE PROCEDURE dbo.AnalyzeMemoryGrants
    @ShowPending BIT = 1,
    @ShowActive BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Current memory grants
    SELECT 
        session_id AS SessionID,
        request_id AS RequestID,
        scheduler_id AS SchedulerID,
        dop AS DegreeOfParallelism,
        request_time AS RequestTime,
        grant_time AS GrantTime,
        DATEDIFF(MS, request_time, ISNULL(grant_time, GETDATE())) AS WaitTimeMs,
        requested_memory_kb / 1024 AS RequestedMB,
        granted_memory_kb / 1024 AS GrantedMB,
        required_memory_kb / 1024 AS RequiredMB,
        used_memory_kb / 1024 AS UsedMB,
        max_used_memory_kb / 1024 AS MaxUsedMB,
        ideal_memory_kb / 1024 AS IdealMB,
        is_small AS IsSmallGrant,
        timeout_sec AS TimeoutSec,
        query_cost AS QueryCost,
        SUBSTRING(st.text, (mg.statement_start_offset/2) + 1,
            ((CASE mg.statement_end_offset
                WHEN -1 THEN DATALENGTH(st.text)
                ELSE mg.statement_end_offset
            END - mg.statement_start_offset)/2) + 1) AS QueryText
    FROM sys.dm_exec_query_memory_grants mg
    CROSS APPLY sys.dm_exec_sql_text(mg.sql_handle) st
    WHERE (@ShowPending = 1 AND grant_time IS NULL)
       OR (@ShowActive = 1 AND grant_time IS NOT NULL)
    ORDER BY requested_memory_kb DESC;
    
    -- Memory grant summary
    SELECT 
        COUNT(*) AS TotalGrants,
        SUM(CASE WHEN grant_time IS NULL THEN 1 ELSE 0 END) AS PendingGrants,
        SUM(CASE WHEN grant_time IS NOT NULL THEN 1 ELSE 0 END) AS ActiveGrants,
        SUM(requested_memory_kb) / 1024 AS TotalRequestedMB,
        SUM(granted_memory_kb) / 1024 AS TotalGrantedMB,
        SUM(used_memory_kb) / 1024 AS TotalUsedMB
    FROM sys.dm_exec_query_memory_grants;
END
GO

-- Analyze memory clerks
CREATE PROCEDURE dbo.AnalyzeMemoryClerks
    @MinSizeMB INT = 10
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        type AS ClerkType,
        name AS ClerkName,
        CAST(pages_kb / 1024.0 AS DECIMAL(18,2)) AS SizeMB,
        CAST(virtual_memory_reserved_kb / 1024.0 AS DECIMAL(18,2)) AS VirtualReservedMB,
        CAST(virtual_memory_committed_kb / 1024.0 AS DECIMAL(18,2)) AS VirtualCommittedMB,
        CAST(awe_allocated_kb / 1024.0 AS DECIMAL(18,2)) AS AWEAllocatedMB,
        CAST(pages_kb * 100.0 / SUM(pages_kb) OVER () AS DECIMAL(5,2)) AS MemoryPercent
    FROM sys.dm_os_memory_clerks
    WHERE pages_kb / 1024 >= @MinSizeMB
    ORDER BY pages_kb DESC;
    
    -- Total by clerk type
    SELECT 
        type AS ClerkType,
        COUNT(*) AS ClerkCount,
        CAST(SUM(pages_kb) / 1024.0 AS DECIMAL(18,2)) AS TotalSizeMB
    FROM sys.dm_os_memory_clerks
    GROUP BY type
    HAVING SUM(pages_kb) / 1024 >= @MinSizeMB
    ORDER BY TotalSizeMB DESC;
END
GO

-- Get memory configuration
CREATE PROCEDURE dbo.GetMemoryConfiguration
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Server memory settings
    SELECT 
        c.name AS ConfigOption,
        c.value AS ConfiguredValue,
        c.value_in_use AS RunningValue,
        CASE c.name
            WHEN 'max server memory (MB)' THEN 'Maximum memory SQL Server can use'
            WHEN 'min server memory (MB)' THEN 'Minimum memory SQL Server will maintain'
            ELSE c.description
        END AS Description
    FROM sys.configurations c
    WHERE c.name IN ('max server memory (MB)', 'min server memory (MB)', 
                     'optimize for ad hoc workloads', 'cost threshold for parallelism');
    
    -- Physical memory info
    SELECT 
        total_physical_memory_kb / 1024 AS TotalPhysicalMemoryMB,
        available_physical_memory_kb / 1024 AS AvailablePhysicalMemoryMB,
        total_page_file_kb / 1024 AS TotalPageFileMB,
        available_page_file_kb / 1024 AS AvailablePageFileMB,
        system_memory_state_desc AS MemoryState
    FROM sys.dm_os_sys_memory;
    
    -- SQL Server memory usage
    SELECT 
        physical_memory_in_use_kb / 1024 AS PhysicalMemoryInUseMB,
        locked_page_allocations_kb / 1024 AS LockedPagesMB,
        virtual_address_space_committed_kb / 1024 AS VirtualCommittedMB,
        memory_utilization_percentage AS MemoryUtilizationPercent,
        process_physical_memory_low AS IsMemoryLow,
        process_virtual_memory_low AS IsVirtualMemoryLow
    FROM sys.dm_os_process_memory;
END
GO

-- Clear specific caches
CREATE PROCEDURE dbo.ClearMemoryCache
    @CacheType NVARCHAR(50) = NULL  -- NULL, PLAN, TOKENANDPERMUSERSTORE, ALL
AS
BEGIN
    SET NOCOUNT ON;
    
    IF @CacheType IS NULL
    BEGIN
        SELECT 'Available cache types: PLAN, TOKENANDPERMUSERSTORE, ALL' AS Info;
        
        -- Show current cache sizes
        SELECT 
            type AS CacheType,
            name AS CacheName,
            CAST(pages_kb / 1024.0 AS DECIMAL(18,2)) AS SizeMB
        FROM sys.dm_os_memory_clerks
        WHERE type IN ('CACHESTORE_SQLCP', 'CACHESTORE_OBJCP', 'CACHESTORE_PHDR', 
                       'CACHESTORE_XPROC', 'USERSTORE_TOKENPERM')
        ORDER BY pages_kb DESC;
        RETURN;
    END
    
    IF @CacheType = 'PLAN' OR @CacheType = 'ALL'
    BEGIN
        DBCC FREEPROCCACHE;
        PRINT 'Plan cache cleared';
    END
    
    IF @CacheType = 'TOKENANDPERMUSERSTORE' OR @CacheType = 'ALL'
    BEGIN
        DBCC FREESYSTEMCACHE('TokenAndPermUserStore');
        PRINT 'Token and permission cache cleared';
    END
    
    SELECT 'Cache cleared: ' + @CacheType AS Status;
END
GO

-- Find memory-intensive queries
CREATE PROCEDURE dbo.FindMemoryIntensiveQueries
    @TopN INT = 25
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT TOP (@TopN)
        qs.total_grant_kb / qs.execution_count / 1024 AS AvgGrantMB,
        qs.max_grant_kb / 1024 AS MaxGrantMB,
        qs.total_used_grant_kb / qs.execution_count / 1024 AS AvgUsedMB,
        qs.max_used_grant_kb / 1024 AS MaxUsedMB,
        qs.total_ideal_grant_kb / qs.execution_count / 1024 AS AvgIdealMB,
        qs.execution_count AS ExecutionCount,
        qs.total_spills AS TotalSpills,
        SUBSTRING(st.text, (qs.statement_start_offset/2) + 1,
            ((CASE qs.statement_end_offset
                WHEN -1 THEN DATALENGTH(st.text)
                ELSE qs.statement_end_offset
            END - qs.statement_start_offset)/2) + 1) AS QueryText
    FROM sys.dm_exec_query_stats qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
    WHERE qs.total_grant_kb > 0
    ORDER BY qs.total_grant_kb / qs.execution_count DESC;
END
GO
