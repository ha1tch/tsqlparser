-- Sample 143: PRINT, RAISERROR, and THROW Statements
-- Category: Missing Syntax Elements
-- Complexity: Intermediate
-- Purpose: Parser testing - messaging and error statements
-- Features: PRINT, RAISERROR variations, THROW, message formatting

-- Pattern 1: Basic PRINT
PRINT 'Hello, World!';
PRINT N'Unicode message: 日本語';
GO

-- Pattern 2: PRINT with variables
DECLARE @Message NVARCHAR(200) = 'Processing started';
DECLARE @Count INT = 100;
PRINT @Message;
PRINT 'Processing ' + CAST(@Count AS VARCHAR(10)) + ' records';
GO

-- Pattern 3: PRINT with CONCAT
DECLARE @Name NVARCHAR(50) = 'John';
DECLARE @Age INT = 30;
PRINT CONCAT('Name: ', @Name, ', Age: ', @Age);
GO

-- Pattern 4: Basic RAISERROR with severity and state
RAISERROR('This is an error message', 10, 1);  -- Informational (severity 10)
RAISERROR('This is a warning', 11, 1);  -- Warning
RAISERROR('This is an error', 16, 1);  -- Error
GO

-- Pattern 5: RAISERROR with substitution parameters
DECLARE @TableName NVARCHAR(128) = 'Customers';
DECLARE @RowCount INT = 500;
RAISERROR('Table %s contains %d rows', 10, 1, @TableName, @RowCount);
GO

-- Pattern 6: RAISERROR format specifiers
RAISERROR('String: %s', 10, 1, 'Hello');
RAISERROR('Integer: %d', 10, 1, 12345);
RAISERROR('Integer with width: %10d', 10, 1, 123);
RAISERROR('Left-aligned: %-10s|', 10, 1, 'Left');
RAISERROR('Hex lowercase: %x', 10, 1, 255);
RAISERROR('Hex uppercase: %X', 10, 1, 255);
RAISERROR('Multiple: %s processed %d items in %d seconds', 10, 1, 'Batch', 100, 5);
GO

-- Pattern 7: RAISERROR with NOWAIT
DECLARE @i INT = 1;
WHILE @i <= 5
BEGIN
    RAISERROR('Processing step %d of 5', 10, 1, @i) WITH NOWAIT;
    WAITFOR DELAY '00:00:01';
    SET @i = @i + 1;
END
GO

-- Pattern 8: RAISERROR with LOG option
RAISERROR('Critical error occurred - logged to error log', 18, 1) WITH LOG;
GO

-- Pattern 9: RAISERROR with custom error message (sp_addmessage)
-- EXEC sp_addmessage @msgnum = 50001, @severity = 16, 
--      @msgtext = N'Customer %s not found in database %s';
-- RAISERROR(50001, 16, 1, 'CUST001', 'SalesDB');
GO

-- Pattern 10: Basic THROW
BEGIN TRY
    -- Some operation that fails
    DECLARE @x INT = 1 / 0;
END TRY
BEGIN CATCH
    THROW;  -- Re-throw the caught error
END CATCH
GO

-- Pattern 11: THROW with custom error
BEGIN TRY
    IF NOT EXISTS (SELECT 1 FROM dbo.Customers WHERE CustomerID = 99999)
    BEGIN
        THROW 50001, 'Customer not found', 1;
    END
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
END CATCH
GO

-- Pattern 12: THROW with formatted message
DECLARE @ErrorMessage NVARCHAR(200);
DECLARE @CustomerID INT = 12345;

SET @ErrorMessage = CONCAT('Customer ID ', @CustomerID, ' does not exist');

BEGIN TRY
    THROW 50002, @ErrorMessage, 1;
END TRY
BEGIN CATCH
    SELECT ERROR_MESSAGE() AS ErrorMessage;
END CATCH
GO

-- Pattern 13: RAISERROR vs THROW comparison
-- RAISERROR does NOT abort batch (severity < 20)
RAISERROR('Error with RAISERROR', 16, 1);
SELECT 'This line executes after RAISERROR' AS Result;
GO

-- THROW aborts the batch
BEGIN TRY
    THROW 50000, 'Error with THROW', 1;
    SELECT 'This line does NOT execute' AS Result;
END TRY
BEGIN CATCH
    SELECT 'Caught the THROW' AS Result;
END CATCH
GO

-- Pattern 14: Error message with all ERROR_* functions
BEGIN TRY
    SELECT 1/0;
END TRY
BEGIN CATCH
    DECLARE @ErrorMsg NVARCHAR(4000) = CONCAT(
        'Error Number: ', ERROR_NUMBER(), CHAR(13), CHAR(10),
        'Error Severity: ', ERROR_SEVERITY(), CHAR(13), CHAR(10),
        'Error State: ', ERROR_STATE(), CHAR(13), CHAR(10),
        'Error Procedure: ', ISNULL(ERROR_PROCEDURE(), 'N/A'), CHAR(13), CHAR(10),
        'Error Line: ', ERROR_LINE(), CHAR(13), CHAR(10),
        'Error Message: ', ERROR_MESSAGE()
    );
    PRINT @ErrorMsg;
END CATCH
GO

-- Pattern 15: Conditional error raising
CREATE PROCEDURE dbo.ValidateAndProcess
    @Value INT
AS
BEGIN
    SET NOCOUNT ON;
    
    IF @Value IS NULL
    BEGIN
        RAISERROR('Value cannot be NULL', 16, 1);
        RETURN -1;
    END
    
    IF @Value < 0
    BEGIN
        THROW 50010, 'Value cannot be negative', 1;
    END
    
    IF @Value > 1000
    BEGIN
        DECLARE @Msg NVARCHAR(100) = CONCAT('Value ', @Value, ' exceeds maximum of 1000');
        THROW 50011, @Msg, 1;
    END
    
    PRINT 'Validation passed';
    RETURN 0;
END;
GO

-- Pattern 16: Progress reporting with RAISERROR NOWAIT
CREATE PROCEDURE dbo.LongRunningProcess
    @TotalSteps INT = 10
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @Step INT = 1;
    DECLARE @StartTime DATETIME = GETDATE();
    
    RAISERROR('Starting process at %s', 10, 1, @StartTime) WITH NOWAIT;
    
    WHILE @Step <= @TotalSteps
    BEGIN
        -- Simulate work
        WAITFOR DELAY '00:00:01';
        
        DECLARE @Pct INT = (@Step * 100) / @TotalSteps;
        RAISERROR('Step %d of %d complete (%d%%)', 10, 1, @Step, @TotalSteps, @Pct) WITH NOWAIT;
        
        SET @Step = @Step + 1;
    END
    
    RAISERROR('Process completed in %d seconds', 10, 1, DATEDIFF(SECOND, @StartTime, GETDATE())) WITH NOWAIT;
END;
GO

-- Pattern 17: Error severity levels demonstration
-- Severity 0-10: Informational
RAISERROR('Severity 10 - Information', 10, 1);

-- Severity 11-16: User errors
RAISERROR('Severity 11 - Object not found', 11, 1);
RAISERROR('Severity 16 - General user error', 16, 1);

-- Severity 17-19: Resource/Software errors (requires special handling)
-- RAISERROR('Severity 17 - Insufficient resources', 17, 1);

-- Severity 20-25: System problems (terminates connection, requires WITH LOG)
-- RAISERROR('Severity 20 - Fatal error', 20, 1) WITH LOG;
GO

-- Cleanup
DROP PROCEDURE IF EXISTS dbo.ValidateAndProcess;
DROP PROCEDURE IF EXISTS dbo.LongRunningProcess;
GO
