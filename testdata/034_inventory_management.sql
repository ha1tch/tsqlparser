-- Sample 034: Inventory Management Procedures
-- Source: Various - MSSQLTips, Database Journal, Stack Overflow
-- Category: ETL/Data Loading
-- Complexity: Advanced
-- Features: Stock movements, FIFO/LIFO costing, reorder points, inventory valuation

-- Record inventory movement (receipt, issue, adjustment, transfer)
CREATE PROCEDURE dbo.RecordInventoryMovement
    @ProductID INT,
    @WarehouseID INT,
    @MovementType NVARCHAR(20),  -- RECEIPT, ISSUE, ADJUSTMENT, TRANSFER_IN, TRANSFER_OUT
    @Quantity DECIMAL(18,4),
    @UnitCost DECIMAL(18,4) = NULL,
    @ReferenceType NVARCHAR(50) = NULL,  -- PO, SO, ADJUSTMENT, TRANSFER
    @ReferenceID INT = NULL,
    @Notes NVARCHAR(500) = NULL,
    @MovementID INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    
    DECLARE @CurrentQty DECIMAL(18,4);
    DECLARE @CurrentAvgCost DECIMAL(18,4);
    DECLARE @NewAvgCost DECIMAL(18,4);
    DECLARE @MovementSign INT;
    
    -- Determine sign based on movement type
    SET @MovementSign = CASE 
        WHEN @MovementType IN ('RECEIPT', 'ADJUSTMENT', 'TRANSFER_IN') AND @Quantity > 0 THEN 1
        WHEN @MovementType IN ('ISSUE', 'TRANSFER_OUT') THEN -1
        WHEN @MovementType = 'ADJUSTMENT' AND @Quantity < 0 THEN 1  -- Negative adjustment
        ELSE 1
    END;
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        -- Get current inventory
        SELECT 
            @CurrentQty = ISNULL(QuantityOnHand, 0),
            @CurrentAvgCost = ISNULL(AverageCost, 0)
        FROM dbo.Inventory WITH (UPDLOCK)
        WHERE ProductID = @ProductID AND WarehouseID = @WarehouseID;
        
        -- Validate issue doesn't go negative
        IF @MovementSign = -1 AND @CurrentQty < ABS(@Quantity)
        BEGIN
            RAISERROR('Insufficient inventory. Available: %s, Requested: %s', 16, 1, 
                CAST(@CurrentQty AS VARCHAR(20)), CAST(@Quantity AS VARCHAR(20)));
            RETURN;
        END
        
        -- Calculate new average cost for receipts
        IF @MovementType = 'RECEIPT' AND @UnitCost IS NOT NULL
        BEGIN
            IF @CurrentQty + @Quantity > 0
                SET @NewAvgCost = ((@CurrentQty * @CurrentAvgCost) + (@Quantity * @UnitCost)) / 
                                  (@CurrentQty + @Quantity);
            ELSE
                SET @NewAvgCost = @UnitCost;
        END
        ELSE
            SET @NewAvgCost = @CurrentAvgCost;
        
        -- Record movement
        INSERT INTO dbo.InventoryMovements (
            ProductID, WarehouseID, MovementType, MovementDate,
            Quantity, UnitCost, TotalCost, QuantityBefore, QuantityAfter,
            ReferenceType, ReferenceID, Notes, CreatedBy, CreatedDate
        )
        VALUES (
            @ProductID, @WarehouseID, @MovementType, GETDATE(),
            @Quantity * @MovementSign, 
            ISNULL(@UnitCost, @CurrentAvgCost),
            ABS(@Quantity) * ISNULL(@UnitCost, @CurrentAvgCost),
            @CurrentQty,
            @CurrentQty + (@Quantity * @MovementSign),
            @ReferenceType, @ReferenceID, @Notes, SUSER_SNAME(), GETDATE()
        );
        
        SET @MovementID = SCOPE_IDENTITY();
        
        -- Update or insert inventory
        IF EXISTS (SELECT 1 FROM dbo.Inventory WHERE ProductID = @ProductID AND WarehouseID = @WarehouseID)
        BEGIN
            UPDATE dbo.Inventory
            SET QuantityOnHand = QuantityOnHand + (@Quantity * @MovementSign),
                AverageCost = @NewAvgCost,
                LastMovementDate = GETDATE(),
                LastMovementID = @MovementID
            WHERE ProductID = @ProductID AND WarehouseID = @WarehouseID;
        END
        ELSE
        BEGIN
            INSERT INTO dbo.Inventory (
                ProductID, WarehouseID, QuantityOnHand, AverageCost,
                LastMovementDate, LastMovementID
            )
            VALUES (
                @ProductID, @WarehouseID, @Quantity * @MovementSign, 
                ISNULL(@UnitCost, 0), GETDATE(), @MovementID
            );
        END
        
        COMMIT TRANSACTION;
        
        -- Return result
        SELECT 
            @MovementID AS MovementID,
            @ProductID AS ProductID,
            @WarehouseID AS WarehouseID,
            @MovementType AS MovementType,
            @Quantity * @MovementSign AS QuantityChanged,
            @CurrentQty + (@Quantity * @MovementSign) AS NewQuantity,
            @NewAvgCost AS AverageCost;
            
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- Calculate inventory valuation using different methods
CREATE PROCEDURE dbo.GetInventoryValuation
    @ProductID INT = NULL,
    @WarehouseID INT = NULL,
    @ValuationMethod NVARCHAR(20) = 'AVERAGE',  -- AVERAGE, FIFO, LIFO, STANDARD
    @AsOfDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    SET @AsOfDate = ISNULL(@AsOfDate, GETDATE());
    
    IF @ValuationMethod = 'AVERAGE'
    BEGIN
        -- Weighted average cost
        SELECT 
            i.ProductID,
            p.ProductName,
            i.WarehouseID,
            w.WarehouseName,
            i.QuantityOnHand,
            i.AverageCost AS UnitCost,
            i.QuantityOnHand * i.AverageCost AS TotalValue,
            'Weighted Average' AS ValuationMethod
        FROM dbo.Inventory i
        INNER JOIN dbo.Products p ON i.ProductID = p.ProductID
        INNER JOIN dbo.Warehouses w ON i.WarehouseID = w.WarehouseID
        WHERE (@ProductID IS NULL OR i.ProductID = @ProductID)
          AND (@WarehouseID IS NULL OR i.WarehouseID = @WarehouseID)
          AND i.QuantityOnHand > 0
        ORDER BY p.ProductName, w.WarehouseName;
    END
    ELSE IF @ValuationMethod = 'FIFO'
    BEGIN
        -- First-In-First-Out
        ;WITH FIFO_Layers AS (
            SELECT 
                ProductID,
                WarehouseID,
                MovementDate,
                Quantity,
                UnitCost,
                SUM(Quantity) OVER (
                    PARTITION BY ProductID, WarehouseID 
                    ORDER BY MovementDate, MovementID
                ) AS RunningQty
            FROM dbo.InventoryMovements
            WHERE MovementType = 'RECEIPT'
              AND MovementDate <= @AsOfDate
              AND (@ProductID IS NULL OR ProductID = @ProductID)
              AND (@WarehouseID IS NULL OR WarehouseID = @WarehouseID)
        ),
        CurrentQty AS (
            SELECT ProductID, WarehouseID, SUM(Quantity) AS TotalQty
            FROM dbo.InventoryMovements
            WHERE MovementDate <= @AsOfDate
              AND (@ProductID IS NULL OR ProductID = @ProductID)
              AND (@WarehouseID IS NULL OR WarehouseID = @WarehouseID)
            GROUP BY ProductID, WarehouseID
        )
        SELECT 
            fl.ProductID,
            p.ProductName,
            fl.WarehouseID,
            w.WarehouseName,
            cq.TotalQty AS QuantityOnHand,
            SUM(CASE 
                WHEN fl.RunningQty <= cq.TotalQty THEN fl.Quantity * fl.UnitCost
                WHEN fl.RunningQty - fl.Quantity < cq.TotalQty 
                THEN (cq.TotalQty - (fl.RunningQty - fl.Quantity)) * fl.UnitCost
                ELSE 0
            END) AS TotalValue,
            'FIFO' AS ValuationMethod
        FROM FIFO_Layers fl
        INNER JOIN CurrentQty cq ON fl.ProductID = cq.ProductID AND fl.WarehouseID = cq.WarehouseID
        INNER JOIN dbo.Products p ON fl.ProductID = p.ProductID
        INNER JOIN dbo.Warehouses w ON fl.WarehouseID = w.WarehouseID
        WHERE cq.TotalQty > 0
        GROUP BY fl.ProductID, p.ProductName, fl.WarehouseID, w.WarehouseName, cq.TotalQty;
    END
    ELSE IF @ValuationMethod = 'STANDARD'
    BEGIN
        -- Standard cost from product master
        SELECT 
            i.ProductID,
            p.ProductName,
            i.WarehouseID,
            w.WarehouseName,
            i.QuantityOnHand,
            p.StandardCost AS UnitCost,
            i.QuantityOnHand * p.StandardCost AS TotalValue,
            'Standard Cost' AS ValuationMethod
        FROM dbo.Inventory i
        INNER JOIN dbo.Products p ON i.ProductID = p.ProductID
        INNER JOIN dbo.Warehouses w ON i.WarehouseID = w.WarehouseID
        WHERE (@ProductID IS NULL OR i.ProductID = @ProductID)
          AND (@WarehouseID IS NULL OR i.WarehouseID = @WarehouseID)
          AND i.QuantityOnHand > 0
        ORDER BY p.ProductName, w.WarehouseName;
    END
