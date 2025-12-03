-- Sample 103: Static Pivot and Unpivot Queries
-- Category: Static SQL Equivalents
-- Complexity: Complex
-- Purpose: Parser testing - PIVOT/UNPIVOT without dynamic column generation
-- Features: PIVOT, UNPIVOT, multiple aggregations, complex pivots

-- Pattern 1: Simple PIVOT with known columns
SELECT 
    ProductCategory,
    [2021] AS Sales2021,
    [2022] AS Sales2022,
    [2023] AS Sales2023,
    [2024] AS Sales2024
FROM (
    SELECT 
        ProductCategory,
        YEAR(OrderDate) AS OrderYear,
        SaleAmount
    FROM dbo.Sales
    WHERE OrderDate >= '2021-01-01'
) AS SourceData
PIVOT (
    SUM(SaleAmount)
    FOR OrderYear IN ([2021], [2022], [2023], [2024])
) AS PivotTable
ORDER BY ProductCategory;
GO

-- Pattern 2: PIVOT with multiple value columns (pre-aggregated)
SELECT 
    Region,
    [Q1] AS Q1_Sales,
    [Q2] AS Q2_Sales,
    [Q3] AS Q3_Sales,
    [Q4] AS Q4_Sales
FROM (
    SELECT 
        Region,
        'Q' + CAST(DATEPART(QUARTER, OrderDate) AS VARCHAR(1)) AS Quarter,
        Amount
    FROM dbo.RegionalSales
    WHERE YEAR(OrderDate) = 2024
) AS SourceData
PIVOT (
    SUM(Amount)
    FOR Quarter IN ([Q1], [Q2], [Q3], [Q4])
) AS PivotTable;
GO

-- Pattern 3: COUNT pivot
SELECT 
    Department,
    [Active] AS ActiveEmployees,
    [OnLeave] AS OnLeaveEmployees,
    [Terminated] AS TerminatedEmployees
FROM (
    SELECT 
        Department,
        EmployeeStatus,
        EmployeeID
    FROM dbo.Employees
) AS SourceData
PIVOT (
    COUNT(EmployeeID)
    FOR EmployeeStatus IN ([Active], [OnLeave], [Terminated])
) AS PivotTable
ORDER BY Department;
GO

-- Pattern 4: UNPIVOT - columns to rows
SELECT 
    ProductID,
    ProductName,
    QuarterName,
    SalesAmount
FROM (
    SELECT 
        ProductID,
        ProductName,
        Q1Sales,
        Q2Sales,
        Q3Sales,
        Q4Sales
    FROM dbo.ProductQuarterlySales
) AS SourceData
UNPIVOT (
    SalesAmount FOR QuarterName IN (Q1Sales, Q2Sales, Q3Sales, Q4Sales)
) AS UnpivotTable
ORDER BY ProductID, QuarterName;
GO

-- Pattern 5: UNPIVOT with value filtering
SELECT 
    CustomerID,
    ContactType,
    ContactValue
FROM (
    SELECT 
        CustomerID,
        Email,
        Phone,
        Fax,
        Mobile
    FROM dbo.CustomerContacts
) AS SourceData
UNPIVOT (
    ContactValue FOR ContactType IN (Email, Phone, Fax, Mobile)
) AS UnpivotTable
WHERE ContactValue IS NOT NULL
  AND ContactValue <> ''
ORDER BY CustomerID, ContactType;
GO

-- Pattern 6: Double PIVOT (matrix report)
SELECT 
    Region,
    [Electronics_2023] AS Electronics2023,
    [Electronics_2024] AS Electronics2024,
    [Clothing_2023] AS Clothing2023,
    [Clothing_2024] AS Clothing2024,
    [Food_2023] AS Food2023,
    [Food_2024] AS Food2024
FROM (
    SELECT 
        Region,
        Category + '_' + CAST(YEAR(SaleDate) AS VARCHAR(4)) AS CategoryYear,
        Amount
    FROM dbo.Sales
    WHERE YEAR(SaleDate) IN (2023, 2024)
) AS SourceData
PIVOT (
    SUM(Amount)
    FOR CategoryYear IN (
        [Electronics_2023], [Electronics_2024],
        [Clothing_2023], [Clothing_2024],
        [Food_2023], [Food_2024]
    )
) AS PivotTable
ORDER BY Region;
GO

-- Pattern 7: AVG pivot with COALESCE for nulls
SELECT 
    Store,
    COALESCE([Monday], 0) AS Monday,
    COALESCE([Tuesday], 0) AS Tuesday,
    COALESCE([Wednesday], 0) AS Wednesday,
    COALESCE([Thursday], 0) AS Thursday,
    COALESCE([Friday], 0) AS Friday,
    COALESCE([Saturday], 0) AS Saturday,
    COALESCE([Sunday], 0) AS Sunday
FROM (
    SELECT 
        StoreID AS Store,
        DATENAME(WEEKDAY, SaleDate) AS DayName,
        SaleAmount
    FROM dbo.DailySales
) AS SourceData
PIVOT (
    AVG(SaleAmount)
    FOR DayName IN ([Monday], [Tuesday], [Wednesday], [Thursday], [Friday], [Saturday], [Sunday])
) AS PivotTable;
GO

-- Pattern 8: Nested subquery with PIVOT
SELECT 
    p.CategoryName,
    p.[Low] AS LowPriceCount,
    p.[Medium] AS MediumPriceCount,
    p.[High] AS HighPriceCount,
    p.[Premium] AS PremiumPriceCount
FROM (
    SELECT 
        c.CategoryName,
        CASE 
            WHEN pr.Price < 10 THEN 'Low'
            WHEN pr.Price < 50 THEN 'Medium'
            WHEN pr.Price < 100 THEN 'High'
            ELSE 'Premium'
        END AS PriceTier,
        pr.ProductID
    FROM dbo.Products pr
    INNER JOIN dbo.Categories c ON pr.CategoryID = c.CategoryID
    WHERE pr.IsActive = 1
) AS SourceData
PIVOT (
    COUNT(ProductID)
    FOR PriceTier IN ([Low], [Medium], [High], [Premium])
) AS p
ORDER BY p.CategoryName;
GO
