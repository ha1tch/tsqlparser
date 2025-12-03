-- Sample 088: Multi-Tenant Database Patterns
-- Source: Various - Microsoft Learn, Azure patterns, SaaS architecture
-- Category: Security
-- Complexity: Advanced
-- Features: Tenant isolation, row-level security, schema per tenant, resource governance

-- Setup multi-tenant infrastructure
CREATE PROCEDURE dbo.SetupMultiTenantInfrastructure
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Tenant registry
    IF OBJECT_ID('dbo.Tenants', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.Tenants (
            TenantID INT IDENTITY(1,1) PRIMARY KEY,
            TenantCode NVARCHAR(50) UNIQUE NOT NULL,
            TenantName NVARCHAR(200) NOT NULL,
            SchemaName NVARCHAR(128),
            ConnectionString NVARCHAR(500),
            TierLevel NVARCHAR(20) DEFAULT 'Standard',  -- Free, Standard, Premium
            IsActive BIT DEFAULT 1,
            CreatedDate DATETIME2 DEFAULT SYSDATETIME(),
            ExpirationDate DATE,
            MaxUsers INT DEFAULT 10,
            MaxStorageMB INT DEFAULT 1000
        );
    END
    
    -- Tenant users
    IF OBJECT_ID('dbo.TenantUsers', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.TenantUsers (
            UserID INT IDENTITY(1,1) PRIMARY KEY,
            TenantID INT REFERENCES dbo.Tenants(TenantID),
            UserName NVARCHAR(128) NOT NULL,
            Email NVARCHAR(256),
            Role NVARCHAR(50) DEFAULT 'User',
            IsActive BIT DEFAULT 1,
            CreatedDate DATETIME2 DEFAULT SYSDATETIME()
        );
    END
    
    -- Tenant usage tracking
    IF OBJECT_ID('dbo.TenantUsage', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.TenantUsage (
            UsageID BIGINT IDENTITY(1,1) PRIMARY KEY,
            TenantID INT REFERENCES dbo.Tenants(TenantID),
            UsageDate DATE DEFAULT CAST(GETDATE() AS DATE),
            RequestCount INT DEFAULT 0,
            StorageUsedMB DECIMAL(18,2),
            DataTransferMB DECIMAL(18,2),
            ComputeMinutes DECIMAL(18,2)
        );
    END
    
    SELECT 'Multi-tenant infrastructure created' AS Status;
END
GO

-- Create tenant with dedicated schema
CREATE PROCEDURE dbo.CreateTenant
    @TenantCode NVARCHAR(50),
    @TenantName NVARCHAR(200),
    @TierLevel NVARCHAR(20) = 'Standard',
    @IsolationType NVARCHAR(20) = 'SHARED',  -- SHARED (RLS), SCHEMA, DATABASE
    @TenantID INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @SchemaName NVARCHAR(128);
    
    -- Validate tenant doesn't exist
    IF EXISTS (SELECT 1 FROM dbo.Tenants WHERE TenantCode = @TenantCode)
    BEGIN
        RAISERROR('Tenant code already exists: %s', 16, 1, @TenantCode);
        RETURN;
    END
    
    BEGIN TRANSACTION;
    
    BEGIN TRY
        -- Create tenant record
        INSERT INTO dbo.Tenants (TenantCode, TenantName, TierLevel, MaxUsers, MaxStorageMB)
        VALUES (@TenantCode, @TenantName, @TierLevel,
                CASE @TierLevel WHEN 'Free' THEN 5 WHEN 'Standard' THEN 25 ELSE 100 END,
                CASE @TierLevel WHEN 'Free' THEN 100 WHEN 'Standard' THEN 1000 ELSE 10000 END);
        
        SET @TenantID = SCOPE_IDENTITY();
        
        -- Schema isolation: create dedicated schema
        IF @IsolationType = 'SCHEMA'
        BEGIN
            SET @SchemaName = 'tenant_' + @TenantCode;
            SET @SQL = 'CREATE SCHEMA ' + QUOTENAME(@SchemaName);
            EXEC sp_executesql @SQL;
            
            UPDATE dbo.Tenants SET SchemaName = @SchemaName WHERE TenantID = @TenantID;
            
            -- Create tenant-specific tables in schema
            SET @SQL = N'
                CREATE TABLE ' + QUOTENAME(@SchemaName) + '.Orders (
                    OrderID INT IDENTITY(1,1) PRIMARY KEY,
                    OrderDate DATETIME2 DEFAULT SYSDATETIME(),
                    Amount DECIMAL(18,2)
                );
                CREATE TABLE ' + QUOTENAME(@SchemaName) + '.Customers (
                    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
                    CustomerName NVARCHAR(200)
                );';
            EXEC sp_executesql @SQL;
        END
        
        COMMIT TRANSACTION;
        
        SELECT @TenantID AS TenantID, @TenantCode AS TenantCode, 'Created' AS Status;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- Setup Row-Level Security for tenant isolation
CREATE PROCEDURE dbo.SetupTenantRLS
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @TenantIdColumn NVARCHAR(128) = 'TenantID'
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FunctionName NVARCHAR(256) = 'fn_TenantFilter_' + @TableName;
    DECLARE @PolicyName NVARCHAR(256) = 'TenantPolicy_' + @TableName;
    
    -- Create security predicate function
    SET @SQL = N'
        CREATE OR ALTER FUNCTION ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@FunctionName) + '(@TenantID INT)
        RETURNS TABLE
        WITH SCHEMABINDING
        AS
        RETURN SELECT 1 AS fn_result
        WHERE @TenantID = CAST(SESSION_CONTEXT(N''TenantID'') AS INT)
           OR IS_MEMBER(''db_owner'') = 1';
    EXEC sp_executesql @SQL;
    
    -- Create security policy
    SET @SQL = N'
        CREATE SECURITY POLICY ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@PolicyName) + '
        ADD FILTER PREDICATE ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@FunctionName) + '(' + QUOTENAME(@TenantIdColumn) + ')
        ON ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ',
        ADD BLOCK PREDICATE ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@FunctionName) + '(' + QUOTENAME(@TenantIdColumn) + ')
        ON ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '
        WITH (STATE = ON)';
    
    BEGIN TRY
        EXEC sp_executesql @SQL;
        SELECT 'RLS policy created' AS Status, @PolicyName AS PolicyName;
    END TRY
    BEGIN CATCH
        -- Policy might already exist
        IF ERROR_NUMBER() = 15387  -- Object already exists
        BEGIN
            SET @SQL = 'ALTER SECURITY POLICY ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@PolicyName) + ' WITH (STATE = ON)';
            EXEC sp_executesql @SQL;
            SELECT 'RLS policy enabled' AS Status, @PolicyName AS PolicyName;
        END
        ELSE
            THROW;
    END CATCH
