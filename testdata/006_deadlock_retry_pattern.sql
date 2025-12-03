-- Sample 006: Deadlock Retry Logic Pattern
-- Source: MSSQLTips/StackOverflow - Deadlock handling patterns
-- Category: Error Handling
-- Complexity: Advanced
-- Features: TRY/CATCH, Deadlock detection (1205), Retry loop, WAITFOR DELAY

CREATE PROCEDURE dbo.ExecuteWithDeadlockRetry
    @MaxRetries INT = 5,
    @DelayBetweenRetries VARCHAR(12) = '00:00:00.500'  -- 500ms
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    
    DECLARE @RetryCount INT = 0;
    DECLARE @Success BIT = 0;
    DECLARE @ErrorNumber INT;
    DECLARE @ErrorMessage NVARCHAR(4000);
    DECLARE @ErrorSeverity INT;
    DECLARE @ErrorState INT;
    DECLARE @ErrorLine INT;
    
    WHILE @RetryCount < @MaxRetries AND @Success = 0
    BEGIN
        BEGIN TRY
            BEGIN TRANSACTION;
            
            -- =============================================
            -- Place your transactional code here
            -- =============================================
            
            -- Example: Update operations that might deadlock
            UPDATE TableA 
            SET Column1 = 'Value1' 
            WHERE ID = 1;
            
            WAITFOR DELAY '00:00:02';  -- Simulate long operation
            
            UPDATE TableB 
            SET Column2 = 'Value2' 
            WHERE ID = 1;
            
            -- =============================================
            -- End of transactional code
            -- =============================================
            
            COMMIT TRANSACTION;
            SET @Success = 1;
            
            SELECT 'Transaction completed successfully on attempt ' + 
                   CAST(@RetryCount + 1 AS VARCHAR(10)) AS Result;
                   
        END TRY
        BEGIN CATCH
            -- Capture error information
            SELECT 
                @ErrorNumber = ERROR_NUMBER(),
                @ErrorMessage = ERROR_MESSAGE(),
                @ErrorSeverity = ERROR_SEVERITY(),
                @ErrorState = ERROR_STATE(),
                @ErrorLine = ERROR_LINE();
            
            -- Rollback if transaction is open
            IF XACT_STATE() <> 0
                ROLLBACK TRANSACTION;
            
            -- Check if this is a deadlock error (1205)
            IF @ErrorNumber = 1205
            BEGIN
                SET @RetryCount = @RetryCount + 1;
                
                IF @RetryCount < @MaxRetries
                BEGIN
                    -- Log the retry attempt
                    PRINT 'Deadlock detected. Retry attempt ' + 
                          CAST(@RetryCount AS VARCHAR(10)) + 
                          ' of ' + CAST(@MaxRetries AS VARCHAR(10));
                    
                    -- Wait before retrying
                    WAITFOR DELAY @DelayBetweenRetries;
                END
                ELSE
                BEGIN
                    -- Max retries exceeded
                    RAISERROR(
                        'Transaction failed after %d deadlock retries. Last error: %s', 
                        16, 1, @MaxRetries, @ErrorMessage
                    );
                END
            END
            ELSE
            BEGIN
                -- Non-deadlock error - re-raise immediately
                RAISERROR(
                    'Error %d at line %d: %s', 
                    @ErrorSeverity, @ErrorState, 
                    @ErrorNumber, @ErrorLine, @ErrorMessage
                );
            END
        END CATCH
    END
END
GO


-- Alternative simpler pattern for inline use
CREATE PROCEDURE dbo.SimpleDeadlockRetry
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @Retries INT = 5;
    
    WHILE @Retries > 0
    BEGIN
        BEGIN TRY
            BEGIN TRANSACTION;
            
            -- Your code here
            UPDATE SomeTable SET Status = 'Updated' WHERE ID = 1;
            
            COMMIT TRANSACTION;
            SET @Retries = 0;  -- Success - exit loop
            
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0
                ROLLBACK TRANSACTION;
            
            IF ERROR_NUMBER() = 1205 AND @Retries > 1
            BEGIN
                -- Deadlock - retry
                SET @Retries = @Retries - 1;
                WAITFOR DELAY '00:00:00.100';
            END
            ELSE
            BEGIN
                -- Non-deadlock or last retry - throw
                THROW;
            END
        END CATCH
    END
END
GO
