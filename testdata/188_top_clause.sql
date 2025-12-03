-- Sample 188: TOP Clause Variations
-- Category: Syntax Coverage / Query Patterns
-- Complexity: Intermediate
-- Purpose: Parser testing - TOP clause syntax variations
-- Features: TOP, TOP PERCENT, WITH TIES, TOP in different contexts

-- Pattern 1: Basic TOP
SELECT TOP 10 CustomerID, CustomerName
FROM dbo.Customers;
GO

-- Pattern 2: TOP with parentheses
SELECT TOP (10) CustomerID, CustomerName
FROM dbo.Customers;
GO

-- Pattern 3: TOP without parentheses (legacy)
SELECT TOP 10 CustomerID, CustomerName
FROM dbo.Customers;
GO

-- Pattern 4: TOP with ORDER BY
SELECT TOP 10 CustomerID, CustomerName, CreatedDate
FROM dbo.Customers
ORDER BY CreatedDate DESC;
GO

-- Pattern 5: TOP PERCENT
SELECT TOP 10 PERCENT CustomerID, CustomerName
FROM dbo.Customers
ORDER BY CustomerName;
GO

-- Pattern 6: TOP PERCENT with parentheses
SELECT TOP (10) PERCENT ProductID, ProductName, Price
FROM dbo.Products
ORDER BY Price DESC;
GO

-- Pattern 7: TOP WITH TIES
SELECT TOP 5 WITH TIES ProductID, ProductName, Price
FROM dbo.Products
ORDER BY Price DESC;
GO

-- Pattern 8: TOP PERCENT WITH TIES
SELECT TOP (10) PERCENT WITH TIES EmployeeID, Salary
FROM dbo.Employees
ORDER BY Salary DESC;
GO

-- Pattern 9: TOP with variable
DECLARE @TopCount INT = 25;

SELECT TOP (@TopCount) CustomerID, CustomerName
FROM dbo.Customers
ORDER BY CustomerName;
GO

-- Pattern 10: TOP with expression
DECLARE @PageSize INT = 10;
DECLARE @PageNumber INT = 3;

SELECT TOP (@PageSize * @PageNumber) CustomerID, CustomerName
FROM dbo.Customers
ORDER BY CustomerID;
GO

-- Pattern 11: TOP with subquery (not directly supported, use variable)
DECLARE @DynamicTop INT;
SELECT @DynamicTop = COUNT(*) / 10 FROM dbo.Customers;

SELECT TOP (@DynamicTop) CustomerID, CustomerName
FROM dbo.Customers
ORDER BY CreatedDate DESC;
GO

-- Pattern 12: TOP 1 for existence check
IF EXISTS (SELECT TOP 1 1 FROM dbo.Orders WHERE CustomerID = @CustomerID)
    PRINT 'Customer has orders';
GO

-- Pattern 13: TOP in UPDATE
UPDATE TOP (100) dbo.Orders
SET Status = 'Processed'
WHERE Status = 'Pending';
GO

-- Pattern 14: UPDATE TOP with ORDER BY (requires CTE)
WITH OrdersToUpdate AS (
    SELECT TOP 100 *
    FROM dbo.Orders
    WHERE Status = 'Pending'
    ORDER BY OrderDate
)
UPDATE OrdersToUpdate
SET Status = 'Processing';
GO

-- Pattern 15: TOP in DELETE
DELETE TOP (1000) FROM dbo.LogEntries
WHERE LogDate < DATEADD(DAY, -30, GETDATE());
GO

-- Pattern 16: DELETE TOP with ORDER BY (requires CTE)
WITH OldestLogs AS (
    SELECT TOP 1000 *
    FROM dbo.LogEntries
    ORDER BY LogDate
)
DELETE FROM OldestLogs;
GO

-- Pattern 17: TOP in INSERT
INSERT TOP (100) INTO dbo.CustomerBackup (CustomerID, CustomerName)
SELECT CustomerID, CustomerName
FROM dbo.Customers
WHERE IsActive = 1;
GO

-- Pattern 18: TOP 0 for schema only
SELECT TOP 0 *
INTO #EmptySchema
FROM dbo.Customers;

-- Get structure without data
SELECT * FROM #EmptySchema;
DROP TABLE #EmptySchema;
GO

-- Pattern 19: TOP in subquery
SELECT *
FROM dbo.Customers c
WHERE c.CustomerID IN (
    SELECT TOP 10 o.CustomerID
    FROM dbo.Orders o
    GROUP BY o.CustomerID
    ORDER BY SUM(o.TotalAmount) DESC
);
GO

-- Pattern 20: TOP in derived table
SELECT dt.CustomerID, dt.TotalSpent
FROM (
    SELECT TOP 10 CustomerID, SUM(TotalAmount) AS TotalSpent
    FROM dbo.Orders
    GROUP BY CustomerID
    ORDER BY SUM(TotalAmount) DESC
) AS dt;
GO

-- Pattern 21: TOP with OFFSET FETCH (alternative)
-- TOP 10 starting from row 21
SELECT CustomerID, CustomerName
FROM dbo.Customers
ORDER BY CustomerName
OFFSET 20 ROWS
FETCH NEXT 10 ROWS ONLY;
GO

-- Pattern 22: TOP per group (using ROW_NUMBER)
WITH RankedProducts AS (
    SELECT 
        ProductID,
        ProductName,
        CategoryID,
        Price,
        ROW_NUMBER() OVER (PARTITION BY CategoryID ORDER BY Price DESC) AS RowNum
    FROM dbo.Products
)
SELECT ProductID, ProductName, CategoryID, Price
FROM RankedProducts
WHERE RowNum <= 3;
GO

-- Pattern 23: TOP with DISTINCT
SELECT DISTINCT TOP 5 CategoryID
FROM dbo.Products
ORDER BY CategoryID;
GO

-- Pattern 24: Multiple TOP in same query (subqueries)
SELECT TOP 5 
    c.CustomerID,
    c.CustomerName,
    (SELECT TOP 1 o.OrderDate 
     FROM dbo.Orders o 
     WHERE o.CustomerID = c.CustomerID 
     ORDER BY o.OrderDate DESC) AS LastOrderDate
FROM dbo.Customers c
ORDER BY c.CustomerName;
GO

-- Pattern 25: TOP 1 for scalar value
DECLARE @MaxOrderAmount DECIMAL(18,2);

SELECT TOP 1 @MaxOrderAmount = TotalAmount
FROM dbo.Orders
ORDER BY TotalAmount DESC;

SELECT @MaxOrderAmount AS MaxAmount;
GO
