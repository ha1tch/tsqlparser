-- Sample 124: WITHIN GROUP Clause and Ordered Set Functions
-- Category: Missing Syntax Elements
-- Complexity: Complex
-- Purpose: Parser testing - WITHIN GROUP syntax for ordered aggregates
-- Features: STRING_AGG, PERCENTILE_CONT, PERCENTILE_DISC, ordered set functions

-- Pattern 1: STRING_AGG with WITHIN GROUP
SELECT 
    DepartmentID,
    STRING_AGG(EmployeeName, ', ') WITHIN GROUP (ORDER BY EmployeeName) AS EmployeeList
FROM Employees
GROUP BY DepartmentID;
GO

-- Pattern 2: STRING_AGG with ORDER BY DESC
SELECT 
    CategoryID,
    STRING_AGG(ProductName, '; ') WITHIN GROUP (ORDER BY ProductName DESC) AS ProductsDescending
FROM Products
GROUP BY CategoryID;
GO

-- Pattern 3: STRING_AGG with multiple ORDER BY columns
SELECT 
    Region,
    STRING_AGG(CustomerName, ' | ') WITHIN GROUP (ORDER BY Country, City, CustomerName) AS CustomerList
FROM Customers
GROUP BY Region;
GO

-- Pattern 4: STRING_AGG with expression in ORDER BY
SELECT 
    OrderID,
    STRING_AGG(ProductName, ', ') WITHIN GROUP (ORDER BY Quantity * UnitPrice DESC) AS ProductsByValue
FROM OrderDetails od
INNER JOIN Products p ON od.ProductID = p.ProductID
GROUP BY OrderID;
GO

-- Pattern 5: PERCENTILE_CONT with WITHIN GROUP (window function style)
SELECT 
    DepartmentID,
    EmployeeName,
    Salary,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Salary) OVER (PARTITION BY DepartmentID) AS MedianSalary,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY Salary) OVER (PARTITION BY DepartmentID) AS Q1Salary,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY Salary) OVER (PARTITION BY DepartmentID) AS Q3Salary
FROM Employees;
GO

-- Pattern 6: PERCENTILE_DISC vs PERCENTILE_CONT
SELECT 
    DepartmentID,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Salary) OVER (PARTITION BY DepartmentID) AS MedianContinuous,
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY Salary) OVER (PARTITION BY DepartmentID) AS MedianDiscrete
FROM Employees;
GO

-- Pattern 7: Multiple percentiles in one query
SELECT DISTINCT
    DepartmentID,
    PERCENTILE_CONT(0.10) WITHIN GROUP (ORDER BY Salary) OVER (PARTITION BY DepartmentID) AS P10,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY Salary) OVER (PARTITION BY DepartmentID) AS P25,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY Salary) OVER (PARTITION BY DepartmentID) AS P50,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY Salary) OVER (PARTITION BY DepartmentID) AS P75,
    PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY Salary) OVER (PARTITION BY DepartmentID) AS P90,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY Salary) OVER (PARTITION BY DepartmentID) AS P99
FROM Employees;
GO

-- Pattern 8: STRING_AGG without WITHIN GROUP (default ordering)
SELECT 
    CategoryID,
    STRING_AGG(ProductName, ', ') AS ProductList  -- No guaranteed order
FROM Products
GROUP BY CategoryID;
GO

-- Pattern 9: STRING_AGG with CAST for non-string columns
SELECT 
    CustomerID,
    STRING_AGG(CAST(OrderID AS VARCHAR(10)), ',') WITHIN GROUP (ORDER BY OrderDate) AS OrderIDs,
    STRING_AGG(CONVERT(VARCHAR(10), OrderDate, 120), ' | ') WITHIN GROUP (ORDER BY OrderDate) AS OrderDates
FROM Orders
GROUP BY CustomerID;
GO

