-- Sample 201: Complete Statement Examples
-- Category: Syntax Coverage / Comprehensive
-- Complexity: Advanced
-- Purpose: Parser testing - complete real-world statement patterns
-- Features: Comprehensive real-world query and procedure examples

-- Pattern 1: Complete SELECT with all clauses
SELECT DISTINCT TOP 100 WITH TIES
    c.CustomerID,
    c.CustomerName,
    COALESCE(c.Email, 'N/A') AS Email,
    COUNT(o.OrderID) AS OrderCount,
    SUM(ISNULL(o.TotalAmount, 0)) AS TotalSpent,
    CASE 
        WHEN SUM(o.TotalAmount) > 10000 THEN 'VIP'
        WHEN SUM(o.TotalAmount) > 5000 THEN 'Gold'
        ELSE 'Standard'
    END AS CustomerTier
FROM dbo.Customers c
LEFT OUTER JOIN dbo.Orders o ON c.CustomerID = o.CustomerID
    AND o.OrderDate >= DATEADD(YEAR, -1, GETDATE())
WHERE c.IsActive = 1
    AND (c.Country IN ('USA', 'Canada') OR c.CustomerType = 'International')
    AND EXISTS (SELECT 1 FROM dbo.CustomerPreferences cp WHERE cp.CustomerID = c.CustomerID)
GROUP BY c.CustomerID, c.CustomerName, c.Email
HAVING COUNT(o.OrderID) >= 5 OR SUM(o.TotalAmount) > 1000
ORDER BY TotalSpent DESC, CustomerName ASC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY
OPTION (RECOMPILE, MAXDOP 4);
GO

-- Pattern 2: Complete CTE with window functions
WITH 
MonthlySales AS (
    SELECT 
        YEAR(OrderDate) AS SaleYear,
        MONTH(OrderDate) AS SaleMonth,
        CustomerID,
        SUM(TotalAmount) AS MonthlyTotal
    FROM dbo.Orders
    WHERE OrderDate >= '2023-01-01'
    GROUP BY YEAR(OrderDate), MONTH(OrderDate), CustomerID
),
RankedSales AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (PARTITION BY SaleYear, SaleMonth ORDER BY MonthlyTotal DESC) AS MonthRank,
        SUM(MonthlyTotal) OVER (PARTITION BY CustomerID ORDER BY SaleYear, SaleMonth) AS RunningTotal,
        LAG(MonthlyTotal) OVER (PARTITION BY CustomerID ORDER BY SaleYear, SaleMonth) AS PrevMonth,
        PERCENT_RANK() OVER (PARTITION BY SaleYear, SaleMonth ORDER BY MonthlyTotal) AS PercentileRank
    FROM MonthlySales
),
TopCustomers AS (
    SELECT * FROM RankedSales WHERE MonthRank <= 10
)
SELECT 
    tc.*,
    c.CustomerName,
    tc.MonthlyTotal - ISNULL(tc.PrevMonth, tc.MonthlyTotal) AS MoMChange
FROM TopCustomers tc
INNER JOIN dbo.Customers c ON tc.CustomerID = c.CustomerID
ORDER BY tc.SaleYear, tc.SaleMonth, tc.MonthRank;
GO

-- Pattern 3: Complete stored procedure
CREATE PROCEDURE dbo.ProcessCustomerOrder
    @CustomerID INT,
    @ProductItems dbo.OrderItemsType READONLY,
    @ShippingAddress NVARCHAR(500),
    @PaymentMethod VARCHAR(50),
    @OrderID INT OUTPUT,
    @ErrorMessage NVARCHAR(500) OUTPUT
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    
    DECLARE @TotalAmount DECIMAL(18,2);
    DECLARE @TaxAmount DECIMAL(18,2);
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        -- Validate customer
        IF NOT EXISTS (SELECT 1 FROM dbo.Customers WHERE CustomerID = @CustomerID AND IsActive = 1)
        BEGIN
            SET @ErrorMessage = 'Invalid or inactive customer';
            THROW 50001, @ErrorMessage, 1;
        END
        
        -- Calculate totals
        SELECT @TotalAmount = SUM(p.Price * pi.Quantity)
        FROM @ProductItems pi
        INNER JOIN dbo.Products p ON pi.ProductID = p.ProductID;
        
        SET @TaxAmount = @TotalAmount * 0.08;
        
        -- Create order
        INSERT INTO dbo.Orders (CustomerID, OrderDate, TotalAmount, TaxAmount, ShippingAddress, PaymentMethod, Status)
        VALUES (@CustomerID, GETDATE(), @TotalAmount, @TaxAmount, @ShippingAddress, @PaymentMethod, 'Pending');
        
        SET @OrderID = SCOPE_IDENTITY();
        
        -- Create order details
        INSERT INTO dbo.OrderDetails (OrderID, ProductID, Quantity, UnitPrice)
        SELECT @OrderID, pi.ProductID, pi.Quantity, p.Price
        FROM @ProductItems pi
        INNER JOIN dbo.Products p ON pi.ProductID = p.ProductID;
        
        -- Update inventory
        UPDATE inv
        SET inv.Quantity = inv.Quantity - pi.Quantity
        FROM dbo.Inventory inv
        INNER JOIN @ProductItems pi ON inv.ProductID = pi.ProductID;
        
        -- Log the order
        INSERT INTO dbo.OrderLog (OrderID, Action, ActionDate, Details)
        VALUES (@OrderID, 'Created', GETDATE(), 
            (SELECT CustomerID, @TotalAmount AS Total FOR JSON PATH, WITHOUT_ARRAY_WRAPPER));
        
        COMMIT TRANSACTION;
        SET @ErrorMessage = NULL;
        
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        SET @OrderID = NULL;
        SET @ErrorMessage = ERROR_MESSAGE();
        
        INSERT INTO dbo.ErrorLog (ErrorNumber, ErrorMessage, ErrorProcedure, ErrorLine, ErrorDate)
        VALUES (ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_PROCEDURE(), ERROR_LINE(), GETDATE());
        
        THROW;
    END CATCH
