-- Sample 162: Transaction Patterns and Savepoints
-- Category: Missing Syntax Elements / Transactions
-- Complexity: Advanced
-- Purpose: Parser testing - transaction syntax variations
-- Features: BEGIN TRAN, COMMIT, ROLLBACK, SAVE TRAN, nested transactions

-- Pattern 1: Basic transaction
BEGIN TRANSACTION;
    INSERT INTO dbo.Customers (CustomerName) VALUES ('New Customer');
    UPDATE dbo.Customers SET ModifiedDate = GETDATE() WHERE CustomerID = 1;
COMMIT TRANSACTION;
GO

-- Pattern 2: Transaction with abbreviations
BEGIN TRAN;
    INSERT INTO dbo.Orders (CustomerID, OrderDate) VALUES (1, GETDATE());
COMMIT TRAN;
GO

-- Pattern 3: Named transaction
BEGIN TRANSACTION InsertCustomer;
    INSERT INTO dbo.Customers (CustomerName, Email) 
    VALUES ('John Smith', 'john@example.com');
COMMIT TRANSACTION InsertCustomer;
GO

-- Pattern 4: Transaction with ROLLBACK
BEGIN TRANSACTION;
    DELETE FROM dbo.OrderDetails WHERE OrderID = 100;
    DELETE FROM dbo.Orders WHERE OrderID = 100;
    
    -- Check if something went wrong
    IF @@ERROR <> 0
    BEGIN
        ROLLBACK TRANSACTION;
        RETURN;
    END
COMMIT TRANSACTION;
GO

-- Pattern 5: Transaction with TRY/CATCH
BEGIN TRY
    BEGIN TRANSACTION;
        INSERT INTO dbo.Customers (CustomerName) VALUES ('Test');
        INSERT INTO dbo.Orders (CustomerID, OrderDate) VALUES (SCOPE_IDENTITY(), GETDATE());
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH
GO

-- Pattern 6: Savepoint basic
BEGIN TRANSACTION;
    INSERT INTO dbo.Customers (CustomerName) VALUES ('Customer 1');
    
    SAVE TRANSACTION SavePoint1;
    
    INSERT INTO dbo.Customers (CustomerName) VALUES ('Customer 2');
    
    -- Oops, rollback just the second insert
    ROLLBACK TRANSACTION SavePoint1;
    
    -- First insert is still pending
COMMIT TRANSACTION;
GO

-- Pattern 7: Multiple savepoints
BEGIN TRANSACTION;
    INSERT INTO dbo.Log (Message) VALUES ('Step 1');
    SAVE TRANSACTION Step1Complete;
    
    INSERT INTO dbo.Log (Message) VALUES ('Step 2');
    SAVE TRANSACTION Step2Complete;
    
    INSERT INTO dbo.Log (Message) VALUES ('Step 3');
    SAVE TRANSACTION Step3Complete;
    
    -- Rollback to step 2, keeping steps 1 and 2
    ROLLBACK TRANSACTION Step2Complete;
    
    INSERT INTO dbo.Log (Message) VALUES ('Step 3 Retry');
COMMIT TRANSACTION;
GO

-- Pattern 8: Nested transactions (@@TRANCOUNT)
SELECT @@TRANCOUNT AS InitialTranCount;  -- 0

BEGIN TRANSACTION Outer;
    SELECT @@TRANCOUNT AS AfterOuter;  -- 1
    
    BEGIN TRANSACTION Inner;
        SELECT @@TRANCOUNT AS AfterInner;  -- 2
        
        INSERT INTO dbo.Log (Message) VALUES ('Inner transaction');
        
    COMMIT TRANSACTION Inner;  -- Decrements @@TRANCOUNT to 1, doesn't really commit
    SELECT @@TRANCOUNT AS AfterInnerCommit;  -- 1
    
COMMIT TRANSACTION Outer;  -- Actually commits
SELECT @@TRANCOUNT AS AfterOuterCommit;  -- 0
GO

-- Pattern 9: Nested transaction with rollback
BEGIN TRANSACTION Outer;
    INSERT INTO dbo.Log (Message) VALUES ('Outer insert');
    
    BEGIN TRANSACTION Inner;
        INSERT INTO dbo.Log (Message) VALUES ('Inner insert');
        
        -- ROLLBACK rolls back ALL transactions, not just inner
        ROLLBACK TRANSACTION;  -- Both inserts are rolled back
        
    -- @@TRANCOUNT is now 0
SELECT @@TRANCOUNT AS TranCountAfterRollback;  -- 0
GO

-- Pattern 10: XACT_ABORT behavior
SET XACT_ABORT ON;

BEGIN TRANSACTION;
    INSERT INTO dbo.Customers (CustomerName) VALUES ('Customer 1');
    -- If this fails, entire transaction is automatically rolled back
    INSERT INTO dbo.Customers (CustomerID, CustomerName) VALUES (1, 'Duplicate');  -- Will fail
    INSERT INTO dbo.Customers (CustomerName) VALUES ('Customer 2');  -- Never reached
COMMIT TRANSACTION;

SET XACT_ABORT OFF;
GO

