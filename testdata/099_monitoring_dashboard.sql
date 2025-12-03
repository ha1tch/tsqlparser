-- Sample 099: Real-Time Monitoring Dashboard
-- Source: Various - SQL Server DMVs, Performance monitoring patterns, Dashboard designs
-- Category: Performance
-- Complexity: Advanced
-- Features: Real-time metrics, dashboard data, alerts, KPIs, trend analysis

-- Get current server health dashboard
CREATE PROCEDURE dbo.GetServerHealthDashboard
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Overall health score
    DECLARE @CPUPercent INT, @MemoryPercent INT, @DiskLatency INT, @BlockedSessions INT;
    DECLARE @HealthScore INT;
    
    -- CPU
    SELECT TOP 1 @CPUPercent = 
        100 - record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int')
    FROM (
        SELECT CONVERT(XML, record) AS record
        FROM sys.dm_os_ring_buffers
        WHERE ring_buffer_type = 'RING_BUFFER_SCHEDULER_MONITOR'
        AND record LIKE '%<SystemHealth>%'
    ) AS x;
    
    -- Memory
    SELECT @MemoryPercent = 
        CAST((committed_kb * 100.0 / committed_target_kb) AS INT)
    FROM sys.dm_os_sys_info;
    
    -- Blocked sessions
    SELECT @BlockedSessions = COUNT(*)
    FROM sys.dm_exec_requests
    WHERE blocking_session_id > 0;
    
    -- Calculate health score
    SET @HealthScore = 100 
        - CASE WHEN @CPUPercent > 90 THEN 30 WHEN @CPUPercent > 75 THEN 15 ELSE 0 END
        - CASE WHEN @MemoryPercent > 95 THEN 25 WHEN @MemoryPercent > 85 THEN 10 ELSE 0 END
        - CASE WHEN @BlockedSessions > 10 THEN 25 WHEN @BlockedSessions > 5 THEN 15 WHEN @BlockedSessions > 0 THEN 5 ELSE 0 END;
    
    -- Return dashboard data
    SELECT 
        @HealthScore AS HealthScore,
        CASE 
            WHEN @HealthScore >= 90 THEN 'Excellent'
            WHEN @HealthScore >= 70 THEN 'Good'
            WHEN @HealthScore >= 50 THEN 'Fair'
            ELSE 'Poor'
        END AS HealthStatus,
        @CPUPercent AS CPUPercent,
        @MemoryPercent AS MemoryPercent,
        @BlockedSessions AS BlockedSessions,
        (SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process = 1) AS ActiveSessions,
        (SELECT cntr_value FROM sys.dm_os_performance_counters 
         WHERE counter_name = 'Batch Requests/sec') AS BatchRequestsPerSec,
        (SELECT COUNT(*) FROM sys.dm_exec_requests WHERE status = 'running') AS RunningQueries;
END
GO

-- Get real-time query activity
CREATE PROCEDURE dbo.GetLiveQueryActivity
    @MinDurationSeconds INT = 5
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        r.session_id AS SessionID,
        r.status AS Status,
        r.command AS Command,
        r.wait_type AS WaitType,
        r.wait_time / 1000 AS WaitTimeSeconds,
        DATEDIFF(SECOND, r.start_time, GETDATE()) AS DurationSeconds,
        r.cpu_time / 1000 AS CPUTimeSeconds,
        r.logical_reads AS LogicalReads,
        r.writes AS Writes,
        DB_NAME(r.database_id) AS DatabaseName,
        s.login_name AS LoginName,
        s.host_name AS HostName,
        s.program_name AS ApplicationName,
        r.blocking_session_id AS BlockingSession,
        r.percent_complete AS PercentComplete,
        SUBSTRING(st.text, (r.statement_start_offset/2) + 1,
            ((CASE r.statement_end_offset
                WHEN -1 THEN DATALENGTH(st.text)
                ELSE r.statement_end_offset
            END - r.statement_start_offset)/2) + 1) AS CurrentStatement,
        qp.query_plan AS ExecutionPlan
    FROM sys.dm_exec_requests r
    INNER JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
    CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) st
    OUTER APPLY sys.dm_exec_query_plan(r.plan_handle) qp
    WHERE r.session_id <> @@SPID
      AND s.is_user_process = 1
      AND DATEDIFF(SECOND, r.start_time, GETDATE()) >= @MinDurationSeconds
    ORDER BY DurationSeconds DESC;
