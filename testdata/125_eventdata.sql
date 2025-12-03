-- Sample 125: EVENTDATA Function and DDL Trigger Context
-- Category: Missing Syntax Elements
-- Complexity: Advanced
-- Purpose: Parser testing - EVENTDATA() function syntax
-- Features: EVENTDATA, DDL triggers, XML extraction from events

-- Pattern 1: Simple EVENTDATA usage in DDL trigger
CREATE TRIGGER trg_AuditDDL
ON DATABASE
FOR DDL_DATABASE_LEVEL_EVENTS
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @EventData XML = EVENTDATA();
    
    INSERT INTO dbo.DDLAuditLog (
        EventType,
        EventTime,
        LoginName,
        DatabaseName,
        SchemaName,
        ObjectName,
        ObjectType,
        TSQLCommand,
        EventDataXML
    )
    SELECT
        @EventData.value('(/EVENT_INSTANCE/EventType)[1]', 'NVARCHAR(100)'),
        @EventData.value('(/EVENT_INSTANCE/PostTime)[1]', 'DATETIME'),
        @EventData.value('(/EVENT_INSTANCE/LoginName)[1]', 'NVARCHAR(128)'),
        @EventData.value('(/EVENT_INSTANCE/DatabaseName)[1]', 'NVARCHAR(128)'),
        @EventData.value('(/EVENT_INSTANCE/SchemaName)[1]', 'NVARCHAR(128)'),
        @EventData.value('(/EVENT_INSTANCE/ObjectName)[1]', 'NVARCHAR(128)'),
        @EventData.value('(/EVENT_INSTANCE/ObjectType)[1]', 'NVARCHAR(50)'),
        @EventData.value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]', 'NVARCHAR(MAX)'),
        @EventData;
END;
GO

-- Pattern 2: EVENTDATA for specific event types
CREATE TRIGGER trg_AuditTableChanges
ON DATABASE
FOR CREATE_TABLE, ALTER_TABLE, DROP_TABLE
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @EventData XML = EVENTDATA();
    DECLARE @EventType NVARCHAR(100) = @EventData.value('(/EVENT_INSTANCE/EventType)[1]', 'NVARCHAR(100)');
    DECLARE @ObjectName NVARCHAR(128) = @EventData.value('(/EVENT_INSTANCE/ObjectName)[1]', 'NVARCHAR(128)');
    
    IF @EventType = 'DROP_TABLE'
    BEGIN
        -- Log table drops specially
        INSERT INTO dbo.DroppedTablesLog (TableName, DroppedBy, DroppedAt, CommandText)
        SELECT 
            @ObjectName,
            @EventData.value('(/EVENT_INSTANCE/LoginName)[1]', 'NVARCHAR(128)'),
            GETDATE(),
            @EventData.value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]', 'NVARCHAR(MAX)');
    END
END;
GO

-- Pattern 3: EVENTDATA for server-level events
CREATE TRIGGER trg_AuditServerDDL
ON ALL SERVER
FOR DDL_SERVER_LEVEL_EVENTS
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @EventData XML = EVENTDATA();
    
    INSERT INTO master.dbo.ServerDDLAuditLog (
        EventType,
        EventTime,
        LoginName,
        ServerName,
        CommandText
    )
    VALUES (
        @EventData.value('(/EVENT_INSTANCE/EventType)[1]', 'NVARCHAR(100)'),
        @EventData.value('(/EVENT_INSTANCE/PostTime)[1]', 'DATETIME'),
        @EventData.value('(/EVENT_INSTANCE/LoginName)[1]', 'NVARCHAR(128)'),
        @EventData.value('(/EVENT_INSTANCE/ServerName)[1]', 'NVARCHAR(128)'),
        @EventData.value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]', 'NVARCHAR(MAX)')
    );
END;
GO

