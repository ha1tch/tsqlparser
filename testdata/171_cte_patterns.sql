-- Sample 171: Common Table Expression (CTE) Patterns
-- Category: Syntax Coverage / Query Patterns
-- Complexity: Complex
-- Purpose: Parser testing - CTE syntax variations
-- Features: WITH clause, recursive CTEs, multiple CTEs, CTE in DML

-- Pattern 1: Basic CTE
WITH CustomerOrders AS (
    SELECT CustomerID, COUNT(*) AS OrderCount, SUM(TotalAmount) AS TotalSpent
    FROM dbo.Orders
    GROUP BY CustomerID
)
SELECT c.CustomerName, co.OrderCount, co.TotalSpent
FROM dbo.Customers c
INNER JOIN CustomerOrders co ON c.CustomerID = co.CustomerID;
GO

-- Pattern 2: CTE with column aliases in definition
WITH CustomerStats (CustID, OrderCnt, TotalAmt) AS (
    SELECT CustomerID, COUNT(*), SUM(TotalAmount)
    FROM dbo.Orders
    GROUP BY CustomerID
)
SELECT * FROM CustomerStats WHERE OrderCnt > 5;
GO

-- Pattern 3: Multiple CTEs
WITH 
ActiveCustomers AS (
    SELECT CustomerID, CustomerName
    FROM dbo.Customers
    WHERE IsActive = 1
),
RecentOrders AS (
    SELECT CustomerID, OrderID, OrderDate, TotalAmount
    FROM dbo.Orders
    WHERE OrderDate >= DATEADD(MONTH, -3, GETDATE())
),
CustomerSummary AS (
    SELECT 
        ac.CustomerID,
        ac.CustomerName,
        COUNT(ro.OrderID) AS RecentOrderCount,
        ISNULL(SUM(ro.TotalAmount), 0) AS RecentTotal
    FROM ActiveCustomers ac
    LEFT JOIN RecentOrders ro ON ac.CustomerID = ro.CustomerID
    GROUP BY ac.CustomerID, ac.CustomerName
)
SELECT * FROM CustomerSummary ORDER BY RecentTotal DESC;
GO

-- Pattern 4: CTE referencing another CTE
WITH 
AllOrders AS (
    SELECT CustomerID, OrderID, TotalAmount
    FROM dbo.Orders
),
CustomerTotals AS (
    SELECT CustomerID, SUM(TotalAmount) AS Total
    FROM AllOrders
    GROUP BY CustomerID
),
RankedCustomers AS (
    SELECT 
        CustomerID, 
        Total,
        RANK() OVER (ORDER BY Total DESC) AS Rank
    FROM CustomerTotals
)
SELECT * FROM RankedCustomers WHERE Rank <= 10;
GO

-- Pattern 5: Basic recursive CTE (hierarchy)
WITH EmployeeHierarchy AS (
    -- Anchor member
    SELECT EmployeeID, EmployeeName, ManagerID, 0 AS Level
    FROM dbo.Employees
    WHERE ManagerID IS NULL
    
    UNION ALL
    
    -- Recursive member
    SELECT e.EmployeeID, e.EmployeeName, e.ManagerID, eh.Level + 1
    FROM dbo.Employees e
    INNER JOIN EmployeeHierarchy eh ON e.ManagerID = eh.EmployeeID
)
SELECT * FROM EmployeeHierarchy ORDER BY Level, EmployeeName;
GO

-- Pattern 6: Recursive CTE with path
WITH CategoryPath AS (
    SELECT 
        CategoryID, 
        CategoryName, 
        ParentCategoryID,
        CAST(CategoryName AS NVARCHAR(500)) AS FullPath,
        0 AS Level
    FROM dbo.Categories
    WHERE ParentCategoryID IS NULL
    
    UNION ALL
    
    SELECT 
        c.CategoryID, 
        c.CategoryName, 
        c.ParentCategoryID,
        CAST(cp.FullPath + ' > ' + c.CategoryName AS NVARCHAR(500)),
        cp.Level + 1
    FROM dbo.Categories c
    INNER JOIN CategoryPath cp ON c.ParentCategoryID = cp.CategoryID
)
SELECT * FROM CategoryPath ORDER BY FullPath;
GO

