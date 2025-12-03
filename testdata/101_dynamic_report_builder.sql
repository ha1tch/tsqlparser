-- Sample 101: Dynamic Report Builder
-- Source: Various - Reporting patterns, Dynamic SQL, Pivot/aggregation patterns
-- Category: Reporting
-- Complexity: Advanced
-- Features: Dynamic pivots, configurable reports, saved report definitions, export support

-- Setup report builder infrastructure
CREATE PROCEDURE dbo.SetupReportBuilder
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Report definitions
    IF OBJECT_ID('dbo.ReportDefinitions', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.ReportDefinitions (
            ReportID INT IDENTITY(1,1) PRIMARY KEY,
            ReportName NVARCHAR(100) NOT NULL UNIQUE,
            Description NVARCHAR(500),
            BaseTable NVARCHAR(256),
            ColumnDefinitions NVARCHAR(MAX),  -- JSON
            FilterDefinitions NVARCHAR(MAX),  -- JSON
            GroupByColumns NVARCHAR(MAX),
            OrderByColumns NVARCHAR(MAX),
            CreatedBy NVARCHAR(128) DEFAULT SUSER_SNAME(),
            CreatedDate DATETIME2 DEFAULT SYSDATETIME(),
            ModifiedDate DATETIME2,
            IsActive BIT DEFAULT 1
        );
    END
    
    -- Report execution history
    IF OBJECT_ID('dbo.ReportExecutionLog', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.ReportExecutionLog (
            ExecutionID INT IDENTITY(1,1) PRIMARY KEY,
            ReportID INT,
            ExecutedBy NVARCHAR(128) DEFAULT SUSER_SNAME(),
            ExecutedAt DATETIME2 DEFAULT SYSDATETIME(),
            Parameters NVARCHAR(MAX),
            RowCount INT,
            ExecutionTimeMs INT,
            Status NVARCHAR(20)
        );
    END
    
    SELECT 'Report builder infrastructure created' AS Status;
END
GO

-- Create dynamic pivot report
CREATE PROCEDURE dbo.GenerateDynamicPivotReport
    @BaseTable NVARCHAR(256),
    @RowColumn NVARCHAR(128),
    @PivotColumn NVARCHAR(128),
    @ValueColumn NVARCHAR(128),
    @AggregateFunction NVARCHAR(20) = 'SUM',
    @WhereClause NVARCHAR(MAX) = NULL,
    @TopN INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @PivotColumns NVARCHAR(MAX);
    DECLARE @SelectColumns NVARCHAR(MAX);
    
    -- Get distinct pivot values
    SET @SQL = N'SELECT @cols = STRING_AGG(QUOTENAME(PivotValue), '', '') 
                 FROM (SELECT DISTINCT ' + QUOTENAME(@PivotColumn) + ' AS PivotValue 
                       FROM ' + @BaseTable + 
                       CASE WHEN @WhereClause IS NOT NULL THEN ' WHERE ' + @WhereClause ELSE '' END +
                       ') AS vals';
    
    EXEC sp_executesql @SQL, N'@cols NVARCHAR(MAX) OUTPUT', @cols = @PivotColumns OUTPUT;
    
    -- Build select columns for readable names
    SET @SelectColumns = @PivotColumns;
    
    -- Build and execute pivot query
    SET @SQL = N'
        SELECT ' + CASE WHEN @TopN IS NOT NULL THEN 'TOP (' + CAST(@TopN AS VARCHAR(10)) + ') ' ELSE '' END +
        QUOTENAME(@RowColumn) + ', ' + @SelectColumns + '
        FROM (
            SELECT ' + QUOTENAME(@RowColumn) + ', ' + QUOTENAME(@PivotColumn) + ', ' + QUOTENAME(@ValueColumn) + '
            FROM ' + @BaseTable +
            CASE WHEN @WhereClause IS NOT NULL THEN ' WHERE ' + @WhereClause ELSE '' END + '
        ) AS SourceData
        PIVOT (
            ' + @AggregateFunction + '(' + QUOTENAME(@ValueColumn) + ')
            FOR ' + QUOTENAME(@PivotColumn) + ' IN (' + @PivotColumns + ')
        ) AS PivotTable
        ORDER BY ' + QUOTENAME(@RowColumn);
    
    EXEC sp_executesql @SQL;
END
GO

-- Build and execute configurable report
CREATE PROCEDURE dbo.ExecuteConfigurableReport
    @SelectColumns NVARCHAR(MAX),  -- JSON array: ["Column1", {"column": "Column2", "alias": "Col2", "aggregate": "SUM"}]
    @FromTable NVARCHAR(256),
    @JoinClauses NVARCHAR(MAX) = NULL,  -- JSON array: [{"table": "Table2", "type": "LEFT", "on": "t1.ID = t2.ID"}]
    @WhereConditions NVARCHAR(MAX) = NULL,  -- JSON array: [{"column": "Status", "operator": "=", "value": "Active"}]
    @GroupByColumns NVARCHAR(MAX) = NULL,
    @HavingConditions NVARCHAR(MAX) = NULL,
    @OrderByColumns NVARCHAR(MAX) = NULL,  -- JSON array: [{"column": "Name", "direction": "ASC"}]
    @TopN INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @SelectPart NVARCHAR(MAX) = '';
    DECLARE @JoinPart NVARCHAR(MAX) = '';
    DECLARE @WherePart NVARCHAR(MAX) = '';
    DECLARE @GroupByPart NVARCHAR(MAX) = '';
    DECLARE @OrderByPart NVARCHAR(MAX) = '';
    
    -- Build SELECT clause
    SELECT @SelectPart = STRING_AGG(
        CASE 
            WHEN ISJSON(value) = 1 THEN 
                ISNULL(JSON_VALUE(value, '$.aggregate') + '(', '') +
                QUOTENAME(JSON_VALUE(value, '$.column')) +
                ISNULL(')', '') +
                ISNULL(' AS ' + QUOTENAME(JSON_VALUE(value, '$.alias')), '')
            ELSE QUOTENAME(value)
        END, ', ')
    FROM OPENJSON(@SelectColumns);
    
    -- Build JOIN clauses
    IF @JoinClauses IS NOT NULL
    BEGIN
        SELECT @JoinPart = STRING_AGG(
            ISNULL(JSON_VALUE(value, '$.type'), 'INNER') + ' JOIN ' +
            JSON_VALUE(value, '$.table') + ' ON ' +
            JSON_VALUE(value, '$.on'), ' ')
        FROM OPENJSON(@JoinClauses);
    END
    
    -- Build WHERE clause
    IF @WhereConditions IS NOT NULL
    BEGIN
        SELECT @WherePart = 'WHERE ' + STRING_AGG(
            QUOTENAME(JSON_VALUE(value, '$.column')) + ' ' +
            JSON_VALUE(value, '$.operator') + ' ' +
            CASE 
                WHEN JSON_VALUE(value, '$.operator') IN ('IN', 'NOT IN') THEN '(' + JSON_VALUE(value, '$.value') + ')'
                WHEN JSON_VALUE(value, '$.operator') LIKE '%LIKE%' THEN '''' + JSON_VALUE(value, '$.value') + ''''
                WHEN ISNUMERIC(JSON_VALUE(value, '$.value')) = 1 THEN JSON_VALUE(value, '$.value')
                ELSE '''' + REPLACE(JSON_VALUE(value, '$.value'), '''', '''''') + ''''
            END, ' AND ')
        FROM OPENJSON(@WhereConditions);
    END
    
    -- Build GROUP BY
    IF @GroupByColumns IS NOT NULL
    BEGIN
        SELECT @GroupByPart = 'GROUP BY ' + STRING_AGG(QUOTENAME(value), ', ')
        FROM OPENJSON(@GroupByColumns);
    END
    
    -- Build ORDER BY
    IF @OrderByColumns IS NOT NULL
    BEGIN
        SELECT @OrderByPart = 'ORDER BY ' + STRING_AGG(
            QUOTENAME(JSON_VALUE(value, '$.column')) + ' ' + 
            ISNULL(JSON_VALUE(value, '$.direction'), 'ASC'), ', ')
        FROM OPENJSON(@OrderByColumns);
    END
    
    -- Construct full query
    SET @SQL = 'SELECT ' + 
        CASE WHEN @TopN IS NOT NULL THEN 'TOP (' + CAST(@TopN AS VARCHAR(10)) + ') ' ELSE '' END +
        @SelectPart + ' FROM ' + @FromTable + ' ' +
        ISNULL(@JoinPart + ' ', '') +
        ISNULL(@WherePart + ' ', '') +
        ISNULL(@GroupByPart + ' ', '') +
        ISNULL(@HavingConditions + ' ', '') +
        ISNULL(@OrderByPart, '');
    
    -- Return generated SQL for debugging
    SELECT @SQL AS GeneratedSQL;
    
    -- Execute
    EXEC sp_executesql @SQL;
END
GO

-- Save report definition
CREATE PROCEDURE dbo.SaveReportDefinition
    @ReportName NVARCHAR(100),
    @Description NVARCHAR(500) = NULL,
    @BaseTable NVARCHAR(256),
    @ColumnDefinitions NVARCHAR(MAX),
    @FilterDefinitions NVARCHAR(MAX) = NULL,
    @GroupByColumns NVARCHAR(MAX) = NULL,
    @OrderByColumns NVARCHAR(MAX) = NULL,
    @ReportID INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    IF EXISTS (SELECT 1 FROM dbo.ReportDefinitions WHERE ReportName = @ReportName)
    BEGIN
        UPDATE dbo.ReportDefinitions
        SET Description = @Description,
            BaseTable = @BaseTable,
            ColumnDefinitions = @ColumnDefinitions,
            FilterDefinitions = @FilterDefinitions,
            GroupByColumns = @GroupByColumns,
            OrderByColumns = @OrderByColumns,
            ModifiedDate = SYSDATETIME()
        WHERE ReportName = @ReportName;
        
        SELECT @ReportID = ReportID FROM dbo.ReportDefinitions WHERE ReportName = @ReportName;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.ReportDefinitions (ReportName, Description, BaseTable, ColumnDefinitions, FilterDefinitions, GroupByColumns, OrderByColumns)
        VALUES (@ReportName, @Description, @BaseTable, @ColumnDefinitions, @FilterDefinitions, @GroupByColumns, @OrderByColumns);
        
        SET @ReportID = SCOPE_IDENTITY();
    END
    
    SELECT @ReportID AS ReportID, @ReportName AS ReportName, 'Saved' AS Status;
END
GO

-- Execute saved report
CREATE PROCEDURE dbo.ExecuteSavedReport
    @ReportID INT = NULL,
    @ReportName NVARCHAR(100) = NULL,
    @RuntimeFilters NVARCHAR(MAX) = NULL  -- Additional filters at runtime
AS
BEGIN
    SET NOCOUNT ON;
    
    IF @ReportID IS NULL AND @ReportName IS NOT NULL
        SELECT @ReportID = ReportID FROM dbo.ReportDefinitions WHERE ReportName = @ReportName;
    
    IF @ReportID IS NULL
    BEGIN
        RAISERROR('Report not found', 16, 1);
        RETURN;
    END
    
    DECLARE @StartTime DATETIME2 = SYSDATETIME();
    DECLARE @BaseTable NVARCHAR(256);
    DECLARE @ColumnDefinitions NVARCHAR(MAX);
    DECLARE @FilterDefinitions NVARCHAR(MAX);
    DECLARE @GroupByColumns NVARCHAR(MAX);
    DECLARE @OrderByColumns NVARCHAR(MAX);
    DECLARE @RowCount INT;
    
    SELECT 
        @BaseTable = BaseTable,
        @ColumnDefinitions = ColumnDefinitions,
        @FilterDefinitions = FilterDefinitions,
        @GroupByColumns = GroupByColumns,
        @OrderByColumns = OrderByColumns
    FROM dbo.ReportDefinitions
    WHERE ReportID = @ReportID AND IsActive = 1;
    
    -- Merge runtime filters with saved filters
    IF @RuntimeFilters IS NOT NULL AND @FilterDefinitions IS NOT NULL
    BEGIN
        -- Combine filters (simplified - in practice, merge JSON arrays)
        SET @FilterDefinitions = @RuntimeFilters;
    END
    ELSE IF @RuntimeFilters IS NOT NULL
    BEGIN
        SET @FilterDefinitions = @RuntimeFilters;
    END
    
    -- Execute the report
    EXEC dbo.ExecuteConfigurableReport
        @SelectColumns = @ColumnDefinitions,
        @FromTable = @BaseTable,
        @WhereConditions = @FilterDefinitions,
        @GroupByColumns = @GroupByColumns,
        @OrderByColumns = @OrderByColumns;
    
    SET @RowCount = @@ROWCOUNT;
    
    -- Log execution
    INSERT INTO dbo.ReportExecutionLog (ReportID, Parameters, RowCount, ExecutionTimeMs, Status)
    VALUES (@ReportID, @RuntimeFilters, @RowCount, DATEDIFF(MILLISECOND, @StartTime, SYSDATETIME()), 'Success');
END
GO

-- List available reports
CREATE PROCEDURE dbo.ListAvailableReports
    @IncludeInactive BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        r.ReportID,
        r.ReportName,
        r.Description,
        r.BaseTable,
        r.CreatedBy,
        r.CreatedDate,
        r.ModifiedDate,
        r.IsActive,
        (SELECT COUNT(*) FROM dbo.ReportExecutionLog WHERE ReportID = r.ReportID) AS ExecutionCount,
        (SELECT MAX(ExecutedAt) FROM dbo.ReportExecutionLog WHERE ReportID = r.ReportID) AS LastExecuted
    FROM dbo.ReportDefinitions r
    WHERE r.IsActive = 1 OR @IncludeInactive = 1
    ORDER BY r.ReportName;
END
GO
