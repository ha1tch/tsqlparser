-- Sample 082: Deadlock Analysis and Prevention
-- Source: Microsoft Learn, Brent Ozar, Jonathan Kehayias
-- Category: Error Handling
-- Complexity: Advanced
-- Features: Deadlock graphs, system_health, deadlock prevention strategies

-- Get recent deadlocks from system_health
CREATE PROCEDURE dbo.GetRecentDeadlocks
    @HoursBack INT = 24
AS
BEGIN
    SET NOCOUNT ON;
    
    ;WITH DeadlockEvents AS (
        SELECT 
            XEvent.query('.') AS DeadlockGraph,
            XEvent.value('@timestamp', 'DATETIME2') AS DeadlockTime
        FROM (
            SELECT CAST(target_data AS XML) AS TargetData
            FROM sys.dm_xe_session_targets st
            INNER JOIN sys.dm_xe_sessions s ON st.event_session_address = s.address
            WHERE s.name = 'system_health'
              AND st.target_name = 'ring_buffer'
        ) AS Data
        CROSS APPLY TargetData.nodes('RingBufferTarget/event[@name="xml_deadlock_report"]') AS XEventData(XEvent)
    )
    SELECT 
        DeadlockTime,
        DeadlockGraph.value('(event/data[@name="xml_report"]/value)[1]', 'NVARCHAR(MAX)') AS DeadlockXML
    FROM DeadlockEvents
    WHERE DeadlockTime >= DATEADD(HOUR, -@HoursBack, SYSDATETIME())
    ORDER BY DeadlockTime DESC;
END
GO

-- Parse deadlock graph for details
CREATE PROCEDURE dbo.ParseDeadlockGraph
    @DeadlockXML NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @XML XML = CAST(@DeadlockXML AS XML);
    
    -- Processes involved
    SELECT 
        Process.value('@id', 'VARCHAR(50)') AS ProcessId,
        Process.value('@spid', 'INT') AS SPID,
        Process.value('@loginname', 'VARCHAR(128)') AS LoginName,
        Process.value('@hostname', 'VARCHAR(128)') AS HostName,
        Process.value('@clientapp', 'VARCHAR(256)') AS ClientApp,
        Process.value('(inputbuf)[1]', 'NVARCHAR(MAX)') AS InputBuffer,
        Process.value('@waitresource', 'VARCHAR(256)') AS WaitResource,
        Process.value('@waittime', 'INT') AS WaitTimeMs,
        Process.value('@transactionname', 'VARCHAR(128)') AS TransactionName,
        Process.value('@isolationlevel', 'VARCHAR(50)') AS IsolationLevel
    FROM @XML.nodes('//deadlock/process-list/process') AS DeadlockData(Process);
    
    -- Resources involved
    SELECT 
        Resource.value('local-name(.)', 'VARCHAR(50)') AS ResourceType,
        Resource.value('@objectname', 'VARCHAR(256)') AS ObjectName,
        Resource.value('@indexname', 'VARCHAR(256)') AS IndexName,
        Resource.value('@mode', 'VARCHAR(50)') AS LockMode,
        OwnerList.value('@id', 'VARCHAR(50)') AS OwnerProcessId,
        OwnerList.value('@mode', 'VARCHAR(50)') AS OwnerMode,
        WaiterList.value('@id', 'VARCHAR(50)') AS WaiterProcessId,
        WaiterList.value('@mode', 'VARCHAR(50)') AS WaiterMode
    FROM @XML.nodes('//deadlock/resource-list/*') AS ResourceData(Resource)
    OUTER APPLY Resource.nodes('owner-list/owner') AS Owners(OwnerList)
    OUTER APPLY Resource.nodes('waiter-list/waiter') AS Waiters(WaiterList);
END
GO

-- Find potential deadlock candidates
CREATE PROCEDURE dbo.FindDeadlockRisks
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Long-running transactions
    SELECT 
        'Long Running Transaction' AS RiskType,
        s.session_id AS SessionId,
        s.login_name AS LoginName,
        s.host_name AS HostName,
        DB_NAME(dt.database_id) AS DatabaseName,
        dt.database_transaction_begin_time AS TransactionStart,
        DATEDIFF(SECOND, dt.database_transaction_begin_time, GETDATE()) AS DurationSeconds,
        t.text AS LastQuery
    FROM sys.dm_tran_database_transactions dt
    INNER JOIN sys.dm_tran_session_transactions st ON dt.transaction_id = st.transaction_id
    INNER JOIN sys.dm_exec_sessions s ON st.session_id = s.session_id
    OUTER APPLY sys.dm_exec_sql_text(s.most_recent_sql_handle) t
    WHERE dt.database_transaction_begin_time IS NOT NULL
      AND DATEDIFF(SECOND, dt.database_transaction_begin_time, GETDATE()) > 60;
    
    -- Sessions with many locks
    SELECT 
        'High Lock Count' AS RiskType,
        r.session_id AS SessionId,
        s.login_name AS LoginName,
        DB_NAME(r.database_id) AS DatabaseName,
        COUNT(*) AS LockCount,
        t.text AS CurrentQuery
    FROM sys.dm_tran_locks l
    INNER JOIN sys.dm_exec_requests r ON l.request_session_id = r.session_id
    INNER JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
    OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
    WHERE l.request_session_id <> @@SPID
    GROUP BY r.session_id, s.login_name, r.database_id, t.text
    HAVING COUNT(*) > 100
    ORDER BY LockCount DESC;
    
    -- Blocked sessions
    SELECT 
        'Currently Blocked' AS RiskType,
        r.session_id AS BlockedSession,
        r.blocking_session_id AS BlockingSession,
        r.wait_type AS WaitType,
        r.wait_time / 1000 AS WaitSeconds,
        DB_NAME(r.database_id) AS DatabaseName,
        blocked.text AS BlockedQuery,
        blocking.text AS BlockingQuery
    FROM sys.dm_exec_requests r
    INNER JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
    OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) blocked
    OUTER APPLY (
        SELECT sql_handle FROM sys.dm_exec_requests WHERE session_id = r.blocking_session_id
    ) br
    OUTER APPLY sys.dm_exec_sql_text(br.sql_handle) blocking
    WHERE r.blocking_session_id <> 0;
