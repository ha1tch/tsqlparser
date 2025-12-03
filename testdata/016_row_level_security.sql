-- Sample 016: Row-Level Security Implementation
-- Source: Microsoft Learn, MSSQLTips, SQLShack
-- Category: Security
-- Complexity: Advanced
-- Features: Security policies, predicate functions, SUSER_SNAME(), SESSION_CONTEXT

-- Setup: Create security predicate function
CREATE FUNCTION dbo.fn_SecurityPredicate_Department
(
    @DepartmentID INT
)
RETURNS TABLE
WITH SCHEMABINDING
AS
    RETURN 
    SELECT 1 AS AccessResult
    WHERE 
        -- Allow if user is in the department
        @DepartmentID IN (
            SELECT DepartmentID 
            FROM dbo.UserDepartments 
            WHERE UserName = SUSER_SNAME()
        )
        -- Or user is a manager with access to all departments
        OR EXISTS (
            SELECT 1 
            FROM dbo.UserRoles 
            WHERE UserName = SUSER_SNAME() 
              AND RoleName = 'DepartmentManager'
        )
        -- Or user is admin
        OR IS_MEMBER('db_owner') = 1;
GO

-- Create security policy
CREATE PROCEDURE dbo.CreateDepartmentSecurityPolicy
    @TableName NVARCHAR(128),
    @SchemaName NVARCHAR(128) = 'dbo',
    @DepartmentColumn NVARCHAR(128) = 'DepartmentID'
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @PolicyName NVARCHAR(256);
    DECLARE @SQL NVARCHAR(MAX);
    
    SET @PolicyName = 'SecurityPolicy_' + @SchemaName + '_' + @TableName;
    
    -- Drop existing policy if present
    IF EXISTS (SELECT 1 FROM sys.security_policies WHERE name = @PolicyName)
    BEGIN
        SET @SQL = 'DROP SECURITY POLICY ' + QUOTENAME(@PolicyName);
        EXEC sp_executesql @SQL;
    END
    
    -- Create security policy
    SET @SQL = '
        CREATE SECURITY POLICY ' + QUOTENAME(@PolicyName) + '
        ADD FILTER PREDICATE dbo.fn_SecurityPredicate_Department(' + 
            QUOTENAME(@DepartmentColumn) + ')
        ON ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ',
        ADD BLOCK PREDICATE dbo.fn_SecurityPredicate_Department(' +
            QUOTENAME(@DepartmentColumn) + ')
        ON ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ' AFTER INSERT,
        ADD BLOCK PREDICATE dbo.fn_SecurityPredicate_Department(' +
            QUOTENAME(@DepartmentColumn) + ')
        ON ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ' AFTER UPDATE
        WITH (STATE = ON, SCHEMABINDING = ON)';
    
    EXEC sp_executesql @SQL;
    
    PRINT 'Security policy created: ' + @PolicyName;
END
GO

-- Session context based security
CREATE FUNCTION dbo.fn_SecurityPredicate_TenantID
(
    @TenantID INT
)
RETURNS TABLE
WITH SCHEMABINDING
AS
    RETURN 
    SELECT 1 AS AccessResult
    WHERE @TenantID = CAST(SESSION_CONTEXT(N'TenantID') AS INT)
       OR SESSION_CONTEXT(N'IsAdmin') = CAST(1 AS SQL_VARIANT);
GO

-- Procedure to set tenant context
CREATE PROCEDURE dbo.SetTenantContext
    @TenantID INT,
    @IsAdmin BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Validate tenant exists
    IF NOT EXISTS (SELECT 1 FROM dbo.Tenants WHERE TenantID = @TenantID AND IsActive = 1)
    BEGIN
        RAISERROR('Invalid or inactive tenant ID: %d', 16, 1, @TenantID);
        RETURN;
    END
    
    -- Set session context
    EXEC sp_set_session_context @key = N'TenantID', @value = @TenantID;
    EXEC sp_set_session_context @key = N'IsAdmin', @value = @IsAdmin;
    
    SELECT 
        @TenantID AS TenantID,
        @IsAdmin AS IsAdmin,
        'Context set successfully' AS Status;
END
GO

-- Multi-tenant data access procedure
CREATE PROCEDURE dbo.GetTenantData
    @TableName NVARCHAR(128),
    @SchemaName NVARCHAR(128) = 'dbo'
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @TenantID INT;
    DECLARE @SQL NVARCHAR(MAX);
    
    -- Get current tenant from session
    SET @TenantID = CAST(SESSION_CONTEXT(N'TenantID') AS INT);
    
    IF @TenantID IS NULL
    BEGIN
        RAISERROR('Tenant context not set. Call SetTenantContext first.', 16, 1);
        RETURN;
    END
    
    -- Build and execute query (RLS will filter automatically)
    SET @SQL = 'SELECT * FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    
    EXEC sp_executesql @SQL;
END
GO

-- Audit security policy access
CREATE PROCEDURE dbo.AuditSecurityPolicies
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        sp.name AS PolicyName,
        sp.is_enabled AS IsEnabled,
        sp.is_schema_bound AS IsSchemaBound,
        OBJECT_SCHEMA_NAME(sp.object_id) AS PolicySchema,
        OBJECT_SCHEMA_NAME(pred.target_object_id) AS TargetSchema,
        OBJECT_NAME(pred.target_object_id) AS TargetTable,
        pred.predicate_type_desc AS PredicateType,
        pred.operation_desc AS Operation,
        OBJECT_SCHEMA_NAME(pred.predicate_definition_id) AS PredicateFunctionSchema,
        OBJECT_NAME(pred.predicate_definition_id) AS PredicateFunctionName,
        sp.create_date AS CreatedDate,
        sp.modify_date AS ModifiedDate
    FROM sys.security_policies sp
    INNER JOIN sys.security_predicates pred 
        ON sp.object_id = pred.object_id
    ORDER BY sp.name, pred.predicate_type_desc;
END
GO

-- Test security access
CREATE PROCEDURE dbo.TestSecurityAccess
    @TableName NVARCHAR(128),
    @SchemaName NVARCHAR(128) = 'dbo',
    @TestUserName NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @RowCount INT;
    DECLARE @CurrentUser NVARCHAR(128);
    
    SET @CurrentUser = ISNULL(@TestUserName, SUSER_SNAME());
    
    -- Get row counts with and without security
    SELECT 
        @CurrentUser AS TestUser,
        @SchemaName + '.' + @TableName AS TableName;
    
    -- Count accessible rows
    SET @SQL = 'SELECT @cnt = COUNT(*) FROM ' + 
               QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    
    EXEC sp_executesql @SQL, N'@cnt INT OUTPUT', @cnt = @RowCount OUTPUT;
    
    SELECT 
        @RowCount AS AccessibleRows,
        SUSER_SNAME() AS ExecutingAs,
        IS_MEMBER('db_owner') AS IsDbOwner;
    
    -- Show security policies affecting this table
    SELECT 
        sp.name AS PolicyName,
        pred.predicate_type_desc,
        pred.operation_desc,
        OBJECT_NAME(pred.predicate_definition_id) AS PredicateFunction
    FROM sys.security_policies sp
    INNER JOIN sys.security_predicates pred 
        ON sp.object_id = pred.object_id
    WHERE pred.target_object_id = OBJECT_ID(@SchemaName + '.' + @TableName);
END
GO
