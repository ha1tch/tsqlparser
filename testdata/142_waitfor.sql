-- Sample 142: WAITFOR and Timing Statements
-- Category: Missing Syntax Elements
-- Complexity: Intermediate
-- Purpose: Parser testing - WAITFOR syntax variations
-- Features: WAITFOR DELAY, WAITFOR TIME, WAITFOR with variables

-- Pattern 1: WAITFOR DELAY basic
WAITFOR DELAY '00:00:05';  -- Wait 5 seconds
SELECT 'Completed after 5 seconds' AS Message;
GO

-- Pattern 2: WAITFOR TIME (wait until specific time)
WAITFOR TIME '14:30:00';  -- Wait until 2:30 PM
SELECT 'It is now 2:30 PM' AS Message;
GO

-- Pattern 3: WAITFOR DELAY with variable
DECLARE @WaitTime VARCHAR(12) = '00:00:03';
WAITFOR DELAY @WaitTime;
SELECT 'Waited for ' + @WaitTime AS Message;
GO

-- Pattern 4: WAITFOR TIME with variable
DECLARE @TargetTime TIME = '15:00:00';
DECLARE @WaitTimeStr VARCHAR(12) = CONVERT(VARCHAR(12), @TargetTime, 108);
WAITFOR TIME @WaitTimeStr;
GO

-- Pattern 5: WAITFOR with milliseconds (extended format)
WAITFOR DELAY '00:00:00.500';  -- Wait 500 milliseconds
GO

-- Pattern 6: WAITFOR in loop for polling
DECLARE @Counter INT = 0;
DECLARE @MaxAttempts INT = 5;
DECLARE @Found BIT = 0;

WHILE @Counter < @MaxAttempts AND @Found = 0
BEGIN
    -- Check for condition
    IF EXISTS (SELECT 1 FROM dbo.ProcessQueue WHERE Status = 'Ready')
    BEGIN
        SET @Found = 1;
        SELECT 'Found ready item' AS Message;
    END
    ELSE
    BEGIN
        SET @Counter = @Counter + 1;
        WAITFOR DELAY '00:00:02';  -- Wait 2 seconds before retry
    END
END

IF @Found = 0
    SELECT 'Timeout after ' + CAST(@MaxAttempts AS VARCHAR(10)) + ' attempts' AS Message;
GO

-- Pattern 7: WAITFOR with timeout pattern
DECLARE @StartTime DATETIME = GETDATE();
DECLARE @TimeoutSeconds INT = 30;
DECLARE @Complete BIT = 0;

WHILE @Complete = 0 AND DATEDIFF(SECOND, @StartTime, GETDATE()) < @TimeoutSeconds
BEGIN
    IF EXISTS (SELECT 1 FROM dbo.AsyncResults WHERE RequestID = 12345)
    BEGIN
        SET @Complete = 1;
    END
    ELSE
    BEGIN
        WAITFOR DELAY '00:00:01';
    END
END

SELECT 
    CASE @Complete 
        WHEN 1 THEN 'Completed successfully' 
        ELSE 'Timed out' 
    END AS Status;
GO

-- Pattern 8: WAITFOR in stored procedure
CREATE PROCEDURE dbo.WaitAndProcess
    @DelaySeconds INT = 5
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @DelayStr VARCHAR(12);
    SET @DelayStr = CONVERT(VARCHAR(12), DATEADD(SECOND, @DelaySeconds, '00:00:00'), 108);
    
    SELECT 'Starting wait...' AS Status, GETDATE() AS StartTime;
    
    WAITFOR DELAY @DelayStr;
    
    SELECT 'Wait complete' AS Status, GETDATE() AS EndTime;
END;
GO

