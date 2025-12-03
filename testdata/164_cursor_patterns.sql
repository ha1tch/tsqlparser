-- Sample 164: Cursor Syntax Patterns
-- Category: Missing Syntax Elements / Cursors
-- Complexity: Complex
-- Purpose: Parser testing - cursor declaration and usage syntax
-- Features: DECLARE CURSOR variations, OPEN, FETCH, CLOSE, DEALLOCATE

-- Pattern 1: Basic forward-only cursor
DECLARE @CustomerID INT, @CustomerName VARCHAR(100);

DECLARE basic_cursor CURSOR FOR
    SELECT CustomerID, CustomerName FROM dbo.Customers;

OPEN basic_cursor;

FETCH NEXT FROM basic_cursor INTO @CustomerID, @CustomerName;

WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT 'Customer: ' + @CustomerName;
    FETCH NEXT FROM basic_cursor INTO @CustomerID, @CustomerName;
END

CLOSE basic_cursor;
DEALLOCATE basic_cursor;
GO

-- Pattern 2: LOCAL cursor (default scope)
DECLARE local_cursor CURSOR LOCAL FOR
    SELECT ProductID FROM dbo.Products;
    
OPEN local_cursor;
CLOSE local_cursor;
DEALLOCATE local_cursor;
GO

-- Pattern 3: GLOBAL cursor
DECLARE global_cursor CURSOR GLOBAL FOR
    SELECT OrderID FROM dbo.Orders;
    
OPEN global_cursor;
-- Can be accessed from other batches by name
CLOSE global_cursor;
DEALLOCATE global_cursor;
GO

-- Pattern 4: FORWARD_ONLY cursor (default)
DECLARE forward_cursor CURSOR FORWARD_ONLY FOR
    SELECT CustomerID FROM dbo.Customers;
    
OPEN forward_cursor;
CLOSE forward_cursor;
DEALLOCATE forward_cursor;
GO

-- Pattern 5: SCROLL cursor (can fetch in any direction)
DECLARE @ID INT;

DECLARE scroll_cursor CURSOR SCROLL FOR
    SELECT CustomerID FROM dbo.Customers ORDER BY CustomerID;

OPEN scroll_cursor;

FETCH FIRST FROM scroll_cursor INTO @ID;
PRINT 'First: ' + CAST(@ID AS VARCHAR);

FETCH LAST FROM scroll_cursor INTO @ID;
PRINT 'Last: ' + CAST(@ID AS VARCHAR);

FETCH ABSOLUTE 5 FROM scroll_cursor INTO @ID;
PRINT 'Fifth: ' + CAST(@ID AS VARCHAR);

FETCH RELATIVE -2 FROM scroll_cursor INTO @ID;
PRINT 'Two before current: ' + CAST(@ID AS VARCHAR);

FETCH PRIOR FROM scroll_cursor INTO @ID;
PRINT 'Previous: ' + CAST(@ID AS VARCHAR);

FETCH NEXT FROM scroll_cursor INTO @ID;
PRINT 'Next: ' + CAST(@ID AS VARCHAR);

CLOSE scroll_cursor;
DEALLOCATE scroll_cursor;
GO

-- Pattern 6: STATIC cursor (snapshot of data)
DECLARE static_cursor CURSOR STATIC FOR
    SELECT ProductID, StockQuantity FROM dbo.Products;
    
OPEN static_cursor;
-- Changes to underlying data won't be visible
CLOSE static_cursor;
DEALLOCATE static_cursor;
GO

-- Pattern 7: KEYSET cursor (keys are fixed, data can change)
DECLARE keyset_cursor CURSOR KEYSET FOR
    SELECT CustomerID, CustomerName FROM dbo.Customers;
    
OPEN keyset_cursor;
-- Membership fixed, but column values reflect current data
CLOSE keyset_cursor;
DEALLOCATE keyset_cursor;
GO

-- Pattern 8: DYNAMIC cursor (fully dynamic)
DECLARE dynamic_cursor CURSOR DYNAMIC FOR
    SELECT OrderID, TotalAmount FROM dbo.Orders;
    
OPEN dynamic_cursor;
-- Reflects all changes including inserts/deletes
CLOSE dynamic_cursor;
DEALLOCATE dynamic_cursor;
GO

-- Pattern 9: FAST_FORWARD cursor (optimized forward-only, read-only)
DECLARE fast_cursor CURSOR FAST_FORWARD FOR
    SELECT CustomerID FROM dbo.Customers;
    
OPEN fast_cursor;
CLOSE fast_cursor;
DEALLOCATE fast_cursor;
GO

-- Pattern 10: READ_ONLY cursor
DECLARE readonly_cursor CURSOR READ_ONLY FOR
    SELECT ProductID, ProductName FROM dbo.Products;
    
OPEN readonly_cursor;
CLOSE readonly_cursor;
DEALLOCATE readonly_cursor;
GO

-- Pattern 11: SCROLL_LOCKS cursor
DECLARE scroll_locks_cursor CURSOR SCROLL_LOCKS FOR
    SELECT CustomerID, Balance FROM dbo.Accounts;
    
OPEN scroll_locks_cursor;
-- Locks rows as they're fetched
CLOSE scroll_locks_cursor;
DEALLOCATE scroll_locks_cursor;
GO

