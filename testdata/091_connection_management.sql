-- Sample 091: Connection Pooling and Session Management
-- Source: Microsoft Learn, MSSQLTips, Connection management patterns
-- Category: Performance
-- Complexity: Complex
-- Features: Connection analysis, session tracking, resource cleanup, connection limits

-- Analyze current connections
CREATE PROCEDURE dbo.AnalyzeConnections
    @ShowIdle BIT = 1,
    @MinIdleMinutes INT = 5
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Connection summary by login
    SELECT 
        s.login_name AS LoginName,
        s.host_name AS HostName,
        s.program_name AS ApplicationName,
        DB_NAME(s.database_id) AS DatabaseName,
        COUNT(*) AS ConnectionCount,
        SUM(CASE WHEN r.request_id IS NULL THEN 1 ELSE 0 END) AS IdleConnections,
        SUM(CASE WHEN r.request_id IS NOT NULL THEN 1 ELSE 0 END) AS ActiveConnections,
        MIN(s.login_time) AS FirstConnection,
        MAX(s.last_request_end_time) AS LastActivity
    FROM sys.dm_exec_sessions s
    LEFT JOIN sys.dm_exec_requests r ON s.session_id = r.session_id
    WHERE s.is_user_process = 1
    GROUP BY s.login_name, s.host_name, s.program_name, s.database_id
    ORDER BY ConnectionCount DESC;
    
    -- Idle connections
    IF @ShowIdle = 1
    BEGIN
        SELECT 
            s.session_id AS SessionID,
            s.login_name AS LoginName,
            s.host_name AS HostName,
            s.program_name AS ApplicationName,
            DB_NAME(s.database_id) AS DatabaseName,
            s.login_time AS LoginTime,
            s.last_request_start_time AS LastRequestStart,
            s.last_request_end_time AS LastRequestEnd,
            DATEDIFF(MINUTE, s.last_request_end_time, GETDATE()) AS IdleMinutes,
            s.memory_usage * 8 AS MemoryUsageKB,
            c.num_reads AS NetworkReads,
            c.num_writes AS NetworkWrites
        FROM sys.dm_exec_sessions s
        LEFT JOIN sys.dm_exec_requests r ON s.session_id = r.session_id
        LEFT JOIN sys.dm_exec_connections c ON s.session_id = c.session_id
        WHERE s.is_user_process = 1
          AND r.request_id IS NULL
          AND DATEDIFF(MINUTE, s.last_request_end_time, GETDATE()) >= @MinIdleMinutes
        ORDER BY IdleMinutes DESC;
    END
    
    -- Connection pool indicators
    SELECT 
        'Connection Pool Analysis' AS Section,
        COUNT(*) AS TotalConnections,
        COUNT(DISTINCT s.host_name + s.program_name + s.login_name) AS UniquePoolGroups,
        AVG(CASE WHEN r.request_id IS NULL THEN 1.0 ELSE 0.0 END) * 100 AS IdleConnectionPercent,
        (SELECT COUNT(*) FROM sys.dm_exec_connections WHERE auth_scheme = 'SQL') AS SQLAuthConnections,
        (SELECT COUNT(*) FROM sys.dm_exec_connections WHERE auth_scheme = 'NTLM') AS WindowsAuthConnections
    FROM sys.dm_exec_sessions s
    LEFT JOIN sys.dm_exec_requests r ON s.session_id = r.session_id
    WHERE s.is_user_process = 1;
END
GO

