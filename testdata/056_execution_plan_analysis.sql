-- Sample 056: Execution Plan Analysis
-- Source: Brent Ozar, Grant Fritchey, MSSQLTips
-- Category: Performance
-- Complexity: Advanced
-- Features: sys.dm_exec_query_plan, plan cache analysis, plan guides

-- Get execution plan for a query
CREATE PROCEDURE dbo.GetQueryExecutionPlan
    @QueryText NVARCHAR(MAX),
    @ShowEstimated BIT = 1,
    @ShowActual BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    
    IF @ShowEstimated = 1
    BEGIN
        SET @SQL = 'SET SHOWPLAN_XML ON; ' + @QueryText + '; SET SHOWPLAN_XML OFF;';
        -- Note: Can't execute directly, need to return instructions
        SELECT 'Run the following to get estimated plan:' AS Instructions,
               'SET SHOWPLAN_XML ON; ' + @QueryText + '; SET SHOWPLAN_XML OFF;' AS Script;
    END
    
    IF @ShowActual = 1
    BEGIN
        SET @SQL = 'SET STATISTICS XML ON; ' + @QueryText + '; SET STATISTICS XML OFF;';
        SELECT 'Run the following to get actual plan:' AS Instructions,
               'SET STATISTICS XML ON; ' + @QueryText + '; SET STATISTICS XML OFF;' AS Script;
    END
END
GO

-- Analyze plan cache for expensive queries
CREATE PROCEDURE dbo.AnalyzePlanCacheExpensive
    @TopN INT = 25,
    @SortBy NVARCHAR(20) = 'TotalCPU'  -- TotalCPU, AvgCPU, TotalReads, AvgReads, ExecutionCount, TotalDuration
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT TOP (@TopN)
        qs.sql_handle,
        qs.plan_handle,
        qs.execution_count AS ExecutionCount,
        qs.total_worker_time / 1000 AS TotalCPUMs,
        qs.total_worker_time / NULLIF(qs.execution_count, 0) / 1000 AS AvgCPUMs,
        qs.total_elapsed_time / 1000 AS TotalDurationMs,
        qs.total_elapsed_time / NULLIF(qs.execution_count, 0) / 1000 AS AvgDurationMs,
        qs.total_logical_reads AS TotalLogicalReads,
        qs.total_logical_reads / NULLIF(qs.execution_count, 0) AS AvgLogicalReads,
        qs.total_physical_reads AS TotalPhysicalReads,
        qs.total_logical_writes AS TotalLogicalWrites,
        qs.total_rows AS TotalRows,
        qs.total_rows / NULLIF(qs.execution_count, 0) AS AvgRows,
        qs.creation_time AS PlanCreationTime,
        qs.last_execution_time AS LastExecutionTime,
        SUBSTRING(st.text, (qs.statement_start_offset/2) + 1,
            ((CASE qs.statement_end_offset
                WHEN -1 THEN DATALENGTH(st.text)
                ELSE qs.statement_end_offset
            END - qs.statement_start_offset)/2) + 1) AS QueryText,
        qp.query_plan AS ExecutionPlan
    FROM sys.dm_exec_query_stats qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
    CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
    ORDER BY 
        CASE @SortBy
            WHEN 'TotalCPU' THEN qs.total_worker_time
            WHEN 'AvgCPU' THEN qs.total_worker_time / NULLIF(qs.execution_count, 0)
            WHEN 'TotalReads' THEN qs.total_logical_reads
            WHEN 'AvgReads' THEN qs.total_logical_reads / NULLIF(qs.execution_count, 0)
            WHEN 'ExecutionCount' THEN qs.execution_count
            WHEN 'TotalDuration' THEN qs.total_elapsed_time
            ELSE qs.total_worker_time
        END DESC;
END
GO

