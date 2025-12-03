-- Sample 191: WHERE Clause Patterns
-- Category: Syntax Coverage / Query Patterns
-- Complexity: Complex
-- Purpose: Parser testing - WHERE clause syntax variations
-- Features: All comparison operators, logical operators, predicates

-- Pattern 1: Basic equality
SELECT * FROM dbo.Customers WHERE CustomerID = 1;
GO

-- Pattern 2: Inequality
SELECT * FROM dbo.Customers WHERE Status <> 'Inactive';
SELECT * FROM dbo.Customers WHERE Status != 'Inactive';
GO

-- Pattern 3: Comparison operators
SELECT * FROM dbo.Products WHERE Price > 100;
SELECT * FROM dbo.Products WHERE Price >= 100;
SELECT * FROM dbo.Products WHERE Price < 50;
SELECT * FROM dbo.Products WHERE Price <= 50;
SELECT * FROM dbo.Products WHERE Price !< 100;  -- NOT LESS THAN
SELECT * FROM dbo.Products WHERE Price !> 50;   -- NOT GREATER THAN
GO

-- Pattern 4: AND operator
SELECT * FROM dbo.Products
WHERE CategoryID = 1 AND Price > 50 AND StockQuantity > 0;
GO

-- Pattern 5: OR operator
SELECT * FROM dbo.Customers
WHERE Country = 'USA' OR Country = 'Canada' OR Country = 'UK';
GO

-- Pattern 6: AND and OR combined with parentheses
SELECT * FROM dbo.Products
WHERE (CategoryID = 1 OR CategoryID = 2) AND Price > 100;

SELECT * FROM dbo.Products
WHERE CategoryID = 1 OR (CategoryID = 2 AND Price > 100);
GO

-- Pattern 7: NOT operator
SELECT * FROM dbo.Customers WHERE NOT IsActive = 1;
SELECT * FROM dbo.Customers WHERE NOT (Country = 'USA' OR Country = 'Canada');
GO

-- Pattern 8: BETWEEN
SELECT * FROM dbo.Products WHERE Price BETWEEN 10 AND 100;
SELECT * FROM dbo.Orders WHERE OrderDate BETWEEN '2024-01-01' AND '2024-12-31';
SELECT * FROM dbo.Products WHERE Price NOT BETWEEN 10 AND 100;
GO

-- Pattern 9: IN
SELECT * FROM dbo.Customers WHERE Country IN ('USA', 'Canada', 'UK', 'Germany');
SELECT * FROM dbo.Products WHERE CategoryID IN (1, 2, 3);
SELECT * FROM dbo.Customers WHERE CustomerID NOT IN (1, 2, 3, 4, 5);
GO

-- Pattern 10: IN with subquery
SELECT * FROM dbo.Customers
WHERE CustomerID IN (SELECT DISTINCT CustomerID FROM dbo.Orders);

SELECT * FROM dbo.Products
WHERE ProductID NOT IN (SELECT ProductID FROM dbo.OrderDetails);
GO

-- Pattern 11: LIKE patterns
SELECT * FROM dbo.Customers WHERE CustomerName LIKE 'John%';
SELECT * FROM dbo.Customers WHERE CustomerName LIKE '%Smith';
SELECT * FROM dbo.Customers WHERE CustomerName LIKE '%son%';
SELECT * FROM dbo.Customers WHERE Email LIKE '%@gmail.com';
SELECT * FROM dbo.Customers WHERE Phone LIKE '555-____';
SELECT * FROM dbo.Products WHERE SKU LIKE '[A-Z][0-9][0-9][0-9]';
SELECT * FROM dbo.Products WHERE ProductName LIKE '[^0-9]%';
SELECT * FROM dbo.Products WHERE Description LIKE '%10[%]%' ESCAPE '[';
GO

-- Pattern 12: NOT LIKE
SELECT * FROM dbo.Customers WHERE Email NOT LIKE '%@test.com';
GO

-- Pattern 13: IS NULL and IS NOT NULL
SELECT * FROM dbo.Customers WHERE Phone IS NULL;
SELECT * FROM dbo.Customers WHERE Email IS NOT NULL;
SELECT * FROM dbo.Products WHERE DiscountPrice IS NULL AND IsActive = 1;
GO

-- Pattern 14: EXISTS
SELECT * FROM dbo.Customers c
WHERE EXISTS (SELECT 1 FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID);
GO

-- Pattern 15: NOT EXISTS
SELECT * FROM dbo.Customers c
WHERE NOT EXISTS (SELECT 1 FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID);
GO

-- Pattern 16: ALL, ANY, SOME
SELECT * FROM dbo.Products WHERE Price > ALL (SELECT Price FROM dbo.Products WHERE CategoryID = 1);
SELECT * FROM dbo.Products WHERE Price > ANY (SELECT Price FROM dbo.Products WHERE CategoryID = 1);
SELECT * FROM dbo.Products WHERE Price = SOME (SELECT Price FROM dbo.Products WHERE CategoryID = 2);
GO

-- Pattern 17: Scalar comparison with subquery
SELECT * FROM dbo.Products WHERE Price > (SELECT AVG(Price) FROM dbo.Products);
SELECT * FROM dbo.Orders WHERE TotalAmount = (SELECT MAX(TotalAmount) FROM dbo.Orders);
GO

-- Pattern 18: Multiple subqueries
SELECT * FROM dbo.Products
WHERE Price > (SELECT AVG(Price) FROM dbo.Products)
  AND StockQuantity < (SELECT AVG(StockQuantity) FROM dbo.Products);
GO

-- Pattern 19: Expressions in WHERE
SELECT * FROM dbo.Products WHERE Price * StockQuantity > 10000;
SELECT * FROM dbo.Orders WHERE DATEDIFF(DAY, OrderDate, ShippedDate) > 7;
SELECT * FROM dbo.Customers WHERE LEN(CustomerName) > 20;
GO

-- Pattern 20: Functions in WHERE
SELECT * FROM dbo.Orders WHERE YEAR(OrderDate) = 2024;
SELECT * FROM dbo.Customers WHERE UPPER(Country) = 'USA';
SELECT * FROM dbo.Products WHERE ABS(Price - 100) < 10;
GO

-- Pattern 21: CASE in WHERE
SELECT * FROM dbo.Products
WHERE CASE CategoryID 
    WHEN 1 THEN Price > 100 
    WHEN 2 THEN Price > 50 
    ELSE Price > 25 
END = 1;
GO

-- Pattern 22: Date comparisons
SELECT * FROM dbo.Orders WHERE OrderDate >= DATEADD(DAY, -30, GETDATE());
SELECT * FROM dbo.Orders WHERE OrderDate >= CAST(GETDATE() AS DATE);
SELECT * FROM dbo.Orders WHERE CAST(OrderDate AS DATE) = '2024-06-15';
GO

-- Pattern 23: String comparisons
SELECT * FROM dbo.Customers WHERE CustomerName > 'M';  -- Names starting after M
SELECT * FROM dbo.Customers WHERE CustomerName COLLATE Latin1_General_CS_AS = 'SMITH';
GO

-- Pattern 24: Binary comparison
SELECT * FROM dbo.Documents WHERE FileHash = 0x1234567890ABCDEF;
GO

-- Pattern 25: Complex nested conditions
SELECT * FROM dbo.Orders
WHERE (Status = 'Pending' AND TotalAmount > 1000)
   OR (Status = 'Shipped' AND ShippedDate < DATEADD(DAY, -7, GETDATE()))
   OR (Status IN ('Cancelled', 'Returned') AND CustomerID NOT IN (SELECT CustomerID FROM dbo.VIPCustomers));
GO
