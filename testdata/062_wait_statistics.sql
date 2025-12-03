-- Sample 062: Wait Statistics Analysis
-- Source: Paul Randal, Brent Ozar, Microsoft Learn
-- Category: Performance
-- Complexity: Advanced
-- Features: sys.dm_os_wait_stats, wait type analysis, baseline comparison

-- Get current wait statistics
CREATE PROCEDURE dbo.GetWaitStatistics
    @TopN INT = 25,
    @ExcludeIdleWaits BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    ;WITH WaitStats AS (
        SELECT 
            wait_type,
            waiting_tasks_count,
            wait_time_ms,
            max_wait_time_ms,
            signal_wait_time_ms,
            wait_time_ms - signal_wait_time_ms AS resource_wait_time_ms
        FROM sys.dm_os_wait_stats
        WHERE (@ExcludeIdleWaits = 0 OR wait_type NOT IN (
            'BROKER_EVENTHANDLER', 'BROKER_RECEIVE_WAITFOR', 'BROKER_TASK_STOP',
            'BROKER_TO_FLUSH', 'BROKER_TRANSMITTER', 'CHECKPOINT_QUEUE',
            'CHKPT', 'CLR_AUTO_EVENT', 'CLR_MANUAL_EVENT', 'CLR_SEMAPHORE',
            'DBMIRROR_DBM_EVENT', 'DBMIRROR_EVENTS_QUEUE', 'DBMIRROR_WORKER_QUEUE',
            'DBMIRRORING_CMD', 'DIRTY_PAGE_POLL', 'DISPATCHER_QUEUE_SEMAPHORE',
            'EXECSYNC', 'FSAGENT', 'FT_IFTS_SCHEDULER_IDLE_WAIT', 'FT_IFTSHC_MUTEX',
            'HADR_CLUSAPI_CALL', 'HADR_FILESTREAM_IOMGR_IOCOMPLETION', 'HADR_LOGCAPTURE_WAIT',
            'HADR_NOTIFICATION_DEQUEUE', 'HADR_TIMER_TASK', 'HADR_WORK_QUEUE',
            'KSOURCE_WAKEUP', 'LAZYWRITER_SLEEP', 'LOGMGR_QUEUE',
            'MEMORY_ALLOCATION_EXT', 'ONDEMAND_TASK_QUEUE', 'PREEMPTIVE_OS_LIBRARYOPS',
            'PREEMPTIVE_OS_COMOPS', 'PREEMPTIVE_OS_CRYPTOPS', 'PREEMPTIVE_OS_PIPEOPS',
            'PREEMPTIVE_OS_AUTHENTICATIONOPS', 'PREEMPTIVE_OS_GENERICOPS',
            'PREEMPTIVE_OS_VERIFYTRUST', 'PREEMPTIVE_OS_FILEOPS', 'PREEMPTIVE_OS_DEVICEOPS',
            'PREEMPTIVE_OS_QUERYREGISTRY', 'PREEMPTIVE_OS_WRITEFILE',
            'PREEMPTIVE_XE_CALLBACKEXECUTE', 'PREEMPTIVE_XE_DISPATCHER',
            'PREEMPTIVE_XE_GETTARGETSTATE', 'PREEMPTIVE_XE_SESSIONCOMMIT',
            'PREEMPTIVE_XE_TARGETINIT', 'PREEMPTIVE_XE_TARGETFINALIZE',
            'PWAIT_ALL_COMPONENTS_INITIALIZED', 'PWAIT_DIRECTLOGCONSUMER_GETNEXT',
            'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', 'QDS_ASYNC_QUEUE',
            'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP', 'REQUEST_FOR_DEADLOCK_SEARCH',
            'RESOURCE_QUEUE', 'SERVER_IDLE_CHECK', 'SLEEP_BPOOL_FLUSH', 'SLEEP_DBSTARTUP',
            'SLEEP_DCOMSTARTUP', 'SLEEP_MASTERDBREADY', 'SLEEP_MASTERMDREADY',
            'SLEEP_MASTERUPGRADED', 'SLEEP_MSDBSTARTUP', 'SLEEP_SYSTEMTASK',
            'SLEEP_TASK', 'SLEEP_TEMPDBSTARTUP', 'SNI_HTTP_ACCEPT', 'SP_SERVER_DIAGNOSTICS_SLEEP',
            'SQLTRACE_BUFFER_FLUSH', 'SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
            'SQLTRACE_WAIT_ENTRIES', 'WAIT_FOR_RESULTS', 'WAITFOR',
            'WAITFOR_TASKSHUTDOWN', 'WAIT_XTP_HOST_WAIT', 'WAIT_XTP_OFFLINE_CKPT_NEW_LOG',
            'WAIT_XTP_CKPT_CLOSE', 'XE_DISPATCHER_JOIN', 'XE_DISPATCHER_WAIT',
            'XE_TIMER_EVENT'
        ))
          AND wait_time_ms > 0
    ),
    TotalWaits AS (
        SELECT SUM(wait_time_ms) AS TotalWaitMs FROM WaitStats
    )
    SELECT TOP (@TopN)
        w.wait_type AS WaitType,
        w.waiting_tasks_count AS WaitCount,
        CAST(w.wait_time_ms / 1000.0 AS DECIMAL(18,2)) AS TotalWaitSec,
        CAST(w.resource_wait_time_ms / 1000.0 AS DECIMAL(18,2)) AS ResourceWaitSec,
        CAST(w.signal_wait_time_ms / 1000.0 AS DECIMAL(18,2)) AS SignalWaitSec,
        CAST(w.wait_time_ms * 100.0 / t.TotalWaitMs AS DECIMAL(5,2)) AS WaitPercent,
        CAST(w.wait_time_ms / NULLIF(w.waiting_tasks_count, 0) AS DECIMAL(18,2)) AS AvgWaitMs,
        w.max_wait_time_ms AS MaxWaitMs,
        CASE 
            WHEN w.wait_type LIKE 'LCK%' THEN 'Locking'
            WHEN w.wait_type LIKE 'PAGEIO%' OR w.wait_type LIKE 'WRITELOG%' THEN 'I/O'
            WHEN w.wait_type LIKE 'ASYNC_NETWORK%' THEN 'Network'
            WHEN w.wait_type LIKE 'CXPACKET%' OR w.wait_type LIKE 'CXCONSUMER%' THEN 'Parallelism'
            WHEN w.wait_type LIKE 'LATCH%' THEN 'Latch'
            WHEN w.wait_type LIKE 'PAGELATCH%' THEN 'Buffer Latch'
            ELSE 'Other'
        END AS WaitCategory
    FROM WaitStats w
    CROSS JOIN TotalWaits t
    ORDER BY w.wait_time_ms DESC;
