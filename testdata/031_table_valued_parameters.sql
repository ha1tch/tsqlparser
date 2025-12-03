-- Sample 031: Table-Valued Parameters (TVPs)
-- Source: Microsoft Learn, MSSQLTips, Stack Overflow
-- Category: ETL/Data Loading
-- Complexity: Complex
-- Features: User-defined table types, TVPs, bulk operations, MERGE with TVPs

-- Create user-defined table types
CREATE TYPE dbo.ProductListType AS TABLE (
    ProductID INT,
    ProductName NVARCHAR(100),
    UnitPrice DECIMAL(18,2),
    CategoryID INT,
    SupplierID INT,
    UnitsInStock INT
);
GO

CREATE TYPE dbo.OrderDetailType AS TABLE (
    ProductID INT NOT NULL,
    Quantity INT NOT NULL,
    UnitPrice DECIMAL(18,2) NOT NULL,
    Discount DECIMAL(5,2) DEFAULT 0
);
GO

CREATE TYPE dbo.IntListType AS TABLE (
    Value INT NOT NULL PRIMARY KEY
);
GO

CREATE TYPE dbo.KeyValueType AS TABLE (
    [Key] NVARCHAR(100) NOT NULL,
    Value NVARCHAR(MAX)
);
GO

-- Bulk insert products using TVP
CREATE PROCEDURE dbo.BulkInsertProducts
    @Products dbo.ProductListType READONLY,
    @UpdateExisting BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @InsertedCount INT = 0;
    DECLARE @UpdatedCount INT = 0;
    
    IF @UpdateExisting = 1
    BEGIN
        -- Use MERGE for upsert
        MERGE dbo.Products AS target
        USING @Products AS source
        ON target.ProductID = source.ProductID
        WHEN MATCHED THEN
            UPDATE SET 
                ProductName = source.ProductName,
                UnitPrice = source.UnitPrice,
                CategoryID = source.CategoryID,
                SupplierID = source.SupplierID,
                UnitsInStock = source.UnitsInStock,
                ModifiedDate = GETDATE()
        WHEN NOT MATCHED BY TARGET THEN
            INSERT (ProductID, ProductName, UnitPrice, CategoryID, SupplierID, UnitsInStock, CreatedDate)
            VALUES (source.ProductID, source.ProductName, source.UnitPrice, 
                    source.CategoryID, source.SupplierID, source.UnitsInStock, GETDATE());
        
        SET @InsertedCount = @@ROWCOUNT;  -- Total affected
    END
    ELSE
    BEGIN
        -- Simple insert only
        INSERT INTO dbo.Products (ProductID, ProductName, UnitPrice, CategoryID, SupplierID, UnitsInStock, CreatedDate)
        SELECT ProductID, ProductName, UnitPrice, CategoryID, SupplierID, UnitsInStock, GETDATE()
        FROM @Products p
        WHERE NOT EXISTS (SELECT 1 FROM dbo.Products WHERE ProductID = p.ProductID);
        
        SET @InsertedCount = @@ROWCOUNT;
    END
    
    SELECT 
        @InsertedCount AS RowsAffected,
        @UpdateExisting AS UpsertMode;
END
GO

-- Create order with details using TVP
CREATE PROCEDURE dbo.CreateOrderWithDetails
    @CustomerID INT,
    @OrderDate DATE = NULL,
    @ShipAddress NVARCHAR(200) = NULL,
    @OrderDetails dbo.OrderDetailType READONLY,
    @OrderID INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    
    DECLARE @OrderTotal DECIMAL(18,2);
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        -- Validate products exist
        IF EXISTS (
            SELECT 1 FROM @OrderDetails od
            WHERE NOT EXISTS (SELECT 1 FROM dbo.Products WHERE ProductID = od.ProductID)
        )
        BEGIN
            RAISERROR('One or more products do not exist', 16, 1);
            RETURN;
        END
        
        -- Calculate order total
        SELECT @OrderTotal = SUM((Quantity * UnitPrice) * (1 - Discount))
        FROM @OrderDetails;
        
        -- Create order
        INSERT INTO dbo.Orders (CustomerID, OrderDate, ShipAddress, OrderTotal, Status)
        VALUES (@CustomerID, ISNULL(@OrderDate, GETDATE()), @ShipAddress, @OrderTotal, 'Pending');
        
        SET @OrderID = SCOPE_IDENTITY();
        
        -- Insert order details
        INSERT INTO dbo.OrderDetails (OrderID, ProductID, Quantity, UnitPrice, Discount, LineTotal)
        SELECT 
            @OrderID,
            ProductID,
            Quantity,
            UnitPrice,
            Discount,
            (Quantity * UnitPrice) * (1 - Discount)
        FROM @OrderDetails;
        
        -- Update inventory
        UPDATE p
        SET p.UnitsInStock = p.UnitsInStock - od.Quantity
        FROM dbo.Products p
        INNER JOIN @OrderDetails od ON p.ProductID = od.ProductID;
        
        COMMIT TRANSACTION;
        
        SELECT 
            @OrderID AS OrderID,
            @OrderTotal AS OrderTotal,
            (SELECT COUNT(*) FROM @OrderDetails) AS LineItemCount;
            
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        THROW;
    END CATCH
END
GO

-- Get records by ID list using TVP
CREATE PROCEDURE dbo.GetProductsByIDs
    @ProductIDs dbo.IntListType READONLY
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        p.ProductID,
        p.ProductName,
        p.UnitPrice,
        c.CategoryName,
        s.SupplierName,
        p.UnitsInStock
    FROM dbo.Products p
    INNER JOIN @ProductIDs ids ON p.ProductID = ids.Value
    LEFT JOIN dbo.Categories c ON p.CategoryID = c.CategoryID
    LEFT JOIN dbo.Suppliers s ON p.SupplierID = s.SupplierID
    ORDER BY p.ProductName;
