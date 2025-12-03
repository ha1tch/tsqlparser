-- Sample 170: Subquery Patterns
-- Category: Syntax Coverage / Query Patterns
-- Complexity: Complex
-- Purpose: Parser testing - subquery syntax variations
-- Features: Scalar, table, correlated subqueries, subquery locations

-- Pattern 1: Scalar subquery in SELECT
SELECT 
    CustomerID,
    CustomerName,
    (SELECT COUNT(*) FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID) AS OrderCount,
    (SELECT MAX(OrderDate) FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID) AS LastOrderDate
FROM dbo.Customers c;
GO

-- Pattern 2: Scalar subquery in WHERE
SELECT CustomerID, CustomerName
FROM dbo.Customers
WHERE CustomerID = (SELECT MAX(CustomerID) FROM dbo.Customers);

SELECT ProductID, ProductName, Price
FROM dbo.Products
WHERE Price > (SELECT AVG(Price) FROM dbo.Products);
GO

-- Pattern 3: Scalar subquery with correlation
SELECT 
    p.ProductID,
    p.ProductName,
    p.Price,
    (SELECT AVG(Price) FROM dbo.Products p2 WHERE p2.CategoryID = p.CategoryID) AS CategoryAvgPrice
FROM dbo.Products p
WHERE p.Price > (SELECT AVG(Price) FROM dbo.Products p2 WHERE p2.CategoryID = p.CategoryID);
GO

-- Pattern 4: Table subquery (derived table) in FROM
SELECT 
    dt.CustomerID,
    dt.TotalOrders,
    dt.TotalSpent
FROM (
    SELECT 
        CustomerID,
        COUNT(*) AS TotalOrders,
        SUM(TotalAmount) AS TotalSpent
    FROM dbo.Orders
    GROUP BY CustomerID
) AS dt
WHERE dt.TotalOrders > 5;
GO

-- Pattern 5: Multiple derived tables with JOIN
SELECT 
    c.CustomerName,
    orders.TotalOrders,
    spending.TotalSpent
FROM dbo.Customers c
INNER JOIN (
    SELECT CustomerID, COUNT(*) AS TotalOrders
    FROM dbo.Orders
    GROUP BY CustomerID
) AS orders ON c.CustomerID = orders.CustomerID
INNER JOIN (
    SELECT CustomerID, SUM(TotalAmount) AS TotalSpent
    FROM dbo.Orders
    GROUP BY CustomerID
) AS spending ON c.CustomerID = spending.CustomerID;
GO

-- Pattern 6: Subquery in WHERE with IN
SELECT CustomerID, CustomerName
FROM dbo.Customers
WHERE CustomerID IN (
    SELECT DISTINCT CustomerID 
    FROM dbo.Orders 
    WHERE OrderDate >= '2024-01-01'
);

SELECT ProductID, ProductName
FROM dbo.Products
WHERE ProductID NOT IN (
    SELECT ProductID 
    FROM dbo.OrderDetails
);
GO

-- Pattern 7: Subquery with EXISTS
SELECT c.CustomerID, c.CustomerName
FROM dbo.Customers c
WHERE EXISTS (
    SELECT 1 
    FROM dbo.Orders o 
    WHERE o.CustomerID = c.CustomerID 
      AND o.TotalAmount > 1000
);

SELECT p.ProductID, p.ProductName
FROM dbo.Products p
WHERE NOT EXISTS (
    SELECT 1 
    FROM dbo.OrderDetails od 
    WHERE od.ProductID = p.ProductID
);
GO

-- Pattern 8: Correlated subquery in SELECT list
SELECT 
    c.CategoryID,
    c.CategoryName,
    (SELECT TOP 1 ProductName 
     FROM dbo.Products p 
     WHERE p.CategoryID = c.CategoryID 
     ORDER BY Price DESC) AS MostExpensiveProduct,
    (SELECT TOP 1 Price 
     FROM dbo.Products p 
     WHERE p.CategoryID = c.CategoryID 
     ORDER BY Price DESC) AS HighestPrice
FROM dbo.Categories c;
GO

-- Pattern 9: Correlated subquery with TOP
SELECT 
    o.OrderID,
    o.CustomerID,
    o.TotalAmount
FROM dbo.Orders o
WHERE o.OrderID IN (
    SELECT TOP 3 OrderID
    FROM dbo.Orders o2
    WHERE o2.CustomerID = o.CustomerID
    ORDER BY TotalAmount DESC
);
GO

-- Pattern 10: Subquery with ALL
SELECT ProductID, ProductName, Price
FROM dbo.Products
WHERE Price > ALL (
    SELECT Price 
    FROM dbo.Products 
    WHERE CategoryID = 1
);
GO

-- Pattern 11: Subquery with ANY/SOME
SELECT ProductID, ProductName, Price
FROM dbo.Products
WHERE Price > ANY (
    SELECT Price 
    FROM dbo.Products 
    WHERE CategoryID = 1
);

SELECT ProductID, ProductName, Price
FROM dbo.Products
WHERE Price = SOME (
    SELECT Price 
    FROM dbo.Products 
    WHERE CategoryID = 2
);
GO