-- Pattern 7: Recursive CTE with MAXRECURSION
WITH Numbers AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM Numbers WHERE n < 1000
)
SELECT n FROM Numbers
OPTION (MAXRECURSION 1000);
GO

-- Pattern 8: Recursive CTE for date range
WITH DateRange AS (
    SELECT CAST('2024-01-01' AS DATE) AS Date
    UNION ALL
    SELECT DATEADD(DAY, 1, Date)
    FROM DateRange
    WHERE Date < '2024-12-31'
)
SELECT Date, DATENAME(WEEKDAY, Date) AS DayName
FROM DateRange
OPTION (MAXRECURSION 400);
GO

-- Pattern 9: Recursive CTE for bill of materials
WITH BOM AS (
    -- Top-level products
    SELECT 
        ProductID,
        ComponentID,
        Quantity,
        1 AS Level
    FROM dbo.ProductComponents
    WHERE ProductID = @ProductID
    
    UNION ALL
    
    -- Sub-components
    SELECT 
        pc.ProductID,
        pc.ComponentID,
        pc.Quantity * b.Quantity,
        b.Level + 1
    FROM dbo.ProductComponents pc
    INNER JOIN BOM b ON pc.ProductID = b.ComponentID
)
SELECT * FROM BOM;
GO

-- Pattern 10: CTE in UPDATE
WITH DuplicateEmails AS (
    SELECT 
        CustomerID,
        Email,
        ROW_NUMBER() OVER (PARTITION BY Email ORDER BY CustomerID) AS RowNum
    FROM dbo.Customers
)
UPDATE DuplicateEmails
SET Email = Email + CAST(RowNum AS VARCHAR(10))
WHERE RowNum > 1;
GO

-- Pattern 11: CTE in DELETE
WITH OldOrders AS (
    SELECT OrderID
    FROM dbo.Orders
    WHERE OrderDate < DATEADD(YEAR, -5, GETDATE())
)
DELETE FROM OldOrders;
GO

-- Pattern 12: CTE in INSERT
WITH NewCustomerOrders AS (
    SELECT 
        c.CustomerID,
        COUNT(o.OrderID) AS OrderCount
    FROM dbo.Customers c
    LEFT JOIN dbo.Orders o ON c.CustomerID = o.CustomerID
    WHERE c.CreatedDate >= DATEADD(MONTH, -1, GETDATE())
    GROUP BY c.CustomerID
)
INSERT INTO dbo.NewCustomerReport (CustomerID, OrderCount, ReportDate)
SELECT CustomerID, OrderCount, GETDATE()
FROM NewCustomerOrders;
GO

-- Pattern 13: CTE in MERGE
WITH SourceData AS (
    SELECT 
        CustomerID,
        COUNT(*) AS OrderCount,
        SUM(TotalAmount) AS TotalSpent
    FROM dbo.Orders
    WHERE OrderDate >= DATEADD(MONTH, -1, GETDATE())
    GROUP BY CustomerID
)
MERGE INTO dbo.CustomerMetrics AS target
USING SourceData AS source
ON target.CustomerID = source.CustomerID
WHEN MATCHED THEN
    UPDATE SET 
        MonthlyOrders = source.OrderCount,
        MonthlySpent = source.TotalSpent,
        LastUpdated = GETDATE()
WHEN NOT MATCHED THEN
    INSERT (CustomerID, MonthlyOrders, MonthlySpent, LastUpdated)
    VALUES (source.CustomerID, source.OrderCount, source.TotalSpent, GETDATE());
GO