END
GO

-- Delete multiple records using TVP
CREATE PROCEDURE dbo.DeleteProductsByIDs
    @ProductIDs dbo.IntListType READONLY,
    @SoftDelete BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @AffectedCount INT;
    
    IF @SoftDelete = 1
    BEGIN
        UPDATE p
        SET p.IsDeleted = 1,
            p.DeletedDate = GETDATE()
        FROM dbo.Products p
        INNER JOIN @ProductIDs ids ON p.ProductID = ids.Value
        WHERE p.IsDeleted = 0;
        
        SET @AffectedCount = @@ROWCOUNT;
    END
    ELSE
    BEGIN
        -- Check for dependencies first
        IF EXISTS (
            SELECT 1 FROM dbo.OrderDetails od
            INNER JOIN @ProductIDs ids ON od.ProductID = ids.Value
        )
        BEGIN
            RAISERROR('Cannot delete products with existing orders', 16, 1);
            RETURN;
        END
        
        DELETE p
        FROM dbo.Products p
        INNER JOIN @ProductIDs ids ON p.ProductID = ids.Value;
        
        SET @AffectedCount = @@ROWCOUNT;
    END
    
    SELECT 
        @AffectedCount AS ProductsDeleted,
        @SoftDelete AS SoftDelete;
END
GO

-- Update multiple records using key-value pairs
CREATE PROCEDURE dbo.UpdateProductAttributes
    @ProductID INT,
    @Attributes dbo.KeyValueType READONLY
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SQL NVARCHAR(MAX) = '';
    DECLARE @Params NVARCHAR(MAX) = '';
    DECLARE @Key NVARCHAR(100);
    DECLARE @Value NVARCHAR(MAX);
    DECLARE @ValidColumns TABLE (ColumnName NVARCHAR(128));
    
    -- Get valid column names
    INSERT INTO @ValidColumns
    SELECT c.name
    FROM sys.columns c
    INNER JOIN sys.tables t ON c.object_id = t.object_id
    WHERE t.name = 'Products'
      AND c.name NOT IN ('ProductID', 'CreatedDate', 'CreatedBy');
    
    -- Validate all attributes are valid columns
    IF EXISTS (
        SELECT 1 FROM @Attributes a
        WHERE NOT EXISTS (SELECT 1 FROM @ValidColumns WHERE ColumnName = a.[Key])
    )
    BEGIN
        RAISERROR('Invalid attribute name provided', 16, 1);
        RETURN;
    END
    
    -- Build dynamic update
    SELECT @SQL = @SQL + QUOTENAME([Key]) + ' = ' + 
        CASE 
            WHEN Value IS NULL THEN 'NULL'
            WHEN TRY_CAST(Value AS DECIMAL(18,2)) IS NOT NULL 
                 AND [Key] IN ('UnitPrice', 'UnitsInStock') THEN Value
            ELSE '''' + REPLACE(Value, '''', '''''') + ''''
        END + ', '
    FROM @Attributes;
    
    -- Remove trailing comma
    SET @SQL = LEFT(@SQL, LEN(@SQL) - 1);
    
    -- Add ModifiedDate
    SET @SQL = 'UPDATE dbo.Products SET ' + @SQL + ', ModifiedDate = GETDATE() WHERE ProductID = @ProductID';
    
    EXEC sp_executesql @SQL, N'@ProductID INT', @ProductID = @ProductID;
    
    SELECT @@ROWCOUNT AS RowsUpdated;
END
GO

-- Validate TVP data before processing
CREATE PROCEDURE dbo.ValidateProductData
    @Products dbo.ProductListType READONLY
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @Errors TABLE (
        RowNumber INT,
        ProductID INT,
        ErrorType NVARCHAR(50),
        ErrorMessage NVARCHAR(500)
    );
    
    -- Check for duplicate ProductIDs in input
    INSERT INTO @Errors (RowNumber, ProductID, ErrorType, ErrorMessage)
    SELECT 
        ROW_NUMBER() OVER (ORDER BY ProductID),
        ProductID,
        'Duplicate',
        'Duplicate ProductID in input data'
    FROM @Products
    GROUP BY ProductID
    HAVING COUNT(*) > 1;
    
    -- Check for invalid CategoryID
    INSERT INTO @Errors (RowNumber, ProductID, ErrorType, ErrorMessage)
    SELECT 
        ROW_NUMBER() OVER (ORDER BY p.ProductID),
        p.ProductID,
        'Invalid Category',
        'CategoryID ' + CAST(p.CategoryID AS VARCHAR(10)) + ' does not exist'
    FROM @Products p
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Categories WHERE CategoryID = p.CategoryID)
      AND p.CategoryID IS NOT NULL;
    
    -- Check for negative prices
    INSERT INTO @Errors (RowNumber, ProductID, ErrorType, ErrorMessage)
    SELECT 
        ROW_NUMBER() OVER (ORDER BY ProductID),
        ProductID,
        'Invalid Price',
        'Unit price cannot be negative'
    FROM @Products
    WHERE UnitPrice < 0;
    
    -- Return validation results
    IF EXISTS (SELECT 1 FROM @Errors)
    BEGIN
        SELECT 
            'Validation Failed' AS Status,
            COUNT(*) AS ErrorCount
        FROM @Errors;
        
        SELECT * FROM @Errors ORDER BY RowNumber;
    END
    ELSE
    BEGIN
        SELECT 
            'Validation Passed' AS Status,
            (SELECT COUNT(*) FROM @Products) AS RecordCount;
    END
END
GO
