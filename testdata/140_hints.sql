-- Sample 140: Table Hints and Query Hints Comprehensive
-- Category: Syntax Edge Cases / Performance
-- Complexity: Advanced
-- Purpose: Parser testing - all hint variations
-- Features: Table hints, query hints, join hints, locking hints

-- Pattern 1: Basic locking hints
SELECT * FROM dbo.Orders WITH (NOLOCK);
SELECT * FROM dbo.Orders WITH (READUNCOMMITTED);
SELECT * FROM dbo.Orders WITH (READCOMMITTED);
SELECT * FROM dbo.Orders WITH (REPEATABLEREAD);
SELECT * FROM dbo.Orders WITH (SERIALIZABLE);
SELECT * FROM dbo.Orders WITH (READCOMMITTEDLOCK);
GO

-- Pattern 2: Lock granularity hints
SELECT * FROM dbo.Orders WITH (ROWLOCK);
SELECT * FROM dbo.Orders WITH (PAGLOCK);
SELECT * FROM dbo.Orders WITH (TABLOCK);
SELECT * FROM dbo.Orders WITH (TABLOCKX);
GO

-- Pattern 3: Lock behavior hints
SELECT * FROM dbo.Orders WITH (UPDLOCK);
SELECT * FROM dbo.Orders WITH (XLOCK);
SELECT * FROM dbo.Orders WITH (HOLDLOCK);
SELECT * FROM dbo.Orders WITH (NOWAIT);
SELECT * FROM dbo.Orders WITH (READPAST);
GO

-- Pattern 4: Combined locking hints
SELECT * FROM dbo.Orders WITH (NOLOCK, INDEX(IX_Orders_CustomerID));
SELECT * FROM dbo.Orders WITH (ROWLOCK, UPDLOCK);
SELECT * FROM dbo.Orders WITH (TABLOCK, HOLDLOCK);
SELECT * FROM dbo.Orders WITH (ROWLOCK, XLOCK, HOLDLOCK);
SELECT * FROM dbo.Orders WITH (READPAST, ROWLOCK);
GO

-- Pattern 5: Index hints
SELECT * FROM dbo.Orders WITH (INDEX(PK_Orders));
SELECT * FROM dbo.Orders WITH (INDEX(IX_Orders_CustomerID));
SELECT * FROM dbo.Orders WITH (INDEX(0));  -- Heap or clustered
SELECT * FROM dbo.Orders WITH (INDEX(1));  -- Clustered index
SELECT * FROM dbo.Orders WITH (INDEX(PK_Orders, IX_Orders_Date));  -- Multiple indexes
GO

-- Pattern 6: FORCESEEK and FORCESCAN hints
SELECT * FROM dbo.Orders WITH (FORCESEEK);
SELECT * FROM dbo.Orders WITH (FORCESCAN);
SELECT * FROM dbo.Orders WITH (FORCESEEK, INDEX(IX_Orders_CustomerID));
SELECT * FROM dbo.Orders WITH (FORCESEEK(IX_Orders_CustomerID(CustomerID)));
GO

-- Pattern 7: Spatial index hints
SELECT * FROM dbo.Locations WITH (INDEX(SPATIAL_Locations));
GO

-- Pattern 8: Join hints in FROM clause
SELECT *
FROM dbo.Orders o
INNER LOOP JOIN dbo.Customers c ON o.CustomerID = c.CustomerID;

SELECT *
FROM dbo.Orders o
INNER HASH JOIN dbo.Customers c ON o.CustomerID = c.CustomerID;

SELECT *
FROM dbo.Orders o
INNER MERGE JOIN dbo.Customers c ON o.CustomerID = c.CustomerID;

SELECT *
FROM dbo.Orders o
LEFT LOOP JOIN dbo.Customers c ON o.CustomerID = c.CustomerID;
GO

-- Pattern 9: REMOTE join hint (for distributed queries)
SELECT *
FROM dbo.LocalOrders o
INNER REMOTE JOIN LinkedServer.Database.dbo.RemoteCustomers c ON o.CustomerID = c.CustomerID;
GO

-- Pattern 10: Query hints with OPTION clause
SELECT * FROM dbo.Orders
OPTION (HASH JOIN);

SELECT * FROM dbo.Orders
OPTION (MERGE JOIN);

SELECT * FROM dbo.Orders
OPTION (LOOP JOIN);

SELECT * FROM dbo.Orders
OPTION (CONCAT UNION);

SELECT * FROM dbo.Orders
OPTION (HASH UNION);

SELECT * FROM dbo.Orders
OPTION (MERGE UNION);
GO

-- Pattern 11: MAXDOP hint
SELECT * FROM dbo.Orders
OPTION (MAXDOP 1);

SELECT * FROM dbo.Orders
OPTION (MAXDOP 4);

SELECT * FROM dbo.Orders
OPTION (MAXDOP 0);  -- Use all processors
GO

-- Pattern 12: RECOMPILE hint
SELECT * FROM dbo.Orders WHERE CustomerID = @CustomerID
OPTION (RECOMPILE);

EXEC dbo.GetOrders @CustomerID = 1 WITH RECOMPILE;
GO

-- Pattern 13: OPTIMIZE FOR hints
DECLARE @CustomerID INT = 1;
SELECT * FROM dbo.Orders WHERE CustomerID = @CustomerID
OPTION (OPTIMIZE FOR (@CustomerID = 100));

