-- Sample 173: Table Expressions and Derived Tables
-- Category: Syntax Coverage / Query Patterns
-- Complexity: Complex
-- Purpose: Parser testing - table expression syntax variations
-- Features: Derived tables, VALUES, table constructors, inline views

-- Pattern 1: Basic derived table
SELECT dt.CustomerID, dt.OrderCount
FROM (
    SELECT CustomerID, COUNT(*) AS OrderCount
    FROM dbo.Orders
    GROUP BY CustomerID
) AS dt
WHERE dt.OrderCount > 5;
GO

-- Pattern 2: Derived table with column aliases
SELECT x.ID, x.Total
FROM (
    SELECT CustomerID, SUM(TotalAmount)
    FROM dbo.Orders
    GROUP BY CustomerID
) AS x(ID, Total);
GO

-- Pattern 3: Nested derived tables
SELECT final.Category, final.AvgTotal
FROM (
    SELECT CategoryID, AVG(OrderTotal) AS AvgTotal
    FROM (
        SELECT 
            p.CategoryID,
            SUM(od.Quantity * od.UnitPrice) AS OrderTotal
        FROM dbo.OrderDetails od
        INNER JOIN dbo.Products p ON od.ProductID = p.ProductID
        GROUP BY p.CategoryID, od.OrderID
    ) AS order_totals
    GROUP BY CategoryID
) AS final(Category, AvgTotal)
WHERE final.AvgTotal > 100;
GO

-- Pattern 4: VALUES clause as table
SELECT * FROM (VALUES 
    (1, 'Active'),
    (2, 'Inactive'),
    (3, 'Pending'),
    (4, 'Cancelled')
) AS StatusTable(StatusID, StatusName);
GO

-- Pattern 5: VALUES with different data types
SELECT * FROM (VALUES
    (1, 'John', '2024-01-15', 100.50),
    (2, 'Jane', '2024-02-20', 200.75),
    (3, 'Bob', '2024-03-25', 150.00)
) AS SampleData(ID, Name, Date, Amount);
GO

-- Pattern 6: VALUES in INSERT
INSERT INTO dbo.Customers (CustomerName, Email, Phone)
VALUES 
    ('Customer 1', 'c1@example.com', '111-1111'),
    ('Customer 2', 'c2@example.com', '222-2222'),
    ('Customer 3', 'c3@example.com', '333-3333');
GO

-- Pattern 7: VALUES with CROSS JOIN for combinations
SELECT nums.n, letters.l
FROM (VALUES (1), (2), (3)) AS nums(n)
CROSS JOIN (VALUES ('A'), ('B'), ('C')) AS letters(l);
GO

-- Pattern 8: Derived table in UPDATE
UPDATE c
SET c.TotalOrders = dt.OrderCount,
    c.TotalSpent = dt.TotalAmount
FROM dbo.Customers c
INNER JOIN (
    SELECT CustomerID, COUNT(*) AS OrderCount, SUM(TotalAmount) AS TotalAmount
    FROM dbo.Orders
    GROUP BY CustomerID
) AS dt ON c.CustomerID = dt.CustomerID;
GO

-- Pattern 9: Derived table in DELETE
DELETE FROM c
FROM dbo.Customers c
INNER JOIN (
    SELECT CustomerID
    FROM dbo.Orders
    GROUP BY CustomerID
    HAVING MAX(OrderDate) < DATEADD(YEAR, -5, GETDATE())
) AS inactive ON c.CustomerID = inactive.CustomerID;
GO

-- Pattern 10: Derived table with window functions
SELECT *
FROM (
    SELECT 
        CustomerID,
        OrderID,
        TotalAmount,
        ROW_NUMBER() OVER (PARTITION BY CustomerID ORDER BY TotalAmount DESC) AS rn
    FROM dbo.Orders
) AS ranked
WHERE rn <= 3;
GO

-- Pattern 11: Derived table with UNION
SELECT *
FROM (
    SELECT CustomerID, 'Customer' AS EntityType FROM dbo.Customers
    UNION ALL
    SELECT SupplierID, 'Supplier' FROM dbo.Suppliers
    UNION ALL
    SELECT EmployeeID, 'Employee' FROM dbo.Employees
) AS AllEntities
ORDER BY EntityType, CustomerID;
GO