END
GO

-- Get database activity summary
CREATE PROCEDURE dbo.GetDatabaseActivitySummary
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        DB_NAME(database_id) AS DatabaseName,
        COUNT(*) AS ActiveConnections,
        SUM(CASE WHEN status = 'running' THEN 1 ELSE 0 END) AS RunningQueries,
        SUM(CASE WHEN status = 'sleeping' THEN 1 ELSE 0 END) AS IdleConnections,
        SUM(cpu_time) / 1000 AS TotalCPUSeconds,
        SUM(logical_reads) AS TotalLogicalReads,
        SUM(writes) AS TotalWrites,
        MAX(total_elapsed_time) / 1000 AS MaxQueryDurationSeconds
    FROM sys.dm_exec_requests r
    INNER JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
    WHERE s.is_user_process = 1
    GROUP BY database_id
    ORDER BY TotalCPUSeconds DESC;
END
GO

-- Get wait statistics summary for dashboard
CREATE PROCEDURE dbo.GetWaitStatsSummary
    @TopN INT = 10
AS
BEGIN
    SET NOCOUNT ON;
    
    ;WITH WaitStats AS (
        SELECT 
            wait_type,
            wait_time_ms,
            waiting_tasks_count,
            signal_wait_time_ms,
            wait_time_ms - signal_wait_time_ms AS resource_wait_time_ms
        FROM sys.dm_os_wait_stats
        WHERE wait_type NOT IN (
            'CLR_SEMAPHORE', 'LAZYWRITER_SLEEP', 'RESOURCE_QUEUE',
            'SLEEP_TASK', 'SLEEP_SYSTEMTASK', 'SQLTRACE_BUFFER_FLUSH',
            'WAITFOR', 'LOGMGR_QUEUE', 'CHECKPOINT_QUEUE',
            'REQUEST_FOR_DEADLOCK_SEARCH', 'XE_TIMER_EVENT',
            'BROKER_TO_FLUSH', 'BROKER_TASK_STOP', 'CLR_MANUAL_EVENT',
            'DISPATCHER_QUEUE_SEMAPHORE', 'FT_IFTS_SCHEDULER_IDLE_WAIT',
            'XE_DISPATCHER_WAIT', 'XE_DISPATCHER_JOIN', 'SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
            'HADR_FILESTREAM_IOMGR_IOCOMPLETION', 'DIRTY_PAGE_POLL'
        )
        AND wait_time_ms > 0
    )
    SELECT TOP (@TopN)
        wait_type AS WaitType,
        CAST(wait_time_ms / 1000.0 AS DECIMAL(18,2)) AS WaitTimeSeconds,
        waiting_tasks_count AS WaitCount,
        CAST(wait_time_ms * 100.0 / SUM(wait_time_ms) OVER() AS DECIMAL(5,2)) AS WaitPercent,
        CAST(resource_wait_time_ms / 1000.0 AS DECIMAL(18,2)) AS ResourceWaitSeconds,
        CAST(signal_wait_time_ms / 1000.0 AS DECIMAL(18,2)) AS SignalWaitSeconds,
        CASE 
            WHEN wait_type LIKE 'LCK%' THEN 'Locking'
            WHEN wait_type LIKE 'PAGEIO%' OR wait_type LIKE 'WRITELOG%' THEN 'Disk IO'
            WHEN wait_type LIKE 'ASYNC_NETWORK%' THEN 'Network'
            WHEN wait_type LIKE 'CXPACKET%' THEN 'Parallelism'
            WHEN wait_type LIKE 'SOS_SCHEDULER%' THEN 'CPU'
            ELSE 'Other'
        END AS WaitCategory
    FROM WaitStats
    ORDER BY wait_time_ms DESC;
END
GO

-- Generate alert if thresholds exceeded
CREATE PROCEDURE dbo.CheckAlertThresholds
    @CPUThreshold INT = 90,
    @MemoryThreshold INT = 95,
    @BlockingThreshold INT = 5,
    @LongQueryThreshold INT = 300  -- seconds
