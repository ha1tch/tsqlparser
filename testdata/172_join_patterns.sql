-- Sample 172: JOIN Syntax Variations
-- Category: Syntax Coverage / Query Patterns
-- Complexity: Complex
-- Purpose: Parser testing - all JOIN syntax variations
-- Features: INNER, OUTER, CROSS, self-joins, multi-table joins

-- Pattern 1: Basic INNER JOIN
SELECT c.CustomerID, c.CustomerName, o.OrderID, o.OrderDate
FROM dbo.Customers c
INNER JOIN dbo.Orders o ON c.CustomerID = o.CustomerID;
GO

-- Pattern 2: JOIN without INNER keyword (same as INNER JOIN)
SELECT c.CustomerID, c.CustomerName, o.OrderID
FROM dbo.Customers c
JOIN dbo.Orders o ON c.CustomerID = o.CustomerID;
GO

-- Pattern 3: LEFT OUTER JOIN
SELECT c.CustomerID, c.CustomerName, o.OrderID
FROM dbo.Customers c
LEFT OUTER JOIN dbo.Orders o ON c.CustomerID = o.CustomerID;
GO

-- Pattern 4: LEFT JOIN (without OUTER keyword)
SELECT c.CustomerID, c.CustomerName, o.OrderID
FROM dbo.Customers c
LEFT JOIN dbo.Orders o ON c.CustomerID = o.CustomerID;
GO

-- Pattern 5: RIGHT OUTER JOIN
SELECT c.CustomerID, c.CustomerName, o.OrderID
FROM dbo.Customers c
RIGHT OUTER JOIN dbo.Orders o ON c.CustomerID = o.CustomerID;
GO

-- Pattern 6: RIGHT JOIN (without OUTER keyword)
SELECT o.OrderID, c.CustomerName
FROM dbo.Orders o
RIGHT JOIN dbo.Customers c ON o.CustomerID = c.CustomerID;
GO

-- Pattern 7: FULL OUTER JOIN
SELECT c.CustomerID, c.CustomerName, o.OrderID
FROM dbo.Customers c
FULL OUTER JOIN dbo.Orders o ON c.CustomerID = o.CustomerID;
GO

-- Pattern 8: FULL JOIN (without OUTER keyword)
SELECT c.CustomerID, o.OrderID
FROM dbo.Customers c
FULL JOIN dbo.Orders o ON c.CustomerID = o.CustomerID;
GO

-- Pattern 9: CROSS JOIN
SELECT c.CustomerName, p.ProductName
FROM dbo.Customers c
CROSS JOIN dbo.Products p;
GO

-- Pattern 10: CROSS JOIN alternative syntax (comma)
SELECT c.CustomerName, p.ProductName
FROM dbo.Customers c, dbo.Products p;
GO

-- Pattern 11: Self-join
SELECT 
    e.EmployeeID,
    e.EmployeeName,
    m.EmployeeName AS ManagerName
FROM dbo.Employees e
LEFT JOIN dbo.Employees m ON e.ManagerID = m.EmployeeID;
GO

-- Pattern 12: Multiple JOIN conditions
SELECT o.OrderID, c.CustomerName
FROM dbo.Orders o
INNER JOIN dbo.Customers c 
    ON o.CustomerID = c.CustomerID 
    AND o.RegionID = c.RegionID;
GO

-- Pattern 13: JOIN with OR condition
SELECT o.OrderID, c.CustomerName
FROM dbo.Orders o
INNER JOIN dbo.Customers c 
    ON o.CustomerID = c.CustomerID 
    OR o.AlternateCustomerID = c.CustomerID;
GO

-- Pattern 14: JOIN with inequality
SELECT p1.ProductName AS Product1, p2.ProductName AS Product2
FROM dbo.Products p1
INNER JOIN dbo.Products p2 
    ON p1.CategoryID = p2.CategoryID 
    AND p1.ProductID < p2.ProductID;
GO

-- Pattern 15: JOIN with BETWEEN
SELECT o.OrderID, d.DateValue
FROM dbo.Orders o
INNER JOIN dbo.DateDimension d 
    ON d.DateValue BETWEEN o.StartDate AND o.EndDate;
GO

-- Pattern 16: Three-table JOIN
SELECT 
    c.CustomerName,
    o.OrderID,
    p.ProductName
FROM dbo.Customers c
INNER JOIN dbo.Orders o ON c.CustomerID = o.CustomerID
INNER JOIN dbo.OrderDetails od ON o.OrderID = od.OrderID
INNER JOIN dbo.Products p ON od.ProductID = p.ProductID;
GO

-- Pattern 17: Mixed JOIN types
SELECT 
    c.CustomerName,
    o.OrderID,
    od.Quantity,
    p.ProductName
FROM dbo.Customers c
LEFT JOIN dbo.Orders o ON c.CustomerID = o.CustomerID
LEFT JOIN dbo.OrderDetails od ON o.OrderID = od.OrderID
INNER JOIN dbo.Products p ON od.ProductID = p.ProductID;
GO

