-- Sample 186: PIVOT and UNPIVOT Patterns
-- Category: Syntax Coverage / Query Patterns
-- Complexity: Complex
-- Purpose: Parser testing - PIVOT and UNPIVOT syntax
-- Features: Static PIVOT, dynamic PIVOT, UNPIVOT

-- Pattern 1: Basic PIVOT
SELECT *
FROM (
    SELECT CustomerID, YEAR(OrderDate) AS OrderYear, TotalAmount
    FROM dbo.Orders
) AS src
PIVOT (
    SUM(TotalAmount)
    FOR OrderYear IN ([2022], [2023], [2024])
) AS pvt;
GO

-- Pattern 2: PIVOT with multiple aggregates (requires separate queries)
SELECT 
    CustomerID,
    [2022] AS Sales2022,
    [2023] AS Sales2023,
    [2024] AS Sales2024
FROM (
    SELECT CustomerID, YEAR(OrderDate) AS OrderYear, TotalAmount
    FROM dbo.Orders
) AS src
PIVOT (
    SUM(TotalAmount)
    FOR OrderYear IN ([2022], [2023], [2024])
) AS pvt;
GO

-- Pattern 3: PIVOT by month
SELECT *
FROM (
    SELECT 
        ProductID,
        MONTH(SaleDate) AS SaleMonth,
        Quantity
    FROM dbo.Sales
    WHERE YEAR(SaleDate) = 2024
) AS src
PIVOT (
    SUM(Quantity)
    FOR SaleMonth IN ([1], [2], [3], [4], [5], [6], [7], [8], [9], [10], [11], [12])
) AS pvt;
GO

-- Pattern 4: PIVOT with COUNT
SELECT *
FROM (
    SELECT CustomerID, Status, OrderID
    FROM dbo.Orders
) AS src
PIVOT (
    COUNT(OrderID)
    FOR Status IN ([Pending], [Shipped], [Delivered], [Cancelled])
) AS pvt;
GO

-- Pattern 5: PIVOT with AVG
SELECT *
FROM (
    SELECT CategoryID, YEAR(OrderDate) AS OrderYear, od.UnitPrice
    FROM dbo.Orders o
    INNER JOIN dbo.OrderDetails od ON o.OrderID = od.OrderID
    INNER JOIN dbo.Products p ON od.ProductID = p.ProductID
) AS src
PIVOT (
    AVG(UnitPrice)
    FOR OrderYear IN ([2022], [2023], [2024])
) AS pvt;
GO

-- Pattern 6: PIVOT with string values
SELECT *
FROM (
    SELECT ProductID, AttributeName, AttributeValue
    FROM dbo.ProductAttributes
) AS src
PIVOT (
    MAX(AttributeValue)
    FOR AttributeName IN ([Color], [Size], [Material], [Weight])
) AS pvt;
GO

-- Pattern 7: Dynamic PIVOT
DECLARE @Columns NVARCHAR(MAX);
DECLARE @SQL NVARCHAR(MAX);

-- Build column list
SELECT @Columns = STRING_AGG(QUOTENAME(CategoryName), ', ')
FROM dbo.Categories;

-- Build dynamic PIVOT query
SET @SQL = N'
SELECT *
FROM (
    SELECT p.ProductID, c.CategoryName, p.Price
    FROM dbo.Products p
    INNER JOIN dbo.Categories c ON p.CategoryID = c.CategoryID
) AS src
PIVOT (
    SUM(Price)
    FOR CategoryName IN (' + @Columns + ')
) AS pvt';

EXEC sp_executesql @SQL;
GO

-- Pattern 8: Basic UNPIVOT
SELECT ProductID, Attribute, Value
FROM (
    SELECT ProductID, Color, Size, Material
    FROM dbo.Products
) AS src
UNPIVOT (
    Value FOR Attribute IN (Color, Size, Material)
) AS unpvt;
GO

-- Pattern 9: UNPIVOT with column renaming
SELECT 
    ProductID,
    AttributeName,
    AttributeValue
