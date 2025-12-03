-- Sample 141: WAITFOR, RAISERROR, THROW, PRINT Statements
-- Category: Missing Syntax Elements / Control Flow
-- Complexity: Intermediate
-- Purpose: Parser testing - control and messaging statements
-- Features: WAITFOR, RAISERROR, THROW, PRINT, messaging patterns

-- Pattern 1: Basic PRINT statement
PRINT 'Hello, World!';
PRINT N'Unicode message: 日本語';
PRINT '';  -- Empty line
GO

-- Pattern 2: PRINT with expressions
DECLARE @msg NVARCHAR(200);
SET @msg = 'Current time: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT @msg;

PRINT 'Row count: ' + CAST(@@ROWCOUNT AS VARCHAR(10));
PRINT CONCAT('Server: ', @@SERVERNAME, ', Database: ', DB_NAME());
GO

-- Pattern 3: PRINT with variable substitution
DECLARE @Name NVARCHAR(50) = 'John';
DECLARE @Count INT = 42;
PRINT 'Hello, ' + @Name + '! You have ' + CAST(@Count AS VARCHAR(10)) + ' items.';
GO

-- Pattern 4: Basic RAISERROR
RAISERROR('This is an error message', 16, 1);
GO

-- Pattern 5: RAISERROR with severity levels
RAISERROR('Informational message', 0, 1);   -- Info
RAISERROR('Informational message', 10, 1);  -- Info
RAISERROR('Warning message', 11, 1);        -- Warning
RAISERROR('Error message', 16, 1);          -- Error
RAISERROR('Severe error', 17, 1);           -- Severe
-- RAISERROR('Critical error', 20, 1) WITH LOG;  -- Critical (requires WITH LOG)
GO

-- Pattern 6: RAISERROR with substitution parameters
RAISERROR('Error in procedure %s at line %d', 16, 1, 'MyProcedure', 100);
RAISERROR('Value %d exceeds maximum %d', 16, 1, 150, 100);
RAISERROR('Customer %s not found in table %s', 16, 1, 'CUST001', 'Customers');
GO

-- Pattern 7: RAISERROR format specifications
RAISERROR('Integer: %d, String: %s', 10, 1, 42, 'text');
RAISERROR('Padded integer: %10d', 10, 1, 42);
RAISERROR('Left-padded: %-10d end', 10, 1, 42);
RAISERROR('With width: %*d', 10, 1, 10, 42);  -- Width from argument
RAISERROR('Hex: %x, Octal: %o', 10, 1, 255, 255);
GO

-- Pattern 8: RAISERROR with NOWAIT
RAISERROR('Immediate message 1', 0, 1) WITH NOWAIT;
WAITFOR DELAY '00:00:01';
RAISERROR('Immediate message 2', 0, 1) WITH NOWAIT;
WAITFOR DELAY '00:00:01';
RAISERROR('Immediate message 3', 0, 1) WITH NOWAIT;
GO

-- Pattern 9: RAISERROR with LOG
-- RAISERROR('Logged error message', 18, 1) WITH LOG;
-- RAISERROR('Logged error', 19, 1) WITH LOG, NOWAIT;
GO

-- Pattern 10: RAISERROR with user-defined message
-- First, add message to sys.messages (requires permissions)
-- EXEC sp_addmessage @msgnum = 50001, @severity = 16, @msgtext = 'Custom error: %s';
-- Then use:
-- RAISERROR(50001, 16, 1, 'Parameter value');
GO

-- Pattern 11: Basic THROW (SQL Server 2012+)
THROW 50000, 'This is a thrown error', 1;
GO

-- Pattern 12: THROW in TRY/CATCH
BEGIN TRY
    -- Some operation that might fail
    SELECT 1/0;
END TRY
BEGIN CATCH
    THROW;  -- Re-throw the caught error
END CATCH
GO

-- Pattern 13: THROW with variables
DECLARE @ErrorNumber INT = 50001;
DECLARE @ErrorMessage NVARCHAR(200) = 'Dynamic error message';
DECLARE @ErrorState INT = 1;

THROW @ErrorNumber, @ErrorMessage, @ErrorState;
GO

-- Pattern 14: Conditional THROW
DECLARE @Value INT = 150;
DECLARE @MaxValue INT = 100;

IF @Value > @MaxValue
    THROW 50000, 'Value exceeds maximum allowed', 1;
GO

-- Pattern 15: THROW vs RAISERROR comparison
-- RAISERROR: More formatting options, can be info-level
-- THROW: Simpler syntax, always terminates batch, better for re-throwing

