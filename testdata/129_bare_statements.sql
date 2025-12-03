-- Sample 129: Standalone SELECT Statements
-- Category: Bare Statements Without Procedures
-- Complexity: Intermediate to Complex
-- Purpose: Parser testing - statement-level parsing without procedure wrapper
-- Features: Ad-hoc queries, variable declarations, temp tables, batches

-- Bare SELECT with all common clauses
SELECT DISTINCT TOP 100
    c.CustomerID,
    c.CustomerName,
    c.Email,
    COUNT(o.OrderID) AS OrderCount,
    SUM(o.TotalAmount) AS TotalSpent,
    AVG(o.TotalAmount) AS AvgOrderValue,
    MAX(o.OrderDate) AS LastOrderDate
FROM dbo.Customers c
LEFT JOIN dbo.Orders o ON c.CustomerID = o.CustomerID
WHERE c.IsActive = 1
  AND c.CreatedDate >= '2023-01-01'
  AND (c.Region = 'North' OR c.Region = 'South')
GROUP BY c.CustomerID, c.CustomerName, c.Email
HAVING COUNT(o.OrderID) > 0
ORDER BY TotalSpent DESC, c.CustomerName ASC
OFFSET 0 ROWS
FETCH NEXT 100 ROWS ONLY;
GO

-- Simple SELECT with expression
SELECT 1 + 1 AS Sum, 10 * 5 AS Product, 100 / 4 AS Quotient, 17 % 5 AS Modulo;
GO

-- SELECT with functions
SELECT 
    GETDATE() AS CurrentDateTime,
    SYSDATETIME() AS CurrentDateTime2,
    GETUTCDATE() AS UTCDateTime,
    NEWID() AS NewGuid,
    @@VERSION AS SQLVersion,
    @@SERVERNAME AS ServerName,
    DB_NAME() AS DatabaseName,
    SUSER_SNAME() AS LoginName,
    USER_NAME() AS UserName;
GO

-- SELECT INTO (creates table)
SELECT 
    CustomerID,
    CustomerName,
    Email,
    CreatedDate
INTO #TempCustomers
FROM dbo.Customers
WHERE IsActive = 1;
GO

-- SELECT from temp table
SELECT * FROM #TempCustomers ORDER BY CustomerName;
GO

-- DROP temp table
DROP TABLE #TempCustomers;
GO

-- Variable declaration and SELECT assignment
DECLARE @CustomerCount INT;
DECLARE @TotalRevenue DECIMAL(18,2);
DECLARE @LastOrderDate DATE;

SELECT 
    @CustomerCount = COUNT(DISTINCT CustomerID),
    @TotalRevenue = SUM(TotalAmount),
    @LastOrderDate = MAX(OrderDate)
FROM dbo.Orders
WHERE YEAR(OrderDate) = 2024;

SELECT @CustomerCount AS CustomerCount, @TotalRevenue AS TotalRevenue, @LastOrderDate AS LastOrderDate;
GO

-- CTE without procedure
;WITH 
MonthlySales AS (
    SELECT 
        YEAR(OrderDate) AS Year,
        MONTH(OrderDate) AS Month,
        SUM(TotalAmount) AS Revenue
    FROM dbo.Orders
    GROUP BY YEAR(OrderDate), MONTH(OrderDate)
),
RankedMonths AS (
    SELECT 
        Year,
        Month,
        Revenue,
        RANK() OVER (PARTITION BY Year ORDER BY Revenue DESC) AS RevenueRank
    FROM MonthlySales
)
SELECT * FROM RankedMonths WHERE RevenueRank <= 3 ORDER BY Year, RevenueRank;
GO

-- Subquery in SELECT list
SELECT 
    c.CustomerID,
    c.CustomerName,
    (SELECT COUNT(*) FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID) AS OrderCount,
    (SELECT MAX(OrderDate) FROM dbo.Orders o WHERE o.CustomerID = c.CustomerID) AS LastOrder
FROM dbo.Customers c
WHERE c.IsActive = 1;
GO

-- Derived table
SELECT 
    OrderYear,
    TotalOrders,
    TotalRevenue,
    TotalRevenue / TotalOrders AS AvgOrderValue
FROM (
    SELECT 
        YEAR(OrderDate) AS OrderYear,
        COUNT(*) AS TotalOrders,
        SUM(TotalAmount) AS TotalRevenue
    FROM dbo.Orders
    GROUP BY YEAR(OrderDate)
) AS YearlySummary
ORDER BY OrderYear;
GO

