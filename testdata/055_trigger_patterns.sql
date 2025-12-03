-- Sample 055: Event-Driven Trigger Patterns
-- Source: Microsoft Learn, MSSQLTips, Stack Overflow
-- Category: Audit Trail
-- Complexity: Advanced
-- Features: AFTER triggers, INSTEAD OF triggers, DDL triggers, EVENTDATA()

-- Generic audit trigger generator
CREATE PROCEDURE dbo.CreateAuditTrigger
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @AuditTableName NVARCHAR(128) = NULL,
    @IncludeOldValues BIT = 1,
    @IncludeNewValues BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    DECLARE @TriggerName NVARCHAR(128) = 'TR_Audit_' + @TableName;
    DECLARE @Columns NVARCHAR(MAX);
    DECLARE @PKColumn NVARCHAR(128);
    
    SET @AuditTableName = ISNULL(@AuditTableName, @TableName + '_Audit');
    
    -- Get primary key column
    SELECT @PKColumn = c.name
    FROM sys.index_columns ic
    INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
    INNER JOIN sys.indexes i ON ic.object_id = i.object_id AND ic.index_id = i.index_id
    WHERE i.is_primary_key = 1 AND i.object_id = OBJECT_ID(@FullPath);
    
    -- Get all columns
    SELECT @Columns = STRING_AGG(QUOTENAME(name), ', ')
    FROM sys.columns
    WHERE object_id = OBJECT_ID(@FullPath);
    
    -- Create audit table if not exists
    SET @SQL = N'
        IF OBJECT_ID(''dbo.' + @AuditTableName + ''', ''U'') IS NULL
        BEGIN
            CREATE TABLE dbo.' + QUOTENAME(@AuditTableName) + ' (
                AuditID BIGINT IDENTITY(1,1) PRIMARY KEY,
                AuditAction CHAR(1) NOT NULL,  -- I, U, D
                AuditDate DATETIME2 DEFAULT SYSDATETIME(),
                AuditUser NVARCHAR(128) DEFAULT SUSER_SNAME(),
                AuditApp NVARCHAR(128) DEFAULT APP_NAME(),
                RecordID SQL_VARIANT,
                OldValues NVARCHAR(MAX),
                NewValues NVARCHAR(MAX)
            );
        END';
    EXEC sp_executesql @SQL;
    
    -- Create the trigger
    SET @SQL = N'
        CREATE OR ALTER TRIGGER ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TriggerName) + '
        ON ' + @FullPath + '
        AFTER INSERT, UPDATE, DELETE
        AS
        BEGIN
            SET NOCOUNT ON;
            
            DECLARE @Action CHAR(1);
            
            IF EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted)
                SET @Action = ''U'';
            ELSE IF EXISTS (SELECT 1 FROM inserted)
                SET @Action = ''I'';
            ELSE
                SET @Action = ''D'';
            
            -- Insert audit records
            INSERT INTO dbo.' + QUOTENAME(@AuditTableName) + ' (AuditAction, RecordID, OldValues, NewValues)
            SELECT 
                @Action,
                COALESCE(i.' + QUOTENAME(@PKColumn) + ', d.' + QUOTENAME(@PKColumn) + '),';
    
    IF @IncludeOldValues = 1
        SET @SQL = @SQL + '
                (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),';
    ELSE
        SET @SQL = @SQL + '
                NULL,';
    
    IF @IncludeNewValues = 1
        SET @SQL = @SQL + '
                (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)';
    ELSE
        SET @SQL = @SQL + '
                NULL';
    
    SET @SQL = @SQL + '
            FROM inserted i
            FULL OUTER JOIN deleted d ON i.' + QUOTENAME(@PKColumn) + ' = d.' + QUOTENAME(@PKColumn) + ';
        END';
    
    EXEC sp_executesql @SQL;
    
    SELECT 'Audit trigger created: ' + @TriggerName AS Status;
END
GO

