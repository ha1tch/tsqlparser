-- Sample 044: Session and Connection Management
-- Source: Microsoft Learn, Brent Ozar, MSSQLTips
-- Category: Performance
-- Complexity: Complex
-- Features: sys.dm_exec_sessions, sys.dm_exec_connections, sp_who2, blocking analysis

-- Get detailed session information
CREATE PROCEDURE dbo.GetSessionDetails
    @SessionID INT = NULL,
    @ShowSleeping BIT = 0,
    @ShowSystemSessions BIT = 0,
    @DatabaseName NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        s.session_id AS SessionID,
        s.login_name AS LoginName,
        s.host_name AS HostName,
        s.program_name AS ProgramName,
        DB_NAME(s.database_id) AS DatabaseName,
        s.status AS Status,
        s.cpu_time AS CPUTime,
        s.memory_usage * 8 AS MemoryKB,
        s.reads AS LogicalReads,
        s.writes AS Writes,
        s.logical_reads AS TotalLogicalReads,
        s.last_request_start_time AS LastRequestStart,
        s.last_request_end_time AS LastRequestEnd,
        DATEDIFF(SECOND, s.last_request_start_time, GETDATE()) AS SecondsSinceLastRequest,
        c.client_net_address AS ClientIP,
        c.auth_scheme AS AuthScheme,
        c.encrypt_option AS Encrypted,
        r.command AS CurrentCommand,
        r.wait_type AS WaitType,
        r.wait_time AS WaitTimeMs,
        r.blocking_session_id AS BlockedBy,
        r.open_transaction_count AS OpenTransactions,
        r.percent_complete AS PercentComplete,
        SUBSTRING(st.text, (r.statement_start_offset/2) + 1,
            ((CASE r.statement_end_offset
                WHEN -1 THEN DATALENGTH(st.text)
                ELSE r.statement_end_offset
            END - r.statement_start_offset)/2) + 1) AS CurrentStatement,
        st.text AS FullQueryText
    FROM sys.dm_exec_sessions s
    LEFT JOIN sys.dm_exec_connections c ON s.session_id = c.session_id
    LEFT JOIN sys.dm_exec_requests r ON s.session_id = r.session_id
    OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) st
    WHERE (@SessionID IS NULL OR s.session_id = @SessionID)
      AND (@ShowSleeping = 1 OR s.status <> 'sleeping')
      AND (@ShowSystemSessions = 1 OR s.is_user_process = 1)
      AND (@DatabaseName IS NULL OR DB_NAME(s.database_id) = @DatabaseName)
    ORDER BY s.cpu_time DESC;
END
GO

-- Get blocking chain analysis
CREATE PROCEDURE dbo.GetBlockingChain
    @IncludeQueryText BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Find head blockers (blockers that are not blocked themselves)
    ;WITH BlockingChain AS (
        -- Head blockers
        SELECT 
            r.session_id,
            r.blocking_session_id,
            0 AS BlockingLevel,
            CAST(r.session_id AS VARCHAR(MAX)) AS BlockingChain
        FROM sys.dm_exec_requests r
        WHERE r.blocking_session_id = 0
          AND EXISTS (
              SELECT 1 FROM sys.dm_exec_requests r2
              WHERE r2.blocking_session_id = r.session_id
          )
        
        UNION ALL
        
        -- Blocked sessions
        SELECT 
            r.session_id,
            r.blocking_session_id,
            bc.BlockingLevel + 1,
            CAST(bc.BlockingChain + ' -> ' + CAST(r.session_id AS VARCHAR(10)) AS VARCHAR(MAX))
        FROM sys.dm_exec_requests r
        INNER JOIN BlockingChain bc ON r.blocking_session_id = bc.session_id
        WHERE bc.BlockingLevel < 10  -- Prevent infinite loop
    )
    SELECT 
        bc.session_id AS SessionID,
        bc.blocking_session_id AS BlockedBy,
        bc.BlockingLevel,
        bc.BlockingChain,
        s.login_name AS LoginName,
        s.host_name AS HostName,
        s.program_name AS ProgramName,
        DB_NAME(r.database_id) AS DatabaseName,
        r.status AS Status,
        r.command AS Command,
        r.wait_type AS WaitType,
        r.wait_time / 1000 AS WaitTimeSec,
        r.wait_resource AS WaitResource,
        CASE WHEN @IncludeQueryText = 1 THEN st.text ELSE NULL END AS QueryText
    FROM BlockingChain bc
    INNER JOIN sys.dm_exec_sessions s ON bc.session_id = s.session_id
    LEFT JOIN sys.dm_exec_requests r ON bc.session_id = r.session_id
    OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) st
    ORDER BY bc.BlockingChain;
    
    -- Summary
    SELECT 
        COUNT(DISTINCT blocking_session_id) AS HeadBlockers,
        COUNT(*) AS TotalBlockedSessions,
        MAX(wait_time) / 1000 AS MaxWaitTimeSec
    FROM sys.dm_exec_requests
    WHERE blocking_session_id <> 0;
END
GO

