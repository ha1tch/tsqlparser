-- Sample 067: Resource Governor Management
-- Source: Microsoft Learn, MSSQLTips, Glenn Berry
-- Category: Performance
-- Complexity: Advanced
-- Features: Resource pools, workload groups, classifier functions

-- Create resource pool
CREATE PROCEDURE dbo.CreateResourcePool
    @PoolName NVARCHAR(128),
    @MinCpuPercent INT = 0,
    @MaxCpuPercent INT = 100,
    @MinMemoryPercent INT = 0,
    @MaxMemoryPercent INT = 100,
    @CapCpuPercent INT = 100,
    @AffinityMask NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    
    -- Check if pool exists
    IF EXISTS (SELECT 1 FROM sys.resource_governor_resource_pools WHERE name = @PoolName)
    BEGIN
        -- Alter existing pool
        SET @SQL = N'
            ALTER RESOURCE POOL ' + QUOTENAME(@PoolName) + '
            WITH (
                MIN_CPU_PERCENT = ' + CAST(@MinCpuPercent AS VARCHAR(10)) + ',
                MAX_CPU_PERCENT = ' + CAST(@MaxCpuPercent AS VARCHAR(10)) + ',
                CAP_CPU_PERCENT = ' + CAST(@CapCpuPercent AS VARCHAR(10)) + ',
                MIN_MEMORY_PERCENT = ' + CAST(@MinMemoryPercent AS VARCHAR(10)) + ',
                MAX_MEMORY_PERCENT = ' + CAST(@MaxMemoryPercent AS VARCHAR(10)) + '
            )';
    END
    ELSE
    BEGIN
        -- Create new pool
        SET @SQL = N'
            CREATE RESOURCE POOL ' + QUOTENAME(@PoolName) + '
            WITH (
                MIN_CPU_PERCENT = ' + CAST(@MinCpuPercent AS VARCHAR(10)) + ',
                MAX_CPU_PERCENT = ' + CAST(@MaxCpuPercent AS VARCHAR(10)) + ',
                CAP_CPU_PERCENT = ' + CAST(@CapCpuPercent AS VARCHAR(10)) + ',
                MIN_MEMORY_PERCENT = ' + CAST(@MinMemoryPercent AS VARCHAR(10)) + ',
                MAX_MEMORY_PERCENT = ' + CAST(@MaxMemoryPercent AS VARCHAR(10)) + '
            )';
    END
    
    EXEC sp_executesql @SQL;
    
    -- Reconfigure to apply changes
    ALTER RESOURCE GOVERNOR RECONFIGURE;
    
    SELECT 'Resource pool configured' AS Status, @PoolName AS PoolName;
END
GO

-- Create workload group
CREATE PROCEDURE dbo.CreateWorkloadGroup
    @GroupName NVARCHAR(128),
    @PoolName NVARCHAR(128),
    @Importance NVARCHAR(10) = 'MEDIUM',  -- LOW, MEDIUM, HIGH
    @RequestMaxMemoryGrantPercent INT = 25,
    @RequestMaxCpuTimeSec INT = 0,  -- 0 = unlimited
    @RequestMemoryGrantTimeoutSec INT = 0,  -- 0 = use pool default
    @MaxDop INT = 0,  -- 0 = use server default
    @GroupMaxRequests INT = 0  -- 0 = unlimited
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    
    IF EXISTS (SELECT 1 FROM sys.resource_governor_workload_groups WHERE name = @GroupName)
    BEGIN
        SET @SQL = N'
            ALTER WORKLOAD GROUP ' + QUOTENAME(@GroupName) + '
            WITH (
                IMPORTANCE = ' + @Importance + ',
                REQUEST_MAX_MEMORY_GRANT_PERCENT = ' + CAST(@RequestMaxMemoryGrantPercent AS VARCHAR(10)) + ',
                REQUEST_MAX_CPU_TIME_SEC = ' + CAST(@RequestMaxCpuTimeSec AS VARCHAR(10)) + ',
                REQUEST_MEMORY_GRANT_TIMEOUT_SEC = ' + CAST(@RequestMemoryGrantTimeoutSec AS VARCHAR(10)) + ',
                MAX_DOP = ' + CAST(@MaxDop AS VARCHAR(10)) + ',
                GROUP_MAX_REQUESTS = ' + CAST(@GroupMaxRequests AS VARCHAR(10)) + '
            )
            USING ' + QUOTENAME(@PoolName);
    END
    ELSE
    BEGIN
        SET @SQL = N'
            CREATE WORKLOAD GROUP ' + QUOTENAME(@GroupName) + '
            WITH (
                IMPORTANCE = ' + @Importance + ',
                REQUEST_MAX_MEMORY_GRANT_PERCENT = ' + CAST(@RequestMaxMemoryGrantPercent AS VARCHAR(10)) + ',
                REQUEST_MAX_CPU_TIME_SEC = ' + CAST(@RequestMaxCpuTimeSec AS VARCHAR(10)) + ',
                REQUEST_MEMORY_GRANT_TIMEOUT_SEC = ' + CAST(@RequestMemoryGrantTimeoutSec AS VARCHAR(10)) + ',
                MAX_DOP = ' + CAST(@MaxDop AS VARCHAR(10)) + ',
                GROUP_MAX_REQUESTS = ' + CAST(@GroupMaxRequests AS VARCHAR(10)) + '
            )
            USING ' + QUOTENAME(@PoolName);
    END
    
    EXEC sp_executesql @SQL;
    ALTER RESOURCE GOVERNOR RECONFIGURE;
    
    SELECT 'Workload group configured' AS Status, @GroupName AS GroupName, @PoolName AS PoolName;