SELECT * FROM dbo.Orders WHERE CustomerID = @CustomerID
OPTION (OPTIMIZE FOR (@CustomerID UNKNOWN));

SELECT * FROM dbo.Orders WHERE CustomerID = @CustomerID AND Status = @Status
OPTION (OPTIMIZE FOR (@CustomerID = 100, @Status = 'Active'));
GO

-- Pattern 14: FAST hint
SELECT * FROM dbo.Orders
OPTION (FAST 100);  -- Optimize for first 100 rows

SELECT * FROM dbo.Orders
OPTION (FAST 1);  -- Optimize for first row
GO

-- Pattern 15: FORCE ORDER hint
SELECT *
FROM dbo.Orders o
INNER JOIN dbo.Customers c ON o.CustomerID = c.CustomerID
INNER JOIN dbo.OrderDetails od ON o.OrderID = od.OrderID
OPTION (FORCE ORDER);
GO

-- Pattern 16: KEEP PLAN and KEEPFIXED PLAN
SELECT * FROM dbo.Orders WHERE OrderDate > @StartDate
OPTION (KEEP PLAN);

SELECT * FROM dbo.Orders WHERE OrderDate > @StartDate
OPTION (KEEPFIXED PLAN);
GO

-- Pattern 17: EXPAND VIEWS hint
SELECT * FROM dbo.vw_OrderSummary
OPTION (EXPAND VIEWS);
GO

-- Pattern 18: ROBUST PLAN hint
SELECT * FROM dbo.Orders o
INNER JOIN dbo.Customers c ON o.CustomerID = c.CustomerID
OPTION (ROBUST PLAN);
GO

-- Pattern 19: USE PLAN hint
DECLARE @plan XML = N'<ShowPlanXML>...</ShowPlanXML>';
SELECT * FROM dbo.Orders
OPTION (USE PLAN @plan);

SELECT * FROM dbo.Orders
OPTION (USE PLAN N'<ShowPlanXML xmlns="http://schemas.microsoft.com/sqlserver/2004/07/showplan">...</ShowPlanXML>');
GO

-- Pattern 20: QUERYTRACEON hint
SELECT * FROM dbo.Orders
OPTION (QUERYTRACEON 4199);  -- Enable query optimizer fixes

SELECT * FROM dbo.Orders
OPTION (QUERYTRACEON 9481);  -- Use legacy cardinality estimator

SELECT * FROM dbo.Orders
OPTION (QUERYTRACEON 2312);  -- Use new cardinality estimator
GO

-- Pattern 21: MAX_GRANT_PERCENT and MIN_GRANT_PERCENT
SELECT * FROM dbo.Orders
OPTION (MAX_GRANT_PERCENT = 25);

SELECT * FROM dbo.Orders
OPTION (MIN_GRANT_PERCENT = 10, MAX_GRANT_PERCENT = 50);
GO

-- Pattern 22: LABEL hint (for tracking)
SELECT * FROM dbo.Orders
OPTION (LABEL = 'OrderQuery_Report1');
GO

-- Pattern 23: NO_PERFORMANCE_SPOOL hint
SELECT * FROM dbo.Orders o
WHERE EXISTS (SELECT 1 FROM dbo.OrderDetails od WHERE od.OrderID = o.OrderID)
OPTION (NO_PERFORMANCE_SPOOL);
GO

-- Pattern 24: DISABLE_OPTIMIZED_NESTED_LOOP
SELECT *
FROM dbo.Orders o
INNER JOIN dbo.Customers c ON o.CustomerID = c.CustomerID
OPTION (DISABLE_OPTIMIZED_NESTED_LOOP);
GO

-- Pattern 25: Multiple query hints combined
SELECT *
FROM dbo.Orders o WITH (NOLOCK, INDEX(IX_Orders_Date))
INNER JOIN dbo.Customers c WITH (NOLOCK) ON o.CustomerID = c.CustomerID
WHERE o.OrderDate > '2024-01-01'
OPTION (MAXDOP 4, RECOMPILE, FORCE ORDER);
GO

-- Pattern 26: Table hints with old syntax (without WITH)
SELECT * FROM dbo.Orders (NOLOCK);
SELECT * FROM dbo.Orders (INDEX = 1);
SELECT * FROM dbo.Orders (TABLOCK, HOLDLOCK);
GO

-- Pattern 27: SNAPSHOT hint
SELECT * FROM dbo.Orders WITH (SNAPSHOT);
GO

-- Pattern 28: Table hint in UPDATE/DELETE
UPDATE dbo.Orders WITH (ROWLOCK)
SET Status = 'Updated'
WHERE OrderID = 1;

DELETE FROM dbo.Orders WITH (ROWLOCK, READPAST)
WHERE Status = 'Cancelled';
GO

-- Pattern 29: IGNORE_NONCLUSTERED_COLUMNSTORE_INDEX
SELECT * FROM dbo.Orders
OPTION (IGNORE_NONCLUSTERED_COLUMNSTORE_INDEX);
GO

-- Pattern 30: Table sample hint
SELECT * FROM dbo.Orders TABLESAMPLE (10 PERCENT);
SELECT * FROM dbo.Orders TABLESAMPLE (1000 ROWS);
SELECT * FROM dbo.Orders TABLESAMPLE SYSTEM (10 PERCENT);
SELECT * FROM dbo.Orders TABLESAMPLE (10 PERCENT) REPEATABLE (123);
GO