-- Pattern 12: Nested subqueries
SELECT CustomerID, CustomerName
FROM dbo.Customers
WHERE CustomerID IN (
    SELECT CustomerID
    FROM dbo.Orders
    WHERE ProductID IN (
        SELECT ProductID
        FROM dbo.Products
        WHERE CategoryID IN (
            SELECT CategoryID
            FROM dbo.Categories
            WHERE CategoryName LIKE '%Electronics%'
        )
    )
);
GO

-- Pattern 13: Subquery in HAVING
SELECT 
    CategoryID,
    AVG(Price) AS AvgPrice
FROM dbo.Products
GROUP BY CategoryID
HAVING AVG(Price) > (SELECT AVG(Price) FROM dbo.Products);
GO

-- Pattern 14: Subquery in CASE
SELECT 
    ProductID,
    ProductName,
    Price,
    CASE 
        WHEN Price > (SELECT AVG(Price) FROM dbo.Products) THEN 'Above Average'
        WHEN Price = (SELECT AVG(Price) FROM dbo.Products) THEN 'Average'
        ELSE 'Below Average'
    END AS PriceCategory
FROM dbo.Products;
GO

-- Pattern 15: Subquery in UPDATE
UPDATE dbo.Products
SET Price = Price * 1.1
WHERE CategoryID = (
    SELECT CategoryID 
    FROM dbo.Categories 
    WHERE CategoryName = 'Electronics'
);

UPDATE dbo.Customers
SET TotalOrders = (
    SELECT COUNT(*) 
    FROM dbo.Orders o 
    WHERE o.CustomerID = dbo.Customers.CustomerID
);
GO

-- Pattern 16: Subquery in DELETE
DELETE FROM dbo.Products
WHERE ProductID IN (
    SELECT ProductID
    FROM dbo.DiscontinuedProducts
);

DELETE FROM dbo.Customers
WHERE CustomerID NOT IN (
    SELECT DISTINCT CustomerID FROM dbo.Orders
);
GO

-- Pattern 17: Subquery in INSERT
INSERT INTO dbo.HighValueCustomers (CustomerID, CustomerName, TotalSpent)
SELECT 
    c.CustomerID,
    c.CustomerName,
    (SELECT SUM(TotalAmount) FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID)
FROM dbo.Customers c
WHERE (SELECT SUM(TotalAmount) FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID) > 10000;
GO

-- Pattern 18: Subquery as table expression in MERGE
MERGE INTO dbo.CustomerSummary AS target
USING (
    SELECT 
        CustomerID,
        COUNT(*) AS OrderCount,
        SUM(TotalAmount) AS TotalSpent
    FROM dbo.Orders
    GROUP BY CustomerID
) AS source
ON target.CustomerID = source.CustomerID
WHEN MATCHED THEN
    UPDATE SET OrderCount = source.OrderCount, TotalSpent = source.TotalSpent
WHEN NOT MATCHED THEN
    INSERT (CustomerID, OrderCount, TotalSpent)
    VALUES (source.CustomerID, source.OrderCount, source.TotalSpent);
GO

-- Pattern 19: Subquery in JOIN condition
SELECT c.CustomerName, o.OrderID
FROM dbo.Customers c
INNER JOIN dbo.Orders o ON c.CustomerID = o.CustomerID
    AND o.OrderDate = (
        SELECT MAX(o2.OrderDate) 
        FROM dbo.Orders o2 
        WHERE o2.CustomerID = c.CustomerID
    );
GO

-- Pattern 20: Subquery with UNION in derived table
SELECT CustomerType, CustomerCount
FROM (
    SELECT 'Active' AS CustomerType, COUNT(*) AS CustomerCount
    FROM dbo.Customers WHERE IsActive = 1
    UNION ALL
    SELECT 'Inactive', COUNT(*)
    FROM dbo.Customers WHERE IsActive = 0
) AS CustomerStats;
GO

-- Pattern 21: Lateral subquery with APPLY
SELECT 
    c.CustomerID,
    c.CustomerName,
    recent.OrderID,
    recent.OrderDate
FROM dbo.Customers c
CROSS APPLY (
    SELECT TOP 3 OrderID, OrderDate
    FROM dbo.Orders o
    WHERE o.CustomerID = c.CustomerID
    ORDER BY OrderDate DESC
) AS recent;
GO

-- Pattern 22: Subquery returning multiple columns (table subquery)
-- Note: T-SQL doesn't support row constructors in IN like (col1, col2) IN (subquery)
-- Use EXISTS or JOIN as an alternative:
SELECT *
FROM dbo.Customers c
WHERE EXISTS (
    SELECT 1
    FROM (
        SELECT CustomerID, MIN(CreatedDate) AS MinDate
        FROM dbo.Customers
        GROUP BY CustomerID
    ) AS sub
    WHERE sub.CustomerID = c.CustomerID AND sub.MinDate = c.CreatedDate
);
GO

-- Pattern 23: Scalar subquery with aggregate
SELECT 
    ProductID,
    ProductName,
    Price,
    Price - (SELECT AVG(Price) FROM dbo.Products) AS DiffFromAvg,
    Price * 100.0 / (SELECT SUM(Price) FROM dbo.Products) AS PctOfTotal
FROM dbo.Products;
GO