-- Kill idle connections
CREATE PROCEDURE dbo.KillIdleConnections
    @IdleMinutes INT = 30,
    @ExcludeApplications NVARCHAR(MAX) = NULL,  -- Comma-separated
    @ExcludeLogins NVARCHAR(MAX) = NULL,
    @WhatIf BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SessionsToKill TABLE (
        SessionID INT,
        LoginName NVARCHAR(128),
        HostName NVARCHAR(128),
        ApplicationName NVARCHAR(256),
        IdleMinutes INT
    );
    
    -- Find idle sessions
    INSERT INTO @SessionsToKill
    SELECT 
        s.session_id,
        s.login_name,
        s.host_name,
        s.program_name,
        DATEDIFF(MINUTE, s.last_request_end_time, GETDATE())
    FROM sys.dm_exec_sessions s
    LEFT JOIN sys.dm_exec_requests r ON s.session_id = r.session_id
    WHERE s.is_user_process = 1
      AND r.request_id IS NULL
      AND s.session_id <> @@SPID
      AND DATEDIFF(MINUTE, s.last_request_end_time, GETDATE()) >= @IdleMinutes
      AND (@ExcludeApplications IS NULL OR s.program_name NOT IN (SELECT value FROM STRING_SPLIT(@ExcludeApplications, ',')))
      AND (@ExcludeLogins IS NULL OR s.login_name NOT IN (SELECT value FROM STRING_SPLIT(@ExcludeLogins, ',')));
    
    IF @WhatIf = 1
    BEGIN
        SELECT 'Sessions that would be killed:' AS Info;
        SELECT * FROM @SessionsToKill ORDER BY IdleMinutes DESC;
        SELECT COUNT(*) AS SessionsToKill FROM @SessionsToKill;
    END
    ELSE
    BEGIN
        DECLARE @SessionID INT;
        DECLARE @KillCount INT = 0;
        DECLARE @SQL NVARCHAR(100);
        
        DECLARE KillCursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT SessionID FROM @SessionsToKill;
        
        OPEN KillCursor;
        FETCH NEXT FROM KillCursor INTO @SessionID;
        
        WHILE @@FETCH_STATUS = 0
        BEGIN
            BEGIN TRY
                SET @SQL = 'KILL ' + CAST(@SessionID AS VARCHAR(10));
                EXEC sp_executesql @SQL;
                SET @KillCount = @KillCount + 1;
            END TRY
            BEGIN CATCH
                PRINT 'Failed to kill session ' + CAST(@SessionID AS VARCHAR(10)) + ': ' + ERROR_MESSAGE();
            END CATCH
            
            FETCH NEXT FROM KillCursor INTO @SessionID;
        END
        
        CLOSE KillCursor;
        DEALLOCATE KillCursor;
        
        SELECT @KillCount AS SessionsKilled;
    END
END
GO

-- Get session resource usage
CREATE PROCEDURE dbo.GetSessionResourceUsage
    @TopN INT = 25,
    @SortBy NVARCHAR(20) = 'CPU'  -- CPU, MEMORY, READS, WRITES
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT TOP (@TopN)
        s.session_id AS SessionID,
        s.login_name AS LoginName,
        s.host_name AS HostName,
        s.program_name AS ApplicationName,
        DB_NAME(s.database_id) AS DatabaseName,
        s.cpu_time AS CPUTimeMs,
        s.memory_usage * 8 AS MemoryUsageKB,
        s.reads AS LogicalReads,
        s.writes AS Writes,
        s.logical_reads AS TotalLogicalReads,
        s.row_count AS RowCount,
        s.login_time AS LoginTime,
        DATEDIFF(MINUTE, s.login_time, GETDATE()) AS SessionAgeMinutes,
        s.status AS Status,
        ISNULL(r.command, 'Idle') AS CurrentCommand,
        r.wait_type AS WaitType,
        r.wait_time AS WaitTimeMs,
        t.text AS CurrentQuery
    FROM sys.dm_exec_sessions s
    LEFT JOIN sys.dm_exec_requests r ON s.session_id = r.session_id
    OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
    WHERE s.is_user_process = 1
    ORDER BY 
        CASE @SortBy 
            WHEN 'CPU' THEN s.cpu_time 
            WHEN 'MEMORY' THEN s.memory_usage 
            WHEN 'READS' THEN s.reads 
            WHEN 'WRITES' THEN s.writes 
            ELSE s.cpu_time 
        END DESC;
END
GO

-- Monitor connection limits
CREATE PROCEDURE dbo.MonitorConnectionLimits
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @MaxConnections INT;
    SELECT @MaxConnections = CAST(value_in_use AS INT) FROM sys.configurations WHERE name = 'user connections';
    IF @MaxConnections = 0 SET @MaxConnections = 32767;  -- Default
    
    DECLARE @CurrentConnections INT;
    SELECT @CurrentConnections = COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process = 1;
    
    SELECT 
        @MaxConnections AS MaxConfiguredConnections,
        @CurrentConnections AS CurrentConnections,
        @MaxConnections - @CurrentConnections AS AvailableConnections,
        CAST(@CurrentConnections * 100.0 / @MaxConnections AS DECIMAL(5,2)) AS UsagePercent,
        CASE 
            WHEN @CurrentConnections * 100.0 / @MaxConnections > 90 THEN 'CRITICAL'
            WHEN @CurrentConnections * 100.0 / @MaxConnections > 75 THEN 'WARNING'
            ELSE 'OK'
        END AS Status;
    
    -- Connections by application
    SELECT 
        program_name AS ApplicationName,
        COUNT(*) AS ConnectionCount,
        CAST(COUNT(*) * 100.0 / @CurrentConnections AS DECIMAL(5,2)) AS PercentOfTotal
    FROM sys.dm_exec_sessions
    WHERE is_user_process = 1
    GROUP BY program_name
    ORDER BY ConnectionCount DESC;
    
    -- Connection trend (last hour via DMV snapshots if available)
    SELECT 
        'Note: Enable connection tracking for historical trends' AS Info;
