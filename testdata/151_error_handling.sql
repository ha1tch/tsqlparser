-- Sample 151: Error Handling Patterns and TRY/CATCH Variations
-- Category: Missing Syntax Elements / Bare Statements
-- Complexity: Advanced
-- Purpose: Parser testing - comprehensive error handling syntax
-- Features: TRY/CATCH, nested handling, transactions, error functions

-- Pattern 1: Basic TRY/CATCH
BEGIN TRY
    SELECT 1/0;
END TRY
BEGIN CATCH
    SELECT ERROR_MESSAGE() AS ErrorMessage;
END CATCH
GO

-- Pattern 2: TRY/CATCH with all error functions
BEGIN TRY
    RAISERROR('Test error', 16, 1);
END TRY
BEGIN CATCH
    SELECT 
        ERROR_NUMBER() AS ErrorNumber,
        ERROR_SEVERITY() AS ErrorSeverity,
        ERROR_STATE() AS ErrorState,
        ERROR_LINE() AS ErrorLine,
        ERROR_PROCEDURE() AS ErrorProcedure,
        ERROR_MESSAGE() AS ErrorMessage;
END CATCH
GO

-- Pattern 3: TRY/CATCH with THROW (re-throw)
BEGIN TRY
    -- Some operation
    DECLARE @x INT = 1/0;
END TRY
BEGIN CATCH
    -- Log the error
    PRINT 'Error occurred: ' + ERROR_MESSAGE();
    
    -- Re-throw the original error
    THROW;
END CATCH
GO

-- Pattern 4: TRY/CATCH with custom THROW
BEGIN TRY
    IF NOT EXISTS (SELECT 1 FROM dbo.Customers WHERE CustomerID = 99999)
    BEGIN
        THROW 50001, 'Customer not found', 1;
    END
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS Num, ERROR_MESSAGE() AS Msg;
END CATCH
GO

-- Pattern 5: TRY/CATCH with transaction
BEGIN TRY
    BEGIN TRANSACTION;
    
    INSERT INTO dbo.Orders (CustomerID, OrderDate) VALUES (100, GETDATE());
    INSERT INTO dbo.OrderDetails (OrderID, ProductID, Quantity) VALUES (SCOPE_IDENTITY(), 1, 5);
    
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    
    THROW;
END CATCH
GO

-- Pattern 6: Nested TRY/CATCH
BEGIN TRY
    PRINT 'Outer TRY - Starting';
    
    BEGIN TRY
        PRINT 'Inner TRY - Starting';
        SELECT 1/0;  -- This will cause error
        PRINT 'Inner TRY - Completed';  -- Won't execute
    END TRY
    BEGIN CATCH
        PRINT 'Inner CATCH - Handling error';
        PRINT 'Inner error: ' + ERROR_MESSAGE();
        -- Optionally re-throw or handle
    END CATCH
    
    PRINT 'Outer TRY - After inner block';
END TRY
BEGIN CATCH
    PRINT 'Outer CATCH - This only catches if inner re-throws';
END CATCH
GO

-- Pattern 7: TRY/CATCH in stored procedure
CREATE PROCEDURE dbo.SafeInsertOrder
    @CustomerID INT,
    @ProductID INT,
    @Quantity INT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @ErrorMessage NVARCHAR(4000);
    DECLARE @ErrorSeverity INT;
    DECLARE @ErrorState INT;
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        -- Validate customer
        IF NOT EXISTS (SELECT 1 FROM dbo.Customers WHERE CustomerID = @CustomerID)
            THROW 50001, 'Invalid CustomerID', 1;
        
        -- Validate product
        IF NOT EXISTS (SELECT 1 FROM dbo.Products WHERE ProductID = @ProductID)
            THROW 50002, 'Invalid ProductID', 1;
        
        -- Insert order
        INSERT INTO dbo.Orders (CustomerID, OrderDate)
        VALUES (@CustomerID, GETDATE());
        
        DECLARE @OrderID INT = SCOPE_IDENTITY();
        
        INSERT INTO dbo.OrderDetails (OrderID, ProductID, Quantity)
        VALUES (@OrderID, @ProductID, @Quantity);
        
        COMMIT TRANSACTION;
        
        SELECT @OrderID AS NewOrderID;
        RETURN 0;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        SET @ErrorMessage = ERROR_MESSAGE();
        SET @ErrorSeverity = ERROR_SEVERITY();
        SET @ErrorState = ERROR_STATE();
        
        -- Log error
        INSERT INTO dbo.ErrorLog (ErrorMessage, ErrorSeverity, ErrorState, ErrorDate)
        VALUES (@ErrorMessage, @ErrorSeverity, @ErrorState, GETDATE());
        
        -- Re-raise
        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
        RETURN -1;
    END CATCH
END;
GO

-- Pattern 8: XACT_ABORT behavior
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;
    
    INSERT INTO dbo.TestTable VALUES (1);
    INSERT INTO dbo.TestTable VALUES (2);
    -- With XACT_ABORT ON, error automatically rolls back
    SELECT 1/0;
    INSERT INTO dbo.TestTable VALUES (3);
    
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    -- Transaction already rolled back by XACT_ABORT
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    
    PRINT 'Transaction was rolled back. XACT_STATE: ' + CAST(XACT_STATE() AS VARCHAR(2));
