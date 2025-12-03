-- Sample 048: Queue and Message Processing Patterns
-- Source: Various - Service Broker patterns, MSSQLTips, Stack Overflow
-- Category: Integration
-- Complexity: Advanced
-- Features: Queue tables, message processing, retry logic, dead letter handling

-- Create message queue infrastructure
CREATE PROCEDURE dbo.SetupMessageQueue
    @QueueName NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @QueueTable NVARCHAR(128) = 'Queue_' + @QueueName;
    DECLARE @DeadLetterTable NVARCHAR(128) = 'DeadLetter_' + @QueueName;
    
    -- Main queue table
    SET @SQL = N'
        IF OBJECT_ID(''dbo.' + @QueueTable + ''', ''U'') IS NULL
        BEGIN
            CREATE TABLE dbo.' + QUOTENAME(@QueueTable) + ' (
                MessageID BIGINT IDENTITY(1,1) PRIMARY KEY,
                MessageType NVARCHAR(100) NOT NULL,
                MessageBody NVARCHAR(MAX) NOT NULL,
                Priority INT DEFAULT 5,
                Status NVARCHAR(20) DEFAULT ''Pending'',
                CorrelationID UNIQUEIDENTIFIER,
                RetryCount INT DEFAULT 0,
                MaxRetries INT DEFAULT 3,
                CreatedDate DATETIME2 DEFAULT SYSDATETIME(),
                ProcessingStartDate DATETIME2,
                ProcessingEndDate DATETIME2,
                ProcessedBy NVARCHAR(128),
                ErrorMessage NVARCHAR(MAX),
                ScheduledDate DATETIME2 DEFAULT SYSDATETIME(),
                INDEX IX_Status_Priority (Status, Priority DESC, ScheduledDate),
                INDEX IX_CorrelationID (CorrelationID)
            );
        END';
    EXEC sp_executesql @SQL;
    
    -- Dead letter queue
    SET @SQL = N'
        IF OBJECT_ID(''dbo.' + @DeadLetterTable + ''', ''U'') IS NULL
        BEGIN
            CREATE TABLE dbo.' + QUOTENAME(@DeadLetterTable) + ' (
                DeadLetterID BIGINT IDENTITY(1,1) PRIMARY KEY,
                OriginalMessageID BIGINT,
                MessageType NVARCHAR(100),
                MessageBody NVARCHAR(MAX),
                CorrelationID UNIQUEIDENTIFIER,
                ErrorMessage NVARCHAR(MAX),
                RetryCount INT,
                OriginalCreatedDate DATETIME2,
                DeadLetterDate DATETIME2 DEFAULT SYSDATETIME(),
                Reason NVARCHAR(100)
            );
        END';
    EXEC sp_executesql @SQL;
    
    SELECT 'Queue infrastructure created' AS Status, @QueueTable AS QueueTable, @DeadLetterTable AS DeadLetterTable;
END
GO

-- Enqueue a message
CREATE PROCEDURE dbo.EnqueueMessage
    @QueueName NVARCHAR(128),
    @MessageType NVARCHAR(100),
    @MessageBody NVARCHAR(MAX),
    @Priority INT = 5,
    @CorrelationID UNIQUEIDENTIFIER = NULL,
    @ScheduledDate DATETIME2 = NULL,
    @MaxRetries INT = 3,
    @MessageID BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @QueueTable NVARCHAR(128) = 'Queue_' + @QueueName;
    
    SET @ScheduledDate = ISNULL(@ScheduledDate, SYSDATETIME());
    
    SET @SQL = N'
        INSERT INTO dbo.' + QUOTENAME(@QueueTable) + '
        (MessageType, MessageBody, Priority, CorrelationID, ScheduledDate, MaxRetries)
        VALUES (@MsgType, @MsgBody, @Pri, @CorrID, @SchedDate, @MaxRet);
        
        SET @OutMsgID = SCOPE_IDENTITY();';
    
    EXEC sp_executesql @SQL,
        N'@MsgType NVARCHAR(100), @MsgBody NVARCHAR(MAX), @Pri INT, @CorrID UNIQUEIDENTIFIER, 
          @SchedDate DATETIME2, @MaxRet INT, @OutMsgID BIGINT OUTPUT',
        @MsgType = @MessageType,
        @MsgBody = @MessageBody,
        @Pri = @Priority,
        @CorrID = @CorrelationID,
        @SchedDate = @ScheduledDate,
        @MaxRet = @MaxRetries,
        @OutMsgID = @MessageID OUTPUT;
    
    SELECT @MessageID AS MessageID;
