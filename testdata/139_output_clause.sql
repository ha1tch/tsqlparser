-- Sample 139: OUTPUT Clause in DML Statements
-- Category: Missing Syntax Elements / Advanced DML
-- Complexity: Complex
-- Purpose: Parser testing - OUTPUT clause variations
-- Features: OUTPUT, OUTPUT INTO, inserted/deleted pseudo-tables

-- Pattern 1: Basic INSERT with OUTPUT
INSERT INTO dbo.Products (ProductName, CategoryID, Price)
OUTPUT inserted.ProductID, inserted.ProductName, inserted.Price
VALUES ('New Product', 1, 29.99);
GO

-- Pattern 2: INSERT with OUTPUT INTO table variable
DECLARE @InsertedProducts TABLE (
    ProductID INT,
    ProductName NVARCHAR(100),
    InsertedAt DATETIME DEFAULT GETDATE()
);

INSERT INTO dbo.Products (ProductName, CategoryID, Price)
OUTPUT inserted.ProductID, inserted.ProductName INTO @InsertedProducts(ProductID, ProductName)
VALUES 
    ('Product A', 1, 19.99),
    ('Product B', 1, 29.99),
    ('Product C', 2, 39.99);

SELECT * FROM @InsertedProducts;
GO

-- Pattern 3: UPDATE with OUTPUT showing before and after
UPDATE dbo.Products
SET Price = Price * 1.10
OUTPUT 
    deleted.ProductID,
    deleted.ProductName,
    deleted.Price AS OldPrice,
    inserted.Price AS NewPrice,
    inserted.Price - deleted.Price AS PriceIncrease
WHERE CategoryID = 1;
GO

-- Pattern 4: UPDATE with OUTPUT INTO
DECLARE @PriceChanges TABLE (
    ProductID INT,
    ProductName NVARCHAR(100),
    OldPrice DECIMAL(10,2),
    NewPrice DECIMAL(10,2),
    ChangeDate DATETIME DEFAULT GETDATE()
);

UPDATE dbo.Products
SET Price = Price * 0.90  -- 10% discount
OUTPUT 
    deleted.ProductID,
    deleted.ProductName,
    deleted.Price,
    inserted.Price
INTO @PriceChanges(ProductID, ProductName, OldPrice, NewPrice)
WHERE Price > 100;

SELECT * FROM @PriceChanges;
GO

-- Pattern 5: DELETE with OUTPUT
DELETE FROM dbo.Products
OUTPUT 
    deleted.ProductID,
    deleted.ProductName,
    deleted.Price,
    GETDATE() AS DeletedAt
WHERE IsDiscontinued = 1;
GO

-- Pattern 6: DELETE with OUTPUT INTO
DECLARE @DeletedProducts TABLE (
    ProductID INT,
    ProductName NVARCHAR(100),
    Price DECIMAL(10,2),
    DeleteReason NVARCHAR(50)
);

DELETE FROM dbo.Products
OUTPUT 
    deleted.ProductID,
    deleted.ProductName,
    deleted.Price,
    'Low Stock' AS DeleteReason
INTO @DeletedProducts
WHERE StockQuantity = 0;

SELECT * FROM @DeletedProducts;
GO

-- Pattern 7: MERGE with OUTPUT
DECLARE @MergeOutput TABLE (
    Action NVARCHAR(10),
    ProductID INT,
    ProductName NVARCHAR(100),
    OldPrice DECIMAL(10,2),
    NewPrice DECIMAL(10,2)
);

MERGE INTO dbo.Products AS target
USING dbo.StagingProducts AS source
ON target.ProductCode = source.ProductCode
WHEN MATCHED THEN
    UPDATE SET 
        target.ProductName = source.ProductName,
        target.Price = source.Price
WHEN NOT MATCHED BY TARGET THEN
    INSERT (ProductCode, ProductName, CategoryID, Price)
    VALUES (source.ProductCode, source.ProductName, source.CategoryID, source.Price)
WHEN NOT MATCHED BY SOURCE THEN
    DELETE
OUTPUT 
    $action,
    COALESCE(inserted.ProductID, deleted.ProductID),
    COALESCE(inserted.ProductName, deleted.ProductName),
    deleted.Price,
    inserted.Price
INTO @MergeOutput;

SELECT * FROM @MergeOutput;
GO

-- Pattern 8: OUTPUT with computed columns
INSERT INTO dbo.Orders (CustomerID, OrderDate, Status)
OUTPUT 
    inserted.OrderID,
    inserted.CustomerID,
    inserted.OrderDate,
    'Order #' + CAST(inserted.OrderID AS VARCHAR(10)) AS OrderReference,
    DATEDIFF(DAY, inserted.OrderDate, GETDATE()) AS DaysOld
VALUES (1, GETDATE(), 'New');
GO

-- Pattern 9: OUTPUT with JOIN in UPDATE
UPDATE o
SET o.Status = 'VIP Order'
OUTPUT 
    deleted.OrderID,
    deleted.Status AS OldStatus,
    inserted.Status AS NewStatus,
    c.CustomerName
FROM dbo.Orders o
INNER JOIN dbo.Customers c ON o.CustomerID = c.CustomerID
WHERE c.CustomerType = 'VIP';
GO