END
GO

-- Create classifier function
CREATE PROCEDURE dbo.CreateClassifierFunction
    @FunctionName NVARCHAR(128) = 'dbo.ResourceClassifier',
    @Rules NVARCHAR(MAX)  -- JSON array: [{"app":"ReportApp","group":"ReportingGroup"},{"login":"ETLUser","group":"ETLGroup"}]
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @CaseStatements NVARCHAR(MAX) = '';
    
    -- Build CASE statements from rules
    SELECT @CaseStatements = @CaseStatements +
        CASE 
            WHEN JSON_VALUE(value, '$.app') IS NOT NULL THEN
                'WHEN APP_NAME() LIKE ''%' + JSON_VALUE(value, '$.app') + '%'' THEN ''' + JSON_VALUE(value, '$.group') + ''''
            WHEN JSON_VALUE(value, '$.login') IS NOT NULL THEN
                'WHEN SUSER_SNAME() = ''' + JSON_VALUE(value, '$.login') + ''' THEN ''' + JSON_VALUE(value, '$.group') + ''''
            WHEN JSON_VALUE(value, '$.host') IS NOT NULL THEN
                'WHEN HOST_NAME() = ''' + JSON_VALUE(value, '$.host') + ''' THEN ''' + JSON_VALUE(value, '$.group') + ''''
            ELSE ''
        END + CHAR(13) + CHAR(10)
    FROM OPENJSON(@Rules);
    
    -- Create the classifier function
    SET @SQL = N'
        CREATE OR ALTER FUNCTION ' + @FunctionName + '()
        RETURNS SYSNAME
        WITH SCHEMABINDING
        AS
        BEGIN
            DECLARE @GroupName SYSNAME;
            
            SET @GroupName = CASE
                ' + @CaseStatements + '
                ELSE ''default''
            END;
            
            RETURN @GroupName;
        END';
    
    EXEC sp_executesql @SQL;
    
    -- Set the classifier function
    SET @SQL = 'ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = ' + @FunctionName + ')';
    EXEC sp_executesql @SQL;
    
    ALTER RESOURCE GOVERNOR RECONFIGURE;
    
    SELECT 'Classifier function created and enabled' AS Status;
END
GO

-- Get Resource Governor status
CREATE PROCEDURE dbo.GetResourceGovernorStatus
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Overall status
    SELECT 
        is_enabled AS IsEnabled,
        classifier_function_id AS ClassifierFunctionId,
        OBJECT_NAME(classifier_function_id) AS ClassifierFunctionName,
        max_outstanding_io_per_volume AS MaxOutstandingIOPerVolume
    FROM sys.resource_governor_configuration;
    
    -- Resource pools
    SELECT 
        p.name AS PoolName,
        p.min_cpu_percent AS MinCpuPercent,
        p.max_cpu_percent AS MaxCpuPercent,
        p.cap_cpu_percent AS CapCpuPercent,
        p.min_memory_percent AS MinMemoryPercent,
        p.max_memory_percent AS MaxMemoryPercent,
        ps.active_sessions_count AS ActiveSessions,
        ps.total_cpu_usage_ms AS TotalCpuMs,
        ps.total_memgrant_count AS TotalMemGrants,
        ps.total_memgrant_timeout_count AS MemGrantTimeouts,
        ps.cache_memory_kb / 1024 AS CacheMemoryMB,
        ps.used_memory_kb / 1024 AS UsedMemoryMB
    FROM sys.resource_governor_resource_pools p
    LEFT JOIN sys.dm_resource_governor_resource_pools ps ON p.pool_id = ps.pool_id;
    
    -- Workload groups
    SELECT 
        wg.name AS GroupName,
        rp.name AS PoolName,
        wg.importance AS Importance,
        wg.request_max_memory_grant_percent AS MaxMemGrantPercent,
        wg.request_max_cpu_time_sec AS MaxCpuTimeSec,
        wg.max_dop AS MaxDop,
        wg.group_max_requests AS MaxRequests,
        ws.active_request_count AS ActiveRequests,
        ws.total_request_count AS TotalRequests,
        ws.total_cpu_usage_ms AS TotalCpuMs,
        ws.blocked_task_count AS BlockedTasks,
        ws.total_reduced_memgrant_count AS ReducedMemGrants
    FROM sys.resource_governor_workload_groups wg
    INNER JOIN sys.resource_governor_resource_pools rp ON wg.pool_id = rp.pool_id
    LEFT JOIN sys.dm_resource_governor_workload_groups ws ON wg.group_id = ws.group_id;
END
GO

-- Disable Resource Governor
CREATE PROCEDURE dbo.DisableResourceGovernor
AS
BEGIN
    SET NOCOUNT ON;
    
    ALTER RESOURCE GOVERNOR DISABLE;
    
    SELECT 'Resource Governor disabled' AS Status;
END
GO

-- Enable Resource Governor
CREATE PROCEDURE dbo.EnableResourceGovernor
AS
BEGIN
    SET NOCOUNT ON;
    
    ALTER RESOURCE GOVERNOR RECONFIGURE;
    
    SELECT 'Resource Governor enabled' AS Status;
END
GO