-- Find queries with plan issues (scans, lookups, spills)
CREATE PROCEDURE dbo.FindProblematicPlans
    @MinExecutions INT = 10,
    @LookForScans BIT = 1,
    @LookForLookups BIT = 1,
    @LookForSpills BIT = 1,
    @LookForImplicitConversions BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        qs.execution_count,
        qs.total_logical_reads,
        qs.total_worker_time / 1000 AS TotalCPUMs,
        SUBSTRING(st.text, (qs.statement_start_offset/2) + 1,
            ((CASE qs.statement_end_offset
                WHEN -1 THEN DATALENGTH(st.text)
                ELSE qs.statement_end_offset
            END - qs.statement_start_offset)/2) + 1) AS QueryText,
        CASE WHEN CAST(qp.query_plan AS NVARCHAR(MAX)) LIKE '%<TableScan%' THEN 'Table Scan' ELSE '' END +
        CASE WHEN CAST(qp.query_plan AS NVARCHAR(MAX)) LIKE '%<IndexScan%' AND CAST(qp.query_plan AS NVARCHAR(MAX)) NOT LIKE '%<IndexSeek%' THEN ' Index Scan' ELSE '' END +
        CASE WHEN CAST(qp.query_plan AS NVARCHAR(MAX)) LIKE '%<NestedLoops%Lookup%' OR CAST(qp.query_plan AS NVARCHAR(MAX)) LIKE '%Key Lookup%' THEN ' Key Lookup' ELSE '' END +
        CASE WHEN CAST(qp.query_plan AS NVARCHAR(MAX)) LIKE '%SpillToTempDb%' THEN ' TempDB Spill' ELSE '' END +
        CASE WHEN CAST(qp.query_plan AS NVARCHAR(MAX)) LIKE '%CONVERT_IMPLICIT%' THEN ' Implicit Conversion' ELSE '' END AS Issues,
        qp.query_plan
    FROM sys.dm_exec_query_stats qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
    CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
    WHERE qs.execution_count >= @MinExecutions
      AND (
          (@LookForScans = 1 AND (CAST(qp.query_plan AS NVARCHAR(MAX)) LIKE '%<TableScan%' OR CAST(qp.query_plan AS NVARCHAR(MAX)) LIKE '%<IndexScan%'))
          OR (@LookForLookups = 1 AND (CAST(qp.query_plan AS NVARCHAR(MAX)) LIKE '%Key Lookup%' OR CAST(qp.query_plan AS NVARCHAR(MAX)) LIKE '%<NestedLoops%Lookup%'))
          OR (@LookForSpills = 1 AND CAST(qp.query_plan AS NVARCHAR(MAX)) LIKE '%SpillToTempDb%')
          OR (@LookForImplicitConversions = 1 AND CAST(qp.query_plan AS NVARCHAR(MAX)) LIKE '%CONVERT_IMPLICIT%')
      )
    ORDER BY qs.total_logical_reads DESC;
END
GO