BEGIN TRY
    RAISERROR('RAISERROR error', 16, 1);
END TRY
BEGIN CATCH
    PRINT 'Caught RAISERROR: ' + ERROR_MESSAGE();
END CATCH

BEGIN TRY
    THROW 50000, 'THROW error', 1;
END TRY
BEGIN CATCH
    PRINT 'Caught THROW: ' + ERROR_MESSAGE();
END CATCH
GO

-- Pattern 16: Basic WAITFOR DELAY
WAITFOR DELAY '00:00:05';  -- Wait 5 seconds
PRINT 'After 5 second delay';
GO

-- Pattern 17: WAITFOR TIME (wait until specific time)
-- WAITFOR TIME '14:30:00';  -- Wait until 2:30 PM
-- PRINT 'It is now 2:30 PM';
GO

-- Pattern 18: WAITFOR with variable
DECLARE @DelayTime DATETIME = '00:00:02';
WAITFOR DELAY @DelayTime;
PRINT 'After variable delay';
GO

-- Pattern 19: WAITFOR with timeout
DECLARE @StartTime DATETIME = GETDATE();
WAITFOR DELAY '00:00:01';
PRINT 'Waited for ' + CAST(DATEDIFF(MILLISECOND, @StartTime, GETDATE()) AS VARCHAR(10)) + ' ms';
GO

-- Pattern 20: WAITFOR in loop (progress indicator)
DECLARE @i INT = 1;
WHILE @i <= 5
BEGIN
    RAISERROR('Processing step %d of 5...', 0, 1, @i) WITH NOWAIT;
    WAITFOR DELAY '00:00:01';
    SET @i = @i + 1;
END
PRINT 'Processing complete!';
GO

-- Pattern 21: Error handling with custom messages
CREATE PROCEDURE dbo.ProcessOrder
    @OrderID INT
AS
BEGIN
    SET NOCOUNT ON;
    
    IF @OrderID IS NULL
    BEGIN
        RAISERROR('OrderID cannot be NULL', 16, 1);
        RETURN -1;
    END
    
    IF NOT EXISTS (SELECT 1 FROM dbo.Orders WHERE OrderID = @OrderID)
    BEGIN
        THROW 50001, 'Order not found', 1;
    END
    
    PRINT 'Processing order: ' + CAST(@OrderID AS VARCHAR(10));
    -- Process logic here
    
    PRINT 'Order processed successfully';
    RETURN 0;
END;
GO

-- Pattern 22: Comprehensive error handling
CREATE PROCEDURE dbo.SafeOperation
AS
BEGIN
    SET NOCOUNT ON;
    
    BEGIN TRY
        PRINT 'Starting operation...';
        
        -- Simulate work
        WAITFOR DELAY '00:00:01';
        RAISERROR('Progress: 50%% complete', 0, 1) WITH NOWAIT;
        
        -- Simulate error
        SELECT 1/0;
        
        PRINT 'Operation completed';
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMsg NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSev INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        DECLARE @ErrorProc NVARCHAR(128) = ERROR_PROCEDURE();
        DECLARE @ErrorLine INT = ERROR_LINE();
        
        RAISERROR('Error in %s at line %d: %s', @ErrorSev, @ErrorState, 
            @ErrorProc, @ErrorLine, @ErrorMsg);
        
        -- Or use THROW to re-raise
        -- THROW;
    END CATCH
END;
GO

-- Pattern 23: Using PRINT for debugging
DECLARE @Debug BIT = 1;
DECLARE @Value INT = 100;

IF @Debug = 1
BEGIN
    PRINT '=== DEBUG INFO ===';
    PRINT 'Variable @Value = ' + CAST(@Value AS VARCHAR(10));
    PRINT 'Current user: ' + SUSER_SNAME();
    PRINT 'Current time: ' + CONVERT(VARCHAR(30), SYSDATETIME(), 121);
    PRINT '==================';
END

-- Continue processing...
SELECT @Value * 2 AS Result;
GO

-- Pattern 24: FORMATMESSAGE function
DECLARE @msg NVARCHAR(200);
SET @msg = FORMATMESSAGE('Error: ID=%d, Name=%s, Value=%d', 100, 'Test', 999);
RAISERROR(@msg, 16, 1);
GO

-- Pattern 25: Multiple statement terminators
PRINT 'Line 1'
PRINT 'Line 2';
PRINT 'Line 3';;  -- Double semicolon (empty statement)
GO

-- Cleanup
DROP PROCEDURE IF EXISTS dbo.ProcessOrder;
DROP PROCEDURE IF EXISTS dbo.SafeOperation;
GO
