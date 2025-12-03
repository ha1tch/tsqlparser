-- Sample 185: Ranking and Analytic Functions
-- Category: Syntax Coverage / Pure Logic
-- Complexity: Complex
-- Purpose: Parser testing - ranking and analytic function syntax
-- Features: ROW_NUMBER, RANK, DENSE_RANK, NTILE, LAG, LEAD, etc.

-- Pattern 1: ROW_NUMBER basic
SELECT 
    ROW_NUMBER() OVER (ORDER BY CustomerName) AS RowNum,
    CustomerID,
    CustomerName
FROM dbo.Customers;
GO

-- Pattern 2: ROW_NUMBER with PARTITION BY
SELECT 
    ROW_NUMBER() OVER (PARTITION BY CategoryID ORDER BY Price DESC) AS CategoryRank,
    ProductID,
    ProductName,
    CategoryID,
    Price
FROM dbo.Products;
GO

-- Pattern 3: RANK function
SELECT 
    RANK() OVER (ORDER BY TotalAmount DESC) AS Rank,
    OrderID,
    CustomerID,
    TotalAmount
FROM dbo.Orders;
GO

-- Pattern 4: DENSE_RANK function
SELECT 
    DENSE_RANK() OVER (ORDER BY Salary DESC) AS DenseRank,
    EmployeeID,
    EmployeeName,
    Salary
FROM dbo.Employees;
GO

-- Pattern 5: RANK vs DENSE_RANK comparison
SELECT 
    ProductID,
    Price,
    RANK() OVER (ORDER BY Price DESC) AS Rank,
    DENSE_RANK() OVER (ORDER BY Price DESC) AS DenseRank,
    ROW_NUMBER() OVER (ORDER BY Price DESC) AS RowNum
FROM dbo.Products;
GO

-- Pattern 6: NTILE function
SELECT 
    NTILE(4) OVER (ORDER BY Salary DESC) AS Quartile,
    NTILE(10) OVER (ORDER BY Salary DESC) AS Decile,
    NTILE(100) OVER (ORDER BY Salary DESC) AS Percentile,
    EmployeeID,
    Salary
FROM dbo.Employees;
GO

-- Pattern 7: LAG function
SELECT 
    OrderID,
    CustomerID,
    OrderDate,
    TotalAmount,
    LAG(TotalAmount) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS PrevOrderAmount,
    LAG(OrderDate) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS PrevOrderDate
FROM dbo.Orders;
GO

-- Pattern 8: LAG with offset and default
SELECT 
    OrderID,
    OrderDate,
    TotalAmount,
    LAG(TotalAmount, 1, 0) OVER (ORDER BY OrderDate) AS Prev1,
    LAG(TotalAmount, 2, 0) OVER (ORDER BY OrderDate) AS Prev2,
    LAG(TotalAmount, 3, 0) OVER (ORDER BY OrderDate) AS Prev3
FROM dbo.Orders;
GO

-- Pattern 9: LEAD function
SELECT 
    OrderID,
    CustomerID,
    OrderDate,
    TotalAmount,
    LEAD(TotalAmount) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS NextOrderAmount,
    LEAD(OrderDate) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS NextOrderDate
FROM dbo.Orders;
GO

-- Pattern 10: LEAD with offset and default
SELECT 
    ProductID,
    PriceDate,
    Price,
    LEAD(Price, 1) OVER (PARTITION BY ProductID ORDER BY PriceDate) AS NextPrice,
    LEAD(Price, 1, Price) OVER (PARTITION BY ProductID ORDER BY PriceDate) AS NextPriceOrCurrent
FROM dbo.PriceHistory;
GO

-- Pattern 11: FIRST_VALUE function
SELECT 
    OrderID,
    CustomerID,
    OrderDate,
    TotalAmount,
    FIRST_VALUE(OrderID) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS FirstOrderID,
    FIRST_VALUE(TotalAmount) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS FirstOrderAmount
FROM dbo.Orders;
GO