-- Pattern 4: EVENTDATA for login events
CREATE TRIGGER trg_AuditLogins
ON ALL SERVER
FOR LOGON
AS
BEGIN
    DECLARE @EventData XML = EVENTDATA();
    DECLARE @LoginName NVARCHAR(128) = @EventData.value('(/EVENT_INSTANCE/LoginName)[1]', 'NVARCHAR(128)');
    DECLARE @ClientHost NVARCHAR(128) = @EventData.value('(/EVENT_INSTANCE/ClientHost)[1]', 'NVARCHAR(128)');
    
    -- Block certain logins from certain hosts
    IF @LoginName = 'RestrictedUser' AND @ClientHost NOT LIKE '192.168.1.%'
    BEGIN
        ROLLBACK;
        RAISERROR('Login not allowed from this location.', 16, 1);
    END
    
    -- Log the login attempt
    INSERT INTO master.dbo.LoginAuditLog (LoginName, ClientHost, LoginTime, EventData)
    VALUES (@LoginName, @ClientHost, GETDATE(), @EventData);
END;
GO

-- Pattern 5: EVENTDATA extracting all available elements
CREATE TRIGGER trg_FullEventCapture
ON DATABASE
FOR DDL_DATABASE_LEVEL_EVENTS
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @EventData XML = EVENTDATA();
    
    SELECT
        @EventData.value('(/EVENT_INSTANCE/EventType)[1]', 'NVARCHAR(100)') AS EventType,
        @EventData.value('(/EVENT_INSTANCE/PostTime)[1]', 'DATETIME2') AS PostTime,
        @EventData.value('(/EVENT_INSTANCE/SPID)[1]', 'INT') AS SPID,
        @EventData.value('(/EVENT_INSTANCE/ServerName)[1]', 'NVARCHAR(128)') AS ServerName,
        @EventData.value('(/EVENT_INSTANCE/LoginName)[1]', 'NVARCHAR(128)') AS LoginName,
        @EventData.value('(/EVENT_INSTANCE/UserName)[1]', 'NVARCHAR(128)') AS UserName,
        @EventData.value('(/EVENT_INSTANCE/DatabaseName)[1]', 'NVARCHAR(128)') AS DatabaseName,
        @EventData.value('(/EVENT_INSTANCE/SchemaName)[1]', 'NVARCHAR(128)') AS SchemaName,
        @EventData.value('(/EVENT_INSTANCE/ObjectName)[1]', 'NVARCHAR(128)') AS ObjectName,
        @EventData.value('(/EVENT_INSTANCE/ObjectType)[1]', 'NVARCHAR(50)') AS ObjectType,
        @EventData.value('(/EVENT_INSTANCE/TargetObjectName)[1]', 'NVARCHAR(128)') AS TargetObjectName,
        @EventData.value('(/EVENT_INSTANCE/TargetObjectType)[1]', 'NVARCHAR(50)') AS TargetObjectType,
        @EventData.value('(/EVENT_INSTANCE/TSQLCommand/SetOptions)[1]', 'NVARCHAR(500)') AS SetOptions,
        @EventData.value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]', 'NVARCHAR(MAX)') AS CommandText;
END;
GO

-- Pattern 6: EVENTDATA with index operations
CREATE TRIGGER trg_AuditIndexChanges
ON DATABASE
FOR CREATE_INDEX, ALTER_INDEX, DROP_INDEX
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @EventData XML = EVENTDATA();
    
    INSERT INTO dbo.IndexAuditLog (
        EventType,
        IndexName,
        TableSchema,
        TableName,
        LoginName,
        CommandText,
        EventTime
    )
    SELECT
        @EventData.value('(/EVENT_INSTANCE/EventType)[1]', 'NVARCHAR(100)'),
        @EventData.value('(/EVENT_INSTANCE/ObjectName)[1]', 'NVARCHAR(128)'),
        @EventData.value('(/EVENT_INSTANCE/TargetSchemaName)[1]', 'NVARCHAR(128)'),
        @EventData.value('(/EVENT_INSTANCE/TargetObjectName)[1]', 'NVARCHAR(128)'),
        @EventData.value('(/EVENT_INSTANCE/LoginName)[1]', 'NVARCHAR(128)'),
        @EventData.value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]', 'NVARCHAR(MAX)'),
        GETDATE();
END;
GO

