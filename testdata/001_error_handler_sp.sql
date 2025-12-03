-- Sample 001: Error Handler Stored Procedure
-- Source: Erland Sommarskog - sommarskog.se/error_handling
-- Category: Error Handling
-- Complexity: Complex
-- Features: TRY/CATCH, RAISERROR, error_xxx() functions

CREATE PROCEDURE error_handler_sp 
AS
    DECLARE @errmsg   nvarchar(2048),
            @severity tinyint,
            @state    tinyint,
            @errno    int,
            @proc     sysname,
            @lineno   int
            
    SELECT @errmsg = error_message(), @severity = error_severity(),
           @state  = error_state(), @errno = error_number(),
           @proc   = error_procedure(), @lineno = error_line()
       
    IF @errmsg NOT LIKE '***%'
    BEGIN
        SELECT @errmsg = '*** ' + coalesce(quotename(@proc), '<dynamic SQL>') + 
                         ', Line ' + ltrim(str(@lineno)) + '. Errno ' + 
                         ltrim(str(@errno)) + ': ' + @errmsg
    END
    RAISERROR('%s', @severity, @state, @errmsg)
GO