-- Pattern 11: Checking transaction state with XACT_STATE()
BEGIN TRY
    BEGIN TRANSACTION;
        -- Some operations...
        INSERT INTO dbo.Customers (CustomerName) VALUES ('Test');
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() = -1  -- Uncommittable transaction
    BEGIN
        ROLLBACK TRANSACTION;
        PRINT 'Transaction was uncommittable, rolled back';
    END
    ELSE IF XACT_STATE() = 1  -- Committable transaction
    BEGIN
        -- Could commit or rollback
        ROLLBACK TRANSACTION;
        PRINT 'Transaction was committable, chose to rollback';
    END
    -- XACT_STATE() = 0 means no transaction
    
    THROW;
END CATCH
GO

-- Pattern 12: Transaction with isolation level
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

BEGIN TRANSACTION;
    SELECT * FROM dbo.Customers WITH (NOLOCK);  -- Override isolation
    UPDATE dbo.Customers SET ModifiedDate = GETDATE() WHERE CustomerID = 1;
COMMIT TRANSACTION;
GO

-- Pattern 13: Explicit isolation level in BEGIN TRAN (not supported in T-SQL, use SET)
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
BEGIN TRANSACTION;
    SELECT * FROM dbo.Inventory WHERE ProductID = 1;
    UPDATE dbo.Inventory SET Quantity = Quantity - 1 WHERE ProductID = 1;
COMMIT TRANSACTION;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
GO

-- Pattern 14: Transaction with MARK (for log marking)
BEGIN TRANSACTION MyMarkedTransaction WITH MARK 'Daily backup point';
    UPDATE dbo.Config SET Value = 'Updated' WHERE Key = 'LastRun';
COMMIT TRANSACTION;
GO

-- Pattern 15: Distributed transaction hints
BEGIN DISTRIBUTED TRANSACTION;
    -- Operations on local server
    INSERT INTO dbo.LocalTable (Data) VALUES ('Local data');
    
    -- Operations on linked server
    INSERT INTO LinkedServer.RemoteDB.dbo.RemoteTable (Data) VALUES ('Remote data');
COMMIT TRANSACTION;
GO

-- Pattern 16: Transaction in stored procedure
CREATE PROCEDURE dbo.TransferFunds
    @FromAccountID INT,
    @ToAccountID INT,
    @Amount DECIMAL(18,2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    
    BEGIN TRY
        BEGIN TRANSACTION;
            -- Debit source account
            UPDATE dbo.Accounts 
            SET Balance = Balance - @Amount 
            WHERE AccountID = @FromAccountID;
            
            IF @@ROWCOUNT = 0
                RAISERROR('Source account not found', 16, 1);
            
            -- Credit destination account
            UPDATE dbo.Accounts 
            SET Balance = Balance + @Amount 
            WHERE AccountID = @ToAccountID;
            
            IF @@ROWCOUNT = 0
                RAISERROR('Destination account not found', 16, 1);
            
            -- Log the transfer
            INSERT INTO dbo.TransferLog (FromAccount, ToAccount, Amount, TransferDate)
            VALUES (@FromAccountID, @ToAccountID, @Amount, GETDATE());
            
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

DROP PROCEDURE IF EXISTS dbo.TransferFunds;
GO

-- Pattern 17: Transaction with output parameters for status
CREATE PROCEDURE dbo.ProcessOrderWithStatus
    @OrderID INT,
    @Success BIT OUTPUT,
    @ErrorMessage NVARCHAR(500) OUTPUT
AS
BEGIN
    SET @Success = 0;
    SET @ErrorMessage = NULL;
    
    BEGIN TRY
        BEGIN TRANSACTION;
            UPDATE dbo.Orders SET Status = 'Processing' WHERE OrderID = @OrderID;
            -- More processing...
        COMMIT TRANSACTION;
        SET @Success = 1;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        SET @ErrorMessage = ERROR_MESSAGE();
    END CATCH
END;
GO

DROP PROCEDURE IF EXISTS dbo.ProcessOrderWithStatus;
GO

-- Pattern 18: Implicit transactions
SET IMPLICIT_TRANSACTIONS ON;
-- Now every statement starts a transaction automatically
SELECT * FROM dbo.Customers;  -- Starts implicit transaction
-- Must explicitly COMMIT or ROLLBACK
COMMIT;

SET IMPLICIT_TRANSACTIONS OFF;
GO

-- Pattern 19: Transaction timeout with LOCK_TIMEOUT
SET LOCK_TIMEOUT 5000;  -- 5 seconds

BEGIN TRANSACTION;
    -- If lock cannot be acquired within 5 seconds, error 1222 is raised
    UPDATE dbo.Customers SET ModifiedDate = GETDATE() WHERE CustomerID = 1;
COMMIT TRANSACTION;

SET LOCK_TIMEOUT -1;  -- Reset to wait indefinitely
GO

-- Pattern 20: Checking for open transactions
IF @@TRANCOUNT > 0
BEGIN
    PRINT 'There is an open transaction';
    -- Optionally rollback orphaned transactions
    -- ROLLBACK TRANSACTION;
END
ELSE
BEGIN
    PRINT 'No open transactions';
END
GO
