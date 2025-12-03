-- Sample 076: Row Versioning and Snapshot Isolation
-- Source: Microsoft Learn, Kendra Little, MSSQLTips
-- Category: Error Handling
-- Complexity: Advanced
-- Features: SNAPSHOT isolation, READ_COMMITTED_SNAPSHOT, version store, tempdb analysis

-- Enable snapshot isolation for database
CREATE PROCEDURE dbo.EnableSnapshotIsolation
    @DatabaseName NVARCHAR(128) = NULL,
    @EnableSnapshot BIT = 1,
    @EnableRCSI BIT = 1,  -- Read Committed Snapshot Isolation
    @WhatIf BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @DatabaseName = ISNULL(@DatabaseName, DB_NAME());
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @CurrentSnapshot BIT;
    DECLARE @CurrentRCSI BIT;
    
    -- Get current settings
    SELECT @CurrentSnapshot = snapshot_isolation_state,
           @CurrentRCSI = is_read_committed_snapshot_on
    FROM sys.databases
    WHERE name = @DatabaseName;
    
    -- Show current and proposed settings
    SELECT 
        @DatabaseName AS DatabaseName,
        @CurrentSnapshot AS CurrentSnapshotIsolation,
        @EnableSnapshot AS ProposedSnapshotIsolation,
        @CurrentRCSI AS CurrentRCSI,
        @EnableRCSI AS ProposedRCSI;
    
    IF @WhatIf = 1
    BEGIN
        SELECT 'WhatIf mode - no changes made.' AS Status,
               'NOTE: Enabling RCSI requires exclusive database access' AS Warning;
        RETURN;
    END
    
    -- Enable/Disable Snapshot Isolation
    IF @EnableSnapshot <> @CurrentSnapshot
    BEGIN
        SET @SQL = 'ALTER DATABASE ' + QUOTENAME(@DatabaseName) + 
                   ' SET ALLOW_SNAPSHOT_ISOLATION ' + 
                   CASE WHEN @EnableSnapshot = 1 THEN 'ON' ELSE 'OFF' END;
        EXEC sp_executesql @SQL;
        PRINT 'Snapshot isolation ' + CASE WHEN @EnableSnapshot = 1 THEN 'enabled' ELSE 'disabled' END;
    END
    
    -- Enable/Disable RCSI (requires single user mode)
    IF @EnableRCSI <> @CurrentRCSI
    BEGIN
        SET @SQL = 'ALTER DATABASE ' + QUOTENAME(@DatabaseName) + ' SET SINGLE_USER WITH ROLLBACK IMMEDIATE';
        EXEC sp_executesql @SQL;
        
        SET @SQL = 'ALTER DATABASE ' + QUOTENAME(@DatabaseName) + 
                   ' SET READ_COMMITTED_SNAPSHOT ' + 
                   CASE WHEN @EnableRCSI = 1 THEN 'ON' ELSE 'OFF' END;
        EXEC sp_executesql @SQL;
        
        SET @SQL = 'ALTER DATABASE ' + QUOTENAME(@DatabaseName) + ' SET MULTI_USER';
        EXEC sp_executesql @SQL;
        
        PRINT 'RCSI ' + CASE WHEN @EnableRCSI = 1 THEN 'enabled' ELSE 'disabled' END;
    END
    
    SELECT 'Changes applied successfully' AS Status;
END
GO

-- Analyze version store usage
CREATE PROCEDURE dbo.AnalyzeVersionStore
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Version store size in tempdb
    SELECT 
        SUM(version_store_reserved_page_count) * 8 / 1024 AS VersionStoreMB,
        SUM(user_object_reserved_page_count) * 8 / 1024 AS UserObjectsMB,
        SUM(internal_object_reserved_page_count) * 8 / 1024 AS InternalObjectsMB,
        SUM(unallocated_extent_page_count) * 8 / 1024 AS FreeSpaceMB
    FROM sys.dm_db_file_space_usage;
    
    -- Version store by database
    SELECT 
        DB_NAME(database_id) AS DatabaseName,
        reserved_page_count * 8 / 1024 AS ReservedMB,
        reserved_space_kb / 1024 AS ReservedSpaceKB
    FROM sys.dm_tran_version_store_space_usage
    ORDER BY reserved_page_count DESC;
    
    -- Active transactions using version store
    SELECT 
        t.transaction_id,
        t.transaction_sequence_num AS TransactionSeq,
        t.elapsed_time_seconds AS ElapsedSeconds,
        s.session_id,
        s.login_name,
        s.host_name,
        s.program_name,
        CASE t.transaction_state
            WHEN 0 THEN 'Uninitialized'
            WHEN 1 THEN 'Initialized'
            WHEN 2 THEN 'Active'
            WHEN 3 THEN 'Ended'
            WHEN 4 THEN 'Commit Started'
            WHEN 5 THEN 'Prepared'
            WHEN 6 THEN 'Committed'
            WHEN 7 THEN 'Rolling Back'
            WHEN 8 THEN 'Rolled Back'
        END AS TransactionState,
        r.command,
        r.wait_type,
        SUBSTRING(st.text, (r.statement_start_offset/2) + 1,
            ((CASE r.statement_end_offset
                WHEN -1 THEN DATALENGTH(st.text)
                ELSE r.statement_end_offset
            END - r.statement_start_offset)/2) + 1) AS CurrentStatement
    FROM sys.dm_tran_active_snapshot_database_transactions t
    INNER JOIN sys.dm_exec_sessions s ON t.session_id = s.session_id
    LEFT JOIN sys.dm_exec_requests r ON s.session_id = r.session_id
    OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) st
    ORDER BY t.elapsed_time_seconds DESC;
