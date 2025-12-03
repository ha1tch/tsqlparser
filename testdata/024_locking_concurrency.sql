-- Sample 024: Locking and Concurrency Patterns
-- Source: Microsoft Learn, Brent Ozar, MSSQLTips
-- Category: Error Handling
-- Complexity: Advanced
-- Features: Locking hints, sp_getapplock, isolation levels, blocking detection

-- Application-level lock using sp_getapplock
CREATE PROCEDURE dbo.ExecuteWithAppLock
    @ResourceName NVARCHAR(255),
    @LockMode NVARCHAR(32) = 'Exclusive',  -- Shared, Update, Exclusive, IntentShared, IntentExclusive
    @LockTimeout INT = 5000,  -- milliseconds
    @ProcedureToExecute NVARCHAR(500),
    @Parameters NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @LockResult INT;
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @StartTime DATETIME = GETDATE();
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        -- Acquire the application lock
        EXEC @LockResult = sp_getapplock 
            @Resource = @ResourceName,
            @LockMode = @LockMode,
            @LockOwner = 'Transaction',
            @LockTimeout = @LockTimeout;
        
        -- Check lock result
        IF @LockResult < 0
        BEGIN
            DECLARE @ErrorMsg NVARCHAR(200);
            SET @ErrorMsg = CASE @LockResult
                WHEN -1 THEN 'Lock request timed out'
                WHEN -2 THEN 'Lock request was cancelled'
                WHEN -3 THEN 'Lock request was chosen as deadlock victim'
                WHEN -999 THEN 'Parameter validation or other call error'
                ELSE 'Unknown lock error: ' + CAST(@LockResult AS NVARCHAR(10))
            END;
            
            RAISERROR(@ErrorMsg, 16, 1);
            RETURN;
        END
        
        -- Execute the protected procedure
        SET @SQL = 'EXEC ' + @ProcedureToExecute;
        IF @Parameters IS NOT NULL
            SET @SQL = @SQL + ' ' + @Parameters;
        
        EXEC sp_executesql @SQL;
        
        -- Release the lock (automatic with transaction commit)
        COMMIT TRANSACTION;
        
        SELECT 
            @ResourceName AS ResourceName,
            @LockMode AS LockMode,
            'Success' AS Status,
            DATEDIFF(MILLISECOND, @StartTime, GETDATE()) AS DurationMs;
            
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        SELECT 
            @ResourceName AS ResourceName,
            @LockMode AS LockMode,
            'Failed' AS Status,
            ERROR_MESSAGE() AS ErrorMessage;
            
        THROW;
    END CATCH
END
GO

-- Monitor current locks and blocking
CREATE PROCEDURE dbo.GetCurrentBlocking
    @IncludeSystemProcesses BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Current blocking chains
    SELECT 
        r.session_id AS BlockedSessionID,
        r.blocking_session_id AS BlockingSessionID,
        r.wait_type,
        r.wait_time / 1000.0 AS WaitTimeSeconds,
        r.wait_resource,
        DB_NAME(r.database_id) AS DatabaseName,
        s.login_name AS BlockedLogin,
        s.host_name AS BlockedHost,
        s.program_name AS BlockedProgram,
        r.status AS RequestStatus,
        r.command,
        r.cpu_time,
        r.total_elapsed_time / 1000.0 AS ElapsedSeconds,
        r.reads,
        r.writes,
        r.logical_reads,
        SUBSTRING(st.text, (r.statement_start_offset / 2) + 1,
            ((CASE r.statement_end_offset
                WHEN -1 THEN DATALENGTH(st.text)
                ELSE r.statement_end_offset
            END - r.statement_start_offset) / 2) + 1) AS BlockedQuery,
        -- Blocking session info
        bs.login_name AS BlockingLogin,
        bs.host_name AS BlockingHost,
        bs.program_name AS BlockingProgram,
        bst.text AS BlockingQuery
    FROM sys.dm_exec_requests r
    INNER JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
    CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) st
    LEFT JOIN sys.dm_exec_sessions bs ON r.blocking_session_id = bs.session_id
    LEFT JOIN sys.dm_exec_connections bc ON r.blocking_session_id = bc.session_id
    OUTER APPLY sys.dm_exec_sql_text(bc.most_recent_sql_handle) bst
    WHERE r.blocking_session_id > 0
      AND (@IncludeSystemProcesses = 1 OR r.session_id > 50);
    
    -- Lock summary by object
    SELECT 
        DB_NAME(resource_database_id) AS DatabaseName,
        CASE resource_type
            WHEN 'OBJECT' THEN OBJECT_NAME(resource_associated_entity_id, resource_database_id)
            ELSE resource_type
        END AS Resource,
        request_mode AS LockMode,
        request_status AS LockStatus,
        COUNT(*) AS LockCount
    FROM sys.dm_tran_locks
    WHERE resource_database_id = DB_ID()
    GROUP BY resource_database_id, resource_type, resource_associated_entity_id, 
             request_mode, request_status
    ORDER BY LockCount DESC;
