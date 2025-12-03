-- Sample 025: Change Data Capture (CDC) Procedures
-- Source: Microsoft Learn, MSSQLTips, SQLShack
-- Category: Audit Trail
-- Complexity: Advanced
-- Features: CDC functions, sys.sp_cdc_*, change tracking, LSN handling

-- Enable CDC on database and table
CREATE PROCEDURE dbo.EnableCDCForTable
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @RoleName NVARCHAR(128) = NULL,
    @CaptureInstance NVARCHAR(128) = NULL,
    @SupportsNetChanges BIT = 1,
    @IndexName NVARCHAR(128) = NULL,
    @CapturedColumnList NVARCHAR(MAX) = NULL,
    @FilegroupName NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @DatabaseName NVARCHAR(128) = DB_NAME();
    
    -- Check if CDC is enabled on the database
    IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = @DatabaseName AND is_cdc_enabled = 1)
    BEGIN
        PRINT 'Enabling CDC on database ' + @DatabaseName;
        EXEC sys.sp_cdc_enable_db;
    END
    
    -- Check if table already has CDC enabled
    IF EXISTS (
        SELECT 1 FROM cdc.change_tables ct
        INNER JOIN sys.tables t ON ct.source_object_id = t.object_id
        INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
        WHERE t.name = @TableName AND s.name = @SchemaName
    )
    BEGIN
        PRINT 'CDC is already enabled for ' + @SchemaName + '.' + @TableName;
        RETURN;
    END
    
    -- Enable CDC on the table
    EXEC sys.sp_cdc_enable_table
        @source_schema = @SchemaName,
        @source_name = @TableName,
        @role_name = @RoleName,
        @capture_instance = @CaptureInstance,
        @supports_net_changes = @SupportsNetChanges,
        @index_name = @IndexName,
        @captured_column_list = @CapturedColumnList,
        @filegroup_name = @FilegroupName;
    
    PRINT 'CDC enabled for ' + @SchemaName + '.' + @TableName;
    
    -- Return CDC configuration info
    SELECT 
        ct.capture_instance,
        OBJECT_SCHEMA_NAME(ct.source_object_id) AS source_schema,
        OBJECT_NAME(ct.source_object_id) AS source_table,
        ct.supports_net_changes,
        ct.has_drop_pending,
        ct.role_name,
        ct.index_name,
        ct.filegroup_name,
        ct.create_date
    FROM cdc.change_tables ct
    WHERE ct.source_object_id = OBJECT_ID(@SchemaName + '.' + @TableName);
END
GO

-- Get changes from CDC table
CREATE PROCEDURE dbo.GetCDCChanges
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @FromDate DATETIME = NULL,
    @ToDate DATETIME = NULL,
    @OperationFilter NVARCHAR(20) = NULL,  -- INSERT, UPDATE, DELETE, ALL
    @NetChangesOnly BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @CaptureInstance NVARCHAR(128);
    DECLARE @FromLSN BINARY(10);
    DECLARE @ToLSN BINARY(10);
    DECLARE @SQL NVARCHAR(MAX);
    
    -- Get capture instance name
    SELECT @CaptureInstance = ct.capture_instance
    FROM cdc.change_tables ct
    WHERE ct.source_object_id = OBJECT_ID(@SchemaName + '.' + @TableName);
    
    IF @CaptureInstance IS NULL
    BEGIN
        RAISERROR('CDC is not enabled for table %s.%s', 16, 1, @SchemaName, @TableName);
        RETURN;
    END
    
    -- Convert dates to LSN
    SET @FromDate = ISNULL(@FromDate, DATEADD(DAY, -1, GETDATE()));
    SET @ToDate = ISNULL(@ToDate, GETDATE());
    
    SET @FromLSN = sys.fn_cdc_map_time_to_lsn('smallest greater than or equal', @FromDate);
    SET @ToLSN = sys.fn_cdc_map_time_to_lsn('largest less than or equal', @ToDate);
    
    IF @FromLSN IS NULL
        SET @FromLSN = sys.fn_cdc_get_min_lsn(@CaptureInstance);
    
    IF @ToLSN IS NULL
        SET @ToLSN = sys.fn_cdc_get_max_lsn();
    
    -- Build query based on options
    IF @NetChangesOnly = 1
    BEGIN
        SET @SQL = N'
            SELECT 
                sys.fn_cdc_map_lsn_to_time(__$start_lsn) AS ChangeTime,
                CASE __$operation
                    WHEN 1 THEN ''DELETE''
                    WHEN 2 THEN ''INSERT''
                    WHEN 3 THEN ''UPDATE (Before)''
                    WHEN 4 THEN ''UPDATE (After)''
                    WHEN 5 THEN ''MERGE''
                END AS Operation,
                *
            FROM cdc.fn_cdc_get_net_changes_' + @CaptureInstance + '(@FromLSN, @ToLSN, ''all'')';
    END
    ELSE
    BEGIN
        SET @SQL = N'
            SELECT 
                sys.fn_cdc_map_lsn_to_time(__$start_lsn) AS ChangeTime,
                CASE __$operation
                    WHEN 1 THEN ''DELETE''
                    WHEN 2 THEN ''INSERT''
                    WHEN 3 THEN ''UPDATE (Before)''
                    WHEN 4 THEN ''UPDATE (After)''
                END AS Operation,
                *
            FROM cdc.fn_cdc_get_all_changes_' + @CaptureInstance + '(@FromLSN, @ToLSN, ''all'')';
    END
    
    -- Add operation filter
    IF @OperationFilter IS NOT NULL AND @OperationFilter <> 'ALL'
    BEGIN
        SET @SQL = @SQL + ' WHERE __$operation = ' + 
            CASE @OperationFilter
                WHEN 'DELETE' THEN '1'
                WHEN 'INSERT' THEN '2'
                WHEN 'UPDATE' THEN '4'
                ELSE '0'
            END;
    END
    
    SET @SQL = @SQL + ' ORDER BY __$start_lsn, __$seqval';
    
    EXEC sp_executesql @SQL,
        N'@FromLSN BINARY(10), @ToLSN BINARY(10)',
        @FromLSN = @FromLSN,
        @ToLSN = @ToLSN;
