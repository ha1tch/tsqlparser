-- Sample 026: Query Store Analysis Procedures
-- Source: Microsoft Learn, Brent Ozar, MSSQLTips
-- Category: Performance
-- Complexity: Advanced
-- Features: Query Store DMVs, plan forcing, regression detection

-- Get top resource-consuming queries from Query Store
CREATE PROCEDURE dbo.GetQueryStoreTopQueries
    @TopN INT = 20,
    @MetricName NVARCHAR(50) = 'duration',  -- duration, cpu_time, logical_io_reads, execution_count
    @TimeRange INT = 24,  -- hours
    @MinExecutionCount INT = 10
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @StartTime DATETIMEOFFSET = DATEADD(HOUR, -@TimeRange, SYSDATETIMEOFFSET());
    
    SELECT TOP (@TopN)
        q.query_id,
        qt.query_sql_text,
        OBJECT_NAME(q.object_id) AS ObjectName,
        rs.count_executions AS ExecutionCount,
        rs.avg_duration / 1000.0 AS AvgDurationMs,
        rs.avg_cpu_time / 1000.0 AS AvgCpuMs,
        rs.avg_logical_io_reads AS AvgLogicalReads,
        rs.avg_logical_io_writes AS AvgLogicalWrites,
        rs.avg_physical_io_reads AS AvgPhysicalReads,
        rs.avg_rowcount AS AvgRowCount,
        rs.avg_query_max_used_memory AS AvgMemoryKB,
        p.plan_id,
        p.is_forced_plan AS IsForcedPlan,
        p.force_failure_count AS ForceFailures,
        TRY_CAST(p.query_plan AS XML) AS QueryPlan,
        q.query_hash,
        p.query_plan_hash
    FROM sys.query_store_query q
    INNER JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
    INNER JOIN sys.query_store_plan p ON q.query_id = p.query_id
    INNER JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
    INNER JOIN sys.query_store_runtime_stats_interval rsi ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
    WHERE rsi.start_time >= @StartTime
      AND rs.count_executions >= @MinExecutionCount
    ORDER BY 
        CASE @MetricName
            WHEN 'duration' THEN rs.avg_duration * rs.count_executions
            WHEN 'cpu_time' THEN rs.avg_cpu_time * rs.count_executions
            WHEN 'logical_io_reads' THEN rs.avg_logical_io_reads * rs.count_executions
            WHEN 'execution_count' THEN rs.count_executions
            ELSE rs.avg_duration * rs.count_executions
        END DESC;
END
GO

-- Detect regressed queries (plan changes causing performance degradation)
CREATE PROCEDURE dbo.DetectRegressedQueries
    @RecentHours INT = 24,
    @HistoryHours INT = 168,  -- 1 week
    @RegressionThreshold FLOAT = 2.0  -- 2x worse is considered regression
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @RecentStart DATETIMEOFFSET = DATEADD(HOUR, -@RecentHours, SYSDATETIMEOFFSET());
    DECLARE @HistoryStart DATETIMEOFFSET = DATEADD(HOUR, -@HistoryHours, SYSDATETIMEOFFSET());
    
    ;WITH RecentStats AS (
        SELECT 
            p.query_id,
            p.plan_id,
            AVG(rs.avg_duration) AS AvgDuration,
            AVG(rs.avg_cpu_time) AS AvgCpu,
            SUM(rs.count_executions) AS Executions
        FROM sys.query_store_plan p
        INNER JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
        INNER JOIN sys.query_store_runtime_stats_interval rsi ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
        WHERE rsi.start_time >= @RecentStart
        GROUP BY p.query_id, p.plan_id
    ),
    HistoryStats AS (
        SELECT 
            p.query_id,
            AVG(rs.avg_duration) AS AvgDuration,
            AVG(rs.avg_cpu_time) AS AvgCpu,
            SUM(rs.count_executions) AS Executions
        FROM sys.query_store_plan p
        INNER JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
        INNER JOIN sys.query_store_runtime_stats_interval rsi ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
        WHERE rsi.start_time >= @HistoryStart
          AND rsi.start_time < @RecentStart
        GROUP BY p.query_id
    )
    SELECT 
        q.query_id,
        qt.query_sql_text,
        OBJECT_NAME(q.object_id) AS ObjectName,
        r.plan_id AS CurrentPlanID,
        h.AvgDuration / 1000.0 AS HistoricalAvgDurationMs,
        r.AvgDuration / 1000.0 AS RecentAvgDurationMs,
        r.AvgDuration / NULLIF(h.AvgDuration, 0) AS DurationRegressionFactor,
        h.AvgCpu / 1000.0 AS HistoricalAvgCpuMs,
        r.AvgCpu / 1000.0 AS RecentAvgCpuMs,
        r.AvgCpu / NULLIF(h.AvgCpu, 0) AS CpuRegressionFactor,
        r.Executions AS RecentExecutions,
        h.Executions AS HistoricalExecutions
    FROM RecentStats r
    INNER JOIN HistoryStats h ON r.query_id = h.query_id
    INNER JOIN sys.query_store_query q ON r.query_id = q.query_id
    INNER JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
    WHERE r.AvgDuration > h.AvgDuration * @RegressionThreshold
       OR r.AvgCpu > h.AvgCpu * @RegressionThreshold
    ORDER BY r.AvgDuration / NULLIF(h.AvgDuration, 0) DESC;
