-- Sample 159: Window Function OVER Clause Variations
-- Category: Syntax Coverage / Advanced
-- Complexity: Advanced
-- Purpose: Parser testing - OVER clause syntax variations
-- Features: PARTITION BY, ORDER BY, frame clauses, all window functions

-- Pattern 1: Basic OVER with PARTITION BY
SELECT 
    DepartmentID,
    EmployeeID,
    Salary,
    AVG(Salary) OVER (PARTITION BY DepartmentID) AS DeptAvgSalary,
    SUM(Salary) OVER (PARTITION BY DepartmentID) AS DeptTotalSalary,
    COUNT(*) OVER (PARTITION BY DepartmentID) AS DeptEmployeeCount
FROM dbo.Employees;
GO

-- Pattern 2: OVER with ORDER BY (running aggregates)
SELECT 
    OrderID,
    OrderDate,
    TotalAmount,
    SUM(TotalAmount) OVER (ORDER BY OrderDate) AS RunningTotal,
    AVG(TotalAmount) OVER (ORDER BY OrderDate) AS RunningAvg,
    COUNT(*) OVER (ORDER BY OrderDate) AS RunningCount
FROM dbo.Orders;
GO

-- Pattern 3: OVER with PARTITION BY and ORDER BY
SELECT 
    CustomerID,
    OrderID,
    OrderDate,
    TotalAmount,
    SUM(TotalAmount) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS CustomerRunningTotal,
    ROW_NUMBER() OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS CustomerOrderNum
FROM dbo.Orders;
GO

-- Pattern 4: ROW_NUMBER, RANK, DENSE_RANK, NTILE
SELECT 
    DepartmentID,
    EmployeeID,
    Salary,
    ROW_NUMBER() OVER (PARTITION BY DepartmentID ORDER BY Salary DESC) AS RowNum,
    RANK() OVER (PARTITION BY DepartmentID ORDER BY Salary DESC) AS Rank,
    DENSE_RANK() OVER (PARTITION BY DepartmentID ORDER BY Salary DESC) AS DenseRank,
    NTILE(4) OVER (PARTITION BY DepartmentID ORDER BY Salary DESC) AS Quartile
FROM dbo.Employees;
GO

-- Pattern 5: PERCENT_RANK and CUME_DIST
SELECT 
    ProductID,
    ProductName,
    Price,
    PERCENT_RANK() OVER (ORDER BY Price) AS PercentRank,
    CUME_DIST() OVER (ORDER BY Price) AS CumulativeDistribution
FROM dbo.Products;
GO

-- Pattern 6: LAG and LEAD
SELECT 
    OrderID,
    CustomerID,
    OrderDate,
    TotalAmount,
    LAG(TotalAmount) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS PrevOrderAmount,
    LAG(TotalAmount, 2) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS TwoPrevOrderAmount,
    LEAD(TotalAmount) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS NextOrderAmount,
    LEAD(TotalAmount, 1, 0) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS NextOrderAmountDefault
FROM dbo.Orders;
GO

