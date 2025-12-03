-- Sample 106: Static Aggregate and Reporting Queries
-- Category: Static SQL Equivalents
-- Complexity: Complex
-- Purpose: Parser testing - complex aggregations without dynamic SQL
-- Features: GROUP BY, HAVING, ROLLUP, CUBE, GROUPING SETS, window aggregates

-- Pattern 1: Multi-level GROUP BY with HAVING
SELECT 
    Region,
    Country,
    City,
    COUNT(*) AS CustomerCount,
    SUM(TotalPurchases) AS TotalRevenue,
    AVG(TotalPurchases) AS AvgPurchase,
    MIN(FirstPurchaseDate) AS EarliestCustomer,
    MAX(LastPurchaseDate) AS LatestActivity
FROM dbo.Customers
WHERE IsActive = 1
GROUP BY Region, Country, City
HAVING COUNT(*) >= 10
   AND SUM(TotalPurchases) > 10000
ORDER BY Region, Country, TotalRevenue DESC;
GO

-- Pattern 2: ROLLUP for hierarchical subtotals
SELECT 
    COALESCE(Category, 'ALL CATEGORIES') AS Category,
    COALESCE(SubCategory, 'All SubCategories') AS SubCategory,
    COALESCE(ProductLine, 'All Products') AS ProductLine,
    COUNT(*) AS ProductCount,
    SUM(UnitsSold) AS TotalUnits,
    SUM(Revenue) AS TotalRevenue,
    AVG(Margin) AS AvgMargin
FROM dbo.SalesDetail
WHERE SaleDate BETWEEN '2024-01-01' AND '2024-12-31'
GROUP BY ROLLUP (Category, SubCategory, ProductLine)
ORDER BY 
    GROUPING(Category), Category,
    GROUPING(SubCategory), SubCategory,
    GROUPING(ProductLine), ProductLine;
GO

-- Pattern 3: CUBE for all dimension combinations
SELECT 
    COALESCE(CAST(YEAR(OrderDate) AS VARCHAR(4)), 'All Years') AS OrderYear,
    COALESCE(CAST(MONTH(OrderDate) AS VARCHAR(2)), 'All Months') AS OrderMonth,
    COALESCE(Region, 'All Regions') AS Region,
    COUNT(DISTINCT OrderID) AS OrderCount,
    COUNT(DISTINCT CustomerID) AS UniqueCustomers,
    SUM(OrderTotal) AS Revenue
FROM dbo.Orders
WHERE OrderDate >= '2022-01-01'
GROUP BY CUBE (YEAR(OrderDate), MONTH(OrderDate), Region)
ORDER BY 
    GROUPING(YEAR(OrderDate)), YEAR(OrderDate),
    GROUPING(MONTH(OrderDate)), MONTH(OrderDate),
    GROUPING(Region), Region;
GO

-- Pattern 4: GROUPING SETS for specific combinations
SELECT 
    CASE WHEN GROUPING(Department) = 1 THEN 'Total' ELSE Department END AS Department,
    CASE WHEN GROUPING(JobTitle) = 1 THEN 'All Titles' ELSE JobTitle END AS JobTitle,
    CASE WHEN GROUPING(Gender) = 1 THEN 'All' ELSE Gender END AS Gender,
    COUNT(*) AS EmployeeCount,
    AVG(Salary) AS AvgSalary,
    SUM(Salary) AS TotalSalary
FROM dbo.Employees
WHERE Status = 'Active'
GROUP BY GROUPING SETS (
    (Department, JobTitle, Gender),
    (Department, JobTitle),
    (Department, Gender),
    (Department),
    (JobTitle),
    ()
)
ORDER BY 
    GROUPING(Department), Department,
    GROUPING(JobTitle), JobTitle,
    GROUPING(Gender), Gender;
GO

-- Pattern 5: Window functions with multiple aggregations
SELECT 
    OrderID,
    CustomerID,
    OrderDate,
    OrderTotal,
    SUM(OrderTotal) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS RunningTotal,
    AVG(OrderTotal) OVER (PARTITION BY CustomerID) AS CustomerAvgOrder,
    COUNT(*) OVER (PARTITION BY CustomerID) AS CustomerOrderCount,
    SUM(OrderTotal) OVER (ORDER BY OrderDate ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS Rolling7DayTotal,
    LAG(OrderTotal, 1, 0) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS PrevOrderTotal,
    LEAD(OrderTotal, 1, 0) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS NextOrderTotal,
    FIRST_VALUE(OrderTotal) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS FirstOrderTotal,
    LAST_VALUE(OrderTotal) OVER (PARTITION BY CustomerID ORDER BY OrderDate 
        ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) AS LastOrderTotal
FROM dbo.Orders
WHERE OrderDate >= '2024-01-01'
ORDER BY CustomerID, OrderDate;
GO

-- Pattern 6: Percentile and statistical aggregations
SELECT 
    Department,
    COUNT(*) AS EmpCount,
    AVG(Salary) AS AvgSalary,
    STDEV(Salary) AS StdDevSalary,
    VAR(Salary) AS VarSalary,
    MIN(Salary) AS MinSalary,
    MAX(Salary) AS MaxSalary,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY Salary) OVER (PARTITION BY Department) AS Percentile25,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY Salary) OVER (PARTITION BY Department) AS Median,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY Salary) OVER (PARTITION BY Department) AS Percentile75,
    PERCENTILE_DISC(0.50) WITHIN GROUP (ORDER BY Salary) OVER (PARTITION BY Department) AS MedianDisc