-- Pattern 10: OUTPUT INTO permanent table (audit trail)
CREATE TABLE dbo.ProductAudit (
    AuditID INT IDENTITY(1,1) PRIMARY KEY,
    ProductID INT,
    Action NVARCHAR(10),
    OldValue NVARCHAR(MAX),
    NewValue NVARCHAR(MAX),
    AuditDate DATETIME DEFAULT GETDATE(),
    AuditUser NVARCHAR(128) DEFAULT SUSER_SNAME()
);
GO

UPDATE dbo.Products
SET Price = Price * 1.05
OUTPUT 
    deleted.ProductID,
    'UPDATE',
    CAST(deleted.Price AS NVARCHAR(MAX)),
    CAST(inserted.Price AS NVARCHAR(MAX)),
    GETDATE(),
    SUSER_SNAME()
INTO dbo.ProductAudit(ProductID, Action, OldValue, NewValue, AuditDate, AuditUser)
WHERE CategoryID = 2;
GO

-- Pattern 11: OUTPUT with subquery in INSERT
INSERT INTO dbo.OrderArchive (OrderID, CustomerID, OrderDate, TotalAmount)
OUTPUT inserted.OrderID, inserted.TotalAmount, 'Archived' AS Status
SELECT OrderID, CustomerID, OrderDate, TotalAmount
FROM dbo.Orders
WHERE OrderDate < DATEADD(YEAR, -2, GETDATE());
GO

-- Pattern 12: Chained OUTPUT (INSERT from DELETE)
INSERT INTO dbo.DeletedCustomers (CustomerID, CustomerName, DeletedDate)
OUTPUT inserted.CustomerID, inserted.CustomerName, inserted.DeletedDate
SELECT CustomerID, CustomerName, GETDATE()
FROM (
    DELETE FROM dbo.Customers
    OUTPUT deleted.CustomerID, deleted.CustomerName
    WHERE IsActive = 0 AND LastOrderDate < DATEADD(YEAR, -5, GETDATE())
) AS d;
GO

-- Pattern 13: OUTPUT with CASE expressions
UPDATE dbo.Products
SET StockStatus = CASE 
    WHEN StockQuantity = 0 THEN 'Out of Stock'
    WHEN StockQuantity < ReorderLevel THEN 'Low Stock'
    ELSE 'In Stock'
END
OUTPUT
    inserted.ProductID,
    inserted.ProductName,
    deleted.StockStatus AS OldStatus,
    inserted.StockStatus AS NewStatus,
    CASE 
        WHEN deleted.StockStatus <> inserted.StockStatus THEN 'Changed'
        ELSE 'No Change'
    END AS StatusChange
WHERE 1=1;
GO

-- Pattern 14: OUTPUT all columns with *
INSERT INTO dbo.Products (ProductName, CategoryID, Price, StockQuantity)
OUTPUT inserted.*
VALUES ('Complete Product', 1, 49.99, 100);
GO

DELETE FROM dbo.TempProducts
OUTPUT deleted.*;
GO

-- Pattern 15: OUTPUT with table alias
UPDATE p
SET p.Price = p.Price * 1.1
OUTPUT 
    deleted.ProductID AS ID,
    deleted.Price AS [Old Price],
    inserted.Price AS [New Price]
FROM dbo.Products AS p
WHERE p.CategoryID = 3;
GO

-- Pattern 16: Multiple OUTPUT INTO from single statement (not directly possible, but pattern)
DECLARE @Inserted TABLE (ProductID INT, ProductName NVARCHAR(100));
DECLARE @Summary TABLE (TotalInserted INT, AvgPrice DECIMAL(10,2));

INSERT INTO dbo.Products (ProductName, CategoryID, Price)
OUTPUT inserted.ProductID, inserted.ProductName INTO @Inserted
VALUES ('Product X', 1, 99.99);

INSERT INTO @Summary
SELECT COUNT(*), AVG(Price) FROM @Inserted i
INNER JOIN dbo.Products p ON i.ProductID = p.ProductID;
GO

-- Pattern 17: OUTPUT with IDENTITY column
CREATE TABLE #TempOrders (
    TempID INT IDENTITY(1,1),
    OrderID INT,
    CustomerID INT
);

INSERT INTO dbo.Orders (CustomerID, OrderDate)
OUTPUT inserted.OrderID, inserted.CustomerID INTO #TempOrders(OrderID, CustomerID)
SELECT CustomerID, GETDATE()
FROM dbo.Customers
WHERE IsActive = 1;

SELECT * FROM #TempOrders;
DROP TABLE #TempOrders;
GO

-- Pattern 18: OUTPUT in stored procedure
CREATE PROCEDURE dbo.InsertProductWithAudit
    @ProductName NVARCHAR(100),
    @CategoryID INT,
    @Price DECIMAL(10,2),
    @NewProductID INT OUTPUT
AS
BEGIN
    DECLARE @Output TABLE (ProductID INT);
    
    INSERT INTO dbo.Products (ProductName, CategoryID, Price)
    OUTPUT inserted.ProductID INTO @Output
    VALUES (@ProductName, @CategoryID, @Price);
    
    SELECT @NewProductID = ProductID FROM @Output;
    
    -- Return the inserted row
    SELECT * FROM dbo.Products WHERE ProductID = @NewProductID;
END;
GO

-- Cleanup
DROP TABLE IF EXISTS dbo.ProductAudit;
DROP PROCEDURE IF EXISTS dbo.InsertProductWithAudit;
GO
