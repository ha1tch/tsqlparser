-- Sample 182: UPDATE Statement Patterns
-- Category: DML / Syntax Coverage
-- Complexity: Complex
-- Purpose: Parser testing - UPDATE syntax variations
-- Features: All UPDATE variations, FROM clause, OUTPUT, JOINs

-- Pattern 1: Basic UPDATE
UPDATE dbo.Customers
SET ModifiedDate = GETDATE();
GO

-- Pattern 2: UPDATE with WHERE
UPDATE dbo.Customers
SET IsActive = 0
WHERE LastLoginDate < DATEADD(YEAR, -1, GETDATE());
GO

-- Pattern 3: UPDATE multiple columns
UPDATE dbo.Customers
SET 
    CustomerName = 'Updated Name',
    Email = 'updated@example.com',
    Phone = '555-0000',
    ModifiedDate = GETDATE(),
    ModifiedBy = SUSER_SNAME();
GO

-- Pattern 4: UPDATE with expression
UPDATE dbo.Products
SET 
    Price = Price * 1.10,
    StockQuantity = StockQuantity - 5,
    LastUpdated = GETDATE();
GO

-- Pattern 5: UPDATE with CASE
UPDATE dbo.Products
SET Price = CASE 
    WHEN CategoryID = 1 THEN Price * 1.15
    WHEN CategoryID = 2 THEN Price * 1.10
    WHEN CategoryID = 3 THEN Price * 1.05
    ELSE Price
END;
GO

-- Pattern 6: UPDATE with subquery
UPDATE dbo.Customers
SET TotalOrders = (
    SELECT COUNT(*) 
    FROM dbo.Orders 
    WHERE Orders.CustomerID = Customers.CustomerID
);
GO

-- Pattern 7: UPDATE with correlated subquery
UPDATE dbo.Products
SET AverageRating = (
    SELECT AVG(Rating)
    FROM dbo.Reviews r
    WHERE r.ProductID = Products.ProductID
);
GO

-- Pattern 8: UPDATE with FROM clause
UPDATE c
SET c.TotalSpent = o.TotalAmount
FROM dbo.Customers c
INNER JOIN (
    SELECT CustomerID, SUM(TotalAmount) AS TotalAmount
    FROM dbo.Orders
    GROUP BY CustomerID
) o ON c.CustomerID = o.CustomerID;
GO

-- Pattern 9: UPDATE with multiple JOINs
UPDATE od
SET od.UnitPrice = p.Price,
    od.Discount = CASE WHEN c.CustomerTier = 'Gold' THEN 0.10 ELSE 0 END
FROM dbo.OrderDetails od
INNER JOIN dbo.Orders o ON od.OrderID = o.OrderID
INNER JOIN dbo.Customers c ON o.CustomerID = c.CustomerID
INNER JOIN dbo.Products p ON od.ProductID = p.ProductID;
GO

-- Pattern 10: UPDATE with LEFT JOIN
UPDATE c
SET c.HasOrders = CASE WHEN o.CustomerID IS NOT NULL THEN 1 ELSE 0 END
FROM dbo.Customers c
LEFT JOIN dbo.Orders o ON c.CustomerID = o.CustomerID;
GO

-- Pattern 11: UPDATE with OUTPUT clause
DECLARE @Updated TABLE (CustomerID INT, OldEmail VARCHAR(200), NewEmail VARCHAR(200));

UPDATE dbo.Customers
SET Email = LOWER(Email)
OUTPUT inserted.CustomerID, deleted.Email, inserted.Email
INTO @Updated
WHERE Email <> LOWER(Email);

SELECT * FROM @Updated;
GO

-- Pattern 12: UPDATE with OUTPUT to table
UPDATE dbo.Products
SET Price = Price * 1.05
OUTPUT 
    deleted.ProductID,
    deleted.Price AS OldPrice,
    inserted.Price AS NewPrice,
    'Price Update' AS ChangeType,
    GETDATE() AS ChangeDate
INTO dbo.PriceChangeLog;
GO