END
GO

-- Force or unforce a query plan
CREATE PROCEDURE dbo.ManageQueryPlan
    @QueryID BIGINT,
    @PlanID BIGINT,
    @Action NVARCHAR(20) = 'FORCE'  -- FORCE, UNFORCE
AS
BEGIN
    SET NOCOUNT ON;
    
    IF @Action = 'FORCE'
    BEGIN
        EXEC sp_query_store_force_plan @query_id = @QueryID, @plan_id = @PlanID;
        PRINT 'Plan ' + CAST(@PlanID AS VARCHAR(20)) + ' forced for query ' + CAST(@QueryID AS VARCHAR(20));
    END
    ELSE IF @Action = 'UNFORCE'
    BEGIN
        EXEC sp_query_store_unforce_plan @query_id = @QueryID, @plan_id = @PlanID;
        PRINT 'Plan ' + CAST(@PlanID AS VARCHAR(20)) + ' unforced for query ' + CAST(@QueryID AS VARCHAR(20));
    END
    
    -- Return current status
    SELECT 
        p.query_id,
        p.plan_id,
        p.is_forced_plan,
        p.force_failure_count,
        p.last_force_failure_reason_desc,
        p.plan_forcing_type_desc
    FROM sys.query_store_plan p
    WHERE p.query_id = @QueryID AND p.plan_id = @PlanID;
END
GO

-- Get Query Store configuration and status
CREATE PROCEDURE dbo.GetQueryStoreStatus
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Configuration
    SELECT 
        DB_NAME() AS DatabaseName,
        desired_state_desc AS DesiredState,
        actual_state_desc AS ActualState,
        readonly_reason,
        current_storage_size_mb AS CurrentSizeMB,
        max_storage_size_mb AS MaxSizeMB,
        CAST(current_storage_size_mb * 100.0 / NULLIF(max_storage_size_mb, 0) AS DECIMAL(5,2)) AS UsedPercent,
        flush_interval_seconds AS FlushIntervalSec,
        interval_length_minutes AS IntervalLengthMin,
        stale_query_threshold_days AS StaleThresholdDays,
        query_capture_mode_desc AS CaptureMode,
        size_based_cleanup_mode_desc AS CleanupMode,
        max_plans_per_query AS MaxPlansPerQuery,
        wait_stats_capture_mode_desc AS WaitStatsMode
    FROM sys.database_query_store_options;
    
    -- Summary statistics
    SELECT 
        COUNT(DISTINCT q.query_id) AS TotalQueries,
        COUNT(DISTINCT p.plan_id) AS TotalPlans,
        SUM(CASE WHEN p.is_forced_plan = 1 THEN 1 ELSE 0 END) AS ForcedPlans,
        COUNT(DISTINCT rs.runtime_stats_id) AS RuntimeStatsRecords
    FROM sys.query_store_query q
    LEFT JOIN sys.query_store_plan p ON q.query_id = p.query_id
    LEFT JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id;
END
GO

-- Compare two plans for the same query
CREATE PROCEDURE dbo.CompareQueryPlans
    @QueryID BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        p.plan_id,
        p.is_forced_plan,
        p.is_online_index_plan,
        p.force_failure_count,
        p.last_compile_start_time,
        p.last_execution_time,
        rs.count_executions AS Executions,
        rs.avg_duration / 1000.0 AS AvgDurationMs,
        rs.avg_cpu_time / 1000.0 AS AvgCpuMs,
        rs.avg_logical_io_reads AS AvgReads,
        rs.avg_logical_io_writes AS AvgWrites,
        rs.avg_rowcount AS AvgRows,
        rs.stdev_duration / 1000.0 AS StdDevDurationMs,
        rs.min_duration / 1000.0 AS MinDurationMs,
        rs.max_duration / 1000.0 AS MaxDurationMs,
        TRY_CAST(p.query_plan AS XML) AS QueryPlan
    FROM sys.query_store_plan p
    CROSS APPLY (
        SELECT 
            SUM(count_executions) AS count_executions,
            AVG(avg_duration) AS avg_duration,
            AVG(avg_cpu_time) AS avg_cpu_time,
            AVG(avg_logical_io_reads) AS avg_logical_io_reads,
            AVG(avg_logical_io_writes) AS avg_logical_io_writes,
            AVG(avg_rowcount) AS avg_rowcount,
            AVG(stdev_duration) AS stdev_duration,
            MIN(min_duration) AS min_duration,
            MAX(max_duration) AS max_duration
        FROM sys.query_store_runtime_stats
        WHERE plan_id = p.plan_id
    ) rs
    WHERE p.query_id = @QueryID
    ORDER BY rs.avg_duration;
END
GO