-- Create soft delete trigger
CREATE PROCEDURE dbo.CreateSoftDeleteTrigger
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @DeletedFlagColumn NVARCHAR(128) = 'IsDeleted',
    @DeletedDateColumn NVARCHAR(128) = 'DeletedDate',
    @DeletedByColumn NVARCHAR(128) = 'DeletedBy'
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    DECLARE @TriggerName NVARCHAR(128) = 'TR_SoftDelete_' + @TableName;
    DECLARE @PKColumn NVARCHAR(128);
    
    -- Get primary key
    SELECT @PKColumn = c.name
    FROM sys.index_columns ic
    INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
    INNER JOIN sys.indexes i ON ic.object_id = i.object_id AND ic.index_id = i.index_id
    WHERE i.is_primary_key = 1 AND i.object_id = OBJECT_ID(@FullPath);
    
    -- Check if columns exist, add if not
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@FullPath) AND name = @DeletedFlagColumn)
    BEGIN
        SET @SQL = 'ALTER TABLE ' + @FullPath + ' ADD ' + QUOTENAME(@DeletedFlagColumn) + ' BIT DEFAULT 0';
        EXEC sp_executesql @SQL;
    END
    
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(@FullPath) AND name = @DeletedDateColumn)
    BEGIN
        SET @SQL = 'ALTER TABLE ' + @FullPath + ' ADD ' + QUOTENAME(@DeletedDateColumn) + ' DATETIME2 NULL';
        EXEC sp_executesql @SQL;
    END
    
    -- Create INSTEAD OF DELETE trigger
    SET @SQL = N'
        CREATE OR ALTER TRIGGER ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TriggerName) + '
        ON ' + @FullPath + '
        INSTEAD OF DELETE
        AS
        BEGIN
            SET NOCOUNT ON;
            
            UPDATE t
            SET ' + QUOTENAME(@DeletedFlagColumn) + ' = 1,
                ' + QUOTENAME(@DeletedDateColumn) + ' = SYSDATETIME()
            FROM ' + @FullPath + ' t
            INNER JOIN deleted d ON t.' + QUOTENAME(@PKColumn) + ' = d.' + QUOTENAME(@PKColumn) + ';
            
            -- Log the soft delete
            IF @@ROWCOUNT > 0
            BEGIN
                PRINT ''Soft delete performed on '' + CAST(@@ROWCOUNT AS VARCHAR(10)) + '' record(s)'';
            END
        END';
    
    EXEC sp_executesql @SQL;
    
    SELECT 'Soft delete trigger created: ' + @TriggerName AS Status;
END
GO

-- Create cascading update trigger
CREATE PROCEDURE dbo.CreateCascadeUpdateTrigger
    @ParentSchema NVARCHAR(128),
    @ParentTable NVARCHAR(128),
    @ParentColumn NVARCHAR(128),
    @ChildSchema NVARCHAR(128),
    @ChildTable NVARCHAR(128),
    @ChildColumn NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @TriggerName NVARCHAR(128) = 'TR_Cascade_' + @ParentTable + '_' + @ChildTable;
    
    SET @SQL = N'
        CREATE OR ALTER TRIGGER ' + QUOTENAME(@ParentSchema) + '.' + QUOTENAME(@TriggerName) + '
        ON ' + QUOTENAME(@ParentSchema) + '.' + QUOTENAME(@ParentTable) + '
        AFTER UPDATE
        AS
        BEGIN
            SET NOCOUNT ON;
            
            IF UPDATE(' + QUOTENAME(@ParentColumn) + ')
            BEGIN
                UPDATE c
                SET c.' + QUOTENAME(@ChildColumn) + ' = i.' + QUOTENAME(@ParentColumn) + '
                FROM ' + QUOTENAME(@ChildSchema) + '.' + QUOTENAME(@ChildTable) + ' c
                INNER JOIN deleted d ON c.' + QUOTENAME(@ChildColumn) + ' = d.' + QUOTENAME(@ParentColumn) + '
                INNER JOIN inserted i ON d.' + QUOTENAME(@ParentColumn) + ' = (
                    SELECT TOP 1 ' + QUOTENAME(@ParentColumn) + ' 
                    FROM deleted 
                    WHERE ' + QUOTENAME(@ParentColumn) + ' = d.' + QUOTENAME(@ParentColumn) + '
                );
            END
        END';
    
    EXEC sp_executesql @SQL;
    
    SELECT 'Cascade update trigger created: ' + @TriggerName AS Status;
