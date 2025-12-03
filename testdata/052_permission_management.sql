-- Sample 052: Permission and Role Management
-- Source: Microsoft Learn, MSSQLTips, SQLServerCentral
-- Category: Security
-- Complexity: Advanced
-- Features: sys.database_permissions, sp_addrolemember, GRANT/REVOKE, permission auditing

-- Get effective permissions for a user
CREATE PROCEDURE dbo.GetUserEffectivePermissions
    @UserName NVARCHAR(128) = NULL,
    @ObjectName NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @UserName = ISNULL(@UserName, USER_NAME());
    
    -- Direct permissions
    SELECT 
        'Direct' AS PermissionSource,
        pr.name AS Principal,
        pr.type_desc AS PrincipalType,
        pe.permission_name AS Permission,
        pe.state_desc AS PermissionState,
        ISNULL(OBJECT_SCHEMA_NAME(pe.major_id) + '.' + OBJECT_NAME(pe.major_id), 
               CASE pe.class_desc 
                   WHEN 'DATABASE' THEN DB_NAME()
                   ELSE pe.class_desc
               END) AS SecurableObject,
        pe.class_desc AS SecurableClass
    FROM sys.database_permissions pe
    INNER JOIN sys.database_principals pr ON pe.grantee_principal_id = pr.principal_id
    WHERE pr.name = @UserName
      AND (@ObjectName IS NULL OR OBJECT_NAME(pe.major_id) = @ObjectName)
    
    UNION ALL
    
    -- Permissions through role membership
    SELECT 
        'Via Role: ' + r.name AS PermissionSource,
        pr.name AS Principal,
        pr.type_desc AS PrincipalType,
        pe.permission_name AS Permission,
        pe.state_desc AS PermissionState,
        ISNULL(OBJECT_SCHEMA_NAME(pe.major_id) + '.' + OBJECT_NAME(pe.major_id),
               CASE pe.class_desc 
                   WHEN 'DATABASE' THEN DB_NAME()
                   ELSE pe.class_desc
               END) AS SecurableObject,
        pe.class_desc AS SecurableClass
    FROM sys.database_permissions pe
    INNER JOIN sys.database_principals r ON pe.grantee_principal_id = r.principal_id
    INNER JOIN sys.database_role_members rm ON r.principal_id = rm.role_principal_id
    INNER JOIN sys.database_principals pr ON rm.member_principal_id = pr.principal_id
    WHERE pr.name = @UserName
      AND (@ObjectName IS NULL OR OBJECT_NAME(pe.major_id) = @ObjectName)
    
    ORDER BY SecurableObject, Permission;
END
GO

-- Get role hierarchy and members
CREATE PROCEDURE dbo.GetRoleHierarchy
    @RoleName NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    ;WITH RoleHierarchy AS (
        -- Base: direct members
        SELECT 
            r.name AS RoleName,
            m.name AS MemberName,
            m.type_desc AS MemberType,
            1 AS Level,
            CAST(r.name AS NVARCHAR(MAX)) AS RolePath
        FROM sys.database_role_members rm
        INNER JOIN sys.database_principals r ON rm.role_principal_id = r.principal_id
        INNER JOIN sys.database_principals m ON rm.member_principal_id = m.principal_id
        WHERE @RoleName IS NULL OR r.name = @RoleName
        
        UNION ALL
        
        -- Recursive: nested roles
        SELECT 
            rh.MemberName AS RoleName,
            m.name AS MemberName,
            m.type_desc AS MemberType,
            rh.Level + 1,
            CAST(rh.RolePath + ' -> ' + rh.MemberName AS NVARCHAR(MAX))
        FROM RoleHierarchy rh
        INNER JOIN sys.database_role_members rm ON rm.role_principal_id = (
            SELECT principal_id FROM sys.database_principals WHERE name = rh.MemberName
        )
        INNER JOIN sys.database_principals m ON rm.member_principal_id = m.principal_id
        WHERE rh.Level < 10
          AND rh.MemberType = 'DATABASE_ROLE'
    )
    SELECT 
        RoleName,
        MemberName,
        MemberType,
        Level AS NestingLevel,
        RolePath
    FROM RoleHierarchy
    ORDER BY RolePath, Level;
END
GO

