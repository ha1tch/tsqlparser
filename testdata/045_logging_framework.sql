-- Sample 045: Application Logging Framework
-- Source: Various - MSSQLTips, Stack Overflow, Enterprise patterns
-- Category: Audit Trail
-- Complexity: Complex
-- Features: Structured logging, log levels, log rotation, correlation IDs

-- Create logging infrastructure
CREATE PROCEDURE dbo.SetupLoggingInfrastructure
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Main log table
    IF OBJECT_ID('dbo.ApplicationLog', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.ApplicationLog (
            LogID BIGINT IDENTITY(1,1) PRIMARY KEY,
            LogTime DATETIME2(3) DEFAULT SYSDATETIME(),
            LogLevel NVARCHAR(10) NOT NULL,  -- DEBUG, INFO, WARN, ERROR, FATAL
            Category NVARCHAR(100),
            Message NVARCHAR(MAX),
            Exception NVARCHAR(MAX),
            CorrelationID UNIQUEIDENTIFIER,
            SessionID INT,
            UserName NVARCHAR(128),
            HostName NVARCHAR(128),
            ApplicationName NVARCHAR(128),
            ProcedureName NVARCHAR(128),
            LineNumber INT,
            AdditionalData NVARCHAR(MAX),  -- JSON for structured data
            INDEX IX_LogTime NONCLUSTERED (LogTime),
            INDEX IX_LogLevel NONCLUSTERED (LogLevel, LogTime),
            INDEX IX_CorrelationID NONCLUSTERED (CorrelationID),
            INDEX IX_Category NONCLUSTERED (Category, LogTime)
        );
        
        PRINT 'Created ApplicationLog table';
    END
    
    -- Log level configuration
    IF OBJECT_ID('dbo.LogConfiguration', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.LogConfiguration (
            ConfigKey NVARCHAR(100) PRIMARY KEY,
            ConfigValue NVARCHAR(500),
            Description NVARCHAR(500)
        );
        
        INSERT INTO dbo.LogConfiguration VALUES
            ('MinLogLevel', 'INFO', 'Minimum log level to record (DEBUG, INFO, WARN, ERROR, FATAL)'),
            ('RetentionDays', '30', 'Days to retain log entries'),
            ('MaxEntriesPerMinute', '1000', 'Rate limit for log entries'),
            ('EnableConsoleOutput', '0', 'Print log entries to console');
        
        PRINT 'Created LogConfiguration table';
    END
END
GO

-- Main logging procedure
CREATE PROCEDURE dbo.WriteLog
    @LogLevel NVARCHAR(10),
    @Message NVARCHAR(MAX),
    @Category NVARCHAR(100) = NULL,
    @Exception NVARCHAR(MAX) = NULL,
    @CorrelationID UNIQUEIDENTIFIER = NULL,
    @ProcedureName NVARCHAR(128) = NULL,
    @LineNumber INT = NULL,
    @AdditionalData NVARCHAR(MAX) = NULL  -- JSON
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @MinLogLevel NVARCHAR(10);
    DECLARE @LogLevelOrder INT;
    DECLARE @MinLevelOrder INT;
    DECLARE @EnableConsole BIT;
    
    -- Get configuration
    SELECT @MinLogLevel = ConfigValue FROM dbo.LogConfiguration WHERE ConfigKey = 'MinLogLevel';
    SELECT @EnableConsole = CAST(ConfigValue AS BIT) FROM dbo.LogConfiguration WHERE ConfigKey = 'EnableConsoleOutput';
    
    -- Map log levels to order
    SET @LogLevelOrder = CASE @LogLevel
        WHEN 'DEBUG' THEN 1
        WHEN 'INFO' THEN 2
        WHEN 'WARN' THEN 3
        WHEN 'ERROR' THEN 4
        WHEN 'FATAL' THEN 5
        ELSE 2
    END;
    
    SET @MinLevelOrder = CASE @MinLogLevel
        WHEN 'DEBUG' THEN 1
        WHEN 'INFO' THEN 2
        WHEN 'WARN' THEN 3
        WHEN 'ERROR' THEN 4
        WHEN 'FATAL' THEN 5
        ELSE 2
    END;
    
    -- Check if we should log
    IF @LogLevelOrder < @MinLevelOrder
        RETURN;
    
    -- Insert log entry
    INSERT INTO dbo.ApplicationLog (
        LogLevel, Category, Message, Exception, CorrelationID,
        SessionID, UserName, HostName, ApplicationName,
        ProcedureName, LineNumber, AdditionalData
    )
    VALUES (
        @LogLevel, @Category, @Message, @Exception, @CorrelationID,
        @@SPID, SUSER_SNAME(), HOST_NAME(), APP_NAME(),
        @ProcedureName, @LineNumber, @AdditionalData
    );
    
    -- Console output if enabled
    IF @EnableConsole = 1
        PRINT CONVERT(VARCHAR(23), SYSDATETIME(), 121) + ' [' + @LogLevel + '] ' + @Message;
END
GO

-- Convenience procedures for each log level
CREATE PROCEDURE dbo.LogDebug @Message NVARCHAR(MAX), @Category NVARCHAR(100) = NULL, @CorrelationID UNIQUEIDENTIFIER = NULL
AS EXEC dbo.WriteLog 'DEBUG', @Message, @Category, NULL, @CorrelationID;
GO

CREATE PROCEDURE dbo.LogInfo @Message NVARCHAR(MAX), @Category NVARCHAR(100) = NULL, @CorrelationID UNIQUEIDENTIFIER = NULL
AS EXEC dbo.WriteLog 'INFO', @Message, @Category, NULL, @CorrelationID;
GO

CREATE PROCEDURE dbo.LogWarn @Message NVARCHAR(MAX), @Category NVARCHAR(100) = NULL, @CorrelationID UNIQUEIDENTIFIER = NULL
AS EXEC dbo.WriteLog 'WARN', @Message, @Category, NULL, @CorrelationID;
GO

CREATE PROCEDURE dbo.LogError @Message NVARCHAR(MAX), @Category NVARCHAR(100) = NULL, @Exception NVARCHAR(MAX) = NULL, @CorrelationID UNIQUEIDENTIFIER = NULL
AS EXEC dbo.WriteLog 'ERROR', @Message, @Category, @Exception, @CorrelationID;
GO

-- Query logs with filtering
CREATE PROCEDURE dbo.QueryLogs
    @StartTime DATETIME2 = NULL,
    @EndTime DATETIME2 = NULL,
    @LogLevel NVARCHAR(10) = NULL,
    @Category NVARCHAR(100) = NULL,
    @CorrelationID UNIQUEIDENTIFIER = NULL,
    @SearchText NVARCHAR(500) = NULL,
    @UserName NVARCHAR(128) = NULL,
    @TopN INT = 1000
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @StartTime = ISNULL(@StartTime, DATEADD(HOUR, -24, SYSDATETIME()));
    SET @EndTime = ISNULL(@EndTime, SYSDATETIME());
    
    SELECT TOP (@TopN)
        LogID,
        LogTime,
        LogLevel,
        Category,
        Message,
        Exception,
        CorrelationID,
        UserName,
        HostName,
        ApplicationName,
        ProcedureName,
        AdditionalData
    FROM dbo.ApplicationLog
    WHERE LogTime BETWEEN @StartTime AND @EndTime
      AND (@LogLevel IS NULL OR LogLevel = @LogLevel)
      AND (@Category IS NULL OR Category = @Category)
      AND (@CorrelationID IS NULL OR CorrelationID = @CorrelationID)
      AND (@SearchText IS NULL OR Message LIKE '%' + @SearchText + '%')
      AND (@UserName IS NULL OR UserName = @UserName)
    ORDER BY LogTime DESC;
END
GO

-- Get log statistics
CREATE PROCEDURE dbo.GetLogStatistics
    @Hours INT = 24
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @StartTime DATETIME2 = DATEADD(HOUR, -@Hours, SYSDATETIME());
    
    -- By log level
    SELECT 
        LogLevel,
        COUNT(*) AS EntryCount,
        MIN(LogTime) AS FirstEntry,
        MAX(LogTime) AS LastEntry
    FROM dbo.ApplicationLog
    WHERE LogTime >= @StartTime
    GROUP BY LogLevel
    ORDER BY 
        CASE LogLevel
            WHEN 'FATAL' THEN 1
            WHEN 'ERROR' THEN 2
            WHEN 'WARN' THEN 3
            WHEN 'INFO' THEN 4
            WHEN 'DEBUG' THEN 5
        END;
    
    -- By category
    SELECT TOP 20
        Category,
        COUNT(*) AS EntryCount,
        SUM(CASE WHEN LogLevel = 'ERROR' THEN 1 ELSE 0 END) AS Errors,
        SUM(CASE WHEN LogLevel = 'WARN' THEN 1 ELSE 0 END) AS Warnings
    FROM dbo.ApplicationLog
    WHERE LogTime >= @StartTime
    GROUP BY Category
    ORDER BY EntryCount DESC;
    
    -- Hourly trend
    SELECT 
        DATEADD(HOUR, DATEDIFF(HOUR, 0, LogTime), 0) AS Hour,
        COUNT(*) AS TotalEntries,
        SUM(CASE WHEN LogLevel IN ('ERROR', 'FATAL') THEN 1 ELSE 0 END) AS ErrorCount
    FROM dbo.ApplicationLog
    WHERE LogTime >= @StartTime
    GROUP BY DATEADD(HOUR, DATEDIFF(HOUR, 0, LogTime), 0)
    ORDER BY Hour;
END
GO

-- Cleanup old logs
CREATE PROCEDURE dbo.CleanupOldLogs
    @RetentionDays INT = NULL,
    @BatchSize INT = 10000
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Get retention from config if not specified
    IF @RetentionDays IS NULL
        SELECT @RetentionDays = CAST(ConfigValue AS INT) 
        FROM dbo.LogConfiguration 
        WHERE ConfigKey = 'RetentionDays';
    
    SET @RetentionDays = ISNULL(@RetentionDays, 30);
    
    DECLARE @CutoffDate DATETIME2 = DATEADD(DAY, -@RetentionDays, SYSDATETIME());
    DECLARE @DeletedCount INT = 1;
    DECLARE @TotalDeleted INT = 0;
    
    WHILE @DeletedCount > 0
    BEGIN
        DELETE TOP (@BatchSize)
        FROM dbo.ApplicationLog
        WHERE LogTime < @CutoffDate;
        
        SET @DeletedCount = @@ROWCOUNT;
        SET @TotalDeleted = @TotalDeleted + @DeletedCount;
        
        IF @DeletedCount > 0
            WAITFOR DELAY '00:00:00.100';
    END
    
    -- Log the cleanup
    EXEC dbo.LogInfo 
        @Message = 'Log cleanup completed',
        @Category = 'Maintenance',
        @AdditionalData = CONCAT('{"deletedCount":', @TotalDeleted, ',"retentionDays":', @RetentionDays, '}');
    
    SELECT @TotalDeleted AS EntriesDeleted, @RetentionDays AS RetentionDays;
END
GO