FROM (
    SELECT ProductID, Color, Size, Weight, Material
    FROM dbo.Products
) AS src
UNPIVOT (
    AttributeValue FOR AttributeName IN (Color, Size, Weight, Material)
) AS unpvt;
GO

-- Pattern 10: UNPIVOT numeric columns
SELECT 
    ProductID,
    QuarterName,
    SalesAmount
FROM (
    SELECT ProductID, Q1Sales, Q2Sales, Q3Sales, Q4Sales
    FROM dbo.ProductSales
) AS src
UNPIVOT (
    SalesAmount FOR QuarterName IN (Q1Sales, Q2Sales, Q3Sales, Q4Sales)
) AS unpvt;
GO

-- Pattern 11: Dynamic UNPIVOT
DECLARE @UnpivotColumns NVARCHAR(MAX);
DECLARE @UnpivotSQL NVARCHAR(MAX);

SELECT @UnpivotColumns = STRING_AGG(QUOTENAME(COLUMN_NAME), ', ')
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'ProductAttributes'
  AND COLUMN_NAME NOT IN ('ProductID');

SET @UnpivotSQL = N'
SELECT ProductID, AttributeName, AttributeValue
FROM dbo.ProductAttributes
UNPIVOT (
    AttributeValue FOR AttributeName IN (' + @UnpivotColumns + ')
) AS unpvt';

EXEC sp_executesql @UnpivotSQL;
GO

-- Pattern 12: PIVOT with COALESCE for missing values
SELECT 
    CustomerID,
    COALESCE([2022], 0) AS Sales2022,
    COALESCE([2023], 0) AS Sales2023,
    COALESCE([2024], 0) AS Sales2024
FROM (
    SELECT CustomerID, YEAR(OrderDate) AS OrderYear, TotalAmount
    FROM dbo.Orders
) AS src
PIVOT (
    SUM(TotalAmount)
    FOR OrderYear IN ([2022], [2023], [2024])
) AS pvt;
GO

-- Pattern 13: UNPIVOT preserving NULLs (using CROSS APPLY)
SELECT 
    p.ProductID,
    attr.AttributeName,
    attr.AttributeValue
FROM dbo.Products p
CROSS APPLY (VALUES
    ('Color', p.Color),
    ('Size', p.Size),
    ('Material', p.Material),
    ('Weight', CAST(p.Weight AS VARCHAR(50)))
) AS attr(AttributeName, AttributeValue);
GO

-- Pattern 14: PIVOT with calculated columns
SELECT 
    CategoryID,
    [2022],
    [2023],
    [2024],
    ISNULL([2024], 0) - ISNULL([2023], 0) AS YoYChange
FROM (
    SELECT p.CategoryID, YEAR(o.OrderDate) AS OrderYear, od.Quantity * od.UnitPrice AS Revenue
    FROM dbo.Orders o
    INNER JOIN dbo.OrderDetails od ON o.OrderID = od.OrderID
    INNER JOIN dbo.Products p ON od.ProductID = p.ProductID
) AS src
PIVOT (
    SUM(Revenue)
    FOR OrderYear IN ([2022], [2023], [2024])
) AS pvt;
GO

-- Pattern 15: Multiple PIVOT (simulated)
SELECT 
    CustomerID,
    SUM(CASE WHEN OrderYear = 2023 THEN OrderCount ELSE 0 END) AS Orders2023,
    SUM(CASE WHEN OrderYear = 2024 THEN OrderCount ELSE 0 END) AS Orders2024,
    SUM(CASE WHEN OrderYear = 2023 THEN TotalAmount ELSE 0 END) AS Amount2023,
    SUM(CASE WHEN OrderYear = 2024 THEN TotalAmount ELSE 0 END) AS Amount2024
FROM (
    SELECT 
        CustomerID,
        YEAR(OrderDate) AS OrderYear,
        COUNT(*) AS OrderCount,
        SUM(TotalAmount) AS TotalAmount
    FROM dbo.Orders
    GROUP BY CustomerID, YEAR(OrderDate)
) AS src
GROUP BY CustomerID;
GO