END
GO

-- Set tenant context for session
CREATE PROCEDURE dbo.SetTenantContext
    @TenantCode NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @TenantID INT;
    DECLARE @IsActive BIT;
    
    SELECT @TenantID = TenantID, @IsActive = IsActive
    FROM dbo.Tenants
    WHERE TenantCode = @TenantCode;
    
    IF @TenantID IS NULL
    BEGIN
        RAISERROR('Tenant not found: %s', 16, 1, @TenantCode);
        RETURN;
    END
    
    IF @IsActive = 0
    BEGIN
        RAISERROR('Tenant is inactive: %s', 16, 1, @TenantCode);
        RETURN;
    END
    
    -- Set session context
    EXEC sp_set_session_context @key = N'TenantID', @value = @TenantID;
    EXEC sp_set_session_context @key = N'TenantCode', @value = @TenantCode;
    
    SELECT @TenantID AS TenantID, @TenantCode AS TenantCode, 'Context set' AS Status;
END
GO

-- Get current tenant context
CREATE FUNCTION dbo.GetCurrentTenantID()
RETURNS INT
AS
BEGIN
    RETURN CAST(SESSION_CONTEXT(N'TenantID') AS INT);
END
GO

-- Get tenant usage report
CREATE PROCEDURE dbo.GetTenantUsageReport
    @TenantCode NVARCHAR(50) = NULL,
    @StartDate DATE = NULL,
    @EndDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @StartDate = ISNULL(@StartDate, DATEADD(MONTH, -1, GETDATE()));
    SET @EndDate = ISNULL(@EndDate, GETDATE());
    
    SELECT 
        t.TenantCode,
        t.TenantName,
        t.TierLevel,
        t.MaxStorageMB,
        SUM(u.RequestCount) AS TotalRequests,
        MAX(u.StorageUsedMB) AS CurrentStorageMB,
        CAST(MAX(u.StorageUsedMB) * 100.0 / NULLIF(t.MaxStorageMB, 0) AS DECIMAL(5,2)) AS StorageUsedPercent,
        SUM(u.DataTransferMB) AS TotalDataTransferMB,
        SUM(u.ComputeMinutes) AS TotalComputeMinutes,
        (SELECT COUNT(*) FROM dbo.TenantUsers tu WHERE tu.TenantID = t.TenantID AND tu.IsActive = 1) AS ActiveUsers,
        t.MaxUsers
    FROM dbo.Tenants t
    LEFT JOIN dbo.TenantUsage u ON t.TenantID = u.TenantID AND u.UsageDate BETWEEN @StartDate AND @EndDate
    WHERE (@TenantCode IS NULL OR t.TenantCode = @TenantCode)
    GROUP BY t.TenantID, t.TenantCode, t.TenantName, t.TierLevel, t.MaxStorageMB, t.MaxUsers
    ORDER BY t.TenantCode;
