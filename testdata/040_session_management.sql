-- Sample 040: Session and Connection Management
-- Source: Microsoft Learn, Brent Ozar, MSSQLTips
-- Category: Performance
-- Complexity: Advanced
-- Features: sys.dm_exec_sessions, sys.dm_exec_connections, sys.dm_exec_requests, session context

-- Get active sessions with details
CREATE PROCEDURE dbo.GetActiveSessions
    @DatabaseName NVARCHAR(128) = NULL,
    @LoginName NVARCHAR(128) = NULL,
    @HostName NVARCHAR(128) = NULL,
    @ExcludeSystemSessions BIT = 1,
    @MinCPUTime INT = 0,
    @MinLogicalReads BIGINT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        s.session_id AS SessionID,
        s.login_name AS LoginName,
        s.host_name AS HostName,
        s.program_name AS ProgramName,
        DB_NAME(s.database_id) AS DatabaseName,
        s.status AS SessionStatus,
        s.cpu_time AS CPUTimeMs,
        s.memory_usage * 8 AS MemoryKB,
        s.total_scheduled_time AS TotalScheduledTimeMs,
        s.total_elapsed_time AS TotalElapsedTimeMs,
        s.reads AS TotalReads,
        s.writes AS TotalWrites,
        s.logical_reads AS LogicalReads,
        s.login_time AS LoginTime,
        s.last_request_start_time AS LastRequestStart,
        s.last_request_end_time AS LastRequestEnd,
        DATEDIFF(MINUTE, s.login_time, GETDATE()) AS SessionAgeMinutes,
        c.client_net_address AS ClientIP,
        c.protocol_type AS Protocol,
        c.auth_scheme AS AuthScheme,
        c.encrypt_option AS Encrypted,
        r.command AS CurrentCommand,
        r.wait_type AS WaitType,
        r.wait_time AS WaitTimeMs,
        r.blocking_session_id AS BlockingSessionID,
        r.percent_complete AS PercentComplete,
        SUBSTRING(st.text, (r.statement_start_offset/2)+1,
            ((CASE r.statement_end_offset
                WHEN -1 THEN DATALENGTH(st.text)
                ELSE r.statement_end_offset
            END - r.statement_start_offset)/2) + 1) AS CurrentStatement
    FROM sys.dm_exec_sessions s
    LEFT JOIN sys.dm_exec_connections c ON s.session_id = c.session_id
    LEFT JOIN sys.dm_exec_requests r ON s.session_id = r.session_id
    OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) st
    WHERE (@ExcludeSystemSessions = 0 OR s.is_user_process = 1)
      AND (@DatabaseName IS NULL OR DB_NAME(s.database_id) = @DatabaseName)
      AND (@LoginName IS NULL OR s.login_name LIKE '%' + @LoginName + '%')
      AND (@HostName IS NULL OR s.host_name LIKE '%' + @HostName + '%')
      AND s.cpu_time >= @MinCPUTime
      AND s.logical_reads >= @MinLogicalReads
    ORDER BY s.cpu_time DESC;
END
GO

-- Kill sessions by criteria
CREATE PROCEDURE dbo.KillSessionsByCriteria
    @DatabaseName NVARCHAR(128) = NULL,
    @LoginName NVARCHAR(128) = NULL,
    @HostName NVARCHAR(128) = NULL,
    @OlderThanMinutes INT = NULL,
    @IdleOnly BIT = 0,
    @WhatIf BIT = 1,  -- Preview only by default
    @LogKills BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SessionsToKill TABLE (
        SessionID INT,
        LoginName NVARCHAR(128),
        HostName NVARCHAR(128),
        DatabaseName NVARCHAR(128),
        LoginTime DATETIME,
        LastRequestEnd DATETIME,
        Status NVARCHAR(30)
    );
    
    -- Find matching sessions
    INSERT INTO @SessionsToKill
    SELECT 
        s.session_id,
        s.login_name,
        s.host_name,
        DB_NAME(s.database_id),
        s.login_time,
        s.last_request_end_time,
        s.status
    FROM sys.dm_exec_sessions s
    WHERE s.is_user_process = 1
      AND s.session_id <> @@SPID  -- Don't kill ourselves
      AND (@DatabaseName IS NULL OR DB_NAME(s.database_id) = @DatabaseName)
      AND (@LoginName IS NULL OR s.login_name LIKE '%' + @LoginName + '%')
      AND (@HostName IS NULL OR s.host_name LIKE '%' + @HostName + '%')
      AND (@OlderThanMinutes IS NULL OR 
           DATEDIFF(MINUTE, s.last_request_end_time, GETDATE()) >= @OlderThanMinutes)
      AND (@IdleOnly = 0 OR s.status = 'sleeping');
    
    -- Show sessions that would be killed
    SELECT *, 
           CASE @WhatIf WHEN 1 THEN 'Would be killed' ELSE 'Will be killed' END AS Action
    FROM @SessionsToKill;
    
    IF @WhatIf = 0
    BEGIN
        DECLARE @SessionID INT;
        DECLARE @SQL NVARCHAR(50);
        
        -- Create log table if logging enabled
        IF @LogKills = 1 AND OBJECT_ID('dbo.SessionKillLog', 'U') IS NULL
        BEGIN
            CREATE TABLE dbo.SessionKillLog (
                LogID INT IDENTITY(1,1) PRIMARY KEY,
                KillTime DATETIME DEFAULT GETDATE(),
                SessionID INT,
                LoginName NVARCHAR(128),
                HostName NVARCHAR(128),
                DatabaseName NVARCHAR(128),
                KilledBy NVARCHAR(128) DEFAULT SUSER_SNAME()
            );
        END
        
        DECLARE kill_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT SessionID FROM @SessionsToKill;
        
        OPEN kill_cursor;
        FETCH NEXT FROM kill_cursor INTO @SessionID;
        
        WHILE @@FETCH_STATUS = 0
        BEGIN
            BEGIN TRY
                -- Log before kill
                IF @LogKills = 1
                BEGIN
                    INSERT INTO dbo.SessionKillLog (SessionID, LoginName, HostName, DatabaseName)
                    SELECT SessionID, LoginName, HostName, DatabaseName
                    FROM @SessionsToKill
                    WHERE SessionID = @SessionID;
                END
                
                SET @SQL = 'KILL ' + CAST(@SessionID AS VARCHAR(10));
                EXEC sp_executesql @SQL;
                
            END TRY
            BEGIN CATCH
                PRINT 'Failed to kill session ' + CAST(@SessionID AS VARCHAR(10)) + 
                      ': ' + ERROR_MESSAGE();
            END CATCH
            
            FETCH NEXT FROM kill_cursor INTO @SessionID;
        END
        
        CLOSE kill_cursor;
        DEALLOCATE kill_cursor;
        
        SELECT COUNT(*) AS SessionsKilled FROM @SessionsToKill;
    END
