-- Sample 008: MERGE Statement Patterns for UPSERT Operations
-- Source: Various - MSSQLTips, Database Journal, Stack Overflow
-- Category: ETL/Data Loading
-- Complexity: Complex
-- Features: MERGE, HOLDLOCK, OUTPUT clause, Table-valued parameters

-- Simple UPSERT with MERGE
CREATE PROCEDURE dbo.UpsertProduct
    @ProductID INT,
    @ProductName NVARCHAR(100),
    @Price DECIMAL(10,2),
    @CategoryID INT
AS
BEGIN
    SET NOCOUNT ON;
    
    MERGE INTO dbo.Products WITH (HOLDLOCK) AS target
    USING (
        SELECT 
            @ProductID AS ProductID,
            @ProductName AS ProductName,
            @Price AS Price,
            @CategoryID AS CategoryID
    ) AS source
    ON target.ProductID = source.ProductID
    
    WHEN MATCHED THEN
        UPDATE SET 
            ProductName = source.ProductName,
            Price = source.Price,
            CategoryID = source.CategoryID,
            ModifiedDate = GETUTCDATE()
    
    WHEN NOT MATCHED THEN
        INSERT (ProductID, ProductName, Price, CategoryID, CreatedDate, ModifiedDate)
        VALUES (source.ProductID, source.ProductName, source.Price, 
                source.CategoryID, GETUTCDATE(), GETUTCDATE());
END
GO


-- MERGE with OUTPUT for audit logging
CREATE PROCEDURE dbo.UpsertProductWithAudit
    @ProductID INT,
    @ProductName NVARCHAR(100),
    @Price DECIMAL(10,2),
    @CategoryID INT,
    @UserID INT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @AuditOutput TABLE (
        Action NVARCHAR(10),
        ProductID INT,
        OldProductName NVARCHAR(100),
        NewProductName NVARCHAR(100),
        OldPrice DECIMAL(10,2),
        NewPrice DECIMAL(10,2)
    );
    
    MERGE INTO dbo.Products WITH (HOLDLOCK) AS target
    USING (
        SELECT @ProductID, @ProductName, @Price, @CategoryID
    ) AS source (ProductID, ProductName, Price, CategoryID)
    ON target.ProductID = source.ProductID
    
    WHEN MATCHED AND (
        target.ProductName <> source.ProductName OR
        target.Price <> source.Price OR
        target.CategoryID <> source.CategoryID
    ) THEN
        UPDATE SET 
            ProductName = source.ProductName,
            Price = source.Price,
            CategoryID = source.CategoryID,
            ModifiedDate = GETUTCDATE(),
            ModifiedBy = @UserID
    
    WHEN NOT MATCHED THEN
        INSERT (ProductID, ProductName, Price, CategoryID, 
                CreatedDate, ModifiedDate, CreatedBy, ModifiedBy)
        VALUES (source.ProductID, source.ProductName, source.Price, 
                source.CategoryID, GETUTCDATE(), GETUTCDATE(), @UserID, @UserID)
    
    OUTPUT 
        $action,
        COALESCE(inserted.ProductID, deleted.ProductID),
        deleted.ProductName,
        inserted.ProductName,
        deleted.Price,
        inserted.Price
    INTO @AuditOutput;
    
    -- Log to audit table
    INSERT INTO dbo.ProductAuditLog (
        Action, ProductID, OldProductName, NewProductName, 
        OldPrice, NewPrice, ChangedBy, ChangedDate
    )
    SELECT 
        Action, ProductID, OldProductName, NewProductName,
        OldPrice, NewPrice, @UserID, GETUTCDATE()
    FROM @AuditOutput;
    
    -- Return the action taken
    SELECT * FROM @AuditOutput;
END
GO


-- Bulk UPSERT with Table-Valued Parameter
CREATE TYPE dbo.ProductTableType AS TABLE (
    ProductID INT,
    ProductName NVARCHAR(100),
    Price DECIMAL(10,2),
    CategoryID INT
);
GO

CREATE PROCEDURE dbo.BulkUpsertProducts
    @Products dbo.ProductTableType READONLY,
    @UserID INT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @Results TABLE (
        Action NVARCHAR(10),
        ProductID INT
    );
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        MERGE INTO dbo.Products WITH (HOLDLOCK) AS target
        USING @Products AS source
        ON target.ProductID = source.ProductID
        
        WHEN MATCHED THEN
            UPDATE SET 
                ProductName = source.ProductName,
                Price = source.Price,
                CategoryID = source.CategoryID,
                ModifiedDate = GETUTCDATE(),
                ModifiedBy = @UserID
        
        WHEN NOT MATCHED BY TARGET THEN
            INSERT (ProductID, ProductName, Price, CategoryID, 
                    CreatedDate, ModifiedDate, CreatedBy, ModifiedBy)
            VALUES (source.ProductID, source.ProductName, source.Price, 
                    source.CategoryID, GETUTCDATE(), GETUTCDATE(), @UserID, @UserID)
        
        WHEN NOT MATCHED BY SOURCE THEN
            DELETE
        
        OUTPUT $action, COALESCE(inserted.ProductID, deleted.ProductID)
        INTO @Results;
        
        COMMIT TRANSACTION;
        
        -- Return summary
        SELECT 
            Action,
            COUNT(*) AS RecordCount
        FROM @Results
        GROUP BY Action;
        
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO


-- UPSERT with conditional logic (inventory example)
CREATE PROCEDURE dbo.UpsertInventory
    @ProductID INT,
    @WarehouseID INT,
    @QuantityChange INT,
    @TransactionType CHAR(1)  -- 'I' = In, 'O' = Out
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @CurrentQty INT;
    
    MERGE INTO dbo.Inventory WITH (HOLDLOCK) AS target
    USING (
        SELECT @ProductID AS ProductID, @WarehouseID AS WarehouseID
    ) AS source
    ON target.ProductID = source.ProductID 
       AND target.WarehouseID = source.WarehouseID
    
    WHEN MATCHED THEN
        UPDATE SET 
            Quantity = CASE @TransactionType
                WHEN 'I' THEN target.Quantity + @QuantityChange
                WHEN 'O' THEN 
                    CASE WHEN target.Quantity >= @QuantityChange 
                         THEN target.Quantity - @QuantityChange
                         ELSE target.Quantity  -- Don't go negative
                    END
                ELSE target.Quantity
            END,
            LastUpdated = GETUTCDATE()
    
    WHEN NOT MATCHED AND @TransactionType = 'I' THEN
        INSERT (ProductID, WarehouseID, Quantity, LastUpdated)
        VALUES (@ProductID, @WarehouseID, @QuantityChange, GETUTCDATE());
    
    -- Return new quantity
    SELECT Quantity 
    FROM dbo.Inventory 
    WHERE ProductID = @ProductID AND WarehouseID = @WarehouseID;
END
GO
