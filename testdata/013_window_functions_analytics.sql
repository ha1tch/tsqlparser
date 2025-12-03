-- Sample 013: Window Functions for Analytics
-- Source: Various - MSSQLTips, SQLShack, Itzik Ben-Gan articles
-- Category: Reporting
-- Complexity: Complex
-- Features: Window functions (ROW_NUMBER, RANK, DENSE_RANK, NTILE, LAG, LEAD, 
--           FIRST_VALUE, LAST_VALUE, SUM OVER, AVG OVER), PARTITION BY, ROWS/RANGE

-- Running totals and moving averages
CREATE PROCEDURE dbo.GetSalesAnalytics
    @StartDate DATE,
    @EndDate DATE,
    @ProductID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        s.SaleDate,
        s.ProductID,
        p.ProductName,
        s.Quantity,
        s.TotalAmount,
        
        -- Running total for the period
        SUM(s.TotalAmount) OVER (
            PARTITION BY s.ProductID 
            ORDER BY s.SaleDate
            ROWS UNBOUNDED PRECEDING
        ) AS RunningTotal,
        
        -- 7-day moving average
        AVG(s.TotalAmount) OVER (
            PARTITION BY s.ProductID 
            ORDER BY s.SaleDate
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) AS MovingAvg7Day,
        
        -- 30-day moving sum
        SUM(s.TotalAmount) OVER (
            PARTITION BY s.ProductID 
            ORDER BY s.SaleDate
            ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
        ) AS MovingSum30Day,
        
        -- Previous day's amount
        LAG(s.TotalAmount, 1, 0) OVER (
            PARTITION BY s.ProductID 
            ORDER BY s.SaleDate
        ) AS PreviousDayAmount,
        
        -- Next day's amount
        LEAD(s.TotalAmount, 1, 0) OVER (
            PARTITION BY s.ProductID 
            ORDER BY s.SaleDate
        ) AS NextDayAmount,
        
        -- Day-over-day change
        s.TotalAmount - LAG(s.TotalAmount, 1, 0) OVER (
            PARTITION BY s.ProductID 
            ORDER BY s.SaleDate
        ) AS DayOverDayChange,
        
        -- Percentage of total for product
        s.TotalAmount * 100.0 / SUM(s.TotalAmount) OVER (
            PARTITION BY s.ProductID
        ) AS PctOfProductTotal,
        
        -- Percentage of grand total
        s.TotalAmount * 100.0 / SUM(s.TotalAmount) OVER () AS PctOfGrandTotal
        
    FROM dbo.Sales s
    INNER JOIN dbo.Products p ON s.ProductID = p.ProductID
    WHERE s.SaleDate BETWEEN @StartDate AND @EndDate
      AND (@ProductID IS NULL OR s.ProductID = @ProductID)
    ORDER BY s.ProductID, s.SaleDate;
END
GO

-- Ranking and percentile analysis
CREATE PROCEDURE dbo.GetProductRankings
    @CategoryID INT = NULL,
    @TopN INT = 10
AS
BEGIN
    SET NOCOUNT ON;
    
    WITH ProductSales AS (
        SELECT 
            p.ProductID,
            p.ProductName,
            p.CategoryID,
            c.CategoryName,
            SUM(s.TotalAmount) AS TotalSales,
            COUNT(*) AS TransactionCount,
            AVG(s.TotalAmount) AS AvgSaleAmount
        FROM dbo.Products p
        INNER JOIN dbo.Categories c ON p.CategoryID = c.CategoryID
        LEFT JOIN dbo.Sales s ON p.ProductID = s.ProductID
        WHERE @CategoryID IS NULL OR p.CategoryID = @CategoryID
        GROUP BY p.ProductID, p.ProductName, p.CategoryID, c.CategoryName
    )
    SELECT 
        ProductID,
        ProductName,
        CategoryName,
        TotalSales,
        TransactionCount,
        AvgSaleAmount,
        
        -- Different ranking methods
        ROW_NUMBER() OVER (ORDER BY TotalSales DESC) AS RowNum,
        RANK() OVER (ORDER BY TotalSales DESC) AS SalesRank,
        DENSE_RANK() OVER (ORDER BY TotalSales DESC) AS DenseRank,
        
        -- Rank within category
        ROW_NUMBER() OVER (
            PARTITION BY CategoryID 
            ORDER BY TotalSales DESC
        ) AS CategoryRowNum,
        
        RANK() OVER (
            PARTITION BY CategoryID 
            ORDER BY TotalSales DESC
        ) AS CategoryRank,
        
        -- Percentile (quartiles)
        NTILE(4) OVER (ORDER BY TotalSales DESC) AS Quartile,
        NTILE(10) OVER (ORDER BY TotalSales DESC) AS Decile,
        NTILE(100) OVER (ORDER BY TotalSales DESC) AS Percentile,
        
        -- Percent rank (0 to 1)
        PERCENT_RANK() OVER (ORDER BY TotalSales) AS PercentRank,
        
        -- Cumulative distribution
        CUME_DIST() OVER (ORDER BY TotalSales) AS CumulativeDistribution,
        
        -- First and last in category
        FIRST_VALUE(ProductName) OVER (
            PARTITION BY CategoryID 
            ORDER BY TotalSales DESC
            ROWS UNBOUNDED PRECEDING
        ) AS TopProductInCategory,
        
        LAST_VALUE(ProductName) OVER (
            PARTITION BY CategoryID 
            ORDER BY TotalSales DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS BottomProductInCategory
        
    FROM ProductSales
    WHERE TotalSales IS NOT NULL
    ORDER BY TotalSales DESC;
END
GO

-- Gap and island detection using window functions
CREATE PROCEDURE dbo.FindSequenceGaps
    @TableName NVARCHAR(128),
    @ColumnName NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX);
    
    SET @SQL = N'
        WITH NumberedRows AS (
            SELECT 
                ' + QUOTENAME(@ColumnName) + ' AS Value,
                ROW_NUMBER() OVER (ORDER BY ' + QUOTENAME(@ColumnName) + ') AS RowNum
            FROM ' + QUOTENAME(@TableName) + '
        ),
        Gaps AS (
            SELECT 
                Value,
                RowNum,
                Value - RowNum AS GroupId,
                LAG(Value) OVER (ORDER BY Value) AS PrevValue
            FROM NumberedRows
        )
        SELECT 
            PrevValue + 1 AS GapStart,
            Value - 1 AS GapEnd,
            Value - PrevValue - 1 AS GapSize
        FROM Gaps
        WHERE Value - PrevValue > 1
        ORDER BY GapStart;';
    
    EXEC sp_executesql @SQL;
END
GO
