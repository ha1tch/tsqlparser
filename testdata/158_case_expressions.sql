-- Sample 158: CASE Expression Variations and Patterns
-- Category: Syntax Coverage / Pure Logic
-- Complexity: Complex
-- Purpose: Parser testing - CASE expression syntax variations
-- Features: Simple CASE, searched CASE, nested CASE, CASE in different contexts

-- Pattern 1: Simple CASE expression
SELECT 
    ProductID,
    ProductName,
    CategoryID,
    CASE CategoryID
        WHEN 1 THEN 'Electronics'
        WHEN 2 THEN 'Clothing'
        WHEN 3 THEN 'Home & Garden'
        WHEN 4 THEN 'Sports'
        ELSE 'Other'
    END AS CategoryName
FROM dbo.Products;
GO

-- Pattern 2: Searched CASE expression
SELECT 
    ProductID,
    ProductName,
    Price,
    CASE 
        WHEN Price < 10 THEN 'Budget'
        WHEN Price < 50 THEN 'Standard'
        WHEN Price < 100 THEN 'Premium'
        WHEN Price >= 100 THEN 'Luxury'
        ELSE 'Unknown'
    END AS PriceCategory
FROM dbo.Products;
GO

-- Pattern 3: CASE with NULL handling
SELECT 
    CustomerID,
    Email,
    Phone,
    CASE 
        WHEN Email IS NOT NULL THEN Email
        WHEN Phone IS NOT NULL THEN Phone
        ELSE 'No Contact Info'
    END AS PrimaryContact
FROM dbo.Customers;
GO

-- Pattern 4: CASE with multiple conditions per WHEN
SELECT 
    OrderID,
    Status,
    OrderDate,
    CASE 
        WHEN Status = 'Shipped' AND OrderDate > DATEADD(DAY, -7, GETDATE()) THEN 'Recently Shipped'
        WHEN Status = 'Shipped' AND OrderDate <= DATEADD(DAY, -7, GETDATE()) THEN 'Shipped Earlier'
        WHEN Status IN ('Pending', 'Processing') THEN 'In Progress'
        WHEN Status = 'Cancelled' OR Status = 'Returned' THEN 'Terminated'
        ELSE 'Other'
    END AS StatusCategory
FROM dbo.Orders;
GO

-- Pattern 5: Nested CASE expressions
SELECT 
    EmployeeID,
    DepartmentID,
    Salary,
    CASE DepartmentID
        WHEN 1 THEN 
            CASE 
                WHEN Salary >= 100000 THEN 'Senior Engineer'
                WHEN Salary >= 70000 THEN 'Engineer'
                ELSE 'Junior Engineer'
            END
        WHEN 2 THEN
            CASE 
                WHEN Salary >= 80000 THEN 'Senior Sales'
                WHEN Salary >= 50000 THEN 'Sales Rep'
                ELSE 'Sales Trainee'
            END
        ELSE 'Other Department'
    END AS PositionLevel
FROM dbo.Employees;
GO

-- Pattern 6: CASE in ORDER BY
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

-- Pattern 7: CASE in ORDER BY with direction
SELECT ProductID, ProductName, SortOrder, IsActive
FROM dbo.Products
ORDER BY 
    IsActive DESC,
    CASE WHEN SortOrder IS NULL THEN 1 ELSE 0 END,  -- NULLs last
    SortOrder;
GO

-- Pattern 8: CASE in GROUP BY
SELECT 
    CASE 
        WHEN YEAR(OrderDate) = YEAR(GETDATE()) THEN 'Current Year'
        WHEN YEAR(OrderDate) = YEAR(GETDATE()) - 1 THEN 'Last Year'
        ELSE 'Older'
    END AS Period,
    COUNT(*) AS OrderCount,
    SUM(TotalAmount) AS TotalSales
FROM dbo.Orders
GROUP BY 
    CASE 
        WHEN YEAR(OrderDate) = YEAR(GETDATE()) THEN 'Current Year'
        WHEN YEAR(OrderDate) = YEAR(GETDATE()) - 1 THEN 'Last Year'
        ELSE 'Older'
    END;
GO

-- Pattern 9: CASE in aggregate functions
SELECT 
    CategoryID,
    COUNT(*) AS TotalProducts,
    SUM(CASE WHEN StockQuantity > 0 THEN 1 ELSE 0 END) AS InStockCount,
    SUM(CASE WHEN StockQuantity = 0 THEN 1 ELSE 0 END) AS OutOfStockCount,
    SUM(CASE WHEN Price >= 100 THEN 1 ELSE 0 END) AS PremiumCount,
    AVG(CASE WHEN StockQuantity > 0 THEN Price END) AS AvgPriceInStock
FROM dbo.Products
GROUP BY CategoryID;
GO

-- Pattern 10: CASE for pivot-like behavior
SELECT 
    CustomerID,
    SUM(CASE WHEN MONTH(OrderDate) = 1 THEN TotalAmount ELSE 0 END) AS Jan,
    SUM(CASE WHEN MONTH(OrderDate) = 2 THEN TotalAmount ELSE 0 END) AS Feb,
    SUM(CASE WHEN MONTH(OrderDate) = 3 THEN TotalAmount ELSE 0 END) AS Mar,
    SUM(CASE WHEN MONTH(OrderDate) = 4 THEN TotalAmount ELSE 0 END) AS Apr,
    SUM(CASE WHEN MONTH(OrderDate) = 5 THEN TotalAmount ELSE 0 END) AS May,
    SUM(CASE WHEN MONTH(OrderDate) = 6 THEN TotalAmount ELSE 0 END) AS Jun