END
GO

-- Dequeue and lock next message
CREATE PROCEDURE dbo.DequeueMessage
    @QueueName NVARCHAR(128),
    @MessageType NVARCHAR(100) = NULL,
    @ProcessorName NVARCHAR(128) = NULL,
    @MessageID BIGINT OUTPUT,
    @MessageBody NVARCHAR(MAX) OUTPUT,
    @MsgType NVARCHAR(100) OUTPUT,
    @CorrelationID UNIQUEIDENTIFIER OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @QueueTable NVARCHAR(128) = 'Queue_' + @QueueName;
    
    SET @ProcessorName = ISNULL(@ProcessorName, HOST_NAME() + '-' + CAST(@@SPID AS NVARCHAR(10)));
    
    -- Use UPDATE with OUTPUT to atomically claim a message
    SET @SQL = N'
        UPDATE TOP (1) q
        SET Status = ''Processing'',
            ProcessingStartDate = SYSDATETIME(),
            ProcessedBy = @Processor
        OUTPUT 
            inserted.MessageID,
            inserted.MessageBody,
            inserted.MessageType,
            inserted.CorrelationID
        INTO @OutputTable
        FROM dbo.' + QUOTENAME(@QueueTable) + ' q WITH (ROWLOCK, READPAST)
        WHERE Status = ''Pending''
          AND ScheduledDate <= SYSDATETIME()
          AND (@MsgType IS NULL OR MessageType = @MsgType)
        ORDER BY Priority DESC, CreatedDate;
        
        SELECT @OutMsgID = MessageID, @OutMsgBody = MessageBody, 
               @OutMsgType = MessageType, @OutCorrID = CorrelationID
        FROM @OutputTable;';
    
    DECLARE @OutputTable TABLE (
        MessageID BIGINT,
        MessageBody NVARCHAR(MAX),
        MessageType NVARCHAR(100),
        CorrelationID UNIQUEIDENTIFIER
    );
    
    -- Execute with proper variable handling
    SET @SQL = N'
        DECLARE @OT TABLE (MessageID BIGINT, MessageBody NVARCHAR(MAX), MessageType NVARCHAR(100), CorrelationID UNIQUEIDENTIFIER);
        
        UPDATE TOP (1) q
        SET Status = ''Processing'',
            ProcessingStartDate = SYSDATETIME(),
            ProcessedBy = @Processor
        OUTPUT inserted.MessageID, inserted.MessageBody, inserted.MessageType, inserted.CorrelationID
        INTO @OT
        FROM dbo.' + QUOTENAME(@QueueTable) + ' q WITH (ROWLOCK, READPAST)
        WHERE Status = ''Pending''
          AND ScheduledDate <= SYSDATETIME()
          AND (@MsgTypeFilter IS NULL OR MessageType = @MsgTypeFilter);
        
        SELECT @OutMsgID = MessageID, @OutMsgBody = MessageBody, 
               @OutMsgType = MessageType, @OutCorrID = CorrelationID
        FROM @OT;';
    
    EXEC sp_executesql @SQL,
        N'@Processor NVARCHAR(128), @MsgTypeFilter NVARCHAR(100),
          @OutMsgID BIGINT OUTPUT, @OutMsgBody NVARCHAR(MAX) OUTPUT,
          @OutMsgType NVARCHAR(100) OUTPUT, @OutCorrID UNIQUEIDENTIFIER OUTPUT',
        @Processor = @ProcessorName,
        @MsgTypeFilter = @MessageType,
        @OutMsgID = @MessageID OUTPUT,
        @OutMsgBody = @MessageBody OUTPUT,
        @OutMsgType = @MsgType OUTPUT,
        @OutCorrID = @CorrelationID OUTPUT;
END
GO

