-- Sample 107: Static Join Patterns
-- Category: Static SQL Equivalents / Missing Syntax
-- Complexity: Complex
-- Purpose: Parser testing - all join types including RIGHT JOIN
-- Features: INNER, LEFT, RIGHT, FULL, CROSS, self-joins, multiple joins

-- Pattern 1: RIGHT JOIN (missing from original corpus)
SELECT 
    o.OrderID,
    o.OrderDate,
    o.TotalAmount,
    c.CustomerID,
    c.CustomerName,
    c.Email
FROM dbo.Orders o
RIGHT JOIN dbo.Customers c ON o.CustomerID = c.CustomerID
WHERE c.CreatedDate >= '2024-01-01'
ORDER BY c.CustomerName, o.OrderDate;
GO

-- Pattern 2: RIGHT OUTER JOIN with NULL check (customers without orders)
SELECT 
    c.CustomerID,
    c.CustomerName,
    c.Email,
    c.SignupDate,
    COUNT(o.OrderID) AS OrderCount,
    COALESCE(SUM(o.TotalAmount), 0) AS TotalSpent
FROM dbo.Orders o
RIGHT OUTER JOIN dbo.Customers c ON o.CustomerID = c.CustomerID
GROUP BY c.CustomerID, c.CustomerName, c.Email, c.SignupDate
HAVING COUNT(o.OrderID) = 0  -- Customers with no orders
ORDER BY c.SignupDate DESC;
GO

-- Pattern 3: FULL OUTER JOIN for data comparison
SELECT 
    COALESCE(s.ProductID, t.ProductID) AS ProductID,
    s.ProductName AS SourceName,
    t.ProductName AS TargetName,
    s.Price AS SourcePrice,
    t.Price AS TargetPrice,
    CASE 
        WHEN s.ProductID IS NULL THEN 'Missing in Source'
        WHEN t.ProductID IS NULL THEN 'Missing in Target'
        WHEN s.ProductName <> t.ProductName OR s.Price <> t.Price THEN 'Different'
        ELSE 'Match'
    END AS ComparisonResult
FROM dbo.Products_Source s
FULL OUTER JOIN dbo.Products_Target t ON s.ProductID = t.ProductID
ORDER BY COALESCE(s.ProductID, t.ProductID);
GO

-- Pattern 4: CROSS JOIN for combinations
SELECT 
    c.ColorName,
    s.SizeName,
    c.ColorCode + '-' + s.SizeCode AS SKUSuffix,
    CASE 
        WHEN c.ColorName IN ('Red', 'Blue') AND s.SizeName IN ('S', 'M', 'L') THEN 'High Stock'
        ELSE 'Standard Stock'
    END AS StockLevel
FROM dbo.Colors c
CROSS JOIN dbo.Sizes s
ORDER BY c.ColorName, s.SortOrder;
GO

-- Pattern 5: Self-join for hierarchy
SELECT 
    e.EmployeeID,
    e.EmployeeName AS Employee,
    e.JobTitle,
    m.EmployeeName AS Manager,
    m.JobTitle AS ManagerTitle,
    COALESCE(m2.EmployeeName, 'CEO') AS ManagersManager
FROM dbo.Employees e
LEFT JOIN dbo.Employees m ON e.ManagerID = m.EmployeeID
LEFT JOIN dbo.Employees m2 ON m.ManagerID = m2.EmployeeID
ORDER BY m2.EmployeeName, m.EmployeeName, e.EmployeeName;
GO

-- Pattern 6: Multiple table join chain
SELECT 
    o.OrderID,
    o.OrderDate,
    c.CustomerName,
    c.Email,
    p.ProductName,
    p.UnitPrice,
    od.Quantity,
    od.Quantity * p.UnitPrice AS LineTotal,
    cat.CategoryName,
    s.SupplierName,
    sh.ShipperName,
    a.City AS ShipCity,
    a.Country AS ShipCountry
FROM dbo.Orders o
INNER JOIN dbo.Customers c ON o.CustomerID = c.CustomerID
INNER JOIN dbo.OrderDetails od ON o.OrderID = od.OrderID
INNER JOIN dbo.Products p ON od.ProductID = p.ProductID
INNER JOIN dbo.Categories cat ON p.CategoryID = cat.CategoryID
INNER JOIN dbo.Suppliers s ON p.SupplierID = s.SupplierID
LEFT JOIN dbo.Shippers sh ON o.ShipperID = sh.ShipperID
LEFT JOIN dbo.Addresses a ON o.ShipAddressID = a.AddressID
WHERE o.OrderDate >= '2024-01-01'
ORDER BY o.OrderDate DESC, o.OrderID, od.LineNumber;
GO

-- Pattern 7: Join with derived table
SELECT 
    c.CustomerID,
    c.CustomerName,
    c.CustomerType,
    stats.OrderCount,
    stats.TotalRevenue,
    stats.AvgOrderValue,
    stats.LastOrderDate,
    CASE 
        WHEN stats.LastOrderDate < DATEADD(MONTH, -6, GETDATE()) THEN 'Inactive'
        WHEN stats.OrderCount >= 10 THEN 'Loyal'
        WHEN stats.TotalRevenue >= 5000 THEN 'High Value'
        ELSE 'Regular'
    END AS CustomerSegment