END
GO

-- Capture wait stats baseline
CREATE PROCEDURE dbo.CaptureWaitStatsBaseline
    @BaselineName NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Create baseline table if not exists
    IF OBJECT_ID('dbo.WaitStatsBaseline', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.WaitStatsBaseline (
            BaselineID INT IDENTITY(1,1),
            BaselineName NVARCHAR(100),
            CaptureTime DATETIME2 DEFAULT SYSDATETIME(),
            wait_type NVARCHAR(60),
            waiting_tasks_count BIGINT,
            wait_time_ms BIGINT,
            max_wait_time_ms BIGINT,
            signal_wait_time_ms BIGINT,
            PRIMARY KEY (BaselineID, wait_type)
        );
    END
    
    SET @BaselineName = ISNULL(@BaselineName, 'Baseline_' + FORMAT(SYSDATETIME(), 'yyyyMMdd_HHmmss'));
    
    INSERT INTO dbo.WaitStatsBaseline (BaselineName, wait_type, waiting_tasks_count, wait_time_ms, max_wait_time_ms, signal_wait_time_ms)
    SELECT 
        @BaselineName,
        wait_type,
        waiting_tasks_count,
        wait_time_ms,
        max_wait_time_ms,
        signal_wait_time_ms
    FROM sys.dm_os_wait_stats
    WHERE wait_time_ms > 0;
    
    SELECT 'Baseline captured' AS Status, @BaselineName AS BaselineName, @@ROWCOUNT AS WaitTypesCaptured;
END
GO

-- Compare current waits to baseline
CREATE PROCEDURE dbo.CompareWaitStatsToBaseline
    @BaselineName NVARCHAR(100),
    @TopN INT = 25
AS
BEGIN
    SET NOCOUNT ON;
    
    ;WITH CurrentWaits AS (
        SELECT 
            wait_type,
            waiting_tasks_count,
            wait_time_ms,
            signal_wait_time_ms
        FROM sys.dm_os_wait_stats
    ),
    BaselineWaits AS (
        SELECT 
            wait_type,
            waiting_tasks_count,
            wait_time_ms,
            signal_wait_time_ms
        FROM dbo.WaitStatsBaseline
        WHERE BaselineName = @BaselineName
    )
    SELECT TOP (@TopN)
        COALESCE(c.wait_type, b.wait_type) AS WaitType,
        ISNULL(c.wait_time_ms, 0) - ISNULL(b.wait_time_ms, 0) AS WaitTimeDeltaMs,
        ISNULL(c.waiting_tasks_count, 0) - ISNULL(b.waiting_tasks_count, 0) AS WaitCountDelta,
        CAST((ISNULL(c.wait_time_ms, 0) - ISNULL(b.wait_time_ms, 0)) / 1000.0 AS DECIMAL(18,2)) AS WaitTimeDeltaSec,
        b.wait_time_ms AS BaselineMs,
        c.wait_time_ms AS CurrentMs,
        CASE 
            WHEN b.wait_time_ms > 0 
            THEN CAST((c.wait_time_ms - b.wait_time_ms) * 100.0 / b.wait_time_ms AS DECIMAL(10,2))
            ELSE NULL
        END AS PercentChange
    FROM CurrentWaits c
    FULL OUTER JOIN BaselineWaits b ON c.wait_type = b.wait_type
    WHERE ISNULL(c.wait_time_ms, 0) - ISNULL(b.wait_time_ms, 0) <> 0
    ORDER BY ABS(ISNULL(c.wait_time_ms, 0) - ISNULL(b.wait_time_ms, 0)) DESC;
END
GO

-- Get wait stats recommendations
CREATE PROCEDURE dbo.GetWaitStatsRecommendations
AS
BEGIN
    SET NOCOUNT ON;
    
    ;WITH TopWaits AS (
        SELECT TOP 10
            wait_type,
            wait_time_ms,
            ROW_NUMBER() OVER (ORDER BY wait_time_ms DESC) AS WaitRank
        FROM sys.dm_os_wait_stats
        WHERE wait_type NOT LIKE '%SLEEP%'
          AND wait_type NOT LIKE '%IDLE%'
          AND wait_type NOT LIKE '%QUEUE%'
          AND wait_time_ms > 0
    )
    SELECT 
        WaitRank,
        wait_type AS WaitType,
        CAST(wait_time_ms / 1000.0 AS DECIMAL(18,2)) AS WaitTimeSec,
        CASE 
            WHEN wait_type IN ('CXPACKET', 'CXCONSUMER') THEN 
                'Parallelism wait - Consider adjusting MAXDOP or Cost Threshold for Parallelism'
            WHEN wait_type LIKE 'LCK%' THEN 
                'Lock contention - Review blocking queries, consider query optimization or isolation level changes'
            WHEN wait_type = 'PAGEIOLATCH_SH' THEN 
                'Reading pages from disk - May need more memory or faster I/O subsystem'
            WHEN wait_type = 'PAGEIOLATCH_EX' THEN 
                'Writing pages to disk - Check for I/O bottlenecks'
            WHEN wait_type = 'WRITELOG' THEN 
                'Transaction log writes - Consider faster log storage or batching transactions'
            WHEN wait_type = 'ASYNC_NETWORK_IO' THEN 
                'Network delays or slow client processing - Check network and client application'
            WHEN wait_type LIKE 'PAGELATCH%' THEN 
                'In-memory page contention - May indicate tempdb or allocation contention'
            WHEN wait_type = 'SOS_SCHEDULER_YIELD' THEN 
                'CPU pressure - Queries running long without yielding'
            WHEN wait_type = 'THREADPOOL' THEN 
                'Thread starvation - May need to increase max worker threads'
            WHEN wait_type LIKE 'LATCH%' THEN 
                'Internal latch contention - May need further investigation'
            ELSE 'Review Microsoft documentation for specific wait type guidance'
        END AS Recommendation
    FROM TopWaits
    ORDER BY WaitRank;
END
GO

-- Clear wait statistics
CREATE PROCEDURE dbo.ClearWaitStatistics
AS
BEGIN
    SET NOCOUNT ON;
    
    DBCC SQLPERF('sys.dm_os_wait_stats', CLEAR);
    
    SELECT 'Wait statistics cleared at ' + CONVERT(VARCHAR(30), SYSDATETIME(), 121) AS Status;
END
GO