END
GO

-- Create deadlock-resistant wrapper
CREATE PROCEDURE dbo.ExecuteWithDeadlockRetry
    @SQL NVARCHAR(MAX),
    @MaxRetries INT = 3,
    @RetryDelayMs INT = 500
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @RetryCount INT = 0;
    DECLARE @Success BIT = 0;
    DECLARE @ErrorMessage NVARCHAR(MAX);
    DECLARE @ErrorNumber INT;
    
    WHILE @RetryCount < @MaxRetries AND @Success = 0
    BEGIN
        BEGIN TRY
            EXEC sp_executesql @SQL;
            SET @Success = 1;
        END TRY
        BEGIN CATCH
            SET @ErrorNumber = ERROR_NUMBER();
            SET @ErrorMessage = ERROR_MESSAGE();
            
            -- 1205 = Deadlock victim
            IF @ErrorNumber = 1205
            BEGIN
                SET @RetryCount = @RetryCount + 1;
                
                IF @RetryCount < @MaxRetries
                BEGIN
                    -- Wait before retry with exponential backoff
                    DECLARE @Delay INT = @RetryDelayMs * POWER(2, @RetryCount - 1);
                    DECLARE @DelayStr VARCHAR(12) = '00:00:00.' + RIGHT('000' + CAST(@Delay AS VARCHAR(3)), 3);
                    WAITFOR DELAY @DelayStr;
                END
            END
            ELSE
            BEGIN
                -- Not a deadlock, rethrow
                THROW;
            END
        END CATCH
    END
    
    IF @Success = 0
    BEGIN
        RAISERROR('Failed after %d deadlock retries. Last error: %s', 16, 1, @MaxRetries, @ErrorMessage);
    END
    
    SELECT @Success AS Success, @RetryCount AS RetriesUsed;
END
GO

-- Deadlock prevention recommendations
CREATE PROCEDURE dbo.GetDeadlockPreventionTips
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT TipNumber, Category, Recommendation, Implementation
    FROM (VALUES
        (1, 'Query Order', 'Access objects in consistent order', 'Always access tables alphabetically or by a defined sequence across all procedures'),
        (2, 'Transaction Length', 'Keep transactions short', 'Minimize work inside BEGIN TRAN...COMMIT; move reads outside when possible'),
        (3, 'Isolation Level', 'Use appropriate isolation', 'Consider READ COMMITTED SNAPSHOT or SNAPSHOT isolation to reduce locks'),
        (4, 'Lock Hints', 'Use NOLOCK or READPAST carefully', 'For reporting queries that can tolerate dirty reads, use WITH (NOLOCK)'),
        (5, 'Indexes', 'Ensure proper indexing', 'Missing indexes cause table scans which hold locks longer'),
        (6, 'Batch Size', 'Process in smaller batches', 'Update/delete in batches of 1000-5000 rows to reduce lock scope'),
        (7, 'Lock Escalation', 'Prevent lock escalation', 'Use ALTER TABLE...SET LOCK_ESCALATION = DISABLE for high-contention tables'),
        (8, 'Retry Logic', 'Implement deadlock retry', 'Always retry deadlock victim (error 1205) with exponential backoff'),
        (9, 'Bound Connections', 'Avoid distributed transactions', 'Minimize cross-database and linked server operations in transactions'),
        (10, 'Query Optimization', 'Optimize slow queries', 'Faster queries hold locks for less time, reducing deadlock window')
    ) AS Tips(TipNumber, Category, Recommendation, Implementation)
    ORDER BY TipNumber;
END
GO

-- Monitor deadlock-prone queries
CREATE PROCEDURE dbo.MonitorDeadlockProneQueries
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Queries with high lock waits
    SELECT TOP 25
        qs.total_elapsed_time / qs.execution_count / 1000 AS AvgDurationMs,
        qs.execution_count AS ExecutionCount,
        qs.total_logical_reads / qs.execution_count AS AvgLogicalReads,
        SUBSTRING(st.text, (qs.statement_start_offset/2) + 1,
            ((CASE qs.statement_end_offset
                WHEN -1 THEN DATALENGTH(st.text)
                ELSE qs.statement_end_offset
            END - qs.statement_start_offset)/2) + 1) AS QueryText,
        qp.query_plan AS ExecutionPlan
    FROM sys.dm_exec_query_stats qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
    CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
    WHERE qs.total_elapsed_time / qs.execution_count > 5000000  -- > 5 seconds avg
    ORDER BY qs.total_elapsed_time / qs.execution_count DESC;
END
GO
