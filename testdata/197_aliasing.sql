-- Sample 197: Aliasing Patterns
-- Category: Syntax Coverage / Query Patterns
-- Complexity: Intermediate
-- Purpose: Parser testing - alias syntax variations
-- Features: Table aliases, column aliases, AS keyword

-- Pattern 1: Column alias with AS
SELECT 
    CustomerID AS ID,
    CustomerName AS Name,
    Email AS ContactEmail
FROM dbo.Customers;
GO

-- Pattern 2: Column alias without AS
SELECT 
    CustomerID ID,
    CustomerName Name,
    Email ContactEmail
FROM dbo.Customers;
GO

-- Pattern 3: Column alias with = (assignment style)
SELECT 
    ID = CustomerID,
    Name = CustomerName,
    ContactEmail = Email
FROM dbo.Customers;
GO

-- Pattern 4: Alias with spaces (requires brackets or quotes)
SELECT 
    CustomerID AS [Customer ID],
    CustomerName AS [Customer Name],
    Email AS "Contact Email"
FROM dbo.Customers;
GO

-- Pattern 5: Alias with special characters
SELECT 
    CustomerID AS [ID#],
    TotalAmount AS [Amount ($)],
    OrderDate AS [Order Date/Time]
FROM dbo.Orders;
GO

-- Pattern 6: Table alias with AS
SELECT c.CustomerID, c.CustomerName
FROM dbo.Customers AS c;
GO

-- Pattern 7: Table alias without AS
SELECT c.CustomerID, c.CustomerName
FROM dbo.Customers c;
GO

-- Pattern 8: Table alias in JOIN
SELECT 
    c.CustomerName,
    o.OrderID,
    o.OrderDate
FROM dbo.Customers AS c
INNER JOIN dbo.Orders AS o ON c.CustomerID = o.CustomerID;
GO

-- Pattern 9: Multiple table aliases
SELECT 
    c.CustomerName,
    o.OrderID,
    od.Quantity,
    p.ProductName
FROM dbo.Customers c
INNER JOIN dbo.Orders o ON c.CustomerID = o.CustomerID
INNER JOIN dbo.OrderDetails od ON o.OrderID = od.OrderID
INNER JOIN dbo.Products p ON od.ProductID = p.ProductID;
GO

-- Pattern 10: Self-join with aliases (required)
SELECT 
    e.EmployeeName AS Employee,
    m.EmployeeName AS Manager
FROM dbo.Employees e
LEFT JOIN dbo.Employees m ON e.ManagerID = m.EmployeeID;
GO

-- Pattern 11: Derived table alias (required)
SELECT dt.CategoryID, dt.ProductCount
FROM (
    SELECT CategoryID, COUNT(*) AS ProductCount
    FROM dbo.Products
    GROUP BY CategoryID
) AS dt;
GO

-- Pattern 12: Derived table alias without AS
SELECT dt.CategoryID, dt.ProductCount
FROM (
    SELECT CategoryID, COUNT(*) AS ProductCount
    FROM dbo.Products
    GROUP BY CategoryID
) dt;
GO

-- Pattern 13: CTE alias (defined in WITH)
WITH CustomerOrders (CustomerID, OrderCount, TotalSpent) AS (
    SELECT CustomerID, COUNT(*), SUM(TotalAmount)
    FROM dbo.Orders
    GROUP BY CustomerID
)
SELECT * FROM CustomerOrders;
GO

-- Pattern 14: Subquery alias
SELECT 
    c.CustomerName,
    (SELECT COUNT(*) FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID) AS OrderCount
FROM dbo.Customers c;
GO

-- Pattern 15: Expression alias
SELECT 
    ProductID,
    Quantity * UnitPrice AS LineTotal,
    Quantity * UnitPrice * 0.08 AS TaxAmount,
    Quantity * UnitPrice * 1.08 AS TotalWithTax
FROM dbo.OrderDetails;
GO

-- Pattern 16: Aggregate alias
SELECT 
    CategoryID,
    COUNT(*) AS ProductCount,
    SUM(StockQuantity) AS TotalStock,
    AVG(Price) AS AveragePrice,
    MIN(Price) AS LowestPrice,
    MAX(Price) AS HighestPrice
FROM dbo.Products
GROUP BY CategoryID;
GO

-- Pattern 17: CASE expression alias
SELECT 
    ProductID,
    ProductName,
    CASE 
        WHEN Price < 10 THEN 'Budget'
        WHEN Price < 50 THEN 'Standard'
        ELSE 'Premium'
    END AS PriceCategory
FROM dbo.Products;
GO

-- Pattern 18: Function result alias
SELECT 
    GETDATE() AS CurrentDateTime,
    YEAR(GETDATE()) AS CurrentYear,
    NEWID() AS NewGuid,
    @@VERSION AS SQLVersion;
GO

-- Pattern 19: CROSS APPLY alias
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

-- Pattern 20: PIVOT column aliases
SELECT 
    CustomerID,
    [2022] AS Sales2022,
    [2023] AS Sales2023,
    [2024] AS Sales2024
FROM (
    SELECT CustomerID, YEAR(OrderDate) AS Year, TotalAmount
    FROM dbo.Orders
) src
PIVOT (
    SUM(TotalAmount) FOR Year IN ([2022], [2023], [2024])
) pvt;
GO

-- Pattern 21: OUTPUT clause aliases
DECLARE @Changes TABLE (Action VARCHAR(10), ID INT);

MERGE INTO dbo.Target t
USING dbo.Source s ON t.ID = s.ID
WHEN MATCHED THEN UPDATE SET t.Value = s.Value
WHEN NOT MATCHED THEN INSERT (ID, Value) VALUES (s.ID, s.Value)
OUTPUT $action AS ActionTaken, inserted.ID AS AffectedID
INTO @Changes;
GO

-- Pattern 22: Window function alias
SELECT 
    ProductID,
    ProductName,
    CategoryID,
    Price,
    ROW_NUMBER() OVER (PARTITION BY CategoryID ORDER BY Price DESC) AS CategoryRank,
    RANK() OVER (ORDER BY Price DESC) AS OverallRank
FROM dbo.Products;
GO

-- Pattern 23: Reserved word as alias (requires brackets)
SELECT 
    CustomerID AS [SELECT],
    CustomerName AS [FROM],
    Email AS [WHERE]
FROM dbo.Customers;
GO

-- Pattern 24: Numeric alias (requires brackets)
SELECT 
    CustomerID AS [1],
    CustomerName AS [2],
    Email AS [3]
FROM dbo.Customers;
GO

-- Pattern 25: Unicode alias
SELECT 
    CustomerID AS [客户ID],
    CustomerName AS [客户名称],
    Email AS [电子邮件]
FROM dbo.Customers;
GO
