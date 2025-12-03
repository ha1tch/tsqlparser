-- Sample 183: DELETE Statement Patterns
-- Category: DML / Syntax Coverage
-- Complexity: Complex
-- Purpose: Parser testing - DELETE syntax variations
-- Features: All DELETE variations, FROM clause, OUTPUT, JOINs

-- Pattern 1: Basic DELETE all rows
DELETE FROM dbo.TempTable;
GO

-- Pattern 2: DELETE with WHERE
DELETE FROM dbo.Customers
WHERE IsActive = 0 AND LastLoginDate < '2020-01-01';
GO

-- Pattern 3: DELETE without FROM keyword
DELETE dbo.LogEntries
WHERE LogDate < DATEADD(MONTH, -6, GETDATE());
GO

-- Pattern 4: DELETE with complex WHERE
DELETE FROM dbo.Orders
WHERE Status = 'Cancelled'
  AND OrderDate < DATEADD(YEAR, -2, GETDATE())
  AND TotalAmount < 100
  AND CustomerID NOT IN (SELECT CustomerID FROM dbo.VIPCustomers);
GO

-- Pattern 5: DELETE with subquery
DELETE FROM dbo.Customers
WHERE CustomerID IN (
    SELECT CustomerID 
    FROM dbo.Customers 
    WHERE CreatedDate < '2015-01-01'
      AND CustomerID NOT IN (SELECT DISTINCT CustomerID FROM dbo.Orders)
);
GO

-- Pattern 6: DELETE with EXISTS
DELETE FROM dbo.Products
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.OrderDetails od
    WHERE od.ProductID = Products.ProductID
);
GO

-- Pattern 7: DELETE with FROM and JOIN
DELETE o
FROM dbo.Orders o
INNER JOIN dbo.Customers c ON o.CustomerID = c.CustomerID
WHERE c.IsActive = 0;
GO

-- Pattern 8: DELETE with multiple JOINs
DELETE od
FROM dbo.OrderDetails od
INNER JOIN dbo.Orders o ON od.OrderID = o.OrderID
INNER JOIN dbo.Customers c ON o.CustomerID = c.CustomerID
WHERE c.CustomerType = 'Test';
GO

-- Pattern 9: DELETE with LEFT JOIN (anti-join)
DELETE p
FROM dbo.Products p
LEFT JOIN dbo.OrderDetails od ON p.ProductID = od.ProductID
WHERE od.ProductID IS NULL;
GO

-- Pattern 10: DELETE with OUTPUT clause
DECLARE @Deleted TABLE (
    CustomerID INT,
    CustomerName VARCHAR(100),
    Email VARCHAR(200),
    DeletedDate DATETIME
);

DELETE FROM dbo.Customers
OUTPUT deleted.CustomerID, deleted.CustomerName, deleted.Email, GETDATE()
INTO @Deleted
WHERE IsActive = 0;

SELECT * FROM @Deleted;
GO

-- Pattern 11: DELETE with OUTPUT to permanent table
DELETE FROM dbo.Orders
OUTPUT 
    deleted.OrderID,
    deleted.CustomerID,
    deleted.OrderDate,
    deleted.TotalAmount,
    'Archived' AS Reason,
    GETDATE() AS ArchivedDate
INTO dbo.OrdersArchive
WHERE OrderDate < DATEADD(YEAR, -5, GETDATE());
GO

-- Pattern 12: DELETE TOP
DELETE TOP (1000) FROM dbo.LogEntries
WHERE LogDate < DATEADD(DAY, -30, GETDATE());
GO

-- Pattern 13: DELETE TOP with percentage
DELETE TOP (10) PERCENT FROM dbo.TempData;
GO

-- Pattern 14: DELETE TOP with ORDER BY (via CTE)
WITH OldestLogs AS (
    SELECT TOP 1000 *
    FROM dbo.LogEntries
    ORDER BY LogDate ASC
)
DELETE FROM OldestLogs;
GO

-- Pattern 15: DELETE with CTE
WITH DuplicateCustomers AS (
    SELECT 
        CustomerID,
        ROW_NUMBER() OVER (PARTITION BY Email ORDER BY CreatedDate) AS RowNum
    FROM dbo.Customers
)
DELETE FROM DuplicateCustomers
WHERE RowNum > 1;
GO

-- Pattern 16: DELETE with table alias
DELETE c
FROM dbo.Customers AS c
WHERE c.CustomerID NOT IN (SELECT CustomerID FROM dbo.Orders);
GO

-- Pattern 17: DELETE with CROSS APPLY
DELETE c
FROM dbo.Customers c
CROSS APPLY (
    SELECT MAX(OrderDate) AS LastOrder
    FROM dbo.Orders o
    WHERE o.CustomerID = c.CustomerID
) AS orders
WHERE orders.LastOrder < DATEADD(YEAR, -3, GETDATE());
GO

-- Pattern 18: DELETE with hint
DELETE FROM dbo.LargeTable WITH (TABLOCK)
WHERE ProcessedFlag = 1;
GO

-- Pattern 19: DELETE through view
DELETE FROM dbo.InactiveCustomersView
WHERE CustomerID = 123;
GO

-- Pattern 20: DELETE in batches (loop pattern)
DECLARE @BatchSize INT = 10000;
DECLARE @RowsDeleted INT = 1;

WHILE @RowsDeleted > 0
BEGIN
    DELETE TOP (@BatchSize) FROM dbo.LargeLogTable
    WHERE LogDate < DATEADD(MONTH, -12, GETDATE());
    
    SET @RowsDeleted = @@ROWCOUNT;
    
    -- Optional: Add delay to reduce locking
    WAITFOR DELAY '00:00:01';
END
GO

-- Pattern 21: DELETE with transaction
BEGIN TRANSACTION;

DELETE FROM dbo.OrderDetails
WHERE OrderID IN (SELECT OrderID FROM dbo.Orders WHERE CustomerID = @CustomerID);

DELETE FROM dbo.Orders
WHERE CustomerID = @CustomerID;

DELETE FROM dbo.Customers
WHERE CustomerID = @CustomerID;

COMMIT TRANSACTION;
GO

-- Pattern 22: DELETE with error handling
BEGIN TRY
    BEGIN TRANSACTION;
    
    DELETE FROM dbo.Customers
    WHERE CustomerID = @CustomerID;
    
    IF @@ROWCOUNT = 0
        THROW 50001, 'Customer not found', 1;
    
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH
GO

-- Pattern 23: TRUNCATE TABLE (faster than DELETE all)
TRUNCATE TABLE dbo.TempTable;
GO

-- Pattern 24: TRUNCATE with partition (SQL Server 2016+)
TRUNCATE TABLE dbo.PartitionedTable
WITH (PARTITIONS (1, 2, 3));

TRUNCATE TABLE dbo.PartitionedTable
WITH (PARTITIONS (5 TO 10));
GO

-- Pattern 25: DELETE vs TRUNCATE comparison
-- DELETE: Logged, can have WHERE, triggers fire, can rollback
DELETE FROM dbo.Table1;

-- TRUNCATE: Minimally logged, no WHERE, no triggers, resets identity
TRUNCATE TABLE dbo.Table2;
GO