-- Pattern 12: Inline table-valued constructor in FROM
SELECT v.Number, v.Name
FROM (VALUES 
    (1, 'One'), (2, 'Two'), (3, 'Three'),
    (4, 'Four'), (5, 'Five'), (6, 'Six'),
    (7, 'Seven'), (8, 'Eight'), (9, 'Nine'), (10, 'Ten')
) AS v(Number, Name)
WHERE v.Number % 2 = 0;
GO

-- Pattern 13: VALUES for lookup/mapping
SELECT 
    o.OrderID,
    o.Status,
    s.StatusDescription
FROM dbo.Orders o
INNER JOIN (VALUES
    ('P', 'Pending'),
    ('A', 'Approved'),
    ('S', 'Shipped'),
    ('D', 'Delivered'),
    ('C', 'Cancelled')
) AS s(StatusCode, StatusDescription) ON o.Status = s.StatusCode;
GO

-- Pattern 14: Derived table for row generation
SELECT TOP 100 
    ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS RowNum
FROM (VALUES(0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS a(n)
CROSS JOIN (VALUES(0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS b(n);
GO

-- Pattern 15: Derived table for date range
SELECT dates.d AS Date
FROM (
    SELECT DATEADD(DAY, n, '2024-01-01') AS d
    FROM (
        SELECT TOP 365 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
        FROM sys.objects a CROSS JOIN sys.objects b
    ) AS nums
) AS dates;
GO

-- Pattern 16: Derived table with expressions
SELECT *
FROM (
    SELECT 
        ProductID,
        ProductName,
        Price,
        StockQuantity,
        Price * StockQuantity AS TotalValue,
        CASE WHEN StockQuantity > 100 THEN 'High' ELSE 'Low' END AS StockLevel
    FROM dbo.Products
) AS ProductStats
WHERE TotalValue > 1000;
GO

-- Pattern 17: Multiple derived tables in JOIN
SELECT a.CustomerID, a.OrderCount, b.ProductCount
FROM (
    SELECT CustomerID, COUNT(*) AS OrderCount
    FROM dbo.Orders
    GROUP BY CustomerID
) AS a
INNER JOIN (
    SELECT o.CustomerID, COUNT(DISTINCT od.ProductID) AS ProductCount
    FROM dbo.Orders o
    INNER JOIN dbo.OrderDetails od ON o.OrderID = od.OrderID
    GROUP BY o.CustomerID
) AS b ON a.CustomerID = b.CustomerID;
GO

-- Pattern 18: Derived table with TOP
SELECT *
FROM (
    SELECT TOP 10 *
    FROM dbo.Orders
    ORDER BY TotalAmount DESC
) AS TopOrders
ORDER BY OrderDate;
GO

-- Pattern 19: Derived table with DISTINCT
SELECT *
FROM (
    SELECT DISTINCT CategoryID, SupplierID
    FROM dbo.Products
) AS UniqueCategoriesToSuppliers
ORDER BY CategoryID;
GO

-- Pattern 20: CROSS APPLY with VALUES (UNPIVOT alternative)
SELECT p.ProductID, p.ProductName, attrib.AttributeName, attrib.AttributeValue
FROM dbo.Products p
CROSS APPLY (VALUES
    ('Color', p.Color),
    ('Size', p.Size),
    ('Weight', CAST(p.Weight AS VARCHAR(50))),
    ('Material', p.Material)
) AS attrib(AttributeName, AttributeValue)
WHERE attrib.AttributeValue IS NOT NULL;
GO

-- Pattern 21: Derived table for pivoting
SELECT *
FROM (
    SELECT 
        CustomerID,
        YEAR(OrderDate) AS OrderYear,
        TotalAmount
    FROM dbo.Orders
) AS src
PIVOT (
    SUM(TotalAmount)
    FOR OrderYear IN ([2022], [2023], [2024])
) AS pvt;
GO

-- Pattern 22: Inline tally table
SELECT n
FROM (
    SELECT ones.n + tens.n * 10 AS n
    FROM (VALUES(0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS ones(n)
    CROSS JOIN (VALUES(0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS tens(n)
) AS tally
WHERE n BETWEEN 1 AND 50;
GO