-- Pattern 7: FIRST_VALUE and LAST_VALUE
SELECT 
    DepartmentID,
    EmployeeID,
    HireDate,
    Salary,
    FIRST_VALUE(EmployeeName) OVER (PARTITION BY DepartmentID ORDER BY HireDate) AS FirstHired,
    LAST_VALUE(EmployeeName) OVER (PARTITION BY DepartmentID ORDER BY HireDate 
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS LastHired
FROM dbo.Employees;
GO

-- Pattern 8: NTH_VALUE (SQL Server 2022+)
SELECT 
    DepartmentID,
    EmployeeID,
    Salary,
    NTH_VALUE(EmployeeName, 1) OVER (PARTITION BY DepartmentID ORDER BY Salary DESC) AS HighestPaid,
    NTH_VALUE(EmployeeName, 2) OVER (PARTITION BY DepartmentID ORDER BY Salary DESC) AS SecondHighest,
    NTH_VALUE(EmployeeName, 3) OVER (PARTITION BY DepartmentID ORDER BY Salary DESC) AS ThirdHighest
FROM dbo.Employees;
GO

-- Pattern 9: ROWS frame clause
SELECT 
    OrderDate,
    TotalAmount,
    SUM(TotalAmount) OVER (ORDER BY OrderDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS Sum3Day,
    AVG(TotalAmount) OVER (ORDER BY OrderDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS Avg3Day,
    SUM(TotalAmount) OVER (ORDER BY OrderDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningTotal,
    SUM(TotalAmount) OVER (ORDER BY OrderDate ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) AS FutureTotal
FROM dbo.Orders;
GO

-- Pattern 10: RANGE frame clause
SELECT 
    OrderDate,
    TotalAmount,
    SUM(TotalAmount) OVER (ORDER BY OrderDate RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningTotalRange,
    SUM(TotalAmount) OVER (ORDER BY TotalAmount RANGE BETWEEN 100 PRECEDING AND 100 FOLLOWING) AS AmountRange200
FROM dbo.Orders;
GO

-- Pattern 11: Frame clause variations
SELECT 
    OrderID,
    OrderDate,
    TotalAmount,
    -- Different frame specifications
    SUM(TotalAmount) OVER (ORDER BY OrderDate ROWS UNBOUNDED PRECEDING) AS RowsUnbounded,
    SUM(TotalAmount) OVER (ORDER BY OrderDate ROWS CURRENT ROW) AS RowsCurrent,
    SUM(TotalAmount) OVER (ORDER BY OrderDate ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS Rows1Each,
    SUM(TotalAmount) OVER (ORDER BY OrderDate ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS AllRows
FROM dbo.Orders;
GO

-- Pattern 12: Multiple window functions with same OVER
SELECT 
    DepartmentID,
    EmployeeID,
    Salary,
    ROW_NUMBER() OVER w AS RowNum,
    RANK() OVER w AS Rank,
    SUM(Salary) OVER w AS RunningTotal
FROM dbo.Employees
WINDOW w AS (PARTITION BY DepartmentID ORDER BY Salary DESC);
GO

-- Pattern 13: Multiple different OVER clauses
SELECT 
    DepartmentID,
    EmployeeID,
    Salary,
    ROW_NUMBER() OVER (ORDER BY Salary DESC) AS OverallRank,
    ROW_NUMBER() OVER (PARTITION BY DepartmentID ORDER BY Salary DESC) AS DeptRank,
    SUM(Salary) OVER () AS TotalAllSalaries,
    SUM(Salary) OVER (PARTITION BY DepartmentID) AS DeptTotalSalary,
    AVG(Salary) OVER (ORDER BY HireDate ROWS BETWEEN 5 PRECEDING AND CURRENT ROW) AS MovingAvg
FROM dbo.Employees;
GO

-- Pattern 14: OVER() with empty parentheses (entire result set)
SELECT 
    ProductID,
    ProductName,
    Price,
    AVG(Price) OVER () AS OverallAvgPrice,
    MIN(Price) OVER () AS OverallMinPrice,
    MAX(Price) OVER () AS OverallMaxPrice,
    COUNT(*) OVER () AS TotalProducts,
    Price - AVG(Price) OVER () AS PriceDiffFromAvg
FROM dbo.Products;
GO

-- Pattern 15: ORDER BY with multiple columns
SELECT 
    DepartmentID,
    EmployeeID,
    LastName,
    FirstName,
    HireDate,
    ROW_NUMBER() OVER (PARTITION BY DepartmentID ORDER BY HireDate, LastName, FirstName) AS Sequence
FROM dbo.Employees;
GO

-- Pattern 16: ORDER BY with DESC/ASC mixed
SELECT 
    DepartmentID,
    EmployeeID,
    Salary,
    HireDate,
    ROW_NUMBER() OVER (PARTITION BY DepartmentID ORDER BY Salary DESC, HireDate ASC) AS Rank
FROM dbo.Employees;
GO

-- Pattern 17: ORDER BY CASE expression
SELECT 
    ProductID,
    ProductName,
    CategoryID,
    Price,
    ROW_NUMBER() OVER (
        ORDER BY 
            CASE CategoryID 
                WHEN 1 THEN 1 
                WHEN 3 THEN 2 
                ELSE 3 
            END,
            Price DESC
    ) AS CustomRank
FROM dbo.Products;
GO

-- Pattern 18: Window aggregate with FILTER (simulated with CASE)
SELECT 
    DepartmentID,
    EmployeeID,
    IsActive,
    Salary,
    SUM(CASE WHEN IsActive = 1 THEN Salary ELSE 0 END) OVER (PARTITION BY DepartmentID) AS ActiveSalaryTotal,
    COUNT(CASE WHEN IsActive = 1 THEN 1 END) OVER (PARTITION BY DepartmentID) AS ActiveCount
FROM dbo.Employees;
GO

-- Pattern 19: Running difference with LAG
SELECT 
    OrderID,
    OrderDate,
    TotalAmount,
    TotalAmount - LAG(TotalAmount, 1, TotalAmount) OVER (ORDER BY OrderDate) AS DiffFromPrev,
    CASE 
        WHEN TotalAmount > LAG(TotalAmount) OVER (ORDER BY OrderDate) THEN 'Increase'
        WHEN TotalAmount < LAG(TotalAmount) OVER (ORDER BY OrderDate) THEN 'Decrease'
        ELSE 'Same'
    END AS Trend
FROM dbo.Orders;
GO

-- Pattern 20: Complex window function combination
SELECT 
    c.CustomerID,
    c.CustomerName,
    o.OrderDate,
    o.TotalAmount,
    -- Running totals
    SUM(o.TotalAmount) OVER (PARTITION BY c.CustomerID ORDER BY o.OrderDate) AS CustomerRunningTotal,
    -- Moving averages
    AVG(o.TotalAmount) OVER (PARTITION BY c.CustomerID ORDER BY o.OrderDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS MovingAvg3,
    -- Rank within customer
    ROW_NUMBER() OVER (PARTITION BY c.CustomerID ORDER BY o.OrderDate) AS OrderSequence,
    -- Overall rank
    DENSE_RANK() OVER (ORDER BY o.TotalAmount DESC) AS OverallAmountRank,
    -- Comparison to first order
    FIRST_VALUE(o.TotalAmount) OVER (PARTITION BY c.CustomerID ORDER BY o.OrderDate) AS FirstOrderAmount,
    -- Percentage of customer total
    o.TotalAmount * 100.0 / SUM(o.TotalAmount) OVER (PARTITION BY c.CustomerID) AS PctOfCustomerTotal
FROM dbo.Customers c
INNER JOIN dbo.Orders o ON c.CustomerID = o.CustomerID;
GO
