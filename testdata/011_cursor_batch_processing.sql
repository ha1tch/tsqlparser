-- Sample 011: Cursor-Based Batch Processing with Transaction Control
-- Source: Various - SQLServerCentral, Stack Overflow patterns
-- Category: Error Handling
-- Complexity: Advanced
-- Features: CURSOR, Transaction per row, TRY/CATCH, CURSOR_STATUS

CREATE PROCEDURE dbo.ProcessOrdersInBatches
    @BatchSize INT = 100,
    @MaxErrors INT = 10
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;  -- We handle errors manually
    
    DECLARE @OrderID INT;
    DECLARE @CustomerID INT;
    DECLARE @OrderTotal DECIMAL(18,2);
    DECLARE @ProcessedCount INT = 0;
    DECLARE @ErrorCount INT = 0;
    DECLARE @SuccessCount INT = 0;
    DECLARE @CurrentBatch INT = 0;
    
    DECLARE @ErrorLog TABLE (
        OrderID INT,
        ErrorNumber INT,
        ErrorMessage NVARCHAR(4000),
        ErrorDate DATETIME DEFAULT GETDATE()
    );
    
    -- Declare cursor for unprocessed orders
    DECLARE OrderCursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT OrderID, CustomerID, OrderTotal
        FROM dbo.Orders
        WHERE ProcessedDate IS NULL
          AND Status = 'Pending'
        ORDER BY OrderDate;
    
    OPEN OrderCursor;
    
    FETCH NEXT FROM OrderCursor INTO @OrderID, @CustomerID, @OrderTotal;
    
    WHILE @@FETCH_STATUS = 0 AND @ErrorCount < @MaxErrors
    BEGIN
        BEGIN TRY
            BEGIN TRANSACTION;
            
            -- Update inventory
            UPDATE dbo.Inventory
            SET Quantity = Quantity - od.Quantity,
                LastUpdated = GETDATE()
            FROM dbo.Inventory i
            INNER JOIN dbo.OrderDetails od ON i.ProductID = od.ProductID
            WHERE od.OrderID = @OrderID;
            
            -- Update customer balance
            UPDATE dbo.Customers
            SET AccountBalance = AccountBalance - @OrderTotal,
                LastOrderDate = GETDATE()
            WHERE CustomerID = @CustomerID;
            
            -- Mark order as processed
            UPDATE dbo.Orders
            SET ProcessedDate = GETDATE(),
                Status = 'Processed'
            WHERE OrderID = @OrderID;
            
            -- Create shipment record
            INSERT INTO dbo.Shipments (OrderID, ShipDate, Status)
            VALUES (@OrderID, DATEADD(DAY, 2, GETDATE()), 'Pending');
            
            COMMIT TRANSACTION;
            SET @SuccessCount = @SuccessCount + 1;
            
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0
                ROLLBACK TRANSACTION;
            
            SET @ErrorCount = @ErrorCount + 1;
            
            INSERT INTO @ErrorLog (OrderID, ErrorNumber, ErrorMessage)
            VALUES (@OrderID, ERROR_NUMBER(), ERROR_MESSAGE());
            
            -- Log to permanent error table
            INSERT INTO dbo.ProcessingErrors (
                OrderID, ErrorNumber, ErrorMessage, ErrorProcedure, ErrorLine
            )
            VALUES (
                @OrderID, ERROR_NUMBER(), ERROR_MESSAGE(), 
                ERROR_PROCEDURE(), ERROR_LINE()
            );
        END CATCH
        
        SET @ProcessedCount = @ProcessedCount + 1;
        SET @CurrentBatch = @CurrentBatch + 1;
        
        -- Batch checkpoint
        IF @CurrentBatch >= @BatchSize
        BEGIN
            -- Optional: Add delay to reduce lock contention
            WAITFOR DELAY '00:00:00.100';
            SET @CurrentBatch = 0;
        END
        
        FETCH NEXT FROM OrderCursor INTO @OrderID, @CustomerID, @OrderTotal;
    END
    
    -- Cleanup cursor
    IF CURSOR_STATUS('local', 'OrderCursor') >= 0
    BEGIN
        CLOSE OrderCursor;
        DEALLOCATE OrderCursor;
    END
    
    -- Return processing summary
    SELECT 
        @ProcessedCount AS TotalProcessed,
        @SuccessCount AS SuccessfulOrders,
        @ErrorCount AS FailedOrders,
        CASE WHEN @ErrorCount >= @MaxErrors 
             THEN 'Stopped - Max errors reached' 
             ELSE 'Completed' 
        END AS Status;
    
    -- Return error details if any
    IF EXISTS (SELECT 1 FROM @ErrorLog)
        SELECT * FROM @ErrorLog;
END
GO
