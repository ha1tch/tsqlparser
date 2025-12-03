-- Sample 117: EXECUTE AS Context and Security Contexts
-- Category: Missing Syntax Elements
-- Complexity: Advanced
-- Purpose: Parser testing - impersonation and security context syntax
-- Features: EXECUTE AS, REVERT, ownership chaining, security context

-- Pattern 1: EXECUTE AS in stored procedure definition
CREATE PROCEDURE dbo.ProcWithCallerContext
WITH EXECUTE AS CALLER
AS
BEGIN
    SELECT 
        SUSER_SNAME() AS LoginName,
        USER_NAME() AS UserName,
        ORIGINAL_LOGIN() AS OriginalLogin;
END;
GO

CREATE PROCEDURE dbo.ProcWithOwnerContext
WITH EXECUTE AS OWNER
AS
BEGIN
    SELECT 
        SUSER_SNAME() AS LoginName,
        USER_NAME() AS UserName,
        ORIGINAL_LOGIN() AS OriginalLogin;
END;
GO

CREATE PROCEDURE dbo.ProcWithSelfContext
WITH EXECUTE AS SELF
AS
BEGIN
    SELECT 
        SUSER_SNAME() AS LoginName,
        USER_NAME() AS UserName,
        ORIGINAL_LOGIN() AS OriginalLogin;
END;
GO

CREATE PROCEDURE dbo.ProcWithSpecificUser
WITH EXECUTE AS 'dbo'
AS
BEGIN
    SELECT 
        SUSER_SNAME() AS LoginName,
        USER_NAME() AS UserName,
        ORIGINAL_LOGIN() AS OriginalLogin;
END;
GO

-- Pattern 2: EXECUTE AS with multiple options
CREATE PROCEDURE dbo.ProcWithMultipleOptions
WITH 
    EXECUTE AS OWNER,
    ENCRYPTION,
    SCHEMABINDING
AS
BEGIN
    SELECT 1;
END;
GO

-- Pattern 3: EXECUTE AS in function definition
CREATE FUNCTION dbo.FuncWithCallerContext()
RETURNS TABLE
WITH EXECUTE AS CALLER
AS
RETURN (SELECT USER_NAME() AS CurrentUser);
GO

CREATE FUNCTION dbo.ScalarFuncWithContext()
RETURNS NVARCHAR(128)
WITH EXECUTE AS OWNER
AS
BEGIN
    RETURN USER_NAME();
END;
GO

-- Pattern 4: EXECUTE AS statement (standalone impersonation)
-- Note: These require appropriate permissions
EXECUTE AS USER = 'dbo';
SELECT USER_NAME() AS ImpersonatedUser;
REVERT;
SELECT USER_NAME() AS RevertedUser;
GO

EXECUTE AS LOGIN = 'sa';
SELECT SUSER_SNAME() AS ImpersonatedLogin;
REVERT;
GO

-- Pattern 5: Nested EXECUTE AS with REVERT
EXECUTE AS USER = 'User1';
SELECT USER_NAME() AS Level1;

EXECUTE AS USER = 'User2';
SELECT USER_NAME() AS Level2;

REVERT;  -- Back to User1
SELECT USER_NAME() AS BackToLevel1;

REVERT;  -- Back to original
SELECT USER_NAME() AS BackToOriginal;
GO

-- Pattern 6: EXECUTE AS with COOKIE for later REVERT
DECLARE @cookie VARBINARY(8000);

EXECUTE AS USER = 'TestUser' WITH COOKIE INTO @cookie;
SELECT USER_NAME() AS ImpersonatedUser;

-- Can revert using cookie even from different scope
REVERT WITH COOKIE = @cookie;
SELECT USER_NAME() AS RevertedUser;
GO