END
GO

-- Check reorder points and generate alerts
CREATE PROCEDURE dbo.CheckReorderPoints
    @WarehouseID INT = NULL,
    @CategoryID INT = NULL,
    @GenerateOrders BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Items below reorder point
    SELECT 
        i.ProductID,
        p.ProductName,
        p.CategoryID,
        c.CategoryName,
        i.WarehouseID,
        w.WarehouseName,
        i.QuantityOnHand,
        p.ReorderPoint,
        p.ReorderQuantity,
        p.LeadTimeDays,
        CASE 
            WHEN i.QuantityOnHand <= 0 THEN 'OUT OF STOCK'
            WHEN i.QuantityOnHand <= p.SafetyStock THEN 'CRITICAL'
            WHEN i.QuantityOnHand <= p.ReorderPoint THEN 'REORDER'
            ELSE 'OK'
        END AS StockStatus,
        p.ReorderQuantity AS SuggestedOrderQty,
        s.SupplierName AS PreferredSupplier,
        s.SupplierID
    FROM dbo.Inventory i
    INNER JOIN dbo.Products p ON i.ProductID = p.ProductID
    INNER JOIN dbo.Categories c ON p.CategoryID = c.CategoryID
    INNER JOIN dbo.Warehouses w ON i.WarehouseID = w.WarehouseID
    LEFT JOIN dbo.Suppliers s ON p.PreferredSupplierID = s.SupplierID
    WHERE i.QuantityOnHand <= p.ReorderPoint
      AND (@WarehouseID IS NULL OR i.WarehouseID = @WarehouseID)
      AND (@CategoryID IS NULL OR p.CategoryID = @CategoryID)
    ORDER BY 
        CASE 
            WHEN i.QuantityOnHand <= 0 THEN 1
            WHEN i.QuantityOnHand <= p.SafetyStock THEN 2
            ELSE 3
        END,
        p.ProductName;
    
    -- Summary by status
    SELECT 
        CASE 
            WHEN i.QuantityOnHand <= 0 THEN 'OUT OF STOCK'
            WHEN i.QuantityOnHand <= p.SafetyStock THEN 'CRITICAL'
            WHEN i.QuantityOnHand <= p.ReorderPoint THEN 'REORDER'
            ELSE 'OK'
        END AS StockStatus,
        COUNT(*) AS ProductCount,
        SUM(p.ReorderQuantity * ISNULL(p.StandardCost, 0)) AS EstimatedOrderValue
    FROM dbo.Inventory i
    INNER JOIN dbo.Products p ON i.ProductID = p.ProductID
    WHERE (@WarehouseID IS NULL OR i.WarehouseID = @WarehouseID)
      AND (@CategoryID IS NULL OR p.CategoryID = @CategoryID)
    GROUP BY 
        CASE 
            WHEN i.QuantityOnHand <= 0 THEN 'OUT OF STOCK'
            WHEN i.QuantityOnHand <= p.SafetyStock THEN 'CRITICAL'
            WHEN i.QuantityOnHand <= p.ReorderPoint THEN 'REORDER'
            ELSE 'OK'
        END
    ORDER BY 
        CASE 
            WHEN i.QuantityOnHand <= 0 THEN 1
            WHEN i.QuantityOnHand <= p.SafetyStock THEN 2
            WHEN i.QuantityOnHand <= p.ReorderPoint THEN 3
            ELSE 4
        END;
