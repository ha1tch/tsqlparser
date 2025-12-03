-- Sample 064: Extended Events Management
-- Source: Microsoft Learn, Jonathan Kehayias, Erin Stellato
-- Category: Performance
-- Complexity: Advanced
-- Features: Extended Events, event sessions, ring_buffer, file targets

-- Create query performance monitoring session
CREATE PROCEDURE dbo.CreateQueryPerfSession
    @SessionName NVARCHAR(128) = 'QueryPerformance',
    @DurationThresholdMs INT = 1000,
    @MaxFileSizeMB INT = 100,
    @MaxFiles INT = 5,
    @FilePath NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    
    -- Drop if exists
    IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = @SessionName)
    BEGIN
        SET @SQL = 'DROP EVENT SESSION ' + QUOTENAME(@SessionName) + ' ON SERVER';
        EXEC sp_executesql @SQL;
    END
    
    SET @FilePath = ISNULL(@FilePath, 
        (SELECT CAST(SERVERPROPERTY('ErrorLogFileName') AS NVARCHAR(500))));
    SET @FilePath = LEFT(@FilePath, LEN(@FilePath) - CHARINDEX('\', REVERSE(@FilePath))) + '\' + @SessionName;
    
    SET @SQL = N'
        CREATE EVENT SESSION ' + QUOTENAME(@SessionName) + ' ON SERVER
        ADD EVENT sqlserver.sql_statement_completed (
            ACTION (
                sqlserver.client_app_name,
                sqlserver.client_hostname,
                sqlserver.database_name,
                sqlserver.username,
                sqlserver.sql_text,
                sqlserver.query_hash,
                sqlserver.query_plan_hash
            )
            WHERE duration >= ' + CAST(@DurationThresholdMs * 1000 AS VARCHAR(20)) + '
        ),
        ADD EVENT sqlserver.sp_statement_completed (
            ACTION (
                sqlserver.client_app_name,
                sqlserver.client_hostname,
                sqlserver.database_name,
                sqlserver.username,
                sqlserver.sql_text
            )
            WHERE duration >= ' + CAST(@DurationThresholdMs * 1000 AS VARCHAR(20)) + '
        ),
        ADD EVENT sqlserver.rpc_completed (
            ACTION (
                sqlserver.client_app_name,
                sqlserver.client_hostname,
                sqlserver.database_name,
                sqlserver.username,
                sqlserver.sql_text
            )
            WHERE duration >= ' + CAST(@DurationThresholdMs * 1000 AS VARCHAR(20)) + '
        )
        ADD TARGET package0.event_file (
            SET filename = N''' + @FilePath + '.xel'',
                max_file_size = ' + CAST(@MaxFileSizeMB AS VARCHAR(10)) + ',
                max_rollover_files = ' + CAST(@MaxFiles AS VARCHAR(10)) + '
        )
        WITH (
            MAX_MEMORY = 4096 KB,
            EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
            MAX_DISPATCH_LATENCY = 30 SECONDS,
            STARTUP_STATE = OFF
        )';
    
    EXEC sp_executesql @SQL;
    
    SELECT 'Event session created' AS Status, @SessionName AS SessionName, @FilePath + '.xel' AS FilePath;
END
GO

-- Create blocking monitoring session
CREATE PROCEDURE dbo.CreateBlockingMonitorSession
    @SessionName NVARCHAR(128) = 'BlockingMonitor',
    @BlockedThresholdSec INT = 5
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    
    IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = @SessionName)
    BEGIN
        SET @SQL = 'DROP EVENT SESSION ' + QUOTENAME(@SessionName) + ' ON SERVER';
        EXEC sp_executesql @SQL;
    END
    
    SET @SQL = N'
        CREATE EVENT SESSION ' + QUOTENAME(@SessionName) + ' ON SERVER
        ADD EVENT sqlserver.blocked_process_report (
            ACTION (
                sqlserver.client_app_name,
                sqlserver.client_hostname,
                sqlserver.database_name,
                sqlserver.sql_text
            )
        ),
        ADD EVENT sqlserver.lock_deadlock (
            ACTION (
                sqlserver.client_app_name,
                sqlserver.database_name,
                sqlserver.sql_text
            )
        ),
        ADD EVENT sqlserver.xml_deadlock_report
        ADD TARGET package0.ring_buffer (
            SET max_memory = 4096
        )
        WITH (
            MAX_MEMORY = 4096 KB,
            EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
            MAX_DISPATCH_LATENCY = 5 SECONDS,
            STARTUP_STATE = OFF
        )';
    
    EXEC sp_executesql @SQL;
    
    -- Set blocked process threshold
    EXEC sp_configure 'blocked process threshold', @BlockedThresholdSec;
    RECONFIGURE;
    
    SELECT 'Blocking monitor session created' AS Status, @SessionName AS SessionName;
END
GO

-- Start/Stop event session
CREATE PROCEDURE dbo.ManageEventSession
    @SessionName NVARCHAR(128),
    @Action NVARCHAR(10)  -- START, STOP, DROP
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    
    IF NOT EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = @SessionName)
    BEGIN
        RAISERROR('Event session not found: %s', 16, 1, @SessionName);
        RETURN;
    END
    
    IF @Action = 'START'
    BEGIN
        SET @SQL = 'ALTER EVENT SESSION ' + QUOTENAME(@SessionName) + ' ON SERVER STATE = START';
    END
    ELSE IF @Action = 'STOP'
    BEGIN
        SET @SQL = 'ALTER EVENT SESSION ' + QUOTENAME(@SessionName) + ' ON SERVER STATE = STOP';
    END
    ELSE IF @Action = 'DROP'
    BEGIN
        SET @SQL = 'DROP EVENT SESSION ' + QUOTENAME(@SessionName) + ' ON SERVER';
    END
    ELSE
    BEGIN
        RAISERROR('Invalid action. Use START, STOP, or DROP', 16, 1);
        RETURN;
    END
    
    EXEC sp_executesql @SQL;
    
    SELECT @Action + ' completed for session: ' + @SessionName AS Status;
END
GO

-- Read events from ring buffer
CREATE PROCEDURE dbo.ReadRingBufferEvents
    @SessionName NVARCHAR(128),
    @TopN INT = 100
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    
    SET @SQL = N'
        ;WITH EventData AS (
            SELECT 
                CAST(target_data AS XML) AS TargetData
            FROM sys.dm_xe_session_targets st
            INNER JOIN sys.dm_xe_sessions s ON st.event_session_address = s.address
            WHERE s.name = @Session
              AND st.target_name = ''ring_buffer''
        )
        SELECT TOP (@N)
            event_data.value(''(@name)[1]'', ''NVARCHAR(100)'') AS EventName,
            event_data.value(''(@timestamp)[1]'', ''DATETIME2'') AS EventTime,
            event_data.value(''(data[@name="duration"]/value)[1]'', ''BIGINT'') / 1000 AS DurationMs,
            event_data.value(''(data[@name="cpu_time"]/value)[1]'', ''BIGINT'') / 1000 AS CpuMs,
            event_data.value(''(data[@name="logical_reads"]/value)[1]'', ''BIGINT'') AS LogicalReads,
            event_data.value(''(data[@name="physical_reads"]/value)[1]'', ''BIGINT'') AS PhysicalReads,
            event_data.value(''(data[@name="writes"]/value)[1]'', ''BIGINT'') AS Writes,
            event_data.value(''(action[@name="database_name"]/value)[1]'', ''NVARCHAR(128)'') AS DatabaseName,
            event_data.value(''(action[@name="username"]/value)[1]'', ''NVARCHAR(128)'') AS UserName,
            event_data.value(''(action[@name="client_hostname"]/value)[1]'', ''NVARCHAR(128)'') AS ClientHost,
            event_data.value(''(action[@name="sql_text"]/value)[1]'', ''NVARCHAR(MAX)'') AS SqlText
        FROM EventData
        CROSS APPLY TargetData.nodes(''RingBufferTarget/event'') AS Events(event_data)
        ORDER BY EventTime DESC';
    
    EXEC sp_executesql @SQL, N'@Session NVARCHAR(128), @N INT', @Session = @SessionName, @N = @TopN;
END
GO

-- Read events from file target
CREATE PROCEDURE dbo.ReadEventFileTarget
    @FilePath NVARCHAR(500),
    @TopN INT = 1000,
    @StartTime DATETIME2 = NULL,
    @EndTime DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT TOP (@TopN)
        object_name AS EventName,
        CAST(event_data AS XML).value('(event/@timestamp)[1]', 'DATETIME2') AS EventTime,
        CAST(event_data AS XML).value('(event/data[@name="duration"]/value)[1]', 'BIGINT') / 1000 AS DurationMs,
        CAST(event_data AS XML).value('(event/data[@name="cpu_time"]/value)[1]', 'BIGINT') / 1000 AS CpuMs,
        CAST(event_data AS XML).value('(event/data[@name="logical_reads"]/value)[1]', 'BIGINT') AS LogicalReads,
        CAST(event_data AS XML).value('(event/action[@name="database_name"]/value)[1]', 'NVARCHAR(128)') AS DatabaseName,
        CAST(event_data AS XML).value('(event/action[@name="sql_text"]/value)[1]', 'NVARCHAR(MAX)') AS SqlText,
        file_name,
        file_offset
    FROM sys.fn_xe_file_target_read_file(@FilePath, NULL, NULL, NULL)
    WHERE (@StartTime IS NULL OR CAST(event_data AS XML).value('(event/@timestamp)[1]', 'DATETIME2') >= @StartTime)
      AND (@EndTime IS NULL OR CAST(event_data AS XML).value('(event/@timestamp)[1]', 'DATETIME2') <= @EndTime)
    ORDER BY CAST(event_data AS XML).value('(event/@timestamp)[1]', 'DATETIME2') DESC;
END
GO

-- List all event sessions
CREATE PROCEDURE dbo.GetEventSessionStatus
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        s.name AS SessionName,
        CASE WHEN ds.name IS NOT NULL THEN 'Running' ELSE 'Stopped' END AS Status,
        s.event_retention_mode_desc AS RetentionMode,
        s.max_dispatch_latency / 1000 AS MaxLatencySec,
        s.max_memory / 1024 AS MaxMemoryMB,
        s.startup_state_desc AS StartupState
    FROM sys.server_event_sessions s
    LEFT JOIN sys.dm_xe_sessions ds ON s.name = ds.name;
    
    -- Targets for running sessions
    SELECT 
        s.name AS SessionName,
        t.target_name AS TargetType,
        CAST(t.target_data AS XML).value('(RingBufferTarget/@eventCount)[1]', 'INT') AS EventCount,
        CAST(t.target_data AS XML).value('(RingBufferTarget/@memoryUsed)[1]', 'BIGINT') / 1024 AS MemoryUsedKB
    FROM sys.dm_xe_sessions s
    INNER JOIN sys.dm_xe_session_targets t ON s.address = t.event_session_address
    WHERE t.target_name = 'ring_buffer';
END
GO