FROM dbo.Customers c
INNER JOIN (
    SELECT 
        CustomerID,
        COUNT(*) AS OrderCount,
        SUM(TotalAmount) AS TotalRevenue,
        AVG(TotalAmount) AS AvgOrderValue,
        MAX(OrderDate) AS LastOrderDate
    FROM dbo.Orders
    WHERE Status = 'Completed'
    GROUP BY CustomerID
) AS stats ON c.CustomerID = stats.CustomerID
ORDER BY stats.TotalRevenue DESC;
GO

-- Pattern 8: Join with CTE
;WITH MonthlySales AS (
    SELECT 
        ProductID,
        YEAR(SaleDate) AS SaleYear,
        MONTH(SaleDate) AS SaleMonth,
        SUM(Quantity) AS TotalQuantity,
        SUM(Amount) AS TotalAmount
    FROM dbo.Sales
    GROUP BY ProductID, YEAR(SaleDate), MONTH(SaleDate)
),
TopProducts AS (
    SELECT 
        ProductID,
        SUM(TotalAmount) AS YearlyTotal,
        ROW_NUMBER() OVER (ORDER BY SUM(TotalAmount) DESC) AS Rank
    FROM MonthlySales
    WHERE SaleYear = 2024
    GROUP BY ProductID
)
SELECT 
    p.ProductID,
    p.ProductName,
    c.CategoryName,
    tp.YearlyTotal,
    tp.Rank,
    ms.SaleMonth,
    ms.TotalQuantity,
    ms.TotalAmount
FROM TopProducts tp
INNER JOIN dbo.Products p ON tp.ProductID = p.ProductID
INNER JOIN dbo.Categories c ON p.CategoryID = c.CategoryID
LEFT JOIN MonthlySales ms ON tp.ProductID = ms.ProductID AND ms.SaleYear = 2024
WHERE tp.Rank <= 20
ORDER BY tp.Rank, ms.SaleMonth;
GO

-- Pattern 9: Join with APPLY operators
SELECT 
    d.DepartmentID,
    d.DepartmentName,
    topEmp.EmployeeID,
    topEmp.EmployeeName,
    topEmp.Salary,
    topEmp.Rank,
    latestHire.EmployeeName AS LatestHire,
    latestHire.HireDate
FROM dbo.Departments d
CROSS APPLY (
    SELECT TOP 3
        EmployeeID,
        EmployeeName,
        Salary,
        ROW_NUMBER() OVER (ORDER BY Salary DESC) AS Rank
    FROM dbo.Employees e
    WHERE e.DepartmentID = d.DepartmentID
    AND e.Status = 'Active'
    ORDER BY Salary DESC
) AS topEmp
OUTER APPLY (
    SELECT TOP 1
        EmployeeName,
        HireDate
    FROM dbo.Employees e
    WHERE e.DepartmentID = d.DepartmentID
    ORDER BY HireDate DESC
) AS latestHire
ORDER BY d.DepartmentName, topEmp.Rank;
GO

-- Pattern 10: Complex multi-way join with all join types
SELECT 
    c.CustomerID,
    c.CustomerName,
    o.OrderID,
    p.ProductName,
    r.ReviewRating,
    ret.ReturnReason,
    promo.PromoCode
FROM dbo.Customers c
LEFT JOIN dbo.Orders o ON c.CustomerID = o.CustomerID
LEFT JOIN dbo.OrderDetails od ON o.OrderID = od.OrderID
LEFT JOIN dbo.Products p ON od.ProductID = p.ProductID
LEFT JOIN dbo.Reviews r ON c.CustomerID = r.CustomerID AND p.ProductID = r.ProductID
LEFT JOIN dbo.Returns ret ON od.OrderID = ret.OrderID AND od.ProductID = ret.ProductID
LEFT JOIN dbo.OrderPromotions op ON o.OrderID = op.OrderID
LEFT JOIN dbo.Promotions promo ON op.PromoID = promo.PromoID
WHERE c.IsActive = 1
AND (o.OrderDate >= '2024-01-01' OR o.OrderID IS NULL)
ORDER BY c.CustomerID, o.OrderID, od.LineNumber;
GO

-- Pattern 11: Anti-join patterns using LEFT JOIN with NULL check
SELECT 
    p.ProductID,
    p.ProductName,
    p.CategoryID,
    p.Price
FROM dbo.Products p
LEFT JOIN dbo.OrderDetails od ON p.ProductID = od.ProductID
WHERE od.ProductID IS NULL  -- Products never ordered
ORDER BY p.ProductName;
GO

-- Pattern 12: Semi-join alternative using INNER JOIN with DISTINCT
SELECT DISTINCT
    c.CustomerID,
    c.CustomerName,
    c.Email
FROM dbo.Customers c
INNER JOIN dbo.Orders o ON c.CustomerID = o.CustomerID
INNER JOIN dbo.OrderDetails od ON o.OrderID = od.OrderID
INNER JOIN dbo.Products p ON od.ProductID = p.ProductID
WHERE p.CategoryID = 5  -- Customers who bought from category 5
ORDER BY c.CustomerName;
GO