-- Pattern 7: EXECUTE AS in trigger
CREATE TRIGGER dbo.AuditTrigger
ON dbo.SensitiveTable
WITH EXECUTE AS OWNER
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    
    INSERT INTO dbo.AuditLog (
        TableName,
        Action,
        ExecutedBy,
        OriginalLogin,
        ActionDate
    )
    SELECT 
        'SensitiveTable',
        CASE 
            WHEN EXISTS(SELECT 1 FROM inserted) AND EXISTS(SELECT 1 FROM deleted) THEN 'UPDATE'
            WHEN EXISTS(SELECT 1 FROM inserted) THEN 'INSERT'
            ELSE 'DELETE'
        END,
        USER_NAME(),
        ORIGINAL_LOGIN(),
        GETDATE();
END;
GO

-- Pattern 8: Module signing alternative (reference)
-- ADD SIGNATURE TO dbo.MyProcedure BY CERTIFICATE MyCert;
-- This is an alternative to EXECUTE AS for permission elevation

-- Pattern 9: EXECUTE AS with NO REVERT
-- EXECUTE AS USER = 'TestUser' WITH NO REVERT;
-- Warning: Cannot revert after this

-- Pattern 10: Security functions in context
CREATE PROCEDURE dbo.ShowSecurityContext
AS
BEGIN
    SELECT 
        SUSER_SNAME() AS SUSER_SNAME,
        SUSER_NAME() AS SUSER_NAME,
        USER_NAME() AS USER_NAME,
        CURRENT_USER AS CURRENT_USER,
        SESSION_USER AS SESSION_USER,
        SYSTEM_USER AS SYSTEM_USER,
        ORIGINAL_LOGIN() AS ORIGINAL_LOGIN,
        SUSER_SID() AS SUSER_SID,
        USER_ID() AS USER_ID,
        DATABASE_PRINCIPAL_ID() AS DATABASE_PRINCIPAL_ID;
END;
GO

-- Pattern 11: Checking impersonation permissions
SELECT 
    dp.name AS PrincipalName,
    dp.type_desc AS PrincipalType,
    pe.permission_name,
    pe.state_desc
FROM sys.database_permissions pe
INNER JOIN sys.database_principals dp ON pe.grantee_principal_id = dp.principal_id
WHERE pe.permission_name = 'IMPERSONATE';
GO

-- Pattern 12: EXECUTE AS in dynamic SQL
DECLARE @SQL NVARCHAR(MAX) = N'
    EXECUTE AS USER = ''TestUser'';
    SELECT USER_NAME() AS ExecutedAs;
    REVERT;
';
EXEC sp_executesql @SQL;
GO

-- Pattern 13: Creating procedure that requires elevated permissions
CREATE PROCEDURE dbo.TruncateAuditLog
WITH EXECUTE AS 'dbo'
AS
BEGIN
    SET NOCOUNT ON;
    
    -- This procedure runs as dbo regardless of who calls it
    -- Useful for allowing limited users to perform specific admin tasks
    
    IF USER_NAME() <> 'dbo'
    BEGIN
        RAISERROR('This procedure must run as dbo', 16, 1);
        RETURN;
    END
    
    TRUNCATE TABLE dbo.AuditLog;
    
    SELECT 'Audit log truncated by ' + ORIGINAL_LOGIN() AS Result;
END;
GO

-- Pattern 14: View with EXECUTE AS
CREATE VIEW dbo.SecureView
WITH SCHEMABINDING, VIEW_METADATA
AS
SELECT 
    CustomerID,
    CustomerName,
    -- Sensitive columns only visible based on context
    CASE 
        WHEN IS_MEMBER('SensitiveDataReaders') = 1 THEN Email
        ELSE '***REDACTED***'
    END AS Email
FROM dbo.Customers;
GO

-- Pattern 15: Queue activation with EXECUTE AS
-- CREATE QUEUE MyQueue
-- WITH ACTIVATION (
--     STATUS = ON,
--     PROCEDURE_NAME = dbo.ProcessQueueMessage,
--     MAX_QUEUE_READERS = 5,
--     EXECUTE AS OWNER
-- );
GO