END
GO

-- Create history table trigger (temporal-like without system versioning)
CREATE PROCEDURE dbo.CreateHistoryTrigger
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @HistoryTableName NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FullPath NVARCHAR(256) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    DECLARE @TriggerName NVARCHAR(128) = 'TR_History_' + @TableName;
    DECLARE @Columns NVARCHAR(MAX);
    
    SET @HistoryTableName = ISNULL(@HistoryTableName, @TableName + '_History');
    
    -- Get columns
    SELECT @Columns = STRING_AGG(QUOTENAME(name), ', ')
    FROM sys.columns
    WHERE object_id = OBJECT_ID(@FullPath);
    
    -- Create history table
    SET @SQL = N'
        IF OBJECT_ID(''dbo.' + @HistoryTableName + ''', ''U'') IS NULL
        BEGIN
            SELECT *, 
                   CAST(NULL AS DATETIME2) AS ValidFrom,
                   CAST(NULL AS DATETIME2) AS ValidTo,
                   CAST(NULL AS CHAR(1)) AS ChangeType
            INTO dbo.' + QUOTENAME(@HistoryTableName) + '
            FROM ' + @FullPath + '
            WHERE 1 = 0;
        END';
    EXEC sp_executesql @SQL;
    
    -- Create trigger
    SET @SQL = N'
        CREATE OR ALTER TRIGGER ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TriggerName) + '
        ON ' + @FullPath + '
        AFTER INSERT, UPDATE, DELETE
        AS
        BEGIN
            SET NOCOUNT ON;
            
            -- Handle deletes and updates (capture old values)
            INSERT INTO dbo.' + QUOTENAME(@HistoryTableName) + ' (' + @Columns + ', ValidFrom, ValidTo, ChangeType)
            SELECT ' + @Columns + ', 
                   SYSDATETIME(), NULL,
                   CASE WHEN EXISTS (SELECT 1 FROM inserted) THEN ''U'' ELSE ''D'' END
            FROM deleted;
            
            -- Handle inserts
            INSERT INTO dbo.' + QUOTENAME(@HistoryTableName) + ' (' + @Columns + ', ValidFrom, ValidTo, ChangeType)
            SELECT ' + @Columns + ', SYSDATETIME(), NULL, ''I''
            FROM inserted i
            WHERE NOT EXISTS (SELECT 1 FROM deleted);
        END';
    
    EXEC sp_executesql @SQL;
    
    SELECT 'History trigger created: ' + @TriggerName AS Status;
END
GO

-- List all triggers with details
CREATE PROCEDURE dbo.GetTriggerDetails
    @SchemaName NVARCHAR(128) = NULL,
    @TableName NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        OBJECT_SCHEMA_NAME(t.parent_id) AS SchemaName,
        OBJECT_NAME(t.parent_id) AS TableName,
        t.name AS TriggerName,
        t.type_desc AS TriggerType,
        CASE WHEN t.is_disabled = 1 THEN 'Disabled' ELSE 'Enabled' END AS Status,
        CASE WHEN t.is_instead_of_trigger = 1 THEN 'INSTEAD OF' ELSE 'AFTER' END AS TriggerTiming,
        te.type_desc AS EventType,
        m.definition AS TriggerDefinition
    FROM sys.triggers t
    INNER JOIN sys.trigger_events te ON t.object_id = te.object_id
    LEFT JOIN sys.sql_modules m ON t.object_id = m.object_id
    WHERE t.parent_class = 1  -- Object triggers
      AND (@SchemaName IS NULL OR OBJECT_SCHEMA_NAME(t.parent_id) = @SchemaName)
      AND (@TableName IS NULL OR OBJECT_NAME(t.parent_id) = @TableName)
    ORDER BY SchemaName, TableName, TriggerName;
END
GO