-- Kill sessions by criteria
CREATE PROCEDURE dbo.KillSessionsByCriteria
    @LoginName NVARCHAR(128) = NULL,
    @HostName NVARCHAR(128) = NULL,
    @DatabaseName NVARCHAR(128) = NULL,
    @ProgramName NVARCHAR(128) = NULL,
    @IdleMinutes INT = NULL,
    @WhatIf BIT = 1,  -- Preview only by default
    @LogToTable BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SessionID INT;
    DECLARE @KillCount INT = 0;
    DECLARE @SQL NVARCHAR(100);
    
    -- Create log table if needed
    IF @LogToTable = 1 AND OBJECT_ID('dbo.SessionKillLog', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.SessionKillLog (
            LogID INT IDENTITY(1,1) PRIMARY KEY,
            SessionID INT,
            LoginName NVARCHAR(128),
            HostName NVARCHAR(128),
            DatabaseName NVARCHAR(128),
            ProgramName NVARCHAR(128),
            KillReason NVARCHAR(500),
            KilledBy NVARCHAR(128),
            KillTime DATETIME DEFAULT GETDATE()
        );
    END
    
    -- Find matching sessions
    DECLARE SessionCursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT s.session_id
        FROM sys.dm_exec_sessions s
        WHERE s.is_user_process = 1
          AND s.session_id <> @@SPID
          AND (@LoginName IS NULL OR s.login_name LIKE @LoginName)
          AND (@HostName IS NULL OR s.host_name LIKE @HostName)
          AND (@DatabaseName IS NULL OR DB_NAME(s.database_id) = @DatabaseName)
          AND (@ProgramName IS NULL OR s.program_name LIKE @ProgramName)
          AND (@IdleMinutes IS NULL OR 
               (s.status = 'sleeping' AND 
                DATEDIFF(MINUTE, s.last_request_end_time, GETDATE()) >= @IdleMinutes));
    
    OPEN SessionCursor;
    FETCH NEXT FROM SessionCursor INTO @SessionID;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF @WhatIf = 1
        BEGIN
            -- Preview mode
            SELECT 
                @SessionID AS SessionToKill,
                s.login_name AS LoginName,
                s.host_name AS HostName,
                DB_NAME(s.database_id) AS DatabaseName,
                s.program_name AS ProgramName,
                s.status AS Status,
                s.last_request_end_time AS LastActivity,
                'Would be killed (WhatIf mode)' AS Action
            FROM sys.dm_exec_sessions s
            WHERE s.session_id = @SessionID;
        END
        ELSE
        BEGIN
            -- Actually kill
            BEGIN TRY
                -- Log before killing
                IF @LogToTable = 1
                BEGIN
                    INSERT INTO dbo.SessionKillLog (SessionID, LoginName, HostName, DatabaseName, ProgramName, KillReason, KilledBy)
                    SELECT 
                        s.session_id,
                        s.login_name,
                        s.host_name,
                        DB_NAME(s.database_id),
                        s.program_name,
                        'Killed by criteria: ' + 
                            ISNULL('Login=' + @LoginName + '; ', '') +
                            ISNULL('Host=' + @HostName + '; ', '') +
                            ISNULL('DB=' + @DatabaseName + '; ', '') +
                            ISNULL('IdleMin=' + CAST(@IdleMinutes AS VARCHAR(10)), ''),
                        SUSER_SNAME()
                    FROM sys.dm_exec_sessions s
                    WHERE s.session_id = @SessionID;
                END
                
                SET @SQL = 'KILL ' + CAST(@SessionID AS VARCHAR(10));
                EXEC sp_executesql @SQL;
                SET @KillCount = @KillCount + 1;
                
            END TRY
            BEGIN CATCH
                PRINT 'Failed to kill session ' + CAST(@SessionID AS VARCHAR(10)) + ': ' + ERROR_MESSAGE();
            END CATCH
        END
        
        FETCH NEXT FROM SessionCursor INTO @SessionID;
    END
    
    CLOSE SessionCursor;
    DEALLOCATE SessionCursor;
    
    IF @WhatIf = 0
        SELECT @KillCount AS SessionsKilled;
END
GO

-- Monitor connection pool usage
CREATE PROCEDURE dbo.GetConnectionPoolStats
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Connections by application
    SELECT 
        s.program_name AS ApplicationName,
        s.login_name AS LoginName,
        s.host_name AS HostName,
        COUNT(*) AS ConnectionCount,
        SUM(CASE WHEN s.status = 'sleeping' THEN 1 ELSE 0 END) AS SleepingConnections,
        SUM(CASE WHEN s.status = 'running' THEN 1 ELSE 0 END) AS ActiveConnections,
        SUM(s.cpu_time) AS TotalCPUTime,
        SUM(s.memory_usage) * 8 AS TotalMemoryKB,
        AVG(DATEDIFF(MINUTE, s.login_time, GETDATE())) AS AvgConnectionAgeMin
    FROM sys.dm_exec_sessions s
    WHERE s.is_user_process = 1
    GROUP BY s.program_name, s.login_name, s.host_name
    ORDER BY ConnectionCount DESC;
    
    -- Overall connection summary
    SELECT 
        @@MAX_CONNECTIONS AS MaxConnections,
        (SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process = 1) AS CurrentUserConnections,
        (SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process = 0) AS SystemConnections,
        (SELECT COUNT(*) FROM sys.dm_exec_connections) AS TotalConnections,
        CAST((SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process = 1) * 100.0 / 
             NULLIF(@@MAX_CONNECTIONS, 0) AS DECIMAL(5,2)) AS ConnectionUsagePercent;
END
GO