END CATCH

SET XACT_ABORT OFF;
GO

-- Pattern 9: XACT_STATE() checking
BEGIN TRY
    BEGIN TRANSACTION;
    
    -- Some operations that might fail
    INSERT INTO dbo.TestTable VALUES (1);
    
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() = -1
    BEGIN
        -- Transaction is uncommittable, must rollback
        PRINT 'Transaction is uncommittable';
        ROLLBACK TRANSACTION;
    END
    ELSE IF XACT_STATE() = 1
    BEGIN
        -- Transaction is committable (partial success possible)
        PRINT 'Transaction is committable';
        COMMIT TRANSACTION;  -- or ROLLBACK depending on logic
    END
    ELSE
    BEGIN
        -- No active transaction
        PRINT 'No active transaction';
    END
END CATCH
GO

-- Pattern 10: Savepoint with error handling
BEGIN TRY
    BEGIN TRANSACTION;
    
    -- First operation
    INSERT INTO dbo.Orders (CustomerID) VALUES (1);
    
    SAVE TRANSACTION SavePoint1;
    
    BEGIN TRY
        -- Second operation that might fail
        INSERT INTO dbo.OrderDetails (OrderID, ProductID) VALUES (999999, 1);  -- Might fail
    END TRY
    BEGIN CATCH
        -- Rollback to savepoint, not entire transaction
        ROLLBACK TRANSACTION SavePoint1;
        PRINT 'Rolled back to savepoint';
    END CATCH
    
    -- Continue with rest of transaction
    INSERT INTO dbo.AuditLog (Message) VALUES ('Order processed');
    
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH
GO

-- Pattern 11: Error handling with output parameters
CREATE PROCEDURE dbo.ProcessWithError
    @Input INT,
    @Output INT OUTPUT,
    @ErrorOccurred BIT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @ErrorOccurred = 0;
    SET @Output = 0;
    
    BEGIN TRY
        SET @Output = 100 / @Input;  -- Will fail if @Input = 0
    END TRY
    BEGIN CATCH
        SET @ErrorOccurred = 1;
        SET @Output = -1;
    END CATCH
END;
GO

-- Pattern 12: Retry pattern with error handling
DECLARE @MaxRetries INT = 3;
DECLARE @RetryCount INT = 0;
DECLARE @Success BIT = 0;

WHILE @RetryCount < @MaxRetries AND @Success = 0
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION;
        
        -- Operation that might have transient failures
        UPDATE dbo.Inventory 
        SET Quantity = Quantity - 1 
        WHERE ProductID = 1 AND Quantity > 0;
        
        IF @@ROWCOUNT = 0
            THROW 50010, 'Insufficient inventory', 1;
        
        COMMIT TRANSACTION;
        SET @Success = 1;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        SET @RetryCount = @RetryCount + 1;
        
        IF @RetryCount < @MaxRetries
        BEGIN
            PRINT 'Retry ' + CAST(@RetryCount AS VARCHAR(10)) + ' of ' + CAST(@MaxRetries AS VARCHAR(10));
            WAITFOR DELAY '00:00:01';  -- Wait before retry
        END
        ELSE
        BEGIN
            THROW;  -- Re-throw after max retries
        END
    END CATCH
END
GO

-- Pattern 13: Deadlock retry
DECLARE @RetryCount INT = 0;
DECLARE @MaxRetries INT = 3;

WHILE @RetryCount <= @MaxRetries
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION;
        
        -- Operations that might deadlock
        UPDATE dbo.Table1 SET Col1 = Col1 + 1 WHERE ID = 1;
        UPDATE dbo.Table2 SET Col1 = Col1 + 1 WHERE ID = 1;
        
        COMMIT TRANSACTION;
        BREAK;  -- Success, exit loop
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        IF ERROR_NUMBER() = 1205  -- Deadlock victim
        BEGIN
            SET @RetryCount = @RetryCount + 1;
            IF @RetryCount <= @MaxRetries
            BEGIN
                WAITFOR DELAY '00:00:00.100';  -- Small delay
                CONTINUE;
            END
        END
        
        THROW;  -- Not a deadlock or max retries exceeded
    END CATCH
END
GO

-- Pattern 14: Structured error information table
BEGIN TRY
    -- Some operation
    EXEC dbo.SomeProcedure;
END TRY
BEGIN CATCH
    DECLARE @ErrorInfo TABLE (
        ErrorNumber INT,
        ErrorSeverity INT,
        ErrorState INT,
        ErrorProcedure NVARCHAR(128),
        ErrorLine INT,
        ErrorMessage NVARCHAR(4000)
    );
    
    INSERT INTO @ErrorInfo
    SELECT 
        ERROR_NUMBER(),
        ERROR_SEVERITY(),
        ERROR_STATE(),
        ERROR_PROCEDURE(),
        ERROR_LINE(),
        ERROR_MESSAGE();
    
    SELECT * FROM @ErrorInfo;
END CATCH
GO

-- Cleanup
DROP PROCEDURE IF EXISTS dbo.SafeInsertOrder;
DROP PROCEDURE IF EXISTS dbo.ProcessWithError;
GO