END
GO

-- Get connection pool statistics
CREATE PROCEDURE dbo.GetConnectionPoolStats
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Connections by login
    SELECT 
        s.login_name AS LoginName,
        COUNT(*) AS ConnectionCount,
        SUM(CASE WHEN s.status = 'sleeping' THEN 1 ELSE 0 END) AS IdleConnections,
        SUM(CASE WHEN s.status = 'running' THEN 1 ELSE 0 END) AS ActiveConnections,
        SUM(CASE WHEN s.status = 'suspended' THEN 1 ELSE 0 END) AS SuspendedConnections,
        MIN(s.login_time) AS OldestConnection,
        MAX(s.last_request_end_time) AS MostRecentActivity
    FROM sys.dm_exec_sessions s
    WHERE s.is_user_process = 1
    GROUP BY s.login_name
    ORDER BY COUNT(*) DESC;
    
    -- Connections by host
    SELECT 
        s.host_name AS HostName,
        s.program_name AS ProgramName,
        COUNT(*) AS ConnectionCount,
        SUM(s.cpu_time) AS TotalCPUTime,
        SUM(s.memory_usage) * 8 AS TotalMemoryKB
    FROM sys.dm_exec_sessions s
    WHERE s.is_user_process = 1
    GROUP BY s.host_name, s.program_name
    ORDER BY COUNT(*) DESC;
    
    -- Connections by database
    SELECT 
        DB_NAME(s.database_id) AS DatabaseName,
        COUNT(*) AS ConnectionCount,
        SUM(CASE WHEN r.session_id IS NOT NULL THEN 1 ELSE 0 END) AS ActiveRequests
    FROM sys.dm_exec_sessions s
    LEFT JOIN sys.dm_exec_requests r ON s.session_id = r.session_id
    WHERE s.is_user_process = 1
      AND s.database_id > 0
    GROUP BY DB_NAME(s.database_id)
    ORDER BY COUNT(*) DESC;
    
    -- Connection summary
    SELECT 
        COUNT(*) AS TotalConnections,
        SUM(CASE WHEN is_user_process = 1 THEN 1 ELSE 0 END) AS UserConnections,
        SUM(CASE WHEN is_user_process = 0 THEN 1 ELSE 0 END) AS SystemConnections,
        (SELECT value_in_use FROM sys.configurations WHERE name = 'user connections') AS MaxConnections
    FROM sys.dm_exec_sessions;
END
GO

-- Set session context for multi-tenant or RLS scenarios
CREATE PROCEDURE dbo.SetSessionContext
    @ContextKey NVARCHAR(128),
    @ContextValue SQL_VARIANT,
    @ReadOnly BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    EXEC sp_set_session_context @key = @ContextKey, @value = @ContextValue, @read_only = @ReadOnly;
    
    SELECT 
        @ContextKey AS ContextKey,
        CAST(SESSION_CONTEXT(@ContextKey) AS NVARCHAR(MAX)) AS ContextValue,
        @ReadOnly AS IsReadOnly,
        'Context set successfully' AS Status;
END
GO

-- Get all session context values
CREATE PROCEDURE dbo.GetSessionContexts
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Note: SQL Server doesn't provide a way to enumerate all session context keys
    -- This procedure shows common keys and requires you to know what keys to check
    
    SELECT 
        'Common Session Context Values' AS Info,
        CAST(SESSION_CONTEXT(N'TenantID') AS NVARCHAR(100)) AS TenantID,
        CAST(SESSION_CONTEXT(N'UserID') AS NVARCHAR(100)) AS UserID,
        CAST(SESSION_CONTEXT(N'DepartmentID') AS NVARCHAR(100)) AS DepartmentID,
        CAST(SESSION_CONTEXT(N'RoleID') AS NVARCHAR(100)) AS RoleID,
        CAST(SESSION_CONTEXT(N'ApplicationName') AS NVARCHAR(100)) AS ApplicationName,
        @@SPID AS CurrentSessionID,
        SUSER_SNAME() AS CurrentLogin,
        USER_NAME() AS CurrentUser,
        DB_NAME() AS CurrentDatabase;
END
GO