END
GO

-- Get detailed lock information for a session
CREATE PROCEDURE dbo.GetSessionLocks
    @SessionID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @SessionID = ISNULL(@SessionID, @@SPID);
    
    SELECT 
        tl.resource_type AS ResourceType,
        tl.resource_subtype AS ResourceSubtype,
        DB_NAME(tl.resource_database_id) AS DatabaseName,
        CASE tl.resource_type
            WHEN 'DATABASE' THEN DB_NAME(tl.resource_database_id)
            WHEN 'OBJECT' THEN OBJECT_NAME(tl.resource_associated_entity_id, tl.resource_database_id)
            WHEN 'KEY' THEN 'Key: ' + ISNULL(CAST(tl.resource_associated_entity_id AS NVARCHAR(50)), '')
            WHEN 'PAGE' THEN 'Page: ' + ISNULL(tl.resource_description, '')
            WHEN 'RID' THEN 'RID: ' + ISNULL(tl.resource_description, '')
            ELSE ISNULL(tl.resource_description, '')
        END AS ResourceDescription,
        tl.request_mode AS LockMode,
        tl.request_type AS RequestType,
        tl.request_status AS LockStatus,
        tl.request_owner_type AS OwnerType,
        tl.request_owner_id AS OwnerID
    FROM sys.dm_tran_locks tl
    WHERE tl.request_session_id = @SessionID
    ORDER BY tl.resource_type, tl.resource_description;
END
GO

-- Execute with specific isolation level
CREATE PROCEDURE dbo.ExecuteWithIsolationLevel
    @IsolationLevel NVARCHAR(50) = 'READ COMMITTED',  
    -- READ UNCOMMITTED, READ COMMITTED, REPEATABLE READ, SERIALIZABLE, SNAPSHOT
    @SQLStatement NVARCHAR(MAX),
    @Parameters NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @OriginalIsolation NVARCHAR(50);
    
    -- Store original isolation level
    SELECT @OriginalIsolation = CASE transaction_isolation_level
        WHEN 0 THEN 'Unspecified'
        WHEN 1 THEN 'READ UNCOMMITTED'
        WHEN 2 THEN 'READ COMMITTED'
        WHEN 3 THEN 'REPEATABLE READ'
        WHEN 4 THEN 'SERIALIZABLE'
        WHEN 5 THEN 'SNAPSHOT'
    END
    FROM sys.dm_exec_sessions
    WHERE session_id = @@SPID;
    
    BEGIN TRY
        -- Set requested isolation level
        SET @SQL = 'SET TRANSACTION ISOLATION LEVEL ' + @IsolationLevel;
        EXEC sp_executesql @SQL;
        
        -- Execute the statement
        IF @Parameters IS NOT NULL
            EXEC sp_executesql @SQLStatement, @Parameters;
        ELSE
            EXEC sp_executesql @SQLStatement;
        
        -- Restore original isolation level
        SET @SQL = 'SET TRANSACTION ISOLATION LEVEL ' + @OriginalIsolation;
        EXEC sp_executesql @SQL;
        
    END TRY
    BEGIN CATCH
        -- Restore original isolation level
        SET @SQL = 'SET TRANSACTION ISOLATION LEVEL ' + @OriginalIsolation;
        EXEC sp_executesql @SQL;
        
        THROW;
    END CATCH
END
GO

