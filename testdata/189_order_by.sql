-- Sample 189: ORDER BY Clause Variations
-- Category: Syntax Coverage / Query Patterns
-- Complexity: Intermediate
-- Purpose: Parser testing - ORDER BY syntax variations
-- Features: ASC, DESC, NULLS, expressions, collation

-- Pattern 1: Basic ORDER BY
SELECT CustomerID, CustomerName
FROM dbo.Customers
ORDER BY CustomerName;
GO

-- Pattern 2: ORDER BY DESC
SELECT CustomerID, CustomerName, CreatedDate
FROM dbo.Customers
ORDER BY CreatedDate DESC;
GO

-- Pattern 3: ORDER BY ASC explicit
SELECT ProductID, ProductName, Price
FROM dbo.Products
ORDER BY Price ASC;
GO

-- Pattern 4: Multiple columns
SELECT CustomerID, City, CustomerName
FROM dbo.Customers
ORDER BY City, CustomerName;
GO

-- Pattern 5: Multiple columns with mixed direction
SELECT ProductID, CategoryID, Price
FROM dbo.Products
ORDER BY CategoryID ASC, Price DESC;
GO

-- Pattern 6: ORDER BY column number
SELECT CustomerID, CustomerName, Email
FROM dbo.Customers
ORDER BY 2;  -- Order by CustomerName
GO

-- Pattern 7: ORDER BY multiple column numbers
SELECT CustomerID, City, CustomerName
FROM dbo.Customers
ORDER BY 2, 3;
GO

-- Pattern 8: ORDER BY expression
SELECT ProductID, ProductName, Price, StockQuantity
FROM dbo.Products
ORDER BY Price * StockQuantity DESC;
GO

-- Pattern 9: ORDER BY CASE expression
SELECT ProductID, ProductName, CategoryID, Price
FROM dbo.Products
ORDER BY 
    CASE CategoryID
        WHEN 1 THEN 1
        WHEN 3 THEN 2
        WHEN 2 THEN 3
        ELSE 4
    END,
    Price DESC;
GO

-- Pattern 10: ORDER BY with CASE for custom NULL handling
SELECT CustomerID, CustomerName, Email
FROM dbo.Customers
ORDER BY 
    CASE WHEN Email IS NULL THEN 1 ELSE 0 END,  -- NULLs last
    Email;
GO

-- Pattern 11: ORDER BY NULLs first
SELECT CustomerID, CustomerName, Phone
FROM dbo.Customers
ORDER BY 
    CASE WHEN Phone IS NULL THEN 0 ELSE 1 END,  -- NULLs first
    Phone;
GO

-- Pattern 12: ORDER BY with function
SELECT CustomerID, CustomerName
FROM dbo.Customers
ORDER BY LEN(CustomerName) DESC;
GO

-- Pattern 13: ORDER BY with date function
SELECT OrderID, OrderDate
FROM dbo.Orders
ORDER BY YEAR(OrderDate), MONTH(OrderDate), DAY(OrderDate);
GO

-- Pattern 14: ORDER BY alias
SELECT 
    CustomerID,
    CustomerName,
    UPPER(CustomerName) AS UpperName
FROM dbo.Customers
ORDER BY UpperName;
GO

-- Pattern 15: ORDER BY with COLLATE
SELECT CustomerID, CustomerName
FROM dbo.Customers
ORDER BY CustomerName COLLATE Latin1_General_BIN;
GO

-- Pattern 16: ORDER BY case-sensitive
SELECT CustomerID, CustomerName
FROM dbo.Customers
ORDER BY CustomerName COLLATE Latin1_General_CS_AS;
GO

-- Pattern 17: ORDER BY with OFFSET FETCH
SELECT CustomerID, CustomerName
FROM dbo.Customers
ORDER BY CustomerID
OFFSET 0 ROWS
FETCH NEXT 25 ROWS ONLY;
GO

-- Pattern 18: ORDER BY for pagination
DECLARE @PageSize INT = 20;
DECLARE @PageNumber INT = 3;

SELECT CustomerID, CustomerName
FROM dbo.Customers
ORDER BY CustomerID
OFFSET (@PageNumber - 1) * @PageSize ROWS
FETCH NEXT @PageSize ROWS ONLY;
GO

-- Pattern 19: OFFSET without FETCH (skip rows)
SELECT CustomerID, CustomerName
FROM dbo.Customers
ORDER BY CustomerID
OFFSET 100 ROWS;
GO

-- Pattern 20: FETCH FIRST (alternative syntax)
SELECT CustomerID, CustomerName
FROM dbo.Customers
ORDER BY CustomerID
OFFSET 0 ROWS
FETCH FIRST 10 ROWS ONLY;
GO

-- Pattern 21: ORDER BY with PERCENT
SELECT TOP 10 PERCENT CustomerID, CustomerName
FROM dbo.Customers
ORDER BY CustomerName;
GO

-- Pattern 22: ORDER BY subquery column
SELECT 
    c.CustomerID,
    c.CustomerName,
    (SELECT COUNT(*) FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID) AS OrderCount
FROM dbo.Customers c
ORDER BY OrderCount DESC;
GO

-- Pattern 23: ORDER BY window function
SELECT 
    ProductID,
    ProductName,
    CategoryID,
    Price,
    ROW_NUMBER() OVER (PARTITION BY CategoryID ORDER BY Price DESC) AS CategoryRank
FROM dbo.Products
ORDER BY CategoryRank, CategoryID;
GO

-- Pattern 24: ORDER BY in UNION (only at end)
SELECT CustomerID, CustomerName, 'Customer' AS Type
FROM dbo.Customers
UNION ALL
SELECT SupplierID, SupplierName, 'Supplier'
FROM dbo.Suppliers
ORDER BY Type, CustomerName;
GO

-- Pattern 25: ORDER BY in subquery (requires TOP or OFFSET)
SELECT *
FROM (
    SELECT TOP 100 PERCENT CustomerID, CustomerName
    FROM dbo.Customers
    ORDER BY CustomerName
) AS sorted;
-- Note: ORDER BY in subquery only guaranteed with TOP or OFFSET FETCH
GO

-- Pattern 26: Random order
SELECT CustomerID, CustomerName
FROM dbo.Customers
ORDER BY NEWID();
GO

-- Pattern 27: ORDER BY with IIF
SELECT ProductID, ProductName, Price, IsActive
FROM dbo.Products
ORDER BY IIF(IsActive = 1, 0, 1), Price DESC;
GO