AS
BEGIN
    SET NOCOUNT ON;
    
    CREATE TABLE #Alerts (
        AlertTime DATETIME2 DEFAULT SYSDATETIME(),
        AlertType NVARCHAR(50),
        Severity NVARCHAR(20),
        Message NVARCHAR(500),
        CurrentValue NVARCHAR(50),
        Threshold NVARCHAR(50)
    );
    
    -- CPU check
    DECLARE @CurrentCPU INT;
    SELECT TOP 1 @CurrentCPU = 
        100 - record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int')
    FROM (
        SELECT CONVERT(XML, record) AS record
        FROM sys.dm_os_ring_buffers
        WHERE ring_buffer_type = 'RING_BUFFER_SCHEDULER_MONITOR'
    ) AS x;
    
    IF @CurrentCPU > @CPUThreshold
        INSERT INTO #Alerts (AlertType, Severity, Message, CurrentValue, Threshold)
        VALUES ('High CPU', 'Critical', 'CPU usage exceeds threshold', CAST(@CurrentCPU AS VARCHAR(10)) + '%', CAST(@CPUThreshold AS VARCHAR(10)) + '%');
    
    -- Memory check
    DECLARE @CurrentMemory INT;
    SELECT @CurrentMemory = CAST((committed_kb * 100.0 / committed_target_kb) AS INT) FROM sys.dm_os_sys_info;
    
    IF @CurrentMemory > @MemoryThreshold
        INSERT INTO #Alerts (AlertType, Severity, Message, CurrentValue, Threshold)
        VALUES ('High Memory', 'Warning', 'Memory usage exceeds threshold', CAST(@CurrentMemory AS VARCHAR(10)) + '%', CAST(@MemoryThreshold AS VARCHAR(10)) + '%');
    
    -- Blocking check
    DECLARE @BlockedCount INT;
    SELECT @BlockedCount = COUNT(*) FROM sys.dm_exec_requests WHERE blocking_session_id > 0;
    
    IF @BlockedCount > @BlockingThreshold
        INSERT INTO #Alerts (AlertType, Severity, Message, CurrentValue, Threshold)
        VALUES ('Blocking', 'Warning', 'Multiple blocked sessions detected', CAST(@BlockedCount AS VARCHAR(10)), CAST(@BlockingThreshold AS VARCHAR(10)));
    
    -- Long running queries
    IF EXISTS (SELECT 1 FROM sys.dm_exec_requests WHERE DATEDIFF(SECOND, start_time, GETDATE()) > @LongQueryThreshold)
        INSERT INTO #Alerts (AlertType, Severity, Message, CurrentValue, Threshold)
        VALUES ('Long Query', 'Warning', 'Query running longer than threshold', 
                (SELECT CAST(MAX(DATEDIFF(SECOND, start_time, GETDATE())) AS VARCHAR(10)) + 's' FROM sys.dm_exec_requests),
                CAST(@LongQueryThreshold AS VARCHAR(10)) + 's');
    
    SELECT * FROM #Alerts ORDER BY Severity;
    
    DROP TABLE #Alerts;
END
GO

-- Get IO performance metrics
CREATE PROCEDURE dbo.GetIOPerformanceMetrics
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        DB_NAME(vfs.database_id) AS DatabaseName,
        mf.name AS FileName,
        mf.physical_name AS PhysicalPath,
        mf.type_desc AS FileType,
        vfs.num_of_reads AS Reads,
        vfs.num_of_writes AS Writes,
        CAST(vfs.io_stall_read_ms / NULLIF(vfs.num_of_reads, 0) AS DECIMAL(10,2)) AS AvgReadLatencyMs,
        CAST(vfs.io_stall_write_ms / NULLIF(vfs.num_of_writes, 0) AS DECIMAL(10,2)) AS AvgWriteLatencyMs,
        CAST(vfs.num_of_bytes_read / 1024.0 / 1024.0 AS DECIMAL(18,2)) AS TotalReadMB,
        CAST(vfs.num_of_bytes_written / 1024.0 / 1024.0 AS DECIMAL(18,2)) AS TotalWrittenMB,
        CASE 
            WHEN vfs.io_stall_read_ms / NULLIF(vfs.num_of_reads, 0) > 20 THEN 'Slow'
            WHEN vfs.io_stall_read_ms / NULLIF(vfs.num_of_reads, 0) > 10 THEN 'Moderate'
            ELSE 'Good'
        END AS ReadPerformance
    FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
    INNER JOIN sys.master_files mf ON vfs.database_id = mf.database_id AND vfs.file_id = mf.file_id
    ORDER BY vfs.io_stall DESC;
END
GO