-- Optimistic locking with row versioning
CREATE PROCEDURE dbo.UpdateWithOptimisticLock
    @TableName NVARCHAR(128),
    @SchemaName NVARCHAR(128) = 'dbo',
    @KeyColumn NVARCHAR(128),
    @KeyValue SQL_VARIANT,
    @VersionColumn NVARCHAR(128),
    @ExpectedVersion ROWVERSION,
    @UpdateColumns NVARCHAR(MAX),  -- col1=@val1, col2=@val2
    @Parameters NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @RowCount INT;
    DECLARE @CurrentVersion BINARY(8);
    
    -- Build update statement with version check
    SET @SQL = N'
        UPDATE ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '
        SET ' + @UpdateColumns + '
        WHERE ' + QUOTENAME(@KeyColumn) + ' = @KeyValue
          AND ' + QUOTENAME(@VersionColumn) + ' = @ExpectedVersion';
    
    -- Execute update
    EXEC sp_executesql @SQL,
        N'@KeyValue SQL_VARIANT, @ExpectedVersion ROWVERSION',
        @KeyValue = @KeyValue,
        @ExpectedVersion = @ExpectedVersion;
    
    SET @RowCount = @@ROWCOUNT;
    
    IF @RowCount = 0
    BEGIN
        -- Check if record exists
        SET @SQL = N'
            SELECT @ver = ' + QUOTENAME(@VersionColumn) + '
            FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '
            WHERE ' + QUOTENAME(@KeyColumn) + ' = @KeyValue';
        
        EXEC sp_executesql @SQL,
            N'@KeyValue SQL_VARIANT, @ver BINARY(8) OUTPUT',
            @KeyValue = @KeyValue,
            @ver = @CurrentVersion OUTPUT;
        
        IF @CurrentVersion IS NULL
            RAISERROR('Record not found', 16, 1);
        ELSE
            RAISERROR('Optimistic concurrency violation - record was modified by another user', 16, 1);
    END
    
    SELECT 
        @RowCount AS RowsAffected,
        'Success' AS Status;
END
GO

-- Kill blocking session (requires elevated permissions)
CREATE PROCEDURE dbo.KillBlockingSession
    @BlockingSessionID INT,
    @Reason NVARCHAR(500) = NULL,
    @LogToTable BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(100);
    DECLARE @LoginName NVARCHAR(128);
    DECLARE @HostName NVARCHAR(128);
    DECLARE @ProgramName NVARCHAR(128);
    DECLARE @QueryText NVARCHAR(MAX);
    
    -- Get session info before killing
    SELECT 
        @LoginName = s.login_name,
        @HostName = s.host_name,
        @ProgramName = s.program_name,
        @QueryText = t.text
    FROM sys.dm_exec_sessions s
    LEFT JOIN sys.dm_exec_connections c ON s.session_id = c.session_id
    OUTER APPLY sys.dm_exec_sql_text(c.most_recent_sql_handle) t
    WHERE s.session_id = @BlockingSessionID;
    
    IF @LoginName IS NULL
    BEGIN
        RAISERROR('Session ID %d not found', 16, 1, @BlockingSessionID);
        RETURN;
    END
    
    -- Log if requested
    IF @LogToTable = 1
    BEGIN
        IF OBJECT_ID('dbo.KilledSessionLog', 'U') IS NULL
        BEGIN
            CREATE TABLE dbo.KilledSessionLog (
                LogID INT IDENTITY(1,1) PRIMARY KEY,
                KilledSessionID INT,
                LoginName NVARCHAR(128),
                HostName NVARCHAR(128),
                ProgramName NVARCHAR(128),
                QueryText NVARCHAR(MAX),
                Reason NVARCHAR(500),
                KilledBy NVARCHAR(128),
                KillTime DATETIME DEFAULT GETDATE()
            );
        END
        
        INSERT INTO dbo.KilledSessionLog (
            KilledSessionID, LoginName, HostName, ProgramName, 
            QueryText, Reason, KilledBy
        )
        VALUES (
            @BlockingSessionID, @LoginName, @HostName, @ProgramName,
            @QueryText, @Reason, SUSER_SNAME()
        );
    END
    
    -- Kill the session
    SET @SQL = 'KILL ' + CAST(@BlockingSessionID AS NVARCHAR(10));
    EXEC sp_executesql @SQL;
    
    SELECT 
        @BlockingSessionID AS KilledSessionID,
        @LoginName AS LoginName,
        @HostName AS HostName,
        'Session killed successfully' AS Status;
END
GO