-- Pattern 12: LAST_VALUE function (requires frame)
SELECT 
    OrderID,
    CustomerID,
    OrderDate,
    TotalAmount,
    LAST_VALUE(OrderID) OVER (
        PARTITION BY CustomerID 
        ORDER BY OrderDate 
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS LastOrderID,
    LAST_VALUE(TotalAmount) OVER (
        PARTITION BY CustomerID 
        ORDER BY OrderDate 
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS LastOrderAmount
FROM dbo.Orders;
GO

-- Pattern 13: NTH_VALUE function (SQL Server 2022+)
SELECT 
    ProductID,
    CategoryID,
    Price,
    NTH_VALUE(ProductName, 1) OVER (PARTITION BY CategoryID ORDER BY Price DESC) AS MostExpensive,
    NTH_VALUE(ProductName, 2) OVER (PARTITION BY CategoryID ORDER BY Price DESC) AS SecondMostExpensive,
    NTH_VALUE(ProductName, 3) OVER (PARTITION BY CategoryID ORDER BY Price DESC) AS ThirdMostExpensive
FROM dbo.Products;
GO

-- Pattern 14: PERCENT_RANK function
SELECT 
    EmployeeID,
    Salary,
    PERCENT_RANK() OVER (ORDER BY Salary) AS PercentRank,
    PERCENT_RANK() OVER (PARTITION BY DepartmentID ORDER BY Salary) AS DeptPercentRank
FROM dbo.Employees;
GO

-- Pattern 15: CUME_DIST function
SELECT 
    EmployeeID,
    Salary,
    CUME_DIST() OVER (ORDER BY Salary) AS CumulativeDistribution,
    CUME_DIST() OVER (PARTITION BY DepartmentID ORDER BY Salary) AS DeptCumeDist
FROM dbo.Employees;
GO

-- Pattern 16: PERCENTILE_CONT function
SELECT DISTINCT
    DepartmentID,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Salary) OVER (PARTITION BY DepartmentID) AS MedianSalary,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY Salary) OVER (PARTITION BY DepartmentID) AS Q1Salary,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY Salary) OVER (PARTITION BY DepartmentID) AS Q3Salary
FROM dbo.Employees;
GO

-- Pattern 17: PERCENTILE_DISC function
SELECT DISTINCT
    DepartmentID,
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY Salary) OVER (PARTITION BY DepartmentID) AS MedianSalary
FROM dbo.Employees;
GO

-- Pattern 18: Multiple ranking functions together
SELECT 
    e.EmployeeID,
    e.EmployeeName,
    e.DepartmentID,
    e.Salary,
    ROW_NUMBER() OVER (PARTITION BY e.DepartmentID ORDER BY e.Salary DESC) AS DeptRowNum,
    RANK() OVER (PARTITION BY e.DepartmentID ORDER BY e.Salary DESC) AS DeptRank,
    DENSE_RANK() OVER (PARTITION BY e.DepartmentID ORDER BY e.Salary DESC) AS DeptDenseRank,
    NTILE(4) OVER (PARTITION BY e.DepartmentID ORDER BY e.Salary DESC) AS DeptQuartile,
    ROW_NUMBER() OVER (ORDER BY e.Salary DESC) AS OverallRowNum,
    RANK() OVER (ORDER BY e.Salary DESC) AS OverallRank
FROM dbo.Employees e;
GO

-- Pattern 19: Ranking for top-N per group
WITH RankedProducts AS (
    SELECT 
        ProductID,
        ProductName,
        CategoryID,
        Price,
        ROW_NUMBER() OVER (PARTITION BY CategoryID ORDER BY Price DESC) AS Rank
    FROM dbo.Products
)
SELECT *
FROM RankedProducts
WHERE Rank <= 3;
GO

-- Pattern 20: Gap and island detection using ranking
WITH Numbered AS (
    SELECT 
        OrderDate,
        ROW_NUMBER() OVER (ORDER BY OrderDate) AS RowNum
    FROM dbo.Orders
),
Grouped AS (
    SELECT 
        OrderDate,
        DATEADD(DAY, -RowNum, OrderDate) AS GroupKey
    FROM Numbered
)
SELECT 
    MIN(OrderDate) AS IslandStart,
    MAX(OrderDate) AS IslandEnd,
    COUNT(*) AS DaysInIsland
FROM Grouped
GROUP BY GroupKey
ORDER BY IslandStart;
GO
