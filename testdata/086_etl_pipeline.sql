-- Sample 086: ETL Pipeline Management
-- Source: Various - SSIS patterns, MSSQLTips, ETL best practices
-- Category: ETL/Data Loading
-- Complexity: Advanced
-- Features: ETL orchestration, checkpoint/restart, error handling, logging

-- Setup ETL infrastructure
CREATE PROCEDURE dbo.SetupETLInfrastructure
AS
BEGIN
    SET NOCOUNT ON;
    
    -- ETL Packages registry
    IF OBJECT_ID('dbo.ETLPackages', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.ETLPackages (
            PackageID INT IDENTITY(1,1) PRIMARY KEY,
            PackageName NVARCHAR(200) NOT NULL UNIQUE,
            Description NVARCHAR(MAX),
            SourceSystem NVARCHAR(100),
            TargetSchema NVARCHAR(128),
            TargetTable NVARCHAR(128),
            LoadType NVARCHAR(20),  -- FULL, INCREMENTAL, DELTA
            IsActive BIT DEFAULT 1,
            CreatedDate DATETIME2 DEFAULT SYSDATETIME(),
            LastModified DATETIME2 DEFAULT SYSDATETIME()
        );
    END
    
    -- ETL Execution log
    IF OBJECT_ID('dbo.ETLExecutionLog', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.ETLExecutionLog (
            ExecutionID BIGINT IDENTITY(1,1) PRIMARY KEY,
            PackageID INT REFERENCES dbo.ETLPackages(PackageID),
            BatchID UNIQUEIDENTIFIER DEFAULT NEWID(),
            StartTime DATETIME2 DEFAULT SYSDATETIME(),
            EndTime DATETIME2,
            Status NVARCHAR(20),  -- Running, Success, Failed, Cancelled
            RowsExtracted INT,
            RowsTransformed INT,
            RowsLoaded INT,
            RowsRejected INT,
            ErrorMessage NVARCHAR(MAX),
            ExecutedBy NVARCHAR(128) DEFAULT SUSER_SNAME()
        );
    END
    
    -- ETL Checkpoints for restart capability
    IF OBJECT_ID('dbo.ETLCheckpoints', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.ETLCheckpoints (
            CheckpointID INT IDENTITY(1,1) PRIMARY KEY,
            PackageID INT REFERENCES dbo.ETLPackages(PackageID),
            CheckpointName NVARCHAR(100),
            CheckpointValue NVARCHAR(MAX),
            LastUpdated DATETIME2 DEFAULT SYSDATETIME(),
            UNIQUE (PackageID, CheckpointName)
        );
    END
    
    -- ETL Error staging
    IF OBJECT_ID('dbo.ETLErrorStaging', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.ETLErrorStaging (
            ErrorID BIGINT IDENTITY(1,1) PRIMARY KEY,
            ExecutionID BIGINT,
            PackageID INT,
            ErrorTime DATETIME2 DEFAULT SYSDATETIME(),
            SourceRowData NVARCHAR(MAX),
            ErrorCode NVARCHAR(50),
            ErrorMessage NVARCHAR(MAX),
            IsReprocessed BIT DEFAULT 0
        );
    END
    
    SELECT 'ETL infrastructure created' AS Status;
END
GO

-- Start ETL execution
CREATE PROCEDURE dbo.StartETLExecution
    @PackageName NVARCHAR(200),
    @ExecutionID BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @PackageID INT;
    
    SELECT @PackageID = PackageID
    FROM dbo.ETLPackages
    WHERE PackageName = @PackageName AND IsActive = 1;
    
    IF @PackageID IS NULL
    BEGIN
        RAISERROR('Package not found or inactive: %s', 16, 1, @PackageName);
        RETURN;
    END
    
    -- Check for already running execution
    IF EXISTS (SELECT 1 FROM dbo.ETLExecutionLog WHERE PackageID = @PackageID AND Status = 'Running')
    BEGIN
        RAISERROR('Package is already running: %s', 16, 1, @PackageName);
        RETURN;
    END
    
    -- Start new execution
    INSERT INTO dbo.ETLExecutionLog (PackageID, Status)
    VALUES (@PackageID, 'Running');
    
    SET @ExecutionID = SCOPE_IDENTITY();
    
    SELECT @ExecutionID AS ExecutionID, 'Started' AS Status;
END
GO

-- Update ETL execution status
CREATE PROCEDURE dbo.UpdateETLExecution
    @ExecutionID BIGINT,
    @Status NVARCHAR(20) = NULL,
    @RowsExtracted INT = NULL,
    @RowsTransformed INT = NULL,
    @RowsLoaded INT = NULL,
    @RowsRejected INT = NULL,
    @ErrorMessage NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    UPDATE dbo.ETLExecutionLog
    SET Status = ISNULL(@Status, Status),
        RowsExtracted = ISNULL(@RowsExtracted, RowsExtracted),
        RowsTransformed = ISNULL(@RowsTransformed, RowsTransformed),
        RowsLoaded = ISNULL(@RowsLoaded, RowsLoaded),
        RowsRejected = ISNULL(@RowsRejected, RowsRejected),
        ErrorMessage = ISNULL(@ErrorMessage, ErrorMessage),
        EndTime = CASE WHEN @Status IN ('Success', 'Failed', 'Cancelled') THEN SYSDATETIME() ELSE EndTime END
    WHERE ExecutionID = @ExecutionID;
END
GO

-- Set/Get ETL checkpoint
CREATE PROCEDURE dbo.ManageETLCheckpoint
    @PackageName NVARCHAR(200),
    @CheckpointName NVARCHAR(100),
    @Action NVARCHAR(10),  -- GET, SET, CLEAR
    @CheckpointValue NVARCHAR(MAX) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @PackageID INT;
    SELECT @PackageID = PackageID FROM dbo.ETLPackages WHERE PackageName = @PackageName;
    
    IF @Action = 'GET'
    BEGIN
        SELECT @CheckpointValue = CheckpointValue
        FROM dbo.ETLCheckpoints
        WHERE PackageID = @PackageID AND CheckpointName = @CheckpointName;
    END
    ELSE IF @Action = 'SET'
    BEGIN
        MERGE dbo.ETLCheckpoints AS target
        USING (SELECT @PackageID, @CheckpointName, @CheckpointValue) AS source (PackageID, CheckpointName, CheckpointValue)
        ON target.PackageID = source.PackageID AND target.CheckpointName = source.CheckpointName
        WHEN MATCHED THEN UPDATE SET CheckpointValue = source.CheckpointValue, LastUpdated = SYSDATETIME()
        WHEN NOT MATCHED THEN INSERT (PackageID, CheckpointName, CheckpointValue) VALUES (source.PackageID, source.CheckpointName, source.CheckpointValue);
    END
    ELSE IF @Action = 'CLEAR'
    BEGIN
        DELETE FROM dbo.ETLCheckpoints WHERE PackageID = @PackageID AND CheckpointName = @CheckpointName;
    END
END
GO

-- Log ETL error
CREATE PROCEDURE dbo.LogETLError
    @ExecutionID BIGINT,
    @SourceRowData NVARCHAR(MAX),
    @ErrorCode NVARCHAR(50),
    @ErrorMessage NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @PackageID INT;
    SELECT @PackageID = PackageID FROM dbo.ETLExecutionLog WHERE ExecutionID = @ExecutionID;
    
    INSERT INTO dbo.ETLErrorStaging (ExecutionID, PackageID, SourceRowData, ErrorCode, ErrorMessage)
    VALUES (@ExecutionID, @PackageID, @SourceRowData, @ErrorCode, @ErrorMessage);
END
GO

-- Incremental load helper
CREATE PROCEDURE dbo.PerformIncrementalLoad
    @SourceQuery NVARCHAR(MAX),
    @TargetSchema NVARCHAR(128),
    @TargetTable NVARCHAR(128),
    @KeyColumns NVARCHAR(MAX),  -- Comma-separated
    @WatermarkColumn NVARCHAR(128),
    @LastWatermark NVARCHAR(MAX),
    @ExecutionID BIGINT,
    @NewWatermark NVARCHAR(MAX) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FullTarget NVARCHAR(256) = QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable);
    DECLARE @MergeJoin NVARCHAR(MAX) = '';
    DECLARE @RowsInserted INT = 0;
    DECLARE @RowsUpdated INT = 0;
    
    -- Build join condition
    SELECT @MergeJoin = STRING_AGG('target.' + QUOTENAME(LTRIM(RTRIM(value))) + ' = source.' + QUOTENAME(LTRIM(RTRIM(value))), ' AND ')
    FROM STRING_SPLIT(@KeyColumns, ',');
    
    -- Apply watermark filter
    IF @LastWatermark IS NOT NULL
    BEGIN
        SET @SourceQuery = @SourceQuery + ' WHERE ' + QUOTENAME(@WatermarkColumn) + ' > ''' + @LastWatermark + '''';
    END
    
    -- Get new watermark
    SET @SQL = N'SELECT @NewWM = MAX(' + QUOTENAME(@WatermarkColumn) + ') FROM (' + @SourceQuery + ') AS src';
    EXEC sp_executesql @SQL, N'@NewWM NVARCHAR(MAX) OUTPUT', @NewWM = @NewWatermark OUTPUT;
    
    -- Build column lists
    DECLARE @Columns NVARCHAR(MAX);
    DECLARE @UpdateSet NVARCHAR(MAX);
    
    SELECT @Columns = STRING_AGG(QUOTENAME(name), ', ')
    FROM sys.columns WHERE object_id = OBJECT_ID(@FullTarget);
    
    SELECT @UpdateSet = STRING_AGG('target.' + QUOTENAME(name) + ' = source.' + QUOTENAME(name), ', ')
    FROM sys.columns 
    WHERE object_id = OBJECT_ID(@FullTarget)
      AND name NOT IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@KeyColumns, ','));
    
    -- Execute MERGE
    SET @SQL = N'
        MERGE ' + @FullTarget + ' AS target
        USING (' + @SourceQuery + ') AS source
        ON ' + @MergeJoin + '
        WHEN MATCHED THEN UPDATE SET ' + @UpdateSet + '
        WHEN NOT MATCHED THEN INSERT (' + @Columns + ') VALUES (' + @Columns + ')
        OUTPUT $action INTO #MergeOutput;
        
        SELECT @Ins = SUM(CASE WHEN action_type = ''INSERT'' THEN 1 ELSE 0 END),
               @Upd = SUM(CASE WHEN action_type = ''UPDATE'' THEN 1 ELSE 0 END)
        FROM #MergeOutput';
    
    CREATE TABLE #MergeOutput (action_type NVARCHAR(10));
    EXEC sp_executesql @SQL, N'@Ins INT OUTPUT, @Upd INT OUTPUT', @Ins = @RowsInserted OUTPUT, @Upd = @RowsUpdated OUTPUT;
    
    -- Update execution log
    EXEC dbo.UpdateETLExecution @ExecutionID, NULL, NULL, NULL, @RowsInserted + @RowsUpdated, NULL, NULL;
    
    DROP TABLE #MergeOutput;
    
    SELECT @RowsInserted AS RowsInserted, @RowsUpdated AS RowsUpdated, @NewWatermark AS NewWatermark;
END
GO

-- Get ETL execution history
CREATE PROCEDURE dbo.GetETLExecutionHistory
    @PackageName NVARCHAR(200) = NULL,
    @DaysBack INT = 7
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        p.PackageName,
        e.ExecutionID,
        e.BatchID,
        e.StartTime,
        e.EndTime,
        DATEDIFF(SECOND, e.StartTime, e.EndTime) AS DurationSeconds,
        e.Status,
        e.RowsExtracted,
        e.RowsTransformed,
        e.RowsLoaded,
        e.RowsRejected,
        e.ErrorMessage,
        e.ExecutedBy
    FROM dbo.ETLExecutionLog e
    INNER JOIN dbo.ETLPackages p ON e.PackageID = p.PackageID
    WHERE e.StartTime >= DATEADD(DAY, -@DaysBack, GETDATE())
      AND (@PackageName IS NULL OR p.PackageName = @PackageName)
    ORDER BY e.StartTime DESC;
END
GO