-- Pattern 12: OPTIMISTIC cursor
DECLARE optimistic_cursor CURSOR OPTIMISTIC FOR
    SELECT ProductID, StockQuantity FROM dbo.Products;
    
OPEN optimistic_cursor;
-- Uses optimistic concurrency (timestamp comparison)
CLOSE optimistic_cursor;
DEALLOCATE optimistic_cursor;
GO

-- Pattern 13: Cursor for UPDATE
DECLARE @ProductID INT, @Price DECIMAL(10,2);

DECLARE update_cursor CURSOR FOR
    SELECT ProductID, Price FROM dbo.Products
    FOR UPDATE OF Price;

OPEN update_cursor;
FETCH NEXT FROM update_cursor INTO @ProductID, @Price;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Update current row
    UPDATE dbo.Products
    SET Price = @Price * 1.10  -- 10% increase
    WHERE CURRENT OF update_cursor;
    
    FETCH NEXT FROM update_cursor INTO @ProductID, @Price;
END

CLOSE update_cursor;
DEALLOCATE update_cursor;
GO

-- Pattern 14: DELETE with WHERE CURRENT OF
DECLARE @OrderID INT;

DECLARE delete_cursor CURSOR FOR
    SELECT OrderID FROM dbo.Orders WHERE Status = 'Cancelled'
    FOR UPDATE;

OPEN delete_cursor;
FETCH NEXT FROM delete_cursor INTO @OrderID;

WHILE @@FETCH_STATUS = 0
BEGIN
    DELETE FROM dbo.Orders WHERE CURRENT OF delete_cursor;
    FETCH NEXT FROM delete_cursor INTO @OrderID;
END

CLOSE delete_cursor;
DEALLOCATE delete_cursor;
GO

-- Pattern 15: Multiple option combinations
DECLARE combo_cursor CURSOR 
    LOCAL STATIC FORWARD_ONLY READ_ONLY 
    FOR SELECT CustomerID FROM dbo.Customers;
    
OPEN combo_cursor;
CLOSE combo_cursor;
DEALLOCATE combo_cursor;
GO

-- Pattern 16: Cursor variable
DECLARE @MyCursor CURSOR;

SET @MyCursor = CURSOR LOCAL FAST_FORWARD FOR
    SELECT ProductID FROM dbo.Products;

OPEN @MyCursor;

DECLARE @ID INT;
FETCH NEXT FROM @MyCursor INTO @ID;
PRINT @ID;

CLOSE @MyCursor;
DEALLOCATE @MyCursor;
GO

-- Pattern 17: Cursor with parameters (using variable in query)
DECLARE @MinPrice DECIMAL(10,2) = 100.00;
DECLARE @ProductID INT, @ProductName VARCHAR(100);

DECLARE param_cursor CURSOR FOR
    SELECT ProductID, ProductName 
    FROM dbo.Products 
    WHERE Price >= @MinPrice;

OPEN param_cursor;
FETCH NEXT FROM param_cursor INTO @ProductID, @ProductName;

WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT @ProductName;
    FETCH NEXT FROM param_cursor INTO @ProductID, @ProductName;
END

CLOSE param_cursor;
DEALLOCATE param_cursor;
GO

-- Pattern 18: Nested cursors
DECLARE @CustomerID INT, @CustomerName VARCHAR(100);
DECLARE @OrderID INT, @OrderDate DATE;

DECLARE outer_cursor CURSOR FOR
    SELECT CustomerID, CustomerName FROM dbo.Customers;

OPEN outer_cursor;
FETCH NEXT FROM outer_cursor INTO @CustomerID, @CustomerName;

WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT 'Customer: ' + @CustomerName;
    
    DECLARE inner_cursor CURSOR FOR
        SELECT OrderID, OrderDate FROM dbo.Orders WHERE CustomerID = @CustomerID;
    
    OPEN inner_cursor;
    FETCH NEXT FROM inner_cursor INTO @OrderID, @OrderDate;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        PRINT '  Order: ' + CAST(@OrderID AS VARCHAR) + ' - ' + CAST(@OrderDate AS VARCHAR);
        FETCH NEXT FROM inner_cursor INTO @OrderID, @OrderDate;
    END
    
    CLOSE inner_cursor;
    DEALLOCATE inner_cursor;
    
    FETCH NEXT FROM outer_cursor INTO @CustomerID, @CustomerName;
END

CLOSE outer_cursor;
DEALLOCATE outer_cursor;
GO

-- Pattern 19: Checking cursor status
DECLARE test_cursor CURSOR FOR SELECT 1;

SELECT CURSOR_STATUS('global', 'test_cursor') AS Status;  -- -3 = doesn't exist

OPEN test_cursor;
SELECT CURSOR_STATUS('global', 'test_cursor') AS Status;  -- 1 = open with rows

CLOSE test_cursor;
SELECT CURSOR_STATUS('global', 'test_cursor') AS Status;  -- -1 = closed

DEALLOCATE test_cursor;
SELECT CURSOR_STATUS('global', 'test_cursor') AS Status;  -- -3 = doesn't exist
GO

-- Pattern 20: @@CURSOR_ROWS
DECLARE count_cursor CURSOR STATIC FOR
    SELECT CustomerID FROM dbo.Customers;

OPEN count_cursor;
SELECT @@CURSOR_ROWS AS TotalRows;  -- Returns row count for STATIC cursor

CLOSE count_cursor;
DEALLOCATE count_cursor;
GO