END
GO

-- Get snapshot isolation status for all databases
CREATE PROCEDURE dbo.GetSnapshotIsolationStatus
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        name AS DatabaseName,
        snapshot_isolation_state_desc AS SnapshotIsolation,
        is_read_committed_snapshot_on AS RCSIEnabled,
        CASE 
            WHEN snapshot_isolation_state = 1 OR is_read_committed_snapshot_on = 1 
            THEN 'Using version store'
            ELSE 'Traditional locking'
        END AS IsolationMode,
        state_desc AS DatabaseState
    FROM sys.databases
    ORDER BY name;
END
GO

-- Find long-running snapshot transactions
CREATE PROCEDURE dbo.FindLongRunningSnapshotTransactions
    @ThresholdSeconds INT = 300
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        t.transaction_id,
        t.elapsed_time_seconds AS ElapsedSeconds,
        s.session_id,
        s.login_name,
        s.host_name,
        s.program_name,
        DB_NAME(s.database_id) AS DatabaseName,
        t.first_snapshot_sequence_num AS FirstSnapshotSeq,
        t.max_version_chain_traversed AS MaxVersionChain,
        t.average_version_chain_traversed AS AvgVersionChain,
        'Consider investigating or terminating' AS Recommendation
    FROM sys.dm_tran_active_snapshot_database_transactions t
    INNER JOIN sys.dm_exec_sessions s ON t.session_id = s.session_id
    WHERE t.elapsed_time_seconds >= @ThresholdSeconds
    ORDER BY t.elapsed_time_seconds DESC;
END
GO

-- Clean up version store (force cleanup)
CREATE PROCEDURE dbo.ForceVersionStoreCleanup
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Get current version store size
    DECLARE @BeforeSize BIGINT;
    SELECT @BeforeSize = SUM(version_store_reserved_page_count) * 8 / 1024
    FROM sys.dm_db_file_space_usage;
    
    -- Run checkpoint to flush dirty pages
    CHECKPOINT;
    
    -- Wait a moment for cleanup
    WAITFOR DELAY '00:00:05';
    
    -- Get new size
    DECLARE @AfterSize BIGINT;
    SELECT @AfterSize = SUM(version_store_reserved_page_count) * 8 / 1024
    FROM sys.dm_db_file_space_usage;
    
    SELECT 
        @BeforeSize AS VersionStoreBeforeMB,
        @AfterSize AS VersionStoreAfterMB,
        @BeforeSize - @AfterSize AS ReclaimedMB,
        'Note: Version store only cleans up when no transactions need old versions' AS Note;
END
GO

-- Monitor version store growth
CREATE PROCEDURE dbo.MonitorVersionStoreGrowth
    @SampleIntervalSeconds INT = 10,
    @SampleCount INT = 6
AS
BEGIN
    SET NOCOUNT ON;
    
    CREATE TABLE #VersionStoreHistory (
        SampleTime DATETIME2,
        VersionStoreMB DECIMAL(18,2)
    );
    
    DECLARE @i INT = 0;
    
    WHILE @i < @SampleCount
    BEGIN
        INSERT INTO #VersionStoreHistory
        SELECT 
            SYSDATETIME(),
            SUM(version_store_reserved_page_count) * 8.0 / 1024
        FROM sys.dm_db_file_space_usage;
        
        SET @i = @i + 1;
        
        IF @i < @SampleCount
            WAITFOR DELAY @SampleIntervalSeconds;
    END
    
    SELECT 
        SampleTime,
        VersionStoreMB,
        VersionStoreMB - LAG(VersionStoreMB) OVER (ORDER BY SampleTime) AS GrowthMB,
        CASE 
            WHEN VersionStoreMB > LAG(VersionStoreMB) OVER (ORDER BY SampleTime) THEN 'Growing'
            WHEN VersionStoreMB < LAG(VersionStoreMB) OVER (ORDER BY SampleTime) THEN 'Shrinking'
            ELSE 'Stable'
        END AS Trend
    FROM #VersionStoreHistory
    ORDER BY SampleTime;
    
    DROP TABLE #VersionStoreHistory;
END
GO
