-- Sample 184: MERGE Statement Patterns
-- Category: DML / Syntax Coverage
-- Complexity: Advanced
-- Purpose: Parser testing - MERGE syntax variations
-- Features: MATCHED, NOT MATCHED, OUTPUT, conditions

-- Pattern 1: Basic MERGE
MERGE INTO dbo.TargetTable AS target
USING dbo.SourceTable AS source
ON target.ID = source.ID
WHEN MATCHED THEN
    UPDATE SET target.Value = source.Value
WHEN NOT MATCHED THEN
    INSERT (ID, Value) VALUES (source.ID, source.Value);
GO

-- Pattern 2: MERGE with all clauses
MERGE INTO dbo.Products AS target
USING dbo.StagingProducts AS source
ON target.ProductID = source.ProductID
WHEN MATCHED THEN
    UPDATE SET 
        target.ProductName = source.ProductName,
        target.Price = source.Price,
        target.ModifiedDate = GETDATE()
WHEN NOT MATCHED BY TARGET THEN
    INSERT (ProductID, ProductName, Price, CreatedDate)
    VALUES (source.ProductID, source.ProductName, source.Price, GETDATE())
WHEN NOT MATCHED BY SOURCE THEN
    DELETE;
GO

-- Pattern 3: MERGE with conditions on MATCHED
MERGE INTO dbo.Inventory AS target
USING dbo.InventoryUpdates AS source
ON target.ProductID = source.ProductID
WHEN MATCHED AND source.Quantity = 0 THEN
    DELETE
WHEN MATCHED AND source.Quantity > 0 THEN
    UPDATE SET target.Quantity = source.Quantity
WHEN NOT MATCHED THEN
    INSERT (ProductID, Quantity) VALUES (source.ProductID, source.Quantity);
GO

-- Pattern 4: MERGE with multiple MATCHED conditions
MERGE INTO dbo.Customers AS target
USING dbo.CustomerUpdates AS source
ON target.CustomerID = source.CustomerID
WHEN MATCHED AND target.ModifiedDate < source.ModifiedDate THEN
    UPDATE SET 
        target.CustomerName = source.CustomerName,
        target.Email = source.Email,
        target.ModifiedDate = source.ModifiedDate
WHEN MATCHED AND target.ModifiedDate >= source.ModifiedDate THEN
    UPDATE SET target.LastChecked = GETDATE()
WHEN NOT MATCHED THEN
    INSERT (CustomerID, CustomerName, Email, CreatedDate)
    VALUES (source.CustomerID, source.CustomerName, source.Email, GETDATE());
GO

-- Pattern 5: MERGE with derived table source
MERGE INTO dbo.ProductPrices AS target
USING (
    SELECT ProductID, AVG(Price) AS AvgPrice
    FROM dbo.PriceHistory
    WHERE PriceDate >= DATEADD(MONTH, -3, GETDATE())
    GROUP BY ProductID
) AS source
ON target.ProductID = source.ProductID
WHEN MATCHED THEN
    UPDATE SET target.AveragePrice = source.AvgPrice
WHEN NOT MATCHED THEN
    INSERT (ProductID, AveragePrice) VALUES (source.ProductID, source.AvgPrice);
GO

-- Pattern 6: MERGE with CTE source
WITH SourceData AS (
    SELECT 
        CustomerID,
        COUNT(*) AS OrderCount,
        SUM(TotalAmount) AS TotalSpent
    FROM dbo.Orders
    GROUP BY CustomerID
)
MERGE INTO dbo.CustomerStats AS target
USING SourceData AS source
ON target.CustomerID = source.CustomerID
WHEN MATCHED THEN
    UPDATE SET 
        target.OrderCount = source.OrderCount,
        target.TotalSpent = source.TotalSpent
WHEN NOT MATCHED THEN
    INSERT (CustomerID, OrderCount, TotalSpent)
    VALUES (source.CustomerID, source.OrderCount, source.TotalSpent);
GO

-- Pattern 7: MERGE with VALUES clause
MERGE INTO dbo.Settings AS target
USING (VALUES
    ('Setting1', 'Value1'),
    ('Setting2', 'Value2'),
    ('Setting3', 'Value3')
) AS source (SettingName, SettingValue)
ON target.SettingName = source.SettingName
WHEN MATCHED THEN
    UPDATE SET target.SettingValue = source.SettingValue
WHEN NOT MATCHED THEN
    INSERT (SettingName, SettingValue) VALUES (source.SettingName, source.SettingValue);
GO

-- Pattern 8: MERGE with OUTPUT clause
DECLARE @Changes TABLE (
    Action VARCHAR(10),
    ProductID INT,
    OldPrice DECIMAL(10,2),
    NewPrice DECIMAL(10,2)
);

