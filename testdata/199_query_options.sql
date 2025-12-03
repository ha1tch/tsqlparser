-- Sample 199: Query Options and Hints
-- Category: Syntax Coverage / Query Optimization
-- Complexity: Advanced
-- Purpose: Parser testing - OPTION clause and query hints
-- Features: Query hints, table hints, join hints

-- Pattern 1: OPTION with RECOMPILE
SELECT * FROM dbo.Customers
WHERE CustomerID = @CustomerID
OPTION (RECOMPILE);
GO

-- Pattern 2: OPTION with OPTIMIZE FOR
DECLARE @Status VARCHAR(20) = 'Active';

SELECT * FROM dbo.Orders
WHERE Status = @Status
OPTION (OPTIMIZE FOR (@Status = 'Pending'));
GO

-- Pattern 3: OPTIMIZE FOR UNKNOWN
SELECT * FROM dbo.Orders
WHERE CustomerID = @CustomerID
OPTION (OPTIMIZE FOR UNKNOWN);
GO

-- Pattern 4: MAXDOP hint
SELECT * FROM dbo.LargeTable
WHERE ProcessedDate IS NULL
OPTION (MAXDOP 4);
GO

-- Pattern 5: MAXRECURSION
WITH Numbers AS (
    SELECT 1 AS N
    UNION ALL
    SELECT N + 1 FROM Numbers WHERE N < 500
)
SELECT * FROM Numbers
OPTION (MAXRECURSION 500);
GO

-- Pattern 6: HASH GROUP / ORDER GROUP
SELECT CategoryID, COUNT(*)
FROM dbo.Products
GROUP BY CategoryID
OPTION (HASH GROUP);

SELECT CategoryID, COUNT(*)
FROM dbo.Products
GROUP BY CategoryID
OPTION (ORDER GROUP);
GO

-- Pattern 7: LOOP JOIN / MERGE JOIN / HASH JOIN
SELECT c.CustomerName, o.OrderID
FROM dbo.Customers c
INNER JOIN dbo.Orders o ON c.CustomerID = o.CustomerID
OPTION (LOOP JOIN);

SELECT c.CustomerName, o.OrderID
FROM dbo.Customers c
INNER JOIN dbo.Orders o ON c.CustomerID = o.CustomerID
OPTION (MERGE JOIN);

SELECT c.CustomerName, o.OrderID
FROM dbo.Customers c
INNER JOIN dbo.Orders o ON c.CustomerID = o.CustomerID
OPTION (HASH JOIN);
GO

-- Pattern 8: FORCE ORDER
SELECT c.CustomerName, o.OrderID, p.ProductName
FROM dbo.Customers c
INNER JOIN dbo.Orders o ON c.CustomerID = o.CustomerID
INNER JOIN dbo.OrderDetails od ON o.OrderID = od.OrderID
INNER JOIN dbo.Products p ON od.ProductID = p.ProductID
OPTION (FORCE ORDER);
GO

-- Pattern 9: USE PLAN
SELECT * FROM dbo.Customers
WHERE Country = 'USA'
OPTION (USE PLAN N'<ShowPlanXML>...</ShowPlanXML>');
GO

-- Pattern 10: QUERYTRACEON
SELECT * FROM dbo.Orders
WHERE OrderDate > '2024-01-01'
OPTION (QUERYTRACEON 4199);  -- Enable query optimizer fixes
GO

-- Pattern 11: Multiple options
SELECT * FROM dbo.LargeTable
WHERE Status = 'Active'
OPTION (RECOMPILE, MAXDOP 2);
GO

-- Pattern 12: FAST hint
SELECT * FROM dbo.Orders
ORDER BY OrderDate DESC
OPTION (FAST 100);  -- Optimize for first 100 rows
GO

-- Pattern 13: ROBUST PLAN
SELECT * FROM dbo.DynamicData
WHERE DataValue > 100
OPTION (ROBUST PLAN);
GO

