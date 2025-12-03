-- Sample 081: Cursor Alternatives and Set-Based Operations
-- Source: Various - Itzik Ben-Gan, MSSQLTips, Performance best practices
-- Category: Performance
-- Complexity: Complex
-- Features: Set-based alternatives, quirky update, running totals, gaps and islands

-- Running total without cursor (window function)
CREATE PROCEDURE dbo.CalculateRunningTotals
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @OrderColumn NVARCHAR(128),
    @ValueColumn NVARCHAR(128),
    @PartitionColumn NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @PartitionClause NVARCHAR(200) = '';
    
    IF @PartitionColumn IS NOT NULL
        SET @PartitionClause = 'PARTITION BY ' + QUOTENAME(@PartitionColumn);
    
    SET @SQL = N'
        SELECT 
            *,
            SUM(CAST(' + QUOTENAME(@ValueColumn) + ' AS DECIMAL(18,2))) 
                OVER (' + @PartitionClause + ' ORDER BY ' + QUOTENAME(@OrderColumn) + 
                     ' ROWS UNBOUNDED PRECEDING) AS RunningTotal,
            AVG(CAST(' + QUOTENAME(@ValueColumn) + ' AS DECIMAL(18,2))) 
                OVER (' + @PartitionClause + ' ORDER BY ' + QUOTENAME(@OrderColumn) + 
                     ' ROWS UNBOUNDED PRECEDING) AS RunningAverage,
            COUNT(*) 
                OVER (' + @PartitionClause + ' ORDER BY ' + QUOTENAME(@OrderColumn) + 
                     ' ROWS UNBOUNDED PRECEDING) AS RunningCount
        FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '
        ORDER BY ' + ISNULL(QUOTENAME(@PartitionColumn) + ', ', '') + QUOTENAME(@OrderColumn);
    
    EXEC sp_executesql @SQL;
END
GO

-- Gaps and Islands solution (set-based)
CREATE PROCEDURE dbo.FindGapsAndIslands
    @SchemaName NVARCHAR(128) = 'dbo',
    @TableName NVARCHAR(128),
    @SequenceColumn NVARCHAR(128),
    @GroupColumn NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @GroupClause NVARCHAR(200) = '';
    DECLARE @PartitionClause NVARCHAR(200) = '';
    
    IF @GroupColumn IS NOT NULL
    BEGIN
        SET @GroupClause = QUOTENAME(@GroupColumn) + ', ';
        SET @PartitionClause = 'PARTITION BY ' + QUOTENAME(@GroupColumn);
    END
    
    -- Find Islands (consecutive sequences)
    SET @SQL = N'
        ;WITH Grouped AS (
            SELECT 
                ' + @GroupClause + '
                ' + QUOTENAME(@SequenceColumn) + ' AS SeqValue,
                ' + QUOTENAME(@SequenceColumn) + ' - ROW_NUMBER() OVER (' + @PartitionClause + ' ORDER BY ' + QUOTENAME(@SequenceColumn) + ') AS GroupId
            FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '
        )
        SELECT 
            ' + @GroupClause + '
            MIN(SeqValue) AS IslandStart,
            MAX(SeqValue) AS IslandEnd,
            COUNT(*) AS IslandLength
        FROM Grouped
        GROUP BY ' + @GroupClause + 'GroupId
        ORDER BY ' + @GroupClause + 'MIN(SeqValue)';
    
    PRINT 'Islands (consecutive sequences):';
    EXEC sp_executesql @SQL;
    
    -- Find Gaps
    SET @SQL = N'
        ;WITH Sequences AS (
            SELECT 
                ' + @GroupClause + '
                ' + QUOTENAME(@SequenceColumn) + ' AS CurrentValue,
                LEAD(' + QUOTENAME(@SequenceColumn) + ') OVER (' + @PartitionClause + ' ORDER BY ' + QUOTENAME(@SequenceColumn) + ') AS NextValue
            FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '
        )
        SELECT 
            ' + @GroupClause + '
            CurrentValue + 1 AS GapStart,
            NextValue - 1 AS GapEnd,
            NextValue - CurrentValue - 1 AS GapSize
        FROM Sequences
        WHERE NextValue - CurrentValue > 1
        ORDER BY ' + @GroupClause + 'CurrentValue';
    
    PRINT '';
    PRINT 'Gaps (missing values):';
    EXEC sp_executesql @SQL;
END
GO

-- Replace cursor with recursive CTE
CREATE PROCEDURE dbo.ProcessHierarchyWithoutCursor
    @TableName NVARCHAR(128),
    @IdColumn NVARCHAR(128),
    @ParentIdColumn NVARCHAR(128),
    @ValueColumn NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    
    -- Accumulate values up the hierarchy
    SET @SQL = N'
        ;WITH HierarchyCTE AS (
            -- Leaf nodes
            SELECT 
                ' + QUOTENAME(@IdColumn) + ' AS NodeId,
                ' + QUOTENAME(@ParentIdColumn) + ' AS ParentId,
                ' + QUOTENAME(@ValueColumn) + ' AS NodeValue,
                ' + QUOTENAME(@ValueColumn) + ' AS AccumulatedValue,
                0 AS Level
            FROM dbo.' + QUOTENAME(@TableName) + '
            WHERE ' + QUOTENAME(@IdColumn) + ' NOT IN (SELECT DISTINCT ' + QUOTENAME(@ParentIdColumn) + ' FROM dbo.' + QUOTENAME(@TableName) + ' WHERE ' + QUOTENAME(@ParentIdColumn) + ' IS NOT NULL)
            
            UNION ALL
            
            -- Parent nodes
            SELECT 
                p.' + QUOTENAME(@IdColumn) + ',
                p.' + QUOTENAME(@ParentIdColumn) + ',
                p.' + QUOTENAME(@ValueColumn) + ',
                p.' + QUOTENAME(@ValueColumn) + ' + c.AccumulatedValue,
                c.Level + 1
            FROM dbo.' + QUOTENAME(@TableName) + ' p
            INNER JOIN HierarchyCTE c ON p.' + QUOTENAME(@IdColumn) + ' = c.ParentId
        )
        SELECT 
            NodeId,
            ParentId,
            NodeValue,
            MAX(AccumulatedValue) AS TotalSubtreeValue,
            MAX(Level) AS MaxDepth
        FROM HierarchyCTE
        GROUP BY NodeId, ParentId, NodeValue
        ORDER BY NodeId';
    
    EXEC sp_executesql @SQL;
END
GO

-- Batch update without cursor
CREATE PROCEDURE dbo.BatchUpdateSetBased
    @TableName NVARCHAR(128),
    @SchemaName NVARCHAR(128) = 'dbo',
    @SetClause NVARCHAR(MAX),
    @WhereClause NVARCHAR(MAX) = NULL,
    @BatchSize INT = 10000,
    @WaitBetweenBatches INT = 100  -- milliseconds
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @RowsAffected INT = 1;
    DECLARE @TotalRows INT = 0;
    DECLARE @BatchCount INT = 0;
    DECLARE @PKColumn NVARCHAR(128);
    
    -- Get primary key column
    SELECT @PKColumn = c.name
    FROM sys.index_columns ic
    INNER JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
    INNER JOIN sys.indexes i ON ic.object_id = i.object_id AND ic.index_id = i.index_id
    WHERE i.is_primary_key = 1 
      AND i.object_id = OBJECT_ID(QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName));
    
    IF @PKColumn IS NULL
    BEGIN
        RAISERROR('Table must have a primary key for batch update', 16, 1);
        RETURN;
    END
    
    -- Build batch update query
    SET @SQL = N'
        UPDATE TOP (@BatchSize) ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '
        SET ' + @SetClause;
    
    IF @WhereClause IS NOT NULL
        SET @SQL = @SQL + ' WHERE ' + @WhereClause;
    
    -- Execute in batches
    WHILE @RowsAffected > 0
    BEGIN
        EXEC sp_executesql @SQL, N'@BatchSize INT', @BatchSize = @BatchSize;
        SET @RowsAffected = @@ROWCOUNT;
        SET @TotalRows = @TotalRows + @RowsAffected;
        SET @BatchCount = @BatchCount + 1;
        
        IF @RowsAffected > 0 AND @WaitBetweenBatches > 0
            WAITFOR DELAY @WaitBetweenBatches;
    END
    
    SELECT @TotalRows AS TotalRowsUpdated, @BatchCount AS BatchesExecuted;
END
GO

-- Pivot without cursor
CREATE PROCEDURE dbo.DynamicPivotSetBased
    @TableName NVARCHAR(128),
    @SchemaName NVARCHAR(128) = 'dbo',
    @RowColumn NVARCHAR(128),
    @PivotColumn NVARCHAR(128),
    @ValueColumn NVARCHAR(128),
    @AggFunction NVARCHAR(10) = 'SUM'
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @PivotColumns NVARCHAR(MAX);
    DECLARE @SelectColumns NVARCHAR(MAX);
    
    -- Build column list dynamically
    SET @SQL = N'SELECT @PivotCols = STRING_AGG(QUOTENAME(CAST(' + QUOTENAME(@PivotColumn) + ' AS NVARCHAR(128))), '','')
                FROM (SELECT DISTINCT ' + QUOTENAME(@PivotColumn) + ' FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ') AS PivotValues';
    
    EXEC sp_executesql @SQL, N'@PivotCols NVARCHAR(MAX) OUTPUT', @PivotCols = @PivotColumns OUTPUT;
    
    -- Build select columns for CASE-based pivot
    SET @SelectColumns = '';
    
    SELECT @SelectColumns = @SelectColumns + 
        ',' + @AggFunction + '(CASE WHEN ' + QUOTENAME(@PivotColumn) + ' = ' + QUOTENAME(PivotValue, '''') + 
        ' THEN ' + QUOTENAME(@ValueColumn) + ' END) AS ' + QUOTENAME(PivotValue)
    FROM (SELECT DISTINCT CAST(@PivotColumn AS NVARCHAR(128)) AS PivotValue 
          FROM sys.columns WHERE 1=0) AS x;  -- Placeholder
    
    -- Build final query using PIVOT operator
    SET @SQL = N'
        SELECT ' + QUOTENAME(@RowColumn) + ', ' + @PivotColumns + '
        FROM (
            SELECT ' + QUOTENAME(@RowColumn) + ', ' + QUOTENAME(@PivotColumn) + ', ' + QUOTENAME(@ValueColumn) + '
            FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '
        ) AS SourceTable
        PIVOT (
            ' + @AggFunction + '(' + QUOTENAME(@ValueColumn) + ')
            FOR ' + QUOTENAME(@PivotColumn) + ' IN (' + @PivotColumns + ')
        ) AS PivotTable
        ORDER BY ' + QUOTENAME(@RowColumn);
    
    EXEC sp_executesql @SQL;
END
GO

-- Row-by-row comparison without cursor
CREATE PROCEDURE dbo.CompareRowsSetBased
    @TableName NVARCHAR(128),
    @SchemaName NVARCHAR(128) = 'dbo',
    @OrderColumn NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @Columns NVARCHAR(MAX);
    
    -- Get columns
    SELECT @Columns = STRING_AGG(QUOTENAME(name), ', ')
    FROM sys.columns
    WHERE object_id = OBJECT_ID(QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName));
    
    -- Compare each row to previous
    SET @SQL = N'
        ;WITH Ranked AS (
            SELECT 
                *,
                ROW_NUMBER() OVER (ORDER BY ' + QUOTENAME(@OrderColumn) + ') AS RowNum
            FROM ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + '
        )
        SELECT 
            curr.*,
            ''Changed from previous'' AS Comparison
        FROM Ranked curr
        LEFT JOIN Ranked prev ON curr.RowNum = prev.RowNum + 1
        WHERE prev.RowNum IS NOT NULL
        ORDER BY curr.' + QUOTENAME(@OrderColumn);
    
    EXEC sp_executesql @SQL;
END
GO