-- Clear specific plan from cache
CREATE PROCEDURE dbo.ClearPlanFromCache
    @PlanHandle VARBINARY(64) = NULL,
    @SqlHandle VARBINARY(64) = NULL,
    @QueryText NVARCHAR(MAX) = NULL,
    @ClearAll BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    IF @ClearAll = 1
    BEGIN
        DBCC FREEPROCCACHE;
        SELECT 'All plans cleared from cache' AS Status;
        RETURN;
    END
    
    IF @PlanHandle IS NOT NULL
    BEGIN
        DBCC FREEPROCCACHE(@PlanHandle);
        SELECT 'Plan cleared using plan handle' AS Status;
        RETURN;
    END
    
    IF @SqlHandle IS NOT NULL
    BEGIN
        -- Find and clear plans for this SQL handle
        DECLARE @Handles TABLE (plan_handle VARBINARY(64));
        
        INSERT INTO @Handles
        SELECT DISTINCT plan_handle
        FROM sys.dm_exec_query_stats
        WHERE sql_handle = @SqlHandle;
        
        DECLARE @Handle VARBINARY(64);
        DECLARE HandleCursor CURSOR LOCAL FAST_FORWARD FOR SELECT plan_handle FROM @Handles;
        
        OPEN HandleCursor;
        FETCH NEXT FROM HandleCursor INTO @Handle;
        
        WHILE @@FETCH_STATUS = 0
        BEGIN
            DBCC FREEPROCCACHE(@Handle);
            FETCH NEXT FROM HandleCursor INTO @Handle;
        END
        
        CLOSE HandleCursor;
        DEALLOCATE HandleCursor;
        
        SELECT 'Plans cleared for SQL handle' AS Status, COUNT(*) AS PlansCleared FROM @Handles;
        RETURN;
    END
    
    IF @QueryText IS NOT NULL
    BEGIN
        -- Find matching queries
        SELECT 
            qs.plan_handle,
            qs.sql_handle,
            'DBCC FREEPROCCACHE(' + CONVERT(VARCHAR(MAX), qs.plan_handle, 1) + ')' AS ClearCommand
        FROM sys.dm_exec_query_stats qs
        CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
        WHERE st.text LIKE '%' + @QueryText + '%';
    END
END
GO

-- Get plan cache summary
CREATE PROCEDURE dbo.GetPlanCacheSummary
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Cache size by type
    SELECT 
        objtype AS ObjectType,
        COUNT(*) AS PlanCount,
        SUM(CAST(size_in_bytes AS BIGINT)) / 1024 / 1024 AS SizeMB,
        SUM(usecounts) AS TotalUseCount,
        AVG(usecounts) AS AvgUseCount
    FROM sys.dm_exec_cached_plans
    GROUP BY objtype
    ORDER BY SizeMB DESC;
    
    -- Single-use plans
    SELECT 
        'Single-Use Plans' AS Metric,
        COUNT(*) AS PlanCount,
        SUM(CAST(size_in_bytes AS BIGINT)) / 1024 / 1024 AS WastedSpaceMB
    FROM sys.dm_exec_cached_plans
    WHERE usecounts = 1;
    
    -- Top databases by cache usage
    SELECT TOP 10
        DB_NAME(st.dbid) AS DatabaseName,
        COUNT(*) AS PlanCount,
        SUM(CAST(cp.size_in_bytes AS BIGINT)) / 1024 / 1024 AS SizeMB
    FROM sys.dm_exec_cached_plans cp
    CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) st
    WHERE st.dbid IS NOT NULL
    GROUP BY st.dbid
    ORDER BY SizeMB DESC;
END
GO

-- Create plan guide
CREATE PROCEDURE dbo.CreateQueryPlanGuide
    @GuideName NVARCHAR(128),
    @QueryText NVARCHAR(MAX),
    @Hints NVARCHAR(MAX),  -- e.g., 'OPTION (RECOMPILE)' or 'OPTION (OPTIMIZE FOR UNKNOWN)'
    @DatabaseName NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @DatabaseName = ISNULL(@DatabaseName, DB_NAME());
    
    BEGIN TRY
        EXEC sp_create_plan_guide
            @name = @GuideName,
            @stmt = @QueryText,
            @type = N'SQL',
            @module_or_batch = NULL,
            @params = NULL,
            @hints = @Hints;
        
        SELECT 'Plan guide created successfully' AS Status, @GuideName AS GuideName;
    END TRY
    BEGIN CATCH
        SELECT 'Failed to create plan guide' AS Status, ERROR_MESSAGE() AS ErrorMessage;
    END CATCH
    
    -- Show existing plan guides
    SELECT 
        name AS GuideName,
        scope_type_desc AS ScopeType,
        is_disabled AS IsDisabled,
        query_text AS QueryText,
        hints AS Hints
    FROM sys.plan_guides
    WHERE name = @GuideName OR @GuideName IS NULL;
END
GO