-- Complete message processing
CREATE PROCEDURE dbo.CompleteMessage
    @QueueName NVARCHAR(128),
    @MessageID BIGINT,
    @Success BIT,
    @ErrorMessage NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @QueueTable NVARCHAR(128) = 'Queue_' + @QueueName;
    DECLARE @DeadLetterTable NVARCHAR(128) = 'DeadLetter_' + @QueueName;
    DECLARE @RetryCount INT;
    DECLARE @MaxRetries INT;
    
    -- Get current retry info
    SET @SQL = N'SELECT @RC = RetryCount, @MR = MaxRetries FROM dbo.' + QUOTENAME(@QueueTable) + ' WHERE MessageID = @MsgID';
    EXEC sp_executesql @SQL, N'@MsgID BIGINT, @RC INT OUTPUT, @MR INT OUTPUT',
        @MsgID = @MessageID, @RC = @RetryCount OUTPUT, @MR = @MaxRetries OUTPUT;
    
    IF @Success = 1
    BEGIN
        -- Mark as completed
        SET @SQL = N'
            UPDATE dbo.' + QUOTENAME(@QueueTable) + '
            SET Status = ''Completed'',
                ProcessingEndDate = SYSDATETIME()
            WHERE MessageID = @MsgID';
        EXEC sp_executesql @SQL, N'@MsgID BIGINT', @MsgID = @MessageID;
    END
    ELSE IF @RetryCount < @MaxRetries
    BEGIN
        -- Retry with exponential backoff
        DECLARE @RetryDelay INT = POWER(2, @RetryCount) * 60;  -- seconds
        
        SET @SQL = N'
            UPDATE dbo.' + QUOTENAME(@QueueTable) + '
            SET Status = ''Pending'',
                RetryCount = RetryCount + 1,
                ProcessingStartDate = NULL,
                ProcessedBy = NULL,
                ErrorMessage = @ErrMsg,
                ScheduledDate = DATEADD(SECOND, @Delay, SYSDATETIME())
            WHERE MessageID = @MsgID';
        EXEC sp_executesql @SQL, N'@MsgID BIGINT, @ErrMsg NVARCHAR(MAX), @Delay INT',
            @MsgID = @MessageID, @ErrMsg = @ErrorMessage, @Delay = @RetryDelay;
    END
    ELSE
    BEGIN
        -- Move to dead letter queue
        SET @SQL = N'
            INSERT INTO dbo.' + QUOTENAME(@DeadLetterTable) + '
            (OriginalMessageID, MessageType, MessageBody, CorrelationID, ErrorMessage, RetryCount, OriginalCreatedDate, Reason)
            SELECT MessageID, MessageType, MessageBody, CorrelationID, @ErrMsg, RetryCount, CreatedDate, ''Max retries exceeded''
            FROM dbo.' + QUOTENAME(@QueueTable) + '
            WHERE MessageID = @MsgID;
            
            DELETE FROM dbo.' + QUOTENAME(@QueueTable) + ' WHERE MessageID = @MsgID;';
        EXEC sp_executesql @SQL, N'@MsgID BIGINT, @ErrMsg NVARCHAR(MAX)',
            @MsgID = @MessageID, @ErrMsg = @ErrorMessage;
    END
    
    SELECT @Success AS Success, @MessageID AS MessageID;
END
GO

-- Get queue statistics
CREATE PROCEDURE dbo.GetQueueStats
    @QueueName NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @QueueTable NVARCHAR(128) = 'Queue_' + @QueueName;
    DECLARE @DeadLetterTable NVARCHAR(128) = 'DeadLetter_' + @QueueName;
    
    -- Queue status
    SET @SQL = N'
        SELECT 
            Status,
            COUNT(*) AS MessageCount,
            AVG(DATEDIFF(SECOND, CreatedDate, ISNULL(ProcessingEndDate, SYSDATETIME()))) AS AvgProcessingTimeSec,
            MIN(CreatedDate) AS OldestMessage
        FROM dbo.' + QUOTENAME(@QueueTable) + '
        GROUP BY Status';
    EXEC sp_executesql @SQL;
    
    -- Dead letter count
    SET @SQL = N'SELECT COUNT(*) AS DeadLetterCount FROM dbo.' + QUOTENAME(@DeadLetterTable);
    EXEC sp_executesql @SQL;
    
    -- Throughput (last hour)
    SET @SQL = N'
        SELECT 
            COUNT(*) AS ProcessedLastHour,
            COUNT(*) / 60.0 AS MessagesPerMinute
        FROM dbo.' + QUOTENAME(@QueueTable) + '
        WHERE Status = ''Completed''
          AND ProcessingEndDate >= DATEADD(HOUR, -1, SYSDATETIME())';
    EXEC sp_executesql @SQL;
END
GO