MERGE INTO dbo.Products AS target
USING dbo.PriceUpdates AS source
ON target.ProductID = source.ProductID
WHEN MATCHED THEN
    UPDATE SET target.Price = source.NewPrice
WHEN NOT MATCHED THEN
    INSERT (ProductID, Price) VALUES (source.ProductID, source.NewPrice)
OUTPUT 
    $action,
    COALESCE(inserted.ProductID, deleted.ProductID),
    deleted.Price,
    inserted.Price
INTO @Changes;

SELECT * FROM @Changes;
GO

-- Pattern 9: MERGE with OUTPUT to permanent table
MERGE INTO dbo.Customers AS target
USING dbo.CustomerImport AS source
ON target.Email = source.Email
WHEN MATCHED THEN
    UPDATE SET target.CustomerName = source.CustomerName
WHEN NOT MATCHED THEN
    INSERT (CustomerName, Email) VALUES (source.CustomerName, source.Email)
OUTPUT 
    $action AS ActionType,
    inserted.CustomerID,
    inserted.CustomerName,
    GETDATE() AS ProcessedDate
INTO dbo.CustomerChangeLog;
GO

-- Pattern 10: MERGE with table variable source
DECLARE @Updates TABLE (ID INT, Value VARCHAR(100));
INSERT INTO @Updates VALUES (1, 'New1'), (2, 'New2'), (3, 'New3');

MERGE INTO dbo.TargetTable AS target
USING @Updates AS source
ON target.ID = source.ID
WHEN MATCHED THEN
    UPDATE SET target.Value = source.Value
WHEN NOT MATCHED THEN
    INSERT (ID, Value) VALUES (source.ID, source.Value);
GO

-- Pattern 11: MERGE with hints
MERGE INTO dbo.LargeTarget WITH (TABLOCK) AS target
USING dbo.LargeSource AS source
ON target.ID = source.ID
WHEN MATCHED THEN
    UPDATE SET target.Value = source.Value
WHEN NOT MATCHED THEN
    INSERT (ID, Value) VALUES (source.ID, source.Value);
GO

-- Pattern 12: MERGE with TOP
MERGE TOP (1000) INTO dbo.Target AS target
USING dbo.Source AS source
ON target.ID = source.ID
WHEN MATCHED THEN
    UPDATE SET target.Value = source.Value;
GO

-- Pattern 13: MERGE with holdlock (serializable)
MERGE INTO dbo.Target WITH (HOLDLOCK) AS target
USING dbo.Source AS source
ON target.ID = source.ID
WHEN MATCHED THEN
    UPDATE SET target.Value = source.Value
WHEN NOT MATCHED THEN
    INSERT (ID, Value) VALUES (source.ID, source.Value);
GO

-- Pattern 14: MERGE for upsert pattern
CREATE PROCEDURE dbo.UpsertCustomer
    @CustomerID INT,
    @CustomerName VARCHAR(100),
    @Email VARCHAR(200)
AS
BEGIN
    MERGE INTO dbo.Customers AS target
    USING (SELECT @CustomerID, @CustomerName, @Email) AS source (CustomerID, CustomerName, Email)
    ON target.CustomerID = source.CustomerID
    WHEN MATCHED THEN
        UPDATE SET 
            CustomerName = source.CustomerName,
            Email = source.Email,
            ModifiedDate = GETDATE()
    WHEN NOT MATCHED THEN
        INSERT (CustomerID, CustomerName, Email, CreatedDate)
        VALUES (source.CustomerID, source.CustomerName, source.Email, GETDATE());
END;
GO
DROP PROCEDURE dbo.UpsertCustomer;
GO

-- Pattern 15: MERGE with complex join condition
MERGE INTO dbo.ProductInventory AS target
USING dbo.WarehouseStock AS source
ON target.ProductID = source.ProductID 
   AND target.WarehouseID = source.WarehouseID
   AND target.LocationID = source.LocationID
WHEN MATCHED THEN
    UPDATE SET target.Quantity = source.Quantity
WHEN NOT MATCHED THEN
    INSERT (ProductID, WarehouseID, LocationID, Quantity)
    VALUES (source.ProductID, source.WarehouseID, source.LocationID, source.Quantity);
GO

-- Pattern 16: MERGE semicolon requirement
-- MERGE statements MUST end with semicolon
MERGE INTO dbo.Target AS t
USING dbo.Source AS s ON t.ID = s.ID
WHEN MATCHED THEN UPDATE SET t.Val = s.Val;  -- Required semicolon
GO