FROM dbo.Orders
WHERE YEAR(OrderDate) = 2024
GROUP BY CustomerID;
GO

-- Pattern 11: CASE in UPDATE statement
UPDATE dbo.Products
SET Status = CASE 
    WHEN StockQuantity = 0 THEN 'Out of Stock'
    WHEN StockQuantity < ReorderLevel THEN 'Low Stock'
    WHEN StockQuantity < ReorderLevel * 2 THEN 'Normal'
    ELSE 'Well Stocked'
END;
GO

-- Pattern 12: CASE in WHERE clause
SELECT ProductID, ProductName, Price, CategoryID
FROM dbo.Products
WHERE CASE 
    WHEN CategoryID = 1 THEN Price > 50
    WHEN CategoryID = 2 THEN Price > 30
    WHEN CategoryID = 3 THEN Price > 20
    ELSE Price > 10
END = 1;  -- Note: condition evaluates to BIT
GO

-- Pattern 13: CASE with LIKE patterns
SELECT 
    CustomerID,
    CustomerName,
    Email,
    CASE 
        WHEN Email LIKE '%@gmail.com' THEN 'Gmail'
        WHEN Email LIKE '%@yahoo.%' THEN 'Yahoo'
        WHEN Email LIKE '%@hotmail.%' OR Email LIKE '%@outlook.%' THEN 'Microsoft'
        WHEN Email LIKE '%.edu' THEN 'Educational'
        WHEN Email LIKE '%.gov' THEN 'Government'
        ELSE 'Other'
    END AS EmailProvider
FROM dbo.Customers;
GO

-- Pattern 14: CASE with EXISTS
SELECT 
    c.CustomerID,
    c.CustomerName,
    CASE 
        WHEN EXISTS (SELECT 1 FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID AND o.OrderDate > DATEADD(MONTH, -1, GETDATE())) THEN 'Active'
        WHEN EXISTS (SELECT 1 FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID) THEN 'Inactive'
        ELSE 'Never Ordered'
    END AS CustomerStatus
FROM dbo.Customers c;
GO

-- Pattern 15: CASE with subquery
SELECT 
    ProductID,
    ProductName,
    Price,
    CASE 
        WHEN Price > (SELECT AVG(Price) FROM dbo.Products) THEN 'Above Average'
        WHEN Price = (SELECT AVG(Price) FROM dbo.Products) THEN 'Average'
        ELSE 'Below Average'
    END AS PriceComparison
FROM dbo.Products;
GO

-- Pattern 16: CASE returning different data types (implicit conversion)
SELECT 
    ProductID,
    CASE 
        WHEN StockQuantity > 100 THEN 'Plenty'
        WHEN StockQuantity > 0 THEN CAST(StockQuantity AS VARCHAR(10))
        ELSE 'Out of Stock'
    END AS StockInfo
FROM dbo.Products;
GO

-- Pattern 17: CASE with date calculations
SELECT 
    OrderID,
    OrderDate,
    ShippedDate,
    CASE 
        WHEN ShippedDate IS NULL THEN 'Not Shipped'
        WHEN DATEDIFF(DAY, OrderDate, ShippedDate) <= 1 THEN 'Same/Next Day'
        WHEN DATEDIFF(DAY, OrderDate, ShippedDate) <= 3 THEN '2-3 Days'
        WHEN DATEDIFF(DAY, OrderDate, ShippedDate) <= 7 THEN '4-7 Days'
        ELSE 'Over a Week'
    END AS ShippingSpeed
FROM dbo.Orders;
GO

-- Pattern 18: CASE with window functions
SELECT 
    ProductID,
    ProductName,
    CategoryID,
    Price,
    CASE 
        WHEN Price = MAX(Price) OVER (PARTITION BY CategoryID) THEN 'Most Expensive'
        WHEN Price = MIN(Price) OVER (PARTITION BY CategoryID) THEN 'Cheapest'
        ELSE 'Middle Range'
    END AS PricePosition
FROM dbo.Products;
GO

-- Pattern 19: CASE for data validation
SELECT 
    CustomerID,
    Email,
    Phone,
    CASE 
        WHEN Email IS NULL AND Phone IS NULL THEN 'Missing Contact'
        WHEN Email NOT LIKE '%@%.%' THEN 'Invalid Email'
        WHEN Phone NOT LIKE '[0-9]%' THEN 'Invalid Phone'
        ELSE 'Valid'
    END AS ValidationStatus
FROM dbo.Customers;
GO

-- Pattern 20: Complex business logic with CASE
SELECT 
    o.OrderID,
    o.CustomerID,
    o.TotalAmount,
    c.CustomerTier,
    o.TotalAmount * 
    CASE c.CustomerTier
        WHEN 'Platinum' THEN 
            CASE 
                WHEN o.TotalAmount >= 1000 THEN 0.15
                WHEN o.TotalAmount >= 500 THEN 0.12
                ELSE 0.10
            END
        WHEN 'Gold' THEN 
            CASE 
                WHEN o.TotalAmount >= 1000 THEN 0.10
                WHEN o.TotalAmount >= 500 THEN 0.08
                ELSE 0.05
            END
        WHEN 'Silver' THEN 
            CASE WHEN o.TotalAmount >= 500 THEN 0.05 ELSE 0.03 END
        ELSE 0
    END AS Discount
FROM dbo.Orders o
INNER JOIN dbo.Customers c ON o.CustomerID = c.CustomerID;
GO
