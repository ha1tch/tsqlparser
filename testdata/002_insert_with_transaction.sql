-- Sample 002: Transaction with Error Handling Pattern
-- Source: Erland Sommarskog - sommarskog.se/error_handling
-- Category: Error Handling
-- Complexity: Complex
-- Features: TRY/CATCH, Transaction, XACT_ABORT, ROLLBACK

CREATE PROCEDURE insert_data 
    @a int, 
    @b int 
AS
    SET XACT_ABORT, NOCOUNT ON
    
    BEGIN TRY
        BEGIN TRANSACTION
            INSERT sometable(a, b) VALUES (@a, @b)
            INSERT sometable(a, b) VALUES (@b, @a)
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        IF @@trancount > 0 
            ROLLBACK TRANSACTION
        
        DECLARE @msg nvarchar(2048) = error_message()  
        RAISERROR (@msg, 16, 1)
        RETURN 55555
    END CATCH
GO
