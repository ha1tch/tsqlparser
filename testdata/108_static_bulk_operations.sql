-- Sample 108: Static Bulk Operations
-- Category: Static SQL Equivalents
-- Complexity: Complex
-- Purpose: Parser testing - bulk DML without dynamic SQL
-- Features: Multi-row INSERT, UPDATE from JOIN, DELETE with subquery, MERGE

-- Pattern 1: Multi-row INSERT with VALUES
INSERT INTO dbo.Products (ProductID, ProductName, CategoryID, Price, StockQuantity, IsActive)
VALUES 
    (1001, 'Widget A', 1, 19.99, 100, 1),
    (1002, 'Widget B', 1, 24.99, 150, 1),
    (1003, 'Widget C', 1, 29.99, 200, 1),
    (1004, 'Gadget X', 2, 49.99, 75, 1),
    (1005, 'Gadget Y', 2, 59.99, 50, 1),
    (1006, 'Gadget Z', 2, 69.99, 25, 1),
    (1007, 'Tool 1', 3, 9.99, 500, 1),
    (1008, 'Tool 2', 3, 14.99, 300, 1),
    (1009, 'Tool 3', 3, 19.99, 200, 1),
    (1010, 'Accessory Alpha', 4, 4.99, 1000, 1);
GO

-- Pattern 2: INSERT from SELECT
INSERT INTO dbo.ProductArchive (ProductID, ProductName, CategoryID, Price, ArchivedDate, ArchivedBy)
SELECT 
    ProductID,
    ProductName,
    CategoryID,
    Price,
    GETDATE(),
    SUSER_SNAME()
FROM dbo.Products
WHERE IsActive = 0
  AND LastModifiedDate < DATEADD(YEAR, -1, GETDATE())
  AND ProductID NOT IN (SELECT ProductID FROM dbo.ProductArchive);
GO

-- Pattern 3: INSERT with OUTPUT clause
INSERT INTO dbo.AuditLog (TableName, ActionType, RecordID, ActionDate, ActionBy)
OUTPUT inserted.LogID, inserted.TableName, inserted.RecordID
SELECT 
    'Products' AS TableName,
    'ARCHIVE' AS ActionType,
    ProductID,
    GETDATE(),
    SUSER_SNAME()
FROM dbo.Products
WHERE IsActive = 0;
GO

-- Pattern 4: UPDATE with JOIN
UPDATE p
SET 
    p.Price = p.Price * (1 + pa.PriceAdjustmentPercent / 100.0),
    p.LastModifiedDate = GETDATE(),
    p.LastModifiedBy = SUSER_SNAME()
FROM dbo.Products p
INNER JOIN dbo.PriceAdjustments pa ON p.CategoryID = pa.CategoryID
WHERE pa.EffectiveDate <= GETDATE()
  AND pa.ExpirationDate >= GETDATE()
  AND p.IsActive = 1;
GO

-- Pattern 5: UPDATE with subquery
UPDATE dbo.Customers
SET 
    CustomerTier = CASE 
        WHEN TotalSpent >= 10000 THEN 'Platinum'
        WHEN TotalSpent >= 5000 THEN 'Gold'
        WHEN TotalSpent >= 1000 THEN 'Silver'
        ELSE 'Bronze'
    END,
    TotalSpent = (
        SELECT COALESCE(SUM(TotalAmount), 0)
        FROM dbo.Orders o
        WHERE o.CustomerID = Customers.CustomerID
        AND o.Status = 'Completed'
    ),
    OrderCount = (
        SELECT COUNT(*)
        FROM dbo.Orders o
        WHERE o.CustomerID = Customers.CustomerID
        AND o.Status = 'Completed'
    ),
    LastOrderDate = (
        SELECT MAX(OrderDate)
        FROM dbo.Orders o
        WHERE o.CustomerID = Customers.CustomerID
    ),
    LastUpdated = GETDATE()
WHERE IsActive = 1;
GO

-- Pattern 6: UPDATE with CTE
;WITH CustomerStats AS (
    SELECT 
        CustomerID,
        COUNT(*) AS OrderCount,
        SUM(TotalAmount) AS TotalSpent,
        MAX(OrderDate) AS LastOrderDate,
        AVG(TotalAmount) AS AvgOrderValue
    FROM dbo.Orders
    WHERE Status = 'Completed'
    GROUP BY CustomerID
)
UPDATE c
SET 
    c.OrderCount = cs.OrderCount,
    c.TotalSpent = cs.TotalSpent,
    c.LastOrderDate = cs.LastOrderDate,
    c.AvgOrderValue = cs.AvgOrderValue,
    c.LastUpdated = GETDATE()
FROM dbo.Customers c
INNER JOIN CustomerStats cs ON c.CustomerID = cs.CustomerID;
GO

