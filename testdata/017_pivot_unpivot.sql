-- Sample 017: PIVOT and UNPIVOT Operations
-- Source: Microsoft Learn, MSSQLTips, Stack Overflow
-- Category: Reporting
-- Complexity: Complex
-- Features: PIVOT, UNPIVOT, Dynamic PIVOT, aggregations

-- Static PIVOT - Monthly sales by product
CREATE PROCEDURE dbo.GetMonthlySalesPivot
    @Year INT
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        ProductID,
        ProductName,
        ISNULL([1], 0) AS Jan,
        ISNULL([2], 0) AS Feb,
        ISNULL([3], 0) AS Mar,
        ISNULL([4], 0) AS Apr,
        ISNULL([5], 0) AS May,
        ISNULL([6], 0) AS Jun,
        ISNULL([7], 0) AS Jul,
        ISNULL([8], 0) AS Aug,
        ISNULL([9], 0) AS Sep,
        ISNULL([10], 0) AS Oct,
        ISNULL([11], 0) AS Nov,
        ISNULL([12], 0) AS [Dec],
        ISNULL([1], 0) + ISNULL([2], 0) + ISNULL([3], 0) + 
        ISNULL([4], 0) + ISNULL([5], 0) + ISNULL([6], 0) +
        ISNULL([7], 0) + ISNULL([8], 0) + ISNULL([9], 0) +
        ISNULL([10], 0) + ISNULL([11], 0) + ISNULL([12], 0) AS YearTotal
    FROM (
        SELECT 
            p.ProductID,
            p.ProductName,
            MONTH(s.SaleDate) AS SaleMonth,
            s.TotalAmount
        FROM dbo.Sales s
        INNER JOIN dbo.Products p ON s.ProductID = p.ProductID
        WHERE YEAR(s.SaleDate) = @Year
    ) AS SourceData
    PIVOT (
        SUM(TotalAmount)
        FOR SaleMonth IN ([1],[2],[3],[4],[5],[6],[7],[8],[9],[10],[11],[12])
    ) AS PivotTable
    ORDER BY ProductName;
END
GO

-- Dynamic PIVOT - Pivot on any column with any aggregation
CREATE PROCEDURE dbo.DynamicPivot
    @TableName NVARCHAR(128),
    @PivotColumn NVARCHAR(128),
    @ValueColumn NVARCHAR(128),
    @AggFunction NVARCHAR(10) = 'SUM',
    @GroupByColumns NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @PivotValues NVARCHAR(MAX);
    DECLARE @SelectList NVARCHAR(MAX);
    
    -- Get distinct values for pivot
    SET @SQL = N'
        SELECT @vals = STRING_AGG(QUOTENAME(PivotValue), '','')
        FROM (
            SELECT DISTINCT CAST(' + QUOTENAME(@PivotColumn) + ' AS NVARCHAR(128)) AS PivotValue
            FROM ' + QUOTENAME(@TableName) + '
            WHERE ' + QUOTENAME(@PivotColumn) + ' IS NOT NULL
        ) AS DistinctVals';
    
    EXEC sp_executesql @SQL, N'@vals NVARCHAR(MAX) OUTPUT', @vals = @PivotValues OUTPUT;
    
    IF @PivotValues IS NULL
    BEGIN
        RAISERROR('No values found for pivot column', 16, 1);
        RETURN;
    END
    
    -- Build group by clause
    IF @GroupByColumns IS NULL
        SET @GroupByColumns = '';
    ELSE
        SET @GroupByColumns = @GroupByColumns + ', ';
    
    -- Build the dynamic pivot query
    SET @SQL = N'
        SELECT ' + @GroupByColumns + @PivotValues + '
        FROM (
            SELECT ' + 
                CASE WHEN @GroupByColumns = '' THEN '' 
                     ELSE REPLACE(@GroupByColumns, ', ', ', ') END +
                QUOTENAME(@PivotColumn) + ' AS PivotColumn, ' +
                QUOTENAME(@ValueColumn) + ' AS ValueColumn
            FROM ' + QUOTENAME(@TableName) + '
        ) AS SourceData
        PIVOT (
            ' + @AggFunction + '(ValueColumn)
            FOR PivotColumn IN (' + @PivotValues + ')
        ) AS PivotTable';
    
    EXEC sp_executesql @SQL;
END
GO

-- UNPIVOT - Convert columns to rows
CREATE PROCEDURE dbo.UnpivotMonthlySales
    @Year INT