-- Pattern 18: Parenthesized JOINs (controlling order)
SELECT c.CustomerName, o.OrderID, s.ShipperName
FROM dbo.Customers c
INNER JOIN (
    dbo.Orders o
    INNER JOIN dbo.Shippers s ON o.ShipperID = s.ShipperID
) ON c.CustomerID = o.CustomerID;
GO

-- Pattern 19: JOIN with derived table
SELECT c.CustomerName, os.TotalOrders, os.TotalSpent
FROM dbo.Customers c
INNER JOIN (
    SELECT CustomerID, COUNT(*) AS TotalOrders, SUM(TotalAmount) AS TotalSpent
    FROM dbo.Orders
    GROUP BY CustomerID
) AS os ON c.CustomerID = os.CustomerID;
GO

-- Pattern 20: JOIN with CTE
WITH RecentOrders AS (
    SELECT CustomerID, OrderID, OrderDate
    FROM dbo.Orders
    WHERE OrderDate >= DATEADD(MONTH, -1, GETDATE())
)
SELECT c.CustomerName, ro.OrderID, ro.OrderDate
FROM dbo.Customers c
INNER JOIN RecentOrders ro ON c.CustomerID = ro.CustomerID;
GO

-- Pattern 21: CROSS APPLY
SELECT c.CustomerID, c.CustomerName, recent.OrderID, recent.OrderDate
FROM dbo.Customers c
CROSS APPLY (
    SELECT TOP 3 OrderID, OrderDate
    FROM dbo.Orders o
    WHERE o.CustomerID = c.CustomerID
    ORDER BY OrderDate DESC
) AS recent;
GO

-- Pattern 22: OUTER APPLY
SELECT c.CustomerID, c.CustomerName, recent.OrderID
FROM dbo.Customers c
OUTER APPLY (
    SELECT TOP 1 OrderID
    FROM dbo.Orders o
    WHERE o.CustomerID = c.CustomerID
    ORDER BY OrderDate DESC
) AS recent;
GO

-- Pattern 23: JOIN with table-valued function
SELECT c.CustomerID, c.CustomerName, orders.OrderID
FROM dbo.Customers c
CROSS APPLY dbo.GetCustomerOrders(c.CustomerID) AS orders;
GO

-- Pattern 24: Natural key vs surrogate key JOIN
-- Composite key JOIN
SELECT od.*, p.ProductName
FROM dbo.OrderDetails od
INNER JOIN dbo.Products p 
    ON od.ProductID = p.ProductID 
    AND od.ProductVersion = p.Version;
GO

-- Pattern 25: JOIN with COALESCE for optional matching
SELECT 
    c.CustomerName,
    COALESCE(o.ShippingAddress, c.DefaultAddress) AS Address
FROM dbo.Customers c
LEFT JOIN dbo.Orders o ON c.CustomerID = o.CustomerID;
GO

-- Pattern 26: Anti-join pattern (LEFT JOIN + NULL check)
SELECT c.CustomerID, c.CustomerName
FROM dbo.Customers c
LEFT JOIN dbo.Orders o ON c.CustomerID = o.CustomerID
WHERE o.OrderID IS NULL;
GO

-- Pattern 27: Semi-join alternative (EXISTS is usually better)
SELECT DISTINCT c.CustomerID, c.CustomerName
FROM dbo.Customers c
INNER JOIN dbo.Orders o ON c.CustomerID = o.CustomerID;
-- Better: WHERE EXISTS (SELECT 1 FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID)
GO

-- Pattern 28: JOIN with hints
SELECT c.CustomerName, o.OrderID
FROM dbo.Customers c WITH (NOLOCK)
INNER JOIN dbo.Orders o WITH (NOLOCK) ON c.CustomerID = o.CustomerID;

SELECT c.CustomerName, o.OrderID
FROM dbo.Customers c
INNER HASH JOIN dbo.Orders o ON c.CustomerID = o.CustomerID;

SELECT c.CustomerName, o.OrderID
FROM dbo.Customers c
INNER MERGE JOIN dbo.Orders o ON c.CustomerID = o.CustomerID;

SELECT c.CustomerName, o.OrderID
FROM dbo.Customers c
INNER LOOP JOIN dbo.Orders o ON c.CustomerID = o.CustomerID;
GO

-- Pattern 29: JOIN to same table multiple times
SELECT 
    o.OrderID,
    creator.UserName AS CreatedBy,
    modifier.UserName AS ModifiedBy,
    approver.UserName AS ApprovedBy
FROM dbo.Orders o
LEFT JOIN dbo.Users creator ON o.CreatedByUserID = creator.UserID
LEFT JOIN dbo.Users modifier ON o.ModifiedByUserID = modifier.UserID
LEFT JOIN dbo.Users approver ON o.ApprovedByUserID = approver.UserID;
GO

-- Pattern 30: Complex multi-path JOIN
SELECT 
    c.CustomerName,
    ba.Address AS BillingAddress,
    sa.Address AS ShippingAddress,
    o.OrderID
FROM dbo.Customers c
INNER JOIN dbo.Orders o ON c.CustomerID = o.CustomerID
LEFT JOIN dbo.Addresses ba ON o.BillingAddressID = ba.AddressID
LEFT JOIN dbo.Addresses sa ON o.ShippingAddressID = sa.AddressID;
GO
