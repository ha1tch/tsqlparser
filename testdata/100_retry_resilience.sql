-- Sample 100: Query Retry and Resilience Patterns
-- Source: Various - Azure patterns, Polly.NET patterns, Transient fault handling
-- Category: Error Handling
-- Complexity: Advanced
-- Features: Retry logic, circuit breaker, timeout handling, transient error detection

-- Execute with retry for transient errors
CREATE PROCEDURE dbo.ExecuteWithRetry
    @SQL NVARCHAR(MAX),
    @Parameters NVARCHAR(MAX) = NULL,
    @MaxRetries INT = 3,
    @InitialDelayMs INT = 100,
    @MaxDelayMs INT = 5000,
    @ExponentialBackoff BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @RetryCount INT = 0;
    DECLARE @CurrentDelay INT = @InitialDelayMs;
    DECLARE @Success BIT = 0;
    DECLARE @ErrorNumber INT;
    DECLARE @ErrorMessage NVARCHAR(MAX);
    DECLARE @ErrorSeverity INT;
    DECLARE @StartTime DATETIME2 = SYSDATETIME();
    
    -- Transient error numbers that warrant retry
    DECLARE @TransientErrors TABLE (ErrorNumber INT);
    INSERT INTO @TransientErrors VALUES 
        (1205),   -- Deadlock victim
        (1222),   -- Lock request timeout
        (3960),   -- Snapshot isolation abort
        (3961),   -- Snapshot isolation failure
        (8645),   -- Timeout waiting for memory
        (8651),   -- Low memory condition
        (17197),  -- Login timeout
        (10053),  -- Connection broken
        (10054),  -- Connection reset
        (10060),  -- Connection timeout
        (40143),  -- Connection could not be initialized
        (40197),  -- Service error processing request
        (40501),  -- Service busy
        (40613),  -- Database not available
        (49918),  -- Not enough resources
        (49919),  -- Cannot process request
        (49920);  -- Cannot process request
    
    WHILE @RetryCount <= @MaxRetries AND @Success = 0
    BEGIN
        BEGIN TRY
            IF @Parameters IS NOT NULL
                EXEC sp_executesql @SQL, @Parameters;
            ELSE
                EXEC sp_executesql @SQL;
            
            SET @Success = 1;
        END TRY
        BEGIN CATCH
            SET @ErrorNumber = ERROR_NUMBER();
            SET @ErrorMessage = ERROR_MESSAGE();
            SET @ErrorSeverity = ERROR_SEVERITY();
            
            -- Check if transient error
            IF EXISTS (SELECT 1 FROM @TransientErrors WHERE ErrorNumber = @ErrorNumber)
            BEGIN
                SET @RetryCount = @RetryCount + 1;
                
                IF @RetryCount <= @MaxRetries
                BEGIN
                    -- Calculate delay
                    IF @ExponentialBackoff = 1
                        SET @CurrentDelay = CASE 
                            WHEN @CurrentDelay * 2 > @MaxDelayMs THEN @MaxDelayMs 
                            ELSE @CurrentDelay * 2 
                        END;
                    
                    -- Add jitter (random 0-20%)
                    SET @CurrentDelay = @CurrentDelay + (@CurrentDelay * (ABS(CHECKSUM(NEWID())) % 20) / 100);
                    
                    -- Wait before retry
                    DECLARE @WaitTime VARCHAR(12) = '00:00:00.' + RIGHT('000' + CAST(@CurrentDelay AS VARCHAR(3)), 3);
                    IF @CurrentDelay >= 1000
                        SET @WaitTime = '00:00:' + RIGHT('0' + CAST(@CurrentDelay / 1000 AS VARCHAR(2)), 2) + '.' + RIGHT('000' + CAST(@CurrentDelay % 1000 AS VARCHAR(3)), 3);
                    
                    WAITFOR DELAY @WaitTime;
                END
            END
            ELSE
            BEGIN
                -- Non-transient error, throw immediately
                THROW;
            END
        END CATCH
    END
    
    IF @Success = 0
    BEGIN
        RAISERROR('Max retries exceeded. Last error: %s', 16, 1, @ErrorMessage);
    END
    
    SELECT 
        @Success AS Success,
        @RetryCount AS RetriesUsed,
        DATEDIFF(MILLISECOND, @StartTime, SYSDATETIME()) AS TotalTimeMs,
        @ErrorNumber AS LastErrorNumber,
        @ErrorMessage AS LastErrorMessage;
END
GO