-- Pattern 7: EVENTDATA for permission changes
CREATE TRIGGER trg_AuditPermissions
ON DATABASE
FOR GRANT_DATABASE, DENY_DATABASE, REVOKE_DATABASE
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @EventData XML = EVENTDATA();
    
    INSERT INTO dbo.PermissionAuditLog (
        EventType,
        Grantee,
        Permission,
        ObjectName,
        ObjectType,
        GrantedBy,
        EventTime,
        CommandText
    )
    SELECT
        @EventData.value('(/EVENT_INSTANCE/EventType)[1]', 'NVARCHAR(100)'),
        @EventData.value('(/EVENT_INSTANCE/Grantee)[1]', 'NVARCHAR(128)'),
        @EventData.value('(/EVENT_INSTANCE/Permissions/Permission)[1]', 'NVARCHAR(128)'),
        @EventData.value('(/EVENT_INSTANCE/ObjectName)[1]', 'NVARCHAR(128)'),
        @EventData.value('(/EVENT_INSTANCE/ObjectType)[1]', 'NVARCHAR(50)'),
        @EventData.value('(/EVENT_INSTANCE/LoginName)[1]', 'NVARCHAR(128)'),
        @EventData.value('(/EVENT_INSTANCE/PostTime)[1]', 'DATETIME'),
        @EventData.value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]', 'NVARCHAR(MAX)');
END;
GO

-- Pattern 8: EVENTDATA preventing operations
CREATE TRIGGER trg_PreventTableDrop
ON DATABASE
FOR DROP_TABLE
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @EventData XML = EVENTDATA();
    DECLARE @ObjectName NVARCHAR(128) = @EventData.value('(/EVENT_INSTANCE/ObjectName)[1]', 'NVARCHAR(128)');
    DECLARE @SchemaName NVARCHAR(128) = @EventData.value('(/EVENT_INSTANCE/SchemaName)[1]', 'NVARCHAR(128)');
    
    -- Prevent dropping critical tables
    IF @ObjectName IN ('Customers', 'Orders', 'Products') AND @SchemaName = 'dbo'
    BEGIN
        RAISERROR('Cannot drop critical table %s.%s', 16, 1, @SchemaName, @ObjectName);
        ROLLBACK;
    END
END;
GO

-- Pattern 9: EVENTDATA with multiple command extraction
CREATE TRIGGER trg_AuditStoredProcs
ON DATABASE
FOR CREATE_PROCEDURE, ALTER_PROCEDURE, DROP_PROCEDURE
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @EventData XML = EVENTDATA();
    
    -- Store the full procedure definition when created/altered
    INSERT INTO dbo.ProcedureVersionHistory (
        SchemaName,
        ProcedureName,
        EventType,
        Definition,
        ModifiedBy,
        ModifiedAt
    )
    SELECT
        @EventData.value('(/EVENT_INSTANCE/SchemaName)[1]', 'NVARCHAR(128)'),
        @EventData.value('(/EVENT_INSTANCE/ObjectName)[1]', 'NVARCHAR(128)'),
        @EventData.value('(/EVENT_INSTANCE/EventType)[1]', 'NVARCHAR(100)'),
        @EventData.value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]', 'NVARCHAR(MAX)'),
        @EventData.value('(/EVENT_INSTANCE/LoginName)[1]', 'NVARCHAR(128)'),
        @EventData.value('(/EVENT_INSTANCE/PostTime)[1]', 'DATETIME');
END;
GO

-- Pattern 10: Querying stored EVENTDATA XML
SELECT 
    LogID,
    EventDataXML.value('(/EVENT_INSTANCE/EventType)[1]', 'NVARCHAR(100)') AS EventType,
    EventDataXML.value('(/EVENT_INSTANCE/ObjectName)[1]', 'NVARCHAR(128)') AS ObjectName,
    EventDataXML.query('/EVENT_INSTANCE/TSQLCommand') AS CommandXML
FROM dbo.DDLAuditLog
WHERE EventDataXML.exist('/EVENT_INSTANCE[EventType="CREATE_TABLE"]') = 1;
GO

-- Pattern 11: Sample DDL Audit table structure
CREATE TABLE dbo.DDLAuditLog (
    LogID INT IDENTITY(1,1) PRIMARY KEY,
    EventType NVARCHAR(100),
    EventTime DATETIME DEFAULT GETDATE(),
    LoginName NVARCHAR(128),
    DatabaseName NVARCHAR(128),
    SchemaName NVARCHAR(128),
    ObjectName NVARCHAR(128),
    ObjectType NVARCHAR(50),
    TSQLCommand NVARCHAR(MAX),
    EventDataXML XML
);
GO