END
GO

-- Cleanup tenant data
CREATE PROCEDURE dbo.CleanupTenantData
    @TenantCode NVARCHAR(50),
    @ConfirmDelete BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @TenantID INT;
    DECLARE @SchemaName NVARCHAR(128);
    DECLARE @SQL NVARCHAR(MAX);
    
    SELECT @TenantID = TenantID, @SchemaName = SchemaName
    FROM dbo.Tenants WHERE TenantCode = @TenantCode;
    
    IF @TenantID IS NULL
    BEGIN
        RAISERROR('Tenant not found: %s', 16, 1, @TenantCode);
        RETURN;
    END
    
    IF @ConfirmDelete = 0
    BEGIN
        SELECT 'WARNING: This will delete all tenant data!' AS Warning,
               @TenantCode AS TenantCode,
               @SchemaName AS SchemaToDelete,
               'Set @ConfirmDelete = 1 to proceed' AS Action;
        RETURN;
    END
    
    BEGIN TRANSACTION;
    
    BEGIN TRY
        -- Delete from shared tables with TenantID
        -- Add your tenant-specific table cleanup here
        
        -- If schema isolation, drop the schema
        IF @SchemaName IS NOT NULL
        BEGIN
            -- Drop all objects in schema
            DECLARE @ObjectName NVARCHAR(256);
            DECLARE ObjCursor CURSOR FOR
                SELECT QUOTENAME(@SchemaName) + '.' + QUOTENAME(name)
                FROM sys.objects WHERE schema_id = SCHEMA_ID(@SchemaName);
            
            OPEN ObjCursor;
            FETCH NEXT FROM ObjCursor INTO @ObjectName;
            WHILE @@FETCH_STATUS = 0
            BEGIN
                SET @SQL = 'DROP TABLE ' + @ObjectName;
                EXEC sp_executesql @SQL;
                FETCH NEXT FROM ObjCursor INTO @ObjectName;
            END
            CLOSE ObjCursor;
            DEALLOCATE ObjCursor;
            
            SET @SQL = 'DROP SCHEMA ' + QUOTENAME(@SchemaName);
            EXEC sp_executesql @SQL;
        END
        
        -- Delete tenant users
        DELETE FROM dbo.TenantUsers WHERE TenantID = @TenantID;
        
        -- Delete usage records
        DELETE FROM dbo.TenantUsage WHERE TenantID = @TenantID;
        
        -- Delete tenant
        DELETE FROM dbo.Tenants WHERE TenantID = @TenantID;
        
        COMMIT TRANSACTION;
        
        SELECT 'Tenant deleted successfully' AS Status, @TenantCode AS DeletedTenant;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
