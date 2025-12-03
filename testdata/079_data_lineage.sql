-- Sample 079: Data Lineage Tracking
-- Source: Various - Data governance patterns, MSSQLTips, ETL frameworks
-- Category: Audit Trail
-- Complexity: Advanced
-- Features: Column-level lineage, transformation tracking, data flow analysis

-- Setup lineage tracking infrastructure
CREATE PROCEDURE dbo.SetupLineageTracking
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Data sources registry
    IF OBJECT_ID('dbo.DataSources', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.DataSources (
            SourceID INT IDENTITY(1,1) PRIMARY KEY,
            SourceName NVARCHAR(200) NOT NULL,
            SourceType NVARCHAR(50) NOT NULL,  -- Database, File, API, etc.
            ConnectionInfo NVARCHAR(500),
            Description NVARCHAR(MAX),
            IsActive BIT DEFAULT 1,
            CreatedDate DATETIME2 DEFAULT SYSDATETIME()
        );
    END
    
    -- Data flows registry
    IF OBJECT_ID('dbo.DataFlows', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.DataFlows (
            FlowID INT IDENTITY(1,1) PRIMARY KEY,
            FlowName NVARCHAR(200) NOT NULL,
            SourceID INT REFERENCES dbo.DataSources(SourceID),
            TargetSchemaName NVARCHAR(128),
            TargetTableName NVARCHAR(128),
            TransformationType NVARCHAR(50),  -- Direct, Aggregation, Join, etc.
            FlowDescription NVARCHAR(MAX),
            ScheduleInfo NVARCHAR(200),
            LastExecuted DATETIME2,
            IsActive BIT DEFAULT 1,
            CreatedDate DATETIME2 DEFAULT SYSDATETIME()
        );
    END
    
    -- Column-level lineage
    IF OBJECT_ID('dbo.ColumnLineage', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.ColumnLineage (
            LineageID INT IDENTITY(1,1) PRIMARY KEY,
            FlowID INT REFERENCES dbo.DataFlows(FlowID),
            SourceColumn NVARCHAR(128),
            SourceExpression NVARCHAR(MAX),
            TargetSchema NVARCHAR(128),
            TargetTable NVARCHAR(128),
            TargetColumn NVARCHAR(128),
            TransformationLogic NVARCHAR(MAX),
            IsDirectMapping BIT DEFAULT 1,
            CreatedDate DATETIME2 DEFAULT SYSDATETIME()
        );
    END
    
    -- Lineage execution history
    IF OBJECT_ID('dbo.LineageExecutionLog', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.LineageExecutionLog (
            LogID BIGINT IDENTITY(1,1) PRIMARY KEY,
            FlowID INT REFERENCES dbo.DataFlows(FlowID),
            ExecutionStart DATETIME2,
            ExecutionEnd DATETIME2,
            RowsProcessed BIGINT,
            Status NVARCHAR(50),
            ErrorMessage NVARCHAR(MAX)
        );
    END
    
    SELECT 'Lineage tracking infrastructure created' AS Status;
END
GO

-- Register a data flow
CREATE PROCEDURE dbo.RegisterDataFlow
    @FlowName NVARCHAR(200),
    @SourceName NVARCHAR(200),
    @SourceType NVARCHAR(50),
    @TargetSchema NVARCHAR(128),
    @TargetTable NVARCHAR(128),
    @TransformationType NVARCHAR(50),
    @Description NVARCHAR(MAX) = NULL,
    @FlowID INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SourceID INT;
    
    -- Get or create source
    SELECT @SourceID = SourceID FROM dbo.DataSources WHERE SourceName = @SourceName;
    
    IF @SourceID IS NULL
    BEGIN
        INSERT INTO dbo.DataSources (SourceName, SourceType)
        VALUES (@SourceName, @SourceType);
        SET @SourceID = SCOPE_IDENTITY();
    END
    
    -- Create flow
    INSERT INTO dbo.DataFlows (FlowName, SourceID, TargetSchemaName, TargetTableName, TransformationType, FlowDescription)
    VALUES (@FlowName, @SourceID, @TargetSchema, @TargetTable, @TransformationType, @Description);
    
    SET @FlowID = SCOPE_IDENTITY();
    
    SELECT @FlowID AS FlowID, @FlowName AS FlowName;
END
GO

-- Add column lineage mapping
CREATE PROCEDURE dbo.AddColumnLineage
    @FlowID INT,
    @SourceColumn NVARCHAR(128),
    @TargetSchema NVARCHAR(128),
    @TargetTable NVARCHAR(128),
    @TargetColumn NVARCHAR(128),
    @TransformationLogic NVARCHAR(MAX) = NULL,
    @SourceExpression NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    INSERT INTO dbo.ColumnLineage (FlowID, SourceColumn, SourceExpression, TargetSchema, TargetTable, TargetColumn, TransformationLogic, IsDirectMapping)
    VALUES (@FlowID, @SourceColumn, @SourceExpression, @TargetSchema, @TargetTable, @TargetColumn, @TransformationLogic,
            CASE WHEN @TransformationLogic IS NULL THEN 1 ELSE 0 END);
    
    SELECT SCOPE_IDENTITY() AS LineageID;
END
GO

-- Trace column lineage upstream
CREATE PROCEDURE dbo.TraceColumnLineage
    @SchemaName NVARCHAR(128),
    @TableName NVARCHAR(128),
    @ColumnName NVARCHAR(128),
    @Direction NVARCHAR(10) = 'UP'  -- UP (find sources), DOWN (find targets)
AS
BEGIN
    SET NOCOUNT ON;
    
    IF @Direction = 'UP'
    BEGIN
        ;WITH LineageTree AS (
            -- Base: direct sources of this column
            SELECT 
                cl.LineageID,
                cl.FlowID,
                df.FlowName,
                cl.SourceColumn,
                cl.SourceExpression,
                cl.TargetSchema,
                cl.TargetTable,
                cl.TargetColumn,
                cl.TransformationLogic,
                ds.SourceName AS DataSource,
                1 AS Level
            FROM dbo.ColumnLineage cl
            INNER JOIN dbo.DataFlows df ON cl.FlowID = df.FlowID
            INNER JOIN dbo.DataSources ds ON df.SourceID = ds.SourceID
            WHERE cl.TargetSchema = @SchemaName
              AND cl.TargetTable = @TableName
              AND cl.TargetColumn = @ColumnName
            
            UNION ALL
            
            -- Recursive: trace further upstream
            SELECT 
                cl.LineageID,
                cl.FlowID,
                df.FlowName,
                cl.SourceColumn,
                cl.SourceExpression,
                cl.TargetSchema,
                cl.TargetTable,
                cl.TargetColumn,
                cl.TransformationLogic,
                ds.SourceName,
                lt.Level + 1
            FROM dbo.ColumnLineage cl
            INNER JOIN dbo.DataFlows df ON cl.FlowID = df.FlowID
            INNER JOIN dbo.DataSources ds ON df.SourceID = ds.SourceID
            INNER JOIN LineageTree lt ON cl.TargetSchema = lt.TargetSchema 
                                      AND cl.TargetTable = lt.TargetTable
                                      AND cl.TargetColumn = lt.SourceColumn
            WHERE lt.Level < 10
        )
        SELECT 
            Level,
            DataSource,
            FlowName,
            SourceColumn,
            TargetSchema + '.' + TargetTable + '.' + TargetColumn AS TargetPath,
            TransformationLogic,
            SourceExpression
        FROM LineageTree
        ORDER BY Level, FlowName;
    END
    ELSE  -- DOWN
    BEGIN
        ;WITH LineageTree AS (
            SELECT 
                cl.LineageID,
                cl.FlowID,
                df.FlowName,
                cl.SourceColumn,
                cl.TargetSchema,
                cl.TargetTable,
                cl.TargetColumn,
                cl.TransformationLogic,
                1 AS Level
            FROM dbo.ColumnLineage cl
            INNER JOIN dbo.DataFlows df ON cl.FlowID = df.FlowID
            WHERE cl.TargetSchema = @SchemaName
              AND cl.TargetTable = @TableName
              AND cl.SourceColumn = @ColumnName
            
            UNION ALL
            
            SELECT 
                cl.LineageID,
                cl.FlowID,
                df.FlowName,
                cl.SourceColumn,
                cl.TargetSchema,
                cl.TargetTable,
                cl.TargetColumn,
                cl.TransformationLogic,
                lt.Level + 1
            FROM dbo.ColumnLineage cl
            INNER JOIN dbo.DataFlows df ON cl.FlowID = df.FlowID
            INNER JOIN LineageTree lt ON cl.SourceColumn = lt.TargetColumn
                                      AND df.TargetSchemaName = lt.TargetSchema
                                      AND df.TargetTableName = lt.TargetTable
            WHERE lt.Level < 10
        )
        SELECT 
            Level,
            FlowName,
            SourceColumn,
            TargetSchema + '.' + TargetTable + '.' + TargetColumn AS TargetPath,
            TransformationLogic
        FROM LineageTree
        ORDER BY Level, FlowName;
    END
END
GO

-- Generate lineage report for a table
CREATE PROCEDURE dbo.GenerateTableLineageReport
    @SchemaName NVARCHAR(128),
    @TableName NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Data flows feeding this table
    SELECT 
        'Incoming' AS Direction,
        df.FlowName,
        ds.SourceName AS DataSource,
        ds.SourceType,
        df.TransformationType,
        df.LastExecuted,
        (SELECT COUNT(*) FROM dbo.ColumnLineage cl WHERE cl.FlowID = df.FlowID) AS MappedColumns
    FROM dbo.DataFlows df
    INNER JOIN dbo.DataSources ds ON df.SourceID = ds.SourceID
    WHERE df.TargetSchemaName = @SchemaName AND df.TargetTableName = @TableName;
    
    -- Column-level lineage
    SELECT 
        c.name AS ColumnName,
        cl.SourceColumn,
        cl.SourceExpression,
        cl.TransformationLogic,
        df.FlowName,
        ds.SourceName AS DataSource,
        CASE WHEN cl.IsDirectMapping = 1 THEN 'Direct' ELSE 'Transformed' END AS MappingType
    FROM sys.columns c
    LEFT JOIN dbo.ColumnLineage cl ON cl.TargetSchema = @SchemaName 
                                   AND cl.TargetTable = @TableName 
                                   AND cl.TargetColumn = c.name
    LEFT JOIN dbo.DataFlows df ON cl.FlowID = df.FlowID
    LEFT JOIN dbo.DataSources ds ON df.SourceID = ds.SourceID
    WHERE c.object_id = OBJECT_ID(QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName))
    ORDER BY c.column_id;
    
    -- Execution history
    SELECT TOP 10
        df.FlowName,
        el.ExecutionStart,
        el.ExecutionEnd,
        DATEDIFF(SECOND, el.ExecutionStart, el.ExecutionEnd) AS DurationSeconds,
        el.RowsProcessed,
        el.Status
    FROM dbo.LineageExecutionLog el
    INNER JOIN dbo.DataFlows df ON el.FlowID = df.FlowID
    WHERE df.TargetSchemaName = @SchemaName AND df.TargetTableName = @TableName
    ORDER BY el.ExecutionStart DESC;
END
GO