-- Circuit breaker pattern
CREATE PROCEDURE dbo.SetupCircuitBreaker
AS
BEGIN
    SET NOCOUNT ON;
    
    IF OBJECT_ID('dbo.CircuitBreakerState', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.CircuitBreakerState (
            CircuitName NVARCHAR(100) PRIMARY KEY,
            State NVARCHAR(20) DEFAULT 'Closed',  -- Closed, Open, HalfOpen
            FailureCount INT DEFAULT 0,
            LastFailureTime DATETIME2,
            LastSuccessTime DATETIME2,
            OpenUntil DATETIME2,
            FailureThreshold INT DEFAULT 5,
            ResetTimeoutSeconds INT DEFAULT 60,
            HalfOpenSuccessThreshold INT DEFAULT 3,
            HalfOpenSuccessCount INT DEFAULT 0
        );
    END
    
    SELECT 'Circuit breaker infrastructure created' AS Status;
END
GO

-- Check circuit breaker before execution
CREATE FUNCTION dbo.CanExecute(@CircuitName NVARCHAR(100))
RETURNS BIT
AS
BEGIN
    DECLARE @CanExecute BIT = 1;
    DECLARE @State NVARCHAR(20);
    DECLARE @OpenUntil DATETIME2;
    
    SELECT @State = State, @OpenUntil = OpenUntil
    FROM dbo.CircuitBreakerState
    WHERE CircuitName = @CircuitName;
    
    IF @State = 'Open' AND @OpenUntil > SYSDATETIME()
        SET @CanExecute = 0;
    
    RETURN @CanExecute;
END
GO

-- Record circuit breaker result
CREATE PROCEDURE dbo.RecordCircuitResult
    @CircuitName NVARCHAR(100),
    @Success BIT
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Ensure circuit exists
    IF NOT EXISTS (SELECT 1 FROM dbo.CircuitBreakerState WHERE CircuitName = @CircuitName)
        INSERT INTO dbo.CircuitBreakerState (CircuitName) VALUES (@CircuitName);
    
    DECLARE @CurrentState NVARCHAR(20);
    DECLARE @FailureCount INT;
    DECLARE @FailureThreshold INT;
    DECLARE @ResetTimeoutSeconds INT;
    DECLARE @HalfOpenSuccessThreshold INT;
    DECLARE @HalfOpenSuccessCount INT;
    
    SELECT 
        @CurrentState = State,
        @FailureCount = FailureCount,
        @FailureThreshold = FailureThreshold,
        @ResetTimeoutSeconds = ResetTimeoutSeconds,
        @HalfOpenSuccessThreshold = HalfOpenSuccessThreshold,
        @HalfOpenSuccessCount = HalfOpenSuccessCount
    FROM dbo.CircuitBreakerState
    WHERE CircuitName = @CircuitName;
    
    IF @Success = 1
    BEGIN
        IF @CurrentState = 'HalfOpen'
        BEGIN
            SET @HalfOpenSuccessCount = @HalfOpenSuccessCount + 1;
            IF @HalfOpenSuccessCount >= @HalfOpenSuccessThreshold
            BEGIN
                -- Reset to closed
                UPDATE dbo.CircuitBreakerState
                SET State = 'Closed', FailureCount = 0, HalfOpenSuccessCount = 0, LastSuccessTime = SYSDATETIME()
                WHERE CircuitName = @CircuitName;
            END
            ELSE
            BEGIN
                UPDATE dbo.CircuitBreakerState
                SET HalfOpenSuccessCount = @HalfOpenSuccessCount, LastSuccessTime = SYSDATETIME()
                WHERE CircuitName = @CircuitName;
            END
        END
        ELSE
        BEGIN
            -- Success in closed state
            UPDATE dbo.CircuitBreakerState
            SET FailureCount = 0, LastSuccessTime = SYSDATETIME()
            WHERE CircuitName = @CircuitName;
        END
    END
    ELSE
    BEGIN
        SET @FailureCount = @FailureCount + 1;
        
        IF @FailureCount >= @FailureThreshold OR @CurrentState = 'HalfOpen'
        BEGIN
            -- Open the circuit
            UPDATE dbo.CircuitBreakerState
            SET State = 'Open', 
                FailureCount = @FailureCount,
                LastFailureTime = SYSDATETIME(),
                OpenUntil = DATEADD(SECOND, @ResetTimeoutSeconds, SYSDATETIME()),
                HalfOpenSuccessCount = 0
            WHERE CircuitName = @CircuitName;
        END
        ELSE
        BEGIN
            UPDATE dbo.CircuitBreakerState
            SET FailureCount = @FailureCount, LastFailureTime = SYSDATETIME()
            WHERE CircuitName = @CircuitName;
        END
    END
END
GO

-- Execute with timeout
CREATE PROCEDURE dbo.ExecuteWithTimeout
    @SQL NVARCHAR(MAX),
    @TimeoutSeconds INT = 30
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @StartTime DATETIME2 = SYSDATETIME();
    DECLARE @EndTime DATETIME2;
    DECLARE @Success BIT = 0;
    
    -- Set query timeout (applies to next statement)
    DECLARE @SetTimeout NVARCHAR(100) = 'SET LOCK_TIMEOUT ' + CAST(@TimeoutSeconds * 1000 AS VARCHAR(10));
    EXEC sp_executesql @SetTimeout;
    
    BEGIN TRY
        EXEC sp_executesql @SQL;
        SET @Success = 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() = 1222  -- Lock timeout
            RAISERROR('Query timed out after %d seconds', 16, 1, @TimeoutSeconds);
        ELSE
            THROW;
    END CATCH
    
    -- Reset timeout
    EXEC sp_executesql N'SET LOCK_TIMEOUT -1';
    
    SET @EndTime = SYSDATETIME();
    
    SELECT 
        @Success AS Success,
        DATEDIFF(MILLISECOND, @StartTime, @EndTime) AS ExecutionTimeMs;
END
GO

-- Get circuit breaker status
CREATE PROCEDURE dbo.GetCircuitBreakerStatus
    @CircuitName NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        CircuitName,
        State,
        FailureCount,
        FailureThreshold,
        LastFailureTime,
        LastSuccessTime,
        CASE 
            WHEN State = 'Open' AND OpenUntil > SYSDATETIME() 
            THEN DATEDIFF(SECOND, SYSDATETIME(), OpenUntil) 
            ELSE 0 
        END AS SecondsUntilReset,
        HalfOpenSuccessCount,
        HalfOpenSuccessThreshold
    FROM dbo.CircuitBreakerState
    WHERE @CircuitName IS NULL OR CircuitName = @CircuitName;
END
GO