-- Clone permissions from one user to another
CREATE PROCEDURE dbo.CloneUserPermissions
    @SourceUser NVARCHAR(128),
    @TargetUser NVARCHAR(128),
    @IncludeRoles BIT = 1,
    @IncludeDirectPermissions BIT = 1,
    @WhatIf BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @Scripts TABLE (ScriptOrder INT IDENTITY(1,1), Script NVARCHAR(MAX));
    
    -- Clone role memberships
    IF @IncludeRoles = 1
    BEGIN
        INSERT INTO @Scripts (Script)
        SELECT 'ALTER ROLE ' + QUOTENAME(r.name) + ' ADD MEMBER ' + QUOTENAME(@TargetUser) + ';'
        FROM sys.database_role_members rm
        INNER JOIN sys.database_principals r ON rm.role_principal_id = r.principal_id
        INNER JOIN sys.database_principals m ON rm.member_principal_id = m.principal_id
        WHERE m.name = @SourceUser
          AND NOT EXISTS (
              SELECT 1 FROM sys.database_role_members rm2
              INNER JOIN sys.database_principals m2 ON rm2.member_principal_id = m2.principal_id
              WHERE rm2.role_principal_id = rm.role_principal_id AND m2.name = @TargetUser
          );
    END
    
    -- Clone direct permissions
    IF @IncludeDirectPermissions = 1
    BEGIN
        INSERT INTO @Scripts (Script)
        SELECT 
            pe.state_desc + ' ' + pe.permission_name + 
            CASE 
                WHEN pe.class_desc = 'OBJECT_OR_COLUMN' 
                THEN ' ON ' + QUOTENAME(OBJECT_SCHEMA_NAME(pe.major_id)) + '.' + QUOTENAME(OBJECT_NAME(pe.major_id))
                WHEN pe.class_desc = 'SCHEMA'
                THEN ' ON SCHEMA::' + QUOTENAME(SCHEMA_NAME(pe.major_id))
                ELSE ''
            END +
            ' TO ' + QUOTENAME(@TargetUser) + ';'
        FROM sys.database_permissions pe
        INNER JOIN sys.database_principals pr ON pe.grantee_principal_id = pr.principal_id
        WHERE pr.name = @SourceUser
          AND pe.class_desc IN ('OBJECT_OR_COLUMN', 'SCHEMA', 'DATABASE');
    END
    
    IF @WhatIf = 1
    BEGIN
        SELECT Script AS 'Scripts to Execute (WhatIf Mode)' FROM @Scripts ORDER BY ScriptOrder;
    END
    ELSE
    BEGIN
        DECLARE @Script NVARCHAR(MAX);
        DECLARE ScriptCursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT Script FROM @Scripts ORDER BY ScriptOrder;
        
        OPEN ScriptCursor;
        FETCH NEXT FROM ScriptCursor INTO @Script;
        
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC sp_executesql @Script;
            PRINT 'Executed: ' + @Script;
            FETCH NEXT FROM ScriptCursor INTO @Script;
        END
        
        CLOSE ScriptCursor;
        DEALLOCATE ScriptCursor;
        
        SELECT COUNT(*) AS ScriptsExecuted FROM @Scripts;
    END
END
GO

-- Generate permission report
CREATE PROCEDURE dbo.GeneratePermissionReport
    @SchemaName NVARCHAR(128) = NULL,
    @IncludeSystemObjects BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Object-level permissions summary
    SELECT 
        OBJECT_SCHEMA_NAME(o.object_id) AS SchemaName,
        o.name AS ObjectName,
        o.type_desc AS ObjectType,
        pr.name AS Principal,
        STRING_AGG(pe.permission_name + ' (' + LEFT(pe.state_desc, 1) + ')', ', ') AS Permissions
    FROM sys.objects o
    CROSS APPLY (
        SELECT DISTINCT pe.grantee_principal_id, pe.permission_name, pe.state_desc
        FROM sys.database_permissions pe
        WHERE pe.major_id = o.object_id
    ) pe
    INNER JOIN sys.database_principals pr ON pe.grantee_principal_id = pr.principal_id
    WHERE (@SchemaName IS NULL OR OBJECT_SCHEMA_NAME(o.object_id) = @SchemaName)
      AND (@IncludeSystemObjects = 1 OR o.is_ms_shipped = 0)
    GROUP BY o.object_id, o.name, o.type_desc, pr.name
    ORDER BY SchemaName, ObjectName, Principal;
END
GO

-- Audit permission changes
CREATE PROCEDURE dbo.SetupPermissionAudit
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Create audit log table
    IF OBJECT_ID('dbo.PermissionAuditLog', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.PermissionAuditLog (
            AuditID INT IDENTITY(1,1) PRIMARY KEY,
            EventTime DATETIME2 DEFAULT SYSDATETIME(),
            EventType NVARCHAR(50),
            Principal NVARCHAR(128),
            Permission NVARCHAR(128),
            SecurableType NVARCHAR(50),
            SecurableName NVARCHAR(256),
            GrantedBy NVARCHAR(128),
            Statement NVARCHAR(MAX)
        );
    END
    
    -- Create trigger for permission tracking would go here
    -- (DDL triggers require specific database context)
    
    SELECT 'Permission audit table created. Configure DDL trigger separately.' AS Status;
END
GO
