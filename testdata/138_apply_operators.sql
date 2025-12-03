-- Sample 138: APPLY Operators - CROSS APPLY and OUTER APPLY
-- Category: Missing Syntax Elements / Advanced Patterns
-- Complexity: Advanced
-- Purpose: Parser testing - APPLY operator variations
-- Features: CROSS APPLY, OUTER APPLY, with TVFs, subqueries, expressions

-- Pattern 1: Basic CROSS APPLY with inline table expression
SELECT 
    c.CustomerID,
    c.CustomerName,
    o.OrderID,
    o.OrderDate,
    o.TotalAmount
FROM Customers c
CROSS APPLY (
    SELECT TOP 3 OrderID, OrderDate, TotalAmount
    FROM Orders
    WHERE CustomerID = c.CustomerID
    ORDER BY OrderDate DESC
) AS o;
GO

-- Pattern 2: OUTER APPLY (like LEFT JOIN - includes NULLs)
SELECT 
    c.CustomerID,
    c.CustomerName,
    o.OrderID,
    o.OrderDate,
    o.TotalAmount
FROM Customers c
OUTER APPLY (
    SELECT TOP 3 OrderID, OrderDate, TotalAmount
    FROM Orders
    WHERE CustomerID = c.CustomerID
    ORDER BY OrderDate DESC
) AS o;
GO

-- Pattern 3: APPLY with table-valued function
CREATE FUNCTION dbo.GetCustomerOrders(@CustomerID INT)
RETURNS TABLE
AS
RETURN (
    SELECT OrderID, OrderDate, TotalAmount, Status
    FROM Orders
    WHERE CustomerID = @CustomerID
);
GO

SELECT 
    c.CustomerID,
    c.CustomerName,
    co.OrderID,
    co.TotalAmount
FROM Customers c
CROSS APPLY dbo.GetCustomerOrders(c.CustomerID) AS co;

SELECT 
    c.CustomerID,
    c.CustomerName,
    co.OrderID,
    co.TotalAmount
FROM Customers c
OUTER APPLY dbo.GetCustomerOrders(c.CustomerID) AS co;
GO

-- Pattern 4: APPLY with aggregates
SELECT 
    c.CustomerID,
    c.CustomerName,
    stats.OrderCount,
    stats.TotalSpent,
    stats.AvgOrderValue,
    stats.LastOrderDate
FROM Customers c
CROSS APPLY (
    SELECT 
        COUNT(*) AS OrderCount,
        SUM(TotalAmount) AS TotalSpent,
        AVG(TotalAmount) AS AvgOrderValue,
        MAX(OrderDate) AS LastOrderDate
    FROM Orders
    WHERE CustomerID = c.CustomerID
) AS stats;
GO

-- Pattern 5: APPLY to unpivot columns
SELECT 
    p.ProductID,
    p.ProductName,
    prices.PriceType,
    prices.PriceValue
FROM Products p
CROSS APPLY (
    VALUES 
        ('List', p.ListPrice),
        ('Cost', p.CostPrice),
        ('Sale', p.SalePrice)
) AS prices(PriceType, PriceValue)
WHERE prices.PriceValue IS NOT NULL;
GO

-- Pattern 6: APPLY with STRING_SPLIT
SELECT 
    c.CustomerID,
    c.CustomerName,
    tag.value AS Tag
FROM Customers c
CROSS APPLY STRING_SPLIT(c.Tags, ',') AS tag;
GO

-- Pattern 7: APPLY with XML nodes
SELECT 
    o.OrderID,
    items.item.value('@ProductID', 'INT') AS ProductID,
    items.item.value('@Quantity', 'INT') AS Quantity,
    items.item.value('@Price', 'DECIMAL(10,2)') AS Price
FROM Orders o
CROSS APPLY o.OrderXML.nodes('/Order/Items/Item') AS items(item);
GO

-- Pattern 8: APPLY with JSON
SELECT 
    o.OrderID,
    j.ProductID,
    j.Quantity,
    j.Price
FROM Orders o
CROSS APPLY OPENJSON(o.OrderJSON, '$.items')
WITH (
    ProductID INT '$.productId',
    Quantity INT '$.quantity',
    Price DECIMAL(10,2) '$.price'
) AS j;
GO

-- Pattern 9: Multiple APPLY clauses
SELECT 
    c.CustomerID,
    c.CustomerName,
    lastOrder.OrderID AS LastOrderID,
    lastOrder.OrderDate AS LastOrderDate,
    topProduct.ProductName AS TopProduct,
    topProduct.TotalQuantity
FROM Customers c
CROSS APPLY (
    SELECT TOP 1 OrderID, OrderDate
    FROM Orders
    WHERE CustomerID = c.CustomerID
    ORDER BY OrderDate DESC
) AS lastOrder
OUTER APPLY (
    SELECT TOP 1 p.ProductName, SUM(od.Quantity) AS TotalQuantity
    FROM Orders o
    INNER JOIN OrderDetails od ON o.OrderID = od.OrderID
    INNER JOIN Products p ON od.ProductID = p.ProductID
    WHERE o.CustomerID = c.CustomerID
    GROUP BY p.ProductID, p.ProductName
    ORDER BY SUM(od.Quantity) DESC
) AS topProduct;
GO

-- Pattern 10: APPLY with ROW_NUMBER for pagination
SELECT 
    c.CustomerID,
    c.CustomerName,
    o.OrderID,
    o.OrderDate,
    o.RowNum