-- Pattern 14: CTE with window functions
WITH RankedProducts AS (
    SELECT 
        ProductID,
        ProductName,
        CategoryID,
        Price,
        ROW_NUMBER() OVER (PARTITION BY CategoryID ORDER BY Price DESC) AS PriceRank,
        DENSE_RANK() OVER (PARTITION BY CategoryID ORDER BY Price DESC) AS DenseRank,
        NTILE(4) OVER (PARTITION BY CategoryID ORDER BY Price DESC) AS Quartile
    FROM dbo.Products
)
SELECT * FROM RankedProducts WHERE PriceRank <= 3;
GO

-- Pattern 15: CTE for pagination
WITH PagedResults AS (
    SELECT 
        CustomerID,
        CustomerName,
        Email,
        ROW_NUMBER() OVER (ORDER BY CustomerName) AS RowNum
    FROM dbo.Customers
    WHERE IsActive = 1
)
SELECT CustomerID, CustomerName, Email
FROM PagedResults
WHERE RowNum BETWEEN 21 AND 40;  -- Page 2, 20 per page
GO

-- Pattern 16: CTE with aggregation and filtering
WITH MonthlySales AS (
    SELECT 
        YEAR(OrderDate) AS Year,
        MONTH(OrderDate) AS Month,
        SUM(TotalAmount) AS TotalSales,
        COUNT(*) AS OrderCount
    FROM dbo.Orders
    GROUP BY YEAR(OrderDate), MONTH(OrderDate)
),
SalesWithGrowth AS (
    SELECT 
        Year,
        Month,
        TotalSales,
        OrderCount,
        LAG(TotalSales) OVER (ORDER BY Year, Month) AS PrevMonthSales,
        TotalSales - LAG(TotalSales) OVER (ORDER BY Year, Month) AS Growth
    FROM MonthlySales
)
SELECT * FROM SalesWithGrowth WHERE Growth > 0;
GO

-- Pattern 17: CTE for running totals
WITH DailySales AS (
    SELECT 
        CAST(OrderDate AS DATE) AS SaleDate,
        SUM(TotalAmount) AS DailyTotal
    FROM dbo.Orders
    GROUP BY CAST(OrderDate AS DATE)
),
RunningTotals AS (
    SELECT 
        SaleDate,
        DailyTotal,
        SUM(DailyTotal) OVER (ORDER BY SaleDate ROWS UNBOUNDED PRECEDING) AS RunningTotal
    FROM DailySales
)
SELECT * FROM RunningTotals ORDER BY SaleDate;
GO

-- Pattern 18: CTE with UNION
WITH AllContacts AS (
    SELECT CustomerID AS ID, CustomerName AS Name, 'Customer' AS Type
    FROM dbo.Customers
    UNION ALL
    SELECT SupplierID, SupplierName, 'Supplier'
    FROM dbo.Suppliers
    UNION ALL
    SELECT EmployeeID, EmployeeName, 'Employee'
    FROM dbo.Employees
)
SELECT * FROM AllContacts ORDER BY Type, Name;
GO

-- Pattern 19: CTE with EXISTS
WITH CustomersWithReturns AS (
    SELECT DISTINCT CustomerID
    FROM dbo.Returns
    WHERE ReturnDate >= DATEADD(YEAR, -1, GETDATE())
)
SELECT c.CustomerID, c.CustomerName
FROM dbo.Customers c
WHERE EXISTS (SELECT 1 FROM CustomersWithReturns cwr WHERE cwr.CustomerID = c.CustomerID);
GO

-- Pattern 20: Nested CTE usage (CTE calling CTE calling CTE)
WITH 
Level1 AS (
    SELECT ProductID, CategoryID, Price FROM dbo.Products
),
Level2 AS (
    SELECT CategoryID, AVG(Price) AS AvgPrice FROM Level1 GROUP BY CategoryID
),
Level3 AS (
    SELECT l1.ProductID, l1.Price, l2.AvgPrice, l1.Price - l2.AvgPrice AS Diff
    FROM Level1 l1
    INNER JOIN Level2 l2 ON l1.CategoryID = l2.CategoryID
)
SELECT * FROM Level3 WHERE Diff > 0;
GO
