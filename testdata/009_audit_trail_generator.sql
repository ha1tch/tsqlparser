-- Sample 009: Audit Trail Generator
-- Source: CodeProject, SQLShack - Audit Trail patterns
-- Category: Audit Trail
-- Complexity: Advanced
-- Features: Dynamic SQL, Triggers, FOR JSON PATH, System metadata

CREATE PROCEDURE dbo.GenerateAuditTrail
    @TableName NVARCHAR(128),
    @SchemaName NVARCHAR(128) = 'dbo',
    @AuditTableSuffix NVARCHAR(50) = '_Audit',
    @DropExisting BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @FullTableName NVARCHAR(261) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName);
    DECLARE @AuditTableName NVARCHAR(261) = QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName + @AuditTableSuffix);
    DECLARE @TriggerName NVARCHAR(128) = 'TR_' + @TableName + '_Audit';
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @Columns NVARCHAR(MAX);
    DECLARE @ColumnList NVARCHAR(MAX);
    DECLARE @InsertedSelect NVARCHAR(MAX);
    DECLARE @DeletedSelect NVARCHAR(MAX);
    
    -- Validate source table exists
    IF NOT EXISTS (
        SELECT 1 FROM sys.tables t
        INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
        WHERE t.name = @TableName AND s.name = @SchemaName
    )
    BEGIN
        RAISERROR('Source table does not exist: %s.%s', 16, 1, @SchemaName, @TableName);
        RETURN;
    END
    
    -- Get column list
    SELECT @ColumnList = STRING_AGG(QUOTENAME(c.name), ', ') WITHIN GROUP (ORDER BY c.column_id)
    FROM sys.columns c
    INNER JOIN sys.tables t ON c.object_id = t.object_id
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE t.name = @TableName AND s.name = @SchemaName;
    
    -- Build column definitions for audit table
    SELECT @Columns = STRING_AGG(
        QUOTENAME(c.name) + ' ' + 
        tp.name + 
        CASE 
            WHEN tp.name IN ('varchar', 'nvarchar', 'char', 'nchar') 
            THEN '(' + CASE WHEN c.max_length = -1 THEN 'MAX' ELSE CAST(c.max_length AS VARCHAR(10)) END + ')'
            WHEN tp.name IN ('decimal', 'numeric') 
            THEN '(' + CAST(c.precision AS VARCHAR(10)) + ',' + CAST(c.scale AS VARCHAR(10)) + ')'
            ELSE ''
        END + ' NULL',
        ', '
    ) WITHIN GROUP (ORDER BY c.column_id)
    FROM sys.columns c
    INNER JOIN sys.tables t ON c.object_id = t.object_id
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    INNER JOIN sys.types tp ON c.user_type_id = tp.user_type_id
    WHERE t.name = @TableName AND s.name = @SchemaName;
    
    -- Drop existing audit table if requested
    IF @DropExisting = 1
    BEGIN
        SET @SQL = N'IF OBJECT_ID(''' + @AuditTableName + ''') IS NOT NULL DROP TABLE ' + @AuditTableName;
        EXEC sp_executesql @SQL;
        
        SET @SQL = N'IF OBJECT_ID(''' + @FullTableName + '.' + @TriggerName + ''', ''TR'') IS NOT NULL DROP TRIGGER ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TriggerName);
        EXEC sp_executesql @SQL;
    END
    
    -- Create audit table
    SET @SQL = N'
    CREATE TABLE ' + @AuditTableName + ' (
        AuditID BIGINT IDENTITY(1,1) PRIMARY KEY,
        AuditAction CHAR(1) NOT NULL,  -- I=Insert, U=Update, D=Delete
        AuditDate DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
        AuditUser NVARCHAR(128) NOT NULL DEFAULT SUSER_SNAME(),
        AuditApp NVARCHAR(128) NULL DEFAULT APP_NAME(),
        AuditHost NVARCHAR(128) NULL DEFAULT HOST_NAME(),
        ' + @Columns + '
    )';
    
    EXEC sp_executesql @SQL;
    
    -- Create audit trigger
    SET @SQL = N'
    CREATE TRIGGER ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TriggerName) + '
    ON ' + @FullTableName + '
    AFTER INSERT, UPDATE, DELETE
    AS
    BEGIN
        SET NOCOUNT ON;
        
        DECLARE @Action CHAR(1);
        
        IF EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted)
            SET @Action = ''U'';  -- Update
        ELSE IF EXISTS (SELECT 1 FROM inserted)
            SET @Action = ''I'';  -- Insert
        ELSE IF EXISTS (SELECT 1 FROM deleted)
            SET @Action = ''D'';  -- Delete
        ELSE
            RETURN;  -- No action
        
        -- For INSERT and UPDATE, log the new values
        IF @Action IN (''I'', ''U'')
        BEGIN
            INSERT INTO ' + @AuditTableName + ' (AuditAction, ' + @ColumnList + ')
            SELECT ''' + 'I' + ''', ' + @ColumnList + '
            FROM inserted;
        END
        
        -- For DELETE, log the old values
        IF @Action = ''D''
        BEGIN
            INSERT INTO ' + @AuditTableName + ' (AuditAction, ' + @ColumnList + ')
            SELECT ''D'', ' + @ColumnList + '
            FROM deleted;
        END
    END';
    
    EXEC sp_executesql @SQL;
    
    -- Return confirmation
    SELECT 
        'Audit trail created successfully' AS Status,
        @AuditTableName AS AuditTable,
        @TriggerName AS TriggerName;
END
GO


-- JSON-based audit trail procedure
CREATE PROCEDURE dbo.LogChangeAsJSON
    @TableName NVARCHAR(128),
    @PrimaryKeyValue NVARCHAR(100),
    @Action NVARCHAR(10),
    @OldValues NVARCHAR(MAX) = NULL,  -- JSON
    @NewValues NVARCHAR(MAX) = NULL,  -- JSON
    @UserID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    INSERT INTO dbo.AuditTrailJSON (
        TableName,
        PrimaryKeyValue,
        Action,
        OldRowData,
        NewRowData,
        ChangedBy,
        ChangedDate,
        AppName,
        HostName
    )
    VALUES (
        @TableName,
        @PrimaryKeyValue,
        @Action,
        @OldValues,
        @NewValues,
        COALESCE(@UserID, SUSER_ID()),
        SYSDATETIME(),
        APP_NAME(),
        HOST_NAME()
    );
END
GO


-- Query audit history
CREATE PROCEDURE dbo.GetAuditHistory
    @TableName NVARCHAR(128),
    @PrimaryKeyValue NVARCHAR(100) = NULL,
    @StartDate DATETIME2 = NULL,
    @EndDate DATETIME2 = NULL,
    @Action NVARCHAR(10) = NULL,
    @TopN INT = 100
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT TOP (@TopN)
        AuditID,
        TableName,
        PrimaryKeyValue,
        Action,
        OldRowData,
        NewRowData,
        ChangedBy,
        ChangedDate,
        AppName,
        HostName
    FROM dbo.AuditTrailJSON
    WHERE TableName = @TableName
      AND (@PrimaryKeyValue IS NULL OR PrimaryKeyValue = @PrimaryKeyValue)
      AND (@StartDate IS NULL OR ChangedDate >= @StartDate)
      AND (@EndDate IS NULL OR ChangedDate <= @EndDate)
      AND (@Action IS NULL OR Action = @Action)
    ORDER BY ChangedDate DESC;
END
GO