END
GO

-- Setup session timeout
CREATE PROCEDURE dbo.ConfigureSessionTimeout
    @TimeoutMinutes INT = 30
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Note: SQL Server doesn't have built-in session timeout
    -- This creates a SQL Agent job to handle timeouts
    
    SELECT 
        'To implement session timeout, create a SQL Agent job that runs:' AS Instructions,
        'EXEC dbo.KillIdleConnections @IdleMinutes = ' + CAST(@TimeoutMinutes AS VARCHAR(10)) + ', @WhatIf = 0' AS Command,
        'Schedule it to run every 5-10 minutes' AS Note;
END
GO

-- Get connection string recommendations
CREATE PROCEDURE dbo.GetConnectionStringRecommendations
    @ApplicationType NVARCHAR(50) = 'WEB'  -- WEB, DESKTOP, SERVICE, BATCH
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        @ApplicationType AS ApplicationType,
        Recommendation,
        Setting,
        Example
    FROM (VALUES
        ('Pool Size', 'Min Pool Size', 'Min Pool Size=5'),
        ('Pool Size', 'Max Pool Size', 'Max Pool Size=' + CASE @ApplicationType WHEN 'WEB' THEN '100' WHEN 'BATCH' THEN '50' ELSE '25' END),
        ('Timeout', 'Connection Timeout', 'Connection Timeout=30'),
        ('Timeout', 'Command Timeout', 'Command Timeout=30'),
        ('Resiliency', 'ConnectRetryCount', 'ConnectRetryCount=3'),
        ('Resiliency', 'ConnectRetryInterval', 'ConnectRetryInterval=10'),
        ('Performance', 'MultipleActiveResultSets', CASE @ApplicationType WHEN 'WEB' THEN 'MultipleActiveResultSets=True' ELSE 'MultipleActiveResultSets=False' END),
        ('Performance', 'Pooling', 'Pooling=True'),
        ('Security', 'Encrypt', 'Encrypt=True'),
        ('Security', 'TrustServerCertificate', 'TrustServerCertificate=False')
    ) AS Recommendations(Category, Recommendation, Setting)
    CROSS APPLY (SELECT Setting AS Example) ex
    ORDER BY Category;
END
GO

-- Track connection history
CREATE PROCEDURE dbo.CaptureConnectionSnapshot
AS
BEGIN
    SET NOCOUNT ON;
    
    IF OBJECT_ID('dbo.ConnectionHistory', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.ConnectionHistory (
            SnapshotID BIGINT IDENTITY(1,1) PRIMARY KEY,
            SnapshotTime DATETIME2 DEFAULT SYSDATETIME(),
            TotalConnections INT,
            ActiveConnections INT,
            IdleConnections INT,
            TopApplication NVARCHAR(256),
            TopApplicationCount INT
        );
    END
    
    INSERT INTO dbo.ConnectionHistory (TotalConnections, ActiveConnections, IdleConnections, TopApplication, TopApplicationCount)
    SELECT 
        COUNT(*),
        SUM(CASE WHEN r.request_id IS NOT NULL THEN 1 ELSE 0 END),
        SUM(CASE WHEN r.request_id IS NULL THEN 1 ELSE 0 END),
        (SELECT TOP 1 program_name FROM sys.dm_exec_sessions WHERE is_user_process = 1 GROUP BY program_name ORDER BY COUNT(*) DESC),
        (SELECT TOP 1 COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process = 1 GROUP BY program_name ORDER BY COUNT(*) DESC)
    FROM sys.dm_exec_sessions s
    LEFT JOIN sys.dm_exec_requests r ON s.session_id = r.session_id
    WHERE s.is_user_process = 1;
END
GO