-- CROSS APPLY
SELECT 
    c.CustomerID,
    c.CustomerName,
    recent.OrderID,
    recent.OrderDate,
    recent.TotalAmount
FROM dbo.Customers c
CROSS APPLY (
    SELECT TOP 3 OrderID, OrderDate, TotalAmount
    FROM dbo.Orders o
    WHERE o.CustomerID = c.CustomerID
    ORDER BY OrderDate DESC
) AS recent;
GO

-- PIVOT without procedure
SELECT * FROM (
    SELECT 
        YEAR(OrderDate) AS OrderYear,
        MONTH(OrderDate) AS OrderMonth,
        TotalAmount
    FROM dbo.Orders
) AS SourceData
PIVOT (
    SUM(TotalAmount)
    FOR OrderMonth IN ([1],[2],[3],[4],[5],[6],[7],[8],[9],[10],[11],[12])
) AS PivotTable;
GO

-- Window functions
SELECT 
    OrderID,
    CustomerID,
    OrderDate,
    TotalAmount,
    SUM(TotalAmount) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS RunningTotal,
    ROW_NUMBER() OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS OrderSequence,
    LAG(TotalAmount) OVER (PARTITION BY CustomerID ORDER BY OrderDate) AS PreviousOrderAmount
FROM dbo.Orders
WHERE YEAR(OrderDate) = 2024;
GO

-- Multiple result sets in one batch
SELECT 'Customers' AS TableName, COUNT(*) AS RowCount FROM dbo.Customers;
SELECT 'Orders' AS TableName, COUNT(*) AS RowCount FROM dbo.Orders;
SELECT 'Products' AS TableName, COUNT(*) AS RowCount FROM dbo.Products;
GO

-- SELECT with FOR XML
SELECT 
    CustomerID AS '@ID',
    CustomerName AS 'Name',
    Email AS 'Contact/Email'
FROM dbo.Customers
WHERE IsActive = 1
FOR XML PATH('Customer'), ROOT('Customers');
GO

-- SELECT with FOR JSON
SELECT 
    CustomerID,
    CustomerName,
    Email
FROM dbo.Customers
WHERE IsActive = 1
FOR JSON PATH, ROOT('Customers');
GO

-- Table variable
DECLARE @Results TABLE (
    ID INT,
    Name NVARCHAR(100),
    Value DECIMAL(18,2)
);

INSERT INTO @Results (ID, Name, Value)
SELECT ProductID, ProductName, Price FROM dbo.Products WHERE CategoryID = 1;

SELECT * FROM @Results ORDER BY Value DESC;
GO

-- MERGE as standalone statement
MERGE INTO dbo.Products AS target
USING (SELECT 1 AS ProductID, 'Updated Product' AS ProductName, 99.99 AS Price) AS source
ON target.ProductID = source.ProductID
WHEN MATCHED THEN UPDATE SET ProductName = source.ProductName, Price = source.Price
WHEN NOT MATCHED THEN INSERT (ProductID, ProductName, Price) VALUES (source.ProductID, source.ProductName, source.Price);
GO

-- IF statement without procedure
DECLARE @Count INT;
SELECT @Count = COUNT(*) FROM dbo.Orders WHERE OrderDate = CAST(GETDATE() AS DATE);

IF @Count > 0
BEGIN
    SELECT 'Orders exist for today' AS Message, @Count AS OrderCount;
END
ELSE
BEGIN
    SELECT 'No orders for today' AS Message;
END
GO

-- WHILE loop without procedure
DECLARE @i INT = 1;
DECLARE @Results TABLE (Iteration INT, Square INT);

WHILE @i <= 10
BEGIN
    INSERT INTO @Results VALUES (@i, @i * @i);
    SET @i = @i + 1;
END

SELECT * FROM @Results;
GO

-- TRY/CATCH without procedure
BEGIN TRY
    SELECT 1/0 AS WillFail;
END TRY
BEGIN CATCH
    SELECT 
        ERROR_NUMBER() AS ErrorNumber,
        ERROR_MESSAGE() AS ErrorMessage,
        ERROR_SEVERITY() AS ErrorSeverity,
        ERROR_STATE() AS ErrorState;
END CATCH
GO

-- Transaction without procedure
BEGIN TRANSACTION;
    UPDATE dbo.Products SET Price = Price * 1.1 WHERE CategoryID = 1;
    SELECT @@ROWCOUNT AS RowsUpdated;
ROLLBACK TRANSACTION;
GO