-- Pattern 9: WAITFOR for scheduled execution
CREATE PROCEDURE dbo.RunAtMidnight
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Calculate time until midnight
    DECLARE @Now DATETIME = GETDATE();
    DECLARE @Midnight DATETIME = DATEADD(DAY, 1, CAST(CAST(@Now AS DATE) AS DATETIME));
    DECLARE @WaitSeconds INT = DATEDIFF(SECOND, @Now, @Midnight);
    
    IF @WaitSeconds > 0
    BEGIN
        DECLARE @WaitStr VARCHAR(12);
        SET @WaitStr = CONVERT(VARCHAR(12), DATEADD(SECOND, @WaitSeconds, '00:00:00'), 108);
        WAITFOR DELAY @WaitStr;
    END
    
    -- Execute midnight task
    EXEC dbo.MidnightMaintenanceTask;
END;
GO

-- Pattern 10: WAITFOR with RECEIVE (Service Broker)
DECLARE @ConversationHandle UNIQUEIDENTIFIER;
DECLARE @MessageBody NVARCHAR(MAX);
DECLARE @MessageType NVARCHAR(256);

WAITFOR (
    RECEIVE TOP (1)
        @ConversationHandle = conversation_handle,
        @MessageBody = CAST(message_body AS NVARCHAR(MAX)),
        @MessageType = message_type_name
    FROM dbo.TargetQueue
), TIMEOUT 5000;  -- 5 second timeout

IF @ConversationHandle IS NOT NULL
    SELECT @MessageType AS MessageType, @MessageBody AS MessageBody;
ELSE
    SELECT 'No message received within timeout' AS Status;
GO

-- Pattern 11: WAITFOR with GET CONVERSATION GROUP
DECLARE @ConversationGroupID UNIQUEIDENTIFIER;

WAITFOR (
    GET CONVERSATION GROUP @ConversationGroupID FROM dbo.TargetQueue
), TIMEOUT 1000;

IF @ConversationGroupID IS NOT NULL
    SELECT 'Got conversation group: ' + CAST(@ConversationGroupID AS VARCHAR(36)) AS Status;
GO

-- Pattern 12: Cascading delays
DECLARE @Step INT = 1;

WHILE @Step <= 3
BEGIN
    SELECT 'Executing step ' + CAST(@Step AS VARCHAR(10)) AS Status, GETDATE() AS ExecutionTime;
    
    -- Exponential backoff
    DECLARE @DelaySeconds INT = POWER(2, @Step - 1);
    DECLARE @DelayStr VARCHAR(12) = RIGHT('00' + CAST(@DelaySeconds / 3600 AS VARCHAR(2)), 2) + ':' +
                                     RIGHT('00' + CAST((@DelaySeconds % 3600) / 60 AS VARCHAR(2)), 2) + ':' +
                                     RIGHT('00' + CAST(@DelaySeconds % 60 AS VARCHAR(2)), 2);
    
    WAITFOR DELAY @DelayStr;
    SET @Step = @Step + 1;
END
GO

-- Pattern 13: Using WAITFOR for rate limiting
CREATE PROCEDURE dbo.RateLimitedBatchProcess
    @BatchSize INT = 100,
    @DelayBetweenBatches VARCHAR(12) = '00:00:01'
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @ProcessedCount INT = 0;
    DECLARE @TotalToProcess INT;
    
    SELECT @TotalToProcess = COUNT(*) FROM dbo.ItemsToProcess WHERE Processed = 0;
    
    WHILE @ProcessedCount < @TotalToProcess
    BEGIN
        UPDATE TOP (@BatchSize) dbo.ItemsToProcess
        SET Processed = 1, ProcessedDate = GETDATE()
        WHERE Processed = 0;
        
        SET @ProcessedCount = @ProcessedCount + @@ROWCOUNT;
        
        IF @ProcessedCount < @TotalToProcess
            WAITFOR DELAY @DelayBetweenBatches;
    END
    
    SELECT @ProcessedCount AS TotalProcessed;
END;
GO

-- Cleanup
DROP PROCEDURE IF EXISTS dbo.WaitAndProcess;
DROP PROCEDURE IF EXISTS dbo.RunAtMidnight;
DROP PROCEDURE IF EXISTS dbo.RateLimitedBatchProcess;
GO
