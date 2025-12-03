-- Sample 102: Static Pagination Queries
-- Category: Static SQL Equivalents
-- Complexity: Intermediate
-- Purpose: Parser testing - actual SQL statements without dynamic string construction
-- Features: OFFSET FETCH, ROW_NUMBER, TOP, multiple pagination patterns

-- Pattern 1: OFFSET FETCH pagination (SQL Server 2012+)
SELECT 
    CustomerID,
    CustomerName,
    Email,
    City,
    Country,
    CreatedDate
FROM dbo.Customers
WHERE IsActive = 1
  AND Country = 'USA'
ORDER BY CustomerName ASC
OFFSET 20 ROWS
FETCH NEXT 10 ROWS ONLY;
GO

-- Pattern 2: ROW_NUMBER pagination (pre-2012 compatible)
SELECT 
    CustomerID,
    CustomerName,
    Email,
    City,
    Country,
    CreatedDate
FROM (
    SELECT 
        CustomerID,
        CustomerName,
        Email,
        City,
        Country,
        CreatedDate,
        ROW_NUMBER() OVER (ORDER BY CustomerName ASC) AS RowNum
    FROM dbo.Customers
    WHERE IsActive = 1
      AND Country = 'USA'
) AS NumberedRows
WHERE RowNum BETWEEN 21 AND 30
ORDER BY RowNum;
GO

-- Pattern 3: TOP with subquery for page skipping
SELECT TOP (10) *
FROM (
    SELECT TOP (30)
        CustomerID,
        CustomerName,
        Email,
        City,
        Country,
        CreatedDate
    FROM dbo.Customers
    WHERE IsActive = 1
    ORDER BY CustomerName ASC
) AS TopRows
ORDER BY CustomerName DESC;
GO

-- Pattern 4: Keyset pagination (seek method) - most efficient
SELECT TOP (10)
    CustomerID,
    CustomerName,
    Email,
    City,
    Country,
    CreatedDate
FROM dbo.Customers
WHERE IsActive = 1
  AND (CustomerName > 'Smith, John' 
       OR (CustomerName = 'Smith, John' AND CustomerID > 12345))
ORDER BY CustomerName ASC, CustomerID ASC;
GO

-- Pattern 5: OFFSET FETCH with total count
SELECT 
    CustomerID,
    CustomerName,
    Email,
    COUNT(*) OVER() AS TotalCount
FROM dbo.Customers
WHERE IsActive = 1
ORDER BY CustomerName
OFFSET 0 ROWS
FETCH NEXT 25 ROWS ONLY;
GO

-- Pattern 6: Pagination with multiple sort columns
SELECT 
    OrderID,
    CustomerID,
    OrderDate,
    TotalAmount,
    Status
FROM dbo.Orders
ORDER BY 
    Status ASC,
    OrderDate DESC,
    OrderID ASC
OFFSET 50 ROWS
FETCH NEXT 25 ROWS ONLY;
GO

-- Pattern 7: Pagination with expressions in ORDER BY
SELECT 
    ProductID,
    ProductName,
    Price,
    Quantity,
    Price * Quantity AS TotalValue
FROM dbo.Products
ORDER BY Price * Quantity DESC, ProductName ASC
OFFSET 0 ROWS
FETCH NEXT 20 ROWS ONLY;
GO

-- Pattern 8: Pagination with CASE in ORDER BY
SELECT 
    EmployeeID,
    FirstName,
    LastName,
    Department,
    HireDate
FROM dbo.Employees
ORDER BY 
    CASE Department 
        WHEN 'Executive' THEN 1
        WHEN 'Management' THEN 2
        WHEN 'Sales' THEN 3
        ELSE 4
    END,
    LastName,
    FirstName
OFFSET 10 ROWS
FETCH NEXT 10 ROWS ONLY;
GO