-- Pattern 14: Table hint with WITH
SELECT * FROM dbo.Customers WITH (NOLOCK);
SELECT * FROM dbo.Customers WITH (READUNCOMMITTED);
SELECT * FROM dbo.Customers WITH (READCOMMITTED);
SELECT * FROM dbo.Customers WITH (REPEATABLEREAD);
SELECT * FROM dbo.Customers WITH (SERIALIZABLE);
GO

-- Pattern 15: Table hint without WITH (legacy)
SELECT * FROM dbo.Customers (NOLOCK);
SELECT * FROM dbo.Customers (TABLOCK);
GO

-- Pattern 16: Multiple table hints
SELECT * FROM dbo.Customers WITH (NOLOCK, INDEX(IX_CustomerName));
SELECT * FROM dbo.LargeTable WITH (TABLOCK, HOLDLOCK);
GO

-- Pattern 17: Lock hints
SELECT * FROM dbo.Orders WITH (ROWLOCK);
SELECT * FROM dbo.Orders WITH (PAGLOCK);
SELECT * FROM dbo.Orders WITH (TABLOCK);
SELECT * FROM dbo.Orders WITH (TABLOCKX);
SELECT * FROM dbo.Orders WITH (UPDLOCK);
SELECT * FROM dbo.Orders WITH (XLOCK);
SELECT * FROM dbo.Orders WITH (HOLDLOCK);
SELECT * FROM dbo.Orders WITH (NOWAIT);
SELECT * FROM dbo.Orders WITH (READPAST);
GO

-- Pattern 18: INDEX hint
SELECT * FROM dbo.Customers WITH (INDEX(IX_CustomerName));
SELECT * FROM dbo.Customers WITH (INDEX(1));  -- By index ID
SELECT * FROM dbo.Customers WITH (INDEX(IX_Name, IX_Email));  -- Multiple indexes
SELECT * FROM dbo.Customers WITH (INDEX = IX_CustomerName);  -- Alternative syntax
GO

-- Pattern 19: FORCESEEK and FORCESCAN
SELECT * FROM dbo.Customers WITH (FORCESEEK);
SELECT * FROM dbo.Customers WITH (FORCESCAN);
SELECT * FROM dbo.Customers WITH (FORCESEEK(IX_CustomerName(CustomerName)));
GO

-- Pattern 20: Join hints in FROM
SELECT c.CustomerName, o.OrderID
FROM dbo.Customers c
INNER LOOP JOIN dbo.Orders o ON c.CustomerID = o.CustomerID;

SELECT c.CustomerName, o.OrderID
FROM dbo.Customers c
INNER MERGE JOIN dbo.Orders o ON c.CustomerID = o.CustomerID;

SELECT c.CustomerName, o.OrderID
FROM dbo.Customers c
INNER HASH JOIN dbo.Orders o ON c.CustomerID = o.CustomerID;

SELECT c.CustomerName, o.OrderID
FROM dbo.Customers c
LEFT REMOTE JOIN dbo.Orders o ON c.CustomerID = o.CustomerID;
GO

-- Pattern 21: KEEPIDENTITY / KEEPDEFAULTS
INSERT INTO dbo.TargetTable WITH (KEEPIDENTITY)
SELECT * FROM dbo.SourceTable;

INSERT INTO dbo.TargetTable WITH (KEEPDEFAULTS)
SELECT Col1, Col2 FROM dbo.SourceTable;
GO

-- Pattern 22: SNAPSHOT hint
SELECT * FROM dbo.Customers WITH (SNAPSHOT);
GO

-- Pattern 23: KEEPFIXED PLAN
SELECT * FROM dbo.DynamicTable
WHERE Column1 = @Value
OPTION (KEEPFIXED PLAN);
GO

-- Pattern 24: EXPAND VIEWS
SELECT * FROM dbo.CustomerOrdersView
OPTION (EXPAND VIEWS);
GO

-- Pattern 25: IGNORE_NONCLUSTERED_COLUMNSTORE_INDEX
SELECT * FROM dbo.TableWithCCI
WHERE Column1 = 'Value'
OPTION (IGNORE_NONCLUSTERED_COLUMNSTORE_INDEX);
GO
