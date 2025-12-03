-- Sample 084: Audit Compliance Reporting
-- Source: Various - SOX, HIPAA, GDPR compliance patterns, Microsoft Learn
-- Category: Security
-- Complexity: Advanced
-- Features: Compliance auditing, access reporting, data retention, audit trails

-- Setup compliance audit infrastructure
CREATE PROCEDURE dbo.SetupComplianceAudit
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Compliance audit log
    IF OBJECT_ID('dbo.ComplianceAuditLog', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.ComplianceAuditLog (
            AuditID BIGINT IDENTITY(1,1) PRIMARY KEY,
            AuditTime DATETIME2 DEFAULT SYSDATETIME(),
            AuditType NVARCHAR(50) NOT NULL,
            ObjectType NVARCHAR(50),
            ObjectName NVARCHAR(256),
            ActionPerformed NVARCHAR(100),
            PerformedBy NVARCHAR(128),
            PerformedFrom NVARCHAR(128),
            OldValue NVARCHAR(MAX),
            NewValue NVARCHAR(MAX),
            AdditionalInfo NVARCHAR(MAX)
        );
        
        CREATE INDEX IX_ComplianceAudit_Time ON dbo.ComplianceAuditLog(AuditTime);
        CREATE INDEX IX_ComplianceAudit_Type ON dbo.ComplianceAuditLog(AuditType);
    END
    
    -- Sensitive data inventory
    IF OBJECT_ID('dbo.SensitiveDataInventory', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.SensitiveDataInventory (
            InventoryID INT IDENTITY(1,1) PRIMARY KEY,
            SchemaName NVARCHAR(128),
            TableName NVARCHAR(128),
            ColumnName NVARCHAR(128),
            DataClassification NVARCHAR(50),  -- PII, PHI, Financial, Confidential
            EncryptionRequired BIT DEFAULT 0,
            MaskingRequired BIT DEFAULT 0,
            RetentionDays INT,
            LastReviewed DATE,
            ReviewedBy NVARCHAR(128),
            Notes NVARCHAR(MAX)
        );
    END
    
    -- Data access log
    IF OBJECT_ID('dbo.DataAccessLog', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.DataAccessLog (
            LogID BIGINT IDENTITY(1,1) PRIMARY KEY,
            AccessTime DATETIME2 DEFAULT SYSDATETIME(),
            UserName NVARCHAR(128),
            TableAccessed NVARCHAR(256),
            AccessType NVARCHAR(20),  -- SELECT, INSERT, UPDATE, DELETE
            RowsAffected INT,
            QueryText NVARCHAR(MAX),
            ClientIP NVARCHAR(50),
            ApplicationName NVARCHAR(256)
        );
    END
    
    SELECT 'Compliance audit infrastructure created' AS Status;
END
GO

-- Log compliance audit event
CREATE PROCEDURE dbo.LogComplianceEvent
    @AuditType NVARCHAR(50),
    @ObjectType NVARCHAR(50) = NULL,
    @ObjectName NVARCHAR(256) = NULL,
    @ActionPerformed NVARCHAR(100),
    @OldValue NVARCHAR(MAX) = NULL,
    @NewValue NVARCHAR(MAX) = NULL,
    @AdditionalInfo NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    INSERT INTO dbo.ComplianceAuditLog (AuditType, ObjectType, ObjectName, ActionPerformed, 
                                         PerformedBy, PerformedFrom, OldValue, NewValue, AdditionalInfo)
    VALUES (@AuditType, @ObjectType, @ObjectName, @ActionPerformed,
            SUSER_SNAME(), HOST_NAME(), @OldValue, @NewValue, @AdditionalInfo);
END
GO

-- Generate user access report
CREATE PROCEDURE dbo.GenerateUserAccessReport
    @StartDate DATE = NULL,
    @EndDate DATE = NULL,
    @UserName NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @StartDate = ISNULL(@StartDate, DATEADD(DAY, -30, GETDATE()));
    SET @EndDate = ISNULL(@EndDate, GETDATE());
    
    -- Login history
    SELECT 
        'Login Activity' AS ReportSection,
        dp.name AS UserName,
        dp.type_desc AS PrincipalType,
        dp.create_date AS AccountCreated,
        dp.modify_date AS AccountModified,
        LOGINPROPERTY(dp.name, 'PasswordLastSetTime') AS PasswordLastSet,
        LOGINPROPERTY(dp.name, 'DaysUntilExpiration') AS DaysUntilPasswordExpires,
        LOGINPROPERTY(dp.name, 'IsLocked') AS IsLocked,
        LOGINPROPERTY(dp.name, 'BadPasswordCount') AS FailedLoginAttempts
    FROM sys.database_principals dp
    WHERE dp.type IN ('S', 'U', 'G')
      AND (@UserName IS NULL OR dp.name = @UserName);
    
    -- Permission summary
    SELECT 
        'Permission Summary' AS ReportSection,
        dp.name AS UserName,
        dp.type_desc AS PrincipalType,
        perm.permission_name AS Permission,
        perm.state_desc AS PermissionState,
        CASE perm.class
            WHEN 0 THEN 'Database'
            WHEN 1 THEN 'Object: ' + OBJECT_NAME(perm.major_id)
            WHEN 3 THEN 'Schema: ' + SCHEMA_NAME(perm.major_id)
            ELSE 'Other'
        END AS SecurableScope
    FROM sys.database_permissions perm
    INNER JOIN sys.database_principals dp ON perm.grantee_principal_id = dp.principal_id
    WHERE (@UserName IS NULL OR dp.name = @UserName)
    ORDER BY dp.name, perm.permission_name;
    
    -- Role memberships
    SELECT 
        'Role Memberships' AS ReportSection,
        member.name AS UserName,
        role.name AS RoleName,
        role.type_desc AS RoleType
    FROM sys.database_role_members rm
    INNER JOIN sys.database_principals role ON rm.role_principal_id = role.principal_id
    INNER JOIN sys.database_principals member ON rm.member_principal_id = member.principal_id
    WHERE (@UserName IS NULL OR member.name = @UserName)
    ORDER BY member.name, role.name;
END
GO

-- Identify sensitive data columns
CREATE PROCEDURE dbo.IdentifySensitiveData
    @AutoClassify BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Find potential PII columns based on naming patterns
    SELECT 
        OBJECT_SCHEMA_NAME(c.object_id) AS SchemaName,
        OBJECT_NAME(c.object_id) AS TableName,
        c.name AS ColumnName,
        TYPE_NAME(c.user_type_id) AS DataType,
        CASE 
            WHEN c.name LIKE '%SSN%' OR c.name LIKE '%Social%Security%' THEN 'PII - SSN'
            WHEN c.name LIKE '%Email%' THEN 'PII - Email'
            WHEN c.name LIKE '%Phone%' OR c.name LIKE '%Mobile%' THEN 'PII - Phone'
            WHEN c.name LIKE '%Address%' OR c.name LIKE '%Street%' OR c.name LIKE '%City%' THEN 'PII - Address'
            WHEN c.name LIKE '%Birth%' OR c.name LIKE '%DOB%' THEN 'PII - DOB'
            WHEN c.name LIKE '%Credit%Card%' OR c.name LIKE '%CardNumber%' THEN 'Financial - Card'
            WHEN c.name LIKE '%Account%' OR c.name LIKE '%Bank%' THEN 'Financial - Account'
            WHEN c.name LIKE '%Salary%' OR c.name LIKE '%Wage%' OR c.name LIKE '%Income%' THEN 'Financial - Compensation'
            WHEN c.name LIKE '%Password%' OR c.name LIKE '%Secret%' OR c.name LIKE '%Key%' THEN 'Confidential - Credential'
            WHEN c.name LIKE '%Medical%' OR c.name LIKE '%Health%' OR c.name LIKE '%Diagnosis%' THEN 'PHI - Medical'
            ELSE 'Review Required'
        END AS SuggestedClassification,
        CASE 
            WHEN c.name LIKE '%SSN%' OR c.name LIKE '%Credit%Card%' OR c.name LIKE '%Password%' THEN 1
            ELSE 0
        END AS EncryptionRecommended,
        CASE 
            WHEN c.name LIKE '%SSN%' OR c.name LIKE '%Credit%Card%' OR c.name LIKE '%Account%' THEN 1
            ELSE 0
        END AS MaskingRecommended
    FROM sys.columns c
    INNER JOIN sys.tables t ON c.object_id = t.object_id
    WHERE t.is_ms_shipped = 0
      AND (c.name LIKE '%SSN%' OR c.name LIKE '%Social%' OR c.name LIKE '%Email%'
           OR c.name LIKE '%Phone%' OR c.name LIKE '%Address%' OR c.name LIKE '%Birth%'
           OR c.name LIKE '%Credit%' OR c.name LIKE '%Card%' OR c.name LIKE '%Account%'
           OR c.name LIKE '%Salary%' OR c.name LIKE '%Password%' OR c.name LIKE '%Medical%'
           OR c.name LIKE '%Health%' OR c.name LIKE '%Bank%' OR c.name LIKE '%Secret%')
    ORDER BY SchemaName, TableName, ColumnName;
    
    -- Auto-populate inventory if requested
    IF @AutoClassify = 1
    BEGIN
        INSERT INTO dbo.SensitiveDataInventory (SchemaName, TableName, ColumnName, DataClassification, 
                                                 EncryptionRequired, MaskingRequired, LastReviewed, ReviewedBy)
        SELECT 
            OBJECT_SCHEMA_NAME(c.object_id),
            OBJECT_NAME(c.object_id),
            c.name,
            CASE 
                WHEN c.name LIKE '%SSN%' THEN 'PII'
                WHEN c.name LIKE '%Credit%Card%' THEN 'Financial'
                WHEN c.name LIKE '%Medical%' OR c.name LIKE '%Health%' THEN 'PHI'
                ELSE 'Confidential'
            END,
            CASE WHEN c.name LIKE '%SSN%' OR c.name LIKE '%Credit%Card%' OR c.name LIKE '%Password%' THEN 1 ELSE 0 END,
            CASE WHEN c.name LIKE '%SSN%' OR c.name LIKE '%Credit%Card%' THEN 1 ELSE 0 END,
            GETDATE(),
            SUSER_SNAME()
        FROM sys.columns c
        INNER JOIN sys.tables t ON c.object_id = t.object_id
        WHERE t.is_ms_shipped = 0
          AND NOT EXISTS (SELECT 1 FROM dbo.SensitiveDataInventory sdi 
                          WHERE sdi.SchemaName = OBJECT_SCHEMA_NAME(c.object_id)
                            AND sdi.TableName = OBJECT_NAME(c.object_id)
                            AND sdi.ColumnName = c.name)
          AND (c.name LIKE '%SSN%' OR c.name LIKE '%Credit%Card%' OR c.name LIKE '%Medical%');
    END
END
GO

-- Generate compliance summary report
CREATE PROCEDURE dbo.GenerateComplianceSummary
    @ComplianceFramework NVARCHAR(20) = 'ALL'  -- SOX, HIPAA, GDPR, PCI, ALL
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Data classification summary
    SELECT 
        'Data Classification' AS Category,
        DataClassification,
        COUNT(*) AS ColumnCount,
        SUM(CASE WHEN EncryptionRequired = 1 THEN 1 ELSE 0 END) AS RequiresEncryption,
        SUM(CASE WHEN MaskingRequired = 1 THEN 1 ELSE 0 END) AS RequiresMasking
    FROM dbo.SensitiveDataInventory
    GROUP BY DataClassification;
    
    -- Access control summary
    SELECT 
        'Access Control' AS Category,
        type_desc AS PrincipalType,
        COUNT(*) AS PrincipalCount
    FROM sys.database_principals
    WHERE type IN ('S', 'U', 'G', 'R')
    GROUP BY type_desc;
    
    -- Encryption status
    SELECT 
        'Encryption Status' AS Category,
        CASE WHEN is_encrypted = 1 THEN 'TDE Enabled' ELSE 'TDE Disabled' END AS Status,
        COUNT(*) AS DatabaseCount
    FROM sys.databases
    WHERE database_id > 4
    GROUP BY is_encrypted;
    
    -- Audit configuration
    SELECT 
        'Audit Status' AS Category,
        name AS AuditName,
        status_desc AS Status,
        audit_file_path AS AuditFilePath
    FROM sys.dm_server_audit_status;
    
    -- Recent compliance events
    SELECT TOP 100
        'Recent Audit Events' AS Category,
        AuditTime,
        AuditType,
        ActionPerformed,
        PerformedBy,
        ObjectName
    FROM dbo.ComplianceAuditLog
    ORDER BY AuditTime DESC;
END
GO