-- Pattern 10: STRING_AGG with NULL handling
SELECT 
    DepartmentID,
    STRING_AGG(COALESCE(MiddleName, '(none)'), ', ') WITHIN GROUP (ORDER BY LastName) AS MiddleNames,
    STRING_AGG(MiddleName, ', ') WITHIN GROUP (ORDER BY LastName) AS MiddleNamesWithNulls  -- NULLs excluded
FROM Employees
GROUP BY DepartmentID;
GO

-- Pattern 11: PERCENTILE_CONT/DISC as aggregate (non-window)
-- Note: In SQL Server, these require OVER clause, but some databases allow pure aggregate
-- This pattern shows the window function form with entire table as partition
SELECT DISTINCT
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Salary) OVER () AS CompanyMedianSalary,
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY Salary) OVER () AS CompanyMedianSalaryDisc
FROM Employees;
GO

-- Pattern 12: Combining STRING_AGG with other aggregates
SELECT 
    DepartmentID,
    COUNT(*) AS EmployeeCount,
    AVG(Salary) AS AvgSalary,
    STRING_AGG(EmployeeName, ', ') WITHIN GROUP (ORDER BY HireDate) AS EmployeesByTenure,
    MIN(HireDate) AS FirstHire,
    MAX(HireDate) AS LastHire
FROM Employees
GROUP BY DepartmentID;
GO

-- Pattern 13: STRING_AGG with TOP in subquery
SELECT 
    CategoryID,
    (
        SELECT STRING_AGG(ProductName, ', ') WITHIN GROUP (ORDER BY Price DESC)
        FROM (SELECT TOP 5 ProductName, Price FROM Products p WHERE p.CategoryID = c.CategoryID ORDER BY Price DESC) AS TopProducts
    ) AS Top5Products
FROM Categories c;
GO

-- Pattern 14: Nested STRING_AGG (via subquery)
SELECT 
    Region,
    STRING_AGG(DeptSummary, ' || ') WITHIN GROUP (ORDER BY DepartmentName) AS RegionSummary
FROM (
    SELECT 
        Region,
        DepartmentName,
        DepartmentName + ': ' + STRING_AGG(EmployeeName, ', ') WITHIN GROUP (ORDER BY EmployeeName) AS DeptSummary
    FROM Employees
    GROUP BY Region, DepartmentName
) AS DeptAgg
GROUP BY Region;
GO

-- Pattern 15: STRING_AGG with DISTINCT (via CTE)
;WITH DistinctValues AS (
    SELECT DISTINCT DepartmentID, JobTitle
    FROM Employees
)
SELECT 
    DepartmentID,
    STRING_AGG(JobTitle, ', ') WITHIN GROUP (ORDER BY JobTitle) AS UniqueJobTitles
FROM DistinctValues
GROUP BY DepartmentID;
GO

-- Pattern 16: PERCENTILE with datetime
SELECT DISTINCT
    DepartmentID,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY HireDate) OVER (PARTITION BY DepartmentID) AS MedianHireDate
FROM Employees;
GO

-- Pattern 17: Complex ORDER BY in WITHIN GROUP
SELECT 
    Region,
    STRING_AGG(
        CustomerName + ' (' + CAST(TotalOrders AS VARCHAR(10)) + ' orders)', 
        '; '
    ) WITHIN GROUP (ORDER BY TotalOrders DESC, CustomerName ASC) AS CustomerRanking
FROM (
    SELECT Region, CustomerName, COUNT(*) AS TotalOrders
    FROM Customers c
    INNER JOIN Orders o ON c.CustomerID = o.CustomerID
    GROUP BY Region, CustomerName
) AS CustomerStats
GROUP BY Region;
GO

-- Pattern 18: STRING_AGG with separator expression
DECLARE @Separator NVARCHAR(10) = ' | ';

SELECT 
    CategoryID,
    STRING_AGG(ProductName, @Separator) WITHIN GROUP (ORDER BY ProductName) AS ProductList
FROM Products
GROUP BY CategoryID;
GO