FROM Customers c
CROSS APPLY (
    SELECT 
        OrderID, 
        OrderDate, 
        ROW_NUMBER() OVER (ORDER BY OrderDate DESC) AS RowNum
    FROM Orders
    WHERE CustomerID = c.CustomerID
) AS o
WHERE o.RowNum <= 5;
GO

-- Pattern 11: APPLY for running totals
SELECT 
    o.OrderID,
    o.OrderDate,
    o.TotalAmount,
    rt.RunningTotal
FROM Orders o
CROSS APPLY (
    SELECT SUM(TotalAmount) AS RunningTotal
    FROM Orders o2
    WHERE o2.CustomerID = o.CustomerID
    AND o2.OrderDate <= o.OrderDate
) AS rt
ORDER BY o.CustomerID, o.OrderDate;
GO

-- Pattern 12: APPLY with recursive-like behavior
SELECT 
    e.EmployeeID,
    e.EmployeeName,
    mgr.ManagerName,
    mgr.ManagerLevel
FROM Employees e
OUTER APPLY (
    SELECT 
        m.EmployeeName AS ManagerName,
        1 AS ManagerLevel
    FROM Employees m
    WHERE m.EmployeeID = e.ManagerID
    UNION ALL
    SELECT 
        m2.EmployeeName,
        2 AS ManagerLevel
    FROM Employees m
    INNER JOIN Employees m2 ON m.ManagerID = m2.EmployeeID
    WHERE m.EmployeeID = e.ManagerID
) AS mgr;
GO

-- Pattern 13: APPLY with CASE expression
SELECT 
    p.ProductID,
    p.ProductName,
    p.Price,
    disc.DiscountType,
    disc.DiscountPercent,
    p.Price * (1 - disc.DiscountPercent / 100.0) AS FinalPrice
FROM Products p
CROSS APPLY (
    SELECT 
        CASE 
            WHEN p.Price >= 100 THEN 'Premium'
            WHEN p.Price >= 50 THEN 'Standard'
            ELSE 'Budget'
        END AS DiscountType,
        CASE 
            WHEN p.Price >= 100 THEN 15.0
            WHEN p.Price >= 50 THEN 10.0
            ELSE 5.0
        END AS DiscountPercent
) AS disc;
GO

-- Pattern 14: APPLY vs JOIN comparison
-- Using JOIN (less efficient for correlated operations)
SELECT c.CustomerID, c.CustomerName, o.MaxOrder
FROM Customers c
LEFT JOIN (
    SELECT CustomerID, MAX(TotalAmount) AS MaxOrder
    FROM Orders
    GROUP BY CustomerID
) AS o ON c.CustomerID = o.CustomerID;

-- Using APPLY (more efficient, can reference outer table)
SELECT c.CustomerID, c.CustomerName, o.MaxOrder
FROM Customers c
OUTER APPLY (
    SELECT MAX(TotalAmount) AS MaxOrder
    FROM Orders
    WHERE CustomerID = c.CustomerID
) AS o;
GO

-- Pattern 15: APPLY with dynamic TOP
DECLARE @TopN INT = 5;

SELECT 
    c.CustomerID,
    c.CustomerName,
    o.OrderID,
    o.TotalAmount
FROM Customers c
CROSS APPLY (
    SELECT TOP (@TopN) OrderID, TotalAmount
    FROM Orders
    WHERE CustomerID = c.CustomerID
    ORDER BY TotalAmount DESC
) AS o;
GO

-- Pattern 16: APPLY for split and process
SELECT 
    t.ID,
    t.DelimitedData,
    parts.ItemNumber,
    parts.ItemValue
FROM (
    SELECT 1 AS ID, 'A,B,C,D' AS DelimitedData
    UNION ALL
    SELECT 2, 'X,Y,Z'
) AS t
CROSS APPLY (
    SELECT 
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS ItemNumber,
        value AS ItemValue
    FROM STRING_SPLIT(t.DelimitedData, ',')
) AS parts;
GO

-- Pattern 17: APPLY with computed expressions
SELECT 
    o.OrderID,
    o.Subtotal,
    o.TaxRate,
    calc.TaxAmount,
    calc.Total,
    calc.TotalWithShipping
FROM Orders o
CROSS APPLY (
    SELECT 
        o.Subtotal * o.TaxRate / 100 AS TaxAmount,
        o.Subtotal * (1 + o.TaxRate / 100) AS Total,
        o.Subtotal * (1 + o.TaxRate / 100) + CASE WHEN o.Subtotal < 50 THEN 9.99 ELSE 0 END AS TotalWithShipping
) AS calc;
GO

-- Pattern 18: Nested APPLY
SELECT 
    c.CustomerID,
    c.CustomerName,
    orders.OrderID,
    items.ProductName,
    items.Quantity
FROM Customers c
CROSS APPLY (
    SELECT TOP 2 OrderID
    FROM Orders
    WHERE CustomerID = c.CustomerID
    ORDER BY OrderDate DESC
) AS orders
CROSS APPLY (
    SELECT p.ProductName, od.Quantity
    FROM OrderDetails od
    INNER JOIN Products p ON od.ProductID = p.ProductID
    WHERE od.OrderID = orders.OrderID
) AS items;
GO

-- Cleanup
DROP FUNCTION IF EXISTS dbo.GetCustomerOrders;
GO