END
GO

-- Get CDC status and statistics
CREATE PROCEDURE dbo.GetCDCStatus
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Database CDC status
    SELECT 
        name AS DatabaseName,
        is_cdc_enabled AS CDCEnabled
    FROM sys.databases
    WHERE database_id = DB_ID();
    
    -- Tables with CDC enabled
    SELECT 
        OBJECT_SCHEMA_NAME(ct.source_object_id) AS SchemaName,
        OBJECT_NAME(ct.source_object_id) AS TableName,
        ct.capture_instance,
        ct.supports_net_changes,
        ct.role_name,
        ct.index_name,
        ct.create_date,
        sys.fn_cdc_get_min_lsn(ct.capture_instance) AS MinLSN,
        sys.fn_cdc_get_max_lsn() AS MaxLSN,
        sys.fn_cdc_map_lsn_to_time(sys.fn_cdc_get_min_lsn(ct.capture_instance)) AS MinChangeTime,
        sys.fn_cdc_map_lsn_to_time(sys.fn_cdc_get_max_lsn()) AS MaxChangeTime
    FROM cdc.change_tables ct;
    
    -- CDC jobs status
    SELECT 
        j.name AS JobName,
        j.enabled AS IsEnabled,
        ja.start_execution_date AS LastStartTime,
        ja.stop_execution_date AS LastStopTime,
        CASE 
            WHEN ja.stop_execution_date IS NULL AND ja.start_execution_date IS NOT NULL 
            THEN 'Running'
            ELSE 'Stopped'
        END AS Status
    FROM msdb.dbo.sysjobs j
    LEFT JOIN msdb.dbo.sysjobactivity ja ON j.job_id = ja.job_id
        AND ja.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)
    WHERE j.name LIKE 'cdc.%';
    
    -- CDC change table sizes
    SELECT 
        OBJECT_SCHEMA_NAME(ct.source_object_id) AS SourceSchema,
        OBJECT_NAME(ct.source_object_id) AS SourceTable,
        ct.capture_instance,
        p.rows AS ChangeRowCount,
        CAST(SUM(a.total_pages) * 8.0 / 1024 AS DECIMAL(18,2)) AS ChangeSizeMB
    FROM cdc.change_tables ct
    INNER JOIN sys.partitions p ON p.object_id = ct.object_id
    INNER JOIN sys.allocation_units a ON a.container_id = p.partition_id
    WHERE p.index_id IN (0, 1)
    GROUP BY ct.source_object_id, ct.capture_instance, ct.object_id, p.rows;
END
GO

-- Cleanup old CDC data
CREATE PROCEDURE dbo.CleanupCDCData
    @RetentionDays INT = 3,
    @BatchSize INT = 5000
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @CaptureInstance NVARCHAR(128);
    DECLARE @CutoffLSN BINARY(10);
    DECLARE @CutoffTime DATETIME;
    
    SET @CutoffTime = DATEADD(DAY, -@RetentionDays, GETDATE());
    SET @CutoffLSN = sys.fn_cdc_map_time_to_lsn('largest less than or equal', @CutoffTime);
    
    IF @CutoffLSN IS NULL
    BEGIN
        PRINT 'No CDC data older than ' + CAST(@RetentionDays AS VARCHAR(10)) + ' days';
        RETURN;
    END
    
    -- Cleanup each capture instance
    DECLARE InstanceCursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT capture_instance FROM cdc.change_tables;
    
    OPEN InstanceCursor;
    FETCH NEXT FROM InstanceCursor INTO @CaptureInstance;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        PRINT 'Cleaning up CDC data for: ' + @CaptureInstance;
        
        EXEC sys.sp_cdc_cleanup_change_table
            @capture_instance = @CaptureInstance,
            @low_water_mark = @CutoffLSN,
            @threshold = @BatchSize;
        
        FETCH NEXT FROM InstanceCursor INTO @CaptureInstance;
    END
    
    CLOSE InstanceCursor;
    DEALLOCATE InstanceCursor;
    
    PRINT 'CDC cleanup completed';
END
GO