-- Pattern 13: UPDATE TOP
UPDATE TOP (100) dbo.Orders
SET Status = 'Processed'
WHERE Status = 'Pending'
  AND OrderDate < DATEADD(DAY, -7, GETDATE());
GO

-- Pattern 14: UPDATE TOP with ORDER BY (via CTE)
WITH OrdersToUpdate AS (
    SELECT TOP 100 *
    FROM dbo.Orders
    WHERE Status = 'Pending'
    ORDER BY OrderDate
)
UPDATE OrdersToUpdate
SET Status = 'Processing';
GO

-- Pattern 15: UPDATE with CTE
WITH CustomerStats AS (
    SELECT 
        CustomerID,
        COUNT(*) AS OrderCount,
        SUM(TotalAmount) AS TotalSpent
    FROM dbo.Orders
    GROUP BY CustomerID
)
UPDATE c
SET 
    c.OrderCount = cs.OrderCount,
    c.TotalSpent = cs.TotalSpent
FROM dbo.Customers c
INNER JOIN CustomerStats cs ON c.CustomerID = cs.CustomerID;
GO

-- Pattern 16: UPDATE with table variable
DECLARE @Updates TABLE (ProductID INT, NewPrice DECIMAL(10,2));
INSERT INTO @Updates VALUES (1, 19.99), (2, 29.99), (3, 39.99);

UPDATE p
SET p.Price = u.NewPrice
FROM dbo.Products p
INNER JOIN @Updates u ON p.ProductID = u.ProductID;
GO

-- Pattern 17: UPDATE with CROSS APPLY
UPDATE c
SET c.LastOrderDate = recent.OrderDate,
    c.LastOrderAmount = recent.TotalAmount
FROM dbo.Customers c
CROSS APPLY (
    SELECT TOP 1 OrderDate, TotalAmount
    FROM dbo.Orders o
    WHERE o.CustomerID = c.CustomerID
    ORDER BY OrderDate DESC
) AS recent;
GO

-- Pattern 18: UPDATE column from itself
UPDATE dbo.Products
SET ProductName = UPPER(LEFT(ProductName, 1)) + LOWER(SUBSTRING(ProductName, 2, LEN(ProductName)));
GO

-- Pattern 19: UPDATE with NULL handling
UPDATE dbo.Customers
SET 
    Phone = NULLIF(Phone, ''),
    Fax = NULLIF(Fax, ''),
    Email = COALESCE(Email, AlternateEmail, 'no-email@example.com');
GO

-- Pattern 20: UPDATE with hints
UPDATE dbo.LargeTable WITH (TABLOCK)
SET ProcessedDate = GETDATE()
WHERE ProcessedDate IS NULL;
GO

-- Pattern 21: UPDATE through view
UPDATE dbo.ActiveCustomersView
SET Email = 'updated@example.com'
WHERE CustomerID = 1;
GO

-- Pattern 22: UPDATE with MERGE alternative
UPDATE target
SET 
    target.Value = source.Value,
    target.UpdatedDate = GETDATE()
FROM dbo.TargetTable target
INNER JOIN dbo.SourceTable source ON target.ID = source.ID
WHERE target.Value <> source.Value;
GO

-- Pattern 23: UPDATE in transaction with error handling
BEGIN TRY
    BEGIN TRANSACTION;
    
    UPDATE dbo.Inventory
    SET Quantity = Quantity - @OrderedQuantity
    WHERE ProductID = @ProductID
      AND Quantity >= @OrderedQuantity;
    
    IF @@ROWCOUNT = 0
        THROW 50001, 'Insufficient inventory', 1;
    
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH
GO

-- Pattern 24: UPDATE with computed values
UPDATE dbo.OrderDetails
SET 
    LineTotal = Quantity * UnitPrice * (1 - Discount),
    TaxAmount = Quantity * UnitPrice * (1 - Discount) * 0.08;
GO

-- Pattern 25: Conditional UPDATE with EXISTS
UPDATE dbo.Products
SET InStock = CASE 
    WHEN EXISTS (
        SELECT 1 FROM dbo.Inventory i 
        WHERE i.ProductID = Products.ProductID AND i.Quantity > 0
    ) THEN 1 
    ELSE 0 
END;
GO