END
GO

-- Perform inventory count adjustment
CREATE PROCEDURE dbo.PerformInventoryCount
    @ProductID INT,
    @WarehouseID INT,
    @CountedQuantity DECIMAL(18,4),
    @CountDate DATE = NULL,
    @CountedBy NVARCHAR(100) = NULL,
    @Notes NVARCHAR(500) = NULL,
    @AdjustmentID INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    
    DECLARE @CurrentQty DECIMAL(18,4);
    DECLARE @Variance DECIMAL(18,4);
    DECLARE @VarianceValue DECIMAL(18,4);
    DECLARE @UnitCost DECIMAL(18,4);
    
    SET @CountDate = ISNULL(@CountDate, GETDATE());
    SET @CountedBy = ISNULL(@CountedBy, SUSER_SNAME());
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        -- Get current inventory
        SELECT 
            @CurrentQty = ISNULL(QuantityOnHand, 0),
            @UnitCost = ISNULL(AverageCost, 0)
        FROM dbo.Inventory WITH (UPDLOCK)
        WHERE ProductID = @ProductID AND WarehouseID = @WarehouseID;
        
        SET @CurrentQty = ISNULL(@CurrentQty, 0);
        SET @Variance = @CountedQuantity - @CurrentQty;
        SET @VarianceValue = @Variance * @UnitCost;
        
        -- Record count
        INSERT INTO dbo.InventoryCounts (
            ProductID, WarehouseID, CountDate, SystemQuantity, 
            CountedQuantity, Variance, VarianceValue, CountedBy, Notes, CreatedDate
        )
        VALUES (
            @ProductID, @WarehouseID, @CountDate, @CurrentQty,
            @CountedQuantity, @Variance, @VarianceValue, @CountedBy, @Notes, GETDATE()
        );
        
        SET @AdjustmentID = SCOPE_IDENTITY();
        
        -- If variance, create adjustment movement
        IF @Variance <> 0
        BEGIN
            DECLARE @MovementID INT;
            
            EXEC dbo.RecordInventoryMovement
                @ProductID = @ProductID,
                @WarehouseID = @WarehouseID,
                @MovementType = 'ADJUSTMENT',
                @Quantity = @Variance,
                @UnitCost = @UnitCost,
                @ReferenceType = 'COUNT',
                @ReferenceID = @AdjustmentID,
                @Notes = @Notes,
                @MovementID = @MovementID OUTPUT;
        END
        
        COMMIT TRANSACTION;
        
        -- Return result
        SELECT 
            @AdjustmentID AS CountID,
            @ProductID AS ProductID,
            @WarehouseID AS WarehouseID,
            @CurrentQty AS SystemQuantity,
            @CountedQuantity AS CountedQuantity,
            @Variance AS Variance,
            @VarianceValue AS VarianceValue,
            CASE 
                WHEN @Variance = 0 THEN 'NO VARIANCE'
                WHEN @Variance > 0 THEN 'OVERAGE'
                ELSE 'SHORTAGE'
            END AS VarianceType;
            
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