FROM dbo.Employees
WHERE Status = 'Active'
GROUP BY Department, Salary
ORDER BY Department;
GO

-- Pattern 7: Conditional aggregation
SELECT 
    ProductCategory,
    COUNT(*) AS TotalProducts,
    SUM(CASE WHEN StockLevel > 0 THEN 1 ELSE 0 END) AS InStockCount,
    SUM(CASE WHEN StockLevel = 0 THEN 1 ELSE 0 END) AS OutOfStockCount,
    SUM(CASE WHEN StockLevel < ReorderLevel THEN 1 ELSE 0 END) AS NeedsReorderCount,
    AVG(CASE WHEN SalesLastMonth > 0 THEN Price ELSE NULL END) AS AvgPriceOfSoldItems,
    SUM(CASE WHEN IsDiscontinued = 0 THEN StockLevel * Price ELSE 0 END) AS ActiveInventoryValue,
    MAX(CASE WHEN SalesLastMonth > 0 THEN LastSaleDate ELSE NULL END) AS LastSaleDate
FROM dbo.Products
GROUP BY ProductCategory
HAVING SUM(CASE WHEN StockLevel = 0 THEN 1 ELSE 0 END) > 0
ORDER BY OutOfStockCount DESC;
GO

-- Pattern 8: Year-over-year comparison
SELECT 
    Category,
    SUM(CASE WHEN YEAR(SaleDate) = 2022 THEN Amount ELSE 0 END) AS Sales2022,
    SUM(CASE WHEN YEAR(SaleDate) = 2023 THEN Amount ELSE 0 END) AS Sales2023,
    SUM(CASE WHEN YEAR(SaleDate) = 2024 THEN Amount ELSE 0 END) AS Sales2024,
    CAST(
        (SUM(CASE WHEN YEAR(SaleDate) = 2024 THEN Amount ELSE 0 END) - 
         SUM(CASE WHEN YEAR(SaleDate) = 2023 THEN Amount ELSE 0 END)) * 100.0 /
        NULLIF(SUM(CASE WHEN YEAR(SaleDate) = 2023 THEN Amount ELSE 0 END), 0)
        AS DECIMAL(10,2)
    ) AS YoYGrowthPercent
FROM dbo.Sales
WHERE YEAR(SaleDate) BETWEEN 2022 AND 2024
GROUP BY Category
ORDER BY Sales2024 DESC;
GO

-- Pattern 9: Dense ranking and distribution
SELECT 
    EmployeeID,
    EmployeeName,
    Department,
    Salary,
    ROW_NUMBER() OVER (ORDER BY Salary DESC) AS RowNum,
    RANK() OVER (ORDER BY Salary DESC) AS SalaryRank,
    DENSE_RANK() OVER (ORDER BY Salary DESC) AS DenseRank,
    NTILE(4) OVER (ORDER BY Salary DESC) AS Quartile,
    PERCENT_RANK() OVER (ORDER BY Salary) AS PercentRank,
    CUME_DIST() OVER (ORDER BY Salary) AS CumeDist,
    ROW_NUMBER() OVER (PARTITION BY Department ORDER BY Salary DESC) AS DeptRank
FROM dbo.Employees
WHERE Status = 'Active'
ORDER BY Salary DESC;
GO

-- Pattern 10: Complex aggregation with subqueries
SELECT 
    c.CustomerID,
    c.CustomerName,
    c.CustomerType,
    OrderSummary.OrderCount,
    OrderSummary.TotalSpent,
    OrderSummary.AvgOrderValue,
    OrderSummary.FirstOrder,
    OrderSummary.LastOrder,
    DATEDIFF(DAY, OrderSummary.FirstOrder, OrderSummary.LastOrder) AS CustomerLifespanDays,
    OrderSummary.TotalSpent / NULLIF(DATEDIFF(MONTH, OrderSummary.FirstOrder, OrderSummary.LastOrder), 0) AS AvgMonthlySpend
FROM dbo.Customers c
CROSS APPLY (
    SELECT 
        COUNT(*) AS OrderCount,
        SUM(OrderTotal) AS TotalSpent,
        AVG(OrderTotal) AS AvgOrderValue,
        MIN(OrderDate) AS FirstOrder,
        MAX(OrderDate) AS LastOrder
    FROM dbo.Orders o
    WHERE o.CustomerID = c.CustomerID
    AND o.Status = 'Completed'
) AS OrderSummary
WHERE OrderSummary.OrderCount > 0
ORDER BY OrderSummary.TotalSpent DESC;
GO