AS
BEGIN
    SET NOCOUNT ON;
    
    -- First create the pivoted data, then unpivot
    WITH MonthlySales AS (
        SELECT 
            ProductID,
            ProductName,
            ISNULL([1], 0) AS Jan,
            ISNULL([2], 0) AS Feb,
            ISNULL([3], 0) AS Mar,
            ISNULL([4], 0) AS Apr,
            ISNULL([5], 0) AS May,
            ISNULL([6], 0) AS Jun,
            ISNULL([7], 0) AS Jul,
            ISNULL([8], 0) AS Aug,
            ISNULL([9], 0) AS Sep,
            ISNULL([10], 0) AS Oct,
            ISNULL([11], 0) AS Nov,
            ISNULL([12], 0) AS [Dec]
        FROM (
            SELECT 
                p.ProductID,
                p.ProductName,
                MONTH(s.SaleDate) AS SaleMonth,
                s.TotalAmount
            FROM dbo.Sales s
            INNER JOIN dbo.Products p ON s.ProductID = p.ProductID
            WHERE YEAR(s.SaleDate) = @Year
        ) AS SourceData
        PIVOT (
            SUM(TotalAmount)
            FOR SaleMonth IN ([1],[2],[3],[4],[5],[6],[7],[8],[9],[10],[11],[12])
        ) AS PivotTable
    )
    SELECT 
        ProductID,
        ProductName,
        MonthName,
        SalesAmount
    FROM MonthlySales
    UNPIVOT (
        SalesAmount FOR MonthName IN (Jan, Feb, Mar, Apr, May, Jun, 
                                       Jul, Aug, Sep, Oct, Nov, [Dec])
    ) AS UnpivotTable
    WHERE SalesAmount > 0
    ORDER BY ProductID, 
        CASE MonthName 
            WHEN 'Jan' THEN 1 WHEN 'Feb' THEN 2 WHEN 'Mar' THEN 3
            WHEN 'Apr' THEN 4 WHEN 'May' THEN 5 WHEN 'Jun' THEN 6
            WHEN 'Jul' THEN 7 WHEN 'Aug' THEN 8 WHEN 'Sep' THEN 9
            WHEN 'Oct' THEN 10 WHEN 'Nov' THEN 11 WHEN 'Dec' THEN 12
        END;
END
GO

-- Cross-tab with multiple aggregations
CREATE PROCEDURE dbo.GetSalesCrossTab
    @StartDate DATE,
    @EndDate DATE
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        c.CategoryName,
        r.RegionName,
        COUNT(DISTINCT s.SaleID) AS TransactionCount,
        COUNT(DISTINCT s.CustomerID) AS UniqueCustomers,
        SUM(s.Quantity) AS TotalQuantity,
        SUM(s.TotalAmount) AS TotalRevenue,
        AVG(s.TotalAmount) AS AvgTransactionValue,
        MIN(s.TotalAmount) AS MinTransaction,
        MAX(s.TotalAmount) AS MaxTransaction
    FROM dbo.Sales s
    INNER JOIN dbo.Products p ON s.ProductID = p.ProductID
    INNER JOIN dbo.Categories c ON p.CategoryID = c.CategoryID
    INNER JOIN dbo.Regions r ON s.RegionID = r.RegionID
    WHERE s.SaleDate BETWEEN @StartDate AND @EndDate
    GROUP BY GROUPING SETS (
        (c.CategoryName, r.RegionName),  -- Detail
        (c.CategoryName),                 -- Category subtotal
        (r.RegionName),                   -- Region subtotal
        ()                                -- Grand total
    )
    ORDER BY 
        GROUPING(c.CategoryName),
        GROUPING(r.RegionName),
        c.CategoryName,
        r.RegionName;
END
GO

-- Dynamic cross-tab report
CREATE PROCEDURE dbo.GenerateCrossTabReport
    @RowField NVARCHAR(128),
    @ColumnField NVARCHAR(128),
    @ValueField NVARCHAR(128),
    @TableName NVARCHAR(128),
    @AggFunction NVARCHAR(10) = 'SUM',
    @IncludeTotals BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @ColumnList NVARCHAR(MAX);
    DECLARE @TotalExpression NVARCHAR(MAX) = '';
    
    -- Get distinct column values
    SET @SQL = N'
        SELECT @cols = STRING_AGG(QUOTENAME(ColVal), '','') WITHIN GROUP (ORDER BY ColVal)
        FROM (
            SELECT DISTINCT CAST(' + QUOTENAME(@ColumnField) + ' AS NVARCHAR(128)) AS ColVal
            FROM ' + QUOTENAME(@TableName) + '
            WHERE ' + QUOTENAME(@ColumnField) + ' IS NOT NULL
        ) x';
    
    EXEC sp_executesql @SQL, N'@cols NVARCHAR(MAX) OUTPUT', @cols = @ColumnList OUTPUT;
    
    -- Build total expression if needed
    IF @IncludeTotals = 1
    BEGIN
        SET @SQL = N'
            SELECT @totals = STRING_AGG(''ISNULL('' + QUOTENAME(ColVal) + '', 0)'', '' + '')
            FROM (
                SELECT DISTINCT CAST(' + QUOTENAME(@ColumnField) + ' AS NVARCHAR(128)) AS ColVal
                FROM ' + QUOTENAME(@TableName) + '
            ) x';
        
        EXEC sp_executesql @SQL, N'@totals NVARCHAR(MAX) OUTPUT', @totals = @TotalExpression OUTPUT;
        SET @TotalExpression = ', ' + @TotalExpression + ' AS RowTotal';
    END
    
    -- Build and execute pivot query
    SET @SQL = N'
        SELECT ' + QUOTENAME(@RowField) + ', ' + @ColumnList + @TotalExpression + '
        FROM (
            SELECT ' + QUOTENAME(@RowField) + ', ' + 
                       QUOTENAME(@ColumnField) + ', ' + 
                       QUOTENAME(@ValueField) + '
            FROM ' + QUOTENAME(@TableName) + '
        ) src
        PIVOT (
            ' + @AggFunction + '(' + QUOTENAME(@ValueField) + ')
            FOR ' + QUOTENAME(@ColumnField) + ' IN (' + @ColumnList + ')
        ) pvt
        ORDER BY ' + QUOTENAME(@RowField);
    
    EXEC sp_executesql @SQL;
END
GO
