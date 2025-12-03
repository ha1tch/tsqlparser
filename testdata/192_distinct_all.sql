-- Sample 192: DISTINCT and ALL Patterns
-- Category: Syntax Coverage / Query Patterns
-- Complexity: Intermediate
-- Purpose: Parser testing - DISTINCT and ALL syntax
-- Features: DISTINCT, ALL, DISTINCTROW

-- Pattern 1: Basic DISTINCT
SELECT DISTINCT Country
FROM dbo.Customers;
GO

-- Pattern 2: DISTINCT on multiple columns
SELECT DISTINCT City, Country
FROM dbo.Customers;
GO

-- Pattern 3: DISTINCT on all columns
SELECT DISTINCT *
FROM dbo.CustomerAddresses;
GO

-- Pattern 4: DISTINCT with ORDER BY
SELECT DISTINCT CategoryID
FROM dbo.Products
ORDER BY CategoryID;
GO

-- Pattern 5: ALL keyword (default, explicit)
SELECT ALL CustomerID, CustomerName
FROM dbo.Customers;
GO

-- Pattern 6: COUNT DISTINCT
SELECT COUNT(DISTINCT Country) AS UniqueCountries
FROM dbo.Customers;
GO

-- Pattern 7: COUNT DISTINCT on multiple expressions
SELECT 
    COUNT(DISTINCT Country) AS UniqueCountries,
    COUNT(DISTINCT City) AS UniqueCities,
    COUNT(DISTINCT CONCAT(City, ', ', Country)) AS UniqueCityCombinations
FROM dbo.Customers;
GO

-- Pattern 8: DISTINCT in subquery
SELECT CustomerID, CustomerName
FROM dbo.Customers
WHERE Country IN (SELECT DISTINCT Country FROM dbo.Suppliers);
GO

-- Pattern 9: DISTINCT TOP
SELECT DISTINCT TOP 10 Country
FROM dbo.Customers
ORDER BY Country;
GO

-- Pattern 10: DISTINCT with expressions
SELECT DISTINCT YEAR(OrderDate) AS OrderYear
FROM dbo.Orders
ORDER BY OrderYear;
GO

-- Pattern 11: DISTINCT with CASE
SELECT DISTINCT
    CASE 
        WHEN Price < 10 THEN 'Low'
        WHEN Price < 50 THEN 'Medium'
        ELSE 'High'
    END AS PriceCategory
FROM dbo.Products;
GO

-- Pattern 12: DISTINCT in aggregate (SUM)
SELECT SUM(DISTINCT Price) AS SumOfUniquePrices
FROM dbo.Products;
GO

-- Pattern 13: DISTINCT in aggregate (AVG)
SELECT 
    AVG(Price) AS AvgAllPrices,
    AVG(DISTINCT Price) AS AvgUniquePrices
FROM dbo.Products;
GO

-- Pattern 14: DISTINCT with JOIN
SELECT DISTINCT c.Country
FROM dbo.Customers c
INNER JOIN dbo.Orders o ON c.CustomerID = o.CustomerID
WHERE o.OrderDate >= '2024-01-01';
GO

-- Pattern 15: DISTINCT vs GROUP BY
-- These often produce same results
SELECT DISTINCT Country FROM dbo.Customers;
SELECT Country FROM dbo.Customers GROUP BY Country;
GO

-- Pattern 16: DISTINCT with NULL
-- NULL is treated as a single distinct value
SELECT DISTINCT Phone  -- Includes NULL as one value
FROM dbo.Customers;
GO

-- Pattern 17: Remove duplicates with ROW_NUMBER
WITH Ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY Email ORDER BY CreatedDate DESC) AS RowNum
    FROM dbo.Customers
)
SELECT *
FROM Ranked
WHERE RowNum = 1;
GO

-- Pattern 18: DISTINCT in UNION (implicit)
SELECT Country FROM dbo.Customers
UNION  -- Implicit DISTINCT
SELECT Country FROM dbo.Suppliers;
GO

-- Pattern 19: ALL in UNION (keeps duplicates)
SELECT Country FROM dbo.Customers
UNION ALL
SELECT Country FROM dbo.Suppliers;
GO

-- Pattern 20: DISTINCT with STRING_AGG
SELECT 
    CustomerID,
    STRING_AGG(ProductName, ', ') AS AllProducts,
    STRING_AGG(DISTINCT Category, ', ') AS UniqueCategories
FROM dbo.OrderProducts
GROUP BY CustomerID;
-- Note: STRING_AGG with DISTINCT may not be supported in all versions
GO

-- Pattern 21: Finding duplicates
SELECT Email, COUNT(*) AS DuplicateCount
FROM dbo.Customers
GROUP BY Email
HAVING COUNT(*) > 1;
GO

-- Pattern 22: DISTINCT with computed columns
SELECT DISTINCT
    CustomerID,
    UPPER(LEFT(CustomerName, 1)) AS Initial
FROM dbo.Customers;
GO

-- Pattern 23: ALL with comparison (quantified predicate)
SELECT * FROM dbo.Products
WHERE Price >= ALL (SELECT Price FROM dbo.Products WHERE CategoryID = 1);
GO

-- Pattern 24: DISTINCT ON simulation (SQL Server doesn't have this)
-- Get one row per customer (the most recent order)
WITH RankedOrders AS (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY CustomerID ORDER BY OrderDate DESC) AS rn
    FROM dbo.Orders
)
SELECT OrderID, CustomerID, OrderDate, TotalAmount
FROM RankedOrders
WHERE rn = 1;
GO

-- Pattern 25: CHECKSUM for distinct rows
SELECT DISTINCT CHECKSUM(*) AS RowHash
FROM dbo.Products;
GO