-- Pattern 7: DELETE with JOIN
DELETE od
FROM dbo.OrderDetails od
INNER JOIN dbo.Orders o ON od.OrderID = o.OrderID
WHERE o.Status = 'Cancelled'
  AND o.OrderDate < DATEADD(YEAR, -2, GETDATE());
GO

-- Pattern 8: DELETE with subquery and TOP
DELETE TOP (1000)
FROM dbo.EventLog
WHERE EventDate < DATEADD(MONTH, -6, GETDATE())
  AND EventID NOT IN (
      SELECT TOP 100 EventID
      FROM dbo.EventLog
      WHERE Severity = 'Critical'
      ORDER BY EventDate DESC
  );
GO

-- Pattern 9: DELETE with OUTPUT
DELETE FROM dbo.ExpiredSessions
OUTPUT 
    deleted.SessionID,
    deleted.UserID,
    deleted.ExpirationDate,
    GETDATE() AS DeletedAt
INTO dbo.SessionArchive (SessionID, UserID, OriginalExpiration, ArchivedDate)
WHERE ExpirationDate < DATEADD(DAY, -30, GETDATE());
GO

-- Pattern 10: MERGE with all clauses
MERGE INTO dbo.Products AS target
USING dbo.ProductUpdates AS source
ON target.ProductID = source.ProductID

WHEN MATCHED AND source.IsDeleted = 1 THEN
    DELETE

WHEN MATCHED AND target.Price <> source.Price 
             OR target.ProductName <> source.ProductName 
             OR target.StockQuantity <> source.StockQuantity THEN
    UPDATE SET 
        target.ProductName = source.ProductName,
        target.Price = source.Price,
        target.StockQuantity = source.StockQuantity,
        target.LastModifiedDate = GETDATE()

WHEN NOT MATCHED BY TARGET THEN
    INSERT (ProductID, ProductName, CategoryID, Price, StockQuantity, CreatedDate)
    VALUES (source.ProductID, source.ProductName, source.CategoryID, 
            source.Price, source.StockQuantity, GETDATE())

WHEN NOT MATCHED BY SOURCE AND target.IsActive = 1 THEN
    UPDATE SET target.IsActive = 0, target.LastModifiedDate = GETDATE()

OUTPUT 
    $action AS MergeAction,
    COALESCE(inserted.ProductID, deleted.ProductID) AS ProductID,
    deleted.Price AS OldPrice,
    inserted.Price AS NewPrice;
GO

-- Pattern 11: MERGE with derived source
MERGE INTO dbo.DailySalesSummary AS target
USING (
    SELECT 
        CAST(OrderDate AS DATE) AS SaleDate,
        COUNT(DISTINCT OrderID) AS OrderCount,
        COUNT(DISTINCT CustomerID) AS UniqueCustomers,
        SUM(TotalAmount) AS TotalRevenue,
        AVG(TotalAmount) AS AvgOrderValue
    FROM dbo.Orders
    WHERE OrderDate >= DATEADD(DAY, -7, GETDATE())
    AND Status = 'Completed'
    GROUP BY CAST(OrderDate AS DATE)
) AS source
ON target.SaleDate = source.SaleDate

WHEN MATCHED THEN
    UPDATE SET 
        target.OrderCount = source.OrderCount,
        target.UniqueCustomers = source.UniqueCustomers,
        target.TotalRevenue = source.TotalRevenue,
        target.AvgOrderValue = source.AvgOrderValue,
        target.LastUpdated = GETDATE()

WHEN NOT MATCHED THEN
    INSERT (SaleDate, OrderCount, UniqueCustomers, TotalRevenue, AvgOrderValue, CreatedDate)
    VALUES (source.SaleDate, source.OrderCount, source.UniqueCustomers, 
            source.TotalRevenue, source.AvgOrderValue, GETDATE());
GO

-- Pattern 12: INSERT with DEFAULT VALUES
INSERT INTO dbo.SystemLog DEFAULT VALUES;
GO

-- Pattern 13: INSERT with EXEC
INSERT INTO dbo.CustomerReport (CustomerID, ReportData, GeneratedDate)
EXEC dbo.GenerateCustomerReport @StartDate = '2024-01-01', @EndDate = '2024-12-31';
GO

-- Pattern 14: UPDATE with CASE expression
UPDATE dbo.Inventory
SET 
    StockStatus = CASE 
        WHEN QuantityOnHand = 0 THEN 'Out of Stock'
        WHEN QuantityOnHand < ReorderLevel THEN 'Low Stock'
        WHEN QuantityOnHand < ReorderLevel * 2 THEN 'Normal'
        ELSE 'Overstocked'
    END,
    ReorderRequired = CASE 
        WHEN QuantityOnHand < ReorderLevel THEN 1 
        ELSE 0 
    END,
    LastChecked = GETDATE()
WHERE IsActive = 1;
GO