END;
GO

DROP PROCEDURE IF EXISTS dbo.ProcessCustomerOrder;
GO

-- Pattern 4: Complete MERGE statement
MERGE INTO dbo.ProductInventory AS target
USING (
    SELECT 
        p.ProductID,
        p.ProductName,
        ISNULL(SUM(po.Quantity), 0) AS IncomingQty,
        ISNULL(SUM(od.Quantity), 0) AS OutgoingQty
    FROM dbo.Products p
    LEFT JOIN dbo.PurchaseOrders po ON p.ProductID = po.ProductID AND po.Status = 'Received'
    LEFT JOIN dbo.OrderDetails od ON p.ProductID = od.ProductID
    GROUP BY p.ProductID, p.ProductName
) AS source
ON target.ProductID = source.ProductID
WHEN MATCHED AND target.Quantity <> (target.Quantity + source.IncomingQty - source.OutgoingQty) THEN
    UPDATE SET 
        target.Quantity = target.Quantity + source.IncomingQty - source.OutgoingQty,
        target.LastUpdated = GETDATE()
WHEN NOT MATCHED BY TARGET THEN
    INSERT (ProductID, ProductName, Quantity, LastUpdated)
    VALUES (source.ProductID, source.ProductName, source.IncomingQty - source.OutgoingQty, GETDATE())
WHEN NOT MATCHED BY SOURCE AND target.LastUpdated < DATEADD(YEAR, -1, GETDATE()) THEN
    DELETE
OUTPUT 
    $action AS MergeAction,
    ISNULL(inserted.ProductID, deleted.ProductID) AS ProductID,
    deleted.Quantity AS OldQuantity,
    inserted.Quantity AS NewQuantity,
    GETDATE() AS ActionDate
INTO dbo.InventoryChangeLog;
GO

-- Pattern 5: Complete trigger
CREATE TRIGGER dbo.trg_Orders_Audit
ON dbo.Orders
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @Action VARCHAR(10);
    
    IF EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted)
        SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT 1 FROM inserted)
        SET @Action = 'INSERT';
    ELSE
        SET @Action = 'DELETE';
    
    INSERT INTO dbo.OrderAudit (
        OrderID, Action, ActionDate, ActionBy,
        OldValues, NewValues
    )
    SELECT 
        COALESCE(i.OrderID, d.OrderID),
        @Action,
        GETDATE(),
        SUSER_SNAME(),
        CASE WHEN d.OrderID IS NOT NULL THEN
            (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        END,
        CASE WHEN i.OrderID IS NOT NULL THEN
            (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        END
    FROM inserted i
    FULL OUTER JOIN deleted d ON i.OrderID = d.OrderID;
END;
GO

DROP TRIGGER IF EXISTS dbo.trg_Orders_Audit;
GO

-- Pattern 6: Complete function
CREATE FUNCTION dbo.CalculateCustomerMetrics
(
    @CustomerID INT,
    @StartDate DATE = NULL,
    @EndDate DATE = NULL
)
RETURNS @Results TABLE
(
    CustomerID INT,
    TotalOrders INT,
    TotalSpent DECIMAL(18,2),
    AverageOrderValue DECIMAL(18,2),
    FirstOrderDate DATE,
    LastOrderDate DATE,
    DaysSinceLastOrder INT,
    OrderFrequencyDays DECIMAL(10,2),
    CustomerLifetimeValue DECIMAL(18,2)
)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @FirstOrder DATE, @LastOrder DATE, @OrderCount INT;
    
    IF @StartDate IS NULL SET @StartDate = '1900-01-01';
    IF @EndDate IS NULL SET @EndDate = GETDATE();
    
    INSERT INTO @Results
    SELECT 
        @CustomerID,
        COUNT(o.OrderID),
        SUM(o.TotalAmount),
        AVG(o.TotalAmount),
        MIN(o.OrderDate),
        MAX(o.OrderDate),
        DATEDIFF(DAY, MAX(o.OrderDate), GETDATE()),
        CASE WHEN COUNT(*) > 1 
            THEN CAST(DATEDIFF(DAY, MIN(o.OrderDate), MAX(o.OrderDate)) AS DECIMAL(10,2)) / (COUNT(*) - 1)
            ELSE NULL 
        END,
        SUM(o.TotalAmount) * 
            CASE WHEN DATEDIFF(MONTH, MIN(o.OrderDate), GETDATE()) > 0
                THEN 12.0 / DATEDIFF(MONTH, MIN(o.OrderDate), GETDATE())
                ELSE 1
            END
    FROM dbo.Orders o
    WHERE o.CustomerID = @CustomerID
        AND o.OrderDate BETWEEN @StartDate AND @EndDate;
    
    RETURN;
END;
GO

DROP FUNCTION IF EXISTS dbo.CalculateCustomerMetrics;
GO

-- Final pattern: Script completion marker
PRINT '====================================';
PRINT 'Sample 201 - Complete!';
PRINT 'Total samples in corpus: 201';
PRINT '====================================';
GO
